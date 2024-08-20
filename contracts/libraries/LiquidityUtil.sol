// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "../core/LPToken.sol";
import "./MarketUtil.sol";
import "./PositionUtil.sol";
import {SHORT} from "../types/Side.sol";
import {M as Math} from "./Math.sol";
import "./UnsafeMath.sol";
import "@openzeppelin/contracts/utils/Create2.sol";

/// @notice Utility library for managing liquidity
library LiquidityUtil {
    using SafeCast for *;
    using UnsafeMath for *;

    bytes32 internal constant LP_TOKEN_INIT_CODE_HASH =
        0xf7ee18f8779e8a47b9fee2bf37816783fe8615833733cf03cc48cd8fc3e3128b;

    struct MintParam {
        IERC20 market;
        address account;
        address receiver;
        uint96 liquidity;
        uint64 indexPrice;
    }

    struct BurnParam {
        IERC20 market;
        address account;
        address receiver;
        uint64 tokenValue;
        uint64 indexPrice;
    }

    function deployLPToken(IERC20 _market, string calldata _tokenSymbol) public returns (LPToken token) {
        token = new LPToken{salt: bytes32(uint256(uint160(address(_market))))}();
        token.initialize(_market, _tokenSymbol);
    }

    function computeLPTokenAddress(IERC20 _market) internal view returns (address) {
        return computeLPTokenAddress(_market, address(this));
    }

    function computeLPTokenAddress(IERC20 _market, address _deployer) internal pure returns (address) {
        return Create2.computeAddress(bytes32(uint256(uint160(address(_market)))), LP_TOKEN_INIT_CODE_HASH, _deployer);
    }

    function mintLPT(
        IMarketManager.State storage _state,
        IConfigurable.MarketConfig storage _cfg,
        MintParam memory _param
    ) public returns (uint64 tokenValue) {
        unchecked {
            IMarketManager.PackedState storage packedState = _state.packedState;
            uint128 liquidityBefore = packedState.lpLiquidity;
            uint256 liquidityAfter = uint256(liquidityBefore) + _param.liquidity;
            if (liquidityAfter > _cfg.liquidityCap)
                revert IMarketErrors.LiquidityCapExceeded(liquidityBefore, _param.liquidity, _cfg.liquidityCap);
            packedState.lpLiquidity = uint128(liquidityAfter);

            ILPToken token = ILPToken(computeLPTokenAddress(_param.market));
            uint256 totalSupply = token.totalSupply();
            if (totalSupply == 0) {
                tokenValue = PositionUtil.calcDecimals6TokenValue(
                    _param.liquidity,
                    _param.indexPrice,
                    _cfg.decimals,
                    Math.Rounding.Down
                );
            } else {
                int256 pnl = PositionUtil.calcUnrealizedPnL(
                    SHORT,
                    packedState.lpNetSize,
                    packedState.lpEntryPrice,
                    _param.indexPrice
                );
                tokenValue = Math
                    .mulDiv(_param.liquidity, totalSupply, (pnl + int256(uint256(liquidityBefore))).toUint256())
                    .toUint64();
            }

            // mint LPT
            token.mint(_param.receiver, tokenValue);
        }
        emit IMarketLiquidity.LPTMinted(_param.market, _param.account, _param.receiver, _param.liquidity, tokenValue);
    }

    function burnLPT(IMarketManager.State storage _state, BurnParam memory _param) public returns (uint96 liquidity) {
        IMarketManager.PackedState storage packedState = _state.packedState;
        (uint128 liquidityBefore, uint128 netSize) = (packedState.lpLiquidity, packedState.lpNetSize);
        int256 pnl = PositionUtil.calcUnrealizedPnL(SHORT, netSize, packedState.lpEntryPrice, _param.indexPrice);
        ILPToken token = ILPToken(computeLPTokenAddress(_param.market));
        unchecked {
            liquidity = Math
                .mulDiv((pnl + int256(uint256(liquidityBefore))).toUint256(), _param.tokenValue, token.totalSupply())
                .toUint96();
            if (uint256(netSize) + liquidity > liquidityBefore) revert IMarketErrors.BalanceRateCapExceeded();

            packedState.lpLiquidity = liquidityBefore - liquidity;
        }
        // burn LPT
        token.burn(_param.tokenValue);

        emit IMarketLiquidity.LPTBurned(_param.market, _param.account, _param.receiver, liquidity, _param.tokenValue);
    }

    function settlePosition(
        IMarketManager.PackedState storage _packedState,
        IERC20 _market,
        Side _side,
        uint64 _indexPrice,
        uint96 _sizeDelta
    ) internal {
        (uint128 netSize, uint64 entryPrice) = (_packedState.lpNetSize, _packedState.lpEntryPrice);
        unchecked {
            if (_side.isLong()) {
                uint64 entryPriceAfter = PositionUtil.calcNextEntryPrice(
                    SHORT,
                    netSize,
                    entryPrice,
                    _sizeDelta,
                    _indexPrice
                );
                _packedState.lpNetSize = netSize + _sizeDelta;
                _packedState.lpEntryPrice = entryPriceAfter;
                emit IMarketLiquidity.GlobalLiquiditySettled(_market, int256(uint256(_sizeDelta)), 0, entryPriceAfter);
            } else {
                int256 realizedPnL = PositionUtil.calcUnrealizedPnL(SHORT, _sizeDelta, entryPrice, _indexPrice);
                _packedState.lpLiquidity = (int256(uint256(_packedState.lpLiquidity)) + realizedPnL)
                    .toUint256()
                    .toUint128();
                _packedState.lpNetSize = netSize - _sizeDelta;

                emit IMarketLiquidity.GlobalLiquiditySettled(
                    _market,
                    -int256(uint256(_sizeDelta)),
                    realizedPnL,
                    entryPrice
                );
            }
        }
    }
}
