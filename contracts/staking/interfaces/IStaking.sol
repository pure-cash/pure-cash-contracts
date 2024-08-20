// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IStaking {
    /// @notice Emitted when the token is staked
    /// @param token The token contract address
    /// @param sender The address to call the function
    /// @param receiver The address to receive the staked token
    /// @param amount The token to stake
    event Staked(IERC20 indexed token, address sender, address receiver, uint256 amount);

    /// @notice Emitted when the token is unstaked
    /// @param token The token contract address
    /// @param account The address to unstake the token
    /// @param receiver The address to receive the unstaked token
    /// @param amount The token to unstake
    event Unstaked(IERC20 indexed token, address account, address receiver, uint128 amount);

    /// @notice Emitted when stableMarketPriceFeed set
    /// @param token The token contract address
    /// @param limit The maximum allowed amount of tokens for staking
    event MaxStakedLimitSet(IERC20 indexed token, uint256 limit);

    /// @notice Error thrown when the input amount is invalid
    error InvalidInputAmount(uint128 amount);

    /// @notice Error thrown when the staked amount exceeds the maximum allowed stake limit
    error ExceededMaxStakedLimit(uint256 amount);

    /// @notice Error thrown when the input limit is invalid
    error InvalidLimit(uint256 limit);

    /// @notice Stake the token
    /// @param token The token contract address
    /// @param receiver The address to receive the staked token
    /// @param amount The token to stake
    /// @param permitData The permit data for the token, optional
    function stake(IERC20 token, address receiver, uint128 amount, bytes calldata permitData) external;

    /// @notice Unstake the token
    /// @param token The token contract address
    /// @param receiver The address to receive the unstaked token
    /// @param amount The token to unstake
    function unstake(IERC20 token, address receiver, uint128 amount) external;

    /// @notice Set the the maximum allowed stake limit
    /// @param token The token contract address
    /// @param limit The maximum allowed amount of tokens for staking
    function setMaxStakedLimit(IERC20 token, uint256 limit) external;
}
