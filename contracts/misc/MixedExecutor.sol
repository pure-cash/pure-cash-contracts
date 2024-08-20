// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.26;

import "../types/PackedValue.sol";
import "../core/interfaces/IMarketManager.sol";
import "../plugins/interfaces/ILiquidator.sol";
import "../plugins/interfaces/IPositionRouter.sol";
import "../plugins/interfaces/IPositionRouter2.sol";
import "../governance/GovernableProxy.sol";
import "@openzeppelin/contracts/utils/Multicall.sol";
import "../plugins/interfaces/IBalanceRateBalancer.sol";

/// @notice MixedExecutor is a contract that executes multiple calls in a single transaction
contract MixedExecutor is Multicall, GovernableProxy {
    /// @notice The address of liquidator
    ILiquidator public immutable liquidator;
    /// @notice The address of position router
    IPositionRouter public immutable positionRouter;
    /// @notice The address of position router2
    IPositionRouter2 public immutable positionRouter2;
    /// @notice The address of market manager
    IMarketManager public immutable marketManager;
    /// @notice The address of balance rate balancer
    IBalanceRateBalancer public immutable balanceRateBalancer;

    /// @notice The executors
    mapping(address => bool) public executors;

    /// @notice Emitted when an executor is updated
    /// @param executor The address of executor to update
    /// @param active Updated status
    event ExecutorUpdated(address indexed executor, bool indexed active);

    /// @notice Emitted when the position liquidate failed
    /// @dev The event is emitted when the liquidate is failed after the execution error
    /// @param market The target market contract address, such as the contract address of WETH
    /// @param account The address of account
    /// @param shortenedReason The shortened reason of the execution error
    event LiquidatePositionFailed(IERC20 indexed market, address indexed account, bytes4 shortenedReason);

    /// @notice Error thrown when the execution error and `requireSuccess` is set to true
    error ExecutionFailed(bytes reason);

    modifier onlyExecutor() {
        if (!executors[msg.sender]) revert Forbidden();
        _;
    }

    constructor(
        Governable _govImpl,
        ILiquidator _liquidator,
        IPositionRouter _positionRouter,
        IPositionRouter2 _positionRouter2,
        IMarketManager _marketManager,
        IBalanceRateBalancer _balanceRateBalancer
    ) GovernableProxy(_govImpl) {
        (liquidator, positionRouter, positionRouter2) = (_liquidator, _positionRouter, _positionRouter2);
        marketManager = _marketManager;
        balanceRateBalancer = _balanceRateBalancer;
    }

    /// @notice Set executor status active or not
    /// @param _executor Executor address
    /// @param _active Status of executor permission to set
    function setExecutor(address _executor, bool _active) external virtual onlyGov {
        executors[_executor] = _active;
        emit ExecutorUpdated(_executor, _active);
    }

    /// @notice Update price
    function updatePrice(PackedValue _packedValue) external virtual onlyExecutor {
        marketManager.updatePrice(_packedValue);
    }

    /// @notice Try to execute mint LP token request. If the request is not executable, cancel it.
    /// @param _param The mint LPT request id calculation param
    function executeOrCancelMintLPT(
        IPositionRouter2.MintLPTRequestIdParam calldata _param
    ) external virtual onlyExecutor {
        positionRouter2.executeOrCancelMintLPT(_param, payable(msg.sender));
    }

    /// @notice Try to execute burn LP token request. If the request is not executable, cancel it.
    /// @param _param The burn LPT request id calculation param
    function executeOrCancelBurnLPT(
        IPositionRouter2.BurnLPTRequestIdParam calldata _param
    ) external virtual onlyExecutor {
        positionRouter2.executeOrCancelBurnLPT(_param, payable(msg.sender));
    }

    /// @notice Try to execute increase position request. If the request is not executable, cancel it.
    /// @param _param The increase position request id calculation param
    function executeOrCancelIncreasePosition(
        IPositionRouter.IncreasePositionRequestIdParam calldata _param
    ) external virtual onlyExecutor {
        positionRouter.executeOrCancelIncreasePosition(_param, payable(msg.sender));
    }

    /// @notice Try to execute decrease position request. If the request is not executable, cancel it.
    /// @param _param The decrease position request id calculation param
    function executeOrCancelDecreasePosition(
        IPositionRouter.DecreasePositionRequestIdParam calldata _param
    ) external virtual onlyExecutor {
        positionRouter.executeOrCancelDecreasePosition(_param, payable(msg.sender));
    }

    /// @notice Try to Execute mint PUSD request. If the request is not executable, cancel it.
    /// @param _param The mint PUSD request id calculation param
    function executeOrCancelMintPUSD(
        IPositionRouter.MintPUSDRequestIdParam calldata _param
    ) external virtual onlyExecutor {
        positionRouter.executeOrCancelMintPUSD(_param, payable(msg.sender));
    }

    /// @notice Try to execute burn request. If the request is not executable, cancel it.
    /// @param _param The burn PUSD request id calculation param
    function executeOrCancelBurnPUSD(
        IPositionRouter.BurnPUSDRequestIdParam calldata _param
    ) external virtual onlyExecutor {
        positionRouter.executeOrCancelBurnPUSD(_param, payable(msg.sender));
    }

    /// @notice Collect protocol fee
    function collectProtocolFee(IERC20 _market) external virtual onlyExecutor {
        marketManager.collectProtocolFee(_market);
    }

    /// @notice Collect protocol fee batch
    /// @param _markets The array of market address to collect protocol fee
    function collectProtocolFeeBatch(IERC20[] calldata _markets) external virtual onlyExecutor {
        for (uint8 i; i < _markets.length; ++i) {
            marketManager.collectProtocolFee(_markets[i]);
        }
    }

    /// @notice Liquidate a position
    /// @param _market The market address
    /// @param _packedValue The packed values of the account and require success flag:
    /// bit 0-159 represent the account, and bit 160 represent the require success flag
    function liquidatePosition(IERC20 _market, PackedValue _packedValue) external virtual onlyExecutor {
        address account = _packedValue.unpackAddress(0);
        bool requireSuccess = _packedValue.unpackBool(160);

        try liquidator.liquidatePosition(_market, payable(account), payable(msg.sender)) {} catch (
            bytes memory reason
        ) {
            if (requireSuccess) revert ExecutionFailed(reason);

            emit LiquidatePositionFailed(_market, account, _decodeShortenedReason(reason));
        }
    }

    /// @notice Try to execute increase balance rate request. If the request is not executable, cancel it.
    /// @param _param The increase balance rate request id calculation param
    /// @param _shouldCancelOnFail should cancel request when execute failed
    function executeOrCancelIncreaseBalanceRate(
        IBalanceRateBalancer.IncreaseBalanceRateRequestIdParam calldata _param,
        bool _shouldCancelOnFail
    ) external virtual onlyExecutor {
        balanceRateBalancer.executeOrCancelIncreaseBalanceRate(_param, _shouldCancelOnFail, payable(msg.sender));
    }

    /// @notice Decode the shortened reason of the execution error
    /// @dev The default implementation is to return the first 4 bytes of the reason, which is typically the
    /// selector for the error type
    /// @param _reason The reason of the execution error
    /// @return The shortened reason of the execution error
    function _decodeShortenedReason(bytes memory _reason) internal pure virtual returns (bytes4) {
        return bytes4(_reason);
    }
}
