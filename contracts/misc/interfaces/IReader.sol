// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "../../core/interfaces/IMarketManager.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IReader {
    struct ReaderState {
        IMarketManager marketManager;
        MockState mockState;
    }

    struct MockState {
        IMarketManager.State state;
        IConfigurable.MarketConfig marketConfig;
        uint256 totalSupply;
    }

    /// @notice Calculate the price of the LP Token
    /// @param market The target market contract address, such as the contract address of WETH
    /// @param indexPrice The index price of the market
    /// @return totalSupply The total supply of the LP Token
    /// @return liquidity The liquidity of the LP Token
    /// @return price The price of the LP Token
    function calcLPTPrice(
        IERC20 market,
        uint64 indexPrice
    ) external returns (uint256 totalSupply, uint128 liquidity, uint64 price);

    /// @notice Calculates the amount when user minting PUSD
    /// @param market The target market contract address, such as the contract address of WETH
    /// @param amount When `exactIn` is true, it is the amount of token to pay,
    /// otherwise, it is the amount of PUSD to mint
    /// @param indexPrice The index price of the market
    /// @return payAmount The amount of market tokens to pay
    /// @return receiveAmount The amount of PUSD to receive
    function quoteMintPUSD(
        IERC20 market,
        bool exactIn,
        uint96 amount,
        uint64 indexPrice
    ) external returns (uint96 payAmount, uint64 receiveAmount);

    /// @notice Calculates the amount when user burning PUSD
    /// @param market The target market contract address, such as the contract address of WETH
    /// @param amount When `exactIn` is true, it is the amount of PUSD to burn,
    /// otherwise, it is the amount of token to receive
    /// @param indexPrice The index price of the market
    /// @return payAmount The amount of PUSD to pay
    /// @return receiveAmount The amount of market tokens to receive
    function quoteBurnPUSD(
        IERC20 market,
        bool exactIn,
        uint96 amount,
        uint64 indexPrice
    ) external returns (uint64 payAmount, uint96 receiveAmount);

    /// @notice Calculates the amount of LPT tokens that can be minted by burning a given amount of PUSD
    /// @dev Uses the provided index price to determine the conversion rates
    /// @param market The target market contract address, such as the contract address of WETH
    /// @param amountIn The amount of PUSD to be burned
    /// @param indexPrice The index price of the market
    /// @return burnPUSDReceiveAmount The amount of market tokens received after burning the provided PUSD
    /// @return mintLPTTokenValue The amount of LPT tokens minted using `burnPUSDReceiveAmount`
    function quoteBurnPUSDToMintLPT(
        IERC20 market,
        uint96 amountIn,
        uint64 indexPrice
    ) external returns (uint96 burnPUSDReceiveAmount, uint64 mintLPTTokenValue);

    /// @notice Calculates the amount of PUSD tokens minted when burning a given amount of LPT tokens
    /// @dev Uses the provided index price to determine the conversion rates
    /// @param market The target market contract address, such as the contract address of WETH
    /// @param amountIn The amount of LPT tokens to be burned
    /// @param indexPrice The index price of the market
    /// @return burnLPTReceiveAmount The amount of market tokens received after burning the provided LPT tokens
    /// @return mintPUSDTokenValue The amount of PUSD tokens minted using `burnLPTReceiveAmount`
    function quoteBurnLPTToMintPUSD(
        IERC20 market,
        uint64 amountIn,
        uint64 indexPrice
    ) external returns (uint96 burnLPTReceiveAmount, uint64 mintPUSDTokenValue);

    /// @notice Calculates the results of burning PUSD to increase a position in a given market
    /// @dev Uses the provided index price and leverage to determine the conversion rates
    /// @param market The target market contract address, such as the contract address of WETH
    /// @param account The owner of the position
    /// @param amountIn The amount of PUSD to be burned
    /// @param indexPrice The index price of the market
    /// @param leverage The leverage to be applied for this position increase operation,
    /// denominated in thousandths of a bip (i.e. 1e-7)
    /// @return burnPUSDReceiveAmount The amount of market tokens received after burning the provided PUSD
    /// @return size The position size to increase
    /// @return position The updated position after the operation
    function quoteBurnPUSDToIncreasePosition(
        IERC20 market,
        address account,
        uint64 amountIn,
        uint64 indexPrice,
        uint32 leverage
    ) external returns (uint96 burnPUSDReceiveAmount, uint96 size, IMarketPosition.Position memory position);

    /// @notice Calculates the results of decreasing a position to mint PUSD tokens in a given market
    /// @dev Uses the provided index price to determine the conversion rates and position changes
    /// @param market The target market contract address, such as the contract address of WETH
    /// @param account The owner of the position
    /// @param size The size of the position to be decreased
    /// @param indexPrice The index price of the market
    /// @return decreasePositionReceiveAmount The amount of market tokens received after decreasing the position
    /// @return mintPUSDTokenValue The amount of PUSD tokens minted using `decreasePositionReceiveAmount`
    /// @return marginAfter The margin remaining in the position after the operation
    function quoteDecreasePositionToMintPUSD(
        IERC20 market,
        address account,
        uint96 size,
        uint64 indexPrice
    ) external returns (uint96 decreasePositionReceiveAmount, uint64 mintPUSDTokenValue, uint96 marginAfter);

    /// @notice Calculate the market tokens required to pay based on the increase position size
    /// @dev Uses the provided index price and leverage to determine the conversion rates
    /// @param market The target market contract address, such as the contract address of WETH
    /// @param account The owner of the position
    /// @param size The size of the position to be increased
    /// @param leverage The leverage to be applied for this position increase operation,
    /// denominated in thousandths of a bip (i.e. 1e-7)
    /// @param indexPrice The index price of the market
    /// @return payAmount The amount of market tokens to pay
    /// @return marginAfter The adjusted margin
    /// @return spread The spread incurred by the position
    /// @return tradingFee The trading fee paid by the position
    /// @return liquidationPrice The liquidation price after increasing position
    function quoteIncreasePositionBySize(
        IERC20 market,
        address account,
        uint96 size,
        uint32 leverage,
        uint64 indexPrice
    )
        external
        returns (uint96 payAmount, uint96 marginAfter, uint96 spread, uint96 tradingFee, uint64 liquidationPrice);

    /// @notice Calculate min and max price if passed a specific price value
    /// @param marketPrices Array of market addresses and prices to update for
    /// @return minPrices The minimum price for each market
    /// @return maxPrices The maximum price for each market
    function calcPrices(
        PackedValue[] calldata marketPrices
    ) external view returns (uint64[] memory minPrices, uint64[] memory maxPrices);
}
