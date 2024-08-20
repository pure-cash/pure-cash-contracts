// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.26;

import "./PositionRouterCommon.sol";
import "./interfaces/IPositionRouter.sol";
import {LONG, SHORT} from "../types/Side.sol";
import {M as Math} from "../libraries/Math.sol";

contract PositionRouter is IPositionRouter, PositionRouterCommon {
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

    /// @inheritdoc IPositionRouter
    function createIncreasePosition(
        IERC20 _market,
        uint96 _marginDelta,
        uint96 _sizeDelta,
        uint64 _acceptableIndexPrice,
        bytes calldata _permitData
    ) external payable override returns (bytes32 id) {
        uint256 minExecutionFee = _estimateGasFees(EstimatedGasLimitType.IncreasePosition);
        if (msg.value < minExecutionFee) revert InsufficientExecutionFee(msg.value, minExecutionFee);

        _market.safePermit(address(marketManager), _permitData);
        if (_marginDelta > 0) marketManager.pluginTransfer(_market, msg.sender, address(this), _marginDelta);

        id = _createIncreasePosition(
            IncreasePositionRequestIdParam({
                account: msg.sender,
                market: _market,
                marginDelta: _marginDelta,
                sizeDelta: _sizeDelta,
                acceptableIndexPrice: _acceptableIndexPrice,
                executionFee: msg.value,
                payPUSD: false
            })
        );
    }

    /// @inheritdoc IPositionRouter
    function createIncreasePositionETH(
        uint96 _sizeDelta,
        uint64 _acceptableIndexPrice,
        uint256 _executionFee
    ) external payable override returns (bytes32 id) {
        unchecked {
            _validateExecutionFee(_executionFee, EstimatedGasLimitType.IncreasePosition);

            uint96 marginDelta = (msg.value - _executionFee).toUint96();

            if (marginDelta > 0) weth.deposit{value: marginDelta}();

            id = _createIncreasePosition(
                IncreasePositionRequestIdParam({
                    account: msg.sender,
                    market: IERC20(address(weth)),
                    marginDelta: marginDelta,
                    sizeDelta: _sizeDelta,
                    acceptableIndexPrice: _acceptableIndexPrice,
                    executionFee: _executionFee,
                    payPUSD: false
                })
            );
        }
    }

    /// @inheritdoc IPositionRouter
    function createIncreasePositionPayPUSD(
        IERC20 _market,
        uint64 _pusdAmount,
        uint96 _sizeDelta,
        uint64 _acceptableIndexPrice,
        bytes calldata _permitData
    ) external payable override returns (bytes32 id) {
        uint256 minExecutionFee = _estimateGasFees(EstimatedGasLimitType.IncreasePositionPayPUSD);
        if (msg.value < minExecutionFee) revert InsufficientExecutionFee(msg.value, minExecutionFee);

        usd.safePermit(address(marketManager), _permitData);
        if (_pusdAmount > 0) marketManager.pluginTransfer(usd, msg.sender, address(this), _pusdAmount);

        id = _createIncreasePosition(
            IncreasePositionRequestIdParam({
                account: msg.sender,
                market: _market,
                marginDelta: _pusdAmount,
                sizeDelta: _sizeDelta,
                acceptableIndexPrice: _acceptableIndexPrice,
                executionFee: msg.value,
                payPUSD: true
            })
        );
    }

    /// @inheritdoc IPositionRouter
    function cancelIncreasePosition(
        IncreasePositionRequestIdParam calldata _param,
        address payable _executionFeeReceiver
    ) external override returns (bool) {
        bytes32 id = _increasePositionRequestId(_param);
        uint256 blockNumber = blockNumbers[id];
        if (blockNumber == 0) return true;

        bool shouldCancel = _shouldCancel(blockNumber, _param.account);
        if (!shouldCancel) return false;

        delete blockNumbers[id];

        if (_param.payPUSD) usd.safeTransfer(_param.account, _param.marginDelta);
        else _transferRefund(_param.market, _param.account, _param.marginDelta);

        // transfer out execution fee
        _transferOutETH(_param.executionFee, _executionFeeReceiver);

        emit IncreasePositionCancelled(id, _executionFeeReceiver);

        return true;
    }

    /// @inheritdoc IPositionRouter
    function executeIncreasePosition(
        IncreasePositionRequestIdParam calldata _param,
        address payable _executionFeeReceiver
    ) external override returns (bool) {
        bytes32 id = _increasePositionRequestId(_param);
        uint256 blockNumber = blockNumbers[id];
        if (blockNumber == 0) return true;

        bool shouldExecute = _shouldExecute(blockNumber, _param.account);
        if (!shouldExecute) return false;

        delete blockNumbers[id];

        (, uint64 maxIndexPrice) = marketManager.getPrice(_param.market);
        _validateIndexPrice(LONG, maxIndexPrice, _param.acceptableIndexPrice);

        uint256 executionGasLimit_ = executionGasLimit;
        uint96 _marginDelta = _param.marginDelta;
        if (_param.payPUSD) {
            (, uint96 receiveAmount) = marketManager.burnPUSD{gas: executionGasLimit_}(
                _param.market,
                true,
                _param.marginDelta,
                this,
                abi.encode(CallbackData({margin: _param.marginDelta, account: _param.account})),
                address(this)
            );
            _marginDelta = receiveAmount;
        }

        _param.market.safeTransfer(address(marketManager), _marginDelta, executionGasLimit_);
        marketManager.increasePosition{gas: executionGasLimit_}(_param.market, _param.account, _param.sizeDelta);

        uint256 actualExecutionFee = _refundExecutionFee(
            _param.payPUSD ? EstimatedGasLimitType.IncreasePositionPayPUSD : EstimatedGasLimitType.IncreasePosition,
            _param.executionFee,
            _param.account
        );
        _transferOutETH(actualExecutionFee, _executionFeeReceiver);

        emit IncreasePositionExecuted(id, _executionFeeReceiver, actualExecutionFee);
        return true;
    }

    /// @inheritdoc IPositionRouter
    function executeOrCancelIncreasePosition(
        IncreasePositionRequestIdParam calldata _param,
        address payable _executionFeeReceiver
    ) external override onlyPositionExecutor {
        try this.executeIncreasePosition(_param, _executionFeeReceiver) returns (bool _executed) {
            if (!_executed) return;
        } catch (bytes memory reason) {
            bytes4 errorTypeSelector = _decodeShortenedReason(reason);
            bytes32 id = _increasePositionRequestId(_param);
            emit ExecuteFailed(RequestType.IncreasePosition, id, errorTypeSelector);

            try this.cancelIncreasePosition(_param, _executionFeeReceiver) returns (bool _cancelled) {
                if (!_cancelled) return;
            } catch {}
        }
    }

    /// @inheritdoc IPositionRouter
    function createDecreasePosition(
        IERC20 _market,
        uint96 _marginDelta,
        uint96 _sizeDelta,
        uint64 _acceptableIndexPrice,
        address payable _receiver
    ) external payable override returns (bytes32 id) {
        uint256 minExecutionFee = _estimateGasFees(EstimatedGasLimitType.DecreasePosition);
        if (msg.value < minExecutionFee) revert InsufficientExecutionFee(msg.value, minExecutionFee);

        id = _createDecreasePosition(
            DecreasePositionRequestIdParam({
                account: msg.sender,
                market: _market,
                marginDelta: _marginDelta,
                sizeDelta: _sizeDelta,
                acceptableIndexPrice: _acceptableIndexPrice,
                receiver: _receiver,
                executionFee: msg.value,
                receivePUSD: false
            })
        );
    }

    function createDecreasePositionReceivePUSD(
        IERC20 _market,
        uint96 _marginDelta,
        uint96 _sizeDelta,
        uint64 _acceptableIndexPrice,
        address _receiver
    ) external payable override returns (bytes32 id) {
        uint256 minExecutionFee = _estimateGasFees(EstimatedGasLimitType.DecreasePositionReceivePUSD);
        if (msg.value < minExecutionFee) revert InsufficientExecutionFee(msg.value, minExecutionFee);

        id = _createDecreasePosition(
            DecreasePositionRequestIdParam({
                account: msg.sender,
                market: _market,
                marginDelta: _marginDelta,
                sizeDelta: _sizeDelta,
                acceptableIndexPrice: _acceptableIndexPrice,
                receiver: _receiver,
                executionFee: msg.value,
                receivePUSD: true
            })
        );
    }

    /// @inheritdoc IPositionRouter
    function cancelDecreasePosition(
        DecreasePositionRequestIdParam calldata _param,
        address payable _executionFeeReceiver
    ) external override returns (bool) {
        bytes32 id = _decreasePositionRequestId(_param);
        uint256 blockNumber = blockNumbers[id];
        if (blockNumber == 0) return true;

        bool shouldCancel = _shouldCancel(blockNumber, _param.account);
        if (!shouldCancel) return false;

        delete blockNumbers[id];

        _transferOutETH(_param.executionFee, _executionFeeReceiver);

        emit DecreasePositionCancelled(id, _executionFeeReceiver);

        return true;
    }

    /// @inheritdoc IPositionRouter
    function executeDecreasePosition(
        DecreasePositionRequestIdParam calldata _param,
        address payable _executionFeeReceiver
    ) external override returns (bool) {
        bytes32 id = _decreasePositionRequestId(_param);
        uint256 blockNumber = blockNumbers[id];
        if (blockNumber == 0) return true;

        bool shouldExecute = _shouldExecute(blockNumber, _param.account);
        if (!shouldExecute) return false;

        delete blockNumbers[id];

        bool receiveETH = address(weth) == address(_param.market) && !MarketUtil.isDeployedContract(_param.receiver);

        (uint64 minIndexPrice, ) = marketManager.getPrice(_param.market);
        _validateIndexPrice(SHORT, minIndexPrice, _param.acceptableIndexPrice);

        uint256 executionGasLimit_ = executionGasLimit;
        (, uint96 marginDelta) = marketManager.decreasePosition{gas: executionGasLimit_}(
            _param.market,
            _param.account,
            _param.marginDelta,
            _param.sizeDelta,
            (_param.receivePUSD || receiveETH) ? address(this) : _param.receiver
        );

        if (marginDelta > 0) {
            if (_param.receivePUSD) {
                marketManager.mintPUSD{gas: executionGasLimit_}(
                    _param.market,
                    true,
                    marginDelta,
                    this,
                    abi.encode(CallbackData({margin: marginDelta, account: _param.account})),
                    _param.receiver
                );
            } else if (receiveETH) {
                weth.withdraw(marginDelta);
                _transferOutETH(marginDelta, payable(_param.receiver));
            }
        }

        uint256 actualExecutionFee = _refundExecutionFee(
            _param.receivePUSD
                ? EstimatedGasLimitType.DecreasePositionReceivePUSD
                : EstimatedGasLimitType.DecreasePosition,
            _param.executionFee,
            _param.account
        );
        _transferOutETH(actualExecutionFee, _executionFeeReceiver);

        emit DecreasePositionExecuted(id, _executionFeeReceiver, actualExecutionFee);
        return true;
    }

    /// @inheritdoc IPositionRouter
    function executeOrCancelDecreasePosition(
        DecreasePositionRequestIdParam calldata _param,
        address payable _executionFeeReceiver
    ) external override onlyPositionExecutor {
        try this.executeDecreasePosition(_param, _executionFeeReceiver) returns (bool _executed) {
            if (!_executed) return;
        } catch (bytes memory reason) {
            bytes4 errorTypeSelector = _decodeShortenedReason(reason);
            bytes32 id = _decreasePositionRequestId(_param);
            emit ExecuteFailed(RequestType.DecreasePosition, id, errorTypeSelector);

            try this.cancelDecreasePosition(_param, _executionFeeReceiver) returns (bool _cancelled) {
                if (!_cancelled) return;
            } catch {}
        }
    }

    /// @inheritdoc IPositionRouter
    function createMintPUSD(
        IERC20 _market,
        bool _exactIn,
        uint96 _acceptableMaxPayAmount,
        uint64 _acceptableMinReceiveAmount,
        address _receiver,
        bytes calldata _permitData
    ) external payable override returns (bytes32 id) {
        uint256 minExecutionFee = _estimateGasFees(EstimatedGasLimitType.MintPUSD);
        if (msg.value < minExecutionFee) revert InsufficientExecutionFee(msg.value, minExecutionFee);

        _market.safePermit(address(marketManager), _permitData);
        marketManager.pluginTransfer(_market, msg.sender, address(this), _acceptableMaxPayAmount);

        id = _createMintPUSD(
            MintPUSDRequestIdParam({
                account: msg.sender,
                market: _market,
                exactIn: _exactIn,
                acceptableMaxPayAmount: _acceptableMaxPayAmount,
                acceptableMinReceiveAmount: _acceptableMinReceiveAmount,
                receiver: _receiver,
                executionFee: msg.value
            })
        );
    }

    /// @inheritdoc IPositionRouter
    function createMintPUSDETH(
        bool _exactIn,
        uint64 _acceptableMinReceiveAmount,
        address _receiver,
        uint256 _executionFee
    ) external payable override returns (bytes32 id) {
        unchecked {
            _validateExecutionFee(_executionFee, EstimatedGasLimitType.MintPUSD);

            uint256 acceptableMaxPayAmount = msg.value - _executionFee;
            weth.deposit{value: acceptableMaxPayAmount}();

            id = _createMintPUSD(
                MintPUSDRequestIdParam({
                    account: msg.sender,
                    market: IERC20(address(weth)),
                    exactIn: _exactIn,
                    acceptableMaxPayAmount: acceptableMaxPayAmount.toUint96(),
                    acceptableMinReceiveAmount: _acceptableMinReceiveAmount,
                    receiver: _receiver,
                    executionFee: _executionFee
                })
            );
        }
    }

    /// @inheritdoc IPositionRouter
    function cancelMintPUSD(
        MintPUSDRequestIdParam calldata _param,
        address payable _executionFeeReceiver
    ) external override returns (bool cancelled) {
        bytes32 id = _mintPUSDRequestId(_param);
        uint256 blockNumber = blockNumbers[id];
        if (blockNumber == 0) return true;

        bool shouldCancel = _shouldCancel(blockNumber, _param.account);
        if (!shouldCancel) return false;

        delete blockNumbers[id];

        _transferRefund(_param.market, _param.account, _param.acceptableMaxPayAmount);

        // transfer out execution fee
        _transferOutETH(_param.executionFee, _executionFeeReceiver);

        emit MintPUSDCancelled(id, _executionFeeReceiver);

        return true;
    }

    /// @inheritdoc IPositionRouter
    function executeMintPUSD(
        MintPUSDRequestIdParam calldata _param,
        address payable _executionFeeReceiver
    ) external override returns (bool executed) {
        bytes32 id = _mintPUSDRequestId(_param);
        uint256 blockNumber = blockNumbers[id];
        if (blockNumber == 0) return true;

        bool shouldExecute = _shouldExecute(blockNumber, _param.account);
        if (!shouldExecute) return false;

        delete blockNumbers[id];

        (, uint64 receiveAmount) = marketManager.mintPUSD{gas: executionGasLimit}(
            _param.market,
            _param.exactIn,
            _param.exactIn ? _param.acceptableMaxPayAmount : _param.acceptableMinReceiveAmount,
            this,
            abi.encode(CallbackData({margin: _param.acceptableMaxPayAmount, account: _param.account})),
            _param.receiver
        );
        if (receiveAmount < _param.acceptableMinReceiveAmount)
            revert TooLittleReceived(_param.acceptableMinReceiveAmount, receiveAmount);

        uint256 actualExecutionFee = _refundExecutionFee(
            EstimatedGasLimitType.MintPUSD,
            _param.executionFee,
            _param.account
        );
        _transferOutETH(actualExecutionFee, _executionFeeReceiver);

        emit MintPUSDExecuted(id, _executionFeeReceiver, actualExecutionFee);
        return true;
    }

    /// @inheritdoc IPositionRouter
    function executeOrCancelMintPUSD(
        MintPUSDRequestIdParam calldata _param,
        address payable _executionFeeReceiver
    ) external override onlyPositionExecutor {
        try this.executeMintPUSD(_param, _executionFeeReceiver) returns (bool _executed) {
            if (!_executed) return;
        } catch (bytes memory reason) {
            bytes4 errorTypeSelector = _decodeShortenedReason(reason);
            bytes32 id = _mintPUSDRequestId(_param);
            emit ExecuteFailed(RequestType.Mint, id, errorTypeSelector);

            try this.cancelMintPUSD(_param, _executionFeeReceiver) returns (bool _cancelled) {
                if (!_cancelled) return;
            } catch {}
        }
    }

    /// @inheritdoc IPositionRouter
    function createBurnPUSD(
        IERC20 _market,
        bool _exactIn,
        uint64 _acceptableMaxPayAmount,
        uint96 _acceptableMinReceiveAmount,
        address _receiver,
        bytes calldata _permitData
    ) external payable override returns (bytes32 id) {
        uint256 minExecutionFee = _estimateGasFees(EstimatedGasLimitType.BurnPUSD);
        if (msg.value < minExecutionFee) revert InsufficientExecutionFee(msg.value, minExecutionFee);

        usd.safePermit(address(marketManager), _permitData);
        marketManager.pluginTransfer(usd, msg.sender, address(this), _acceptableMaxPayAmount);

        id = _burnPUSDRequestId(
            BurnPUSDRequestIdParam({
                account: msg.sender,
                market: _market,
                exactIn: _exactIn,
                acceptableMaxPayAmount: _acceptableMaxPayAmount,
                acceptableMinReceiveAmount: _acceptableMinReceiveAmount,
                receiver: _receiver,
                executionFee: msg.value
            })
        );
        _validateRequestConflict(id);
        blockNumbers[id] = block.number;

        emit BurnPUSDCreated(
            msg.sender,
            _market,
            _exactIn,
            _acceptableMaxPayAmount,
            _acceptableMinReceiveAmount,
            _receiver,
            msg.value,
            id
        );
    }

    /// @inheritdoc IPositionRouter
    function cancelBurnPUSD(
        BurnPUSDRequestIdParam calldata _param,
        address payable _executionFeeReceiver
    ) external override returns (bool cancelled) {
        bytes32 id = _burnPUSDRequestId(_param);
        uint256 blockNumber = blockNumbers[id];
        if (blockNumber == 0) return true;

        bool shouldCancel = _shouldCancel(blockNumber, _param.account);
        if (!shouldCancel) return false;

        delete blockNumbers[id];

        usd.safeTransfer(_param.account, _param.acceptableMaxPayAmount);

        _transferOutETH(_param.executionFee, _executionFeeReceiver);

        emit BurnPUSDCancelled(id, _executionFeeReceiver);

        return true;
    }

    function executeBurnPUSD(
        BurnPUSDRequestIdParam calldata _param,
        address payable _executionFeeReceiver
    ) external override returns (bool executed) {
        bytes32 id = _burnPUSDRequestId(_param);
        uint256 blockNumber = blockNumbers[id];
        if (blockNumber == 0) return true;

        bool shouldExecute = _shouldExecute(blockNumber, _param.account);
        if (!shouldExecute) return false;

        delete blockNumbers[id];

        uint256 executionGasLimit_ = executionGasLimit;
        uint96 receiveAmount;
        uint96 amount = _param.exactIn ? _param.acceptableMaxPayAmount : _param.acceptableMinReceiveAmount;
        if (address(weth) == address(_param.market) && !MarketUtil.isDeployedContract(_param.receiver)) {
            (, receiveAmount) = marketManager.burnPUSD{gas: executionGasLimit_}(
                _param.market,
                _param.exactIn,
                amount,
                this,
                abi.encode(CallbackData({margin: _param.acceptableMaxPayAmount, account: _param.account})),
                address(this)
            );

            weth.withdraw(receiveAmount);
            _transferOutETH(receiveAmount, _param.receiver);
        } else {
            (, receiveAmount) = marketManager.burnPUSD{gas: executionGasLimit_}(
                _param.market,
                _param.exactIn,
                amount,
                this,
                abi.encode(CallbackData({margin: _param.acceptableMaxPayAmount, account: _param.account})),
                _param.receiver
            );
        }

        if (receiveAmount < _param.acceptableMinReceiveAmount)
            revert TooLittleReceived(_param.acceptableMinReceiveAmount, receiveAmount);

        uint256 actualExecutionFee = _refundExecutionFee(
            EstimatedGasLimitType.BurnPUSD,
            _param.executionFee,
            _param.account
        );

        _transferOutETH(actualExecutionFee, _executionFeeReceiver);

        emit BurnPUSDExecuted(id, _executionFeeReceiver, actualExecutionFee);
        return true;
    }

    /// @inheritdoc IPositionRouter
    function executeOrCancelBurnPUSD(
        BurnPUSDRequestIdParam calldata _param,
        address payable _executionFeeReceiver
    ) external override onlyPositionExecutor {
        try this.executeBurnPUSD(_param, _executionFeeReceiver) returns (bool _executed) {
            if (!_executed) return;
        } catch (bytes memory reason) {
            bytes4 errorTypeSelector = _decodeShortenedReason(reason);
            bytes32 id = _burnPUSDRequestId(_param);
            emit ExecuteFailed(RequestType.Burn, id, errorTypeSelector);

            try this.cancelBurnPUSD(_param, _executionFeeReceiver) returns (bool _cancelled) {
                if (!_cancelled) return;
            } catch {}
        }
    }

    function _createIncreasePosition(IncreasePositionRequestIdParam memory _param) private returns (bytes32 id) {
        id = _increasePositionRequestId(_param);
        _validateRequestConflict(id);
        blockNumbers[id] = block.number;

        emit IncreasePositionCreated(
            _param.account,
            _param.market,
            _param.marginDelta,
            _param.sizeDelta,
            _param.acceptableIndexPrice,
            _param.executionFee,
            _param.payPUSD,
            id
        );
    }

    function _createDecreasePosition(DecreasePositionRequestIdParam memory _param) private returns (bytes32 id) {
        id = _decreasePositionRequestId(_param);
        _validateRequestConflict(id);
        blockNumbers[id] = block.number;

        emit DecreasePositionCreated(
            _param.account,
            _param.market,
            _param.marginDelta,
            _param.sizeDelta,
            _param.acceptableIndexPrice,
            _param.receiver,
            _param.executionFee,
            _param.receivePUSD,
            id
        );
    }

    function _createMintPUSD(MintPUSDRequestIdParam memory _param) private returns (bytes32 id) {
        id = _mintPUSDRequestId(_param);
        _validateRequestConflict(id);
        blockNumbers[id] = block.number;

        emit MintPUSDCreated(
            _param.account,
            _param.market,
            _param.exactIn,
            _param.acceptableMaxPayAmount,
            _param.acceptableMinReceiveAmount,
            _param.receiver,
            _param.executionFee,
            id
        );
    }

    function _increasePositionRequestId(
        IncreasePositionRequestIdParam memory _param
    ) private pure returns (bytes32 id) {
        return keccak256(abi.encode(_param));
    }

    function _decreasePositionRequestId(
        DecreasePositionRequestIdParam memory _param
    ) private pure returns (bytes32 id) {
        return keccak256(abi.encode(_param));
    }

    function _mintPUSDRequestId(MintPUSDRequestIdParam memory _param) private pure returns (bytes32 id) {
        return keccak256(abi.encode(_param));
    }

    function _burnPUSDRequestId(BurnPUSDRequestIdParam memory _param) private pure returns (bytes32 id) {
        return keccak256(abi.encode(_param));
    }
}
