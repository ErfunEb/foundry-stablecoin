// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {DeployDSC} from "script/DeployDSC.s.sol";
import {DecentralizedStableCoin} from "src/DecentralizedStableCoin.sol";
import {DSCEngine} from "src/DSCEngine.sol";

contract DecentralizedStableCoinTest is Test {
    DeployDSC deployer;
    DecentralizedStableCoin dsc;
    DSCEngine dscEngine;
    address public user = makeAddr("user");

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, dscEngine, ) = deployer.run();
    }

    function testMint() public {
        vm.prank(address(dscEngine));
        dsc.mint(user, 1000);

        assert(dsc.balanceOf(user) == 1000);
    }

    function testMintRevertsNotZeroAddress() public {
        vm.expectRevert(
            DecentralizedStableCoin
                .DecentralizedStableCoin__NotZeroAddress
                .selector
        );
        vm.prank(address(dscEngine));
        dsc.mint(address(0), 1000);
    }

    function testMintRevertsIfAmountIsZero() public {
        vm.expectRevert(
            DecentralizedStableCoin
                .DecentralizedStableCoin__MustBeMoreThanZero
                .selector
        );

        vm.prank(address(dscEngine));
        dsc.mint(user, 0);
    }

    modifier mintedDsc() {
        vm.prank(address(dscEngine));
        dsc.mint(address(dscEngine), 1000);
        _;
    }

    function testBurn() public mintedDsc {
        vm.prank(address(dscEngine));
        dsc.burn(1000);
    }

    function testBurnRevertsIfAmountNotMoreThanZero() public mintedDsc {
        vm.expectRevert(
            DecentralizedStableCoin
                .DecentralizedStableCoin__MustBeMoreThanZero
                .selector
        );

        vm.prank(address(dscEngine));
        dsc.burn(0);
    }

    function testBurnExceedsBalanceReverts() public mintedDsc {
        vm.expectRevert(
            DecentralizedStableCoin
                .DecentralizedStableCoin__BurnAmountExceedsBalance
                .selector
        );

        vm.prank(address(dscEngine));
        dsc.burn(1300);
    }
}
