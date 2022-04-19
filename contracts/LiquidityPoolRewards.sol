
// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import "hardhat/console.sol";


contract LiquidityPoolRewards is ReentrancyGuard {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    uint256 public constant OGUN_PRECISION_FACTOR = 10**12;
    uint256 public constant REWARDS_RATE = 20000000000000000000; // 20.0 
    
    IERC20 public immutable OGUNToken;
    IERC20 public immutable lpToken;

    uint256 private _lastUpdatedBlockNumber;
    uint256 public immutable firstBlockNumber;
    uint256 private _totalRewardsSupply;
    uint256 private _totalUsersRewards;
    uint256 private _totalLpStaked;
    uint256 private _totalStakedTemp;

    mapping(address => uint256) private _OGUNrewards;
    mapping(address => uint256) private _lpBalances;
    mapping(address => bool) private _addressInserted;
    address[] private _addresses;

    constructor(address _OGUNToken, address _lpToken, uint256 _rewardsSupply) {
        OGUNToken = IERC20(_OGUNToken);
        lpToken = IERC20(_lpToken);
        _totalRewardsSupply = _rewardsSupply;
        firstBlockNumber = block.number;
    } 

    modifier isValidAccount(address _account) {
        require(_addressInserted[_account], "address hasn't stake any tokens yet");
        _;
    }

    function getUpdatedBalanceOf(address _account) external isValidAccount(_account) returns (uint256, uint256) {
        _updateReward();
        emit RewardsCalculatedOf(_lpBalances[_account], _OGUNrewards[_account], _account);
        return (_lpBalances[_account], _OGUNrewards[_account]);
    }

    function getBalanceOf(address _account) external view isValidAccount(_account) returns (uint256, uint256) {
        return (_lpBalances[_account], _OGUNrewards[_account]);
    }

    function _calculateReward(address _user) private {
        if (_totalRewardsSupply <= 0) {
            return;
        }
        uint256 userLpBalance = _lpBalances[_user];
        if (userLpBalance <= 0) {
            return;
        }
        uint256 blocksToCalculate = block.number - _lastUpdatedBlockNumber;
        //Calculate blocks under 1000000
        if (block.number - firstBlockNumber > 1000000) {
          blocksToCalculate = 1000000 - (_lastUpdatedBlockNumber - firstBlockNumber);
        }

        uint256 rewards = _rewardPerBlock(userLpBalance, REWARDS_RATE, blocksToCalculate);
        _OGUNrewards[_user] += rewards; 
        _totalUsersRewards += rewards;
    }

    function _rewardPerBlock(uint256 _balance, uint256 _rate, uint256 _blocks) private view returns (uint256) {
        uint256 balanceScaled = (_balance.mul(OGUN_PRECISION_FACTOR)).div(_totalLpStaked);
        return (balanceScaled.mul(_rate).div(OGUN_PRECISION_FACTOR)).mul(_blocks);
    }

    function _updateReward() internal {
        if (block.number <= _lastUpdatedBlockNumber) {
            return;
        }
        if (_lastUpdatedBlockNumber == 0) {
          _lastUpdatedBlockNumber = block.number;
          return;
        }

        if (_lastUpdatedBlockNumber - firstBlockNumber > 1000000){
          return;
        }

        if (_totalLpStaked <= 0) {
            return;
        }
        
        for (uint256 i = 0; i < this.getAddressesSize(); i++){
            _calculateReward(_addresses[i]);
        }
        _lastUpdatedBlockNumber = block.number;
        emit RewardsCalculated(_totalLpStaked);
    }

    function updateReward() external {
        _updateReward();
    }

    function stake(uint256 _amount) external nonReentrant {
        require(_amount > 0, "Stake: Amount must be greater than 0");
        require(block.number - firstBlockNumber < 1000000, "This liquidity pool stake has ended. You can withdraw in case of any active balance");
        lpToken.safeTransferFrom(msg.sender, address(this), _amount);
        _updateReward();
        _totalLpStaked += _amount;
        _totalRewardsSupply += _amount;
        _lpBalances[msg.sender] += _amount;
        setAddress(msg.sender);

        emit Stake(msg.sender, _amount);
    }

    function withdraw() external nonReentrant isValidAccount(msg.sender) {
        _updateReward();
        uint256 lpAmount = _lpBalances[msg.sender];
        uint256 rewardsAmount = _OGUNrewards[msg.sender];
        require(lpAmount > 0, "Current balance is 0");

        if (rewardsAmount > _totalRewardsSupply) {
            rewardsAmount = _totalRewardsSupply;
        }

        _lpBalances[msg.sender] = 0;
        _OGUNrewards[msg.sender] = 0;
        _totalLpStaked -= lpAmount;
        _totalRewardsSupply -= rewardsAmount;
        lpToken.safeTransfer(msg.sender, lpAmount);
        OGUNToken.safeTransfer(msg.sender, rewardsAmount);

        emit Withdraw(msg.sender, lpAmount, rewardsAmount);
    }

    function setAddress(address account) internal {

        if (!_addressInserted[account]) {
            _addressInserted[account] = true;
            _addresses.push(account);
        }
    }

    function getAddressesSize() external view returns (uint256) {
        return _addresses.length;
    }

    event Stake(address indexed user, uint256 amount);

    event Withdraw(address indexed user, uint256 lpAmount, uint256 rewardsAmount);

    event RewardsCalculated(uint256 amount);

    event RewardsCalculatedOf(uint256 balance, uint256 rewards,address account);
}
