import {loadFixture, mine, time} from "@nomicfoundation/hardhat-network-helpers";
import {expect} from "chai";
import {ethers, upgrades} from "hardhat";
import {PUSDUpgradeable} from "../typechain-types";
import {genERC20PermitData, resetAllowance} from "./shared/Permit";
import {keccak256} from "@ethersproject/keccak256";
import {defaultAbiCoder} from "@ethersproject/abi";
import {IPositionRouter2} from "../typechain-types/contracts/plugins/PositionRouter2";
import {positionRouter2ExecutionFeeTypes} from "./shared/PositionRouterFixture";

describe("PositionRouter2", () => {
    const marketDecimals = 18n;
    const minExecutionFee = ethers.parseUnits("0.0001", marketDecimals);

    async function deployFixture() {
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
        const positionRouter2 = await ethers.deployContract("PositionRouter2", [
            govImpl.target,
            usd.target,
            marketManager.target,
            await weth.getAddress(),
            await positionRouter2ExecutionFeeTypes(),
            Array((await positionRouter2ExecutionFeeTypes()).length).fill(minExecutionFee),
        ]);
        await positionRouter2.waitForDeployment();
        await positionRouter2.updatePositionExecutor(executor.address, true);

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
            positionRouter2,
        };
    }

    describe("#receive", () => {
        it("should revert if msg.sender is not WETH", async () => {
            const {owner, weth, positionRouter2} = await loadFixture(deployFixture);
            await expect(owner.sendTransaction({to: await positionRouter2.getAddress(), value: 1}))
                .to.be.revertedWithCustomError(positionRouter2, "InvalidCaller")
                .withArgs(weth.target);
        });

        it("should pass", async () => {
            const {owner, executor, positionRouter2, weth} = await loadFixture(deployFixture);
            await expect(positionRouter2.createMintLPTETH(owner.address, 1e15, {value: 10n ** 18n})).to.be.emit(
                positionRouter2,
                "MintLPTCreated",
            );

            expect(await weth.balanceOf(await positionRouter2.getAddress())).to.be.eq(10n ** 18n - 10n ** 15n);

            await positionRouter2.connect(executor).cancelMintLPT(
                {
                    account: owner.address,
                    market: await weth.getAddress(),
                    liquidityDelta: 10n ** 18n - 10n ** 15n,
                    executionFee: 10n ** 15n,
                    receiver: owner.address,
                    payPUSD: false,
                    minReceivedFromBurningPUSD: 0,
                },
                owner.address,
            );

            expect(await weth.balanceOf(await positionRouter2.getAddress())).to.be.eq(0n);
        });
    });

    describe("#updatePositionExecutor", async () => {
        it("should revert with 'Forbidden' if caller is not gov", async () => {
            const {other, positionRouter2} = await loadFixture(deployFixture);
            await expect(
                positionRouter2.connect(other).updatePositionExecutor(other.address, true),
            ).to.be.revertedWithCustomError(positionRouter2, "Forbidden");
        });

        it("should emit correct event and update param", async () => {
            const {positionRouter2, other} = await loadFixture(deployFixture);

            await expect(positionRouter2.updatePositionExecutor(other.address, true))
                .to.emit(positionRouter2, "PositionExecutorUpdated")
                .withArgs(other.address, true);
            expect(await positionRouter2.positionExecutors(other.address)).to.eq(true);

            await expect(positionRouter2.updatePositionExecutor(other.address, false))
                .to.emit(positionRouter2, "PositionExecutorUpdated")
                .withArgs(other.address, false);
            expect(await positionRouter2.positionExecutors(other.address)).to.eq(false);
        });
    });

    describe("#updateDelayValues", async () => {
        it("should revert with 'Forbidden' if caller is not gov", async () => {
            const {other, positionRouter2} = await loadFixture(deployFixture);
            await expect(positionRouter2.connect(other).updateDelayValues(0n, 0n, 0n)).to.be.revertedWithCustomError(
                positionRouter2,
                "Forbidden",
            );
        });

        it("should emit correct event and update param", async () => {
            const {positionRouter2} = await loadFixture(deployFixture);
            await expect(positionRouter2.updateDelayValues(10n, 20n, 30n))
                .to.emit(positionRouter2, "DelayValuesUpdated")
                .withArgs(10n, 20n, 30n);
            expect(await positionRouter2.minBlockDelayExecutor()).to.eq(10n);
            expect(await positionRouter2.minBlockDelayPublic()).to.eq(20n);
            expect(await positionRouter2.maxBlockDelay()).to.eq(30n);
        });
    });

    describe("#updateMinExecutionFee", async () => {
        it("should revert with 'Forbidden' if caller is not gov", async () => {
            const {other, positionRouter2} = await loadFixture(deployFixture);
            await expect(positionRouter2.connect(other).updateMinExecutionFee(0, 3000n)).to.be.revertedWithCustomError(
                positionRouter2,
                "Forbidden",
            );
        });

        it("should emit correct event and update params", async () => {
            const {positionRouter2} = await loadFixture(deployFixture);
            await expect(positionRouter2.updateMinExecutionFee(1, 8000n))
                .to.emit(positionRouter2, "MinExecutionFeeUpdated")
                .withArgs(1, 8000n);
            expect(await positionRouter2.minExecutionFees(0)).to.eq(minExecutionFee);
            expect(await positionRouter2.minExecutionFees(1)).to.eq(8000n);
            expect(await positionRouter2.minExecutionFees(2)).to.eq(minExecutionFee);
            expect(await positionRouter2.minExecutionFees(3)).to.eq(minExecutionFee);
            expect(await positionRouter2.minExecutionFees(4)).to.eq(minExecutionFee);
            expect(await positionRouter2.minExecutionFees(5)).to.eq(0n);
        });
    });

    describe("#updateExecutionGasLimit", async () => {
        it("should revert with 'Forbidden' if caller is not gov", async () => {
            const {other, positionRouter2} = await loadFixture(deployFixture);
            await expect(
                positionRouter2.connect(other).updateExecutionGasLimit(2000000n),
            ).to.be.revertedWithCustomError(positionRouter2, "Forbidden");
        });

        it("should update param", async () => {
            const {positionRouter2} = await loadFixture(deployFixture);

            await positionRouter2.updateExecutionGasLimit(2000000n);
            expect(await positionRouter2.executionGasLimit()).to.eq(2000000n);
        });
    });

    describe("MintLPT", () => {
        const liquidityDelta = 1n * 10n ** marketDecimals;
        describe("#createMintLPT", () => {
            it("should revert if msg.value is less than minExecutionFee", async function () {
                const {trader, market, positionRouter2} = await loadFixture(deployFixture);

                let minExecutionFeeAfter = ethers.parseUnits("0.0002", marketDecimals);
                await expect(positionRouter2.updateMinExecutionFee(0, minExecutionFeeAfter))
                    .to.emit(positionRouter2, "MinExecutionFeeUpdated")
                    .withArgs(0, minExecutionFeeAfter);

                const value = minExecutionFee;
                await expect(
                    positionRouter2
                        .connect(trader)
                        .createMintLPT(market.target, liquidityDelta, trader.address, "0x", {value: value}),
                )
                    .to.be.revertedWithCustomError(positionRouter2, "InsufficientExecutionFee")
                    .withArgs(value, minExecutionFeeAfter);
            });
            it("should revert if allowance is insufficient and permitData is empty", async function () {
                const {trader, market, marketManager, positionRouter2} = await loadFixture(deployFixture);
                await resetAllowance(market, trader, await marketManager.getAddress());
                await expect(
                    positionRouter2
                        .connect(trader)
                        .createMintLPT(market.target, liquidityDelta, trader.address, "0x", {value: minExecutionFee}),
                )
                    .to.be.revertedWithCustomError(market, "ERC20InsufficientAllowance")
                    .withArgs(marketManager.target, 0, liquidityDelta);
            });
            it("should revert if allowance is insufficient and permitData is invalid", async function () {
                const {trader, market, marketManager, positionRouter2} = await loadFixture(deployFixture);
                await resetAllowance(market, trader, await marketManager.getAddress());
                await expect(
                    positionRouter2
                        .connect(trader)
                        .createMintLPT(market.target, liquidityDelta, trader.address, "0xabcdef", {
                            value: minExecutionFee,
                        }),
                ).to.be.reverted;
            });
            it("should revert if allowance is insufficient and permitData is other's", async function () {
                const {trader, other, market, marketManager, positionRouter2} = await loadFixture(deployFixture);
                await resetAllowance(market, trader, await marketManager.getAddress());
                const permitData = await genERC20PermitData(
                    market,
                    other,
                    await marketManager.getAddress(),
                    liquidityDelta,
                );
                await expect(
                    positionRouter2
                        .connect(trader)
                        .createMintLPT(market.target, liquidityDelta, trader.address, permitData, {
                            value: minExecutionFee,
                        }),
                )
                    .to.be.revertedWithCustomError(market, "ERC20InsufficientAllowance")
                    .withArgs(marketManager.target, 0, liquidityDelta);
            });
            it("should pass if allowance is insufficient and permitData is valid", async function () {
                const {trader, market, marketManager, positionRouter2} = await loadFixture(deployFixture);
                await resetAllowance(market, trader, await marketManager.getAddress());
                for (let i = 0; i < 10; i++) {
                    let liquidityDelta = 100n + BigInt(i);
                    const permitData = await genERC20PermitData(
                        market,
                        trader,
                        await marketManager.getAddress(),
                        liquidityDelta,
                    );
                    const tx = await positionRouter2
                        .connect(trader)
                        .createMintLPT(market.target, liquidityDelta, trader.address, permitData, {
                            value: minExecutionFee,
                        });
                    let idExpected = keccak256(
                        defaultAbiCoder.encode(
                            ["address", "address", "uint96", "uint256", "address", "bool", "uint96"],
                            [trader.address, market.target, liquidityDelta, minExecutionFee, trader.address, false, 0n],
                        ),
                    );
                    await expect(tx).to.changeEtherBalances(
                        [trader, positionRouter2],
                        [-minExecutionFee, minExecutionFee],
                    );
                    await expect(tx).to.changeTokenBalances(
                        market,
                        [trader, positionRouter2],
                        [-liquidityDelta, liquidityDelta],
                    );
                    await expect(tx)
                        .to.emit(positionRouter2, "MintLPTCreated")
                        .withArgs(
                            trader.address,
                            market.target,
                            liquidityDelta,
                            minExecutionFee,
                            trader.address,
                            false,
                            0n,
                            idExpected,
                        );
                    expect(await positionRouter2.blockNumbers(idExpected)).to.eq(await time.latestBlock());
                }
            });
            it("should pass if allowance is sufficient and permitData is empty", async function () {
                const {trader, market, positionRouter2} = await loadFixture(deployFixture);
                for (let i = 0; i < 10; i++) {
                    let liquidityDelta = 100n + BigInt(i);
                    const tx = await positionRouter2
                        .connect(trader)
                        .createMintLPT(market.target, liquidityDelta, trader.address, "0x", {
                            value: minExecutionFee,
                        });
                    let id = mintLPTId({
                        account: trader.address,
                        market: market.target,
                        liquidityDelta: liquidityDelta,
                        executionFee: minExecutionFee,
                        receiver: trader.address,
                        payPUSD: false,
                        minReceivedFromBurningPUSD: 0n,
                    });
                    await expect(tx).to.changeEtherBalances(
                        [trader, positionRouter2],
                        [-minExecutionFee, minExecutionFee],
                    );
                    await expect(tx).to.changeTokenBalances(
                        market,
                        [trader, positionRouter2],
                        [-liquidityDelta, liquidityDelta],
                    );
                    await expect(tx)
                        .to.emit(positionRouter2, "MintLPTCreated")
                        .withArgs(
                            trader.address,
                            market,
                            liquidityDelta,
                            minExecutionFee,
                            trader.address,
                            false,
                            0n,
                            id,
                        );
                    expect(await positionRouter2.blockNumbers(id)).to.eq(await time.latestBlock());
                }
            });
            it("should revert if create two identical requests", async function () {
                const {trader, market, positionRouter2} = await loadFixture(deployFixture);
                const tx = await positionRouter2
                    .connect(trader)
                    .createMintLPT(market.target, liquidityDelta, trader.address, "0x", {
                        value: minExecutionFee,
                    });
                let id = mintLPTId({
                    account: trader.address,
                    market: market.target,
                    liquidityDelta: liquidityDelta,
                    executionFee: minExecutionFee,
                    receiver: trader.address,
                    payPUSD: false,
                    minReceivedFromBurningPUSD: 0n,
                });
                expect(await positionRouter2.blockNumbers(id)).to.eq(await time.latestBlock());
                await expect(
                    positionRouter2
                        .connect(trader)
                        .createMintLPT(market.target, liquidityDelta, trader.address, "0x", {value: minExecutionFee}),
                )
                    .to.be.revertedWithCustomError(positionRouter2, "ConflictRequests")
                    .withArgs(id);
            });
            it("should pass if create two identical requests except for execution fee", async function () {
                const {trader, market, positionRouter2} = await loadFixture(deployFixture);
                const tx = await positionRouter2
                    .connect(trader)
                    .createMintLPT(market.target, liquidityDelta, trader.address, "0x", {
                        value: minExecutionFee,
                    });
                let id = mintLPTId({
                    account: trader.address,
                    market: market.target,
                    liquidityDelta: liquidityDelta,
                    executionFee: minExecutionFee,
                    receiver: trader.address,
                    payPUSD: false,
                    minReceivedFromBurningPUSD: 0n,
                });
                expect(await positionRouter2.blockNumbers(id)).to.eq(await time.latestBlock());
                await expect(
                    positionRouter2.connect(trader).createMintLPT(market.target, liquidityDelta, trader.address, "0x", {
                        value: minExecutionFee + BigInt(1),
                    }),
                ).not.to.be.reverted;
            });
        });
        describe("#createMintLPTETH", () => {
            it("should revert if msg.value is less than executionFee", async function () {
                const {trader, positionRouter2} = await loadFixture(deployFixture);

                let minExecutionFeeAfter = ethers.parseUnits("0.0002", marketDecimals);
                await expect(positionRouter2.updateMinExecutionFee(1, minExecutionFeeAfter))
                    .to.emit(positionRouter2, "MinExecutionFeeUpdated")
                    .withArgs(1, minExecutionFeeAfter);

                const value = minExecutionFee;

                await expect(positionRouter2.connect(trader).createMintLPTETH(trader.address, minExecutionFee, {value}))
                    .to.be.revertedWithCustomError(positionRouter2, "InsufficientExecutionFee")
                    .withArgs(value, minExecutionFeeAfter);
            });
            it("should revert if executionFee is less than minExecutionFee", async function () {
                const {trader, positionRouter2} = await loadFixture(deployFixture);
                const value = minExecutionFee - 1n;
                await expect(positionRouter2.connect(trader).createMintLPTETH(trader.address, value, {value}))
                    .to.be.revertedWithCustomError(positionRouter2, "InsufficientExecutionFee")
                    .withArgs(value, minExecutionFee);
            });
            it("should pass", async function () {
                const {trader, weth, positionRouter2} = await loadFixture(deployFixture);
                let liquidityDelta = 100n;
                for (let i = 0; i < 10; i++) {
                    liquidityDelta = liquidityDelta + BigInt(i);
                    const value = minExecutionFee + liquidityDelta;
                    const tx = await positionRouter2
                        .connect(trader)
                        .createMintLPTETH(trader.address, minExecutionFee, {value});
                    await expect(tx).to.changeEtherBalances([trader, positionRouter2], [-value, minExecutionFee]);
                    await expect(tx).to.changeTokenBalance(weth, positionRouter2, liquidityDelta);

                    let idExpected = keccak256(
                        defaultAbiCoder.encode(
                            ["address", "address", "uint96", "uint256", "address", "bool", "uint96"],
                            [trader.address, weth.target, liquidityDelta, minExecutionFee, trader.address, false, 0n],
                        ),
                    );
                    await expect(tx)
                        .to.emit(positionRouter2, "MintLPTCreated")
                        .withArgs(
                            trader.address,
                            weth,
                            liquidityDelta,
                            minExecutionFee,
                            trader.address,
                            false,
                            0n,
                            idExpected,
                        );
                }
            });
        });
        describe("#createMintLPTPayPUSD", () => {
            it("should revert if executionFee is less than minExecutionFee", async function () {
                const {trader, market, positionRouter2} = await loadFixture(deployFixture);

                let minExecutionFeeAfter = ethers.parseUnits("0.0002", marketDecimals);
                await expect(positionRouter2.updateMinExecutionFee(2, minExecutionFeeAfter))
                    .to.emit(positionRouter2, "MinExecutionFeeUpdated")
                    .withArgs(2, minExecutionFeeAfter);

                const value = minExecutionFee;
                await expect(
                    positionRouter2
                        .connect(trader)
                        .createMintLPTPayPUSD(market.target, 100n, trader.address, 0n, "0x", {value}),
                )
                    .to.be.revertedWithCustomError(positionRouter2, "InsufficientExecutionFee")
                    .withArgs(value, minExecutionFeeAfter);
            });
            it("should revert if allowance is insufficient and permitData is empty", async function () {
                const {trader, market, usd, marketManager, positionRouter2} = await loadFixture(deployFixture);
                await resetAllowance(usd, trader, await marketManager.getAddress());
                await expect(
                    positionRouter2
                        .connect(trader)
                        .createMintLPTPayPUSD(market.target, 100n, trader.address, 0n, "0x", {value: minExecutionFee}),
                )
                    .to.be.revertedWithCustomError(usd, "ERC20InsufficientAllowance")
                    .withArgs(marketManager.target, 0, 100n);
            });
            it("should revert if allowance is insufficient and permitData is invalid", async function () {
                const {trader, market, usd, marketManager, positionRouter2} = await loadFixture(deployFixture);
                await resetAllowance(usd, trader, await marketManager.getAddress());
                await expect(
                    positionRouter2
                        .connect(trader)
                        .createMintLPTPayPUSD(market.target, 100n, trader.address, 0n, "0xabcdef", {
                            value: minExecutionFee,
                        }),
                ).to.be.reverted;
            });
            it("should revert if allowance is insufficient and permitData is other's", async function () {
                const {trader, other, market, usd, marketManager, positionRouter2} = await loadFixture(deployFixture);
                await resetAllowance(usd, trader, await marketManager.getAddress());
                const permitData = await genERC20PermitData(usd, other, await marketManager.getAddress(), 100n);
                await expect(
                    positionRouter2
                        .connect(trader)
                        .createMintLPTPayPUSD(market.target, 100n, trader.address, 0n, permitData, {
                            value: minExecutionFee,
                        }),
                )
                    .to.be.revertedWithCustomError(usd, "ERC20InsufficientAllowance")
                    .withArgs(marketManager.target, 0, 100n);
            });
            it("should pass if allowance is insufficient and permitData is valid", async function () {
                const {trader, market, usd, marketManager, positionRouter2} = await loadFixture(deployFixture);
                await resetAllowance(usd, trader, await marketManager.getAddress());
                for (let i = 0; i < 10; i++) {
                    let pusdAmount = 100n + BigInt(i);
                    const permitData = await genERC20PermitData(
                        usd,
                        trader,
                        await marketManager.getAddress(),
                        pusdAmount,
                    );
                    const tx = await positionRouter2
                        .connect(trader)
                        .createMintLPTPayPUSD(market.target, pusdAmount, trader.address, 0n, permitData, {
                            value: minExecutionFee,
                        });

                    let idExpected = keccak256(
                        defaultAbiCoder.encode(
                            ["address", "address", "uint96", "uint256", "address", "bool", "uint96"],
                            [trader.address, market.target, pusdAmount, minExecutionFee, trader.address, true, 0n],
                        ),
                    );
                    await expect(tx).to.changeEtherBalances(
                        [trader, positionRouter2],
                        [-minExecutionFee, minExecutionFee],
                    );
                    await expect(tx).to.changeTokenBalances(usd, [trader, positionRouter2], [-pusdAmount, pusdAmount]);
                    await expect(tx)
                        .to.emit(positionRouter2, "MintLPTCreated")
                        .withArgs(
                            trader.address,
                            market.target,
                            pusdAmount,
                            minExecutionFee,
                            trader.address,
                            true,
                            0n,
                            idExpected,
                        );
                }
            });

            it("should pass if allowance is sufficient and permitData is empty", async function () {
                const {trader, market, usd, positionRouter2} = await loadFixture(deployFixture);
                let liquidityDelta = 100n;
                for (let i = 0; i < 10; i++) {
                    liquidityDelta = liquidityDelta + BigInt(i);
                    const tx = await positionRouter2
                        .connect(trader)
                        .createMintLPTPayPUSD(market.target, liquidityDelta, trader.address, 0n, "0x", {
                            value: minExecutionFee,
                        });
                    await expect(tx).to.changeEtherBalances(
                        [trader, positionRouter2],
                        [-minExecutionFee, minExecutionFee],
                    );
                    await expect(tx).to.changeTokenBalances(
                        usd,
                        [trader, positionRouter2],
                        [-liquidityDelta, liquidityDelta],
                    );
                    let idExpected = keccak256(
                        defaultAbiCoder.encode(
                            ["address", "address", "uint96", "uint256", "address", "bool", "uint96"],
                            [trader.address, market.target, liquidityDelta, minExecutionFee, trader.address, true, 0n],
                        ),
                    );
                    await expect(tx)
                        .to.emit(positionRouter2, "MintLPTCreated")
                        .withArgs(
                            trader.address,
                            market.target,
                            liquidityDelta,
                            minExecutionFee,
                            trader.address,
                            true,
                            0n,
                            idExpected,
                        );
                }
            });
        });
        describe("#cancelMintLPT", () => {
            describe("shouldCancel/shouldExecuteOrCancel", function () {
                it("should revert if caller is not request owner nor executor", async () => {
                    const {positionRouter2, market, trader, other} = await loadFixture(deployFixture);
                    // create a new request
                    await positionRouter2.connect(trader).createMintLPT(market, liquidityDelta, trader.address, "0x", {
                        value: minExecutionFee,
                    });

                    await expect(
                        positionRouter2.connect(other).cancelMintLPT(
                            {
                                account: trader.address,
                                market: market.target,
                                liquidityDelta: liquidityDelta,
                                executionFee: minExecutionFee,
                                receiver: trader.address,
                                payPUSD: false,
                                minReceivedFromBurningPUSD: 0n,
                            },
                            other.address,
                        ),
                    ).to.be.revertedWithCustomError(positionRouter2, "Forbidden");
                });

                it("should wait at least minBlockDelayExecutor until executors can cancel", async () => {
                    const {positionRouter2, market, trader, executor} = await loadFixture(deployFixture);
                    // executor has to wait 10 blocks
                    await positionRouter2.updateDelayValues(10n, 3000n, 6000n);
                    // create a new request
                    await positionRouter2.connect(trader).createMintLPT(market, liquidityDelta, trader.address, "0x", {
                        value: minExecutionFee,
                    });

                    let arg = {
                        account: trader.address,
                        market: market.target,
                        liquidityDelta: liquidityDelta,
                        executionFee: minExecutionFee,
                        receiver: trader.address,
                        payPUSD: false,
                        minReceivedFromBurningPUSD: 0n,
                    };

                    let idExpected = mintLPTId(arg);

                    // should fail to cancel
                    await positionRouter2.connect(executor).cancelMintLPT(arg, executor.address);
                    expect(await positionRouter2.blockNumbers(idExpected)).to.eq((await time.latestBlock()) - 1);

                    // mine 10 blocks
                    await mine(10);

                    // should be cancelled
                    await positionRouter2.connect(executor).cancelMintLPT(arg, executor.address);
                    expect(await positionRouter2.blockNumbers(idExpected)).to.eq(0);
                });

                it("should wait at least minBlockDelayPublic until public can cancel", async () => {
                    const {positionRouter2, market, trader} = await loadFixture(deployFixture);
                    await expect(positionRouter2.updateDelayValues(10n, 100n, 600n)).not.to.be.reverted;
                    // create a new request
                    await positionRouter2.connect(trader).createMintLPT(market, liquidityDelta, trader.address, "0x", {
                        value: minExecutionFee,
                    });
                    const earliest = (await time.latestBlock()) + 100;

                    let arg = {
                        account: trader.address,
                        market: market.target,
                        liquidityDelta: liquidityDelta,
                        executionFee: minExecutionFee,
                        receiver: trader.address,
                        payPUSD: false,
                        minReceivedFromBurningPUSD: 0n,
                    };
                    await expect(positionRouter2.connect(trader).cancelMintLPT(arg, trader.address))
                        .to.be.revertedWithCustomError(positionRouter2, "TooEarly")
                        .withArgs(earliest);

                    await mine(100n);
                    let idExpected = keccak256(
                        defaultAbiCoder.encode(
                            ["address", "address", "uint96", "uint256", "address", "bool", "uint96"],
                            [trader.address, market.target, liquidityDelta, minExecutionFee, trader.address, false, 0n],
                        ),
                    );
                    expect(await positionRouter2.blockNumbers(idExpected)).to.not.eq(0n);

                    await positionRouter2.connect(trader).cancelMintLPT(arg, trader.address);
                    expect(await positionRouter2.blockNumbers(idExpected)).to.eq(0n);
                });
            });

            it("should pass if request not exist", async () => {
                const {owner, weth, positionRouter2} = await loadFixture(deployFixture);
                await positionRouter2.cancelMintLPT(
                    {
                        account: owner.address,
                        market: weth.target,
                        liquidityDelta: 0n,
                        executionFee: minExecutionFee,
                        receiver: owner.address,
                        payPUSD: false,
                        minReceivedFromBurningPUSD: 0n,
                    },
                    owner.address,
                );
            });

            it("should revert with 'Forbidden' if caller is not request owner", async () => {
                const {positionRouter2, trader, other, market} = await loadFixture(deployFixture);
                await positionRouter2.connect(trader).createMintLPT(market, liquidityDelta, trader.address, "0x", {
                    value: minExecutionFee,
                });
                await expect(
                    positionRouter2.connect(other).cancelMintLPT(
                        {
                            account: trader.address,
                            market: market.target,
                            liquidityDelta: liquidityDelta,
                            executionFee: minExecutionFee,
                            receiver: trader.address,
                            payPUSD: false,
                            minReceivedFromBurningPUSD: 0n,
                        },
                        other.address,
                    ),
                ).to.be.revertedWithCustomError(positionRouter2, "Forbidden");
            });

            it("should be ok if executor cancel and market is not weth", async () => {
                const {positionRouter2, market, trader, executor} = await loadFixture(deployFixture);
                await positionRouter2.connect(trader).createMintLPT(market, liquidityDelta, trader.address, "0x", {
                    value: minExecutionFee,
                });
                let idParam = {
                    account: trader.address,
                    market: market.target,
                    liquidityDelta: liquidityDelta,
                    executionFee: minExecutionFee,
                    receiver: trader.address,
                    payPUSD: false,
                    minReceivedFromBurningPUSD: 0n,
                };
                const tx = positionRouter2.connect(executor).cancelMintLPT(idParam, executor.address);
                await expect(tx).to.changeEtherBalances(
                    [positionRouter2, executor],
                    [-minExecutionFee, minExecutionFee],
                );
                await expect(tx).to.changeTokenBalances(
                    market,
                    [positionRouter2, trader],
                    [-liquidityDelta, liquidityDelta],
                );
                let id = mintLPTId(idParam);
                await expect(tx).to.emit(positionRouter2, "MintLPTCancelled").withArgs(id, executor.address);

                let blockNumber = await positionRouter2.blockNumbers(id);
                expect(blockNumber).eq(0);
            });
            it("should be ok if executor cancel and market is weth", async () => {
                const {positionRouter2, weth, trader, executor} = await loadFixture(deployFixture);
                await positionRouter2
                    .connect(trader)
                    .createMintLPTETH(trader.address, minExecutionFee, {value: minExecutionFee + 100n});
                let idParam = {
                    account: trader.address,
                    market: weth.target,
                    liquidityDelta: 100n,
                    executionFee: minExecutionFee,
                    receiver: trader.address,
                    payPUSD: false,
                    minReceivedFromBurningPUSD: 0n,
                };
                const tx = positionRouter2.connect(executor).cancelMintLPT(idParam, executor.address);
                await expect(tx).to.changeEtherBalances(
                    [positionRouter2, executor, trader],
                    [-minExecutionFee, minExecutionFee, 100n],
                );
                await expect(tx).to.changeTokenBalance(weth, positionRouter2, -100n);
                let id = mintLPTId(idParam);
                await expect(tx).to.emit(positionRouter2, "MintLPTCancelled").withArgs(id, executor.address);
                // validation
                let blockNumber = await positionRouter2.blockNumbers(id);
                expect(blockNumber).eq(0);
            });
            it("should be ok if executor cancel and payPUSD is true", async () => {
                const {positionRouter2, market, usd, trader, executor} = await loadFixture(deployFixture);
                await positionRouter2
                    .connect(trader)
                    .createMintLPTPayPUSD(market.target, 100n, trader.address, 0n, "0x", {value: minExecutionFee});
                let idParam = {
                    account: trader.address,
                    market: market.target,
                    liquidityDelta: 100n,
                    executionFee: minExecutionFee,
                    receiver: trader.address,
                    payPUSD: true,
                    minReceivedFromBurningPUSD: 0n,
                };
                let id = mintLPTId(idParam);
                const tx = positionRouter2.connect(executor).cancelMintLPT(idParam, executor.address);
                await expect(tx).to.changeEtherBalances(
                    [positionRouter2, executor],
                    [-minExecutionFee, minExecutionFee],
                );
                await expect(tx).to.changeTokenBalances(usd, [positionRouter2, trader], [-100n, 100n]);
                await expect(tx).to.emit(positionRouter2, "MintLPTCancelled").withArgs(id, executor.address);

                let blockNumber = await positionRouter2.blockNumbers(id);
                expect(blockNumber).eq(0);
            });

            it("should be ok if request owner calls and market is not weth", async () => {
                const {positionRouter2, market, trader} = await loadFixture(deployFixture);
                await positionRouter2.connect(trader).createMintLPT(market, liquidityDelta, trader.address, "0x", {
                    value: minExecutionFee,
                });
                let idParam = {
                    account: trader.address,
                    market: market.target,
                    liquidityDelta: liquidityDelta,
                    executionFee: minExecutionFee,
                    receiver: trader.address,
                    payPUSD: false,
                    minReceivedFromBurningPUSD: 0n,
                };
                let id = mintLPTId(idParam);
                await mine(await positionRouter2.minBlockDelayPublic());
                const tx = positionRouter2.connect(trader).cancelMintLPT(idParam, trader.address);
                await expect(tx).to.changeEtherBalances([positionRouter2, trader], [-minExecutionFee, minExecutionFee]);
                await expect(tx).to.changeTokenBalances(
                    market,
                    [positionRouter2, trader],
                    [-liquidityDelta, liquidityDelta],
                );
                await expect(tx).to.emit(positionRouter2, "MintLPTCancelled").withArgs(id, trader.address);
                let blockNumber = await positionRouter2.blockNumbers(id);
                expect(blockNumber).eq(0);
            });
            it("should be ok if request owner calls and market is weth", async () => {
                const {positionRouter2, weth, trader} = await loadFixture(deployFixture);
                await positionRouter2
                    .connect(trader)
                    .createMintLPTETH(trader.address, minExecutionFee, {value: minExecutionFee + 100n});
                let idParam = {
                    account: trader.address,
                    market: weth.target,
                    liquidityDelta: 100n,
                    executionFee: minExecutionFee,
                    receiver: trader.address,
                    payPUSD: false,
                    minReceivedFromBurningPUSD: 0n,
                };
                let id = mintLPTId(idParam);
                await mine(await positionRouter2.minBlockDelayPublic());
                const tx = positionRouter2.connect(trader).cancelMintLPT(idParam, trader.address);
                await expect(tx).to.changeEtherBalances(
                    [positionRouter2, trader],
                    [-minExecutionFee, minExecutionFee + 100n],
                );
                await expect(tx).to.changeTokenBalance(weth, positionRouter2, -100n);
                await expect(tx).to.emit(positionRouter2, "MintLPTCancelled").withArgs(id, trader.address);
                let blockNumber = await positionRouter2.blockNumbers(id);
                expect(blockNumber).eq(0);
            });
            it("should be ok if request owner calls and payPUSD is true", async () => {
                const {positionRouter2, market, usd, trader} = await loadFixture(deployFixture);
                await positionRouter2
                    .connect(trader)
                    .createMintLPTPayPUSD(market.target, 100n, trader.address, 0n, "0x", {value: minExecutionFee});
                let idParam = {
                    account: trader.address,
                    market: market.target,
                    liquidityDelta: 100n,
                    executionFee: minExecutionFee,
                    receiver: trader.address,
                    payPUSD: true,
                    minReceivedFromBurningPUSD: 0n,
                };
                await mine(await positionRouter2.minBlockDelayPublic());
                const tx = positionRouter2.connect(trader).cancelMintLPT(idParam, trader.address);
                await expect(tx).to.changeTokenBalances(usd, [positionRouter2, trader], [-100n, 100n]);
                await expect(tx).to.changeEtherBalances([positionRouter2, trader], [-minExecutionFee, minExecutionFee]);
                let id = mintLPTId(idParam);
                await expect(tx).to.emit(positionRouter2, "MintLPTCancelled").withArgs(id, trader.address);
                let blockNumber = await positionRouter2.blockNumbers(id);
                expect(blockNumber).eq(0);
            });
        });
        describe("#executeMintLPT", () => {
            it("should pass if request is not exist", async () => {
                const {owner, trader, weth, positionRouter2} = await loadFixture(deployFixture);
                await positionRouter2.executeMintLPT(
                    {
                        account: trader.address,
                        market: weth.target,
                        liquidityDelta: 100n,
                        executionFee: minExecutionFee,
                        receiver: trader.address,
                        payPUSD: false,
                        minReceivedFromBurningPUSD: 0n,
                    },
                    owner.address,
                );
            });

            it("should revert with 'Forbidden' if caller is not executor nor request owner", async () => {
                const {trader, other, market, positionRouter2} = await loadFixture(deployFixture);
                await positionRouter2.connect(trader).createMintLPT(market, liquidityDelta, trader.address, "0x", {
                    value: minExecutionFee,
                });
                let idParam = {
                    account: trader.address,
                    market: market.target,
                    liquidityDelta: liquidityDelta,
                    executionFee: minExecutionFee,
                    receiver: trader.address,
                    payPUSD: false,
                    minReceivedFromBurningPUSD: 0n,
                };
                await positionRouter2.updateDelayValues(0n, 0n, 600n);
                await expect(
                    positionRouter2.connect(other).executeMintLPT(idParam, other.address),
                ).to.be.revertedWithCustomError(positionRouter2, "Forbidden");
            });

            it("should revert with 'Expired' if maxBlockDelay passed", async () => {
                const {positionRouter2, market, trader, executor} = await loadFixture(deployFixture);
                await positionRouter2.updateDelayValues(0n, 0n, 600n);
                await positionRouter2.connect(trader).createMintLPT(market, liquidityDelta, trader.address, "0x", {
                    value: minExecutionFee,
                });
                let idParam = {
                    account: trader.address,
                    market: market.target,
                    liquidityDelta: liquidityDelta,
                    executionFee: minExecutionFee,
                    receiver: trader.address,
                    payPUSD: false,
                    minReceivedFromBurningPUSD: 0n,
                };
                const expiredAt = (await time.latestBlock()) + 600;
                await mine(600n);
                await expect(positionRouter2.connect(executor).executeMintLPT(idParam, executor.address))
                    .to.be.revertedWithCustomError(positionRouter2, "Expired")
                    .withArgs(expiredAt);
            });

            it("should revert with 'TooEarly' if someone who are not the executor executes his own request and pass if sufficient time elapsed", async () => {
                const {positionRouter2, market, trader} = await loadFixture(deployFixture);
                await positionRouter2.connect(trader).createMintLPT(market, liquidityDelta, trader.address, "0x", {
                    value: minExecutionFee,
                });
                let idParam = {
                    account: trader.address,
                    market: market.target,
                    liquidityDelta: liquidityDelta,
                    executionFee: minExecutionFee,
                    receiver: trader.address,
                    payPUSD: false,
                    minReceivedFromBurningPUSD: 0n,
                };
                const current = BigInt(await time.latestBlock());
                const minBlockDelayPublic = await positionRouter2.minBlockDelayPublic();
                await expect(positionRouter2.connect(trader).executeMintLPT(idParam, trader.address))
                    .to.be.revertedWithCustomError(positionRouter2, "TooEarly")
                    .withArgs(current + minBlockDelayPublic);
                await mine(minBlockDelayPublic);
                await expect(positionRouter2.connect(trader).executeMintLPT(idParam, trader.address)).not.to.be
                    .reverted;
            });

            it("should revert with 'TooLittleReceived' if tokenValue is less than acceptableMinTokenValue", async () => {
                const {positionRouter2, marketManager, market, trader, executor} = await loadFixture(deployFixture);
                await positionRouter2
                    .connect(trader)
                    .createMintLPTPayPUSD(market.target, 100n, trader.address, 200n, "0x", {value: minExecutionFee});
                let idParam = {
                    account: trader.address,
                    market: market.target,
                    liquidityDelta: 100n,
                    executionFee: minExecutionFee,
                    receiver: trader.address,
                    payPUSD: true,
                    minReceivedFromBurningPUSD: 200n,
                };
                // set a delay value to prevent expire
                await positionRouter2.updateDelayValues(0n, 0n, 600n);
                await marketManager.setReceiveAmount(100n);
                const tx = positionRouter2.connect(executor).executeMintLPT(idParam, executor.address);
                await expect(tx)
                    .to.be.revertedWithCustomError(positionRouter2, "TooLittleReceived")
                    .withArgs(200n, 100n);
            });

            it("should emit event and distribute funds", async () => {
                const {positionRouter2, market, marketManager, trader, executor} = await loadFixture(deployFixture);
                await positionRouter2.connect(trader).createMintLPT(market, liquidityDelta, trader.address, "0x", {
                    value: minExecutionFee,
                });

                let idParam = {
                    account: trader.address,
                    market: market.target,
                    liquidityDelta: liquidityDelta,
                    executionFee: minExecutionFee,
                    receiver: trader.address,
                    payPUSD: false,
                    minReceivedFromBurningPUSD: 0n,
                };

                // set a delay value to prevent expire
                await positionRouter2.updateDelayValues(0n, 0n, 600n);
                const tx = positionRouter2.connect(executor).executeMintLPT(idParam, executor.address);
                await expect(tx).to.changeEtherBalances(
                    [positionRouter2, executor],
                    [-minExecutionFee, minExecutionFee],
                );
                await expect(tx).to.changeTokenBalances(
                    market,
                    [positionRouter2, marketManager],
                    [-liquidityDelta, liquidityDelta],
                );
                let id = mintLPTId(idParam);
                await expect(tx).to.emit(positionRouter2, "MintLPTExecuted").withArgs(id, executor.address);
                // delete request
                let blockNumber = await positionRouter2.blockNumbers(id);
                expect(blockNumber).eq(0);
            });
        });
        describe("#executeOrCancelMintLPT", () => {
            it("should revert with 'Forbidden' if caller is not executor", async () => {
                const {owner, trader, weth, positionRouter2} = await loadFixture(deployFixture);
                await expect(
                    positionRouter2.executeOrCancelMintLPT(
                        {
                            account: trader.address,
                            market: weth.target,
                            liquidityDelta: 100n,
                            executionFee: minExecutionFee,
                            receiver: trader.address,
                            payPUSD: false,
                            minReceivedFromBurningPUSD: 0n,
                        },
                        owner.address,
                    ),
                ).to.be.revertedWithCustomError(positionRouter2, "Forbidden");
            });

            it("should cancel request if execution reverted", async () => {
                const {trader, executor, positionRouter2, market} = await loadFixture(deployFixture);
                // _maxBlockDelay is 0, execution will revert immediately
                await positionRouter2.updateDelayValues(0, 0, 0);
                await positionRouter2.connect(trader).createMintLPT(market, liquidityDelta, trader.address, "0x", {
                    value: minExecutionFee,
                });
                let idParam = {
                    account: trader.address,
                    market: market.target,
                    liquidityDelta: liquidityDelta,
                    executionFee: minExecutionFee,
                    receiver: trader.address,
                    payPUSD: false,
                    minReceivedFromBurningPUSD: 0n,
                };
                let id = mintLPTId(idParam);
                const tx = positionRouter2.connect(executor).executeOrCancelMintLPT(idParam, executor.address);

                let reason = ethers.id("Expired(uint256)").substring(0, 10);
                await expect(tx)
                    .to.emit(positionRouter2, "ExecuteFailed")
                    .withArgs(0, id, reason)
                    .to.emit(positionRouter2, "MintLPTCancelled")
                    .withArgs(id, executor.address);
            });

            it("should pass if should not execute now", async () => {
                const {trader, executor, positionRouter2, market} = await loadFixture(deployFixture);
                await positionRouter2.updateDelayValues(20, 0, 100);
                await positionRouter2.connect(trader).createMintLPT(market, liquidityDelta, trader.address, "0x", {
                    value: minExecutionFee,
                });
                let idParam = {
                    account: trader.address,
                    market: market.target,
                    liquidityDelta: liquidityDelta,
                    executionFee: minExecutionFee,
                    receiver: trader.address,
                    payPUSD: false,
                    minReceivedFromBurningPUSD: 0n,
                };
                let id = mintLPTId(idParam);
                let blockNumber = await positionRouter2.blockNumbers(id);
                expect(blockNumber).eq(await time.latestBlock());
                await positionRouter2.connect(executor).executeOrCancelMintLPT(idParam, executor.address);
                expect(await positionRouter2.blockNumbers(id)).to.eq(blockNumber);
            });
        });
    });

    describe("BurnLPT", () => {
        describe("#createBurnLPT", () => {
            it("should revert if msg.value is less than minExecutionFee", async () => {
                const {positionRouter2, market, trader} = await loadFixture(deployFixture);

                let minExecutionFeeAfter = ethers.parseUnits("0.0002", marketDecimals);
                await expect(positionRouter2.updateMinExecutionFee(3, minExecutionFeeAfter))
                    .to.emit(positionRouter2, "MinExecutionFeeUpdated")
                    .withArgs(3, minExecutionFeeAfter);
                const value = minExecutionFee;
                // insufficient execution fee
                await expect(positionRouter2.connect(trader).createBurnLPT(market, 10n, 0n, trader, "0x", {value}))
                    .to.be.revertedWithCustomError(positionRouter2, "InsufficientExecutionFee")
                    .withArgs(value, minExecutionFeeAfter);
            });
            it("should revert if allowance is insufficient and permitData is empty", async () => {
                const {positionRouter2, market, lpToken, trader, marketManager} = await loadFixture(deployFixture);
                await marketManager.mintLPToken(market.target, trader.address, 100n);
                await resetAllowance(lpToken, trader, await marketManager.getAddress());
                await expect(
                    positionRouter2
                        .connect(trader)
                        .createBurnLPT(market, 100n, 0n, trader, "0x", {value: minExecutionFee}),
                )
                    .to.be.revertedWithCustomError(lpToken, "ERC20InsufficientAllowance")
                    .withArgs(marketManager.target, 0, 100n);
            });
            it("should revert if allowance is insufficient and permitData is invalid", async () => {
                const {positionRouter2, market, lpToken, trader, marketManager} = await loadFixture(deployFixture);
                await marketManager.mintLPToken(market.target, trader.address, 100n);
                await resetAllowance(lpToken, trader, await marketManager.getAddress());
                await expect(
                    positionRouter2
                        .connect(trader)
                        .createBurnLPT(market, 100n, 0n, trader, "0xabcdef", {value: minExecutionFee}),
                ).to.be.reverted;
            });
            it("should revert if allowance is insufficient and permitData is other's", async () => {
                const {positionRouter2, market, lpToken, trader, other, marketManager} =
                    await loadFixture(deployFixture);
                await marketManager.mintLPToken(market.target, trader.address, 100n);
                await resetAllowance(lpToken, trader, await marketManager.getAddress());
                const permitData = await genERC20PermitData(lpToken, other, await marketManager.getAddress(), 100n);
                await expect(
                    positionRouter2
                        .connect(trader)
                        .createBurnLPT(market, 100n, 0n, trader, permitData, {value: minExecutionFee}),
                )
                    .to.be.revertedWithCustomError(lpToken, "ERC20InsufficientAllowance")
                    .withArgs(marketManager.target, 0, 100n);
            });
            it("should pass if allowance is insufficient and permitData is valid", async () => {
                const {positionRouter2, market, lpToken, trader, marketManager} = await loadFixture(deployFixture);
                await marketManager.mintLPToken(market.target, trader.address, 100n);
                await resetAllowance(lpToken, trader, await marketManager.getAddress());
                for (let i = 0; i < 10; i++) {
                    let amount = 10n + BigInt(i);
                    const permitData = await genERC20PermitData(
                        lpToken,
                        trader,
                        await marketManager.getAddress(),
                        amount,
                    );
                    await marketManager.mintLPToken(market.target, trader.address, amount);
                    const tx = positionRouter2
                        .connect(trader)
                        .createBurnLPT(market, amount, 0n, trader, permitData, {value: minExecutionFee});
                    let idParam = {
                        account: trader.address,
                        market: market.target,
                        amount: amount,
                        acceptableMinLiquidity: 0n,
                        receiver: trader.address,
                        executionFee: minExecutionFee,
                        receivePUSD: false,
                        minPUSDReceived: 0n,
                    };
                    let id = burnLPTId(idParam);
                    await expect(tx)
                        .to.emit(positionRouter2, "BurnLPTCreated")
                        .withArgs(trader.address, market, amount, 0n, trader.address, minExecutionFee, false, 0n, id);
                    await expect(tx).to.changeEtherBalances(
                        [trader, positionRouter2],
                        [-minExecutionFee, minExecutionFee],
                    );
                    await expect(tx).to.changeTokenBalances(lpToken, [trader, positionRouter2], [-amount, amount]);
                    expect(await positionRouter2.blockNumbers(id)).to.eq(await time.latestBlock());
                }
            });
            it("should pass if allowance is sufficient and permitData is empty", async () => {
                const {positionRouter2, market, lpToken, trader, marketManager} = await loadFixture(deployFixture);
                for (let i = 0; i < 10; i++) {
                    let amount = 10n + BigInt(i);
                    await marketManager.mintLPToken(market.target, trader.address, amount);
                    const tx = positionRouter2
                        .connect(trader)
                        .createBurnLPT(market, amount, 0n, trader, "0x", {value: minExecutionFee});
                    let idParam = {
                        account: trader.address,
                        market: market.target,
                        amount: amount,
                        acceptableMinLiquidity: 0n,
                        receiver: trader.address,
                        executionFee: minExecutionFee,
                        receivePUSD: false,
                        minPUSDReceived: 0,
                    };
                    let id = burnLPTId(idParam);
                    await expect(tx)
                        .to.emit(positionRouter2, "BurnLPTCreated")
                        .withArgs(trader.address, market, amount, 0n, trader.address, minExecutionFee, false, 0n, id);
                    await expect(tx).to.changeEtherBalances(
                        [trader, positionRouter2],
                        [-minExecutionFee, minExecutionFee],
                    );
                    await expect(tx).to.changeTokenBalances(lpToken, [trader, positionRouter2], [-amount, amount]);
                    expect(await positionRouter2.blockNumbers(id)).to.eq(await time.latestBlock());
                }
            });
            it("should revert if create two identical requests", async () => {
                const {positionRouter2, market, lpToken, trader, marketManager} = await loadFixture(deployFixture);
                await marketManager.mintLPToken(market.target, trader.address, 200n);
                await positionRouter2
                    .connect(trader)
                    .createBurnLPT(market, 100n, 0n, trader, "0x", {value: minExecutionFee});
                let idParam = {
                    account: trader.address,
                    market: market.target,
                    amount: 100n,
                    acceptableMinLiquidity: 0n,
                    receiver: trader.address,
                    executionFee: minExecutionFee,
                    receivePUSD: false,
                    minPUSDReceived: 0,
                };
                let id = burnLPTId(idParam);
                expect(await positionRouter2.blockNumbers(id)).to.eq(await time.latestBlock());
                await expect(
                    positionRouter2
                        .connect(trader)
                        .createBurnLPT(market, 100n, 0n, trader, "0x", {value: minExecutionFee}),
                )
                    .to.be.revertedWithCustomError(positionRouter2, "ConflictRequests")
                    .withArgs(id);
            });
            it("should pass if create two identical requests except for execution fee", async () => {
                const {positionRouter2, market, lpToken, trader, marketManager} = await loadFixture(deployFixture);
                await marketManager.mintLPToken(market.target, trader.address, 200n);
                await positionRouter2
                    .connect(trader)
                    .createBurnLPT(market, 100n, 0n, trader, "0x", {value: minExecutionFee});
                let idParam = {
                    account: trader.address,
                    market: market.target,
                    amount: 100n,
                    acceptableMinLiquidity: 0n,
                    receiver: trader.address,
                    executionFee: minExecutionFee,
                    receivePUSD: false,
                    minPUSDReceived: 0,
                };
                let id = burnLPTId(idParam);
                expect(await positionRouter2.blockNumbers(id)).to.eq(await time.latestBlock());

                await positionRouter2
                    .connect(trader)
                    .createBurnLPT(market, 100n, 0n, trader, "0x", {value: minExecutionFee + 1n});
                idParam.executionFee = minExecutionFee + 1n;
                id = burnLPTId(idParam);
                expect(await positionRouter2.blockNumbers(id)).to.eq(await time.latestBlock());
            });
        });
        describe("#createBurnLPTReceivePUSD", () => {
            it("should revert if msg.value is less than minExecutionFee", async () => {
                const {positionRouter2, market, trader} = await loadFixture(deployFixture);

                let minExecutionFeeAfter = ethers.parseUnits("0.0002", marketDecimals);
                await expect(positionRouter2.updateMinExecutionFee(4, minExecutionFeeAfter))
                    .to.emit(positionRouter2, "MinExecutionFeeUpdated")
                    .withArgs(4, minExecutionFeeAfter);

                const value = minExecutionFee;
                // insufficient execution fee
                await expect(
                    positionRouter2.connect(trader).createBurnLPTReceivePUSD(market, 100n, 0n, trader, "0x", {value}),
                )
                    .to.be.revertedWithCustomError(positionRouter2, "InsufficientExecutionFee")
                    .withArgs(value, minExecutionFeeAfter);
            });
            it("should revert if allowance is insufficient and permitData is empty", async () => {
                const {positionRouter2, market, lpToken, trader, marketManager} = await loadFixture(deployFixture);
                await marketManager.mintLPToken(market.target, trader.address, 100n);
                await resetAllowance(lpToken, trader, await marketManager.getAddress());
                await expect(
                    positionRouter2
                        .connect(trader)
                        .createBurnLPTReceivePUSD(market, 100n, 0n, trader, "0x", {value: minExecutionFee}),
                )
                    .to.be.revertedWithCustomError(lpToken, "ERC20InsufficientAllowance")
                    .withArgs(marketManager.target, 0, 100n);
            });
            it("should revert if allowance is insufficient and permitData is invalid", async () => {
                const {positionRouter2, market, lpToken, trader, marketManager} = await loadFixture(deployFixture);
                await marketManager.mintLPToken(market.target, trader.address, 100n);
                await resetAllowance(lpToken, trader, await marketManager.getAddress());
                await expect(
                    positionRouter2
                        .connect(trader)
                        .createBurnLPTReceivePUSD(market, 100n, 0n, trader, "0xabcdef", {value: minExecutionFee}),
                ).to.be.reverted;
            });
            it("should revert if allowance is insufficient and permitData is other's", async () => {
                const {positionRouter2, market, lpToken, trader, other, marketManager} =
                    await loadFixture(deployFixture);
                await marketManager.mintLPToken(market.target, trader.address, 100n);
                await resetAllowance(lpToken, trader, await marketManager.getAddress());
                const permitData = await genERC20PermitData(lpToken, other, await marketManager.getAddress(), 100n);
                await expect(
                    positionRouter2
                        .connect(trader)
                        .createBurnLPTReceivePUSD(market, 100n, 0n, trader, permitData, {value: minExecutionFee}),
                )
                    .to.be.revertedWithCustomError(lpToken, "ERC20InsufficientAllowance")
                    .withArgs(marketManager.target, 0, 100n);
            });
            it("should pass if allowance is insufficient and permitData is valid", async () => {
                const {positionRouter2, market, lpToken, trader, marketManager} = await loadFixture(deployFixture);
                resetAllowance(lpToken, trader, await marketManager.getAddress());
                for (let i = 0; i < 10; i++) {
                    let amount = 100n + BigInt(i);
                    await marketManager.mintLPToken(market.target, trader.address, amount);
                    const permitData = await genERC20PermitData(
                        lpToken,
                        trader,
                        await marketManager.getAddress(),
                        amount,
                    );
                    const tx = positionRouter2
                        .connect(trader)
                        .createBurnLPTReceivePUSD(market, amount, 0n, trader, permitData, {value: minExecutionFee});
                    let idParam = {
                        account: trader.address,
                        market: market.target,
                        amount: amount,
                        acceptableMinLiquidity: 0n,
                        receiver: trader.address,
                        executionFee: minExecutionFee,
                        receivePUSD: true,
                        minPUSDReceived: 0,
                    };
                    let id = burnLPTId(idParam);
                    await expect(tx)
                        .to.emit(positionRouter2, "BurnLPTCreated")
                        .withArgs(trader.address, market, amount, 0n, trader.address, minExecutionFee, true, 0n, id);
                    await expect(tx).to.changeEtherBalances(
                        [trader, positionRouter2],
                        [-minExecutionFee, minExecutionFee],
                    );
                    await expect(tx).to.changeTokenBalances(lpToken, [trader, positionRouter2], [-amount, amount]);
                    expect(await positionRouter2.blockNumbers(id)).to.eq(await time.latestBlock());
                }
            });
            it("should pass if allowance is sufficient and permitData is empty", async () => {
                const {positionRouter2, market, lpToken, trader, marketManager} = await loadFixture(deployFixture);
                for (let i = 0; i < 10; i++) {
                    let amount = 100n + BigInt(i);
                    await marketManager.mintLPToken(market.target, trader.address, amount);
                    const tx = positionRouter2
                        .connect(trader)
                        .createBurnLPTReceivePUSD(market, amount, 0n, trader, "0x", {value: minExecutionFee});
                    let idParam = {
                        account: trader.address,
                        market: market.target,
                        amount: amount,
                        acceptableMinLiquidity: 0n,
                        receiver: trader.address,
                        executionFee: minExecutionFee,
                        receivePUSD: true,
                        minPUSDReceived: 0,
                    };
                    let id = burnLPTId(idParam);
                    await expect(tx)
                        .to.emit(positionRouter2, "BurnLPTCreated")
                        .withArgs(trader.address, market, amount, 0n, trader.address, minExecutionFee, true, 0n, id);
                    await expect(tx).to.changeEtherBalances(
                        [trader, positionRouter2],
                        [-minExecutionFee, minExecutionFee],
                    );
                    await expect(tx).to.changeTokenBalances(lpToken, [trader, positionRouter2], [-amount, amount]);
                    expect(await positionRouter2.blockNumbers(id)).to.eq(await time.latestBlock());
                }
            });
        });

        describe("#cancelBurnLPT", () => {
            it("should pass if request not exist", async () => {
                const {trader, weth, positionRouter2} = await loadFixture(deployFixture);
                await positionRouter2.cancelBurnLPT(
                    {
                        account: trader.address,
                        market: weth.target,
                        amount: 10n,
                        acceptableMinLiquidity: 0n,
                        receiver: trader.address,
                        executionFee: minExecutionFee,
                        receivePUSD: true,
                        minPUSDReceived: 0,
                    },
                    trader.address,
                );
            });

            it("should revert with 'Forbidden' if caller is not executor nor request owner", async () => {
                const {positionRouter2, marketManager, market, trader, other} = await loadFixture(deployFixture);
                await marketManager.mintLPToken(market.target, trader.address, 100n);
                await positionRouter2
                    .connect(trader)
                    .createBurnLPT(market, 100n, 0n, trader.address, "0x", {value: minExecutionFee});
                let idParam = {
                    account: trader.address,
                    market: market.target,
                    amount: 100n,
                    acceptableMinLiquidity: 0n,
                    receiver: trader.address,
                    executionFee: minExecutionFee,
                    receivePUSD: false,
                    minPUSDReceived: 0,
                };
                await mine(await positionRouter2.minBlockDelayPublic());
                await expect(
                    positionRouter2.connect(other).cancelBurnLPT(idParam, other.address),
                ).to.be.revertedWithCustomError(positionRouter2, "Forbidden");
                // request owner should be able to cancel
                await positionRouter2.connect(trader).cancelBurnLPT(idParam, trader.address);
            });

            it("should emit event and refund", async () => {
                const {positionRouter2, marketManager, lpToken, market, trader, executor} =
                    await loadFixture(deployFixture);
                await marketManager.mintLPToken(market.target, trader.address, 100n);
                await positionRouter2
                    .connect(trader)
                    .createBurnLPT(market, 100n, 0n, trader.address, "0x", {value: minExecutionFee});
                let idParam = {
                    account: trader.address,
                    market: market.target,
                    amount: 100n,
                    acceptableMinLiquidity: 0n,
                    receiver: trader.address,
                    executionFee: minExecutionFee,
                    receivePUSD: false,
                    minPUSDReceived: 0,
                };
                const tx = positionRouter2.connect(executor).cancelBurnLPT(idParam, executor.address);
                await expect(tx).to.changeEtherBalances(
                    [positionRouter2, executor],
                    [-minExecutionFee, minExecutionFee],
                );
                await expect(tx).to.changeTokenBalances(lpToken, [positionRouter2, trader], [-100n, 100n]);
                let id = burnLPTId(idParam);
                await expect(tx).to.emit(positionRouter2, "BurnLPTCancelled").withArgs(id, executor.address);

                let blockNumber = await positionRouter2.blockNumbers(id);
                expect(blockNumber).eq(0);
            });
        });

        describe("#executeBurnLPT", async () => {
            it("should pass if request not exist", async () => {
                const {trader, market, positionRouter2} = await loadFixture(deployFixture);
                await positionRouter2.executeBurnLPT(
                    {
                        account: trader.address,
                        market: market.target,
                        amount: 100n,
                        acceptableMinLiquidity: 0n,
                        receiver: trader.address,
                        executionFee: minExecutionFee,
                        receivePUSD: false,
                        minPUSDReceived: 0,
                    },
                    trader.address,
                );
            });

            it("should revert with 'Forbidden' if caller is not executor nor request owner", async () => {
                const {positionRouter2, marketManager, market, trader, other} = await loadFixture(deployFixture);
                await marketManager.mintLPToken(market.target, trader.address, 100n);
                await positionRouter2
                    .connect(trader)
                    .createBurnLPT(market, 100n, 0n, trader.address, "0x", {value: minExecutionFee});
                await positionRouter2.updateDelayValues(0n, 0n, 600n);
                let idParam = {
                    account: trader.address,
                    market: market.target,
                    amount: 100n,
                    acceptableMinLiquidity: 0n,
                    receiver: trader.address,
                    executionFee: minExecutionFee,
                    receivePUSD: false,
                    minPUSDReceived: 0,
                };
                await expect(
                    positionRouter2.connect(other).executeBurnLPT(idParam, other.address),
                ).to.be.revertedWithCustomError(positionRouter2, "Forbidden");
            });

            it("should revert with 'Expired' if maxBlockDelay passed", async () => {
                const {positionRouter2, marketManager, market, trader, executor} = await loadFixture(deployFixture);
                await marketManager.mintLPToken(market.target, trader.address, 100n);
                await positionRouter2.updateDelayValues(0n, 0n, 600n);
                await positionRouter2
                    .connect(trader)
                    .createBurnLPT(market, 100n, 0n, trader.address, "0x", {value: minExecutionFee});
                let idParam = {
                    account: trader.address,
                    market: market.target,
                    amount: 100n,
                    acceptableMinLiquidity: 0n,
                    receiver: trader.address,
                    executionFee: minExecutionFee,
                    receivePUSD: false,
                    minPUSDReceived: 0,
                };
                const expiredAt = (await time.latestBlock()) + 600;
                await mine(600n);
                await expect(positionRouter2.connect(executor).executeBurnLPT(idParam, executor.address))
                    .to.be.revertedWithCustomError(positionRouter2, "Expired")
                    .withArgs(expiredAt);
            });

            it("should revert with 'TooEarly' if someone who are not the executor executes his own request and pass if sufficient time elapsed", async () => {
                const {positionRouter2, marketManager, market, trader} = await loadFixture(deployFixture);
                await marketManager.mintLPToken(market.target, trader.address, 100n);
                await positionRouter2
                    .connect(trader)
                    .createBurnLPT(market, 100n, 0n, trader.address, "0x", {value: minExecutionFee});
                let idParam = {
                    account: trader.address,
                    market: market.target,
                    amount: 100n,
                    acceptableMinLiquidity: 0n,
                    receiver: trader.address,
                    executionFee: minExecutionFee,
                    receivePUSD: false,
                    minPUSDReceived: 0,
                };
                const current = BigInt(await time.latestBlock());
                const minBlockDelayPublic = await positionRouter2.minBlockDelayPublic();
                await expect(positionRouter2.connect(trader).executeBurnLPT(idParam, trader.address))
                    .to.be.revertedWithCustomError(positionRouter2, "TooEarly")
                    .withArgs(current + minBlockDelayPublic);
                await mine(minBlockDelayPublic);
                await expect(positionRouter2.connect(trader).executeBurnLPT(idParam, trader.address)).not.to.be
                    .reverted;
            });

            it("should revert with 'TooLittleReceived' if receiveAmount is less than minPUSDReceived", async () => {
                const {positionRouter2, marketManager, market, trader, executor} = await loadFixture(deployFixture);
                await marketManager.mintLPToken(market.target, trader.address, 100n);
                await positionRouter2
                    .connect(trader)
                    .createBurnLPTReceivePUSD(market, 100n, 200n, trader, "0x", {value: minExecutionFee});
                let idParam = {
                    account: trader.address,
                    market: market.target,
                    amount: 100n,
                    acceptableMinLiquidity: 0n,
                    receiver: trader.address,
                    executionFee: minExecutionFee,
                    receivePUSD: true,
                    minPUSDReceived: 200n,
                };
                // set a delay value to prevent expire
                await positionRouter2.updateDelayValues(0n, 0n, 600n);
                await marketManager.setLiquidity(100n);
                await marketManager.setReceivePUSD(true);
                await marketManager.setPayAmount(100n);
                await marketManager.setReceiveAmount(100n);
                const tx = positionRouter2.connect(executor).executeBurnLPT(idParam, executor.address);
                await expect(tx)
                    .to.be.revertedWithCustomError(positionRouter2, "TooLittleReceived")
                    .withArgs(200n, 100n);
            });

            it("should revert with 'TooLittleReceived' if liquidity is less than acceptableMinLiquidity", async () => {
                const {positionRouter2, marketManager, market, trader, executor} = await loadFixture(deployFixture);
                await marketManager.mintLPToken(market.target, trader.address, 100n);
                await positionRouter2
                    .connect(trader)
                    .createBurnLPT(market, 100n, 200n, trader.address, "0x", {value: minExecutionFee});

                let idParam = {
                    account: trader.address,
                    market: market.target,
                    amount: 100n,
                    acceptableMinLiquidity: 200n,
                    receiver: trader.address,
                    executionFee: minExecutionFee,
                    receivePUSD: false,
                    minPUSDReceived: 0n,
                };

                // set a delay value to prevent expire
                await positionRouter2.updateDelayValues(0n, 0n, 600n);
                await marketManager.setLiquidity(100n);
                const tx = positionRouter2.connect(executor).executeBurnLPT(idParam, executor.address);
                await expect(tx)
                    .to.be.revertedWithCustomError(positionRouter2, "TooLittleReceived")
                    .withArgs(200n, 100n);
            });

            it("should emit event and transfer execution fee when the market is not weth", async () => {
                const {positionRouter2, marketManager, market, lpToken, trader, executor} =
                    await loadFixture(deployFixture);
                await marketManager.mintLPToken(market.target, trader.address, 100n);
                await positionRouter2
                    .connect(trader)
                    .createBurnLPT(market, 100n, 0n, trader.address, "0x", {value: minExecutionFee});
                let idParam = {
                    account: trader.address,
                    market: market.target,
                    amount: 100n,
                    acceptableMinLiquidity: 0n,
                    receiver: trader.address,
                    executionFee: minExecutionFee,
                    receivePUSD: false,
                    minPUSDReceived: 0n,
                };

                // set a delay value to prevent expire
                await positionRouter2.updateDelayValues(0n, 0n, 600n);

                const tx = positionRouter2.connect(executor).executeBurnLPT(idParam, executor.address);
                await expect(tx).to.changeEtherBalances(
                    [positionRouter2, executor],
                    [-minExecutionFee, minExecutionFee],
                );
                await expect(tx).to.changeTokenBalances(lpToken, [positionRouter2, marketManager], [-100n, 100n]);
                let id = burnLPTId(idParam);
                await expect(tx).to.emit(positionRouter2, "BurnLPTExecuted").withArgs(id, executor.address);
                let blockNumber = await positionRouter2.blockNumbers(id);
                expect(blockNumber).eq(0);
            });
            it("should emit event and transfer execution fee when the market is weth", async () => {
                const {positionRouter2, marketManager, weth, wethLpToken, trader, executor, other} =
                    await loadFixture(deployFixture);
                await marketManager.mintLPToken(weth.target, trader.address, 100n);
                await positionRouter2
                    .connect(trader)
                    .createBurnLPT(weth, 100n, 0n, other.address, "0x", {value: minExecutionFee});
                let idParam = {
                    account: trader.address,
                    market: weth.target,
                    amount: 100n,
                    acceptableMinLiquidity: 0n,
                    receiver: other.address,
                    executionFee: minExecutionFee,
                    receivePUSD: false,
                    minPUSDReceived: 0n,
                };

                // set a delay value to prevent expire
                await positionRouter2.updateDelayValues(0n, 0n, 600n);

                await marketManager.setLiquidity(100n);
                const tx = positionRouter2.connect(executor).executeBurnLPT(idParam, executor.address);
                await expect(tx).to.changeEtherBalances(
                    [positionRouter2, executor, other],
                    [-minExecutionFee, minExecutionFee, 100n],
                );
                await expect(tx).to.changeTokenBalances(wethLpToken, [positionRouter2, marketManager], [-100n, 100n]);
                let id = burnLPTId(idParam);
                await expect(tx).to.emit(positionRouter2, "BurnLPTExecuted").withArgs(id, executor.address);
                let blockNumber = await positionRouter2.blockNumbers(id);
                expect(blockNumber).eq(0);
            });
        });

        describe("#executeOrCancelBurnLPT", () => {
            it("should revert with 'Forbidden' if caller is not executor", async () => {
                const {owner, trader, market, positionRouter2} = await loadFixture(deployFixture);
                await expect(
                    positionRouter2.executeOrCancelBurnLPT(
                        {
                            account: trader.address,
                            market: market.target,
                            amount: 100n,
                            acceptableMinLiquidity: 0n,
                            receiver: trader.address,
                            executionFee: minExecutionFee,
                            receivePUSD: false,
                            minPUSDReceived: 0,
                        },
                        owner.address,
                    ),
                ).to.be.revertedWithCustomError(positionRouter2, "Forbidden");
            });

            it("should cancel request if execution reverted", async () => {
                const {trader, marketManager, executor, positionRouter2, market} = await loadFixture(deployFixture);
                await marketManager.mintLPToken(market.target, trader.address, 300n);

                // _maxBlockDelay is 0, execution will revert immediately
                await positionRouter2.updateDelayValues(0, 0, 0);
                await positionRouter2
                    .connect(trader)
                    .createBurnLPT(market, 100n, 0n, trader.address, "0x", {value: minExecutionFee});
                let idParam = {
                    account: trader.address,
                    market: market.target,
                    amount: 100n,
                    acceptableMinLiquidity: 0n,
                    receiver: trader.address,
                    executionFee: minExecutionFee,
                    receivePUSD: false,
                    minPUSDReceived: 0,
                };

                let id = burnLPTId(idParam);
                const tx = positionRouter2.connect(executor).executeOrCancelBurnLPT(idParam, executor.address);

                let reason = ethers.id("Expired(uint256)").substring(0, 10);
                await expect(tx)
                    .to.emit(positionRouter2, "ExecuteFailed")
                    .withArgs(1, id, reason)
                    .to.emit(positionRouter2, "BurnLPTCancelled")
                    .withArgs(id, executor.address);
            });

            it("should pass if should execute returns false", async () => {
                const {trader, executor, marketManager, positionRouter2, market} = await loadFixture(deployFixture);
                await marketManager.mintLPToken(market.target, trader.address, 300n);
                await positionRouter2.updateDelayValues(20, 0, 100);
                await positionRouter2
                    .connect(trader)
                    .createBurnLPT(market, 100n, 0n, trader.address, "0x", {value: minExecutionFee});
                let idParam = {
                    account: trader.address,
                    market: market.target,
                    amount: 100n,
                    acceptableMinLiquidity: 0n,
                    receiver: trader.address,
                    executionFee: minExecutionFee,
                    receivePUSD: false,
                    minPUSDReceived: 0,
                };
                let id = burnLPTId(idParam);
                let blockNumber = await positionRouter2.blockNumbers(id);
                expect(blockNumber).eq(await time.latestBlock());
                const tx = positionRouter2.connect(executor).executeOrCancelBurnLPT(idParam, executor.address);
                await positionRouter2.connect(executor).executeOrCancelBurnLPT(idParam, executor.address);
                expect(await positionRouter2.blockNumbers(id)).to.eq(blockNumber);
            });
        });
    });
});

function mintLPTId(args: IPositionRouter2.MintLPTRequestIdParamStruct) {
    return keccak256(
        defaultAbiCoder.encode(
            ["address", "address", "uint96", "uint256", "address", "bool", "uint96"],
            [
                args.account,
                args.market,
                args.liquidityDelta,
                args.executionFee,
                args.receiver,
                args.payPUSD,
                args.minReceivedFromBurningPUSD,
            ],
        ),
    );
}

function burnLPTId(args: IPositionRouter2.BurnLPTRequestIdParamStruct) {
    return keccak256(
        defaultAbiCoder.encode(
            ["address", "address", "uint64", "uint96", "address", "uint256", "bool", "uint64"],
            [
                args.account,
                args.market,
                args.amount,
                args.acceptableMinLiquidity,
                args.receiver,
                args.executionFee,
                args.receivePUSD,
                args.minPUSDReceived,
            ],
        ),
    );
}
