// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title Configurable Interface
/// @notice This interface defines the functions for manage market configurations
interface IConfigurable {
    struct MarketConfig {
        /// @notice The liquidation fee rate for per trader position,
        /// denominated in thousandths of a bip (i.e. 1e-7)
        uint24 liquidationFeeRatePerPosition;
        /// @notice The maximum size rate for per position, denominated in thousandths of a bip (i.e. 1e-7)
        uint24 maxSizeRatePerPosition;
        /// @notice If the balance rate after increasing a long position is greater than this parameter,
        /// then the trading fee rate will be changed to the floating fee rate,
        /// denominated in thousandths of a bip (i.e. 1e-7)
        uint24 openPositionThreshold;
        /// @notice The trading fee rate for taker increase or decrease positions,
        /// denominated in thousandths of a bip (i.e. 1e-7)
        uint24 tradingFeeRate;
        /// @notice The maximum leverage for per trader position, for example, 100 means the maximum leverage
        /// is 100 times
        uint8 maxLeveragePerPosition;
        /// @notice The market token decimals
        uint8 decimals;
        /// @notice A system variable to calculate the `spread`
        uint120 liquidityScale;
        /// @notice The protocol fee rate as a percentage of trading fee,
        /// denominated in thousandths of a bip (i.e. 1e-7)
        uint24 protocolFeeRate;
        /// @notice The maximum floating fee rate for increasing long position,
        /// denominated in thousandths of a bip (i.e. 1e-7)
        uint24 maxFeeRate;
        /// @notice A system variable to calculate the `spreadFactor`, in seconds
        uint24 riskFreeTime;
        /// @notice The minimum entry margin required for per trader position
        uint64 minMarginPerPosition;
        /// @notice If balance rate is less than minMintingRate, the minting is disabled,
        /// denominated in thousandths of a bip (i.e. 1e-7)
        uint24 minMintingRate;
        /// @notice If balance rate is greater than maxBurningRate, the burning is disabled,
        /// denominated in thousandths of a bip (i.e. 1e-7)
        uint24 maxBurningRate;
        /// @notice The liquidation execution fee for LP and trader positions
        uint64 liquidationExecutionFee;
        /// @notice Whether the liquidity buffer module is enabled when decreasing position
        bool liquidityBufferModuleEnabled;
        /// @notice If the total supply of the stable coin reach stableCoinSupplyCap, the minting is disabled.
        uint64 stableCoinSupplyCap;
        /// @notice The capacity of the liquidity
        uint120 liquidityCap;
    }

    /// @notice Emitted when the market is enabled
    /// @param market The target market contract address, such as the contract address of WETH
    /// @param cfg The new market configuration
    event MarketConfigEnabled(IERC20 indexed market, MarketConfig cfg);

    /// @notice Emitted when a market configuration is changed
    /// @param market The target market contract address, such as the contract address of WETH
    /// @param cfg The new market configuration
    event MarketConfigChanged(IERC20 indexed market, MarketConfig cfg);

    /// @notice Market is already enabled
    error MarketAlreadyEnabled(IERC20 market);
    /// @notice Market is not enabled
    error MarketNotEnabled(IERC20 market);
    /// @notice Invalid maximum leverage for trader positions
    error InvalidMaxLeveragePerPosition(uint8 maxLeveragePerPosition);
    /// @notice Invalid liquidation fee rate for trader positions
    error InvalidLiquidationFeeRatePerPosition(uint24 liquidationFeeRatePerPosition);
    /// @notice Invalid max size per rate for per position
    error InvalidMaxSizeRatePerPosition(uint24 maxSizeRatePerPosition);
    /// @notice Invalid liquidity capacity
    error InvalidLiquidityCap(uint120 liquidityCap);
    /// @notice Invalid trading fee rate
    error InvalidTradingFeeRate(uint24 tradingFeeRate);
    /// @notice Invalid protocol fee rate
    error InvalidProtocolFeeRate(uint24 protocolFeeRate);
    /// @notice Invalid min minting rate
    error InvalidMinMintingRate(uint24 minMintingRate);
    /// @notice Invalid max burning rate
    error InvalidMaxBurningRate(uint24 maxBurnningRate);
    /// @notice Invalid open position threshold
    error InvalidOpenPositionThreshold(uint24 openPositionThreshold);
    /// @notice Invalid max fee rate
    error InvalidMaxFeeRate(uint24 maxFeeRate);
    /// @notice The risk free time is zero, which is not allowed
    error ZeroRiskFreeTime();
    /// @notice The liquidity scale is zero, which is not allowed
    error ZeroLiquidityScale();
    /// @notice Invalid stable coin supply capacity
    error InvalidStableCoinSupplyCap(uint256 stablecoinSupplyCap);
    /// @notice Invalid decimals
    error InvalidDecimals(uint8 decimals);

    /// @notice Checks if a market is enabled
    /// @param market The target market contract address, such as the contract address of WETH
    /// @return True if the market is enabled, false otherwise
    function isEnabledMarket(IERC20 market) external view returns (bool);

    /// @notice Get the information of market configuration
    /// @param market The target market contract address, such as the contract address of WETH
    function marketConfigs(IERC20 market) external view returns (MarketConfig memory);

    /// @notice Enable the market
    /// @dev The call will fail if caller is not the governor or the market is already enabled
    /// @param market The target market contract address, such as the contract address of WETH
    /// @param tokenSymbol The symbol of the LP token
    /// @param cfg The market configuration
    function enableMarket(IERC20 market, string calldata tokenSymbol, MarketConfig calldata cfg) external;

    /// @notice Update a market configuration
    /// @dev The call will fail if caller is not the governor or the market is not enabled
    /// @param market The target market contract address, such as the contract address of WETH
    /// @param newCfg The new market configuration
    function updateMarketConfig(IERC20 market, MarketConfig calldata newCfg) external;
}
