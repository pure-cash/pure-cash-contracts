// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.26;

import "./interfaces/IPriceFeed.sol";
import "../libraries/PriceFeedUtil.sol";
import "../governance/GovernableUpgradeable.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";

abstract contract PriceFeedUpgradeable is IPriceFeed, GovernableUpgradeable {
    using SafeCast for *;

    /// @custom:storage-location erc7201:Purecash.storage.PriceFeedUpgradeable
    struct PriceFeedStorage {
        /// @dev Ignore if reference price feed is not settled.
        bool ignoreReferencePriceFeedError;
        /// @dev Maximum deviation ratio between price and ChainLink price.
        uint24 maxDeviationRatio;
        /// @dev Period for calculating cumulative deviation ratio.
        uint32 cumulativeRoundDuration;
        /// @dev The timeout for price update transactions.
        uint32 updateTxTimeout;
        /// @dev The price updater address
        address updater;
        /// @dev Market price config
        mapping(IERC20 market => PriceFeedConfig) priceFeedConfigs;
        /// @dev Latest price
        mapping(IERC20 market => PricePack) latestPrices;
    }

    // keccak256(abi.encode(uint256(keccak256("Purecash.storage.PriceFeedUpgradeable")) - 1))
    // & ~bytes32(uint256(0xff))
    bytes32 private constant PRICE_FEED_UPGRADEABLE_STORAGE =
        0x58a0c8f0f88cec20fbd92b7b52b0d2d1fcf9b126fb78d3cc170d4a02c5be0900;

    function __PriceFeed_init(bool _ignoreReferencePriceFeedError, address _initialGov) internal onlyInitializing {
        __PriceFeed_init_unchained(_ignoreReferencePriceFeedError);
        __Governable_init(_initialGov);
    }

    function __PriceFeed_init_unchained(bool _ignoreReferencePriceFeedError) internal onlyInitializing {
        PriceFeedStorage storage $ = _priceFeedStorage();
        ($.maxDeviationRatio, $.cumulativeRoundDuration, $.updateTxTimeout) = (100e3, 1 minutes, 1 minutes);
        $.ignoreReferencePriceFeedError = _ignoreReferencePriceFeedError;
    }

    /// @inheritdoc IPriceFeed
    function updatePrice(PackedValue _packedValue) external override {
        PriceFeedStorage storage $ = _priceFeedStorage();
        if (msg.sender != $.updater) revert Forbidden();
        IERC20 _market = IERC20(_packedValue.unpackAddress(0));
        uint64 price = _packedValue.unpackUint64(160);
        uint32 timestamp = _packedValue.unpackUint32(224);
        PricePack storage pack = $.latestPrices[_market];
        if (!_updateMarketLastUpdated(pack, timestamp, $.updateTxTimeout)) return;
        PriceFeedConfig memory cfg = $.priceFeedConfigs[_market];
        if (address(cfg.refPriceFeed) == address(0)) {
            if (!$.ignoreReferencePriceFeedError) revert ReferencePriceFeedNotSet();
            pack.minPrice = price;
            pack.maxPrice = price;
            emit PriceUpdated(_market, price, price, price);
            return;
        }

        uint64 latestRefPrice = PriceFeedUtil.getReferencePrice(cfg, Constants.PRICE_DECIMALS);
        PriceDataItem memory dataItem = PriceDataItem({
            prevRound: pack.prevRound,
            prevRefPrice: pack.prevRefPrice,
            cumulativeRefPriceDelta: pack.cumulativeRefPriceDelta,
            prevPrice: pack.prevPrice,
            cumulativePriceDelta: pack.cumulativePriceDelta
        });
        bool reachMaxDeltaDiff = PriceFeedUtil.calcNewPriceDataItem(
            dataItem,
            price,
            latestRefPrice,
            cfg.maxCumulativeDeltaDiff,
            $.cumulativeRoundDuration
        );
        pack.prevRound = dataItem.prevRound;
        pack.prevRefPrice = dataItem.prevRefPrice;
        pack.cumulativeRefPriceDelta = dataItem.cumulativeRefPriceDelta;
        pack.prevPrice = dataItem.prevPrice;
        pack.cumulativePriceDelta = dataItem.cumulativePriceDelta;

        if (reachMaxDeltaDiff)
            emit MaxCumulativeDeltaDiffExceeded(
                _market,
                price,
                latestRefPrice,
                dataItem.cumulativePriceDelta,
                dataItem.cumulativeRefPriceDelta
            );
        (uint64 minPrice, uint64 maxPrice) = PriceFeedUtil.calcMinAndMaxPrice(
            price,
            latestRefPrice,
            $.maxDeviationRatio,
            reachMaxDeltaDiff
        );
        pack.minPrice = minPrice;
        pack.maxPrice = maxPrice;
        emit PriceUpdated(_market, price, minPrice, maxPrice);
    }

    /// @inheritdoc IPriceFeed
    function getPrice(IERC20 _market) external view override returns (uint64 minPrice, uint64 maxPrice) {
        (minPrice, maxPrice) = _getPrice(_market);
    }

    /// @inheritdoc IPriceFeed
    function updateUpdater(address _account) external override onlyGov {
        _priceFeedStorage().updater = _account;
    }

    /// @inheritdoc IPriceFeed
    function isUpdater(address _account) external view override returns (bool active) {
        return _priceFeedStorage().updater == _account;
    }

    /// @inheritdoc IPriceFeed
    function updateGlobalPriceFeedConfig(
        uint24 _maxDeviationRatio,
        uint32 _cumulativeRoundDuration,
        uint32 _updateTxTimeout,
        bool _ignoreReferencePriceFeedError
    ) external override onlyGov {
        PriceFeedStorage storage $ = _priceFeedStorage();
        ($.maxDeviationRatio, $.cumulativeRoundDuration, $.updateTxTimeout, $.ignoreReferencePriceFeedError) = (
            _maxDeviationRatio,
            _cumulativeRoundDuration,
            _updateTxTimeout,
            _ignoreReferencePriceFeedError
        );
    }

    /// @inheritdoc IPriceFeed
    function globalPriceFeedConfig()
        external
        view
        override
        returns (
            uint24 maxDeviationRatio,
            uint32 cumulativeRoundDuration,
            uint32 updateTxTimeout,
            bool ignoreReferencePriceFeedError
        )
    {
        PriceFeedStorage storage $ = _priceFeedStorage();
        return ($.maxDeviationRatio, $.cumulativeRoundDuration, $.updateTxTimeout, $.ignoreReferencePriceFeedError);
    }

    /// @inheritdoc IPriceFeed
    function updateMarketPriceFeedConfig(
        IERC20 _market,
        IChainLinkAggregator _priceFeed,
        uint32 _refHeartBeatDuration,
        uint48 _maxCumulativeDeltaDiff
    ) external override onlyGov {
        uint8 refPriceDecimals;
        if (address(_priceFeed) != address(0x0)) refPriceDecimals = _priceFeed.decimals();
        _priceFeedStorage().priceFeedConfigs[_market] = PriceFeedConfig({
            refPriceFeed: _priceFeed,
            refHeartbeatDuration: _refHeartBeatDuration,
            maxCumulativeDeltaDiff: _maxCumulativeDeltaDiff,
            refPriceDecimals: refPriceDecimals
        });
    }

    /// @inheritdoc IPriceFeed
    function marketPriceFeedConfigs(IERC20 _market) external view override returns (PriceFeedConfig memory config) {
        config = _priceFeedStorage().priceFeedConfigs[_market];
    }

    /// @inheritdoc IPriceFeed
    function marketPricePacks(IERC20 _market) external view override returns (PricePack memory pack) {
        pack = _priceFeedStorage().latestPrices[_market];
        return pack;
    }

    function _getPrice(IERC20 _market) internal view returns (uint64 minPrice, uint64 maxPrice) {
        PricePack storage price = _priceFeedStorage().latestPrices[_market];
        (minPrice, maxPrice) = (price.minPrice, price.maxPrice);
        if (minPrice | maxPrice == 0) revert NotInitialized();
    }

    function _getMinPrice(IERC20 _market) internal view returns (uint64 minPrice) {
        minPrice = _priceFeedStorage().latestPrices[_market].minPrice;
        if (minPrice == 0) revert NotInitialized();
    }

    function _getMaxPrice(IERC20 _market) internal view returns (uint64 maxPrice) {
        maxPrice = _priceFeedStorage().latestPrices[_market].maxPrice;
        if (maxPrice == 0) revert NotInitialized();
    }

    function _updateMarketLastUpdated(
        PricePack storage _latestPrice,
        uint32 _timestamp,
        uint32 _updateTxTimeout
    ) internal returns (bool) {
        // Execution delay may cause the update time to be out of order.
        if (_timestamp <= _latestPrice.updateTimestamp) return false;

        // timeout and revert
        if (_timestamp >= block.timestamp + _updateTxTimeout) revert InvalidUpdateTimestamp(_timestamp);

        _latestPrice.updateTimestamp = _timestamp;
        return true;
    }

    function _priceFeedStorage() internal pure returns (PriceFeedStorage storage $) {
        // prettier-ignore
        assembly { $.slot := PRICE_FEED_UPGRADEABLE_STORAGE }
    }
}
