// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../libraries/PUSDManagerUtil.sol";

library PUSDManagerUtilTest {
    function mint(
        IMarketManager.State storage _state,
        IConfigurable.MarketConfig storage _cfg,
        PUSDManagerUtil.MintParam memory _param,
        bytes calldata _data
    ) public returns (uint96 payAmount, uint64 receiveAmount) {
        return PUSDManagerUtil.mint(_state, _cfg, _param, _data);
    }

    function burn(
        IMarketManager.State storage _state,
        IConfigurable.MarketConfig storage _cfg,
        PUSDManagerUtil.BurnParam memory _param,
        bytes calldata _data
    ) public returns (uint64 payAmount, uint96 receiveAmount) {
        return PUSDManagerUtil.burn(_state, _cfg, _param, _data);
    }
}
