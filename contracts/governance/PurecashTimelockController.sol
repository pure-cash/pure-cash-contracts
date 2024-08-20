// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity =0.8.26;

import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/governance/TimelockController.sol";
import "./Governable.sol";

contract PurecashTimelockController is TimelockController {
    using Address for address;

    constructor(
        uint256 minDelay,
        address[] memory proposers,
        address[] memory executors,
        address admin
    ) TimelockController(minDelay, proposers, executors, admin) {}

    function acceptGov(Governable target) public onlyRole(EXECUTOR_ROLE) {
        target.acceptGov();
    }
}
