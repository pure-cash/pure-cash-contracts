// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice PositionRouter contract interface
interface IPositionRouter {
    /// @notice The param used to calculate the increase position request id
    struct IncreasePositionRequestIdParam {
        address account;
        IERC20 market;
        uint96 marginDelta;
        uint96 sizeDelta;
        uint64 acceptableIndexPrice;
        uint256 executionFee;
        bool payPUSD;
    }

    /// @notice The param used to calculate the decrease position request id
    struct DecreasePositionRequestIdParam {
        address account;
        IERC20 market;
        uint96 marginDelta;
        uint96 sizeDelta;
        uint64 acceptableIndexPrice;
        address receiver;
        uint256 executionFee;
        bool receivePUSD;
    }

    /// @notice The param used to calculate the mint PUSD request id
    struct MintPUSDRequestIdParam {
        address account;
        IERC20 market;
        bool exactIn;
        uint96 acceptableMaxPayAmount;
        uint64 acceptableMinReceiveAmount;
        address receiver;
        uint256 executionFee;
    }

    /// @notice The param used to calculate the burn PUSD request id
    struct BurnPUSDRequestIdParam {
        IERC20 market;
        address account;
        bool exactIn;
        uint64 acceptableMaxPayAmount;
        uint96 acceptableMinReceiveAmount;
        address receiver;
        uint256 executionFee;
    }

    /// @notice Emitted when open or increase an existing position size request created
    /// @param account Owner of the request
    /// @param market The target market contract address, such as the contract address of WETH
    /// @param marginDelta The increase in position margin, PUSD amount if `payUSD` is true
    /// @param sizeDelta The increase in position size
    /// @param acceptableIndexPrice The worst index price of the request
    /// @param executionFee Amount of fee for the executor to carry out the request
    /// @param payPUSD Whether to pay PUSD
    /// @param id Id of the request
    event IncreasePositionCreated(
        address indexed account,
        IERC20 indexed market,
        uint96 marginDelta,
        uint96 sizeDelta,
        uint64 acceptableIndexPrice,
        uint256 executionFee,
        bool payPUSD,
        bytes32 id
    );

    /// @notice Emitted when increase position request cancelled
    /// @param id Id of the request
    /// @param executionFeeReceiver Receiver of the cancelled request execution fee
    event IncreasePositionCancelled(bytes32 indexed id, address payable executionFeeReceiver);

    /// @notice Emitted when increase position request executed
    /// @param id Id of the request
    /// @param executionFeeReceiver Receiver of the executed request execution fee
    /// @param executionFee Actual execution fee received
    event IncreasePositionExecuted(bytes32 indexed id, address payable executionFeeReceiver, uint256 executionFee);

    /// @notice Emitted when close or decrease existing position size request created
    /// @param account Owner of the request
    /// @param market The target market contract address, such as the contract address of WETH
    /// @param marginDelta The decrease in position margin
    /// @param sizeDelta The decrease in position size
    /// @param acceptableIndexPrice The worst index price of the request
    /// @param receiver Address of the margin receiver
    /// @param executionFee Amount of fee for the executor to carry out the order
    /// @param receivePUSD Whether to receive PUSD
    /// @param id Id of the request
    event DecreasePositionCreated(
        address indexed account,
        IERC20 indexed market,
        uint96 marginDelta,
        uint96 sizeDelta,
        uint64 acceptableIndexPrice,
        address receiver,
        uint256 executionFee,
        bool receivePUSD,
        bytes32 id
    );

    /// @notice Emitted when decrease position request cancelled
    /// @param id Id of the request
    /// @param executionFeeReceiver Receiver of the request execution fee
    event DecreasePositionCancelled(bytes32 indexed id, address payable executionFeeReceiver);

    /// @notice Emitted when decrease position request executed
    /// @param id Id of the request
    /// @param executionFeeReceiver Receiver of the request execution fee
    /// @param executionFee Actual execution fee received
    event DecreasePositionExecuted(bytes32 indexed id, address payable executionFeeReceiver, uint256 executionFee);

    /// @notice Emitted when mint PUSD request created
    /// @param account Owner of the request
    /// @param market The target market contract address, such as the contract address of WETH
    /// @param acceptableMaxPayAmount The max amount of token to pay
    /// @param acceptableMinReceiveAmount The min amount of PUSD to mint
    /// @param receiver Address to receive PUSD
    /// @param executionFee Amount of the execution fee
    /// @param id Id of the request
    event MintPUSDCreated(
        address indexed account,
        IERC20 indexed market,
        bool exactIn,
        uint96 acceptableMaxPayAmount,
        uint64 acceptableMinReceiveAmount,
        address receiver,
        uint256 executionFee,
        bytes32 id
    );

    /// @notice Emitted when mint PUSD request cancelled
    /// @param id Id of the request
    /// @param executionFeeReceiver Receiver of the request execution fee
    event MintPUSDCancelled(bytes32 indexed id, address payable executionFeeReceiver);

