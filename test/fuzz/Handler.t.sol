// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {DSCEngine} from "src/DSCEngine.sol";
import {DecentralizedStableCoin} from "src/DecentralizedStableCoin.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {ERC20Mock} from "test/mocks/ERC20Mock.sol";
import {MockV3Aggregator} from "test/mocks/MockV3Aggregator.sol";

contract Handler is Test {
    DecentralizedStableCoin dsc;
    DSCEngine dscEngine;
    address liquidator = makeAddr("liquidator");
    uint256 constant PRICE_DROP = 5;
    uint256 constant PERCENTAGE_PRECISION = 100;
    uint256 constant PRICE_DECIMALS = 1e8;
    uint256 constant DECIMALS_PRECISION = 1e18;
    uint256 immutable LIQUIDATION_BONUS;
    uint256 immutable LIQUIDATE_THRESHOLD;

    uint256 constant MAX_DEPOSIT_SIZE = type(uint96).max;
    address[] public collateralUsersDeposited;

    constructor(DSCEngine _dscEngine, DecentralizedStableCoin _dsc) {
        dsc = _dsc;
        dscEngine = _dscEngine;
        LIQUIDATION_BONUS = dscEngine.getLiquidationBonus();
        LIQUIDATE_THRESHOLD = dscEngine.getLiquidateThreshold();
    }

    function depositCollateral(
        uint256 collateralSeed,
        uint256 amountCollateral
    ) public {
        address collateral = _getCollateralFromSeed(collateralSeed);
        amountCollateral = bound(amountCollateral, 1, MAX_DEPOSIT_SIZE);
        vm.startPrank(msg.sender);
        ERC20Mock(collateral).mint(msg.sender, amountCollateral);
        IERC20(collateral).approve(address(dscEngine), amountCollateral);
        dscEngine.depositCollateral(collateral, amountCollateral);
        vm.stopPrank();

        collateralUsersDeposited.push(msg.sender);
    }

    function _getCollateralFromSeed(
        uint256 collateralSeed
    ) private view returns (address) {
        address[] memory collateralTokens = dscEngine.getCollateralTokens();
        uint256 randomIndex = collateralSeed % collateralTokens.length;
        return collateralTokens[randomIndex];
    }

    function _priceDecrease(address collateral) private {
        address priceFeed = dscEngine.getTokenPriceFeed(collateral);
        (, int256 currentPrice, , , ) = MockV3Aggregator(priceFeed)
            .latestRoundData();

        MockV3Aggregator(priceFeed).setPriceData(
            // forge-lint: disable-next-line(unsafe-typecast)
            (uint256(currentPrice) * (PERCENTAGE_PRECISION - PRICE_DROP)) /
                (PERCENTAGE_PRECISION * PRICE_DECIMALS)
        );
    }

    function mintDsc(uint256 amount, uint256 accountSeed) public {
        if (collateralUsersDeposited.length == 0) {
            return;
        }

        uint256 userIndex = accountSeed % collateralUsersDeposited.length;
        address user = collateralUsersDeposited[userIndex];

        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dscEngine
            .getAccountInformation(user);
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 maxDscToMint = ((int256(collateralValueInUsd) *
            // forge-lint: disable-next-line(unsafe-typecast)
            int256(LIQUIDATE_THRESHOLD)) / int256(PERCENTAGE_PRECISION)) -
            // forge-lint: disable-next-line(unsafe-typecast)
            int256(totalDscMinted);

        if (maxDscToMint <= 0) {
            return;
        }
        // forge-lint: disable-next-line(unsafe-typecast)
        amount = bound(amount, 1, uint256(maxDscToMint));
        vm.startPrank(user);
        dscEngine.mintDsc(amount);
        vm.stopPrank();
    }

    function redeemCollateral(
        uint256 collateralSeed,
        uint256 amountCollateral
    ) public {
        address collateral = _getCollateralFromSeed(collateralSeed);
        uint256 maxCollateralToRedeem = dscEngine.getCollateralBalanceOfUser(
            msg.sender,
            collateral
        );
        amountCollateral = bound(amountCollateral, 0, maxCollateralToRedeem);
        if (amountCollateral == 0) {
            return;
        }

        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dscEngine
            .getAccountInformation(msg.sender);

        uint256 collateralValueAfterRedeem = collateralValueInUsd -
            dscEngine.getUsdValue(collateral, amountCollateral);

        uint256 expectedHealthFactor;
        if (totalDscMinted == 0) {
            expectedHealthFactor = type(uint256).max;
        } else {
            expectedHealthFactor =
                (collateralValueAfterRedeem *
                    LIQUIDATE_THRESHOLD *
                    DECIMALS_PRECISION) /
                (totalDscMinted * PERCENTAGE_PRECISION);
        }

        uint256 minHealthFactor = dscEngine.getMinHealthFactor();

        vm.startPrank(msg.sender);
        if (expectedHealthFactor < minHealthFactor) {
            vm.expectRevert(DSCEngine.DSCEngine__BreaksHealthFactor.selector);
        }
        dscEngine.redeemCollateral(collateral, amountCollateral);
        vm.stopPrank();
    }

    function burnDsc(uint256 accountSeed, uint256 burnAmount) public {
        if (collateralUsersDeposited.length == 0) {
            return;
        }

        uint256 userIndex = accountSeed % collateralUsersDeposited.length;
        address user = collateralUsersDeposited[userIndex];

        (uint256 totalDscMinted, ) = dscEngine.getAccountInformation(user);
        uint256 dscBalance = dsc.balanceOf(user);

        if (totalDscMinted == 0 || dscBalance == 0) {
            return;
        }

        burnAmount = bound(burnAmount, 1, totalDscMinted);

        vm.startPrank(user);
        dsc.approve(address(dscEngine), type(uint256).max);
        if (burnAmount == 0) {
            vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        }
        dscEngine.burnDsc(burnAmount);
        vm.stopPrank();
    }

    function liquidate(uint256 collateralSeed, uint256 debtToCover) public {
        address collateral = _getCollateralFromSeed(collateralSeed);
        _priceDecrease(collateral);

        for (uint256 i = 0; i < collateralUsersDeposited.length; i++) {
            address user = collateralUsersDeposited[i];
            uint256 hf = dscEngine.getHealthFactor(user);
            uint256 balance = dscEngine.getCollateralBalanceOfUser(
                user,
                collateral
            );

            if (balance == 0 || hf >= dscEngine.getMinHealthFactor()) {
                continue;
            }

            (uint256 totalDscMinted, uint256 collateralValueInUsd) = dscEngine
                .getAccountInformation(user);

            uint256 maxDscAmount = collateralValueInUsd / 2;
            uint256 maxDebtToCover = totalDscMinted - maxDscAmount;
            debtToCover = bound(debtToCover, 1, maxDebtToCover);

            uint256 collateralAmount = dscEngine.getTokenAmountFromUsd(
                collateral,
                debtToCover
            );

            uint256 collateralAmountWithBonus = (collateralAmount *
                (PERCENTAGE_PRECISION + LIQUIDATION_BONUS)) /
                PERCENTAGE_PRECISION;
            if (collateralAmountWithBonus > balance) {
                continue;
            }

            if (balance < collateralAmount || maxDebtToCover == 0) {
                continue;
            }

            vm.startPrank(liquidator);
            ERC20Mock(collateral).mint(liquidator, type(uint128).max);
            dsc.approve(address(dscEngine), type(uint256).max);
            IERC20(collateral).approve(address(dscEngine), type(uint256).max);
            dscEngine.depositCollateral(collateral, type(uint128).max);
            dscEngine.mintDsc(debtToCover);
            dscEngine.liquidate(collateral, user, debtToCover);
            vm.stopPrank();
        }
    }
}
