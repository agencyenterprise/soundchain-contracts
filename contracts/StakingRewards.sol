// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

import "hardhat/console.sol";


contract StakingRewards {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    address public constant REWARDS_TOKEN = 0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512;
    uint256 public constant OGUN_PRECISION_FACTOR = 10**12;
    uint256 public constant REWARDS_PHASE_ONE = 307692308 * OGUN_PRECISION_FACTOR;
    uint256 public constant REWARDS_PHASE_TWO = 128205128 * OGUN_PRECISION_FACTOR; 
    uint256 public constant REWARDS_PHASE_THREE = 480769231 * OGUN_PRECISION_FACTOR; 
    uint256 public constant REWARDS_PHASE_FOUR = 383590836 * OGUN_PRECISION_FACTOR; 
    uint256 public constant PHASE_ONE_BLOCK = 195000; 
    uint256 public constant PHASE_TWO_BLOCK = 585000; 
    uint256 public constant PHASE_THREE_BLOCK = 1560000; 
    uint256 public constant PHASE_FOUR_BLOCK = 2346250; 
    
    IERC20 public stakingToken;

    uint256 public lastUpdateBlockNumber;
    uint256 public immutable firstBlockNumber;
    uint256 private _totalRewardsSupply = 300000000;
    uint256 private _totalStaked;
    uint256 private _totalStakedTemp;


    uint256 public test;

    mapping(address => uint256) public rewards;

    uint256 private _totalSupply;
    mapping(address => uint256) private _balances;
    mapping(address => bool) private _addressInserted;
    address[] private _addresses;

    constructor(address _stakingToken) {
        stakingToken = IERC20(_stakingToken);
        firstBlockNumber = block.number;
        lastUpdateBlockNumber = block.number;
    }

    function getBalanceOf(address account) public returns (uint256) {
        _updateReward();
        return _balances[account];
    }

    function addBlock() external {
        console.log('Current Block number: ', block.number);
        test += 1;
    }

    function _calculateReward(address user) private {
        if (_totalRewardsSupply <= 0) {
            return;
        }
        // check for rewardPhase change between blocks
        uint256 phase = block.number - firstBlockNumber;
        uint256 blocksToCalculate = block.number - lastUpdateBlockNumber;
        (uint256 currentRate,) = _getRewardPhaseRate(phase);
        (uint256 previousPhaseRate, uint256 previousRateLimit) = _getRewardPhaseRate(lastUpdateBlockNumber + 1);
        uint256 userBalance = _balances[user];
        uint256 previousCompound;
        uint256 previousBlocksToCalculate;
        
        //check if last calculated phase + 1's rate is different than current's rate 
        if (currentRate != previousPhaseRate) {
            console.log("Not new user:", userBalance);
            previousBlocksToCalculate = previousRateLimit.sub(lastUpdateBlockNumber);
            previousCompound = _rewardPerBlock(userBalance, previousPhaseRate).mul(previousBlocksToCalculate); 
            blocksToCalculate = block.number.sub(previousRateLimit);
        } 

        uint256 newBalance = _rewardPerBlock(userBalance + previousCompound, currentRate).mul(blocksToCalculate);

        console.log("Rate:", currentRate);
        console.log("blocksToCalculate:", blocksToCalculate);
        console.log("userBalance:", userBalance);
        console.log("New balance:", userBalance + newBalance);
        _balances[user] += newBalance;
        _totalStakedTemp += newBalance;
        
    }

    function _rewardPerBlock(uint256 balance, uint256 rate) private view returns (uint256) {
        return balance.div(_totalStaked).mul(rate);
    }

    function _getRewardPhaseRate(uint256 blockNumber) private pure returns (uint256 rate, uint256 phaseLimit) {
        if (blockNumber <= PHASE_ONE_BLOCK) {
            return (REWARDS_PHASE_ONE, PHASE_ONE_BLOCK);
        }

        if (blockNumber <= PHASE_TWO_BLOCK) {
            return (REWARDS_PHASE_TWO, PHASE_TWO_BLOCK);
        }

        if (blockNumber <= PHASE_THREE_BLOCK) {
            return (REWARDS_PHASE_THREE, PHASE_THREE_BLOCK);
        }

        if (blockNumber <= PHASE_FOUR_BLOCK) {
            return (REWARDS_PHASE_FOUR, PHASE_FOUR_BLOCK);
        }

        return (0, 0);
    }

    function _updateReward() private {
        if (block.number <= lastUpdateBlockNumber) {
            return;
        }
        _totalStakedTemp = 0;
        for (uint256 i = 0; i < this.getAddressesSize(); i++){
            _calculateReward(_addresses[i]);
        }
        lastUpdateBlockNumber = block.number;
        _totalStaked = _totalStakedTemp;
    }

    function stake(uint256 _amount) external {
        require(_amount > 0, "Stake: Amount must be greater than 0");
        console.log('Current Block number: ', block.number);
        stakingToken.safeTransferFrom(msg.sender, address(this), _amount);
        _updateReward();
        _totalStaked += _amount;
        _balances[msg.sender] += _amount;
        setAddress(msg.sender);

        emit Stake(msg.sender, _amount);
    }

    function withdraw() external {
        _updateReward();
        uint256 amount = _balances[msg.sender];
        if (amount == 0) return;
        _balances[msg.sender] = 0;
        _totalStaked -= amount;
        stakingToken.safeTransfer(msg.sender, amount);

        emit Withdraw(msg.sender, amount);
    }

    function setAddress(address _account) internal {

        if (!_addressInserted[_account]) {
            _addressInserted[_account] = true;
            _addresses.push(_account);
        }
    }

    function getAddressesSize() external view returns (uint256) {
        return _addresses.length;
    }

    event Stake(address indexed user, uint256 amount);

    event Withdraw(address indexed user, uint256 amount);
}