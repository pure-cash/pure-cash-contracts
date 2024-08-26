// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "./ConfigurableUpgradeable.sol";
import "./FeeDistributorUpgradeable.sol";
import "../libraries/MarketUtil.sol";
import "../libraries/PUSDManagerUtil.sol";
import "../plugins/PluginManagerUpgradeable.sol";

abstract contract MarketManagerStatesUpgradeable is IMarketManager, ConfigurableUpgradeable, PluginManagerUpgradeable {
    using SafeCast for *;

    /// @custom:storage-location erc7201:Purecash.storage.MarketManagerStatesUpgradeable
    struct MarketManagerStatesStorage {
        mapping(IERC20 market => State) marketStates;
        FeeDistributorUpgradeable feeDistributor;
    }

    // keccak256(abi.encode(uint256(keccak256("Purecash.storage.MarketManagerStatesUpgradeable")) - 1))
    // & ~bytes32(uint256(0xff))
    bytes32 private constant MARKET_MANAGER_STATES_UPGRADEABLE_STORAGE =
        0x251c369f4ebdedc72c1498dbeb9b538f609b170856998c6e34e4ab95eaf53300;

    function __MarketManagerStates_init(
        address _initialGov,
        FeeDistributorUpgradeable _feeDistributor
    ) internal onlyInitializing {
        __Configurable_init(_initialGov);
        __MarketManagerStates_init_unchained(_feeDistributor);
    }

    function __MarketManagerStates_init_unchained(FeeDistributorUpgradeable _feeDistributor) internal onlyInitializing {
        MarketManagerStatesStorage storage $ = _statesStorage();
        $.feeDistributor = _feeDistributor;
    }

    /// @inheritdoc IMarketManager
    function packedStates(IERC20 _market) external view override returns (PackedState memory) {
        return _statesStorage().marketStates[_market].packedState;
    }

    /// @inheritdoc IMarketManager
    function protocolFees(IERC20 _market) external view override returns (uint128) {
        return _statesStorage().marketStates[_market].protocolFee;
    }

    /// @inheritdoc IMarketManager
    function tokenBalances(IERC20 _market) external view override returns (uint128) {
        return _statesStorage().marketStates[_market].tokenBalance;
    }

    /// @inheritdoc IMarketManager
    function liquidityBufferModules(IERC20 _market) external view override returns (LiquidityBufferModule memory) {
        return _statesStorage().marketStates[_market].liquidityBufferModule;
    }

    /// @inheritdoc IPUSDManager
    function globalPUSDPositions(IERC20 _market) external view returns (GlobalPUSDPosition memory) {
        return _statesStorage().marketStates[_market].globalPUSDPosition;
    }

    /// @inheritdoc IMarketPosition
    function longPositions(IERC20 _market, address _account) external view override returns (Position memory) {
        return _statesStorage().marketStates[_market].longPositions[_account];
    }

    /// @inheritdoc IMarketManager
    function globalStabilityFunds(IERC20 _market) external view override returns (uint256) {
        return _statesStorage().marketStates[_market].globalStabilityFund;
    }

    function pusd() external view returns (address) {
        return PUSDManagerUtil.computePUSDAddress();
    }

    function _statesStorage() internal pure returns (MarketManagerStatesStorage storage $) {
        // prettier-ignore
        assembly { $.slot := MARKET_MANAGER_STATES_UPGRADEABLE_STORAGE }
    }
}
