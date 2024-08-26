// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "./interfaces/IReader.sol";
import "../libraries/PositionReader.sol";
import "../libraries/LiquidityReader.sol";
import "../libraries/PriceFeedUtil.sol";

contract Reader is IReader {
    using SafeCast for *;
    using UnsafeMath for *;

    ReaderState readerState;

    constructor(MarketManagerUpgradeable _marketManager) {
        readerState.marketManager = _marketManager;
    }

    /// @inheritdoc IReader
    function calcLPTPrice(
        IERC20 _market,
        uint64 _indexPrice
    ) public override returns (uint256 totalSupply_, uint128 liquidity, uint64 price) {
        return LiquidityReader.calcLPTPrice(readerState, _market, _indexPrice);
    }

    /// @inheritdoc IReader
    function quoteMintPUSD(
        IERC20 _market,
        bool _exactIn,
        uint96 _amount,
        uint64 _indexPrice
    ) public override returns (uint96 payAmount, uint64 receiveAmount) {
        IMarketManager marketManager = readerState.marketManager;
        if (!marketManager.isEnabledMarket(_market)) revert IConfigurable.MarketNotEnabled(_market);

        MockState storage mockState = readerState.mockState;
        IMarketManager.State storage state = mockState.state;
        mockState.marketConfig = marketManager.marketConfigs(_market);
        IConfigurable.MarketConfig storage marketConfig = mockState.marketConfig;

        state.packedState = marketManager.packedStates(_market);
        IPUSDManager.GlobalPUSDPosition memory pusdPosition = marketManager.globalPUSDPositions(_market);
        state.globalPUSDPosition = pusdPosition;
        state.tokenBalance = marketManager.tokenBalances(_market);

        PUSD pusd = PUSDManagerUtil.deployPUSD();
        pusd.mint(address(this), pusdPosition.totalSupply); // for mock
        (payAmount, receiveAmount) = PUSDManagerUtil.mint(
            state,
            marketConfig,
            PUSDManagerUtil.MintParam({
                market: IERC20(address(this)), // for mock
                exactIn: _exactIn,
                amount: _amount,
                callback: IPUSDManagerCallback(address(this)), // for mock
                indexPrice: _indexPrice,
                receiver: address(this)
            }),
            msg.data // for mock
        );

        delete readerState.mockState;
    }

    /// @inheritdoc IReader
    function quoteBurnPUSD(
        IERC20 _market,
        bool _exactIn,
        uint96 _amount,
        uint64 _indexPrice
    ) public override returns (uint64 payAmount, uint96 receiveAmount) {
        IMarketManager marketManager = readerState.marketManager;
        if (!marketManager.isEnabledMarket(_market)) revert IConfigurable.MarketNotEnabled(_market);

        MockState storage mockState = readerState.mockState;
        IMarketManager.State storage state = mockState.state;
        mockState.marketConfig = marketManager.marketConfigs(_market);
        IConfigurable.MarketConfig storage marketConfig = mockState.marketConfig;

        state.packedState = marketManager.packedStates(_market);
        IPUSDManager.GlobalPUSDPosition memory pusdPosition = marketManager.globalPUSDPositions(_market);
        state.globalPUSDPosition = pusdPosition;
        state.tokenBalance = marketManager.tokenBalances(_market);

        PUSD pusd = PUSDManagerUtil.deployPUSD(); // for mock
        pusd.mint(address(this), pusdPosition.totalSupply);
        (payAmount, receiveAmount) = PUSDManagerUtil.burn(
            state,
            marketConfig,
            PUSDManagerUtil.BurnParam({
                market: IERC20(address(this)), // for mock
                exactIn: _exactIn,
                amount: _amount,
                callback: IPUSDManagerCallback(address(this)), // for mock
                indexPrice: _indexPrice,
                receiver: address(this)
            }),
            bytes("")
        );

        delete readerState.mockState;
    }

    /// @inheritdoc IReader
    function quoteBurnPUSDToMintLPT(
        IERC20 _market,
        uint96 _amountIn,
        uint64 _indexPrice
    ) public override returns (uint96 burnPUSDReceiveAmount, uint64 mintLPTTokenValue) {
        return LiquidityReader.quoteBurnPUSDToMintLPT(readerState, _market, _amountIn, _indexPrice);
    }

    /// @inheritdoc IReader
    function quoteBurnLPTToMintPUSD(
        IERC20 _market,
        uint64 _amountIn,
        uint64 _indexPrice
    ) public override returns (uint96 burnLPTReceiveAmount, uint64 mintPUSDTokenValue) {
        return LiquidityReader.quoteBurnLPTToMintPUSD(readerState, _market, _amountIn, _indexPrice);
    }

    /// @inheritdoc IReader
    function quoteBurnPUSDToIncreasePosition(
        IERC20 _market,
        address _account,
        uint64 _amountIn,
        uint64 _indexPrice,
        uint32 _leverage
    ) public override returns (uint96 burnPUSDReceiveAmount, uint96 size, IMarketPosition.Position memory position) {
        return
            PositionReader.quoteBurnPUSDToIncreasePosition(
                readerState,
                _market,
                _account,
                _amountIn,
                _indexPrice,
                _leverage
            );
    }

    /// @inheritdoc IReader
    function quoteDecreasePositionToMintPUSD(
        IERC20 _market,
        address _account,
        uint96 _size,
        uint64 _indexPrice
    ) public override returns (uint96 decreasePositionReceiveAmount, uint64 mintPUSDTokenValue, uint96 marginAfter) {
        return PositionReader.quoteDecreasePositionToMintPUSD(readerState, _market, _account, _size, _indexPrice);
    }

    /// @inheritdoc IReader
    function quoteIncreasePositionBySize(
        IERC20 _market,
        address _account,
        uint96 _size,
        uint32 _leverage,
        uint64 _indexPrice
    )
        public
        override
        returns (uint96 payAmount, uint96 marginAfter, uint96 spread, uint96 tradingFee, uint64 liquidationPrice)
    {
        return
            PositionReader.quoteIncreasePositionBySize(readerState, _market, _account, _size, _leverage, _indexPrice);
    }

    function longPositions(address _account) external view returns (IMarketPosition.Position memory) {
        return readerState.mockState.state.longPositions[_account];
    }

    /// @inheritdoc IReader
    function calcPrices(
        PackedValue[] calldata _marketPrices
    ) external view override returns (uint64[] memory minPrices, uint64[] memory maxPrices) {
        (uint24 maxDeviationRatio, uint32 cumulativeRoundDuration, , bool ignoreReferencePriceFeedError) = readerState
            .marketManager
            .globalPriceFeedConfig();

        uint256 pricesLength = _marketPrices.length;
        minPrices = new uint64[](pricesLength);
        maxPrices = new uint64[](pricesLength);
        for (uint256 i; i < pricesLength; ++i) {
            IERC20 market = IERC20(_marketPrices[i].unpackAddress(0));
            uint64 price = _marketPrices[i].unpackUint64(160);
            IPriceFeed.PriceFeedConfig memory cfg = readerState.marketManager.marketPriceFeedConfigs(market);
            if (address(cfg.refPriceFeed) == address(0)) {
                if (!ignoreReferencePriceFeedError) revert IPriceFeed.ReferencePriceFeedNotSet();
                minPrices[i] = price.toUint64();
                maxPrices[i] = price.toUint64();
                continue;
            }

            uint64 latestRefPrice = PriceFeedUtil.getReferencePrice(cfg, Constants.PRICE_DECIMALS);

            IPriceFeed.PricePack memory pack = readerState.marketManager.marketPricePacks(market);
            IPriceFeed.PriceDataItem memory dataItem = IPriceFeed.PriceDataItem({
                prevRound: pack.prevRound,
                prevRefPrice: pack.prevRefPrice,
                cumulativeRefPriceDelta: pack.cumulativePriceDelta,
                prevPrice: pack.prevPrice,
                cumulativePriceDelta: pack.cumulativePriceDelta
            });
            bool reachMaxDeltaDiff = PriceFeedUtil.calcNewPriceDataItem(
                dataItem,
                price,
                latestRefPrice,
                cfg.maxCumulativeDeltaDiff,
                cumulativeRoundDuration
            );

            (uint256 minPrice, uint256 maxPrice) = PriceFeedUtil.calcMinAndMaxPrice(
                price,
                latestRefPrice,
                maxDeviationRatio,
                reachMaxDeltaDiff
            );
            (minPrices[i], maxPrices[i]) = (minPrice.toUint64(), maxPrice.toUint64());
        }
        return (minPrices, maxPrices);
    }

    // The following methods are mock methods for calculation

    function PUSDManagerCallback(IERC20 _token, uint96 _payAmount, uint96, bytes calldata) external {
        require(msg.sender == address(this));
        readerState.mockState.totalSupply = _payAmount;

        if (address(_token) == PUSDManagerUtil.computePUSDAddress())
            PUSD(address(_token)).mint(address(this), _payAmount);
    }

    function transfer(address, uint256) external view returns (bool) {
        require(msg.sender == address(this));
        return true;
    }

    function balanceOf(address) external view returns (uint256) {
        return readerState.mockState.totalSupply;
    }

    function totalSupply() external view returns (uint256) {
        return readerState.mockState.totalSupply;
    }
}
