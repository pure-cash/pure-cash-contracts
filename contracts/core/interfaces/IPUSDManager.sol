// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "./IPUSD.sol";
import "./IPUSDManagerCallback.sol";

/// @notice Interface for managing the minting and burning of PUSD.
interface IPUSDManager {
    struct GlobalPUSDPosition {
        /// @notice The total PUSD supply of the current market
        uint64 totalSupply;
        /// @notice The size of the position
        uint128 size;
        /// @notice The entry price of the position
        uint64 entryPrice;
    }

    /// @notice Emitted when PUSD is deployed
    event PUSDDeployed(IPUSD indexed pusd);

    /// @notice Emitted when the PUSD position is increased
    /// @param market The target market contract address, such as the contract address of WETH
    /// @param receiver Address to receive PUSD
    /// @param sizeDelta The size of the position to increase
    /// @param indexPrice The index price at which the position is increased
    /// @param entryPriceAfter The adjusted entry price of the position
    /// @param payAmount The amount of token to pay
    /// @param receiveAmount The amount of PUSD to mint
    /// @param tradingFee The amount of trading fee to pay
    /// @param spread The spread incurred by the position
    event PUSDPositionIncreased(
        IERC20 indexed market,
        address indexed receiver,
        uint96 sizeDelta,
        uint64 indexPrice,
        uint64 entryPriceAfter,
        uint96 payAmount,
        uint64 receiveAmount,
        uint96 tradingFee,
        uint96 spread
    );

    /// @notice Emitted when the PUSD position is decreased
    /// @param market The target market contract address, such as the contract address of WETH
    /// @param receiver Address to receive token
    /// @param sizeDelta The size of the position to decrease
    /// @param indexPrice The index price at which the position is decreased
    /// @param payAmount The amount of PUSD to burn
    /// @param receiveAmount The amount of token to receive
    /// @param realizedPnL The realized profit and loss of the position
    /// @param tradingFee The amount of trading fee to pay
    /// @param spread The spread incurred by the position
    event PUSDPositionDecreased(
        IERC20 indexed market,
        address indexed receiver,
        uint96 sizeDelta,
        uint64 indexPrice,
        uint64 payAmount,
        uint96 receiveAmount,
        int256 realizedPnL,
        uint96 tradingFee,
        uint96 spread
    );

    /// @notice Get the global PUSD position of the given market
    /// @param market The target market contract address, such as the contract address of WETH
    function globalPUSDPositions(IERC20 market) external view returns (GlobalPUSDPosition memory);

    /// @notice Mint PUSD
    /// @param market The target market contract address, such as the contract address of WETH
    /// @param amount When `exactIn` is true, it is the amount of token to pay,
    /// otherwise, it is the amount of PUSD to mint
    /// @param callback Address to callback after minting
    /// @param data Any data to be passed to the callback
    /// @param receiver Address to receive PUSD
    /// @return payAmount The amount of token to pay
    /// @return receiveAmount The amount of PUSD to receive
    function mintPUSD(
        IERC20 market,
        bool exactIn,
        uint96 amount,
        IPUSDManagerCallback callback,
        bytes calldata data,
        address receiver
    ) external returns (uint96 payAmount, uint64 receiveAmount);

    /// @notice Burn PUSD
    /// @param market The target market contract address, such as the contract address of WETH
    /// @param amount When `exactIn` is true, it is the amount of PUSD to burn,
    /// otherwise, it is the amount of token to receive
    /// @param callback Address to callback after burning
    /// @param data Any data to be passed to the callback
    /// @param receiver Address to receive token
    /// @return payAmount The amount of PUSD to pay
    /// @return receiveAmount The amount of token to receive
    function burnPUSD(
        IERC20 market,
        bool exactIn,
        uint96 amount,
        IPUSDManagerCallback callback,
        bytes calldata data,
        address receiver
    ) external returns (uint64 payAmount, uint96 receiveAmount);
}
