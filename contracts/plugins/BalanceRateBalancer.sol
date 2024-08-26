// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.26;

import "./interfaces/IBalanceRateBalancer.sol";
import "./PositionRouterCommon.sol";
import "./interfaces/IDirectExecutablePlugin.sol";

contract BalanceRateBalancer is IBalanceRateBalancer, PositionRouterCommon {
    IDirectExecutablePlugin public immutable plugin;

    struct SwapCallbackData {
        IERC20 collateral;
        address[] targets;
        bytes[] calldatas;
    }

    constructor(
        Governable _govImpl,
        IMarketManager _marketManager,
        IDirectExecutablePlugin _plugin,
        EstimatedGasLimitType[] memory _estimatedGasLimitTypes,
        uint256[] memory _estimatedGasLimits
    )
        PositionRouterCommon(
            _govImpl,
            _marketManager,
            IWETHMinimum(address(0)),
            _estimatedGasLimitTypes,
            _estimatedGasLimits
        )
    {
        plugin = _plugin;
    }

    function createIncreaseBalanceRate(
        IERC20 _market,
        IERC20 _collateral,
        uint96 _amount,
        address[] calldata _targets,
        bytes[] calldata _calldatas
    ) public payable onlyGov returns (bytes32 id) {
        uint256 minExecutionFee = _estimateGasFees(EstimatedGasLimitType.IncreaseBalanceRate);
        if (msg.value < minExecutionFee) revert InsufficientExecutionFee(msg.value, minExecutionFee);
        if (_targets.length != _calldatas.length) revert InvalidCallbackData();

        id = _createIncreaseBalanceRate(
            IncreaseBalanceRateRequestIdParam({
                market: _market,
                collateral: _collateral,
                amount: _amount,
                executionFee: msg.value,
                account: msg.sender,
                targets: _targets,
                calldatas: _calldatas
            })
        );
    }

    function cancelIncreaseBalanceRate(
        IncreaseBalanceRateRequestIdParam calldata _param,
        address payable _executionFeeReceiver
    ) public onlyPositionExecutor returns (bool) {
        bytes32 id = _increaseBalanceRateId(_param);
        uint256 blockNumber = blockNumbers[id];
        if (blockNumber == 0) return true;

        bool shouldCancel = _shouldCancel(blockNumber, _param.account);
        if (!shouldCancel) return false;

        delete blockNumbers[id];

        _transferOutETH(_param.executionFee, _executionFeeReceiver);
        emit IncreaseBalanceRateCancelled(id, _executionFeeReceiver);

        return true;
    }

    function executeIncreaseBalanceRate(
        IncreaseBalanceRateRequestIdParam calldata _param,
        address payable _executionFeeReceiver
    ) public onlyPositionExecutor returns (bool) {
        bytes32 id = _increaseBalanceRateId(_param);
        uint256 blockNumber = blockNumbers[id];
        if (blockNumber == 0) return true;

        bool shouldExecute = _shouldExecute(blockNumber, _param.account);
        if (!shouldExecute) return false;

        delete blockNumbers[id];

        uint256 executionGasLimit_ = executionGasLimit;
        marketManager.burnPUSD{gas: executionGasLimit_}(
            _param.market,
            true,
            _param.amount,
            this,
            abi.encode(
                SwapCallbackData({targets: _param.targets, calldatas: _param.calldatas, collateral: _param.collateral})
            ),
            address(this)
        );

        uint256 actualExecutionFee = _refundExecutionFee(
            EstimatedGasLimitType.IncreaseBalanceRate,
            _param.executionFee,
            _param.account
        );
        _transferOutETH(actualExecutionFee, _executionFeeReceiver);

        emit IncreaseBalanceRateExecuted(id, _executionFeeReceiver, actualExecutionFee);
        return true;
    }

    function executeOrCancelIncreaseBalanceRate(
        IncreaseBalanceRateRequestIdParam calldata _param,
        bool _shouldCancelOnFail,
        address payable _executionFeeReceiver
    ) public onlyPositionExecutor {
        try this.executeIncreaseBalanceRate(_param, _executionFeeReceiver) returns (bool _executed) {
            if (!_executed) return;
        } catch (bytes memory reason) {
            bytes4 errorTypeSelector = _decodeShortenedReason(reason);
            bytes32 id = _increaseBalanceRateId(_param);
            emit ExecuteFailed(id, errorTypeSelector);

            if (_shouldCancelOnFail) {
                try this.cancelIncreaseBalanceRate(_param, _executionFeeReceiver) returns (bool _cancelled) {
                    if (!_cancelled) return;
                } catch {}
            }
        }
    }

    function PUSDManagerCallback(
        IERC20 /* _payToken */,
        // burn pusd amount
        uint96 _payAmount,
        uint96 /* _receiveAmount */,
        bytes calldata _data
    ) external override(PositionRouterCommon, IPUSDManagerCallback) {
        if (msg.sender != address(marketManager)) revert InvalidCaller(msg.sender);

        /**
        e.g. call PUSDManagerCallback, exchange from market token to pusd by curve exchange
        step1. approve market token to curve: calldatas[0] => abi.encodeWithSelector(IERC20.approve.selector, curve address, amount)
        // exchange(_route: address[], _swap_params: uint256[][], _amount: uint256, _min_dy: uint256, _pools: address[]=empty(address[]), _receiver: address=msg.sender)
        step2. swap: calldatas[1] => abi.encodeWithSelector(ICurve.exchange.selector, params)
        step3. approve dai to marketManager(optional): calldatas[2] => abi.encodeWithSelector(IERC20.approve.selector, marketManager address, amount)
        */
        SwapCallbackData memory data = abi.decode(_data, (SwapCallbackData));
        for (uint256 i; i < data.targets.length; i++) {
            Address.functionCall(data.targets[i], data.calldatas[i]);
        }
        plugin.psmMintPUSD(
            data.collateral,
            PositionUtil.calcMarketTokenValue(
                _payAmount,
                Constants.PRICE_1,
                marketManager.psmCollateralStates(data.collateral).decimals
            ),
            address(marketManager),
            ""
        );
    }

    function _createIncreaseBalanceRate(IncreaseBalanceRateRequestIdParam memory _param) private returns (bytes32 id) {
        id = _increaseBalanceRateId(_param);
        _validateRequestConflict(id);
        blockNumbers[id] = block.number;

        emit IncreaseBalanceRateCreated(
            _param.market,
            _param.collateral,
            _param.amount,
            _param.executionFee,
            _param.account,
            _param.targets,
            _param.calldatas,
            id
        );
    }

    function _increaseBalanceRateId(IncreaseBalanceRateRequestIdParam memory _param) private pure returns (bytes32 id) {
        return keccak256(abi.encode(_param));
    }
}
