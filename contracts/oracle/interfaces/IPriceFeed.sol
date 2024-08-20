// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "./IChainLinkAggregator.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "../../types/PackedValue.sol";

interface IPriceFeed {
    struct PriceFeedConfig {
        /// @notice ChainLink contract address for corresponding market
        IChainLinkAggregator refPriceFeed;
        /// @notice Expected update interval of chain link price feed
        uint32 refHeartbeatDuration;
        /// @notice Maximum cumulative change ratio difference between prices and ChainLink price
        /// within a period of time.
        uint48 maxCumulativeDeltaDiff;
        /// @notice Decimals of ChainLink price
        uint8 refPriceDecimals;
    }

    struct PriceDataItem {
        /// @notice previous round id
        uint32 prevRound;
        /// @notice previous ChainLink price
        uint64 prevRefPrice;
        /// @notice cumulative value of the ChainLink price change ratio in a round
        uint64 cumulativeRefPriceDelta;
        /// @notice previous market price
        uint64 prevPrice;
        /// @notice cumulative value of the market price change ratio in a round
        uint64 cumulativePriceDelta;
    }

    struct PricePack {
        /// @notice The timestamp when updater uploads the price
        uint32 updateTimestamp;
        /// @notice Calculated maximum price
        uint64 maxPrice;
        /// @notice Calculated minimum price
        uint64 minPrice;
        /// @notice previous round id
        uint32 prevRound;
        /// @notice previous ChainLink price
        uint64 prevRefPrice;
        /// @notice cumulative value of the ChainLink price change ratio in a round
        uint64 cumulativeRefPriceDelta;
        /// @notice previous market price
        uint64 prevPrice;
        /// @notice cumulative value of the market price change ratio in a round
        uint64 cumulativePriceDelta;
    }

    /// @notice Emitted when market price updated
    /// @param market Market address
    /// @param price The price passed in by updater
    /// @param maxPrice Calculated maximum price
    /// @param minPrice Calculated minimum price
    event PriceUpdated(IERC20 indexed market, uint64 price, uint64 minPrice, uint64 maxPrice);

    /// @notice Emitted when maxCumulativeDeltaDiff exceeded
    /// @param market Market address
    /// @param price The price passed in by updater
    /// @param refPrice The price provided by ChainLink
    /// @param cumulativeDelta The cumulative value of the price change ratio
    /// @param cumulativeRefDelta The cumulative value of the ChainLink price change ratio
    event MaxCumulativeDeltaDiffExceeded(
        IERC20 indexed market,
        uint64 price,
        uint64 refPrice,
        uint64 cumulativeDelta,
        uint64 cumulativeRefDelta
    );

    /// @notice Price not be initialized
    error NotInitialized();

    /// @notice Reference price feed not set
    error ReferencePriceFeedNotSet();

    /// @notice Invalid reference price
    /// @param referencePrice Reference price
    error InvalidReferencePrice(int256 referencePrice);

    /// @notice Reference price timeout
    /// @param elapsed The time elapsed since the last price update.
    error ReferencePriceTimeout(uint256 elapsed);

    /// @notice Invalid update timestamp
    /// @param timestamp Update timestamp
    error InvalidUpdateTimestamp(uint32 timestamp);

    /// @notice Update market price feed config
    /// @param market Market address
    /// @param priceFeed ChainLink price feed
    /// @param refHeartBeatDuration Expected update interval of chain link price feed
    /// @param maxCumulativeDeltaDiff Maximum cumulative change ratio difference between prices and ChainLink price
    function updateMarketPriceFeedConfig(
        IERC20 market,
        IChainLinkAggregator priceFeed,
        uint32 refHeartBeatDuration,
        uint48 maxCumulativeDeltaDiff
    ) external;

    /// @notice Get market price feed config
    /// @param market Market address
    /// @return config The price feed config
    function marketPriceFeedConfigs(IERC20 market) external view returns (PriceFeedConfig memory config);

    /// @notice update global price feed config
    /// @param maxDeviationRatio Maximum deviation ratio between ChainLink price and market price
    /// @param cumulativeRoundDuration The duration of the round for the cumulative value of the price change ratio
    /// @param updateTxTimeout The maximum time allowed for the transaction to update the price
    /// @param ignoreReferencePriceFeedError Whether to ignore the error of the reference price feed not settled
    function updateGlobalPriceFeedConfig(
        uint24 maxDeviationRatio,
        uint32 cumulativeRoundDuration,
        uint32 updateTxTimeout,
        bool ignoreReferencePriceFeedError
    ) external;

    /// @notice Get global price feed config
    /// @return maxDeviationRatio Maximum deviation ratio between ChainLink price and market price
    /// @return cumulativeRoundDuration The duration of the round for the cumulative value of the price change ratio
    /// @return updateTxTimeout The maximum time allowed for the transaction to update the price
    /// @return ignoreReferencePriceFeedError Whether to ignore the error of the reference price feed not settled
    function globalPriceFeedConfig()
        external
        view
        returns (
            uint24 maxDeviationRatio,
            uint32 cumulativeRoundDuration,
            uint32 updateTxTimeout,
            bool ignoreReferencePriceFeedError
        );

    /// @notice Update updater
    /// @param account The account to set
    function updateUpdater(address account) external;

    /// @notice Get market price
    /// @param market Market address
    /// @return minPrice Minimum price
    /// @return maxPrice Maximum price
    function getPrice(IERC20 market) external view returns (uint64 minPrice, uint64 maxPrice);

    /// @notice Check if the account is updater
    /// @param account The account to check
    /// @return active True if the account is updater
    function isUpdater(address account) external view returns (bool active);

    /// @notice Update market price
    /// @param packedValue The packed values of the order index and require success flag: bit 0-159 represent
    /// market address, bit 160-223 represent the price and bit 223-255 represent the update timestamp
    function updatePrice(PackedValue packedValue) external;

    /// @notice Get market price data packed data
    /// @param market Market address
    /// @return pack The price packed data
    function marketPricePacks(IERC20 market) external view returns (PricePack memory pack);
}
