// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "../governance/GovernableUpgradeable.sol";
import "../libraries/ReentrancyGuard.sol";
import "../libraries/ConfigurableUtil.sol";

abstract contract ConfigurableUpgradeable is IConfigurable, GovernableUpgradeable, ReentrancyGuard {
    using ConfigurableUtil for mapping(IERC20 market => MarketConfig);

    /// @custom:storage-location erc7201:Purecash.storage.ConfigurableUpgradeable
    struct ConfigurableStorage {
        mapping(IERC20 market => MarketConfig) marketConfigs;
    }

    // keccak256(abi.encode(uint256(keccak256("Purecash.storage.ConfigurableUpgradeable")) - 1))
    // & ~bytes32(uint256(0xff))
    bytes32 private constant CONFIGURABLE_UPGRADEABLE_STORAGE =
        0x2e53c93cfb85b377c33c5881ea2e8ae1c7fa4b789e2a859438dc71474e045100;

    function __Configurable_init(address _initialGov) internal onlyInitializing {
        __Governable_init(_initialGov);
        __Configurable_init_unchained();
    }

    function __Configurable_init_unchained() internal onlyInitializing {}

    /// @inheritdoc IConfigurable
    function isEnabledMarket(IERC20 _market) external view override returns (bool) {
        return _isEnabledMarket(_market);
    }

    /// @inheritdoc IConfigurable
    function marketConfigs(IERC20 _market) external view override returns (MarketConfig memory) {
        return _configurableStorage().marketConfigs[_market];
    }

    /// @inheritdoc IConfigurable
    function enableMarket(IERC20 _market, string calldata _tokenSymbol, MarketConfig calldata _cfg) external override {
        _onlyGov();
        _configurableStorage().marketConfigs.enableMarket(_market, _cfg);

        afterMarketEnabled(_market, _tokenSymbol);
    }

    /// @inheritdoc IConfigurable
    function updateMarketConfig(IERC20 _market, MarketConfig calldata _newCfg) public override {
        _onlyGov();
        _configurableStorage().marketConfigs.updateMarketConfig(_market, _newCfg);
    }

    function afterMarketEnabled(IERC20 _market, string calldata _tokenSymbol) internal virtual {
        // solhint-disable-previous-line no-empty-blocks
    }

    function _onlyEnabled(IERC20 _market) internal view {
        if (_configurableStorage().marketConfigs[_market].liquidityCap == 0) revert MarketNotEnabled(_market);
    }

    function _isEnabledMarket(IERC20 _market) internal view returns (bool) {
        return _configurableStorage().marketConfigs[_market].liquidityCap != 0;
    }

    function _configurableStorage() internal pure returns (ConfigurableStorage storage $) {
        // prettier-ignore
        assembly { $.slot := CONFIGURABLE_UPGRADEABLE_STORAGE }
    }
}
