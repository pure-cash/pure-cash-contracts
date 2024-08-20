// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.26;

import "../governance/GovernableUpgradeable.sol";
import "./interfaces/IPluginManager.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

abstract contract PluginManagerUpgradeable is IPluginManager, GovernableUpgradeable {
    /// @custom:storage-location erc7201:Purecash.storage.PluginManagerUpgradeable
    struct PluginManagerStorage {
        mapping(address plugin => bool) activePlugins;
    }

    // keccak256(abi.encode(uint256(keccak256("Purecash.storage.PluginManagerUpgradeable")) - 1))
    // & ~bytes32(uint256(0xff))
    bytes32 private constant PLUGIN_MANAGER_UPGRADEABLE_STORAGE =
        0xbb40e86f68fafb11efed99ac959fcf9a51deeafbf5b56a45f87ae418cc6eb300;

    function __PluginManager_init(address _initialGov) internal onlyInitializing {
        __PluginManager_init_unchained();
        __Governable_init(_initialGov);
    }

    function __PluginManager_init_unchained() internal onlyInitializing {}

    /// @inheritdoc IPluginManager
    function updatePlugin(address _plugin, bool _active) external override onlyGov {
        PluginManagerStorage storage $ = _pluginManagerStorage();

        $.activePlugins[_plugin] = _active;

        emit PluginUpdated(_plugin, _active);
    }

    /// @inheritdoc IPluginManager
    function activePlugins(address _plugin) public view override returns (bool active) {
        active = _pluginManagerStorage().activePlugins[_plugin];
    }

    /// @inheritdoc IPluginManager
    function pluginTransfer(IERC20 _token, address _from, address _to, uint256 _amount) external override {
        _onlyPlugin();
        SafeERC20.safeTransferFrom(_token, _from, _to, _amount);
    }

    function _onlyPlugin() internal view {
        require(_pluginManagerStorage().activePlugins[msg.sender], PluginInactive(msg.sender));
    }

    function _pluginManagerStorage() internal pure returns (PluginManagerStorage storage $) {
        // prettier-ignore
        assembly { $.slot := PLUGIN_MANAGER_UPGRADEABLE_STORAGE }
    }
}
