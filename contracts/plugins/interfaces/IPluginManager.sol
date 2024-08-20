// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title Plugin Manager Interface
/// @notice The interface defines the functions to manage plugins
interface IPluginManager {
    /// @notice Emitted when a plugin is updated
    /// @param plugin The plugin to update
    /// @param active Whether active after the update
    event PluginUpdated(address indexed plugin, bool active);

    /// @notice Error thrown when the plugin is inactive
    error PluginInactive(address plugin);

    /// @notice Update plugin
    /// @param plugin The plugin to update
    /// @param active Whether active after the update
    function updatePlugin(address plugin, bool active) external;

    /// @notice Checks if a plugin is registered
    /// @param plugin The plugin to check
    /// @return True if the plugin is registered, false otherwise
    function activePlugins(address plugin) external view returns (bool);

    /// @notice Transfers `amount` of `token` from `from` to `to`
    /// @param token The address of the ERC20 token
    /// @param from The address to transfer the tokens from
    /// @param to The address to transfer the tokens to
    /// @param amount The amount of tokens to transfer
    function pluginTransfer(IERC20 token, address from, address to, uint256 amount) external;
}
