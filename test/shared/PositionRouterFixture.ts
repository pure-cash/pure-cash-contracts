import {ethers, upgrades} from "hardhat";
import {PUSDUpgradeable} from "../../typechain-types";
import {ExecutionFeeType} from "./Constants";

const marketDecimals = 18n;

export async function deployFixture() {
    const [owner, trader, executor, other] = await ethers.getSigners();
    const weth = await ethers.deployContract("WETH9");
    const market = await ethers.deployContract("ERC20Test", ["Market", "MKT", marketDecimals, 0n]);
    await market.mint(trader.address, 10000n * 10n ** marketDecimals);

    const PUSD = await ethers.getContractFactory("PUSDUpgradeable");
    const usd = (await upgrades.deployProxy(PUSD, [owner.address], {kind: "uups"})) as unknown as PUSDUpgradeable;
    await usd.setMinter(owner.address, true);
    const usdDecimals = await usd.decimals();
    await usd.mint(trader.address, 10000n * 10n ** usdDecimals);

    const liquidityUtil = await ethers.deployContract("LiquidityUtil");
    const marketManager = await ethers.deployContract("MockMarketManager", [usd.target, weth.target], {
        value: 100n,
        libraries: {
            LiquidityUtil: liquidityUtil,
        },
    });

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
        usd.target,
        marketManager.target,
        await weth.getAddress(),
        await positionRouterExecutionFeeTypes(),
        await positionRouterMinExecutionFees(),
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

export async function positionRouterExecutionFeeTypes() {
    return [
        ExecutionFeeType.IncreasePosition,
        ExecutionFeeType.IncreasePositionETH,
        ExecutionFeeType.IncreasePositionPayPUSD,
        ExecutionFeeType.DecreasePosition,
        ExecutionFeeType.DecreasePositionReceivePUSD,
        ExecutionFeeType.MintPUSD,
        ExecutionFeeType.MintPUSDETH,
        ExecutionFeeType.BurnPUSD,
    ];
}

export async function positionRouter2ExecutionFeeTypes() {
    return [
        ExecutionFeeType.MintLPT,
        ExecutionFeeType.MintLPTETH,
        ExecutionFeeType.MintLPTPayPUSD,
        ExecutionFeeType.BurnLPT,
        ExecutionFeeType.BurnLPTReceivePUSD,
    ];
}

export async function positionRouterMinExecutionFees() {
    return [
        ethers.parseEther("0.0001"),
        ethers.parseEther("0.0002"),
        ethers.parseEther("0.0003"),
        ethers.parseEther("0.0004"),
        ethers.parseEther("0.0005"),
        ethers.parseEther("0.0006"),
        ethers.parseEther("0.0007"),
        ethers.parseEther("0.0008"),
    ];
}
