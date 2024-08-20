// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "./Governable.sol";

abstract contract GovernableProxy {
    Governable private _impl;

    error Forbidden();

    modifier onlyGov() {
        _onlyGov();
        _;
    }

    constructor(Governable _newImpl) {
        _impl = _newImpl;
    }

    function _changeImpl(Governable _newGov) public virtual onlyGov {
        _impl = _newGov;
    }

    function gov() public view virtual returns (address) {
        return _impl.gov();
    }

    function _onlyGov() internal view {
        if (msg.sender != _impl.gov()) revert Forbidden();
    }
}
