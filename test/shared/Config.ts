import {ethers} from "hardhat";
import {parsePercent} from "../../scripts/util";

export function newBaseConfig() {
    return {
        minMarginPerLiquidityPosition: ethers.parseUnits("0.005", "ether"),
        maxLeveragePerLiquidityPosition: 200n,
        liquidationFeeRatePerLiquidityPosition: parsePercent("0.05%"),
        minMarginPerPosition: ethers.parseUnits("0.005", "ether"),
        maxLeveragePerPosition: 100n,
        liquidationFeeRatePerPosition: parsePercent("0.4%"),
        maxPositionLiquidity: 15_000n * 10n ** 18n,
        maxPositionValueRate: parsePercent("3000%"),
        maxSizeRatePerPosition: parsePercent("0.667%"),
        liquidationExecutionFee: ethers.parseUnits("0.0004", "ether"),
        interestRate: parsePercent("0.00125%"),
        interestRateBuffer: parsePercent("0.00625%"),
        maxFundingRate: parsePercent("0.25%"),
    };
}

export function newFeeRateConfig() {
    return {
        tradingFeeRate: parsePercent("0.01%"),
        protocolFeeRate: parsePercent("50%"),
    };
}

export function newPriceConfig() {
    return {
        maxPriceImpactLiquidity: 15_000n * 10n ** 18n,
        liquidationVertexIndex: 6,
        vertices: [
            {balanceRate: 0, premiumRate: 0},
            {balanceRate: parsePercent("0.5%"), premiumRate: parsePercent("0.05%")},
            {balanceRate: parsePercent("2.5%"), premiumRate: parsePercent("0.1%")},
            {balanceRate: parsePercent("5%"), premiumRate: parsePercent("0.15%")},
            {balanceRate: parsePercent("6%"), premiumRate: parsePercent("0.2%")},
            {balanceRate: parsePercent("7%"), premiumRate: parsePercent("0.3%")},
            {balanceRate: parsePercent("8%"), premiumRate: parsePercent("0.4%")},
            {balanceRate: parsePercent("9%"), premiumRate: parsePercent("0.5%")},
            {balanceRate: parsePercent("10%"), premiumRate: parsePercent("0.6%")},
            {balanceRate: parsePercent("50%"), premiumRate: parsePercent("10%")},
        ],
    };
}

export function newConfig() {
    return {
        baseConfig: newBaseConfig(),
        feeRateConfig: newFeeRateConfig(),
        priceConfig: newPriceConfig(),
    };
}
