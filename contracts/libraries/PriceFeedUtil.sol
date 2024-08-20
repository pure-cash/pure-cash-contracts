// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "./Constants.sol";
import "./UnsafeMath.sol";
import "../oracle/interfaces/IPriceFeed.sol";
import "../oracle/interfaces/IChainLinkAggregator.sol";
import "solady/src/utils/FixedPointMathLib.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";

library PriceFeedUtil {
    using SafeCast for *;
    using UnsafeMath for *;
    using FixedPointMathLib for *;

    /// @dev value difference precision
    uint256 public constant DELTA_PRECISION = 1000 * 1000;

    function getReferencePrice(
        IPriceFeed.PriceFeedConfig memory _cfg,
        uint8 _priceDecimals
    ) internal view returns (uint64 latestRefPrice) {
        (, int256 refPrice, , uint256 timestamp, ) = _cfg.refPriceFeed.latestRoundData();
        if (refPrice <= 0) revert IPriceFeed.InvalidReferencePrice(refPrice);

        if (_cfg.refHeartbeatDuration != 0) {
            uint256 timeDiff = block.timestamp.dist(timestamp);
            if (timeDiff > _cfg.refHeartbeatDuration) revert IPriceFeed.ReferencePriceTimeout(timeDiff);
        }

        latestRefPrice = (
            _cfg.refPriceDecimals >= _priceDecimals
                ? uint256(refPrice).divU256(10 ** _cfg.refPriceDecimals.dist(_priceDecimals))
                : uint256(refPrice) * (10 ** _cfg.refPriceDecimals.dist(_priceDecimals))
        ).toUint64();
    }

    function calcMinAndMaxPrice(
        uint64 _price,
        uint64 _refPrice,
        uint24 _maxDeviationRatio,
        bool _reachMaxDeltaDiff
    ) internal pure returns (uint64 minPrice, uint64 maxPrice) {
        (minPrice, maxPrice) = (_price, _price);
        if (_reachMaxDeltaDiff || calcDiffBasisPoints(_price, _refPrice) > _maxDeviationRatio) {
            if (_price > _refPrice) minPrice = _refPrice;
            else maxPrice = _refPrice;
        }
    }

    function calcDiffBasisPoints(uint64 _price, uint64 _basisPrice) internal pure returns (uint64) {
        // prettier-ignore
        unchecked { return uint64((_price.dist(_basisPrice) * DELTA_PRECISION) / _basisPrice); }
    }

    function calcNewPriceDataItem(
        IPriceFeed.PriceDataItem memory _item,
        uint64 _price,
        uint64 _refPrice,
        uint48 _maxCumulativeDeltaDiffs,
        uint32 _cumulativeRoundDuration
    ) internal view returns (bool reachMaxDeltaDiff) {
        uint32 currentRound;
        // prettier-ignore
        unchecked { currentRound = uint32(block.timestamp / _cumulativeRoundDuration); }
        if (currentRound != _item.prevRound) {
            _item.cumulativePriceDelta = 0;
            _item.cumulativeRefPriceDelta = 0;
            _item.prevRefPrice = _refPrice;
            _item.prevPrice = _price;
            _item.prevRound = currentRound;
            return false;
        }
        uint64 cumulativeRefPriceDelta = calcDiffBasisPoints(_refPrice, _item.prevRefPrice);
        uint64 cumulativePriceDelta = calcDiffBasisPoints(_price, _item.prevPrice);

        _item.cumulativeRefPriceDelta = _item.cumulativeRefPriceDelta + cumulativeRefPriceDelta;
        _item.cumulativePriceDelta = _item.cumulativePriceDelta + cumulativePriceDelta;
        unchecked {
            if (
                _item.cumulativePriceDelta > _item.cumulativeRefPriceDelta &&
                _item.cumulativePriceDelta - _item.cumulativeRefPriceDelta > _maxCumulativeDeltaDiffs
            ) reachMaxDeltaDiff = true;

            _item.prevRefPrice = _refPrice;
            _item.prevPrice = _price;
            _item.prevRound = currentRound;
            return reachMaxDeltaDiff;
        }
    }
}
