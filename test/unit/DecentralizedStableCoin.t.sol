// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";

contract DecentralizedStableCoinTest is Test {
    DecentralizedStableCoin dsc;
    address public OWNER = address(this);
    address public USER = address(0xBEEF);

    function setUp() public {
        dsc = new DecentralizedStableCoin();
    }

    function testOwnerCanMint() public {
        bool success = dsc.mint(USER, 100e18);
        assertTrue(success);
        assertEq(dsc.balanceOf(USER), 100e18);
        assertEq(dsc.totalSupply(), 100e18);
    }

    function testMintToZeroAddressReverts() public {
        vm.expectRevert(bytes("DecentralizedStableCoin__MintingToZeroAddress"));
        dsc.mint(address(0), 100e18);
    }

    function testMintZeroAmountReverts() public {
        vm.expectRevert(bytes("DecentralizedStableCoin__AmountMustBeGreaterThanZero"));
        dsc.mint(USER, 0);
    }

    function testNonOwnerCannotMint() public {
        vm.prank(USER);
        vm.expectRevert("Ownable: caller is not the owner");
        dsc.mint(USER, 100e18);
    }

    function testOwnerCanBurn() public {
        dsc.mint(OWNER, 50e18);
        dsc.burn(10e18);
        assertEq(dsc.balanceOf(OWNER), 40e18);
        assertEq(dsc.totalSupply(), 40e18);
    }

    function testBurnMoreThanBalanceReverts() public {
        dsc.mint(OWNER, 1e18);
        vm.expectRevert(DecentralizedStableCoin.DecentralizedStableCoin__BurnAmountExceedsBalance.selector);
        dsc.burn(2e18);
    }

    function testBurnZeroAmountReverts() public {
        dsc.mint(OWNER, 1e18);
        vm.expectRevert(DecentralizedStableCoin.DecentralisedStableCoin__AmountMustBeGreaterThanZero.selector);
        dsc.burn(0);
    }

    function testNonOwnerCannotBurn() public {
        dsc.mint(OWNER, 1e18);
        vm.prank(USER);
        vm.expectRevert("Ownable: caller is not the owner");
        dsc.burn(1e18);
    }
}
