// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {DeployDSC} from "script/DeployDSC.s.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {DecentralizedStableCoin} from "src/DecentralizedStableCoin.sol";
import {DSCEngine} from "src/DSCEngine.sol";
import {Token} from "src/Token.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";

contract DSCEngineTest is Test {
    DeployDSC deployer;
    DecentralizedStableCoin dsc;
    DSCEngine dscEngine;
    HelperConfig config;
    address ethUsdPriceFeed;
    address btcUsdPriceFeed;
    address weth;
    address public user = makeAddr("user");

    uint256 constant AMOUNT_COLLATERAL = 10 ether;

    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function setUp() public {
        address deployerAddress;
        deployer = new DeployDSC();
        (dsc, dscEngine, config) = deployer.run();
        (ethUsdPriceFeed, btcUsdPriceFeed, weth, , deployerAddress) = config
            .activeNetworkConfig();

        // console.log("WETH: ", weth);

        vm.prank(deployerAddress);
        Token(weth).mint(user, AMOUNT_COLLATERAL);
    }

    function testGetUsdValue() public view {
        uint256 ethAmount = 15e18;
        uint256 expectedUsd = 45000e18;
        uint256 actualUsd = dscEngine.getUsdValue(weth, ethAmount);
        assert(actualUsd == expectedUsd);
    }

    function testRevertsIfCollateralIsZero() public {
        vm.startPrank(user);
        Token(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);

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
        Token someToken = new Token("Some Token", "ST");

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
        assert(totalDscMinted == expectedTotalDscMinted);
        assert(expectedDepositAmount == AMOUNT_COLLATERAL);
    }
}
