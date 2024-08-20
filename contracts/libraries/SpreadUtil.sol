// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "./Constants.sol";
import "../core/interfaces/IMarketManager.sol";
import {M as Math} from "../libraries/Math.sol";
import "solady/src/utils/FixedPointMathLib.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";

library SpreadUtil {
    using SafeCast for *;
    using FixedPointMathLib for *;

    struct CalcSpreadParam {
        Side side;
        uint96 sizeDelta;
        int256 spreadFactorBeforeX96;
        uint64 lastTradingTimestamp;
    }

    /// @notice Calculate the trade spread when operating on positions or mint/burn PUSD
    /// @param _cfg The market configuration
    /// @return spreadAmount The amount of trade spread
    /// @return spreadFactorAfterX96 The spread factor after the trade, as a Q160.96
    function calcSpread(
        IConfigurable.MarketConfig storage _cfg,
        CalcSpreadParam memory _param
    ) internal view returns (uint96 spreadAmount, int256 spreadFactorAfterX96) {
        uint256 spreadX96;
        (spreadFactorAfterX96, spreadX96) = refreshSpread(_cfg, _param);

        spreadAmount = calcSpreadAmount(spreadX96, _param.sizeDelta, Math.Rounding.Up);

        spreadFactorAfterX96 = calcSpreadFactorAfterX96(spreadFactorAfterX96, _param.side, _param.sizeDelta);
    }

    function calcSpreadAmount(
        uint256 _spreadX96,
        uint96 _sizeDelta,
        Math.Rounding _rounding
    ) internal pure returns (uint96 spreadAmount) {
        spreadAmount = Math.mulDiv(_spreadX96, _sizeDelta, Constants.Q96, _rounding).toUint96();
    }

    function calcSpreadFactorAfterX96(
        int256 _spreadFactorBeforeX96,
        Side _side,
        uint96 _sizeDelta
    ) internal pure returns (int256 spreadFactorAfterX96) {
        unchecked {
            int256 sizeDeltaX96 = int256(uint256(_sizeDelta) << 96);
            spreadFactorAfterX96 = _side.isLong()
                ? _spreadFactorBeforeX96 + sizeDeltaX96
                : _spreadFactorBeforeX96 - sizeDeltaX96;
        }
    }

    /// @notice Refresh the spread factor since last trading and calculate the spread
    function refreshSpread(
        IConfigurable.MarketConfig storage _cfg,
        CalcSpreadParam memory _param
    ) internal view returns (int256 spreadFactorAfterX96, uint256 spreadX96) {
        unchecked {
            uint256 riskFreeTime = _cfg.riskFreeTime;
            uint256 timeInterval = block.timestamp - _param.lastTradingTimestamp;
            if (timeInterval >= riskFreeTime || _param.spreadFactorBeforeX96 == 0) return (0, 0);

            // Due to `Math.Rounding.Up`, if `spreadFactorBeforeX96Abs` > `0`, then `spreadFactorAfterX96Abs` > `0`
            uint256 spreadFactorAfterX96Abs = Math.ceilDiv(
                _param.spreadFactorBeforeX96.abs() * (riskFreeTime - timeInterval),
                riskFreeTime
            );

            spreadFactorAfterX96 = _param.spreadFactorBeforeX96 > 0
                ? int256(spreadFactorAfterX96Abs)
                : -int256(spreadFactorAfterX96Abs);

            spreadX96 = (_param.side.isLong() && spreadFactorAfterX96 > 0) ||
                (_param.side.isShort() && spreadFactorAfterX96 < 0)
                ? 0
                : Math.ceilDiv(spreadFactorAfterX96Abs, _cfg.liquidityScale);
        }
    }
}
