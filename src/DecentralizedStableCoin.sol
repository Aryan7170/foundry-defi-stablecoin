// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {ERC20Burnable, ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/* 
* @title Decentralized Stablecoin
* @notice A simple implementation of a decentralized stablecoin with minting and burning capabilities.
* @author Aryan
* @dev This contract allows users to mint and burn stablecoins, ensuring that the total supply is managed correctly.
* Collateral: Exogenous (ETH or BTC)
* Minting: Alogorithmic
* Relative Stability: Pegged to USD
* This is the contract meant to be governed by DSCEngine. This contract is just a simple ERC20 implementation.
*/

contract DecentralizedStableCoin is ERC20Burnable, Ownable {
    constructor() ERC20("Decentralized Stablecoin", "DSC") {}

    error DecentralisedStableCoin__AmountMustBeGreaterThanZero();
    error DecentralizedStableCoin__BurnAmountExceedsBalance();
    error DecentralizedStableCoin__MintingToZeroAddress();

    function burn(uint256 _amount) public override onlyOwner {
        uint256 balance = balanceOf(msg.sender);
        if (_amount <= 0) {
            revert DecentralisedStableCoin__AmountMustBeGreaterThanZero();
        }
        if (_amount > balance) {
            revert DecentralizedStableCoin__BurnAmountExceedsBalance();
        }
        super.burn(_amount);
    }

    function mint(address _to, uint256 _amount) external onlyOwner returns (bool) {
        if (_to == address(0)) {
            revert("DecentralizedStableCoin__MintingToZeroAddress");
        }
        if (_amount <= 0) {
            revert("DecentralizedStableCoin__AmountMustBeGreaterThanZero");
        }
        _mint(_to, _amount);
        return true;
    }
}
