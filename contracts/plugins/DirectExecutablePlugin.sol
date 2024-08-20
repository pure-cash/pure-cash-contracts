// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.26;

import "../IWETHMinimum.sol";
import "../libraries/MarketUtil.sol";
import "../core/interfaces/IPUSD.sol";
import "../governance/GovernableProxy.sol";
import "./interfaces/IDirectExecutablePlugin.sol";
import "@openzeppelin/contracts/utils/Address.sol";

contract DirectExecutablePlugin is IDirectExecutablePlugin, GovernableProxy {
    using MarketUtil for *;

    IPUSD public immutable usd;
    IMarketManager public immutable marketManager;
    IWETHMinimum public immutable weth;

    mapping(address => bool) public override psmMinters;
    mapping(address => bool) public override liquidityBufferDebtPayers;
    bool public override allowAnyoneRepayLiquidityBufferDebt;
    bool public override allowAnyoneUsePSM;

    /// @notice Used to receive ETH withdrawal from the WETH contract
    receive() external payable {
        if (msg.sender != address(weth)) revert IMarketErrors.InvalidCaller(address(weth));
    }

    constructor(
        Governable _govImpl,
        IPUSD _usd,
        IMarketManager _marketManager,
        IWETHMinimum _weth
    ) GovernableProxy(_govImpl) {
        (usd, marketManager, weth) = (_usd, _marketManager, _weth);
    }

    /// @inheritdoc IDirectExecutablePlugin
    function updateLiquidityBufferDebtPayer(address _account, bool _active) external override onlyGov {
        liquidityBufferDebtPayers[_account] = _active;
        emit LiquidityBufferDebtPayerUpdated(_account, _active);
    }

    /// @inheritdoc IDirectExecutablePlugin
    function updateAllowAnyoneRepayLiquidityBufferDebt(bool _allowed) external override onlyGov {
        allowAnyoneRepayLiquidityBufferDebt = _allowed;
    }

    /// @inheritdoc IDirectExecutablePlugin
    function updatePSMMinters(address _account, bool _active) external override onlyGov {
        psmMinters[_account] = _active;
        emit PSMMinterUpdated(_account, _active);
    }

    /// @inheritdoc IDirectExecutablePlugin
    function updateAllowAnyoneUsePSM(bool _allowed) external override onlyGov {
        allowAnyoneUsePSM = _allowed;
    }

    /// @inheritdoc IDirectExecutablePlugin
    function repayLiquidityBufferDebt(
        IERC20 _market,
        uint128 _amount,
        address _receiver,
        bytes calldata _permitData
    ) external override {
        require(liquidityBufferDebtPayers[msg.sender] || allowAnyoneRepayLiquidityBufferDebt, Forbidden());

        IWETHMinimum weth_ = weth;
        IPUSD usd_ = usd;
        IMarketManager marketManager_ = marketManager;
        IMarketManager.LiquidityBufferModule memory lbm = marketManager_.liquidityBufferModules(_market);

        uint256 balance = usd_.balanceOf(address(marketManager_));
        if (_amount > 0 && balance + _amount > lbm.pusdDebt) revert TooMuchRepaid(balance, _amount, lbm.pusdDebt);
        usd_.safePermit(address(marketManager_), _permitData);
        marketManager_.pluginTransfer(usd_, msg.sender, address(marketManager_), _amount);

        if (address(weth_) == address(_market) && !MarketUtil.isDeployedContract(_receiver)) {
            uint128 receiveAmount = marketManager_.repayLiquidityBufferDebt(_market, msg.sender, address(this));

            weth_.withdraw(receiveAmount);
            Address.sendValue(payable(_receiver), receiveAmount);
        } else {
            marketManager_.repayLiquidityBufferDebt(_market, msg.sender, _receiver);
        }
    }

    /// @inheritdoc IDirectExecutablePlugin
    function psmMintPUSD(
        IERC20 _collateral,
        uint120 _amount,
        address _receiver,
        bytes calldata _permitData
    ) external override returns (uint64 receiveAmount) {
        require(psmMinters[msg.sender] || allowAnyoneUsePSM, Forbidden());

        IMarketManager marketManager_ = marketManager;
        IPSM.CollateralState memory state = marketManager_.psmCollateralStates(_collateral);

        uint256 balance = _collateral.balanceOf(address(marketManager_));
        if (_amount > 0 && balance + _amount > state.cap) revert PSMCapExceeded(balance, _amount, state.cap);

        _collateral.safePermit(address(marketManager_), _permitData);
        marketManager_.pluginTransfer(_collateral, msg.sender, address(marketManager_), _amount);
        receiveAmount = marketManager_.psmMintPUSD(_collateral, _receiver);
    }

    /// @inheritdoc IDirectExecutablePlugin
    function psmBurnPUSD(
        IERC20 _collateral,
        uint64 _amount,
        address _receiver,
        bytes calldata _permitData
    ) external override returns (uint96 receiveAmount) {
        IMarketManager marketManager_ = marketManager;
        usd.safePermit(address(marketManager_), _permitData);
        marketManager_.pluginTransfer(usd, msg.sender, address(marketManager_), _amount);
        receiveAmount = marketManager_.psmBurnPUSD(_collateral, _receiver);
    }
}
