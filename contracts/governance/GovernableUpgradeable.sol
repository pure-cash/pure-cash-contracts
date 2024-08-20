// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

abstract contract GovernableUpgradeable is UUPSUpgradeable {
    /// @custom:storage-location erc7201:Purecash.storage.GovernableUpgradeable
    struct GovStorage {
        address gov;
        address pendingGov;
    }

    // keccak256(abi.encode(uint256(keccak256("Purecash.storage.GovernableUpgradeable")) - 1))
    // & ~bytes32(uint256(0xff))
    bytes32 private constant GOVERNABLE_UPGRADEABLE_STORAGE =
        0x71907d27e7f56436d282b33232af729b796faa4dde12f80868ee08b9116c5200;

    event ChangeGovStarted(address indexed previousGov, address indexed newGov);
    event GovChanged(address indexed previousGov, address indexed newGov);

    error Forbidden();

    modifier onlyGov() {
        _onlyGov();
        _;
    }

    function __Governable_init(address _initialGov) internal onlyInitializing {
        UUPSUpgradeable.__UUPSUpgradeable_init();
        __Governable_init_unchained(_initialGov);
    }

    function __Governable_init_unchained(address _initialGov) internal onlyInitializing {
        _changeGov(_initialGov);
    }

    function gov() public view virtual returns (address) {
        return _governableStorage().gov;
    }

    function pendingGov() public view virtual returns (address) {
        return _governableStorage().pendingGov;
    }

    function changeGov(address _newGov) public virtual onlyGov {
        GovStorage storage $ = _governableStorage();
        $.pendingGov = _newGov;
        emit ChangeGovStarted($.gov, _newGov);
    }

    function acceptGov() public virtual {
        GovStorage storage $ = _governableStorage();
        if (msg.sender != $.pendingGov) revert Forbidden();

        delete $.pendingGov;
        _changeGov(msg.sender);
    }

    function _changeGov(address _newGov) internal virtual {
        GovStorage storage $ = _governableStorage();
        address previousGov = $.gov;
        $.gov = _newGov;
        emit GovChanged(previousGov, _newGov);
    }

    function _onlyGov() internal view {
        if (msg.sender != _governableStorage().gov) revert Forbidden();
    }

    function _governableStorage() private pure returns (GovStorage storage $) {
        // prettier-ignore
        assembly { $.slot := GOVERNABLE_UPGRADEABLE_STORAGE }
    }
}
