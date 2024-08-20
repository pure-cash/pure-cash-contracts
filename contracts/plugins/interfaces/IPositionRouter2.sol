// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice PositionRouter2 contract interface
interface IPositionRouter2 {
    /// @notice The param used to calculate the mint LPT request id
    struct MintLPTRequestIdParam {
        address account;
        IERC20 market;
        uint96 liquidityDelta;
        uint256 executionFee;
        address receiver;
        bool payPUSD;
        uint96 minReceivedFromBurningPUSD;
    }

    /// @notice The param used to calculate the burn LPT request id
    struct BurnLPTRequestIdParam {
        address account;
        IERC20 market;
        uint64 amount;
        uint96 acceptableMinLiquidity;
        address receiver;
        uint256 executionFee;
        bool receivePUSD;
        uint64 minPUSDReceived;
    }

    /// @notice Emitted when mint LP token request created
    /// @param account Owner of the request
    /// @param market The target market contract address, such as the contract address of WETH
    /// @param liquidityDelta The liquidity to be paid, PUSD amount if `payUSD` is true
    /// @param executionFee Amount of the execution fee
    /// @param receiver The address to receive the minted LP Token
    /// @param payPUSD Whether to pay PUSD
    /// @param minReceiveAmountFromBurningPUSD The minimum amount received from burning PUSD if `payPUSD` is true
    /// @param id Id of the request
    event MintLPTCreated(
        address indexed account,
        IERC20 indexed market,
        uint96 liquidityDelta,
        uint256 executionFee,
        address receiver,
        bool payPUSD,
        uint96 minReceiveAmountFromBurningPUSD,
        bytes32 id
    );

    /// @notice Emitted when mint LP token request cancelled
    /// @param id Id of the request
    /// @param receiver Receiver of the execution fee and margin
    event MintLPTCancelled(bytes32 indexed id, address payable receiver);

    /// @notice Emitted when mint LP token request executed
    /// @param id Id of the request
    /// @param executionFeeReceiver Receiver of the request execution fee
    /// @param executionFee Actual execution fee received
    event MintLPTExecuted(bytes32 indexed id, address payable executionFeeReceiver, uint256 executionFee);

    /// @notice Emitted when burn LP token request created
    /// @param account Owner of the request
    /// @param market The target market contract address, such as the contract address of WETH
    /// @param amount The amount of LP token that will be burned
    /// @param acceptableMinLiquidity The min amount of liquidity to receive, valid if `receivePUSD` is false
    /// @param receiver Address of the liquidity receiver
    /// @param executionFee  Amount of fee for the executor to carry out the request
    /// @param receivePUSD Whether to receive PUSD
    /// @param minPUSDReceived The min PUSD to receive if `receivePUSD` is true
    /// @param id Id of the request
    event BurnLPTCreated(
        address indexed account,
        IERC20 indexed market,
        uint64 amount,
        uint96 acceptableMinLiquidity,
        address receiver,
        uint256 executionFee,
        bool receivePUSD,
        uint64 minPUSDReceived,
        bytes32 id
    );

    /// @notice Emitted when burn LP token request cancelled
    /// @param id Id of the request
    /// @param executionFeeReceiver Receiver of the request execution fee
    event BurnLPTCancelled(bytes32 indexed id, address payable executionFeeReceiver);

    /// @notice Emitted when burn LP token request executed
    /// @param id Id of the request
    /// @param executionFeeReceiver Receiver of the request execution fee
    // @param executionFee Actual execution fee received
    event BurnLPTExecuted(bytes32 indexed id, address payable executionFeeReceiver, uint256 executionFee);

    /// @notice Create mint LP token request by paying ERC20 token
    /// @param market The target market contract address, such as the contract address of WETH
    /// @param liquidityDelta The liquidity to be paid
    /// @param receiver Address to receive the minted LP Token
    /// @param permitData The permit data for the market token, optional
    /// @return id Id of the request
    function createMintLPT(
        IERC20 market,
        uint96 liquidityDelta,
        address receiver,
        bytes calldata permitData
    ) external payable returns (bytes32 id);

