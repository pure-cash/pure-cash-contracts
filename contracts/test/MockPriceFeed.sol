// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.26;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MockPriceFeed {
    uint160 public minPriceX96;
    uint160 public maxPriceX96;

    function setMaxPriceX96(uint160 _maxPriceX96) external {
        maxPriceX96 = _maxPriceX96;
    }

    function setMinPriceX96(uint160 _minPriceX96) external {
        minPriceX96 = _minPriceX96;
    }

    function getMaxPriceX96(IERC20 /*_market*/) external view returns (uint160) {
        return maxPriceX96;
    }

    function getMinPriceX96(IERC20 /*_market*/) external view returns (uint160) {
        return minPriceX96;
    }

    function getPriceX96(IERC20 /*_market*/) external view returns (uint160, uint160) {
        return (minPriceX96, maxPriceX96);
    }
}
