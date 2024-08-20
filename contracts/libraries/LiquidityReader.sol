// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "../misc/interfaces/IReader.sol";
import "../core/MarketManagerUpgradeable.sol";

library LiquidityReader {
    using SafeCast for *;

    function calcLPTPrice(
        IReader.ReaderState storage _readerState,
        IERC20 _market,
        uint64 _indexPrice
    ) public returns (uint256 totalSupply_, uint128 liquidity, uint64 price) {
        IMarketManager marketManager = _readerState.marketManager;
        if (!marketManager.isEnabledMarket(_market)) revert IConfigurable.MarketNotEnabled(_market);

        totalSupply_ = ILPToken(LiquidityUtil.computeLPTokenAddress(_market, address(marketManager))).totalSupply();
        if (totalSupply_ == 0) return (0, 0, Constants.PRICE_1);

        IReader.MockState storage mockState = _readerState.mockState;
        IMarketManager.State storage state = mockState.state;
        state.packedState = marketManager.packedStates(_market);
        mockState.marketConfig = marketManager.marketConfigs(_market);
        IConfigurable.MarketConfig storage marketConfig = mockState.marketConfig;

        IMarketManager.PackedState storage packedState = state.packedState;
        liquidity = packedState.lpLiquidity;
        int256 pnl = PositionUtil.calcUnrealizedPnL(
            SHORT,
            packedState.lpNetSize,
            packedState.lpEntryPrice,
            _indexPrice
        );
        unchecked {
            uint256 liquidityWithPnL = (pnl + int256(uint256(liquidity))).toUint256().toUint128();
            if (marketConfig.decimals >= Constants.DECIMALS_6) {
                price = Math
                    .mulDiv(
                        liquidityWithPnL,
                        _indexPrice,
                        totalSupply_ * (10 ** (marketConfig.decimals - Constants.DECIMALS_6))
                    )
                    .toUint64();
            } else {
                price = Math
                    .mulDiv(
                        liquidityWithPnL * (10 ** (Constants.DECIMALS_6 - marketConfig.decimals)),
                        _indexPrice,
                        totalSupply_
                    )
                    .toUint64();
            }
        }

        delete _readerState.mockState;
    }

    function quoteBurnPUSDToMintLPT(
        IReader.ReaderState storage _readerState,
        IERC20 _market,
        uint96 _amountIn,
        uint64 _indexPrice
    ) public returns (uint96 burnPUSDReceiveAmount, uint64 mintLPTTokenValue) {
        IMarketManager marketManager = _readerState.marketManager;
        if (!marketManager.isEnabledMarket(_market)) revert IConfigurable.MarketNotEnabled(_market);

        IReader.MockState storage mockState = _readerState.mockState;
        IMarketManager.State storage state = mockState.state;
        mockState.marketConfig = marketManager.marketConfigs(_market);
        IConfigurable.MarketConfig storage marketConfig = mockState.marketConfig;

        IMarketManager.PackedState memory packedState = marketManager.packedStates(_market);
        state.packedState = packedState;
        state.globalPUSDPosition = marketManager.globalPUSDPositions(_market);
        state.tokenBalance = marketManager.tokenBalances(_market);

        (, burnPUSDReceiveAmount) = PUSDManagerUtil.burn(
            state,
            marketConfig,
            PUSDManagerUtil.BurnParam({
                market: IERC20(address(this)), // for mock
                exactIn: true,
                amount: _amountIn,
                callback: IPUSDManagerCallback(address(this)), // for mock
                indexPrice: _indexPrice,
                usd: IPUSD(address(this)), // for mock
                receiver: address(this)
            }),
            bytes("")
        );

        uint256 totalSupply = ILPToken(LiquidityUtil.computeLPTokenAddress(_market, address(marketManager)))
            .totalSupply();
        LPToken token = LiquidityUtil.deployLPToken(IERC20(address(this)), "Mock");
        token.mint(address(this), totalSupply); // for mock

        mintLPTTokenValue = LiquidityUtil.mintLPT(
            state,
            marketConfig,
            LiquidityUtil.MintParam({
                market: IERC20(address(this)), // for mock
                account: address(this),
                receiver: address(this),
                liquidity: burnPUSDReceiveAmount,
                indexPrice: _indexPrice
            })
        );

        delete _readerState.mockState;
    }

    function quoteBurnLPTToMintPUSD(
        IReader.ReaderState storage _readerState,
        IERC20 _market,
        uint64 _amountIn,
        uint64 _indexPrice
    ) public returns (uint96 burnLPTReceiveAmount, uint64 mintPUSDTokenValue) {
        IMarketManager marketManager = _readerState.marketManager;
        if (!marketManager.isEnabledMarket(_market)) revert IConfigurable.MarketNotEnabled(_market);

        IReader.MockState storage mockState = _readerState.mockState;
        IMarketManager.State storage state = mockState.state;
        mockState.marketConfig = marketManager.marketConfigs(_market);
        IConfigurable.MarketConfig storage marketConfig = mockState.marketConfig;

        state.packedState = marketManager.packedStates(_market);
        state.globalPUSDPosition = marketManager.globalPUSDPositions(_market);
        state.tokenBalance = marketManager.tokenBalances(_market);

        uint256 totalSupply = ILPToken(LiquidityUtil.computeLPTokenAddress(_market, address(marketManager)))
            .totalSupply();
        LPToken token = LiquidityUtil.deployLPToken(IERC20(address(this)), "Mock");
        token.mint(address(this), totalSupply); // for mock

        burnLPTReceiveAmount = LiquidityUtil.burnLPT(
            state,
            LiquidityUtil.BurnParam({
                market: IERC20(address(this)), // for mock
                account: address(this),
                receiver: address(this),
                tokenValue: _amountIn,
                indexPrice: _indexPrice
            })
        );
        delete mockState.totalSupply; // reset totalSupply

        (, mintPUSDTokenValue) = PUSDManagerUtil.mint(
            state,
            marketConfig,
            PUSDManagerUtil.MintParam({
                market: IERC20(address(this)), // for mock
                exactIn: true,
                amount: burnLPTReceiveAmount,
                callback: IPUSDManagerCallback(address(this)), // for mock
                indexPrice: _indexPrice,
                usd: IPUSD(address(this)), // for mock
                receiver: address(this)
            }),
            msg.data // for mock
        );

        delete _readerState.mockState;
    }
}
