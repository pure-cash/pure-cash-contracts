// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IPUSD is IERC20 {
    /// @notice Emitted when minter is updated
    event MinterUpdate(address minter, bool enabled);

    error InvalidMinter();

    /// @notice Set minter
    /// @param minter Minter address
    /// @param enabled Whether minter is enabled
    function setMinter(address minter, bool enabled) external;

    function mint(address to, uint256 value) external;

    function burn(uint256 value) external;
}