    /// @notice Create mint LP token request by paying ETH
    /// @param receiver Address to receive the minted LP Token
    /// @param executionFee Amount of the execution fee
    /// @return id Id of the request
    function createMintLPTETH(address receiver, uint256 executionFee) external payable returns (bytes32 id);

    /// @notice Create mint LP token request by paying PUSD
    /// @param market The target market contract address, such as the contract address of WETH
    /// @param pusdAmount The PUSD amount to pay
    /// @param receiver Address to receive the minted LP Token
    /// @param minReceivedFromBurningPUSD The minimum amount to receive from burning PUSD
    /// @param permitData The permit data for the PUSD token, optional
    /// @return id Id of the request
    function createMintLPTPayPUSD(
        IERC20 market,
        uint64 pusdAmount,
        address receiver,
        uint96 minReceivedFromBurningPUSD,
        bytes calldata permitData
    ) external payable returns (bytes32 id);

    /// @notice Cancel mint LP token request
    /// @param param The mint LPT request id calculation param
    /// @param executionFeeReceiver Receiver of request execution fee
    /// @return cancelled True if the cancellation succeeds or request not exists
    function cancelMintLPT(
        MintLPTRequestIdParam calldata param,
        address payable executionFeeReceiver
    ) external returns (bool cancelled);

    /// @notice Execute mint LP token request
    /// @param param The mint LPT request id calculation param
    /// @param executionFeeReceiver Receiver of request execution fee
    /// @return executed True if the execution succeeds or request not exists
    function executeMintLPT(
        MintLPTRequestIdParam calldata param,
        address payable executionFeeReceiver
    ) external returns (bool executed);

    /// @notice Try to execute mint LP token request. If the request is not executable, cancel it.
    /// @param param The mint LPT request id calculation param
    /// @param executionFeeReceiver Receiver of request execution fee
    function executeOrCancelMintLPT(
        MintLPTRequestIdParam calldata param,
        address payable executionFeeReceiver
    ) external;

    /// @notice Create burn LP token request
    /// @param market The target market contract address, such as the contract address of WETH
    /// @param amount The amount of LP token that will be burned
    /// @param acceptableMinLiquidity The min amount of liquidity to receive
    /// @param receiver Address of the margin receiver
    /// @param permitData The permit data for the LPT token, optional
    /// @return id Id of the request
    function createBurnLPT(
        IERC20 market,
        uint64 amount,
        uint96 acceptableMinLiquidity,
        address receiver,
        bytes calldata permitData
    ) external payable returns (bytes32 id);

    /// @notice Create burn LP token request and receive PUSD
    /// @param market The target market contract address, such as the contract address of WETH
    /// @param amount The amount of LP token that will be burned
    /// @param minPUSDReceived The min amount of PUSD to receive
    /// @param receiver Address of the margin receiver
    /// @param permitData The permit data for the LPT token, optional
    /// @return id Id of the request
    function createBurnLPTReceivePUSD(
        IERC20 market,
        uint64 amount,
        uint64 minPUSDReceived,
        address receiver,
        bytes calldata permitData
    ) external payable returns (bytes32 id);

    /// @notice Cancel burn LP token request
    /// @param param The burn LPT request id calculation param
    /// @param executionFeeReceiver Receiver of the request execution fee
    /// @return cancelled True if the cancellation succeeds or request not exists
    function cancelBurnLPT(
        BurnLPTRequestIdParam calldata param,
        address payable executionFeeReceiver
    ) external returns (bool cancelled);

    /// @notice Execute burn LP token request
    /// @param param The burn LPT request id calculation param
    /// @param executionFeeReceiver Receiver of the request execution fee
    /// @return executed True if the execution succeeds or request not exists
    function executeBurnLPT(
        BurnLPTRequestIdParam calldata param,
        address payable executionFeeReceiver
    ) external returns (bool executed);

    /// @notice Try to execute burn LP token request. If the request is not executable, cancel it.
    /// @param param The burn LPT request id calculation param
    /// @param executionFeeReceiver Receiver of the request execution fee
    function executeOrCancelBurnLPT(
        BurnLPTRequestIdParam calldata param,
        address payable executionFeeReceiver
    ) external;
}
