// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.26;

import "./interfaces/IPUSD.sol";
import "../libraries/Constants.sol";
import "../governance/GovernableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";

contract PUSDUpgradeable is ERC20Upgradeable, ERC20PermitUpgradeable, GovernableUpgradeable, IPUSD {
    /// @notice Mapping of minters
    mapping(address minter => bool) public minters;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    modifier onlyMinter() {
        if (!minters[msg.sender]) revert InvalidMinter();
        _;
    }

    function initialize(address _initialGov) public initializer {
        ERC20Upgradeable.__ERC20_init("PUSD", "PUSD");
        ERC20PermitUpgradeable.__ERC20Permit_init("PUSD");
        GovernableUpgradeable.__Governable_init(_initialGov);
    }

    /// @inheritdoc ERC20Upgradeable
    function decimals() public view virtual override returns (uint8) {
        return Constants.DECIMALS_6;
    }

    /// @inheritdoc IPUSD
    function setMinter(address _minter, bool _enabled) external override onlyGov {
        minters[_minter] = _enabled;
        emit MinterUpdate(_minter, _enabled);
    }

    /// @inheritdoc IPUSD
    function mint(address _to, uint256 _value) external override onlyMinter {
        _mint(_to, _value);
    }

    /// @inheritdoc IPUSD
    function burn(uint256 _value) external override onlyMinter {
        _burn(msg.sender, _value);
    }

    /// @inheritdoc UUPSUpgradeable
    function _authorizeUpgrade(address newImplementation) internal virtual override onlyGov {}
}
