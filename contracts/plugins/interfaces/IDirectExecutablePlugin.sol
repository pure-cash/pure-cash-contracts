// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IDirectExecutablePlugin {
    /// @notice Emitted when liquidity buffer debt payer updated
    /// @param account Account to update
    /// @param active Whether active after the update
    event LiquidityBufferDebtPayerUpdated(address indexed account, bool active);

    /// @notice Emitted when PSM minter updated
    /// @param account Account to update
    /// @param active Whether active after the update
    event PSMMinterUpdated(address indexed account, bool active);

    /// @notice Error thrown when the cap is exceeded
    error PSMCapExceeded(uint256 balance, uint120 amount, uint120 cap);

    /// @notice Error thrown when the excess debt is repaid
    error TooMuchRepaid(uint256 balance, uint128 amount, uint128 cap);

    function liquidityBufferDebtPayers(address account) external view returns (bool);

    function allowAnyoneRepayLiquidityBufferDebt() external view returns (bool);

    function psmMinters(address account) external view returns (bool);

    function allowAnyoneUsePSM() external view returns (bool);

    /// @notice Update liquidity buffer debt payer
    /// @param account Account to update
    /// @param active Updated status
    function updateLiquidityBufferDebtPayer(address account, bool active) external;

    /// @notice Update allow anyone repay liquidity buffer debt status
    /// @param allowed Updated status
    function updateAllowAnyoneRepayLiquidityBufferDebt(bool allowed) external;

    /// @notice Update PSM minters
    /// @param account Account to update
    /// @param active Updated status
    function updatePSMMinters(address account, bool active) external;

    /// @notice Update allow anyone use PSM
    /// @param allowed Updated status
    function updateAllowAnyoneUsePSM(bool allowed) external;

    /// @notice Repay liquidity buffer debt
    /// @param market The target market contract address, such as the contract address of WETH
    /// @param amount The amount of PUSD to repay
    /// @param receiver Address to receive repaid token
    /// @param permitData The permit data for the PUSD token, optional
    function repayLiquidityBufferDebt(
        IERC20 market,
        uint128 amount,
        address receiver,
        bytes calldata permitData
    ) external;

    /// @notice Mint PUSD through the PSM module
    /// @param collateral The collateral token
    /// @param amount The amount of collateral to mint
    /// @param receiver Address to receive PUSD
    /// @param permitData The permit data for the collateral token, optional
    /// @return receiveAmount The amount of PUSD minted
    function psmMintPUSD(
        IERC20 collateral,
        uint120 amount,
        address receiver,
        bytes memory permitData
    ) external returns (uint64 receiveAmount);

    /// @notice Burn PUSD through the PSM module
    /// @param collateral The collateral token
    /// @param amount The amount of PUSD to burn
    /// @param receiver Address to receive collateral
    /// @param permitData The permit data for the PUSD token, optional
    /// @return receiveAmount The amount of collateral received
    function psmBurnPUSD(
        IERC20 collateral,
        uint64 amount,
        address receiver,
        bytes calldata permitData
    ) external returns (uint96 receiveAmount);
}
