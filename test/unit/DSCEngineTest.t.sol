// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {DeployDSC} from "script/DeployDSC.s.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {DecentralizedStableCoin} from "src/DecentralizedStableCoin.sol";
import {DSCEngine} from "src/DSCEngine.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {ERC20Mock} from "test/mocks/ERC20Mock.sol";
import {MockV3Aggregator} from "test/mocks/MockV3Aggregator.sol";
import {OracleLib} from "src/libraries/OracleLib.sol";

contract DSCEngineTest is Test {
    DeployDSC deployer;
    DecentralizedStableCoin dsc;
    DSCEngine dscEngine;
    HelperConfig config;
    address ethUsdPriceFeed;
    address btcUsdPriceFeed;
    address weth;
    address public user = makeAddr("user");
    address liquidator = makeAddr("liquidator");
    address liquidator2 = makeAddr("liquidator2");
    ERC20Mock someToken;

    uint256 constant AMOUNT_COLLATERAL = 10 ether;
    uint256 constant AMOUNT_MINT = 4 ether;
    uint256 constant AMOUNT_REDEEM = 2 ether;
    uint256 constant AMOUNT_LIQUIDATE = 4000 ether; // 4,000 DSC
    uint256 constant PERCENTAGE_PRECISION = 100;
    uint256 constant PRICE_DECIMALS = 8;
    uint256 constant DECIMALS_PRECISION = 1e18;

    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function setUp() public {
        address deployerAddress;
        deployer = new DeployDSC();
        (dsc, dscEngine, config) = deployer.run();
        (ethUsdPriceFeed, btcUsdPriceFeed, weth, , deployerAddress) = config
            .activeNetworkConfig();

        vm.prank(deployerAddress);
        ERC20Mock(weth).mint(user, AMOUNT_COLLATERAL);

        vm.prank(user);
        someToken = new ERC20Mock("Some Token", "ST");
    }

    function testGetUsdValue() public view {
        uint256 ethAmount = 15e18;
        uint256 expectedUsd = 45000e18;
        uint256 actualUsd = dscEngine.getUsdValue(weth, ethAmount);
        assert(actualUsd == expectedUsd);
    }

    function testRevertsIfCollateralIsZero() public {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);

        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dscEngine.depositCollateral(weth, 0);
    }

    function testRevertsIfTokenLengthDoesntMatchPriceFeeds() public {
        tokenAddresses.push(weth);
        priceFeedAddresses.push(ethUsdPriceFeed);
        priceFeedAddresses.push(btcUsdPriceFeed);

        vm.expectRevert(
            DSCEngine
                .DSCEngine__TokenAddressesPriceFeedAndAddressesMustBeSameLength
                .selector
        );
        new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
    }

    function testGetTokenAmountFromUsd() public view {
        uint256 usdAmount = 150 ether;
        uint256 expectedWeth = 0.05 ether;

        uint256 actualWeth = dscEngine.getTokenAmountFromUsd(weth, usdAmount);
        assert(actualWeth == expectedWeth);
    }

    function testRevertsWithUnapprovedCollateral() public {
        vm.startPrank(user);
        vm.expectRevert(DSCEngine.DSCEngine__NotAllowedToken.selector);
        dscEngine.depositCollateral(address(someToken), 100);
    }

    modifier depositedCollateral() {
        vm.startPrank(user);
        IERC20(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);
        dscEngine.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    function testCanDepositCollateralAndGetAccountInfo()
        public
        depositedCollateral
    {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dscEngine
            .getAccountInformation(user);
        uint256 expectedTotalDscMinted = 0;
        uint256 expectedDepositAmount = dscEngine.getTokenAmountFromUsd(
            address(weth),
            collateralValueInUsd
        );

        uint256 collateralAmount = dscEngine.getCollateralBalanceOfUser(
            user,
            weth
        );

        assert(collateralAmount == AMOUNT_COLLATERAL);
        assert(totalDscMinted == expectedTotalDscMinted);
        assert(expectedDepositAmount == AMOUNT_COLLATERAL);
    }

    function testDepositAndMint() public depositedCollateral {
        vm.prank(user);
        dscEngine.mintDsc(AMOUNT_MINT);

        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dscEngine
            .getAccountInformation(user);
        uint256 expectedDepositAmount = dscEngine.getTokenAmountFromUsd(
            address(weth),
            collateralValueInUsd
        );

        assert(expectedDepositAmount == AMOUNT_COLLATERAL);
        assert(totalDscMinted == AMOUNT_MINT);
    }

    function testDepositAndMintRevertsBreakingHealthFactor()
        public
        depositedCollateral
    {
        (, uint256 usdValue) = dscEngine.getAccountInformation(user);
        vm.expectRevert(DSCEngine.DSCEngine__BreaksHealthFactor.selector);
        vm.prank(user);
        dscEngine.mintDsc(usdValue / 2 + 1); // well above the 50% threshold
    }

    modifier depositAndMint() {
        vm.startPrank(user);
        IERC20(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);
        dscEngine.depositCollateralAndMintDsc(
            weth,
            AMOUNT_COLLATERAL,
            AMOUNT_MINT
        );
        vm.stopPrank();
        _;
    }

    function testdepositCollateralAndMintDscFunction() public depositAndMint {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dscEngine
            .getAccountInformation(user);
        uint256 expectedDepositAmount = dscEngine.getTokenAmountFromUsd(
            address(weth),
            collateralValueInUsd
        );

        assert(expectedDepositAmount == AMOUNT_COLLATERAL);
        assert(totalDscMinted == AMOUNT_MINT);
    }

    function testRedeemCollateralShouldBeMoreThanZero()
        public
        depositedCollateral
    {
        vm.prank(user);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dscEngine.redeemCollateral(weth, 0);
    }

    function testRedeemCollateral() public depositedCollateral {
        vm.prank(user);
        dscEngine.redeemCollateral(weth, AMOUNT_REDEEM);

        (uint256 totalDscMinted, ) = dscEngine.getAccountInformation(user);
        uint256 collateralAmount = dscEngine.getCollateralBalanceOfUser(
            user,
            weth
        );

        assert(collateralAmount == AMOUNT_COLLATERAL - AMOUNT_REDEEM);
        assert(totalDscMinted == 0);
    }

    function testRedeemCollateralBreaksHealthFactor()
        public
        depositedCollateral
    {
        (, uint256 usdValue) = dscEngine.getAccountInformation(user);
        vm.startPrank(user);
        dscEngine.mintDsc(usdValue / 2);
        vm.expectRevert(DSCEngine.DSCEngine__BreaksHealthFactor.selector);
        dscEngine.redeemCollateral(weth, AMOUNT_REDEEM);
        vm.stopPrank();
    }

    function testBurnDscShouldRevertIfThereIsNoBalance() public {
        vm.expectRevert(DSCEngine.DSCEngine__BurnBalanceOverflow.selector);
        vm.prank(user);
        dscEngine.burnDsc(AMOUNT_MINT);
    }

    function testBurnDsc() public depositAndMint {
        vm.startPrank(user);
        dsc.approve(address(dscEngine), AMOUNT_MINT);
        dscEngine.burnDsc(AMOUNT_MINT);
        vm.stopPrank();

        assert(dsc.balanceOf(user) == 0);
    }

    function testPartialBurnDsc() public depositAndMint {
        vm.startPrank(user);
        dsc.approve(address(dscEngine), AMOUNT_MINT);
        dscEngine.burnDsc(AMOUNT_MINT / 2);
        vm.stopPrank();

        assert(dsc.balanceOf(user) == AMOUNT_MINT / 2);
    }

    function testRedeemCollateralAndBurnDscFunction() public depositAndMint {
        vm.startPrank(user);
        dsc.approve(address(dscEngine), AMOUNT_MINT);
        dscEngine.redeemCollateralForDsc(weth, AMOUNT_COLLATERAL, AMOUNT_MINT);
        vm.stopPrank();

        (uint256 totalDscMinted, ) = dscEngine.getAccountInformation(user);
        uint256 collateralAmount = dscEngine.getCollateralBalanceOfUser(
            user,
            weth
        );

        assert(dsc.balanceOf(user) == 0);
        assert(totalDscMinted == 0);
        assert(collateralAmount == 0);
    }

    modifier canBeLiquidated() {
        vm.startPrank(user);
        IERC20(weth).approve(address(dscEngine), 10 ether);
        dscEngine.depositCollateralAndMintDsc(
            weth,
            10 ether, // 10 ether worth of $30,000
            15000 ether
        );
        vm.stopPrank();

        ERC20Mock(weth).mint(liquidator, 20 ether);
        vm.startPrank(liquidator);
        IERC20(weth).approve(address(dscEngine), 20 ether);
        dscEngine.depositCollateralAndMintDsc(
            weth,
            20 ether, // 20 ether worth of $60,000
            25000 ether
        );
        bool success = dsc.transfer(liquidator2, AMOUNT_LIQUIDATE);
        require(success, "Transfer failed");
        vm.stopPrank();
        _;
    }

    function testLiquidateWorksAsExpected() public canBeLiquidated {
        uint256 liquidatorStartingWethBalance = ERC20Mock(weth).balanceOf(
            liquidator
        );
        uint256 liquidatorStartingBalance = dsc.balanceOf(liquidator);
        MockV3Aggregator(ethUsdPriceFeed).setPriceData(2800); // $200 price drop

        uint256 userStartingHealthFactor = dscEngine.getHealthFactor(user);

        vm.startPrank(liquidator);
        dsc.approve(address(dscEngine), type(uint256).max);
        dscEngine.liquidate(weth, user, AMOUNT_LIQUIDATE);
        vm.stopPrank();
        uint256 userEndingHealthFactor = dscEngine.getHealthFactor(user);
        uint256 liquidatorHealthFactor = dscEngine.getHealthFactor(liquidator);

        assert(userEndingHealthFactor >= userStartingHealthFactor);
        assert(liquidatorHealthFactor > 1e18);

        uint256 userCollateralValue = dscEngine.getAccountCollateralValue(user);
        uint256 redeemCollateralValue = (dscEngine.getTokenAmountFromUsd(
            weth,
            AMOUNT_LIQUIDATE
        ) * 110) / PERCENTAGE_PRECISION;
        uint256 userCollateralAmount = 10 ether - redeemCollateralValue;

        uint256 expectedCollateralValue = dscEngine.getUsdValue(
            weth,
            userCollateralAmount
        );

        uint256 liquidatorBalance = dsc.balanceOf(liquidator);

        assert(
            liquidatorBalance == liquidatorStartingBalance - AMOUNT_LIQUIDATE
        );
        assert(userCollateralValue == expectedCollateralValue);

        uint256 liquidatorCollateralAmount = ERC20Mock(weth).balanceOf(
            liquidator
        );

        assert(
            liquidatorCollateralAmount ==
                liquidatorStartingWethBalance + redeemCollateralValue
        );
    }

    function testLiquidateMoreThanZero() public canBeLiquidated {
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        vm.prank(liquidator);
        dscEngine.liquidate(weth, user, 0);
    }

    function testLiquidateHealthFactorOkReverts() public canBeLiquidated {
        vm.expectRevert(DSCEngine.DSCEngine__HealthFactorOk.selector);
        vm.prank(liquidator);
        dscEngine.liquidate(weth, user, AMOUNT_LIQUIDATE);
    }

    function testLiquidateWithNormalUser() public canBeLiquidated {
        MockV3Aggregator(ethUsdPriceFeed).setPriceData(2800);

        vm.assume(IERC20(weth).balanceOf(liquidator2) == 0);
        vm.startPrank(liquidator2);
        dsc.approve(address(dscEngine), type(uint256).max);
        dscEngine.liquidate(weth, user, AMOUNT_LIQUIDATE);
        vm.stopPrank();

        assertEq(dsc.balanceOf(liquidator2), 0); // AMOUNT_LIQUIDATE all covered for debt
        assert(IERC20(weth).balanceOf(liquidator2) > 0);
    }

    function testDepositCollateralEmitsEvent() public {
        vm.startPrank(user);
        IERC20(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);

        vm.recordLogs();

        dscEngine.depositCollateral(weth, AMOUNT_COLLATERAL);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        vm.stopPrank();

        Vm.Log memory log = logs[0];
        assert(log.emitter == address(dscEngine));

        bytes32 expectedSignature = keccak256(
            "CollateralDeposited(address,address,uint256)"
        );
        assertEq(log.topics[0], expectedSignature);
        assertEq(log.topics[1], bytes32(uint256(uint160(address(user)))));
        assert(log.topics[2] == bytes32(uint256(uint160(address(weth)))));

        uint256 amount = abi.decode(log.data, (uint256));
        assert(amount == AMOUNT_COLLATERAL);
    }

    function testRedeemCollateralEmitsAnEvent() public depositedCollateral {
        vm.recordLogs();

        vm.prank(user);
        dscEngine.redeemCollateral(weth, AMOUNT_REDEEM);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        Vm.Log memory log = logs[0];
        assert(log.emitter == address(dscEngine));

        bytes32 expectedSignature = keccak256(
            "CollateralRedeemed(address,address,address,uint256)"
        );

        assertEq(log.topics[0], expectedSignature);
        assertEq(log.topics[1], bytes32(uint256(uint160(address(user)))));
        assertEq(log.topics[2], bytes32(uint256(uint160(address(user)))));
        assertEq(log.topics[3], bytes32(uint256(uint160(address(weth)))));

        uint256 amount = abi.decode(log.data, (uint256));
        assert(amount == AMOUNT_REDEEM);
    }

    function testLiquidationEmitsAnEvent() public canBeLiquidated {
        MockV3Aggregator(ethUsdPriceFeed).setPriceData(2800);

        vm.startPrank(liquidator2);
        dsc.approve(address(dscEngine), type(uint256).max);
        vm.recordLogs();
        dscEngine.liquidate(weth, user, AMOUNT_LIQUIDATE);
        vm.stopPrank();

        Vm.Log[] memory logs = vm.getRecordedLogs();

        Vm.Log memory log = logs[4];
        assert(log.emitter == address(dscEngine));

        bytes32 expectedSignature = keccak256(
            "Liquidation(address,address,address,uint256,uint256)"
        );

        assertEq(log.topics[0], expectedSignature);
        assertEq(
            log.topics[1],
            bytes32(uint256(uint160(address(liquidator2))))
        );
        assertEq(log.topics[2], bytes32(uint256(uint160(address(user)))));

        (
            address collateral,
            uint256 debtCovered,
            uint256 collateralAmount
        ) = abi.decode(log.data, (address, uint256, uint256));

        assert(collateral == weth);
        assert(debtCovered == AMOUNT_LIQUIDATE);
        assert(collateralAmount == IERC20(weth).balanceOf(liquidator2));
    }

    function testBurnRevertsIfAmountExceedsBalance() public depositAndMint {
        vm.startPrank(user);
        dsc.approve(address(dscEngine), AMOUNT_MINT);
        vm.expectRevert(DSCEngine.DSCEngine__BurnBalanceOverflow.selector);
        dscEngine.burnDsc(AMOUNT_MINT + 1);
        vm.stopPrank();
    }

    function testRedeemCollateralRevertsBalanceOverflow()
        public
        depositAndMint
    {
        vm.startPrank(user);
        dsc.approve(address(dscEngine), AMOUNT_MINT);
        dscEngine.burnDsc(AMOUNT_MINT);
        vm.expectRevert(
            DSCEngine.DSCEngine__CollateralBalanceOverflow.selector
        );
        dscEngine.redeemCollateral(weth, AMOUNT_COLLATERAL + 1);
        vm.stopPrank();
    }

    function testHealthFactorGetter() public view {
        uint256 minHealthFactor = dscEngine.getMinHealthFactor();

        assert(minHealthFactor > 0);
    }

    function testGetTokenPriceFeedGetter() public view {
        MockV3Aggregator wethPriceFeed = MockV3Aggregator(
            dscEngine.getTokenPriceFeed(weth)
        );

        assert(wethPriceFeed.decimals() == PRICE_DECIMALS);
    }

    function testNotAllowedTokenOnRedeemCollateral()
        public
        depositedCollateral
    {
        vm.prank(user);
        vm.expectRevert(DSCEngine.DSCEngine__NotAllowedToken.selector);
        dscEngine.redeemCollateral(address(someToken), AMOUNT_REDEEM);
    }

    function testRevertsWithUnapprovedCollateralOnRedeemCollateralForDsc()
        public
        depositAndMint
    {
        vm.startPrank(user);
        dsc.approve(address(dscEngine), AMOUNT_MINT);

        vm.expectRevert(DSCEngine.DSCEngine__NotAllowedToken.selector);
        dscEngine.redeemCollateralForDsc(
            address(someToken),
            AMOUNT_REDEEM,
            AMOUNT_MINT / 2
        );

        vm.stopPrank();
    }

    function testRevertsWithUnapprovedCollateralOnLiquidate()
        public
        canBeLiquidated
    {
        MockV3Aggregator(ethUsdPriceFeed).setPriceData(2800); // $200 price drop

        vm.startPrank(liquidator2);
        dsc.approve(address(dscEngine), type(uint256).max);

        vm.expectRevert(DSCEngine.DSCEngine__NotAllowedToken.selector);
        dscEngine.liquidate(address(someToken), user, AMOUNT_LIQUIDATE);

        vm.stopPrank();
    }

    function testRevertsWithUnapprovedCollateralOnDepositCollateralAndMintDsc()
        public
    {
        vm.startPrank(user);
        IERC20(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);

        vm.expectRevert(DSCEngine.DSCEngine__NotAllowedToken.selector);
        dscEngine.depositCollateralAndMintDsc(
            address(someToken),
            AMOUNT_COLLATERAL,
            AMOUNT_MINT
        );

        vm.stopPrank();
    }

    function testOracleLibRevertsZeroPrice(uint256 amount) public {
        amount = bound(amount, 1, type(uint96).max);
        MockV3Aggregator(ethUsdPriceFeed).setPriceData(0);
        vm.expectRevert(OracleLib.OracleLib__InvalidPrice.selector);
        dscEngine.getTokenAmountFromUsd(weth, amount);
    }

    function testOracleLibRevertsStalePrice(uint256 amount) public {
        amount = bound(amount, 1, type(uint96).max);
        vm.warp(5 hours);
        MockV3Aggregator(ethUsdPriceFeed).setUpdatedAt(1 hours);
        vm.expectRevert(OracleLib.OracleLib__StalePrice.selector);
        dscEngine.getTokenAmountFromUsd(weth, amount);
    }
}
