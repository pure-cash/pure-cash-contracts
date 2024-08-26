// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.26;

import "../IWETHMinimum.sol";
import "../libraries/MarketUtil.sol";
import "../libraries/PositionUtil.sol";
import "../libraries/TransferHelper.sol";
import "../governance/GovernableProxy.sol";
import "./interfaces/IPositionRouterCommon.sol";

abstract contract PositionRouterCommon is IPositionRouterCommon, GovernableProxy {
    using TransferHelper for *;

    IMarketManager public immutable marketManager;
    IWETHMinimum public immutable weth;

    mapping(EstimatedGasLimitType => uint256) public estimatedGasLimits;

    // pack into a single slot to save gas
    uint32 public minBlockDelayExecutor;
    uint32 public minBlockDelayPublic;
    uint32 public maxBlockDelay;
    uint32 public executionGasLimit;
    uint24 public estimatedGasFeeMultiplier = Constants.BASIS_POINTS_DIVISOR;
    uint24 public executionGasFeeMultiplier = Constants.BASIS_POINTS_DIVISOR;
    uint32 public etherTransferGasLimit = 10000 wei;

    mapping(address => bool) public positionExecutors;

    mapping(bytes32 id => uint256 blockNumber) public blockNumbers;

    modifier onlyPositionExecutor() {
        if (!positionExecutors[msg.sender]) revert Forbidden();
        _;
    }

    /// @notice Used to receive ETH withdrawal from the WETH contract
    receive() external payable {
        if (msg.sender != address(weth)) revert IMarketErrors.InvalidCaller(address(weth));
    }

    constructor(
        Governable _govImpl,
        IMarketManager _marketManager,
        IWETHMinimum _weth,
        EstimatedGasLimitType[] memory _estimatedGasLimitTypes,
        uint256[] memory _estimatedGasLimits
    ) GovernableProxy(_govImpl) {
        marketManager = _marketManager;
        weth = _weth;
        minBlockDelayPublic = 50; // 10 minutes
        maxBlockDelay = 300; // 60 minutes
        executionGasLimit = 1_000_000 wei;
        for (uint256 i; i < _estimatedGasLimitTypes.length; ++i) {
            estimatedGasLimits[_estimatedGasLimitTypes[i]] = _estimatedGasLimits[i];
            emit EstimatedGasLimitUpdated(_estimatedGasLimitTypes[i], _estimatedGasLimits[i]);
        }
    }

    /// @inheritdoc IPositionRouterCommon
    function updatePositionExecutor(address _account, bool _active) external override onlyGov {
        positionExecutors[_account] = _active;
        emit PositionExecutorUpdated(_account, _active);
    }

    /// @inheritdoc IPositionRouterCommon
    function updateDelayValues(
        uint32 _minBlockDelayExecutor,
        uint32 _minBlockDelayPublic,
        uint32 _maxBlockDelay
    ) external override onlyGov {
        minBlockDelayExecutor = _minBlockDelayExecutor;
        minBlockDelayPublic = _minBlockDelayPublic;
        maxBlockDelay = _maxBlockDelay;
        emit DelayValuesUpdated(_minBlockDelayExecutor, _minBlockDelayPublic, _maxBlockDelay);
    }

    /// @inheritdoc IPositionRouterCommon
    function updateEstimatedGasFeeMultiplier(uint24 _multiplier) external override onlyGov {
        estimatedGasFeeMultiplier = _multiplier;
        emit EstimatedGasFeeMultiplierUpdated(_multiplier);
    }

    /// @inheritdoc IPositionRouterCommon
    function updateExecutionGasFeeMultiplier(uint24 _multiplier) external override onlyGov {
        executionGasFeeMultiplier = _multiplier;
        emit ExecutionGasFeeMultiplierUpdated(_multiplier);
    }

    /// @inheritdoc IPositionRouterCommon
    function updateEstimatedGasLimit(
        EstimatedGasLimitType _estimatedGasLimitType,
        uint256 _estimatedGasLimit
    ) external override onlyGov {
        estimatedGasLimits[_estimatedGasLimitType] = _estimatedGasLimit;
        emit EstimatedGasLimitUpdated(_estimatedGasLimitType, _estimatedGasLimit);
    }

    /// @inheritdoc IPositionRouterCommon
    function updateExecutionGasLimit(uint32 _executionGasLimit) external override onlyGov {
        executionGasLimit = _executionGasLimit;
    }

    /// @inheritdoc IPositionRouterCommon
    function updateEtherTransferGasLimit(uint32 _etherTransferGasLimit) external override onlyGov {
        etherTransferGasLimit = _etherTransferGasLimit;
    }

    /// @inheritdoc IPUSDManagerCallback
    function PUSDManagerCallback(
        IERC20 _payToken,
        uint96 _payAmount,
        uint96 /* _receiveAmount */,
        bytes calldata _data
    ) external virtual override {
        if (msg.sender != address(marketManager)) revert Forbidden();

        CallbackData memory data = abi.decode(_data, (CallbackData));
        if (_payAmount > data.margin) revert TooMuchPaid(_payAmount, data.margin);

        unchecked {
            // transfer remaining margin back to the account
            uint96 remaining = data.margin - _payAmount;
            if (remaining > 0) _transferRefund(_payToken, data.account, remaining);
        }

        // transfer pay token to the market manager
        _payToken.safeTransfer(msg.sender, _payAmount);
    }

    // validation
    function _shouldCancel(uint256 _positionBlockNumber, address _account) internal view returns (bool) {
        return _shouldExecuteOrCancel(_positionBlockNumber, _account);
    }

    function _shouldExecute(uint256 _positionBlockNumber, address _account) internal view returns (bool) {
        uint32 _maxBlockDelay = maxBlockDelay;
        unchecked {
            // overflow is desired
            if (_positionBlockNumber + _maxBlockDelay <= block.number)
                revert Expired(_positionBlockNumber + _maxBlockDelay);
        }
        return _shouldExecuteOrCancel(_positionBlockNumber, _account);
    }

    function _shouldExecuteOrCancel(uint256 _positionBlockNumber, address _account) internal view returns (bool) {
        bool isExecutorCall = msg.sender == address(this) || positionExecutors[msg.sender];

        unchecked {
            // overflow is desired
            if (isExecutorCall) return _positionBlockNumber + minBlockDelayExecutor <= block.number;

            if (msg.sender != _account) revert Forbidden();

            if (_positionBlockNumber + minBlockDelayPublic > block.number)
                revert TooEarly(_positionBlockNumber + minBlockDelayPublic);
        }

        return true;
    }

    function _validateIndexPrice(Side _side, uint64 _indexPrice, uint64 _acceptableIndexPrice) internal pure {
        // long makes price up, short makes price down
        if (
            (_side.isLong() && (_indexPrice > _acceptableIndexPrice)) ||
            (_side.isShort() && (_indexPrice < _acceptableIndexPrice))
        ) revert InvalidIndexPrice(_indexPrice, _acceptableIndexPrice);
    }

    function _decodeShortenedReason(bytes memory _reason) internal pure virtual returns (bytes4) {
        return bytes4(_reason);
    }

    function _transferOutETH(uint256 _amountOut, address _receiver) internal {
        MarketUtil.transferOutETH(payable(_receiver), _amountOut, etherTransferGasLimit);
    }

    function _validateExecutionFee(uint256 _executionFee, EstimatedGasLimitType _estimatedGasLimitType) internal view {
        if (msg.value < _executionFee) revert InsufficientExecutionFee(msg.value, _executionFee);
        uint256 minExecutionFee = _estimateGasFees(_estimatedGasLimitType);
        if (_executionFee < minExecutionFee) revert InsufficientExecutionFee(_executionFee, minExecutionFee);
    }

    function _estimateGasFees(EstimatedGasLimitType _type) internal view returns (uint256 fee) {
        unchecked {
            fee = Math.ceilDiv(
                tx.gasprice * estimatedGasLimits[_type] * estimatedGasFeeMultiplier,
                Constants.BASIS_POINTS_DIVISOR
            );
        }
    }

    function _executionGasFees(EstimatedGasLimitType _type) internal view returns (uint256 fee) {
        unchecked {
            fee = Math.ceilDiv(
                tx.gasprice * estimatedGasLimits[_type] * executionGasFeeMultiplier,
                Constants.BASIS_POINTS_DIVISOR
            );
        }
    }

    function _refundExecutionFee(
        EstimatedGasLimitType _type,
        uint256 _executionFeePaid,
        address receiver
    ) internal returns (uint256 actualExecutionFee) {
        actualExecutionFee = _executionGasFees(_type);
        if (_executionFeePaid <= actualExecutionFee) {
            actualExecutionFee = _executionFeePaid;
        } else {
            // prettier-ignore
            unchecked { _transferOutETH(_executionFeePaid - actualExecutionFee, receiver); }
        }
    }

    function _transferRefund(IERC20 _market, address _account, uint128 _refund) internal {
        if (address(weth) == address(_market) && !MarketUtil.isDeployedContract(_account)) {
            weth.withdraw(_refund);
            MarketUtil.transferOutETH(payable(_account), _refund, etherTransferGasLimit);
        } else {
            _market.safeTransfer(_account, _refund, executionGasLimit);
        }
    }

    function _validateRequestConflict(bytes32 _id) internal view {
        require(blockNumbers[_id] == 0, ConflictRequests(_id));
    }
}
