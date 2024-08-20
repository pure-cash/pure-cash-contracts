// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../../core/interfaces/IPUSDManagerCallback.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IMarketManager} from "../../core/interfaces/IMarketManager.sol";

interface IPositionRouterCommon is IPUSDManagerCallback {
    enum RequestType {
        MintLPT,
        BurnLPT,
        IncreasePosition,
        DecreasePosition,
        Mint,
        Burn
    }

    enum EstimatedGasLimitType {
        MintLPT,
        MintLPTPayPUSD,
        BurnLPT,
        BurnLPTReceivePUSD,
        IncreasePosition,
        IncreasePositionPayPUSD,
        DecreasePosition,
        DecreasePositionReceivePUSD,
        MintPUSD,
        BurnPUSD,
        IncreaseBalanceRate
    }

    struct CallbackData {
        uint96 margin;
        address account;
    }

    /// @notice Emitted when estimated gas limit updated
    /// @param estimatedGasLimitType Type of the estimated gas limit, each kind of request has a different estimated gas limit
    /// @param estimatedGasLimit Updated estimated gas limit
    event EstimatedGasLimitUpdated(EstimatedGasLimitType estimatedGasLimitType, uint256 estimatedGasLimit);

    /// @notice Emitted when position executor updated
    /// @param account Account to update
    /// @param active Whether active after the update
    event PositionExecutorUpdated(address indexed account, bool active);

    /// @notice Emitted when delay parameter updated
    /// @param minBlockDelayExecutor The new min block delay for executor to execute requests
    /// @param minBlockDelayPublic The new min block delay for public to execute requests
    /// @param maxBlockDelay The new max block delay until request expires
    event DelayValuesUpdated(uint32 minBlockDelayExecutor, uint32 minBlockDelayPublic, uint32 maxBlockDelay);

    /// @notice Emitted when estimated gas fee multiplier updated
    /// @param estimatedGasMultiplier The new estimated gas fee multiplier
    event EstimatedGasFeeMultiplierUpdated(uint24 estimatedGasMultiplier);

    /// @notice Emitted when execution gas fee multiplier updated
    /// @param executionGasFeeMultiplier The new execution gas fee multiplier
    event ExecutionGasFeeMultiplierUpdated(uint24 executionGasFeeMultiplier);

    /// @notice Emitted when requests execution reverted
    /// @param reqType Request type
    /// @param id Id of the failed request
    /// @param shortenedReason The error selector for the failure
    event ExecuteFailed(RequestType indexed reqType, bytes32 indexed id, bytes4 shortenedReason);

    /// @notice Execution fee is insufficient
    /// @param available The available execution fee amount
    /// @param required The required minimum execution fee amount
    error InsufficientExecutionFee(uint256 available, uint256 required);

    /// @notice Request expired
    /// @param expiredAt When the request is expired
    error Expired(uint256 expiredAt);

    /// @notice Too early to execute request
    /// @param earliest The earliest block to execute the request
    error TooEarly(uint256 earliest);

    /// @notice Paid amount is more than acceptable max amount
    error TooMuchPaid(uint96 payAmount, uint96 acceptableMaxAmount);

    /// @notice Received amount is less than acceptable min amount
    error TooLittleReceived(uint96 acceptableMinAmount, uint96 receiveAmount);

    /// @notice Index price exceeds limit
    error InvalidIndexPrice(uint64 indexPrice, uint64 acceptableIndexPrice);

    /// @notice Request id conflicts
    error ConflictRequests(bytes32 id);

    /// @notice Update position executor
    /// @param account Account to update
    /// @param active Updated status
    function updatePositionExecutor(address account, bool active) external;

    /// @notice Update delay parameters
    /// @param minBlockDelayExecutor New min block delay for executor to execute requests
    /// @param minBlockDelayPublic New min block delay for public to execute requests
    /// @param maxBlockDelay New max block delay until request expires
    function updateDelayValues(uint32 minBlockDelayExecutor, uint32 minBlockDelayPublic, uint32 maxBlockDelay) external;

    /// @notice Update estimated gas fee multiplier
    /// @param multiplier New estimated gas multiplier
    function updateEstimatedGasFeeMultiplier(uint24 multiplier) external;

    /// @notice Update execution gas fee multiplier
    /// @param multiplier New execution gas multiplier
    function updateExecutionGasFeeMultiplier(uint24 multiplier) external;

    /// @notice Update estimated gas limit
    /// @param estimatedGasLimitType Type of the estimated gas limit, each kind of request has a different estimated gas limit
    /// @param estimatedGasLimit New estimated gas limit
    function updateEstimatedGasLimit(EstimatedGasLimitType estimatedGasLimitType, uint256 estimatedGasLimit) external;

    /// @notice Update the gas limit for executing requests
    /// @param executionGasLimit New execution gas limit
    function updateExecutionGasLimit(uint32 executionGasLimit) external;

    /// @notice Update the gas limit of ether transfer
    /// @param etherTransferGasLimit New gas limit of ether transfer
    function updateEtherTransferGasLimit(uint32 etherTransferGasLimit) external;

    /// @notice Get the status of the position executor
    /// @param account Account to check
    function positionExecutors(address account) external view returns (bool);

    /// @notice Get the block number of the hash id
    /// @param id The hash id
    /// @return blockNumber The block number of the hash id
    function blockNumbers(bytes32 id) external view returns (uint256 blockNumber);
}
