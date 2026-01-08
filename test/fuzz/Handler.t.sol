// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {DSCEngine} from "src/DSCEngine.sol";
import {DecentralizedStableCoin} from "src/DecentralizedStableCoin.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {ERC20Mock} from "test/mocks/ERC20Mock.sol";

contract Handler is Test {
    DecentralizedStableCoin dsc;
    DSCEngine dscEngine;

    uint256 constant MAX_DEPOSIT_SIZE = type(uint96).max;
    address[] public collateralUsersDeposited;

    constructor(DSCEngine _dscEngine, DecentralizedStableCoin _dsc) {
        dsc = _dsc;
        dscEngine = _dscEngine;
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

    function mintDsc(uint256 amount, uint256 accountSeed) public {
        if (collateralUsersDeposited.length == 0) {
            return;
        }

        uint256 userIndex = accountSeed % collateralUsersDeposited.length;
        address user = collateralUsersDeposited[userIndex];

        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dscEngine
            .getAccountInformation(user);
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 maxDscToMint = (int256(collateralValueInUsd) / 2) -
            // forge-lint: disable-next-line(unsafe-typecast)
            int256(totalDscMinted);

        if (maxDscToMint <= 0) {
            return;
        }
        // forge-lint: disable-next-line(unsafe-typecast)
        amount = bound(amount, 1, uint256(maxDscToMint));
        vm.prank(user);
        dscEngine.mintDsc(amount);
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

        uint256 healthFactor = dscEngine.getHealthFactor(msg.sender);

        vm.startPrank(msg.sender);
        if (healthFactor < dscEngine.MIN_HEALTH_FACTOR()) {
            vm.expectRevert(DSCEngine.DSCEngine__BreaksHealthFactor.selector);
        }
        dscEngine.redeemCollateral(collateral, amountCollateral);
        vm.stopPrank();
    }
}
