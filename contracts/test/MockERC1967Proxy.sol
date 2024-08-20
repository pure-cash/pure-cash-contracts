// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/// @dev only used for importing ERC1967Proxy into compilation task
contract MockERC1967Proxy is ERC1967Proxy {
    constructor() ERC1967Proxy(address(0x0), bytes("")) {}
}