    /// @notice Emitted when mint PUSD request executed
    /// @param id Id of the request
    /// @param executionFeeReceiver Receiver of the request execution fee
    /// @param executionFee Actual execution fee received
    event MintPUSDExecuted(bytes32 indexed id, address payable executionFeeReceiver, uint256 executionFee);

    /// @notice Emitted when burn PUSD request created
    /// @param account Owner of the request
    /// @param market The target market contract address, such as the contract address of WETH
    /// @param acceptableMaxPayAmount The max amount of PUSD to burn
    /// @param acceptableMinReceiveAmount The min amount of token to receive
    /// @param receiver Address to receive ETH
    /// @param executionFee Amount of the execution fee
    /// @param id Id of the request
    event BurnPUSDCreated(
        address indexed account,
        IERC20 indexed market,
        bool exactIn,
        uint64 acceptableMaxPayAmount,
        uint96 acceptableMinReceiveAmount,
        address receiver,
        uint256 executionFee,
        bytes32 id
    );

    /// @notice Emitted when burn PUSD request cancelled
    /// @param id Id of the request
    /// @param executionFeeReceiver Receiver of the request execution fee
    event BurnPUSDCancelled(bytes32 indexed id, address payable executionFeeReceiver);

    /// @notice Emitted when burn PUSD request executed
    /// @param id Id of the request
    /// @param executionFeeReceiver Receiver of the request execution fee
    /// @param executionFee Actual execution fee received
    event BurnPUSDExecuted(bytes32 indexed id, address payable executionFeeReceiver, uint256 executionFee);

    /// @notice Create open or increase the size of existing position request
    /// @param market The target market contract address, such as the contract address of WETH
    /// @param marginDelta The increase in position margin
    /// @param sizeDelta The increase in position size
    /// @param acceptableIndexPrice The worst index price of the request
    /// @param permitData The permit data for the market token, optional
    /// @param id Id of the request
    function createIncreasePosition(
        IERC20 market,
        uint96 marginDelta,
        uint96 sizeDelta,
        uint64 acceptableIndexPrice,
        bytes calldata permitData
    ) external payable returns (bytes32 id);

    /// @notice Create open or increase the size of existing position request by paying ETH
    /// @param sizeDelta The increase in position size
    /// @param acceptableIndexPrice The worst index price of the request
    /// @param executionFee Amount of the execution fee
    /// @param id Id of the request
    function createIncreasePositionETH(
        uint96 sizeDelta,
        uint64 acceptableIndexPrice,
        uint256 executionFee
    ) external payable returns (bytes32 id);

    /// @notice Create open or increase the size of existing position request, paying PUSD
    /// @param market The target market contract address, such as the contract address of WETH
    /// @param pusdAmount The PUSD amount to pay
    /// @param sizeDelta The increase in position size
    /// @param acceptableIndexPrice The worst index price of the request
    /// @param permitData The permit data for the PUSD token, optional
    /// @param id Id of the request
    function createIncreasePositionPayPUSD(
        IERC20 market,
        uint64 pusdAmount,
        uint96 sizeDelta,
        uint64 acceptableIndexPrice,
        bytes calldata permitData
    ) external payable returns (bytes32 id);

    /// @notice Cancel increase position request
    /// @param param The increase position request id calculation param
    /// @param executionFeeReceiver Receiver of the request execution fee
    /// @return cancelled True if the cancellation succeeds or request not exists
    function cancelIncreasePosition(
        IncreasePositionRequestIdParam calldata param,
        address payable executionFeeReceiver
    ) external returns (bool cancelled);

    /// @notice Execute increase position request
    /// @param param The increase position request id calculation param
    /// @param executionFeeReceiver Receiver of the request execution fee
    /// @return executed True if the execution succeeds or request not exists
    function executeIncreasePosition(
        IncreasePositionRequestIdParam calldata param,
        address payable executionFeeReceiver
    ) external returns (bool executed);

    /// @notice Try to execute increase position request. If the request is not executable, cancel it.
    /// @param param The increase position request id calculation param
    /// @param executionFeeReceiver Receiver of the request execution fee
    function executeOrCancelIncreasePosition(
        IncreasePositionRequestIdParam calldata param,
        address payable executionFeeReceiver
    ) external;

    /// @notice Create decrease position request
    /// @param market The target market contract address, such as the contract address of WETH
    /// @param marginDelta The decrease in position margin
    /// @param sizeDelta The decrease in position size
    /// @param acceptableIndexPrice The worst index price of the request
    /// @param receiver Margin recipient address
    /// @param id Id of the request
    function createDecreasePosition(
        IERC20 market,
        uint96 marginDelta,
        uint96 sizeDelta,
        uint64 acceptableIndexPrice,
        address payable receiver
    ) external payable returns (bytes32 id);

    /// @notice Create decrease position request, receiving PUSD
    /// @param market The target market contract address, such as the contract address of WETH
    /// @param marginDelta The decrease in position margin
    /// @param sizeDelta The decrease in position size
    /// @param acceptableIndexPrice The worst index price of decreasing position of the request
    /// @param receiver Margin recipient address
    /// @param id Id of the request
    function createDecreasePositionReceivePUSD(
        IERC20 market,
        uint96 marginDelta,
        uint96 sizeDelta,
        uint64 acceptableIndexPrice,
        address receiver
    ) external payable returns (bytes32 id);

