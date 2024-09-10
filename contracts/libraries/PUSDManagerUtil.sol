// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "./SpreadUtil.sol";
import "./PositionUtil.sol";
import "./LiquidityUtil.sol";
import "./UnsafeMath.sol";
import "./SpreadUtil.sol";
import "../core/PUSD.sol";
import "../core/interfaces/IMarketManager.sol";
import {LONG, SHORT} from "../types/Side.sol";
import "@openzeppelin/contracts/utils/Create2.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

library PUSDManagerUtil {
    using SafeCast for *;
    using SafeERC20 for IERC20;
    using UnsafeMath for *;

    bytes32 internal constant PUSD_SALT = keccak256("Pure USD");
    bytes32 internal constant PUSD_INIT_CODE_HASH = 0x833a3129a7c49096ba2bc346ab64e2bbec674f4181bf8e6dedfa83aea7fb0fec;

    struct MintParam {
        IERC20 market;
        bool exactIn;
        uint96 amount;
        IPUSDManagerCallback callback;
        uint64 indexPrice;
        address receiver;
    }

    struct BurnParam {
        IERC20 market;
        bool exactIn;
        uint96 amount;
        IPUSDManagerCallback callback;
        uint64 indexPrice;
        address receiver;
    }

    struct LiquidityBufferModuleBurnParam {
        IERC20 market;
        address account;
        uint96 sizeDelta;
        uint64 indexPrice;
    }

    struct CalcBurnPUSDInputAmountParam {
        uint256 spreadX96;
        uint64 entryPrice;
        uint64 indexPrice;
        uint24 tradingFeeRate;
        uint96 outputAmount;
    }

    function deployPUSD() public returns (PUSD pusd) {
        pusd = new PUSD{salt: PUSD_SALT}();
    }

    function computePUSDAddress() internal view returns (address) {
        return computePUSDAddress(address(this));
    }

    function computePUSDAddress(address _deployer) internal pure returns (address) {
        return Create2.computeAddress(PUSD_SALT, PUSD_INIT_CODE_HASH, _deployer);
    }

    function mint(
        IMarketManager.State storage _state,
        IConfigurable.MarketConfig storage _cfg,
        MintParam memory _param,
        bytes calldata _data
    ) internal returns (uint96 payAmount, uint64 receiveAmount) {
        IMarketManager.PackedState storage packedState = _state.packedState;
        (int256 spreadFactorAfterX96, uint256 spreadX96) = SpreadUtil.refreshSpread(
            _cfg,
            SpreadUtil.CalcSpreadParam({
                side: SHORT,
                sizeDelta: 0,
                spreadFactorBeforeX96: packedState.spreadFactorX96,
                lastTradingTimestamp: packedState.lastTradingTimestamp
            })
        );
        uint96 sizeDelta;
        if (_param.exactIn) {
            // size = amount / (1 + spread + tradingFeeRate)
            unchecked {
                uint256 numeratorX96 = (uint256(_param.amount) << 96) * Constants.BASIS_POINTS_DIVISOR;
                uint256 denominatorX96 = (uint256(Constants.BASIS_POINTS_DIVISOR) + _cfg.tradingFeeRate) << 96;
                denominatorX96 += spreadX96 * Constants.BASIS_POINTS_DIVISOR;
                sizeDelta = (numeratorX96 / denominatorX96).toUint96();
            }
            payAmount = _param.amount;
            receiveAmount = PositionUtil.calcDecimals6TokenValue(
                sizeDelta,
                _param.indexPrice,
                _cfg.decimals,
                Math.Rounding.Down
            );
        } else {
            receiveAmount = _param.amount.toUint64();
            sizeDelta = PositionUtil.calcMarketTokenValue(_param.amount, _param.indexPrice, _cfg.decimals);
        }
        if (sizeDelta == 0) revert IMarketErrors.InvalidSize();

        IPUSDManager.GlobalPUSDPosition storage position = _state.globalPUSDPosition;
        uint64 totalSupplyAfter = _validateStableCoinSupplyCap(
            _cfg.stableCoinSupplyCap,
            position.totalSupply,
            receiveAmount
        );

        (uint128 lpNetSize, uint128 lpLiquidity) = (packedState.lpNetSize, packedState.lpLiquidity);
        if (sizeDelta > lpNetSize) revert IMarketErrors.InsufficientSizeToDecrease(sizeDelta, lpNetSize);

        uint128 sizeBefore = position.size;
        uint128 sizeAfter;
        unchecked {
            // Because the short position is always less than or equal to the long position,
            // there will be no overflow here.
            sizeAfter = sizeBefore + sizeDelta;
            uint256 maxShortSize = (uint256(_cfg.maxShortSizeRate) * lpLiquidity) / Constants.BASIS_POINTS_DIVISOR;
            if (sizeAfter > maxShortSize) revert IMarketErrors.MaxShortSizeExceeded(sizeAfter, maxShortSize);

            uint256 minMintingSizeCap = (uint256(_cfg.minMintingRate) * lpLiquidity) / Constants.BASIS_POINTS_DIVISOR;
            if (lpNetSize - sizeDelta < minMintingSizeCap)
                revert IMarketErrors.MinMintingSizeCapNotMet(lpNetSize, sizeDelta, uint128(minMintingSizeCap));
        }

        // settle liquidity
        LiquidityUtil.settlePosition(_state, _param.market, SHORT, _param.indexPrice, sizeDelta);

        uint96 tradingFee = PositionUtil.distributeTradingFee(
            _state,
            PositionUtil.DistributeFeeParam({
                market: _param.market,
                size: sizeDelta,
                entryPrice: _param.indexPrice,
                indexPrice: _param.indexPrice,
                rounding: Math.Rounding.Down,
                tradingFeeRate: _cfg.tradingFeeRate,
                protocolFeeRate: _cfg.protocolFeeRate
            })
        );

        uint96 spread = _param.exactIn
            ? _param.amount.subU96(sizeDelta).subU96(tradingFee)
            : SpreadUtil.calcSpreadAmount(spreadX96, sizeDelta, Math.Rounding.Up);
        PositionUtil.distributeSpread(_state, _param.market, spread);

        if (!_param.exactIn) payAmount = sizeDelta + tradingFee + spread;

        // mint PUSD
        IPUSD(computePUSDAddress()).mint(_param.receiver, receiveAmount);
        // execute callback
        uint256 balanceBefore = _param.market.balanceOf(address(this));
        _param.callback.PUSDManagerCallback(_param.market, payAmount, receiveAmount, _data);
        uint96 actualPayAmount = (_param.market.balanceOf(address(this)) - balanceBefore).toUint96();
        if (actualPayAmount < payAmount) revert IMarketErrors.TooLittlePayAmount(actualPayAmount, payAmount);
        payAmount = actualPayAmount;
        _state.tokenBalance += payAmount;

        uint64 entryPriceAfter = PositionUtil.calcNextEntryPrice(
            SHORT,
            sizeBefore,
            position.entryPrice,
            sizeDelta,
            _param.indexPrice
        );

        position.totalSupply = totalSupplyAfter;
        position.size = sizeAfter;
        position.entryPrice = entryPriceAfter;

        spreadFactorAfterX96 = SpreadUtil.calcSpreadFactorAfterX96(spreadFactorAfterX96, SHORT, sizeDelta);
        _refreshSpreadFactor(packedState, _param.market, spreadFactorAfterX96);

        emit IPUSDManager.PUSDPositionIncreased(
            _param.market,
            _param.receiver,
            sizeDelta,
            _param.indexPrice,
            entryPriceAfter,
            payAmount,
            receiveAmount,
            tradingFee,
            spread
        );
    }

    function burn(
        IMarketManager.State storage _state,
        IConfigurable.MarketConfig storage _cfg,
        BurnParam memory _param,
        bytes calldata _data
    ) public returns (uint64 payAmount, uint96 receiveAmount) {
        IMarketManager.PackedState storage packedState = _state.packedState;
        (int256 spreadFactorAfterX96, uint256 spreadX96) = SpreadUtil.refreshSpread(
            _cfg,
            SpreadUtil.CalcSpreadParam({
                side: LONG,
                sizeDelta: 0,
                spreadFactorBeforeX96: packedState.spreadFactorX96,
                lastTradingTimestamp: packedState.lastTradingTimestamp
            })
        );

        IPUSDManager.GlobalPUSDPosition storage position = _state.globalPUSDPosition;
        IPUSDManager.GlobalPUSDPosition memory positionCache = position;
        uint96 sizeDelta;
        if (_param.exactIn) {
            if (_param.amount == 0 || _param.amount > positionCache.totalSupply)
                revert IMarketErrors.InvalidAmount(positionCache.totalSupply, _param.amount);

            unchecked {
                sizeDelta = ((uint256(_param.amount) * positionCache.size) / positionCache.totalSupply).toUint96();
            }
            payAmount = uint64(_param.amount);
        } else {
            sizeDelta = calcBurnPUSDSizeDelta(
                CalcBurnPUSDInputAmountParam({
                    spreadX96: spreadX96,
                    entryPrice: positionCache.entryPrice,
                    indexPrice: _param.indexPrice,
                    tradingFeeRate: _cfg.tradingFeeRate,
                    outputAmount: _param.amount
                })
            );
            if (sizeDelta > positionCache.size)
                revert IMarketErrors.InsufficientSizeToDecrease(sizeDelta, positionCache.size);

            receiveAmount = _param.amount;
        }

        validateDecreaseSize(packedState, _cfg.maxBurningRate, sizeDelta);

        // settle liquidity
        LiquidityUtil.settlePosition(_state, _param.market, LONG, _param.indexPrice, sizeDelta);

        uint96 tradingFee = PositionUtil.distributeTradingFee(
            _state,
            PositionUtil.DistributeFeeParam({
                market: _param.market,
                size: sizeDelta,
                entryPrice: positionCache.entryPrice,
                indexPrice: _param.indexPrice,
                rounding: Math.Rounding.Down,
                tradingFeeRate: _cfg.tradingFeeRate,
                protocolFeeRate: _cfg.protocolFeeRate
            })
        );

        uint96 spread = SpreadUtil.calcSpreadAmount(spreadX96, sizeDelta, Math.Rounding.Down);
        PositionUtil.distributeSpread(_state, _param.market, spread);

        (int256 tokenPnL, int184 scaledUSDPnL) = PositionUtil.calcUnrealizedPnL2(
            SHORT,
            sizeDelta,
            positionCache.entryPrice,
            _param.indexPrice
        );
        LiquidityUtil.reviseLiquidityPnL(_state, _param.market, _param.indexPrice, scaledUSDPnL);

        if (_param.exactIn) {
            unchecked {
                int256 receiveAmountInt = int256(uint256(sizeDelta)) + tokenPnL;
                receiveAmountInt -= int256(uint256(tradingFee) + spread);
                if (receiveAmountInt < 0) revert IMarketErrors.NegativeReceiveAmount(receiveAmountInt);
                receiveAmount = uint256(receiveAmountInt).toUint96();
            }
        } else {
            // the amount of PUSD to burn
            payAmount = PositionUtil.calcDecimals6TokenValue(
                sizeDelta,
                _param.indexPrice,
                _cfg.decimals,
                Math.Rounding.Up
            );
            if (payAmount > positionCache.totalSupply)
                revert IMarketErrors.InvalidAmount(positionCache.totalSupply, payAmount);
        }

        // First pay the market token
        _state.tokenBalance -= receiveAmount;
        _param.market.safeTransfer(_param.receiver, receiveAmount);

        // Then execute the callback
        IPUSD usd = IPUSD(computePUSDAddress());
        uint256 balanceBefore = usd.balanceOf(address(this));
        _param.callback.PUSDManagerCallback(usd, payAmount, receiveAmount, _data);
        uint96 actualPayAmount = (usd.balanceOf(address(this)) - balanceBefore).toUint96();
        if (actualPayAmount != payAmount) revert IMarketErrors.UnexpectedPayAmount(payAmount, actualPayAmount);
        usd.burn(payAmount);

        // never underflow because of the validation above
        unchecked {
            position.size = positionCache.size - sizeDelta;
            position.totalSupply = positionCache.totalSupply - payAmount;
        }

        spreadFactorAfterX96 = SpreadUtil.calcSpreadFactorAfterX96(spreadFactorAfterX96, LONG, sizeDelta);
        _refreshSpreadFactor(packedState, _param.market, spreadFactorAfterX96);

        emit IPUSDManager.PUSDPositionDecreased(
            _param.market,
            _param.receiver,
            sizeDelta,
            _param.indexPrice,
            payAmount,
            receiveAmount,
            tokenPnL,
            tradingFee,
            spread
        );
    }

    function liquidityBufferModuleBurn(
        IMarketManager.State storage _state,
        IConfigurable.MarketConfig storage _cfg,
        LiquidityBufferModuleBurnParam memory _param
    ) internal {
        // settle liquidity
        LiquidityUtil.settlePosition(_state, _param.market, LONG, _param.indexPrice, _param.sizeDelta);

        IPUSDManager.GlobalPUSDPosition storage position = _state.globalPUSDPosition;
        IPUSDManager.GlobalPUSDPosition memory positionCache = position;
        uint96 tradingFee = PositionUtil.distributeTradingFee(
            _state,
            PositionUtil.DistributeFeeParam({
                market: _param.market,
                size: _param.sizeDelta,
                entryPrice: positionCache.entryPrice,
                indexPrice: _param.indexPrice,
                rounding: Math.Rounding.Down,
                tradingFeeRate: _cfg.tradingFeeRate,
                protocolFeeRate: _cfg.protocolFeeRate
            })
        );

        (int256 realizedPnL, int184 scaledUSDPnL) = PositionUtil.calcUnrealizedPnL2(
            SHORT,
            _param.sizeDelta,
            positionCache.entryPrice,
            _param.indexPrice
        );
        LiquidityUtil.reviseLiquidityPnL(_state, _param.market, _param.indexPrice, scaledUSDPnL);

        uint96 receiveAmount;
        uint64 pusdDebtDelta;
        unchecked {
            int256 receiveAmountInt = int256(uint256(_param.sizeDelta)) - int256(uint256(tradingFee)) + realizedPnL;
            if (receiveAmountInt < 0) revert IMarketErrors.NegativeReceiveAmount(receiveAmountInt);
            receiveAmount = uint256(receiveAmountInt).toUint96();

            pusdDebtDelta = uint64(
                Math.ceilDiv(uint256(_param.sizeDelta) * positionCache.totalSupply, positionCache.size)
            );

            position.size = positionCache.size - _param.sizeDelta;
            position.totalSupply = positionCache.totalSupply - pusdDebtDelta;
        }

        emit IPUSDManager.PUSDPositionDecreased(
            _param.market,
            address(this),
            _param.sizeDelta,
            _param.indexPrice,
            pusdDebtDelta,
            receiveAmount,
            realizedPnL,
            tradingFee,
            0
        );

        IMarketManager.LiquidityBufferModule storage module = _state.liquidityBufferModule;
        module.pusdDebt += pusdDebtDelta;
        module.tokenPayback += receiveAmount;
        emit IMarketManager.LiquidityBufferModuleDebtIncreased(
            _param.market,
            _param.account,
            pusdDebtDelta,
            receiveAmount
        );
    }

    function repayLiquidityBufferDebt(
        IMarketManager.State storage _state,
        IERC20 _market,
        address _account,
        address _receiver
    ) public returns (uint128 receiveAmount) {
        IMarketManager.LiquidityBufferModule storage module = _state.liquidityBufferModule;
        IMarketManager.LiquidityBufferModule memory moduleCache = module;

        IPUSD usd = IPUSD(computePUSDAddress());
        uint128 amount = usd.balanceOf(address(this)).toUint128();

        // if paid too much, only repay the debt.
        if (amount > moduleCache.pusdDebt) amount = moduleCache.pusdDebt;

        // avoid reentrancy attack
        // prettier-ignore
        unchecked { module.pusdDebt = moduleCache.pusdDebt - amount; }

        usd.burn(amount);

        unchecked {
            receiveAmount = uint128((uint256(moduleCache.tokenPayback) * amount) / moduleCache.pusdDebt);
            module.tokenPayback = moduleCache.tokenPayback - receiveAmount;
        }

        _state.tokenBalance -= receiveAmount;
        _market.safeTransfer(_receiver, receiveAmount);
        emit IMarketManager.LiquidityBufferModuleDebtRepaid(_market, _account, amount, receiveAmount);
    }

    function updatePSMCollateralCap(IPSM.CollateralState storage _state, IERC20 _collateral, uint120 _cap) public {
        address usd = computePUSDAddress();
        require(usd != address(0) && usd != address(_collateral), IPSM.InvalidCollateral());

        if (_state.decimals == 0) {
            uint8 decimals = IERC20Metadata(address(_collateral)).decimals();
            require(decimals <= 18, IPSM.InvalidCollateralDecimals(decimals));
            _state.decimals = decimals;
        }
        _state.cap = _cap;
        emit IPSM.PSMCollateralUpdated(_collateral, _cap);
    }

    function psmMint(
        IPSM.CollateralState storage _state,
        IERC20 _collateral,
        address _receiver
    ) public returns (uint64 receiveAmount) {
        uint128 balanceAfter = _collateral.balanceOf(address(this)).toUint128();
        if (balanceAfter > _state.cap) balanceAfter = _state.cap;

        uint96 payAmount = (balanceAfter - _state.balance).toUint96();
        _state.balance = balanceAfter;

        receiveAmount = PositionUtil.calcDecimals6TokenValue(
            payAmount,
            Constants.PRICE_1,
            _state.decimals,
            Math.Rounding.Down
        );
        IPUSD(computePUSDAddress()).mint(_receiver, receiveAmount);

        emit IPSM.PSMMinted(_collateral, _receiver, payAmount, receiveAmount);
    }

    function psmBurn(
        IPSM.CollateralState storage _state,
        IERC20 _collateral,
        address _receiver
    ) public returns (uint96 receiveAmount) {
        IPUSD usd = IPUSD(computePUSDAddress());
        uint64 payAmount = usd.balanceOf(address(this)).toUint64();
        usd.burn(payAmount);

        receiveAmount = PositionUtil.calcMarketTokenValue(payAmount, Constants.PRICE_1, _state.decimals);

        if (_state.balance < receiveAmount) revert IPSM.InsufficientPSMBalance(receiveAmount, _state.balance);
        // prettier-ignore
        unchecked { _state.balance -= receiveAmount; }

        _collateral.safeTransfer(_receiver, receiveAmount);

        emit IPSM.PSMBurned(_collateral, _receiver, payAmount, receiveAmount);
    }

    /// @notice Calculate the size delta of burning PUSD when output amount is specified
    function calcBurnPUSDSizeDelta(
        CalcBurnPUSDInputAmountParam memory _param
    ) internal pure returns (uint96 sizeDelta) {
        uint256 minuendX96;
        unchecked {
            uint256 numeratorX96 = uint256(Constants.BASIS_POINTS_DIVISOR - _param.tradingFeeRate) << 96;
            numeratorX96 *= _param.entryPrice;
            minuendX96 = numeratorX96 / (uint256(_param.indexPrice) * Constants.BASIS_POINTS_DIVISOR);
        }

        uint256 denominatorX96 = minuendX96 - _param.spreadX96;
        sizeDelta = Math.ceilDiv(uint256(_param.outputAmount) << 96, denominatorX96).toUint96();
    }

    function validateDecreaseSize(
        IMarketManager.PackedState storage _packedState,
        uint24 _maxBurningRate,
        uint128 _sizeDelta
    ) internal view {
        unchecked {
            (uint128 lpNetSize, uint128 lpLiquidity) = (_packedState.lpNetSize, _packedState.lpLiquidity);
            require(_sizeDelta > 0, IMarketErrors.InvalidSize());
            uint256 netSizeAfter = uint256(lpNetSize) + _sizeDelta;
            uint256 maxBurningSizeCap = (uint256(lpLiquidity) * _maxBurningRate) / Constants.BASIS_POINTS_DIVISOR;
            require(
                netSizeAfter <= maxBurningSizeCap,
                IMarketErrors.MaxBurningSizeCapExceeded(lpNetSize, _sizeDelta, maxBurningSizeCap)
            );
        }
    }

    function _refreshSpreadFactor(
        IMarketManager.PackedState storage _state,
        IERC20 _market,
        int256 _spreadFactorAfterX96
    ) private {
        _state.spreadFactorX96 = _spreadFactorAfterX96;
        _state.lastTradingTimestamp = uint64(block.timestamp); // overflow is desired
        emit IMarketManager.SpreadFactorChanged(_market, _spreadFactorAfterX96);
    }

    function _validateStableCoinSupplyCap(
        uint64 _stableCoinSupplyCap,
        uint64 _totalSupply,
        uint64 _amountDelta
    ) private pure returns (uint64 totalSupplyAfter) {
        unchecked {
            uint256 totalSupplyAfter_ = uint256(_totalSupply) + _amountDelta;
            if (totalSupplyAfter_ > _stableCoinSupplyCap)
                revert IMarketErrors.StableCoinSupplyCapExceeded(_stableCoinSupplyCap, _totalSupply, _amountDelta);
            totalSupplyAfter = uint64(totalSupplyAfter_); // there will be no overflow here
        }
    }
}
