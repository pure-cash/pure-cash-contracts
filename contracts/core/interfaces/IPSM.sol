// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice Peg Stability Module interface
interface IPSM {
    struct CollateralState {
        uint120 cap;
        uint8 decimals;
        uint128 balance;
    }

    /// @notice Emitted when the collateral cap is updated
    event PSMCollateralUpdated(IERC20 collateral, uint120 cap);

    /// @notice Emit when PUSD is minted through the PSM module
    /// @param collateral The collateral token
    /// @param receiver Address to receive PUSD
    /// @param payAmount The amount of collateral paid
    /// @param receiveAmount The amount of PUSD minted
    event PSMMinted(IERC20 indexed collateral, address indexed receiver, uint96 payAmount, uint64 receiveAmount);

    /// @notice Emitted when PUSD is burned through the PSM module
    /// @param collateral The collateral token
    /// @param receiver Address to receive collateral
    /// @param payAmount The amount of PUSD burned
    /// @param receiveAmount The amount of collateral received
    event PSMBurned(IERC20 indexed collateral, address indexed receiver, uint64 payAmount, uint96 receiveAmount);

    /// @notice Invalid collateral token
    error InvalidCollateral();

    /// @notice Invalid collateral decimals
    error InvalidCollateralDecimals(uint8 decimals);

    /// @notice The PSM balance is insufficient
    error InsufficientPSMBalance(uint96 receiveAmount, uint128 balance);

    /// @notice Get the collateral state
    function psmCollateralStates(IERC20 collateral) external view returns (CollateralState memory);

    /// @notice Update the collateral cap
    /// @param collateral The collateral token
    /// @param cap The new cap
    function updatePSMCollateralCap(IERC20 collateral, uint120 cap) external;

    /// @notice Mint PUSD
    /// @param collateral The collateral token
    /// @param receiver Address to receive PUSD
    /// @return receiveAmount The amount of PUSD minted
    function psmMintPUSD(IERC20 collateral, address receiver) external returns (uint64 receiveAmount);

    /// @notice Burn PUSD
    /// @param collateral The collateral token
    /// @param receiver Address to receive collateral
    /// @return receiveAmount The amount of collateral received
    function psmBurnPUSD(IERC20 collateral, address receiver) external returns (uint96 receiveAmount);
}
