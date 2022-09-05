
// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import "hardhat/console.sol";

contract TestContract is ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    uint256 private count;
    address private ogunToken;

    constructor(address _ogunToken) {
        count = 0;
        ogunToken = _ogunToken;
    } 

    function withdraw(address destination) external onlyOwner {
      uint256 balance = IERC20(ogunToken).balanceOf(address(this));
      IERC20(ogunToken).transfer(destination, balance);
    }

    function incrementCount() external {
        count += 1;
    }

    function getCount() external view returns (uint256) {
        return count;
    }
}
