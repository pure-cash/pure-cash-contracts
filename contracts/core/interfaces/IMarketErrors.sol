// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

interface IMarketErrors {
    /// @notice Failed to transfer ETH
    error FailedTransferETH();
    /// @notice Invalid caller
    error InvalidCaller(address requiredCaller);
    /// @notice Insufficient size to decrease
    error InsufficientSizeToDecrease(uint128 requiredSize, uint128 size);
    /// @notice Insufficient margin
    error InsufficientMargin();
    /// @notice Position not found
    error PositionNotFound(address requiredAccount);
    /// @notice Size exceeds max size per position
    error SizeExceedsMaxSizePerPosition(uint256 requiredSize, uint256 maxSizePerPosition);
    /// @notice Size exceeds max size
    error SizeExceedsMaxSize(uint256 requiredSize, uint256 maxSize);
    /// @notice Insufficient liquidity to decrease
    error InsufficientLiquidityToDecrease(uint256 liquidity, uint128 requiredLiquidity);
    /// @notice Liquidity Cap exceeded
    error LiquidityCapExceeded(uint128 liquidityBefore, uint96 liquidityDelta, uint120 liquidityCap);
    /// @notice Balance Rate Cap exceeded
    error BalanceRateCapExceeded();
    /// @notice Error thrown when min minting size cap is not met
    error MinMintingSizeCapNotMet(uint128 netSize, uint128 sizeDelta, uint128 minMintingSizeCap);
    /// @notice Error thrown when max burning size cap is exceeded
    error MaxBurningSizeCapExceeded(uint128 netSize, uint128 sizeDelta, uint256 maxBurningSizeCap);
    /// @notice Insufficient balance
    error InsufficientBalance(uint256 balance, uint256 requiredAmount);
    /// @notice Leverage is too high
    error LeverageTooHigh(uint256 margin, uint128 size, uint8 maxLeverage);
    /// @notice Position margin rate is too low
    error MarginRateTooLow(int256 margin, uint256 maintenanceMargin);
    /// @notice Position margin rate is too high
    error MarginRateTooHigh(int256 margin, uint256 maintenanceMargin);
    error InvalidAmount(uint128 requiredAmount, uint128 pusdBalance);
    error InvalidSize();
    /// @notice Stable Coin Supply Cap exceeded
    error StableCoinSupplyCapExceeded(uint256 supplyCap, uint256 totalSupply, uint256 amountDelta);
    /// @notice Error thrown when the pay amount is less than the required amount
    error TooLittlePayAmount(uint128 requiredAmount, uint128 payAmount);
    /// @notice Error thrown when the pay amount is not equal to the required amount
    error UnexpectedPayAmount(uint128 requiredAmount, uint128 payAmount);
    error NegativeReceiveAmount(int256 receiveAmount);
}
