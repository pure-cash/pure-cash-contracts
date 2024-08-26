import {ethers, upgrades} from "hardhat";
import {EstimatedGasLimitType} from "./Constants";

const marketDecimals = 18n;

export async function deployFixture() {
    const [owner, trader, executor, other] = await ethers.getSigners();
    const weth = await ethers.deployContract("WETH9");
    const market = await ethers.deployContract("ERC20Test", ["Market", "MKT", marketDecimals, 0n]);
    await market.mint(trader.address, 10000n * 10n ** marketDecimals);

    const liquidityUtil = await ethers.deployContract("LiquidityUtil");
    const pusdManagerUtil = await ethers.deployContract("PUSDManagerUtil");
    const marketManager = await ethers.deployContract("MockMarketManager", [weth.target], {
        value: 100n,
        libraries: {
            LiquidityUtil: liquidityUtil,
            PUSDManagerUtil: pusdManagerUtil,
        },
    });
    const usd = await ethers.getContractAt("PUSD", await marketManager.usd());
    const usdDecimals = await usd.decimals();
    await marketManager.mintPUSDArbitrary(trader.address, 10000n * 10n ** usdDecimals);

    await marketManager.deployLPToken(market.target, market.symbol + "-LP");
    await marketManager.deployLPToken(weth.target, weth.symbol + "-LP");
    const lpToken = await ethers.getContractAt("LPToken", await marketManager.lpTokens(market.target));
    const wethLpToken = await ethers.getContractAt("LPToken", await marketManager.lpTokens(weth.target));

    await market.mint(marketManager.target, 100n);

    await market.connect(trader).approve(marketManager.target, 10000n * 10n ** marketDecimals);
    await lpToken.connect(trader).approve(marketManager.target, 10000n * 10n ** marketDecimals);
    await wethLpToken.connect(trader).approve(marketManager.target, 10000n * 10n ** marketDecimals);
    await usd.connect(trader).approve(marketManager.target, 10000n * 10n ** usdDecimals);

    const govImpl = await ethers.deployContract("Governable", [owner.address]);
    const positionRouter = await ethers.deployContract("PositionRouter", [
        govImpl.target,
        marketManager.target,
        await weth.getAddress(),
        await positionRouterEstimatedGasLimitTypes(),
        Array((await positionRouterEstimatedGasLimitTypes()).length).fill(500_000),
    ]);
    await positionRouter.waitForDeployment();
    await positionRouter.updatePositionExecutor(executor.address, true);

    return {
        owner,
        trader,
        executor,
        other,
        lpToken,
        wethLpToken,
        usd,
        marketManager,
        weth,
        market,
        positionRouter,
    };
}

export async function positionRouterEstimatedGasLimitTypes() {
    return [
        EstimatedGasLimitType.IncreasePosition,
        EstimatedGasLimitType.IncreasePositionPayPUSD,
        EstimatedGasLimitType.DecreasePosition,
        EstimatedGasLimitType.DecreasePositionReceivePUSD,
        EstimatedGasLimitType.MintPUSD,
        EstimatedGasLimitType.BurnPUSD,
    ];
}

export async function positionRouter2EstimatedGasLimitTypes() {
    return [
        EstimatedGasLimitType.MintLPT,
        EstimatedGasLimitType.MintLPTPayPUSD,
        EstimatedGasLimitType.BurnLPT,
        EstimatedGasLimitType.BurnLPTReceivePUSD,
    ];
}

export function ceilDiv(a: bigint, b: bigint) {
    return (a + b - 1n) / b;
}
