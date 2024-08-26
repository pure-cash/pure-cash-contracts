// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IPUSD is IERC20 {
    function mint(address to, uint256 value) external;

    function burn(uint256 value) external;
}