    /// @notice Cancel decrease position request
    /// @param param The decrease position request id calculation param
    /// @param executionFeeReceiver Receiver of the request execution fee
    /// @return cancelled True if the cancellation succeeds or request not exists
    function cancelDecreasePosition(
        DecreasePositionRequestIdParam calldata param,
        address payable executionFeeReceiver
    ) external returns (bool cancelled);

    /// @notice Execute decrease position request
    /// @param param The decrease position request id calculation param
    /// @param executionFeeReceiver Receiver of the request execution fee
    /// @return executed True if the execution succeeds or request not exists
    function executeDecreasePosition(
        DecreasePositionRequestIdParam calldata param,
        address payable executionFeeReceiver
    ) external returns (bool executed);

    /// @notice Try to execute decrease position request. If the request is not executable, cancel it.
    /// @param param The decrease position request id calculation param
    /// @param executionFeeReceiver Receiver of the request execution fee
    function executeOrCancelDecreasePosition(
        DecreasePositionRequestIdParam calldata param,
        address payable executionFeeReceiver
    ) external;

    /// @notice Create mint PUSD request
    /// @param market The target market contract address, such as the contract address of WETH
    /// @param acceptableMaxPayAmount The max amount of token to pay
    /// @param acceptableMinReceiveAmount The min amount of PUSD to mint
    /// @param receiver Address to receive PUSD
    /// @param permitData The permit data for the market token, optional
    /// @param id Id of the request
    function createMintPUSD(
        IERC20 market,
        bool exactIn,
        uint96 acceptableMaxPayAmount,
        uint64 acceptableMinReceiveAmount,
        address receiver,
        bytes calldata permitData
    ) external payable returns (bytes32 id);

    /// @notice Create mint PUSD request by paying ETH
    /// @param acceptableMinReceiveAmount The min acceptable amount of PUSD to mint
    /// @param receiver Address to receive PUSD
    /// @param executionFee Amount of the execution fee
    /// @param id Id of the request
    function createMintPUSDETH(
        bool exactIn,
        uint64 acceptableMinReceiveAmount,
        address receiver,
        uint256 executionFee
    ) external payable returns (bytes32 id);

    /// @notice Cancel mint PUSD request
    /// @param param The mint PUSD request id calculation param
    /// @param executionFeeReceiver Receiver of the request execution fee
    /// @return cancelled True if the cancellation succeeds or request not exists
    function cancelMintPUSD(
        MintPUSDRequestIdParam calldata param,
        address payable executionFeeReceiver
    ) external returns (bool cancelled);

    /// @notice Execute mint PUSD request
    /// @param param The mint PUSD request id calculation param
    /// @param executionFeeReceiver Receiver of the request execution fee
    /// @return executed True if the execution succeeds or request not exists
    function executeMintPUSD(
        MintPUSDRequestIdParam calldata param,
        address payable executionFeeReceiver
    ) external returns (bool executed);

    /// @notice Try to Execute mint PUSD request. If the request is not executable, cancel it.
    /// @param param The mint PUSD request id calculation param
    /// @param executionFeeReceiver Receiver of the request execution fee
    function executeOrCancelMintPUSD(
        MintPUSDRequestIdParam calldata param,
        address payable executionFeeReceiver
    ) external;

    /// @notice Create burn PUSD request
    /// @param market The target market contract address, such as the contract address of WETH
    /// @param acceptableMaxPayAmount The max amount of PUSD to burn
    /// @param acceptableMinReceiveAmount The min amount of token to receive
    /// @param receiver Address to receive ETH
    /// @param permitData The permit data for the PUSD token, optional
    /// @param id Id of the request
    function createBurnPUSD(
        IERC20 market,
        bool exactIn,
        uint64 acceptableMaxPayAmount,
        uint96 acceptableMinReceiveAmount,
        address receiver,
        bytes calldata permitData
    ) external payable returns (bytes32 id);

    /// @notice Cancel burn request
    /// @notice param The burn PUSD request id calculation param
    /// @param executionFeeReceiver Receiver of the request execution fee
    /// @return cancelled True if the cancellation succeeds or request not exists
    function cancelBurnPUSD(
        BurnPUSDRequestIdParam calldata param,
        address payable executionFeeReceiver
    ) external returns (bool cancelled);

    /// @notice Execute burn request
    /// @param param The burn PUSD request id calculation param
    /// @param executionFeeReceiver Receiver of the request execution fee
    /// @return executed True if the execution succeeds or request not exists
    function executeBurnPUSD(
        BurnPUSDRequestIdParam calldata param,
        address payable executionFeeReceiver
    ) external returns (bool executed);

    /// @notice Try to execute burn request. If the request is not executable, cancel it.
    /// @param param The burn PUSD request id calculation param
    /// @param executionFeeReceiver Receiver of the request execution fee
    function executeOrCancelBurnPUSD(
        BurnPUSDRequestIdParam calldata param,
        address payable executionFeeReceiver
    ) external;
}
