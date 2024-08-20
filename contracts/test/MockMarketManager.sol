// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.26;

import "../types/Side.sol";
import "../IWETHMinimum.sol";
import "../core/interfaces/IPSM.sol";
import "../core/PUSDUpgradeable.sol";
import "../libraries/LiquidityUtil.sol";
import {LPToken} from "../core/LPToken.sol";
import "../core/interfaces/IMarketLiquidity.sol";
import "../core/interfaces/IPUSDManagerCallback.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract MockMarketManager {
    LPToken public lpToken;
    PUSDUpgradeable public usd;
    IWETHMinimum public weth;

    uint64 public minPrice;
    uint64 public maxPrice;
    uint96 public payAmount;
    uint96 public receiveAmount;
    uint96 public spread;
    uint96 public actualMarginDelta;
    uint64 public tokenValue;
    uint96 public liquidity;
    bool public receivePUSD;
    mapping(IERC20 market => LPToken lpToken) public lpTokens;

    IPSM.CollateralState psmCollateralState;
    IMarketManager.LiquidityBufferModule public liquidityBufferModule;

    constructor(PUSDUpgradeable _usd, IWETHMinimum _weth) payable {
        usd = _usd;
        weth = _weth;
    }

    function deployLPToken(IERC20 _market, string calldata _tokenSymbol) external returns (LPToken) {
        lpToken = LiquidityUtil.deployLPToken(_market, _tokenSymbol);
        lpTokens[_market] = lpToken;
        return lpToken;
    }

    function setMinPrice(uint64 _minPrice) external {
        minPrice = _minPrice;
    }

    function setMaxPrice(uint64 _maxPrice) external {
        maxPrice = _maxPrice;
    }

    function setPSMCollateralState(IPSM.CollateralState calldata _state) external {
        psmCollateralState = _state;
    }

    function setPayAmount(uint96 _payAmount) external {
        payAmount = _payAmount;
    }

    function setReceiveAmount(uint96 _receiveAmount) external {
        receiveAmount = _receiveAmount;
    }

    function setSpread(uint96 _spread) external {
        spread = _spread;
    }

    function setActualMarginDelta(uint96 _actualMarginDelta) external {
        actualMarginDelta = _actualMarginDelta;
    }

    function setTokenValue(uint64 _tokenValue) external {
        tokenValue = _tokenValue;
    }

    function setLiquidity(uint96 _liquidity) external {
        liquidity = _liquidity;
    }

    function setReceivePUSD(bool _receivePUSD) external {
        receivePUSD = _receivePUSD;
    }

    function setLiquidityBufferModule(uint128 _pusdDebt, uint128 _tokenPayback) external {
        liquidityBufferModule.pusdDebt = _pusdDebt;
        liquidityBufferModule.tokenPayback = _tokenPayback;
    }

    function mintPUSD(
        IERC20 _market,
        bool /*_exactIn*/,
        uint96 /*_amount*/,
        IPUSDManagerCallback _callback,
        bytes calldata _data,
        address /*_receiver*/
    ) external returns (uint96, uint96) {
        _callback.PUSDManagerCallback(IERC20(address(_market)), payAmount, receiveAmount, _data);
        return (payAmount, receiveAmount);
    }

    function burnPUSD(
        IERC20 _market,
        bool /*_exactIn*/,
        uint96 /*_amount*/,
        IPUSDManagerCallback _callback,
        bytes calldata _data,
        address _receiver
    ) external returns (uint128, uint128) {
        _callback.PUSDManagerCallback(IERC20(address(usd)), payAmount, receiveAmount, _data);
        if (address(_market) == address(weth)) {
            weth.deposit{value: receiveAmount}();
            weth.transfer(_receiver, receiveAmount);
        }
        return (payAmount, receiveAmount);
    }

    function increasePosition(
        IERC20 /*_market*/,
        address /*_account*/,
        uint96 /*_sizeDelta*/
    ) external view returns (uint96) {
        return spread;
    }

    function decreasePosition(
        IERC20 _market,
        address /*_account*/,
        uint96 /*_marginDelta*/,
        uint96 /*_sizeDelta*/,
        address _receiver
    ) external returns (uint96, uint96) {
        if (address(_market) == address(weth)) {
            weth.deposit{value: actualMarginDelta}();
            weth.transfer(_receiver, actualMarginDelta);
        } else if (receivePUSD) {
            _market.transfer(_receiver, actualMarginDelta);
        }
        return (spread, actualMarginDelta);
    }

    function mintLPT(IERC20 /*_market*/, address /*_account*/, address /*_receiver*/) external view returns (uint128) {
        return tokenValue;
    }

    function burnLPT(IERC20 _market, address /*_account*/, address _receiver) external returns (uint128) {
        if (address(_market) == address(weth)) {
            weth.deposit{value: liquidity}();
            weth.transfer(_receiver, liquidity);
        } else if (receivePUSD) {
            _market.transfer(_receiver, liquidity);
        }
        return liquidity;
    }

    function pluginTransfer(IERC20 _token, address _from, address _to, uint256 _amount) external {
        SafeERC20.safeTransferFrom(_token, _from, _to, _amount);
    }

    function mintLPToken(IERC20 _market, address _to, uint256 _amount) external {
        lpTokens[_market].mint(_to, _amount);
    }

    function getPrice(IERC20 /* _market */) external view returns (uint64, uint64) {
        return (minPrice, maxPrice);
    }

    function psmCollateralStates(IERC20 /*_collateral*/) external view returns (IPSM.CollateralState memory state) {
        state = psmCollateralState;
    }

    function psmMintPUSD(IERC20 _collateral, address _receiver) external returns (uint64 /*receiveAmount*/) {
        usd.mint(_receiver, receiveAmount);
        uint128 balanceAfter = uint128(_collateral.balanceOf(address(this)));
        psmCollateralState.balance = balanceAfter;
        return uint64(receiveAmount);
    }

    function psmBurnPUSD(IERC20 /*_collateral*/, address /*_receiver*/) external returns (uint96 /*receiveAmount*/) {}

    function repayLiquidityBufferDebt(
        IERC20 _market,
        address /* _account */,
        address _receiver
    ) external returns (uint128 _receiveAmount) {
        uint128 amount = uint128(usd.balanceOf(address(this)));

        if (amount > liquidityBufferModule.pusdDebt) amount = liquidityBufferModule.pusdDebt;

        usd.burn(amount);
        unchecked {
            _receiveAmount = uint128(
                (uint256(liquidityBufferModule.tokenPayback) * amount) / liquidityBufferModule.pusdDebt
            );
            liquidityBufferModule.tokenPayback = liquidityBufferModule.tokenPayback - _receiveAmount;
            liquidityBufferModule.pusdDebt = liquidityBufferModule.pusdDebt - amount;
        }

        _market.transfer(_receiver, _receiveAmount);
        return _receiveAmount;
    }

    function liquidityBufferModules(
        IERC20 /* _market */
    ) external view returns (IMarketManager.LiquidityBufferModule memory) {
        return liquidityBufferModule;
    }
}
