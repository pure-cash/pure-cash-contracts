// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "./ILPToken.sol";

/// @notice Interface for managing liquidity of the protocol
interface IMarketLiquidity {
    /// @notice Emitted when the global liquidity is increased by trading fee
    /// @param market The target market contract address, such as the contract address of WETH
    /// @param liquidityFee The increased liquidity fee
    event GlobalLiquidityIncreasedByTradingFee(IERC20 indexed market, uint96 liquidityFee);

    /// @notice Emitted when the global liquidity is increased by LP trading fee
    /// @param market The target market contract address, such as the contract address of WETH
    /// @param liquidityFee The increased liquidity fee
    event GlobalLiquidityIncreasedByLPTradingFee(IERC20 indexed market, uint96 liquidityFee);

    /// @notice Emitted when the global liquidity is settled
    /// @param market The target market contract address, such as the contract address of WETH
    /// @param sizeDelta The change in the global liquidity
    /// @param realizedPnL The realized PnL of the global liquidity
    /// @param entryPriceAfter The entry price after the settlement
    event GlobalLiquiditySettled(IERC20 indexed market, int256 sizeDelta, int256 realizedPnL, uint64 entryPriceAfter);

    /// @notice Emitted when a new LP Token is deployed
    /// @param market The target market contract address, such as the contract address of WETH
    /// @param token The LP Token contract address
    event LPTokenDeployed(IERC20 indexed market, ILPToken indexed token);

    /// @notice Emitted when the LP Token is minted
    /// @param market The target market contract address, such as the contract address of WETH
    /// @param account The owner of the LP Token
    /// @param receiver The address to receive the minted LP Token
    /// @param liquidity The liquidity provided by the LP
    /// @param tokenValue The LP Token to be minted
    /// @param tradingFee The trading fee of the LP
    event LPTMinted(
        IERC20 indexed market,
        address indexed account,
        address indexed receiver,
        uint96 liquidity,
        uint64 tokenValue,
        uint96 tradingFee
    );

    /// @notice Emitted when the LP Token is burned
    /// @param market The target market contract address, such as the contract address of WETH
    /// @param account The owner of the LP Token
    /// @param receiver The address to receive the margin
    /// @param liquidity The liquidity to be returned to the LP
    /// @param tokenValue The LP Token to be burned
    /// @param tradingFee The trading fee of the LP
    event LPTBurned(
        IERC20 indexed market,
        address indexed account,
        address indexed receiver,
        uint96 liquidity,
        uint64 tokenValue,
        uint96 tradingFee
    );

    /// @notice Emitted when the global liquidity PnL is revised
    /// @param market The target market contract address, such as the contract address of WETH
    /// @param settledPrice The price when the PnL is settled
    /// @param scaledUSDPnL The settled scaled USD PnL. For saving gas, this value is scaled up
    /// by 10^(market decimals + price decimals - usd decimals)
    /// @param revisedTokenPnL The revised token PnL
    event GlobalLiquidityPnLRevised(
        IERC20 indexed market,
        uint64 settledPrice,
        int256 scaledUSDPnL,
        int256 revisedTokenPnL
    );

    /// @notice Mint the LP Token
    /// @param market The target market contract address, such as the contract address of WETH
    /// @param account The address to mint the liquidity. The parameter is only used for emitting event
    /// @param receiver The address to receive the minted LP Token
    /// @return tokenValue The LP Token to be minted
    function mintLPT(IERC20 market, address account, address receiver) external returns (uint64 tokenValue);

    /// @notice Burn the LP Token
    /// @param market The target market contract address, such as the contract address of WETH
    /// @param account The address to burn the liquidity. The parameter is only used for emitting event
    /// @param receiver The address to receive the returned liquidity
    /// @return liquidity The liquidity to be returned to the LP
    function burnLPT(IERC20 market, address account, address receiver) external returns (uint96 liquidity);
}
