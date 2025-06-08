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
    address btcUsdPriceFeed;
    address weth;
    address wbtc;
    address public USER = makeAddr("user");
    uint256 public constant AMOUNT_COLLATERAL = 100e18; //100ETH
    uint256 public constant STARTING_ERC20_BALANCE = 1000e18; // 1000 ETH

    modifier depositedCollateral() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscE), AMOUNT_COLLATERAL);
        dscE.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }
    
    function setUp() public {
        deployer = new DeployDSC(); 
        (dscE, dsc, config) = deployer.run();   
        (ethUsdPriceFeed,btcUsdPriceFeed , weth, wbtc , ) = config.activeNetworkConfig(); 
        ERC20Mock(weth).mint(USER, STARTING_ERC20_BALANCE); 
    }

    // Constructor Tests
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function testRevertsIfTokenLengthDoesNotMatchPriceFeeds() public {
        tokenAddresses.push(weth);
        priceFeedAddresses.push(ethUsdPriceFeed);
        priceFeedAddresses.push(btcUsdPriceFeed);

        vm.expectRevert(DSCEngine.DSCEninge__TokenAddressAndPriceFeedAddressMustBeSameLength.selector);
        new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));

    }



    // Price Feed Tests

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

    function testGetTokenAmountFromUsd() public view{
        uint256 usdAmount = 1000e18; // 1000 USD
        // 1000 USD * 1 ETH/2000 USD = 0.5 ETH
        uint256 expectedTokenAmount = 0.5e18;
        uint256 actualTokenAmount = dscE.getTokenAmountFromUsd(weth, usdAmount);
        assertEq(expectedTokenAmount, actualTokenAmount);

    }

    // Deposit Collateral Tests

    function testRevertsIfCollateralIsZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscE), AMOUNT_COLLATERAL); 

        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dscE.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    function testRevertsIfUnapprovedCollateral() public{
        ERC20Mock randomToken = new ERC20Mock("randomToken", "randomToken", USER, STARTING_ERC20_BALANCE);
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__TokenNotAllowed.selector);
        dscE.depositCollateral(address(randomToken), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    function testCanDepositCollateralAndGetAccountInfo() public depositedCollateral {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dscE.getAccountInformation(USER);
        uint256 expectedTotalDscMinted = 0;
        uint256 expectedDepositAmount = dscE.getTokenAmountFromUsd(weth, collateralValueInUsd);
        assertEq(totalDscMinted, expectedTotalDscMinted);
        assertEq(AMOUNT_COLLATERAL, expectedDepositAmount);
    }
}
