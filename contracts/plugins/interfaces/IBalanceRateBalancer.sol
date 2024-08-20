// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "../../core/interfaces/IPUSDManagerCallback.sol";

interface IBalanceRateBalancer is IPUSDManagerCallback {
    struct IncreaseBalanceRateRequestIdParam {
        IERC20 market;
        IERC20 collateral;
        uint96 amount;
        uint256 executionFee;
        address account;
        address[] targets;
        bytes[] calldatas;
    }

    /// @notice Emitted when createIncreaseBalanceRate request created
    /// @param market The target market contract address, such as the contract address of WETH
    /// @param collateral The target collateral contract address, such as the contract address of DAI
    /// @param amount The amount of pusd to burn
    /// @param executionFee Amount of fee for the executor to carry out the order
    /// @param account Owner of the request
    /// @param targets swap calldata target list
    /// @param calldatas swap calldata list
    /// @param id Id of the request
    event IncreaseBalanceRateCreated(
        IERC20 indexed market,
        IERC20 indexed collateral,
        uint128 amount,
        uint256 executionFee,
        address account,
        address[] targets,
        bytes[] calldatas,
        bytes32 id
    );

    /// @notice Emitted when createIncreaseBalanceRate request cancelled
    /// @param id Id of the cancelled request
    /// @param executionFeeReceiver Receiver of the cancelled request execution fee
    event IncreaseBalanceRateCancelled(bytes32 indexed id, address payable executionFeeReceiver);

    /// @notice Emitted when createIncreaseBalanceRate request executed
    /// @param id Id of the executed request
    /// @param executionFeeReceiver Receiver of the executed request execution fee
    /// @param executionFee Actual execution fee received
    event IncreaseBalanceRateExecuted(bytes32 indexed id, address payable executionFeeReceiver, uint256 executionFee);

    /// @notice Execute failed
    event ExecuteFailed(bytes32 indexed id, bytes4 shortenedReason);

    /// @notice Error thrown when caller is not the market manager
    error InvalidCaller(address caller);

    /// @notice Invalid callbackData
    error InvalidCallbackData();

    /// @notice create increase balance rate request
    /// @param market The target market contract address, such as the contract address of WETH
    /// @param collateral The target collateral contract address, such as the contract address of DAI
    /// @param amount Amount of pusd to burn
    /// @param targets Address of contract to call
    /// @param data CallData to call
    /// @return id Id of the request
    function createIncreaseBalanceRate(
        IERC20 market,
        IERC20 collateral,
        uint96 amount,
        address[] calldata targets,
        bytes[] calldata data
    ) external payable returns (bytes32 id);

    /// @notice cancel increase balance rate request
    /// @param param The increase request id calculation param
    /// @param executionFeeReceiver Receiver of request execution fee
    /// @return cancelled True if the cancellation succeeds or request not exists
    function cancelIncreaseBalanceRate(
        IncreaseBalanceRateRequestIdParam calldata param,
        address payable executionFeeReceiver
    ) external returns (bool);

    /// @notice Execute increase balance rate request
    /// @param param The increase request id calculation param
    /// @param executionFeeReceiver Receiver of the request execution fee
    /// @return executed True if the execution succeeds or request not exists
    function executeIncreaseBalanceRate(
        IncreaseBalanceRateRequestIdParam calldata param,
        address payable executionFeeReceiver
    ) external returns (bool);

    /// @notice Execute multiple requests
    /// @param param The increase request id calculation param
    /// @param shouldCancelOnFail should cancel request when execute failed
    /// @param executionFeeReceiver Receiver of the request execution fees
    function executeOrCancelIncreaseBalanceRate(
        IncreaseBalanceRateRequestIdParam calldata param,
        bool shouldCancelOnFail,
        address payable executionFeeReceiver
    ) external;
}
