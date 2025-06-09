// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

/* 
 * @title DSCEngine
 * @author Aryan
 * This stablecoin has properties 
 * Exogenous 
 * Dollar Pegged
 * Algorithmic
 * @ notice This contract is based somewhat on the DAI stablecoin.
 * 
 * The system should always be overcollateralized.
 */

contract DSCEngine is ReentrancyGuard {
    error DSCEngine__NeedsMoreThanZero();
    error DSCEninge__TokenAddressAndPriceFeedAddressMustBeSameLength();
    error DSCEngine__TokenNotAllowed();
    error DSCEngine__TransferFailed();
    error DSCEngine__BreaksHealthFactor(uint256 healthFactor);
    error DSCEngine__MintFailed();
    error DSCEngine__HealthFactorOK();
    error DSCEngine__HealthFactorNotImproved();

    uint256 private constant LIQUIDATION_THRESHOLD = 50; // 50% of collateral value
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant MIN_HEALTH_FACTOR = 1;
    uint256 private constant LIQUIDATION_BONUS = 10; // 10% bonus for liquidators
    uint256 private constant LIQUIDATION_BONUS_PRECISION = 100; // 100% precision for bonus calculations–

    // check is token is allowed and give the price feed
    mapping(address token => address priceFeed) private s_priceFeeds;
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;
    mapping(address user => uint256 amountDscMinted) private s_dscMinted;
    address[] private s_collateralTokens;

    DecentralizedStableCoin private immutable i_dsc;

    event CollateralDeposited(
        address indexed user, address indexed tokenCollateralAddress, uint256 indexed amountCollateral
    );
    event CollateralRedeemed(
        address indexed redeemedFrom, address redeemedTo, uint256 amountCollateral, address indexed tokenCollateralAddress
    );

    modifier moreThanZero(uint256 amount) {
        if (amount <= 0) {
            revert DSCEngine__NeedsMoreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address tokenCollateralAddress) {
        if (s_priceFeeds[tokenCollateralAddress] == address(0)) {
            revert DSCEngine__TokenNotAllowed();
        }
        _;
    }

    constructor(address[] memory tokenAddresses, address[] memory priceFeedAddresses, address dscAddress) {
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert DSCEninge__TokenAddressAndPriceFeedAddressMustBeSameLength();
        }
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
            s_collateralTokens.push(tokenAddresses[i]);
        }
        i_dsc = DecentralizedStableCoin(dscAddress);
    }

    function depositCollateralAndMintDsc
    (address tokenCollateralAddress, uint256 amountCollateral, uint256 amountDscToMint) 
    external {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintDsc(amountDscToMint); 
    }

    // @pram tokenCollateralAddress The address of the token to be used as collateral
    function depositCollateral
        (address tokenCollateralAddress, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral) isAllowedToken(tokenCollateralAddress) nonReentrant
    {
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    function redeemCollateralforDsc(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountDscToBurn) external {
        burnDsc(amountDscToBurn);
        redeemCollateral(tokenCollateralAddress, amountCollateral);

    }

    // Health Factor must be greater than 1 after collateral is redeemed
    function redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral) public
        moreThanZero(amountCollateral) nonReentrant(){
        _redeemCollateral(msg.sender, msg.sender, tokenCollateralAddress, amountCollateral);
        _revertIfHealthFactorIsBroken(msg.sender); 
    }

    function mintDsc(uint256 amountDscToMint) public moreThanZero(amountDscToMint) nonReentrant {
        s_dscMinted[msg.sender] += amountDscToMint;
        _revertIfHealthFactorIsBroken(msg.sender);
        bool minted = i_dsc.mint(msg.sender, amountDscToMint);
        if (!minted) {
            revert DSCEngine__MintFailed();
        }
    }

    function burnDsc(uint256 amount) public moreThanZero(amount){
        _burnDsc(amount ,msg.sender, msg.sender );
        _revertIfHealthFactorIsBroken(msg.sender);
        // not really necessary to revert if health factor is broken here, since we are burning Dsc
    }   
    /*
    * @pram collateral The address of the collateral to liquidate from the user
    * @pram user The address of the user to liquidate
    * @pram debtToCover The amount of DSC to burn
    */
    function liquidate(address collateral, address user, uint256 debtToCover) external moreThanZero(debtToCover) nonReentrant(){
        uint256 startingUserHealthFactor = _healthFactor(user);
        if (startingUserHealthFactor >= MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorOK();
        }
        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(collateral, debtToCover);
        // bonus for liquidators to liquidate and sweep extra funds to a storage
        uint256 bonusCollateral = (tokenAmountFromDebtCovered * LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;
        uint256 totalCollateralToRedeem = tokenAmountFromDebtCovered + bonusCollateral;
        _redeemCollateral(user, msg.sender, collateral, totalCollateralToRedeem);
        _burnDsc(debtToCover, user, msg.sender);
        uint256 endingUserHealthFactor = _healthFactor(user);
        if (endingUserHealthFactor <= startingUserHealthFactor){
            revert DSCEngine__HealthFactorNotImproved();
        }
        _revertIfHealthFactorIsBroken(user);
    }

    function _revertIfHealthFactorIsBroken(address user) internal view {
        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__BreaksHealthFactor(userHealthFactor);
        }
    }

    function _healthFactor(address user) internal view returns (uint256) {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = _getAccountInformation(user);
        uint256 collateralAdjustedForThreshold = (collateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        return (collateralAdjustedForThreshold / totalDscMinted);
    }

    // @dev Make sure the function calling this is cheking health factor
    function _burnDsc(uint256 amountDscToBurn,address onBehalfOf, address dscFrom) private{
        s_dscMinted[onBehalfOf] -= amountDscToBurn;
        bool success = i_dsc.transferFrom(dscFrom, address(this), amountDscToBurn);
        if (!success) {
            // If !success then the transfer would automatically revert, so this function is not really necessary
            revert DSCEngine__TransferFailed();
        }
        i_dsc.burn(amountDscToBurn);
    }

    function _redeemCollateral(address from, address to, address tokenCollateralAddress, uint256 amountCollateral)private {
        s_collateralDeposited[from][tokenCollateralAddress] -= amountCollateral;
        emit CollateralRedeemed(from, to, amountCollateral, tokenCollateralAddress); 
        bool success = IERC20(tokenCollateralAddress).transfer(to, amountCollateral);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    function _getAccountInformation(address user)
        private
        view
        returns (uint256 totalDscMinted, uint256 collateralValueInUsd)
    {
        totalDscMinted = s_dscMinted[user];
        collateralValueInUsd = getAccountCollateralValue(user);
    }

    function getTokenAmountFromUsd(address token, uint256 usdAmountInWei) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.latestRoundData();
        // price we will get is in 8 decimals, so we need to convert it to 18 decimals
        return (usdAmountInWei * PRECISION) / (uint256(price) * ADDITIONAL_FEED_PRECISION);
    }

    function getAccountCollateralValue(address user) private view returns (uint256 totalCollateralValueInUsd) {
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[user][token];
            totalCollateralValueInUsd += getUsdValue(token, amount);
        }
    }

    function getUsdValue(address token, uint256 amount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.latestRoundData();
        // price we will get is in 8 decimals, so we need to convert it to 18 decimals
        return ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION;
    }

    function getAccountInformation(address user) external view returns (uint256 totalDscMinted, uint256 collateralValueInUsd){
        (totalDscMinted, collateralValueInUsd) = _getAccountInformation(user);
    }

    function getCollateralTokens() external view returns (address[] memory) {
        return s_collateralTokens;
    }

    function getCollateralTokenPriceFeed(address token) external view returns (address) {
        return s_priceFeeds[token];
    }

    function getCollateralBalanceOfUser(address user, address token) external view returns (uint256) {
        return s_collateralDeposited[user][token];
    }

    function getMinHealthFactor() external pure returns (uint256) {
        return MIN_HEALTH_FACTOR;
    }

    function getAdditionalFeedPrecision() external pure returns (uint256) {
        return ADDITIONAL_FEED_PRECISION;
    }

    function getLiquidationThreshold() external pure returns (uint256) {
        return LIQUIDATION_THRESHOLD;
    }

    function getLiquidationBonus() external pure returns (uint256) {
        return LIQUIDATION_BONUS;
    }

    function getPrecision() external pure returns (uint256) {
        return PRECISION;
    }

    function getDsc() external view returns (address) {
        return address(i_dsc);
    }

    function getHealthFactor(address user) external view returns (uint256) {
        return _healthFactor(user);
    }
}
