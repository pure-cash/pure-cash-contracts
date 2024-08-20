// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.26;

import "./PositionRouterCommon.sol";
import "../libraries/LiquidityUtil.sol";
import "./interfaces/IPositionRouter2.sol";

contract PositionRouter2 is IPositionRouter2, PositionRouterCommon {
    using SafeCast for uint256;
    using TransferHelper for *;
    using MarketUtil for *;

    constructor(
        Governable _govImpl,
        IPUSD _usd,
        IMarketManager _marketManager,
        IWETHMinimum _weth,
        EstimatedGasLimitType[] memory _estimatedGasLimitTypes,
        uint256[] memory _estimatedGasLimits
    ) PositionRouterCommon(_govImpl, _usd, _marketManager, _weth, _estimatedGasLimitTypes, _estimatedGasLimits) {}

    /// @inheritdoc IPositionRouter2
    function createMintLPT(
        IERC20 _market,
        uint96 _liquidityDelta,
        address _receiver,
        bytes calldata _permitData
    ) external payable override returns (bytes32 id) {
        uint256 minExecutionFee = _estimateGasFees(EstimatedGasLimitType.MintLPT);
        if (msg.value < minExecutionFee) revert InsufficientExecutionFee(msg.value, minExecutionFee);
        _market.safePermit(address(marketManager), _permitData);
        marketManager.pluginTransfer(_market, msg.sender, address(this), _liquidityDelta);
        id = _createMintLPT(
            MintLPTRequestIdParam({
                account: msg.sender,
                market: _market,
                liquidityDelta: _liquidityDelta,
                executionFee: msg.value,
                receiver: _receiver,
                payPUSD: false,
                minReceivedFromBurningPUSD: 0
            })
        );
    }

    /// @inheritdoc IPositionRouter2
    function createMintLPTPayPUSD(
        IERC20 _market,
        uint64 _pusdAmount,
        address _receiver,
        uint96 _minReceivedFromBurningPUSD,
        bytes calldata _permitData
    ) external payable override returns (bytes32 id) {
        uint256 minExecutionFee = _estimateGasFees(EstimatedGasLimitType.MintLPTPayPUSD);
        if (msg.value < minExecutionFee) revert InsufficientExecutionFee(msg.value, minExecutionFee);

        usd.safePermit(address(marketManager), _permitData);
        marketManager.pluginTransfer(usd, msg.sender, address(this), _pusdAmount);

        id = _createMintLPT(
            MintLPTRequestIdParam({
                account: msg.sender,
                market: _market,
                liquidityDelta: _pusdAmount,
                executionFee: msg.value,
                receiver: _receiver,
                payPUSD: true,
                minReceivedFromBurningPUSD: _minReceivedFromBurningPUSD
            })
        );
    }

    /// @inheritdoc IPositionRouter2
    function createMintLPTETH(address _receiver, uint256 _executionFee) external payable override returns (bytes32 id) {
        unchecked {
            _validateExecutionFee(_executionFee, EstimatedGasLimitType.MintLPT);

            uint256 liquidityDelta = msg.value - _executionFee;

            weth.deposit{value: liquidityDelta}();

            id = _createMintLPT(
                MintLPTRequestIdParam({
                    account: msg.sender,
                    market: IERC20(address(weth)),
                    liquidityDelta: liquidityDelta.toUint96(),
                    executionFee: _executionFee,
                    receiver: _receiver,
                    payPUSD: false,
                    minReceivedFromBurningPUSD: 0
                })
            );
        }
    }

    /// @inheritdoc IPositionRouter2
    function cancelMintLPT(
        MintLPTRequestIdParam calldata _param,
        address payable _executionFeeReceiver
    ) external override returns (bool) {
        bytes32 id = _mintLPTRequestId(_param);

        uint256 blockNumber = blockNumbers[id];
        if (blockNumber == 0) return true;

        bool shouldCancel = _shouldCancel(blockNumber, _param.account);
        if (!shouldCancel) return false;

        delete blockNumbers[id];

        if (_param.payPUSD) usd.safeTransfer(_param.account, _param.liquidityDelta);
        else _transferRefund(_param.market, _param.account, _param.liquidityDelta);

        // transfer out execution fee
        _transferOutETH(_param.executionFee, _executionFeeReceiver);

        emit MintLPTCancelled(id, _executionFeeReceiver);

        return true;
    }

    /// @inheritdoc IPositionRouter2
    function executeMintLPT(
        MintLPTRequestIdParam calldata _param,
        address payable _executionFeeReceiver
    ) external override returns (bool) {
        bytes32 id = _mintLPTRequestId(_param);

        uint256 blockNumber = blockNumbers[id];
        if (blockNumber == 0) return true;

        bool shouldExecute = _shouldExecute(blockNumber, _param.account);
        if (!shouldExecute) return false;

        delete blockNumbers[id];

        uint256 executionGasLimit_ = executionGasLimit;
        uint96 liquidityDeltaAfter = _param.liquidityDelta;
        if (_param.payPUSD) {
            (, uint96 receiveAmount) = marketManager.burnPUSD{gas: executionGasLimit_}(
                _param.market,
                true,
                _param.liquidityDelta,
                this,
                abi.encode(CallbackData({margin: _param.liquidityDelta, account: _param.account})),
                address(this)
            );
            if (receiveAmount < _param.minReceivedFromBurningPUSD)
                revert TooLittleReceived(_param.minReceivedFromBurningPUSD, receiveAmount);

            liquidityDeltaAfter = receiveAmount;
        }

        _param.market.safeTransfer(address(marketManager), liquidityDeltaAfter, executionGasLimit_);

        marketManager.mintLPT{gas: executionGasLimit_}(_param.market, _param.account, _param.receiver);

        uint256 actualExecutionFee = _refundExecutionFee(
            _param.payPUSD ? EstimatedGasLimitType.MintLPTPayPUSD : EstimatedGasLimitType.MintLPT,
            _param.executionFee,
            _param.account
        );

        _transferOutETH(actualExecutionFee, _executionFeeReceiver);

        emit MintLPTExecuted(id, _executionFeeReceiver, actualExecutionFee);

        return true;
    }

    /// @inheritdoc IPositionRouter2
    function executeOrCancelMintLPT(
        MintLPTRequestIdParam calldata _param,
        address payable _executionFeeReceiver
    ) external override onlyPositionExecutor {
        try this.executeMintLPT(_param, _executionFeeReceiver) returns (bool _executed) {
            if (!_executed) return;
        } catch (bytes memory reason) {
            bytes4 errorTypeSelector = _decodeShortenedReason(reason);
            emit ExecuteFailed(RequestType.MintLPT, _mintLPTRequestId(_param), errorTypeSelector);
            try this.cancelMintLPT(_param, _executionFeeReceiver) returns (bool _cancelled) {
                if (!_cancelled) return;
            } catch {}
        }
    }

    /// @inheritdoc IPositionRouter2
    function createBurnLPT(
        IERC20 _market,
        uint64 _amount,
        uint96 _acceptableMinLiquidity,
        address _receiver,
        bytes calldata _permitData
    ) external payable override returns (bytes32 id) {
        uint256 minExecutionFee = _estimateGasFees(EstimatedGasLimitType.BurnLPT);
        if (msg.value < minExecutionFee) revert InsufficientExecutionFee(msg.value, minExecutionFee);

        ILPToken lpToken = ILPToken(LiquidityUtil.computeLPTokenAddress(_market, address(marketManager)));
        lpToken.safePermit(address(marketManager), _permitData);
        marketManager.pluginTransfer(lpToken, msg.sender, address(this), uint256(_amount));
        id = _createBurnLPT(
            BurnLPTRequestIdParam({
                account: msg.sender,
                market: _market,
                amount: _amount,
                acceptableMinLiquidity: _acceptableMinLiquidity,
                receiver: _receiver,
                executionFee: msg.value,
                receivePUSD: false,
                minPUSDReceived: 0
            })
        );
    }

    /// @inheritdoc IPositionRouter2
    function createBurnLPTReceivePUSD(
        IERC20 _market,
        uint64 _amount,
        uint64 _minPUSDReceived,
        address _receiver,
        bytes calldata _permitData
    ) external payable override returns (bytes32 id) {
        uint256 minExecutionFee = _estimateGasFees(EstimatedGasLimitType.BurnLPTReceivePUSD);
        if (msg.value < minExecutionFee) revert InsufficientExecutionFee(msg.value, minExecutionFee);

        ILPToken lpToken = ILPToken(LiquidityUtil.computeLPTokenAddress(_market, address(marketManager)));
        lpToken.safePermit(address(marketManager), _permitData);
        marketManager.pluginTransfer(lpToken, msg.sender, address(this), uint256(_amount));
        id = _createBurnLPT(
            BurnLPTRequestIdParam({
                account: msg.sender,
                market: _market,
                amount: _amount,
                acceptableMinLiquidity: 0,
                receiver: _receiver,
                executionFee: msg.value,
                receivePUSD: true,
                minPUSDReceived: _minPUSDReceived
            })
        );
    }

    /// @inheritdoc IPositionRouter2
    function cancelBurnLPT(
        BurnLPTRequestIdParam calldata _param,
        address payable _executionFeeReceiver
    ) external override returns (bool) {
        bytes32 id = _burnLPTRequestId(_param);

        uint256 blockNumber = blockNumbers[id];
        if (blockNumber == 0) return true;

        bool shouldCancel = _shouldCancel(blockNumber, _param.account);
        if (!shouldCancel) return false;

        delete blockNumbers[id];

        ILPToken token = ILPToken(LiquidityUtil.computeLPTokenAddress(_param.market, address(marketManager)));
        token.safeTransfer(_param.account, _param.amount, executionGasLimit);

        _transferOutETH(_param.executionFee, _executionFeeReceiver);

        emit BurnLPTCancelled(id, _executionFeeReceiver);

        return true;
    }

    /// @inheritdoc IPositionRouter2
    function executeBurnLPT(
        BurnLPTRequestIdParam calldata _param,
        address payable _executionFeeReceiver
    ) external override returns (bool) {
        bytes32 id = _burnLPTRequestId(_param);

        uint256 blockNumber = blockNumbers[id];
        if (blockNumber == 0) return true;

        bool shouldExecute = _shouldExecute(blockNumber, _param.account);
        if (!shouldExecute) return false;

        delete blockNumbers[id];

        uint256 executionGasLimit_ = executionGasLimit;

        ILPToken token = ILPToken(LiquidityUtil.computeLPTokenAddress(_param.market, address(marketManager)));
        token.safeTransfer(address(marketManager), _param.amount, executionGasLimit_);

        bool receiveETH = address(weth) == address(_param.market) && !MarketUtil.isDeployedContract(_param.receiver);

        uint96 liquidity = marketManager.burnLPT{gas: executionGasLimit_}(
            _param.market,
            _param.account,
            (_param.receivePUSD || receiveETH) ? address(this) : _param.receiver
        );

        if (_param.receivePUSD) {
            uint64 receiveAmount;
            if (liquidity > 0) {
                (, receiveAmount) = marketManager.mintPUSD{gas: executionGasLimit_}(
                    _param.market,
                    true,
                    liquidity,
                    this,
                    abi.encode(CallbackData({margin: liquidity, account: _param.account})),
                    _param.receiver
                );
            }
            if (receiveAmount < _param.minPUSDReceived) revert TooLittleReceived(_param.minPUSDReceived, receiveAmount);
        } else {
            if (liquidity < _param.acceptableMinLiquidity)
                revert TooLittleReceived(_param.acceptableMinLiquidity, liquidity);
            if (receiveETH && liquidity > 0) {
                weth.withdraw(liquidity);
                _transferOutETH(liquidity, _param.receiver);
            }
        }
        uint256 actualExecutionFee = _refundExecutionFee(
            _param.receivePUSD ? EstimatedGasLimitType.BurnLPTReceivePUSD : EstimatedGasLimitType.BurnLPT,
            _param.executionFee,
            _param.account
        );

        _transferOutETH(actualExecutionFee, _executionFeeReceiver);

        emit BurnLPTExecuted(id, _executionFeeReceiver, actualExecutionFee);
        return true;
    }

    /// @inheritdoc IPositionRouter2
    function executeOrCancelBurnLPT(
        BurnLPTRequestIdParam calldata _param,
        address payable _executionFeeReceiver
    ) external override onlyPositionExecutor {
        try this.executeBurnLPT(_param, _executionFeeReceiver) returns (bool _executed) {
            if (!_executed) return;
        } catch (bytes memory reason) {
            bytes4 errorTypeSelector = _decodeShortenedReason(reason);
            emit ExecuteFailed(RequestType.BurnLPT, _burnLPTRequestId(_param), errorTypeSelector);

            try this.cancelBurnLPT(_param, _executionFeeReceiver) returns (bool _cancelled) {
                if (!_cancelled) return;
            } catch {}
        }
    }

    function _createMintLPT(MintLPTRequestIdParam memory _param) private returns (bytes32 id) {
        id = _mintLPTRequestId(_param);
        _validateRequestConflict(id);
        blockNumbers[id] = block.number;
        emit MintLPTCreated(
            _param.account,
            _param.market,
            _param.liquidityDelta,
            _param.executionFee,
            _param.receiver,
            _param.payPUSD,
            _param.minReceivedFromBurningPUSD,
            id
        );
    }

    function _createBurnLPT(BurnLPTRequestIdParam memory _param) private returns (bytes32 id) {
        id = _burnLPTRequestId(_param);
        _validateRequestConflict(id);
        blockNumbers[id] = block.number;
        emit BurnLPTCreated(
            _param.account,
            _param.market,
            _param.amount,
            _param.acceptableMinLiquidity,
            _param.receiver,
            _param.executionFee,
            _param.receivePUSD,
            _param.minPUSDReceived,
            id
        );
    }

    function _mintLPTRequestId(MintLPTRequestIdParam memory _param) private pure returns (bytes32 id) {
        id = keccak256(abi.encode(_param));
    }

    function _burnLPTRequestId(BurnLPTRequestIdParam memory _param) private pure returns (bytes32 id) {
        id = keccak256(abi.encode(_param));
    }
}
