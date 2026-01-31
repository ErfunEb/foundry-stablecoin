// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {DeployDSC} from "script/DeployDSC.s.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {DecentralizedStableCoin} from "src/DecentralizedStableCoin.sol";
import {DSCEngine} from "src/DSCEngine.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {ERC20Mock} from "test/mocks/ERC20Mock.sol";
import {MockV3Aggregator} from "test/mocks/MockV3Aggregator.sol";

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

    uint256 constant AMOUNT_COLLATERAL = 10 ether;
    uint256 constant AMOUNT_MINT = 4 ether;
    uint256 constant AMOUNT_REDEEM = 2 ether;

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
        vm.prank(user);
        ERC20Mock someToken = new ERC20Mock("Some Token", "ST");

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

        (uint256 totalDscMinted, uint256 usdValue) = dscEngine
            .getAccountInformation(user);
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
            20 ether, // 10 ether worth of $30,000
            20000 ether
        );
        vm.stopPrank();
        _;
    }

    function testLiquidateWorksAsExpected() public canBeLiquidated {
        uint256 liquidatorStartingWETHBalance = ERC20Mock(weth).balanceOf(
            liquidator
        );
        uint256 liquidatorStartingBalance = dsc.balanceOf(liquidator);
        MockV3Aggregator(ethUsdPriceFeed).setPriceData(2800); // $200 price drop
        (uint256 totalDscMinted, uint256 usdValue) = dscEngine
            .getAccountInformation(user);

        uint256 userStartingHealthFactor = dscEngine.getHealthFactor(user);

        vm.startPrank(liquidator);
        dsc.approve(address(dscEngine), 150000 ether);
        dscEngine.liquidate(weth, user, 4000 ether);
        vm.stopPrank();
        uint256 userEndingHealthFactor = dscEngine.getHealthFactor(user);
        uint256 liquidatorHealthFactor = dscEngine.getHealthFactor(liquidator);

        assert(userEndingHealthFactor >= userStartingHealthFactor);
        assert(liquidatorHealthFactor > 1e18);

        uint256 userCollateralValue = dscEngine.getAccountCollateralValue(user);
        uint256 redeemCollateralValue = (dscEngine.getTokenAmountFromUsd(
            weth,
            4000 ether
        ) * 110) / 100;
        uint256 userCollateralAmount = 10 ether - redeemCollateralValue;

        uint256 expectedCollateralValue = dscEngine.getUsdValue(
            weth,
            userCollateralAmount
        );

        uint256 liquidatorBalance = dsc.balanceOf(liquidator);

        assert(liquidatorBalance == liquidatorStartingBalance - 4000 ether);
        assert(userCollateralValue == expectedCollateralValue);

        uint256 liquidatorCollateralAmount = ERC20Mock(weth).balanceOf(
            liquidator
        );

        assert(
            liquidatorCollateralAmount ==
                liquidatorCollateralAmount - liquidatorStartingWETHBalance
        );

        // assert user total dsc token
    }

    function testLiquidateRevertsIfHealthFactorNotImproved()
        public
        canBeLiquidated
    {
        MockV3Aggregator(ethUsdPriceFeed).setPriceData(1500);
        vm.startPrank(liquidator);
        dsc.approve(address(dscEngine), 150000 ether);
        vm.expectRevert(
            DSCEngine.DSCEngine__HealthFactorNotImprovemed.selector
        );
        dscEngine.liquidate(weth, user, 9000 ether);
        vm.stopPrank();
    }

    function testLiquidateMoreThanZero() public canBeLiquidated {
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        vm.prank(liquidator);
        dscEngine.liquidate(weth, user, 0);
    }

    function testLiquidateHealthFactorOkReverts() public canBeLiquidated {
        vm.expectRevert(DSCEngine.DSCEngine__HealthFactorOk.selector);
        vm.prank(liquidator);
        dscEngine.liquidate(weth, user, 5000);
    }

    function testLiquidateRevertsIfHealthFactorIsBroken()
        public
        canBeLiquidated
    {
        MockV3Aggregator(ethUsdPriceFeed).setPriceData(1800);
        vm.startPrank(liquidator);
        dsc.approve(address(dscEngine), 150000 ether);
        vm.expectRevert(DSCEngine.DSCEngine__BreaksHealthFactor.selector);
        dscEngine.liquidate(weth, user, 10001 ether);
        vm.stopPrank();
    }

    // function testDepositCollateralEmitsEvent() public {} Event name: CollateralDeposited
    // function testRedeemCollateralEmitsAnEvent() {}
}
