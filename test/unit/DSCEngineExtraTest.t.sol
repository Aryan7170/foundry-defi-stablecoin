// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";

contract DSCEngineExtraTest is Test {
    DeployDSC deployer;
    DecentralizedStableCoin dsc;
    DSCEngine dscE;
    HelperConfig config;
    address ethUsdPriceFeed;
    address btcUsdPriceFeed;
    address weth;
    address wbtc;
    address public USER = makeAddr("user");
    uint256 public constant AMOUNT_COLLATERAL = 100e18;
    uint256 public constant STARTING_ERC20_BALANCE = 1000e18;

    function setUp() public {
        deployer = new DeployDSC();
        (dscE, dsc, config) = deployer.run();
        (ethUsdPriceFeed, btcUsdPriceFeed, weth, wbtc, ) = config.activeNetworkConfig();
        ERC20Mock(weth).mint(USER, STARTING_ERC20_BALANCE);
        ERC20Mock(wbtc).mint(USER, STARTING_ERC20_BALANCE);
    }

    function testBurnDscReducesMintedAmount() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscE), AMOUNT_COLLATERAL);
        dscE.depositCollateral(weth, AMOUNT_COLLATERAL);
        dscE.mintDsc(100e18);
        dsc.approve(address(dscE), 50e18);
        dscE.burnDsc(50e18);
        (uint256 minted, ) = dscE.getAccountInformation(USER);
        assertEq(minted, 50e18);
        vm.stopPrank();
    }

    function testGetAccountInformationReturnsCorrectValues() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscE), AMOUNT_COLLATERAL);
        dscE.depositCollateral(weth, AMOUNT_COLLATERAL);
        dscE.mintDsc(10e18);
        (uint256 minted, uint256 collateralValue) = dscE.getAccountInformation(USER);
        assertEq(minted, 10e18);
        assertGt(collateralValue, 0);
        vm.stopPrank();
    }

}
