// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "../misc/interfaces/IReader.sol";
import "../core/MarketManagerUpgradeable.sol";

library PositionReader {
    using SafeCast for *;
    using UnsafeMath for *;

    /// @dev This struct is introduced to solve the stack too deep error during contract compilation
    struct DecreasePositionRes {
        uint96 decreasePositionReceiveAmount;
        uint96 marginAfter;
    }

    function quoteBurnPUSDToIncreasePosition(
        IReader.ReaderState storage _readerState,
        IERC20 _market,
        address _account,
        uint64 _amountIn,
        uint64 _indexPrice,
        uint32 _leverage
    ) public returns (uint96 burnPUSDReceiveAmount, uint96 size, IMarketPosition.Position memory position) {
        IMarketManager marketManager = _readerState.marketManager;
        if (!marketManager.isEnabledMarket(_market)) revert IConfigurable.MarketNotEnabled(_market);

        IReader.MockState storage mockState = _readerState.mockState;
        IMarketManager.State storage state = mockState.state;
        mockState.marketConfig = marketManager.marketConfigs(_market);
        IConfigurable.MarketConfig storage marketConfig = mockState.marketConfig;

        state.packedState = marketManager.packedStates(_market);
        IPUSDManager.GlobalPUSDPosition memory pusdPosition = marketManager.globalPUSDPositions(_market);
        state.globalPUSDPosition = pusdPosition;
        state.tokenBalance = marketManager.tokenBalances(_market);
        (state.accumulateScaledUSDPnL, state.previousSettledPrice) = marketManager.reviseLiquidityPnLStates(_market);

        PUSD pusd = PUSDManagerUtil.deployPUSD();
        pusd.mint(address(this), pusdPosition.totalSupply - _amountIn); // for mock
        (, burnPUSDReceiveAmount) = PUSDManagerUtil.burn(
            state,
            marketConfig,
            PUSDManagerUtil.BurnParam({
                market: IERC20(address(this)), // for mock
                exactIn: true,
                amount: _amountIn,
                callback: IPUSDManagerCallback(address(this)), // for mock
                indexPrice: _indexPrice,
                receiver: address(this)
            }),
            bytes("")
        );

        mapping(address => IMarketPosition.Position) storage positions = state.longPositions;
        positions[address(this)] = marketManager.longPositions(_market, _account); // for mock

        IMarketManager.PackedState storage packedState = state.packedState;
        uint96 leverageSize = _mulLeverage(burnPUSDReceiveAmount, _leverage);
        uint96 spread = PositionUtil.refreshSpreadFactor(
            packedState,
            marketConfig,
            IERC20(address(this)), // for mock
            leverageSize,
            LONG
        );

        uint32 tradingFeeRate = PositionUtil.calcTradingFeeRate(
            marketConfig,
            packedState.lpLiquidity,
            packedState.lpNetSize + leverageSize
        );
        uint96 tradingFee;
        unchecked {
            tradingFee = Math
                .ceilDiv(uint256(leverageSize) * tradingFeeRate, Constants.BASIS_POINTS_DIVISOR)
                .toUint96();
            uint256 feeAmount = uint256(tradingFee) + spread;
            if (burnPUSDReceiveAmount <= feeAmount) revert IMarketErrors.InsufficientMargin();
            size = _mulLeverage(burnPUSDReceiveAmount - uint96(feeAmount), _leverage);
        }

        PositionUtil.increasePosition(
            state,
            marketConfig,
            PositionUtil.IncreasePositionParam({
                market: IERC20(address(this)), // for mock
                account: address(this),
                sizeDelta: size,
                marginDelta: burnPUSDReceiveAmount,
                minIndexPrice: _indexPrice,
                maxIndexPrice: _indexPrice
            })
        );

        position = positions[address(this)];

        delete positions[address(this)];
        delete _readerState.mockState;
    }

    function quoteDecreasePositionToMintPUSD(
        IReader.ReaderState storage _readerState,
        IERC20 _market,
        address _account,
        uint96 _size,
        uint64 _indexPrice
    ) public returns (uint96 decreasePositionReceiveAmount, uint64 mintPUSDTokenValue, uint96 marginAfter) {
        IMarketManager marketManager = _readerState.marketManager;
        if (!marketManager.isEnabledMarket(_market)) revert IConfigurable.MarketNotEnabled(_market);

        IReader.MockState storage mockState = _readerState.mockState;
        IMarketManager.State storage state = mockState.state;
        mockState.marketConfig = marketManager.marketConfigs(_market);
        IConfigurable.MarketConfig storage marketConfig = mockState.marketConfig;
        state.packedState = marketManager.packedStates(_market);
        IPUSDManager.GlobalPUSDPosition memory pusdPosition = marketManager.globalPUSDPositions(_market);
        state.globalPUSDPosition = pusdPosition;
        state.tokenBalance = marketManager.tokenBalances(_market);
        (state.accumulateScaledUSDPnL, state.previousSettledPrice) = marketManager.reviseLiquidityPnLStates(_market);

        // settle position
        IMarketPosition.Position memory position = marketManager.longPositions(_market, _account);
        if (position.size == 0) revert IMarketErrors.PositionNotFound(_account);

        if (position.size < _size) revert IMarketErrors.InsufficientSizeToDecrease(position.size, _size);

        mapping(address => IMarketPosition.Position) storage positions = state.longPositions;
        positions[address(this)] = position; // for mock

        DecreasePositionRes memory res = _decreasePosition(_readerState, position, _size, _indexPrice);

        PUSD pusd = PUSDManagerUtil.deployPUSD();
        pusd.mint(address(this), pusdPosition.totalSupply); // for mock
        if (res.decreasePositionReceiveAmount > 0) {
            (, mintPUSDTokenValue) = PUSDManagerUtil.mint(
                state,
                marketConfig,
                PUSDManagerUtil.MintParam({
                    market: IERC20(address(this)), // for mock
                    exactIn: true,
                    amount: res.decreasePositionReceiveAmount,
                    callback: IPUSDManagerCallback(address(this)), // for mock
                    indexPrice: _indexPrice,
                    receiver: address(this)
                }),
                msg.data // for mock
            );
        }

        (decreasePositionReceiveAmount, marginAfter) = (res.decreasePositionReceiveAmount, res.marginAfter);

        delete positions[address(this)];
        delete _readerState.mockState;
    }

    function quoteIncreasePositionBySize(
        IReader.ReaderState storage _readerState,
        IERC20 _market,
        address _account,
        uint96 _size,
        uint32 _leverage,
        uint64 _indexPrice
    ) public returns (uint96 payAmount, uint96 marginAfter, uint96 spread, uint96 tradingFee, uint64 liquidationPrice) {
        IMarketManager marketManager = _readerState.marketManager;
        if (!marketManager.isEnabledMarket(_market)) revert IConfigurable.MarketNotEnabled(_market);

        IReader.MockState storage mockState = _readerState.mockState;
        IMarketManager.State storage state = mockState.state;
        mockState.marketConfig = marketManager.marketConfigs(_market);
        IConfigurable.MarketConfig storage marketConfig = mockState.marketConfig;

        state.packedState = marketManager.packedStates(_market);
        IMarketManager.PackedState storage packedState = state.packedState;

        IMarketPosition.Position memory position = marketManager.longPositions(_market, _account);
        (uint256 sizeAfter, uint128 lpNetSizeAfter) = PositionUtil.validateIncreaseSize(
            marketConfig,
            packedState,
            position.size,
            _size
        );

        spread = PositionUtil.refreshSpreadFactor(
            packedState,
            marketConfig,
            IERC20(address(this)), // for mock
            _size,
            LONG
        );

        uint32 tradingFeeRate = PositionUtil.calcTradingFeeRate(marketConfig, packedState.lpLiquidity, lpNetSizeAfter);
        unchecked {
            tradingFee = Math.ceilDiv(uint256(_size) * tradingFeeRate, Constants.BASIS_POINTS_DIVISOR).toUint96();
        }

        uint256 fees = uint256(tradingFee) + spread;
        payAmount = (Math.mulDivUp(_size, Constants.BASIS_POINTS_DIVISOR, _leverage) + fees).toUint96();
        if (position.size == 0 && payAmount < marketConfig.minMarginPerPosition)
            payAmount = marketConfig.minMarginPerPosition;
        marginAfter = (uint256(position.margin) + payAmount - fees).toUint96();

        unchecked {
            uint64 maxLeverage = marketConfig.maxLeveragePerPosition;
            if (uint256(marginAfter) * maxLeverage < sizeAfter) {
                uint256 minMargin = Math.ceilDiv(sizeAfter, maxLeverage);
                payAmount = (minMargin + fees - position.margin).toUint96();
                marginAfter = uint96(minMargin);
            }
        }

        uint64 entryPriceAfter = PositionUtil.calcNextEntryPrice(
            LONG,
            position.size,
            position.entryPrice,
            _size,
            _indexPrice
        );

        position.margin = marginAfter;
        position.size = uint96(sizeAfter);
        position.entryPrice = entryPriceAfter;

        // calculate the liquidation price
        liquidationPrice = PositionUtil.calcLiquidationPrice(
            position,
            marketConfig.liquidationFeeRatePerPosition,
            marketConfig.tradingFeeRate,
            marketConfig.liquidationExecutionFee
        );

        delete _readerState.mockState;
    }

    function _decreasePosition(
        IReader.ReaderState storage _readerState,
        IMarketPosition.Position memory _position,
        uint96 _size,
        uint64 _indexPrice
    ) internal returns (DecreasePositionRes memory res) {
        PositionUtil.DecreasePositionParam memory decreasePosition = PositionUtil.DecreasePositionParam({
            market: IERC20(address(this)), // for mock
            account: address(this),
            marginDelta: 0,
            sizeDelta: _size,
            minIndexPrice: _indexPrice,
            maxIndexPrice: _indexPrice,
            receiver: address(this)
        });

        IMarketManager.State storage state = _readerState.mockState.state;
        IConfigurable.MarketConfig storage marketConfig = _readerState.mockState.marketConfig;
        if (_position.size == _size) {
            (, res.decreasePositionReceiveAmount) = PositionUtil.decreasePosition(
                state,
                marketConfig,
                decreasePosition
            );
        } else {
            uint96 spread = PositionUtil.refreshSpreadFactor(
                state.packedState,
                marketConfig,
                IERC20(address(this)), // for mock
                _size,
                SHORT
            );
            uint96 tradingFee = PositionUtil.calcTradingFee(
                PositionUtil.DistributeFeeParam({
                    market: IERC20(address(this)),
                    size: _size,
                    entryPrice: _indexPrice,
                    indexPrice: _indexPrice,
                    rounding: Math.Rounding.Up,
                    tradingFeeRate: marketConfig.tradingFeeRate,
                    protocolFeeRate: 0
                })
            );
            int256 realizedPnL = PositionUtil.calcUnrealizedPnL(LONG, _size, _position.entryPrice, _indexPrice);
            // calculate the margin required for the remaining position
            unchecked {
                int256 marginDelta = int256((uint256(_position.margin) * _size) / _position.size);
                int256 pnl = realizedPnL - int256(uint256(tradingFee) + spread);
                if (marginDelta < -pnl) revert IMarketErrors.InsufficientMargin();
                res.decreasePositionReceiveAmount = uint256(marginDelta + pnl).toUint96();
                res.marginAfter = _position.margin - uint256(marginDelta).toUint96();
            }

            decreasePosition.marginDelta = res.decreasePositionReceiveAmount;
            PositionUtil.decreasePosition(state, marketConfig, decreasePosition);
        }
    }

    function _mulLeverage(uint96 _amount, uint32 _leverage) private pure returns (uint96 size) {
        return Math.mulDiv(_amount, _leverage, Constants.BASIS_POINTS_DIVISOR).toUint96();
    }
}
