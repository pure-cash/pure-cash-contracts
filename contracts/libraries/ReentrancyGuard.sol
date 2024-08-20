// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

abstract contract ReentrancyGuard {
    bytes32 private constant STORAGE_SLOT = keccak256("solidity_reentrancy_guard.storage.slot");

    /**
     * @dev Unauthorized reentrant call.
     */
    error ReentrancyGuardReentrantCall();

    modifier nonReentrant() {
        _nonReentrantBefore(STORAGE_SLOT);
        _;
        _nonReentrantAfter(STORAGE_SLOT);
    }

    modifier nonReentrantToken(IERC20 _token) {
        bytes32 slot = bytes32(uint256(uint160(address(_token))));
        _nonReentrantBefore(slot);
        _;
        _nonReentrantAfter(slot);
    }

    function _nonReentrantBefore(bytes32 _slot) private {
        uint256 state;
        // prettier-ignore
        assembly { state := tload(_slot) }
        require(state == 0, ReentrancyGuardReentrantCall());
        // prettier-ignore
        assembly { tstore(_slot, 1) }
    }

    function _nonReentrantAfter(bytes32 _slot) private {
        // prettier-ignore
        assembly { tstore(_slot, 0) }
    }
}
