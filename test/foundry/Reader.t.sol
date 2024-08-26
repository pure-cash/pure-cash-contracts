// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.26;

import "./BaseTest.t.sol";
import "../../contracts/test/WETH9.sol";
import "../../contracts/misc/Reader.sol";
import "../../contracts/core/PUSD.sol";
import "../../contracts/test/MockPriceFeed.sol";
import "../../contracts/test/ERC20Test.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract ReaderTest is BaseTest, IPUSDManagerCallback {
    using SafeERC20 for *;

    Reader reader;
    PUSD pusd;
    MarketManagerUpgradeable marketManager;

    IERC20 weth;

    function setUp() public {
        address marketManagerImpl = address(new MarketManagerUpgradeable());
        marketManager = MarketManagerUpgradeable(
            address(
                new ERC1967Proxy(
                    marketManagerImpl,
                    abi.encodeWithSelector(
                        MarketManagerUpgradeable.initialize.selector,
                        this,
                        FeeDistributorUpgradeable(address(this)),
                        true
                    )
                )
            )
        );
        pusd = PUSD(marketManager.pusd());

        reader = new Reader(marketManager);
        weth = IERC20(address(deployWETH9()));
        marketManager.enableMarket(weth, "LPT-ETH", cfg);

        marketManager.updatePlugin(address(this), true);
        marketManager.updateUpdater(address(this));
        marketManager.updatePrice(encodePrice(weth, PRICE, uint32(block.timestamp)));
    }

    function test_quoteBurnPUSDToMintLPT_revertIf_marketNotEnabled() public view {
        (bool success, bytes memory returnData) = address(reader).staticcall(
            abi.encodeWithSelector(Reader.quoteBurnPUSDToMintLPT.selector, address(0), 0, 0)
        );
        assertFalse(success);
        assertTrue(IConfigurable.MarketNotEnabled.selector == abi.decode(returnData, (bytes4)));
    }

    function test_quoteBurnPUSDToMintLPT_pass() public {
        deal(address(weth), ALICE, 100 * 10 ** 18);
        vm.prank(ALICE);
        weth.safeTransfer(address(marketManager), 100 * 10 ** 18);
        marketManager.mintLPT(weth, ALICE, ALICE);

        deal(address(weth), BOB, 10 * 10 ** 18);
        vm.prank(BOB);
        weth.safeTransfer(address(marketManager), 10 * 10 ** 18);
        marketManager.increasePosition(weth, BOB, 10 * 10 ** 18);

        marketManager.mintPUSD(weth, true, 10 * 10 ** 18, IPUSDManagerCallback(address(this)), bytes(""), BOB);

        uint256 pusdValue = pusd.balanceOf(BOB);
        (uint96 burnPUSDReceiveAmount, uint64 mintLPTTokenValue) = reader.quoteBurnPUSDToMintLPT(
            weth,
            uint96(pusdValue),
            PRICE
        );
        assertEq(burnPUSDReceiveAmount, 9985910003897232965);
        assertEq(mintLPTTokenValue, 29853835581);
    }

    function test_quoteBurnLPTToMintPUSD_revertIf_marketNotEnabled() public view {
        (bool success, bytes memory returnData) = address(reader).staticcall(
            abi.encodeWithSelector(Reader.quoteBurnLPTToMintPUSD.selector, address(0), 0, 0)
        );
        assertFalse(success);
        assertTrue(IConfigurable.MarketNotEnabled.selector == abi.decode(returnData, (bytes4)));
    }

    function test_quoteBurnLPTToMintPUSD_pass() public {
        deal(address(weth), ALICE, 100 * 10 ** 18);
        vm.prank(ALICE);
        weth.safeTransfer(address(marketManager), 100 * 10 ** 18);
        marketManager.mintLPT(weth, ALICE, ALICE);

        deal(address(weth), BOB, 10 * 10 ** 18);
        vm.prank(BOB);
        weth.safeTransfer(address(marketManager), 10 * 10 ** 18);
        marketManager.increasePosition(weth, BOB, 10 * 10 ** 18);

        deal(address(weth), CARRIE, 5 * 10 ** 18);
        vm.prank(CARRIE);
        weth.safeTransfer(address(marketManager), 5 * 10 ** 18);
        uint64 lptAmount = marketManager.mintLPT(weth, CARRIE, CARRIE);

        (uint96 burnLPTReceiveAmount, uint64 mintPUSDTokenValue) = reader.quoteBurnLPTToMintPUSD(
            weth,
            lptAmount,
            PRICE
        );

        assertEq(burnLPTReceiveAmount, 4999999999801664324);
        assertEq(mintPUSDTokenValue, 14938941634);
    }

    function test_quoteBurnPUSDToIncreasePosition_passIf_emptyPosition() public {
        deal(address(weth), ALICE, 100 * 10 ** 18);
        vm.prank(ALICE);
        weth.safeTransfer(address(marketManager), 100 * 10 ** 18);
        marketManager.mintLPT(weth, ALICE, ALICE);

        deal(address(weth), BOB, 60 * 10 ** 18);
        vm.prank(BOB);
        weth.safeTransfer(address(marketManager), 60 * 10 ** 18);
        marketManager.increasePosition(weth, BOB, 60 * 10 ** 18);

        (, uint64 receiveAmount) = marketManager.mintPUSD(
            weth,
            true,
            10 * 10 ** 18,
            IPUSDManagerCallback(address(this)),
            bytes(""),
            BOB
        );
        (uint96 burnPUSDReceiveAmount, uint96 size, IMarketPosition.Position memory position) = reader
            .quoteBurnPUSDToIncreasePosition(weth, CARRIE, receiveAmount, PRICE, 2 * 10 ** 7);

        assertEq(burnPUSDReceiveAmount, 9985411087573444183);
        assertEq(size, 19942863024101682722);
        assertEq(position.size, size);
        assertEq(position.entryPrice, PRICE);

        position = reader.longPositions(CARRIE);
        assertEq(0, position.size);

        position = reader.longPositions(address(reader));
        assertEq(0, position.size);
    }

    function test_quoteBurnPUSDToIncreasePosition_passIf_positionAlreadyExists() public {
        deal(address(weth), ALICE, 100 * 10 ** 18);
        vm.prank(ALICE);
        weth.safeTransfer(address(marketManager), 100 * 10 ** 18);
        marketManager.mintLPT(weth, ALICE, ALICE);

        deal(address(weth), BOB, 60 * 10 ** 18);
        vm.prank(BOB);
        weth.safeTransfer(address(marketManager), 60 * 10 ** 18);
        marketManager.increasePosition(weth, BOB, 60 * 10 ** 18);

        (, uint64 receiveAmount) = marketManager.mintPUSD(
            weth,
            true,
            10 * 10 ** 18,
            IPUSDManagerCallback(address(this)),
            bytes(""),
            BOB
        );
        (uint96 burnPUSDReceiveAmount, uint96 size, IMarketPosition.Position memory position) = reader
            .quoteBurnPUSDToIncreasePosition(weth, BOB, receiveAmount, PRICE, 2 * 10 ** 7);

        assertEq(burnPUSDReceiveAmount, 9985411087573444183);
        assertEq(size, 19942863024101682722);
        assertEq(position.size, size + 60 * 10 ** 18);
        assertEq(position.entryPrice, PRICE);

        position = reader.longPositions(BOB);
        assertEq(0, position.size);

        position = reader.longPositions(address(reader));
        assertEq(0, position.size);
    }

    function test_quoteDecreasePositionToMintPUSD_revertIf_positionNotFound() public {
        vm.expectRevert(abi.encodeWithSelector(IMarketErrors.PositionNotFound.selector, ALICE));
        reader.quoteDecreasePositionToMintPUSD(weth, ALICE, 0, 0);
    }

    function test_quoteDecreasePositionToMintPUSD_revertIf_insufficientSizeToDecrease() public {
        deal(address(weth), ALICE, 100 * 10 ** 18);
        vm.prank(ALICE);
        weth.safeTransfer(address(marketManager), 100 * 10 ** 18);
        marketManager.mintLPT(weth, ALICE, ALICE);

        deal(address(weth), BOB, 60 * 10 ** 18);
        vm.prank(BOB);
        weth.safeTransfer(address(marketManager), 60 * 10 ** 18);
        marketManager.increasePosition(weth, BOB, 60 * 10 ** 18);

        vm.expectRevert(
            abi.encodeWithSelector(IMarketErrors.InsufficientSizeToDecrease.selector, 60 * 10 ** 18, 70 * 10 ** 18)
        );
        reader.quoteDecreasePositionToMintPUSD(weth, BOB, 70 * 10 ** 18, 0);
    }

    function test_quoteDecreasePositionToMintPUSD_passIf_sizeIsZero() public {
        deal(address(weth), ALICE, 100 * 10 ** 18);
        vm.prank(ALICE);
        weth.safeTransfer(address(marketManager), 100 * 10 ** 18);
        marketManager.mintLPT(weth, ALICE, ALICE);

        deal(address(weth), BOB, 60 * 10 ** 18);
        vm.prank(BOB);
        weth.safeTransfer(address(marketManager), 60 * 10 ** 18);
        marketManager.increasePosition(weth, BOB, 60 * 10 ** 18);

        IMarketPosition.Position memory position = marketManager.longPositions(weth, BOB);
        (uint96 decreasePositionReceiveAmount, uint64 mintPUSDTokenValue, uint96 marginAfter) = reader
            .quoteDecreasePositionToMintPUSD(weth, BOB, 0, PRICE);

        assertEq(decreasePositionReceiveAmount, 0);
        assertEq(mintPUSDTokenValue, 0);
        assertEq(marginAfter, position.margin);

        position = reader.longPositions(BOB);
        assertEq(0, position.size);

        position = reader.longPositions(address(reader));
        assertEq(0, position.size);
    }

    function test_quoteDecreasePositionToMintPUSD_passIf_partialClose() public {
        deal(address(weth), ALICE, 100 * 10 ** 18);
        vm.prank(ALICE);
        weth.safeTransfer(address(marketManager), 100 * 10 ** 18);
        marketManager.mintLPT(weth, ALICE, ALICE);

        deal(address(weth), BOB, 60 * 10 ** 18);
        vm.prank(BOB);
        weth.safeTransfer(address(marketManager), 60 * 10 ** 18);
        marketManager.increasePosition(weth, BOB, 60 * 10 ** 18);

        (uint96 decreasePositionReceiveAmount, uint64 mintPUSDTokenValue, uint96 marginAfter) = reader
            .quoteDecreasePositionToMintPUSD(weth, BOB, 10 * 10 ** 18, PRICE);

        assertEq(decreasePositionReceiveAmount, 9985399999999999999);
        assertEq(mintPUSDTokenValue, 29833367194);
        assertEq(marginAfter, 49965000000000000000);

        IMarketPosition.Position memory position = reader.longPositions(BOB);
        assertEq(0, position.size);

        position = reader.longPositions(address(reader));
        assertEq(0, position.size);
    }

    function test_quoteDecreasePositionToMintPUSD_passIf_fullyClose() public {
        deal(address(weth), ALICE, 100 * 10 ** 18);
        vm.prank(ALICE);
        weth.safeTransfer(address(marketManager), 100 * 10 ** 18);
        marketManager.mintLPT(weth, ALICE, ALICE);

        deal(address(weth), BOB, 50 * 10 ** 18);
        vm.prank(BOB);
        weth.safeTransfer(address(marketManager), 50 * 10 ** 18);
        marketManager.increasePosition(weth, BOB, 50 * 10 ** 18);

        deal(address(weth), CARRIE, 10 * 10 ** 18);
        vm.prank(CARRIE);
        weth.safeTransfer(address(marketManager), 10 * 10 ** 18);
        marketManager.increasePosition(weth, CARRIE, 10 * 10 ** 18);

        (uint96 decreasePositionReceiveAmount, uint64 mintPUSDTokenValue, uint96 marginAfter) = reader
            .quoteDecreasePositionToMintPUSD(weth, CARRIE, 10 * 10 ** 18, PRICE);

        assertEq(decreasePositionReceiveAmount, 9985399999999999999);
        assertEq(mintPUSDTokenValue, 29833069084);
        assertEq(marginAfter, 0);

        IMarketPosition.Position memory position = reader.longPositions(CARRIE);
        assertEq(0, position.size);

        position = reader.longPositions(address(reader));
        assertEq(0, position.size);
    }

    function test_quoteIncreasePositionBySize_revertIf_marketNotEnabled() public view {
        (bool success, bytes memory returnData) = address(reader).staticcall(
            abi.encodeWithSelector(Reader.quoteIncreasePositionBySize.selector, address(0), address(0), 0, 0, 0)
        );
        assertFalse(success);
        assertTrue(IConfigurable.MarketNotEnabled.selector == abi.decode(returnData, (bytes4)));
    }

    function test_quoteIncreasePositionBySize_passIf_emptyPosition() public {
        deal(address(weth), ALICE, 100 * 10 ** 18);
        vm.prank(ALICE);
        weth.safeTransfer(address(marketManager), 100 * 10 ** 18);
        marketManager.mintLPT(weth, ALICE, ALICE);

        (uint96 payAmount, uint96 marginAfter, uint96 spread, uint96 tradingFee, uint64 liquidationPrice) = reader
            .quoteIncreasePositionBySize(weth, CARRIE, 10 ** 18, 2 * 10 ** 7, PRICE);

        assertEq(payAmount, 500700000000000000);
        assertEq(marginAfter, 500000000000000000);
        assertEq(marginAfter, payAmount - spread - tradingFee);
        assertEq(spread, 0);
        assertEq(tradingFee, 700000000000000);
        assertEq(liquidationPrice, 20093392856789);

        IMarketManager.Position memory position = reader.longPositions(ALICE);
        assertEq(0, position.size);
    }

    function test_quoteIncreasePositionBySize_passIf_positionAlreadyExists() public {
        deal(address(weth), ALICE, 100 * 10 ** 18);
        vm.prank(ALICE);
        weth.safeTransfer(address(marketManager), 100 * 10 ** 18);
        marketManager.mintLPT(weth, ALICE, ALICE);

        deal(address(weth), BOB, 10 * 10 ** 18);
        vm.prank(BOB);
        weth.safeTransfer(address(marketManager), 10 * 10 ** 18);
        marketManager.increasePosition(weth, BOB, 10 * 10 ** 18);

        (uint96 payAmount, uint96 marginAfter, uint96 spread, uint96 tradingFee, uint64 liquidationPrice) = reader
            .quoteIncreasePositionBySize(weth, BOB, 10 ** 18, 2 * 10 ** 7, PRICE);

        assertEq(payAmount, 500700000000000000);
        assertEq(marginAfter, 10493000000000000000);
        assertEq(payAmount - spread - tradingFee, 500000000000000000);
        assertEq(spread, 0);
        assertEq(tradingFee, 700000000000000);
        assertEq(liquidationPrice, 15377691992270);

        IMarketManager.Position memory position = reader.longPositions(BOB);
        assertEq(0, position.size);
    }

    /// @inheritdoc IPUSDManagerCallback
    function PUSDManagerCallback(
        IERC20 payToken,
        uint96 payAmount,
        uint96 /* receiveAmount */,
        bytes calldata /* data */
    ) external override {
        require(msg.sender == address(marketManager));

        deal(address(payToken), address(this), payAmount);
        payToken.safeTransfer(address(marketManager), payAmount);
    }
}
