// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "./MarketUtil.sol";
import "./LiquidityUtil.sol";
import "./SpreadUtil.sol";
import "./UnsafeMath.sol";
import {LONG, SHORT} from "../types/Side.sol";
import "../core/interfaces/IPUSD.sol";
import "./PUSDManagerUtil.sol";

/// @notice Utility library for trader positions
library PositionUtil {
    using SafeCast for *;
    using UnsafeMath for *;

    struct IncreasePositionParam {
        IERC20 market;
        address account;
        uint96 marginDelta;
        uint96 sizeDelta;
        uint64 minIndexPrice;
        uint64 maxIndexPrice;
    }

    struct DecreasePositionParam {
        IERC20 market;
        address account;
        uint96 marginDelta;
        uint96 sizeDelta;
        uint64 minIndexPrice;
        uint64 maxIndexPrice;
        address receiver;
    }

    struct LiquidatePositionParam {
        IERC20 market;
        address account;
        uint64 minIndexPrice;
        uint64 maxIndexPrice;
        address feeReceiver;
    }

    struct MaintainMarginRateParam {
        int256 margin;
        uint96 size;
        uint64 entryPrice;
        uint64 decreaseIndexPrice;
        bool liquidatablePosition;
    }

    struct DistributeFeeParam {
        IERC20 market;
        uint96 size;
        uint64 entryPrice;
        uint64 indexPrice;
        Math.Rounding rounding;
        uint24 tradingFeeRate;
        uint24 protocolFeeRate;
    }

    function increasePosition(
        IMarketManager.State storage _state,
        IConfigurable.MarketConfig storage _cfg,
        IncreasePositionParam memory _param
    ) internal returns (uint96 spread) {
        IMarketManager.Position storage position = _state.longPositions[_param.account];
        IMarketManager.Position memory positionCache = position;
        if (positionCache.size == 0) {
            if (_param.sizeDelta == 0) revert IMarketErrors.PositionNotFound(_param.account);

            if (_param.marginDelta < _cfg.minMarginPerPosition) revert IMarketErrors.InsufficientMargin();
        }

        uint96 tradingFee;
        uint96 sizeAfter = positionCache.size;
        IMarketManager.PackedState storage packedState = _state.packedState;
        if (_param.sizeDelta > 0) {
            spread = refreshSpreadFactor(packedState, _cfg, _param.market, _param.sizeDelta, LONG);
            distributeSpread(_state, _param.market, spread);

            uint128 lpNetSizeAfter;
            (sizeAfter, lpNetSizeAfter) = validateIncreaseSize(_cfg, packedState, positionCache.size, _param.sizeDelta);
            packedState.longSize += _param.sizeDelta;

            // settle liquidity
            LiquidityUtil.settlePosition(packedState, _param.market, LONG, _param.maxIndexPrice, _param.sizeDelta);

            tradingFee = distributeTradingFee(
                _state,
                DistributeFeeParam({
                    market: _param.market,
                    size: _param.sizeDelta,
                    entryPrice: _param.maxIndexPrice,
                    indexPrice: _param.maxIndexPrice,
                    rounding: Math.Rounding.Up,
                    tradingFeeRate: calcTradingFeeRate(_cfg, packedState.lpLiquidity, lpNetSizeAfter),
                    protocolFeeRate: _cfg.protocolFeeRate
                })
            );
        }

        int256 marginAfter;
        unchecked {
            marginAfter = int256(uint256(positionCache.margin) + _param.marginDelta);
            marginAfter -= int256(uint256(tradingFee) + spread);
        }

        uint64 entryPriceAfter = calcNextEntryPrice(
            LONG,
            positionCache.size,
            positionCache.entryPrice,
            _param.sizeDelta,
            _param.maxIndexPrice
        );

        _validatePositionLiquidateMaintainMarginRate(
            _cfg,
            MaintainMarginRateParam({
                margin: marginAfter,
                size: sizeAfter,
                entryPrice: entryPriceAfter,
                decreaseIndexPrice: _param.minIndexPrice,
                liquidatablePosition: false
            })
        );
        uint96 marginAfterU96 = uint256(marginAfter).toUint96();

        if (_param.sizeDelta > 0) MarketUtil.validateLeverage(marginAfterU96, sizeAfter, _cfg.maxLeveragePerPosition);

        position.margin = marginAfterU96;
        if (_param.sizeDelta > 0) {
            position.size = sizeAfter;
            position.entryPrice = entryPriceAfter;
        }
        emit IMarketPosition.PositionIncreased(
            _param.market,
            _param.account,
            _param.marginDelta,
            marginAfterU96,
            _param.sizeDelta,
            _param.maxIndexPrice,
            entryPriceAfter,
            tradingFee,
            spread
        );
    }

    function decreasePosition(
        IMarketManager.State storage _state,
        IConfigurable.MarketConfig storage _cfg,
        DecreasePositionParam memory _param
    ) public returns (uint96 spread, uint96 adjustedMarginDelta) {
        IMarketManager.Position memory positionCache = _state.longPositions[_param.account];
        if (positionCache.size == 0) revert IMarketErrors.PositionNotFound(_param.account);

        uint96 tradingFee;
        uint96 sizeAfter = positionCache.size;
        int256 realizedPnL;
        IMarketManager.PackedState storage packedState = _state.packedState;
        if (_param.sizeDelta > 0) {
            if (positionCache.size < _param.sizeDelta)
                revert IMarketErrors.InsufficientSizeToDecrease(_param.sizeDelta, positionCache.size);

            spread = refreshSpreadFactor(packedState, _cfg, _param.market, _param.sizeDelta, SHORT);
            distributeSpread(_state, _param.market, spread);

            uint128 lpNetSize = packedState.lpNetSize;
            if (lpNetSize < _param.sizeDelta) {
                if (!_cfg.liquidityBufferModuleEnabled)
                    revert IMarketErrors.InsufficientSizeToDecrease(_param.sizeDelta, lpNetSize);

                PUSDManagerUtil.liquidityBufferModuleBurn(
                    _state,
                    _cfg,
                    packedState,
                    PUSDManagerUtil.LiquidityBufferModuleBurnParam({
                        market: _param.market,
                        account: _param.account,
                        sizeDelta: uint96(_param.sizeDelta.subU128(lpNetSize)),
                        indexPrice: _param.maxIndexPrice
                    })
                );
            }

            // never underflow because of the validation above
            unchecked {
                sizeAfter -= _param.sizeDelta;
                packedState.longSize -= _param.sizeDelta;
            }

            // If the position size becomes zero after the decrease, the marginDelta will be ignored
            if (sizeAfter == 0) _param.marginDelta = 0;

            // settle liquidity
            LiquidityUtil.settlePosition(packedState, _param.market, SHORT, _param.minIndexPrice, _param.sizeDelta);

            tradingFee = distributeTradingFee(
                _state,
                DistributeFeeParam({
                    market: _param.market,
                    size: _param.sizeDelta,
                    entryPrice: positionCache.entryPrice,
                    indexPrice: _param.minIndexPrice,
                    rounding: Math.Rounding.Up,
                    tradingFeeRate: _cfg.tradingFeeRate,
                    protocolFeeRate: _cfg.protocolFeeRate
                })
            );

            realizedPnL = calcUnrealizedPnL(LONG, _param.sizeDelta, positionCache.entryPrice, _param.minIndexPrice);
        }

        int256 marginAfter = int256(uint256(positionCache.margin));
        unchecked {
            marginAfter += realizedPnL - int256(uint256(tradingFee) + _param.marginDelta + spread);
            if (marginAfter < 0) revert IMarketErrors.InsufficientMargin();
        }

        uint96 marginAfterU96 = uint256(marginAfter).toUint96();
        if (sizeAfter > 0) {
            _validatePositionLiquidateMaintainMarginRate(
                _cfg,
                MaintainMarginRateParam({
                    margin: marginAfter,
                    size: sizeAfter,
                    entryPrice: positionCache.entryPrice,
                    decreaseIndexPrice: _param.minIndexPrice,
                    liquidatablePosition: false
                })
            );
            if (_param.marginDelta > 0)
                MarketUtil.validateLeverage(marginAfterU96, sizeAfter, _cfg.maxLeveragePerPosition);

            // Update position
            IMarketManager.Position storage position = _state.longPositions[_param.account];
            position.margin = marginAfterU96;
            if (_param.sizeDelta > 0) position.size = sizeAfter;
        } else {
            // Return all remaining margin if the position position size becomes zero after the decrease
            _param.marginDelta = marginAfterU96;
            marginAfterU96 = 0;

            // Delete position
            delete _state.longPositions[_param.account];
        }

        adjustedMarginDelta = _param.marginDelta;

        emit IMarketPosition.PositionDecreased(
            _param.market,
            _param.account,
            adjustedMarginDelta,
            marginAfterU96,
            _param.sizeDelta,
            _param.minIndexPrice,
            realizedPnL,
            tradingFee,
            spread,
            _param.receiver
        );
    }

    function liquidatePosition(
        IMarketManager.State storage _state,
        IConfigurable.MarketConfig storage _cfg,
        LiquidatePositionParam memory _param
    ) public returns (uint64 liquidationExecutionFee) {
        IMarketManager.Position memory positionCache = _state.longPositions[_param.account];
        if (positionCache.size == 0) revert IMarketErrors.PositionNotFound(_param.account);

        _validatePositionLiquidateMaintainMarginRate(
            _cfg,
            MaintainMarginRateParam({
                margin: int256(uint256(positionCache.margin)),
                size: positionCache.size,
                entryPrice: positionCache.entryPrice,
                decreaseIndexPrice: _param.minIndexPrice,
                liquidatablePosition: true
            })
        );

        IMarketManager.PackedState storage packedState = _state.packedState;
        uint128 lpNetSize = packedState.lpNetSize;
        if (lpNetSize < positionCache.size)
            PUSDManagerUtil.liquidityBufferModuleBurn(
                _state,
                _cfg,
                packedState,
                PUSDManagerUtil.LiquidityBufferModuleBurnParam({
                    market: _param.market,
                    account: _param.account,
                    sizeDelta: uint96(positionCache.size.subU128(lpNetSize)),
                    indexPrice: _param.maxIndexPrice
                })
            );

        liquidationExecutionFee = liquidatePosition(_state, _cfg, packedState, positionCache, _param);
    }

    function liquidatePosition(
        IMarketManager.State storage _state,
        IConfigurable.MarketConfig storage _cfg,
        IMarketManager.PackedState storage _packedState,
        IMarketManager.Position memory _positionCache,
        LiquidatePositionParam memory _param
    ) internal returns (uint64 liquidationExecutionFee) {
        liquidationExecutionFee = _cfg.liquidationExecutionFee;
        uint24 liquidationFeeRate = _cfg.liquidationFeeRatePerPosition;

        uint64 liquidationPrice = calcLiquidationPrice(
            _positionCache,
            liquidationFeeRate,
            _cfg.tradingFeeRate,
            liquidationExecutionFee
        );

        // settle liquidity
        LiquidityUtil.settlePosition(_packedState, _param.market, SHORT, liquidationPrice, _positionCache.size);

        uint96 liquidationFee = calcLiquidationFee(
            _positionCache.size,
            _positionCache.entryPrice,
            liquidationPrice,
            liquidationFeeRate
        );
        distributeLiquidationFee(_state, _param.market, liquidationFee);

        uint96 tradingFee = distributeTradingFee(
            _state,
            DistributeFeeParam({
                market: _param.market,
                size: _positionCache.size,
                entryPrice: _positionCache.entryPrice,
                indexPrice: liquidationPrice,
                rounding: Math.Rounding.Down,
                tradingFeeRate: _cfg.tradingFeeRate,
                protocolFeeRate: _cfg.protocolFeeRate
            })
        );

        _packedState.longSize = _packedState.longSize.subU128(_positionCache.size);

        delete _state.longPositions[_param.account];

        emit IMarketPosition.PositionLiquidated(
            _param.market,
            msg.sender,
            _param.account,
            _positionCache.size,
            _param.minIndexPrice,
            liquidationPrice,
            tradingFee,
            liquidationFee,
            liquidationExecutionFee,
            _param.feeReceiver
        );
    }

    /// @notice Calculate the liquidation fee of a position
    /// @param _size The size of the position
    /// @param _entryPrice The entry price of the position
    /// @param _indexPrice The index price
    /// @param _liquidationFeeRate The liquidation fee rate for trader positions,
    /// denominated in thousandths of a bip (i.e. 1e-7)
    /// @return liquidationFee The liquidation fee of the position
    function calcLiquidationFee(
        uint96 _size,
        uint64 _entryPrice,
        uint64 _indexPrice,
        uint24 _liquidationFeeRate
    ) internal pure returns (uint96 liquidationFee) {
        // liquidationFee = size * entryPrice * liquidationFeeRate / indexPrice
        unchecked {
            uint256 denominator = uint256(_indexPrice) * Constants.BASIS_POINTS_DIVISOR;
            liquidationFee = ((uint256(_size) * _liquidationFeeRate * _entryPrice) / denominator).toUint96();
        }
    }

    /// @notice Calculate the maintenance margin
    /// @dev maintenanceMargin = size * entryPrice * liquidationFeeRate / indexPrice
    ///                          + size * entryPrice * tradingFeeRate / indexPrice
    ///                          + liquidationExecutionFee
    ///                        = size * entryPrice * (liquidationFeeRate + tradingFeeRate) / indexPrice
    ///                          + liquidationExecutionFee
    /// @param _size The size of the position
    /// @param _entryPrice The entry price of the position
    /// @param _indexPrice The index price
    /// @param _liquidationFeeRate The liquidation fee rate for trader positions,
    /// denominated in thousandths of a bip (i.e. 1e-7)
    /// @param _tradingFeeRate The trading fee rate for trader increase or decrease positions,
    /// denominated in thousandths of a bip (i.e. 1e-7)
    /// @param _liquidationExecutionFee The liquidation execution fee paid by the position
    /// @return maintenanceMargin The maintenance margin
    function calcMaintenanceMargin(
        uint96 _size,
        uint64 _entryPrice,
        uint64 _indexPrice,
        uint24 _liquidationFeeRate,
        uint24 _tradingFeeRate,
        uint64 _liquidationExecutionFee
    ) internal pure returns (uint256 maintenanceMargin) {
        unchecked {
            uint256 numerator = uint256(_size) * _entryPrice * (uint64(_liquidationFeeRate) + _tradingFeeRate);
            maintenanceMargin = Math.ceilDiv(numerator, uint256(_indexPrice) * Constants.BASIS_POINTS_DIVISOR);
            maintenanceMargin += _liquidationExecutionFee;
        }
    }

    function refreshSpreadFactor(
        IMarketManager.PackedState storage _packedState,
        IConfigurable.MarketConfig storage _cfg,
        IERC20 _market,
        uint96 _sizeDelta,
        Side _side
    ) internal returns (uint96 spread) {
        int256 spreadFactorAfterX96;
        (spread, spreadFactorAfterX96) = SpreadUtil.calcSpread(
            _cfg,
            SpreadUtil.CalcSpreadParam({
                side: _side,
                sizeDelta: _sizeDelta,
                spreadFactorBeforeX96: _packedState.spreadFactorX96,
                lastTradingTimestamp: _packedState.lastTradingTimestamp
            })
        );
        _packedState.spreadFactorX96 = spreadFactorAfterX96;
        _packedState.lastTradingTimestamp = uint64(block.timestamp); // overflow is desired

        emit IMarketManager.SpreadFactorChanged(_market, spreadFactorAfterX96);
    }

    function distributeTradingFee(
        IMarketManager.State storage _state,
        DistributeFeeParam memory _param
    ) internal returns (uint96 tradingFee) {
        tradingFee = calcTradingFee(_param);

        uint96 liquidityFee;
        unchecked {
            uint96 _protocolFee = uint96(
                (uint256(tradingFee) * _param.protocolFeeRate) / Constants.BASIS_POINTS_DIVISOR
            );
            _state.protocolFee += _protocolFee; // overflow is desired
            emit IMarketManager.ProtocolFeeIncreased(_param.market, _protocolFee);

            liquidityFee = tradingFee - _protocolFee;
        }

        _state.packedState.lpLiquidity += liquidityFee;
        emit IMarketLiquidity.GlobalLiquidityIncreasedByTradingFee(_param.market, liquidityFee);
    }

    function calcTradingFee(DistributeFeeParam memory _param) internal pure returns (uint96 tradingFee) {
        unchecked {
            uint256 denominator = uint256(_param.indexPrice) * Constants.BASIS_POINTS_DIVISOR;
            uint256 numerator = uint256(_param.size) * _param.tradingFeeRate * _param.entryPrice;
            tradingFee = _param.rounding == Math.Rounding.Up
                ? Math.ceilDiv(numerator, denominator).toUint96()
                : (numerator / denominator).toUint96();
        }
    }

    function distributeSpread(IMarketManager.State storage _state, IERC20 _market, uint96 _spread) internal {
        if (_spread > 0) {
            unchecked {
                _state.globalStabilityFund += _spread; // overflow is desired
                emit IMarketManager.GlobalStabilityFundIncreasedBySpread(_market, _spread);
            }
        }
    }

    function distributeLiquidationFee(
        IMarketManager.State storage _state,
        IERC20 _market,
        uint96 _liquidationFee
    ) internal {
        unchecked {
            _state.globalStabilityFund += _liquidationFee; // overflow is desired
            emit IMarketManager.GlobalStabilityFundIncreasedByLiquidation(_market, _liquidationFee);
        }
    }

    /// @notice Calculate the next entry price of a position
    /// @param _side The side of the position (Long or Short)
    /// @param _sizeBefore The size of the position before the trade
    /// @param _entryPriceBefore The entry price of the position before the trade
    /// @param _sizeDelta The size of the trade
    /// @param _indexPrice The index price at which the position is changed
    /// @return nextEntryPrice The entry price of the position after the trade
    function calcNextEntryPrice(
        Side _side,
        uint128 _sizeBefore,
        uint64 _entryPriceBefore,
        uint128 _sizeDelta,
        uint64 _indexPrice
    ) internal pure returns (uint64 nextEntryPrice) {
        if (_sizeBefore == 0) nextEntryPrice = _indexPrice;
        else if (_sizeDelta == 0) nextEntryPrice = _entryPriceBefore;
        else {
            unchecked {
                uint256 liquidityAfter = uint256(_sizeBefore) * _entryPriceBefore;
                liquidityAfter += uint256(_sizeDelta) * _indexPrice;
                uint256 sizeAfter = uint256(_sizeBefore) + _sizeDelta;
                nextEntryPrice = uint64(
                    _side.isLong() ? Math.ceilDiv(liquidityAfter, sizeAfter) : liquidityAfter / sizeAfter
                );
            }
        }
    }

    /// @notice Calculate the quantity of tokens with 6 decimal precision that can be exchanged
    /// at the index price using the market token amount
    /// @param _marketTokenAmount The amount of market tokens
    /// @param _indexPrice The index price
    /// @param _marketDecimals The decimal places of the market token
    /// @param _rounding The rounding mode
    /// @return value The quantity of tokens represented with 6 decimal precision
    function calcDecimals6TokenValue(
        uint96 _marketTokenAmount,
        uint64 _indexPrice,
        uint8 _marketDecimals,
        Math.Rounding _rounding
    ) internal pure returns (uint64 value) {
        unchecked {
            uint256 denominator = 10 ** (Constants.PRICE_DECIMALS - Constants.DECIMALS_6 + _marketDecimals);
            value = _rounding == Math.Rounding.Up
                ? Math.ceilDiv(uint256(_marketTokenAmount) * _indexPrice, denominator).toUint64()
                : ((uint256(_marketTokenAmount) * _indexPrice) / denominator).toUint64();
        }
    }

    /// @notice Calculate the quantity of market tokens that can be exchanged at the index price
    /// using the tokens with 6 decimal precision
    /// @param _decimals6TokenAmount The amount of tokens represented with 6 decimal precision
    /// @param _indexPrice The index price
    /// @param _marketDecimals The decimal places of the market token
    /// @return value The quantity of market tokens
    function calcMarketTokenValue(
        uint96 _decimals6TokenAmount,
        uint64 _indexPrice,
        uint8 _marketDecimals
    ) internal pure returns (uint96 value) {
        unchecked {
            uint256 numerator = uint256(_decimals6TokenAmount) *
                10 ** (Constants.PRICE_DECIMALS - Constants.DECIMALS_6 + _marketDecimals);
            value = (numerator / _indexPrice).toUint96();
        }
    }

    /// @notice Calculate the unrealized PnL of a position based on entry price
    /// @param _side The side of the position (Long or Short)
    /// @param _size The size of the position
    /// @param _entryPrice The entry price of the position
    /// @param _price The trade price or index price, caller should ensure that the price is not zero
    /// @return unrealizedPnL The unrealized PnL of the position, positive value means profit,
    /// negative value means loss
    function calcUnrealizedPnL(
        Side _side,
        uint128 _size,
        uint64 _entryPrice,
        uint64 _price
    ) internal pure returns (int256 unrealizedPnL) {
        unchecked {
            if (_side.isLong()) {
                if (_entryPrice > _price)
                    unrealizedPnL = -int256(Math.ceilDiv(uint256(_size) * (_entryPrice - _price), _price));
                else unrealizedPnL = int256((uint256(_size) * (_price - _entryPrice)) / _price);
            } else {
                if (_entryPrice < _price)
                    unrealizedPnL = -int256(Math.ceilDiv(uint256(_size) * (_price - _entryPrice), _price));
                else unrealizedPnL = int256((uint256(_size) * (_entryPrice - _price)) / _price);
            }
        }
    }

    /// @notice Calculate the liquidation price
    /// @dev Given the liquidation condition as:
    /// For long position: margin - size * (entryPrice - liquidationPrice) / liquidationPrice
    ///                     = entryPrice * size * liquidationFeeRate / liquidationPrice
    ///                         + entryPrice * size * tradingFeeRate / liquidationPrice + liquidationExecutionFee
    /// We can get:
    /// Long position liquidation price:
    ///     liquidationPrice
    ///       = size * entryPrice * (liquidationFeeRate + tradingFeeRate + 1)
    ///       / [margin + size - liquidationExecutionFee]
    /// @param _position The cache of position
    /// @param _liquidationFeeRate The liquidation fee rate for trader positions,
    /// denominated in thousandths of a bip (i.e. 1e-7)
    /// @param _tradingFeeRate The trading fee rate for trader increase or decrease positions,
    /// denominated in thousandths of a bip (i.e. 1e-7)
    /// @param _liquidationExecutionFee The liquidation execution fee paid by the position
    /// @return liquidationPrice The liquidation price of the position
    function calcLiquidationPrice(
        IMarketManager.Position memory _position,
        uint24 _liquidationFeeRate,
        uint24 _tradingFeeRate,
        uint64 _liquidationExecutionFee
    ) internal pure returns (uint64 liquidationPrice) {
        unchecked {
            int256 denominator = int256(uint256(_position.margin) + _position.size) -
                int256(uint256(_liquidationExecutionFee));
            assert(denominator > 0);
            denominator *= int256(uint256(Constants.BASIS_POINTS_DIVISOR));

            uint256 numerator = uint256(_position.size) * _position.entryPrice;
            numerator *= uint64(_liquidationFeeRate) + _tradingFeeRate + Constants.BASIS_POINTS_DIVISOR;
            liquidationPrice = (numerator / uint256(denominator)).toUint64();
        }
    }

    function calcTradingFeeRate(
        IConfigurable.MarketConfig storage _cfg,
        uint128 _lpLiquidity,
        uint128 _lpNetSizeAfter
    ) internal view returns (uint24 tradingFeeRate) {
        unchecked {
            uint256 floatingTradingFeeSize = (uint256(_lpLiquidity) * _cfg.openPositionThreshold) /
                Constants.BASIS_POINTS_DIVISOR;
            if (_lpNetSizeAfter > floatingTradingFeeSize) {
                uint256 floatingTradingFeeRate = (_cfg.maxFeeRate * (_lpNetSizeAfter - floatingTradingFeeSize)) /
                    (_lpLiquidity - floatingTradingFeeSize);
                return uint24(floatingTradingFeeRate) + _cfg.tradingFeeRate;
            } else {
                return _cfg.tradingFeeRate;
            }
        }
    }

    /// @notice Validate the increase position size
    /// @param _sizeBefore The size of the position before the trade
    /// @param _sizeDelta The size of the trade
    /// @return sizeAfter The size of the position after the trade
    /// @return lpNetSizeAfter The net size of the LP after the trade
    function validateIncreaseSize(
        IConfigurable.MarketConfig storage _cfg,
        IMarketManager.PackedState storage _packedState,
        uint96 _sizeBefore,
        uint96 _sizeDelta
    ) internal view returns (uint96 sizeAfter, uint128 lpNetSizeAfter) {
        unchecked {
            (uint128 lpNetSize, uint128 lpLiquidity) = (_packedState.lpNetSize, _packedState.lpLiquidity);
            uint256 lpNetSizeAfter_ = uint256(lpNetSize) + _sizeDelta;
            if (lpNetSizeAfter_ > lpLiquidity) revert IMarketErrors.SizeExceedsMaxSize(lpNetSizeAfter_, lpLiquidity);

            lpNetSizeAfter = uint128(lpNetSizeAfter_);

            sizeAfter = (uint256(_sizeBefore) + _sizeDelta).toUint96();
            uint256 maxSizePerPosition = (uint256(_cfg.liquidityCap) * _cfg.maxSizeRatePerPosition) /
                Constants.BASIS_POINTS_DIVISOR;
            if (sizeAfter > maxSizePerPosition)
                revert IMarketErrors.SizeExceedsMaxSizePerPosition(sizeAfter, maxSizePerPosition);
        }
    }

    /// @notice Validate the position has not reached the liquidation margin rate
    function _validatePositionLiquidateMaintainMarginRate(
        IConfigurable.MarketConfig storage _cfg,
        MaintainMarginRateParam memory _param
    ) private view {
        uint256 maintenanceMargin = calcMaintenanceMargin(
            _param.size,
            _param.entryPrice,
            _param.decreaseIndexPrice,
            _cfg.liquidationFeeRatePerPosition,
            _cfg.tradingFeeRate,
            _cfg.liquidationExecutionFee
        );
        int256 unrealizedPnL = calcUnrealizedPnL(LONG, _param.size, _param.entryPrice, _param.decreaseIndexPrice);
        unchecked {
            if (unrealizedPnL < 0) maintenanceMargin += uint256(-unrealizedPnL);
        }

        if (!_param.liquidatablePosition) {
            if (_param.margin <= 0 || maintenanceMargin >= uint256(_param.margin))
                revert IMarketErrors.MarginRateTooHigh(_param.margin, maintenanceMargin);
        } else {
            if (_param.margin > 0 && maintenanceMargin < uint256(_param.margin))
                revert IMarketErrors.MarginRateTooLow(_param.margin, maintenanceMargin);
        }
    }
}
