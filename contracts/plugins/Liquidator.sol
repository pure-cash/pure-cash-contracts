// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.26;

import "../core/MarketManagerUpgradeable.sol";
import "./interfaces/ILiquidator.sol";
import "../governance/GovernableProxy.sol";

contract Liquidator is ILiquidator, GovernableProxy {
    using SafeERC20 for IERC20;

    MarketManagerUpgradeable public immutable marketManager;

    uint256 public executionGasLimit;

    mapping(address => bool) public executors;

    constructor(Governable _govImpl, MarketManagerUpgradeable _marketManager) GovernableProxy(_govImpl) {
        (marketManager, executionGasLimit) = (_marketManager, 1_000_000 wei);
    }

    /// @inheritdoc ILiquidator
    function updateExecutor(address _account, bool _active) external override onlyGov {
        executors[_account] = _active;
        emit ExecutorUpdated(_account, _active);
    }

    /// @inheritdoc ILiquidator
    function updateExecutionGasLimit(uint256 _executionGasLimit) external override onlyGov {
        executionGasLimit = _executionGasLimit;
    }

    /// @inheritdoc ILiquidator
    function liquidatePosition(
        IERC20 _market,
        address payable _account,
        address payable _feeReceiver
    ) external override {
        _onlyExecutor();

        marketManager.liquidatePosition(_market, _account, _feeReceiver);
    }

    function _onlyExecutor() private view {
        if (!executors[msg.sender]) revert Forbidden();
    }
}
