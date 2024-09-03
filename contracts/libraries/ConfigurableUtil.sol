// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "./Constants.sol";
import "../core/interfaces/IConfigurable.sol";

library ConfigurableUtil {
    function enableMarket(
        mapping(IERC20 => IConfigurable.MarketConfig) storage _self,
        IERC20 _market,
        IConfigurable.MarketConfig calldata _cfg
    ) public {
        if (_self[_market].liquidityCap > 0) revert IConfigurable.MarketAlreadyEnabled(_market);

        _validateConfig(_cfg);

        _self[_market] = _cfg;

        emit IConfigurable.MarketConfigEnabled(_market, _cfg);
    }

    function updateMarketConfig(
        mapping(IERC20 => IConfigurable.MarketConfig) storage _self,
        IERC20 _market,
        IConfigurable.MarketConfig calldata _newCfg
    ) public {
        if (_self[_market].liquidityCap == 0) revert IConfigurable.MarketNotEnabled(_market);

        _validateConfig(_newCfg);

        _self[_market] = _newCfg;

        emit IConfigurable.MarketConfigChanged(_market, _newCfg);
    }

    function _validateConfig(IConfigurable.MarketConfig calldata _newCfg) private pure {
        if (_newCfg.maxLeveragePerPosition == 0)
            revert IConfigurable.InvalidMaxLeveragePerPosition(_newCfg.maxLeveragePerPosition);

        if (_newCfg.liquidationFeeRatePerPosition > Constants.BASIS_POINTS_DIVISOR)
            revert IConfigurable.InvalidLiquidationFeeRatePerPosition(_newCfg.liquidationFeeRatePerPosition);

        if (_newCfg.maxSizeRatePerPosition == 0 || _newCfg.maxSizeRatePerPosition > Constants.BASIS_POINTS_DIVISOR)
            revert IConfigurable.InvalidMaxSizeRatePerPosition(_newCfg.maxSizeRatePerPosition);

        if (_newCfg.openPositionThreshold > Constants.BASIS_POINTS_DIVISOR)
            revert IConfigurable.InvalidOpenPositionThreshold(_newCfg.openPositionThreshold);

        if (_newCfg.liquidityCap == 0) revert IConfigurable.InvalidLiquidityCap(_newCfg.liquidityCap);

        if (_newCfg.decimals == 0 || _newCfg.decimals > 18) revert IConfigurable.InvalidDecimals(_newCfg.decimals);

        if (_newCfg.tradingFeeRate > Constants.BASIS_POINTS_DIVISOR)
            revert IConfigurable.InvalidTradingFeeRate(_newCfg.tradingFeeRate);

        if (_newCfg.protocolFeeRate > Constants.BASIS_POINTS_DIVISOR)
            revert IConfigurable.InvalidProtocolFeeRate(_newCfg.protocolFeeRate);

        if (_newCfg.maxFeeRate > Constants.BASIS_POINTS_DIVISOR)
            revert IConfigurable.InvalidMaxFeeRate(_newCfg.maxFeeRate);

        unchecked {
            if (uint64(_newCfg.maxFeeRate) + _newCfg.tradingFeeRate > Constants.BASIS_POINTS_DIVISOR)
                revert IConfigurable.InvalidMaxFeeRate(_newCfg.maxFeeRate);
        }

        if (_newCfg.minMintingRate > Constants.BASIS_POINTS_DIVISOR)
            revert IConfigurable.InvalidMinMintingRate(_newCfg.minMintingRate);

        if (_newCfg.maxBurningRate > Constants.BASIS_POINTS_DIVISOR)
            revert IConfigurable.InvalidMaxBurningRate(_newCfg.maxBurningRate);

        if (_newCfg.riskFreeTime == 0) revert IConfigurable.ZeroRiskFreeTime();

        if (_newCfg.liquidityScale == 0) revert IConfigurable.ZeroLiquidityScale();

        if (_newCfg.stableCoinSupplyCap == 0)
            revert IConfigurable.InvalidStableCoinSupplyCap(_newCfg.stableCoinSupplyCap);

        if (_newCfg.liquidityTradingFeeRate > Constants.BASIS_POINTS_DIVISOR)
            revert IConfigurable.InvalidLiquidityTradingFeeRate(_newCfg.liquidityTradingFeeRate);
    }
}
