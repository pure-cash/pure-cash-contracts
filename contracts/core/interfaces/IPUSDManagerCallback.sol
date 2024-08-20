// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title Callback for IPUSDManager.mint and IPUSDManager.burn
interface IPUSDManagerCallback {
    /// @notice Called after executing a mint or burn operation
    /// @dev In this implementation, you are required to pay the amount of `payAmount` to the caller.
    /// @dev In this implementation, you MUST check that the caller is IPUSDManager.
    /// @param payToken The token to pay
    /// @param payAmount The amount of token to pay
    /// @param receiveAmount The amount of token to receive
    /// @param data The data passed to the original `mint` or `burn` function
    function PUSDManagerCallback(IERC20 payToken, uint96 payAmount, uint96 receiveAmount, bytes calldata data) external;
}
