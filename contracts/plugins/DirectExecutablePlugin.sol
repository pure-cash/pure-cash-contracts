// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.26;

import "../IWETHMinimum.sol";
import "../libraries/MarketUtil.sol";
import "../libraries/PUSDManagerUtil.sol";
import "../governance/GovernableProxy.sol";
import "./interfaces/IDirectExecutablePlugin.sol";
import "@openzeppelin/contracts/utils/Address.sol";

contract DirectExecutablePlugin is IDirectExecutablePlugin, GovernableProxy {
    using MarketUtil for *;

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

    constructor(Governable _govImpl, IMarketManager _marketManager, IWETHMinimum _weth) GovernableProxy(_govImpl) {
        (marketManager, weth) = (_marketManager, _weth);
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

        IPUSD usd = IPUSD(PUSDManagerUtil.computePUSDAddress(address(marketManager)));
        IMarketManager.LiquidityBufferModule memory lbm = marketManager.liquidityBufferModules(_market);

        uint256 balance = usd.balanceOf(address(marketManager));
        if (_amount > 0 && balance + _amount > lbm.pusdDebt) revert TooMuchRepaid(balance, _amount, lbm.pusdDebt);
        usd.safePermit(address(marketManager), _permitData);
        marketManager.pluginTransfer(usd, msg.sender, address(marketManager), _amount);

        if (address(weth) == address(_market) && !MarketUtil.isDeployedContract(_receiver)) {
            uint128 receiveAmount = marketManager.repayLiquidityBufferDebt(_market, msg.sender, address(this));

            weth.withdraw(receiveAmount);
            Address.sendValue(payable(_receiver), receiveAmount);
        } else {
            marketManager.repayLiquidityBufferDebt(_market, msg.sender, _receiver);
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

        IPSM.CollateralState memory state = marketManager.psmCollateralStates(_collateral);

        uint256 balance = _collateral.balanceOf(address(marketManager));
        if (_amount > 0 && balance + _amount > state.cap) revert PSMCapExceeded(balance, _amount, state.cap);

        _collateral.safePermit(address(marketManager), _permitData);
        marketManager.pluginTransfer(_collateral, msg.sender, address(marketManager), _amount);
        receiveAmount = marketManager.psmMintPUSD(_collateral, _receiver);
    }

    /// @inheritdoc IDirectExecutablePlugin
    function psmBurnPUSD(
        IERC20 _collateral,
        uint64 _amount,
        address _receiver,
        bytes calldata _permitData
    ) external override returns (uint96 receiveAmount) {
        IERC20 usd = IERC20(PUSDManagerUtil.computePUSDAddress(address(marketManager)));
        usd.safePermit(address(marketManager), _permitData);
        marketManager.pluginTransfer(usd, msg.sender, address(marketManager), _amount);
        receiveAmount = marketManager.psmBurnPUSD(_collateral, _receiver);
    }
}
