// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Side} from "../../types/Side.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice Interface for managing market positions.
/// @dev The market position is the core component of the protocol, which stores the information of
/// all trader's positions.
interface IMarketPosition {
    struct Position {
        /// @notice The margin of the position
        uint96 margin;
        /// @notice The size of the position
        uint96 size;
        /// @notice The entry price of the position
        uint64 entryPrice;
    }

    /// @notice Emitted when the position is increased
    /// @param market The target market contract address, such as the contract address of WETH
    /// @param account The owner of the position
    /// @param marginDelta The increased margin
    /// @param marginAfter The adjusted margin
    /// @param sizeDelta The increased size
    /// @param indexPrice The index price at which the position is increased.
    /// If only adding margin, it will be 0
    /// @param entryPriceAfter The adjusted entry price of the position
    /// @param tradingFee The trading fee paid by the position
    /// @param spread The spread incurred by the position
    event PositionIncreased(
        IERC20 indexed market,
        address indexed account,
        uint96 marginDelta,
        uint96 marginAfter,
        uint96 sizeDelta,
        uint64 indexPrice,
        uint64 entryPriceAfter,
        uint96 tradingFee,
        uint96 spread
    );

    /// @notice Emitted when the position is decreased
    /// @param market The target market contract address, such as the contract address of WETH
    /// @param account The owner of the position
    /// @param marginDelta The decreased margin
    /// @param marginAfter The adjusted margin
    /// @param sizeDelta The decreased size
    /// @param indexPrice The index price at which the position is decreased
    /// @param realizedPnL The realized PnL
    /// @param tradingFee The trading fee paid by the position
    /// @param spread The spread incurred by the position
    /// @param receiver The address that receives the margin
    event PositionDecreased(
        IERC20 indexed market,
        address indexed account,
        uint96 marginDelta,
        uint96 marginAfter,
        uint96 sizeDelta,
        uint64 indexPrice,
        int256 realizedPnL,
        uint96 tradingFee,
        uint96 spread,
        address receiver
    );

    /// @notice Emitted when a position is liquidated
    /// @param market The target market contract address, such as the contract address of WETH
    /// @param liquidator The address that executes the liquidation of the position
    /// @param account The owner of the position
    /// @param sizeDelta The liquidated size
    /// @param indexPrice The index price at which the position is liquidated
    /// @param liquidationPrice The liquidation price of the position
    /// @param tradingFee The trading fee paid by the position
    /// @param liquidationFee The liquidation fee paid by the position
    /// @param liquidationExecutionFee The liquidation execution fee paid by the position
    /// @param feeReceiver The address that receives the liquidation execution fee
    event PositionLiquidated(
        IERC20 indexed market,
        address indexed liquidator,
        address indexed account,
        uint96 sizeDelta,
        uint64 indexPrice,
        uint64 liquidationPrice,
        uint96 tradingFee,
        uint96 liquidationFee,
        uint64 liquidationExecutionFee,
        address feeReceiver
    );

    /// @notice Get the information of a long position
    /// @param market The target market contract address, such as the contract address of WETH
    /// @param account The owner of the position
    function longPositions(IERC20 market, address account) external view returns (Position memory);

    /// @notice Increase the margin or size of a position
    /// @param market The target market contract address, such as the contract address of WETH
    /// @param account The owner of the position
    /// @param sizeDelta The increase in size, which can be 0
    /// @return spread The spread incurred by the position
    function increasePosition(IERC20 market, address account, uint96 sizeDelta) external returns (uint96 spread);

    /// @notice Decrease the margin or size of a position
    /// @param market The target market contract address, such as the contract address of WETH
    /// @param account The owner of the position
    /// @param marginDelta The decrease in margin, which can be 0. If the position size becomes zero after
    /// the decrease, the marginDelta will be ignored, and all remaining margin will be returned
    /// @param sizeDelta The decrease in size, which can be 0
    /// @param receiver The address to receive the margin
    /// @return spread The spread incurred by the position
    /// @return actualMarginDelta The actual decrease in margin
    function decreasePosition(
        IERC20 market,
        address account,
        uint96 marginDelta,
        uint96 sizeDelta,
        address receiver
    ) external returns (uint96 spread, uint96 actualMarginDelta);

    /// @notice Liquidate a position
    /// @param market The target market contract address, such as the contract address of WETH
    /// @param account The owner of the position
    /// @param feeReceiver The address that receives the liquidation execution fee
    function liquidatePosition(IERC20 market, address account, address feeReceiver) external;
}
