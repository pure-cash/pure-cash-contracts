// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "./MarketManagerStatesUpgradeable.sol";
import "../libraries/PUSDManagerUtil.sol";

abstract contract PSMUpgradeable is MarketManagerStatesUpgradeable {
    using PUSDManagerUtil for CollateralState;

    /// @custom:storage-location erc7201:Purecash.storage.PSMUpgradeable
    struct PSMStorage {
        mapping(IERC20 collateral => CollateralState) collaterals;
    }

    // keccak256(abi.encode(uint256(keccak256("Purecash.storage.PSMUpgradeable")) - 1))
    // & ~bytes32(uint256(0xff))
    bytes32 private constant PSM_UPGRADEABLE_STORAGE =
        0x9f37cc75d7cdaa7a198c13b92cf96b51104a2ab8d71dd4736b100ec4a2373c00;

    function __PSM_init(
        address _initialGov,
        FeeDistributorUpgradeable _feeDistributor,
        IPUSD _usd
    ) internal onlyInitializing {
        MarketManagerStatesUpgradeable.__MarketManagerStates_init(_initialGov, _feeDistributor, _usd);
    }

    /// @inheritdoc IPSM
    function psmCollateralStates(IERC20 _collateral) external view override returns (CollateralState memory state) {
        state = _psmStorage().collaterals[_collateral];
    }

    /// @inheritdoc IPSM
    function updatePSMCollateralCap(IERC20 _collateral, uint120 _cap) external override {
        _onlyGov();

        _psmStorage().collaterals[_collateral].updatePSMCollateralCap(_collateral, _cap, _statesStorage().usd);
    }

    /// @inheritdoc IPSM
    function psmMintPUSD(
        IERC20 _collateral,
        address _receiver
    ) external override nonReentrantToken(_collateral) returns (uint64 receiveAmount) {
        _onlyPlugin();

        receiveAmount = _psmStorage().collaterals[_collateral].psmMint(_collateral, _receiver, _statesStorage().usd);
    }

    /// @inheritdoc IPSM
    function psmBurnPUSD(
        IERC20 _collateral,
        address _receiver
    ) external override nonReentrantToken(_collateral) returns (uint96 receiveAmount) {
        _onlyPlugin();

        receiveAmount = _psmStorage().collaterals[_collateral].psmBurn(_collateral, _receiver, _statesStorage().usd);
    }

    function _psmStorage() internal pure returns (PSMStorage storage $) {
        // prettier-ignore
        assembly { $.slot := PSM_UPGRADEABLE_STORAGE }
    }
}
