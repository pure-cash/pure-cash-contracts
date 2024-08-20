// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.26;

import "./PSMUpgradeable.sol";
import "../libraries/PUSDManagerUtil.sol";
import "../libraries/LiquidityUtil.sol";
import "../plugins/PluginManagerUpgradeable.sol";
import "../oracle/PriceFeedUpgradeable.sol";

/// @custom:oz-upgrades-unsafe-allow external-library-linking
contract MarketManagerUpgradeable is PSMUpgradeable, PriceFeedUpgradeable {
    using SafeCast for *;
    using SafeERC20 for IERC20;
    using MarketUtil for State;
    using PositionUtil for State;
    using PUSDManagerUtil for State;
    using LiquidityUtil for State;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _initialGov,
        FeeDistributorUpgradeable _feeDistributor,
        IPUSD _usd,
        bool _ignoreReferencePriceFeedError
    ) public initializer {
        PSMUpgradeable.__PSM_init(_initialGov, _feeDistributor, _usd);
        PriceFeedUpgradeable.__PriceFeed_init_unchained(_ignoreReferencePriceFeedError);
    }

    /// @inheritdoc IMarketLiquidity
    function mintLPT(
        IERC20 _market,
        address _account,
        address _receiver
    ) external override nonReentrant returns (uint64 tokenValue) {
        _onlyPlugin();

        MarketManagerStatesStorage storage $ = _statesStorage();
        State storage state = $.marketStates[_market];

        uint128 balanceAfter = _market.balanceOf(address(this)).toUint128();
        uint96 liquidity = (balanceAfter - state.tokenBalance).toUint96();
        state.tokenBalance = balanceAfter;

        tokenValue = state.mintLPT(
            _configurableStorage().marketConfigs[_market],
            LiquidityUtil.MintParam({
                market: _market,
                account: _account,
                receiver: _receiver,
                liquidity: liquidity,
                indexPrice: _getMaxPrice(_market)
            })
        );
    }

    /// @inheritdoc IMarketLiquidity
    function burnLPT(
        IERC20 _market,
        address _account,
        address _receiver
    ) external override nonReentrant returns (uint96 liquidity) {
        _onlyPlugin();

        MarketManagerStatesStorage storage $ = _statesStorage();
        State storage state = $.marketStates[_market];

        liquidity = state.burnLPT(
            LiquidityUtil.BurnParam({
                market: _market,
                account: _account,
                receiver: _receiver,
                tokenValue: ILPToken(LiquidityUtil.computeLPTokenAddress(_market)).balanceOf(address(this)).toUint64(),
                indexPrice: _getMaxPrice(_market)
            })
        );

        state.tokenBalance -= liquidity;
        _market.safeTransfer(_receiver, liquidity);
    }

    /// @inheritdoc IMarketManager
    function govUseStabilityFund(
        IERC20 _market,
        address _receiver,
        uint128 _stabilityFundDelta
    ) external override nonReentrant {
        _onlyGov();

        State storage state = _statesStorage().marketStates[_market];

        state.govUseStabilityFund(_market, _stabilityFundDelta, _receiver);

        state.tokenBalance -= _stabilityFundDelta;
        _market.safeTransfer(_receiver, _stabilityFundDelta);
    }

    /// @inheritdoc IMarketPosition
    function increasePosition(
        IERC20 _market,
        address _account,
        uint96 _sizeDelta
    ) external override nonReentrant returns (uint96 spread) {
        _onlyPlugin();

        MarketManagerStatesStorage storage $ = _statesStorage();
        State storage state = $.marketStates[_market];

        uint128 balanceAfter = _market.balanceOf(address(this)).toUint128();
        uint96 marginDelta = (balanceAfter - state.tokenBalance).toUint96();
        state.tokenBalance = balanceAfter;

        (uint64 minIndexPrice, uint64 maxIndexPrice) = _getPrice(_market);
        spread = state.increasePosition(
            _configurableStorage().marketConfigs[_market],
            PositionUtil.IncreasePositionParam({
                market: _market,
                account: _account,
                marginDelta: marginDelta,
                sizeDelta: _sizeDelta,
                minIndexPrice: minIndexPrice,
                maxIndexPrice: maxIndexPrice
            })
        );
    }

    /// @inheritdoc IMarketPosition
    function decreasePosition(
        IERC20 _market,
        address _account,
        uint96 _marginDelta,
        uint96 _sizeDelta,
        address _receiver
    ) external override nonReentrant returns (uint96 spread, uint96 actualMarginDelta) {
        _onlyPlugin();

        MarketManagerStatesStorage storage $ = _statesStorage();
        State storage state = $.marketStates[_market];

        (uint64 minIndexPrice, uint64 maxIndexPrice) = _getPrice(_market);
        (spread, actualMarginDelta) = state.decreasePosition(
            _configurableStorage().marketConfigs[_market],
            PositionUtil.DecreasePositionParam({
                market: _market,
                account: _account,
                marginDelta: _marginDelta,
                sizeDelta: _sizeDelta,
                minIndexPrice: minIndexPrice,
                maxIndexPrice: maxIndexPrice,
                receiver: _receiver
            })
        );
        state.tokenBalance -= actualMarginDelta;
        _market.safeTransfer(_receiver, actualMarginDelta);
    }

    /// @inheritdoc IMarketPosition
    function liquidatePosition(IERC20 _market, address _account, address _feeReceiver) external override nonReentrant {
        _onlyPlugin();

        MarketManagerStatesStorage storage $ = _statesStorage();
        State storage state = $.marketStates[_market];

        uint64 executionFee;
        (uint64 minIndexPrice, uint64 maxIndexPrice) = _getPrice(_market);
        executionFee = state.liquidatePosition(
            _configurableStorage().marketConfigs[_market],
            PositionUtil.LiquidatePositionParam({
                market: _market,
                account: _account,
                minIndexPrice: minIndexPrice,
                maxIndexPrice: maxIndexPrice,
                feeReceiver: _feeReceiver
            })
        );

        state.tokenBalance -= executionFee;
        _market.safeTransfer(_feeReceiver, executionFee);
    }

    /// @inheritdoc IPUSDManager
    function mintPUSD(
        IERC20 _market,
        bool _exactIn,
        uint96 _amount,
        IPUSDManagerCallback _callback,
        bytes calldata _data,
        address _receiver
    ) external override nonReentrant returns (uint96 payAmount, uint64 receiveAmount) {
        _onlyPlugin();

        MarketManagerStatesStorage storage $ = _statesStorage();
        State storage state = $.marketStates[_market];

        (payAmount, receiveAmount) = state.mint(
            _configurableStorage().marketConfigs[_market],
            PUSDManagerUtil.MintParam({
                market: _market,
                exactIn: _exactIn,
                amount: _amount,
                callback: _callback,
                indexPrice: _getMinPrice(_market),
                usd: $.usd,
                receiver: _receiver
            }),
            _data
        );
    }

    /// @inheritdoc IPUSDManager
    function burnPUSD(
        IERC20 _market,
        bool _exactIn,
        uint96 _amount,
        IPUSDManagerCallback _callback,
        bytes calldata _data,
        address _receiver
    ) external override nonReentrant returns (uint64 payAmount, uint96 receiveAmount) {
        _onlyPlugin();

        MarketManagerStatesStorage storage $ = _statesStorage();
        State storage state = $.marketStates[_market];

        (payAmount, receiveAmount) = state.burn(
            _configurableStorage().marketConfigs[_market],
            PUSDManagerUtil.BurnParam({
                market: _market,
                exactIn: _exactIn,
                amount: _amount,
                callback: _callback,
                indexPrice: _getMaxPrice(_market),
                usd: $.usd,
                receiver: _receiver
            }),
            _data
        );
    }

    /// @inheritdoc IMarketManager
    function collectProtocolFee(IERC20 _market) external override nonReentrant {
        MarketManagerStatesStorage storage $ = _statesStorage();
        State storage state = $.marketStates[_market];

        uint128 protocolFee_ = state.protocolFee;
        state.protocolFee = 0;
        state.tokenBalance -= protocolFee_;

        FeeDistributorUpgradeable feeDistributor_ = $.feeDistributor;
        _market.safeTransfer(address(feeDistributor_), protocolFee_);
        feeDistributor_.deposit(_market);

        emit ProtocolFeeCollected(_market, protocolFee_);
    }

    /// @inheritdoc IMarketManager
    function repayLiquidityBufferDebt(
        IERC20 _market,
        address _account,
        address _receiver
    ) external override nonReentrant returns (uint128 receiveAmount) {
        _onlyPlugin();

        MarketManagerStatesStorage storage $ = _statesStorage();
        State storage state = $.marketStates[_market];

        return state.repayLiquidityBufferDebt($.usd, _market, _account, _receiver);
    }

    /// @inheritdoc ConfigurableUpgradeable
    function afterMarketEnabled(IERC20 _market, string calldata _tokenSymbol) internal override {
        ILPToken token = LiquidityUtil.deployLPToken(_market, _tokenSymbol);
        emit IMarketLiquidity.LPTokenDeployed(_market, token);
    }

    /// @inheritdoc UUPSUpgradeable
    function _authorizeUpgrade(address newImplementation) internal virtual override onlyGov {}
}
