// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";

contract DSCEngineTest is Test{
    DeployDSC deployer;
    DecentralizedStableCoin dsc;
    DSCEngine dscE;
    HelperConfig config;
    address ethUsdPriceFeed;
    address weth;
    address public USER = makeAddr("user");
    uint256 public constant AMOUNT_COLLATERAL = 100e18; //100ETH
    uint256 public constant STARTING_ERC20_BALANCE = 1000e18; // 1000 ETH
    
    function setUp() public {
        deployer = new DeployDSC();
        (dscE, dsc, config) = deployer.run();   
        (ethUsdPriceFeed, , weth, , ) = config.activeNetworkConfig(); 
        ERC20Mock(weth).mint(USER, STARTING_ERC20_BALANCE); 
    }

    function testGetUsdValue() public view {
        uint256 ethAmount = 15e18;
        // 15e18 * 2000/ETH = 30,000e18
        uint256 expectedUsdValue = 30_000e18;
        uint256 actualUsdValue = dscE.getUsdValue(weth, ethAmount);
        assertEq(expectedUsdValue, actualUsdValue);

    }

    function testIfCollateralIsZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscE), AMOUNT_COLLATERAL); 

        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dscE.depositCollateral(weth, 0);
        vm.stopPrank();

    }
}