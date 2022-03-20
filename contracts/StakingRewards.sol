// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

import "hardhat/console.sol";


contract StakingRewards {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    address public constant REWARDS_TOKEN = 0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512;
    // uint256 public constant OGUN_PRECISION_FACTOR = 10**12;
    uint256 public constant REWARDS_PHASE_ONE = 307692308000000000000;
    uint256 public constant REWARDS_PHASE_TWO = 128205128000000000000; 
    uint256 public constant REWARDS_PHASE_THREE = 48076923100000000000; 
    uint256 public constant REWARDS_PHASE_FOUR = 38359083600000000000; 
    uint256 public constant PHASE_ONE_BLOCK = 195000; 
    uint256 public constant PHASE_TWO_BLOCK = 585000; 
    uint256 public constant PHASE_THREE_BLOCK = 1560000; 
    uint256 public constant PHASE_FOUR_BLOCK = 2346250; 
    
    IERC20 public immutable stakingToken;

    uint256 public lastUpdateBlockNumber;
    uint256 public immutable firstBlockNumber;
    uint256 private _totalRewardsSupply;
    uint256 private _totalStaked;
    uint256 private _totalStakedTemp;

    // mapping(address => uint256) public rewards;

    uint256 private _totalSupply;
    mapping(address => uint256) private _balances;
    mapping(address => bool) private _addressInserted;
    address[] private _addresses;

    constructor(address _stakingToken, uint256 rawardsSupply) {
        stakingToken = IERC20(_stakingToken);
        _totalRewardsSupply = rawardsSupply;
        firstBlockNumber = block.number;
        lastUpdateBlockNumber = block.number;
    }

    modifier isValidAccount(address account) {
        require(_addressInserted[account], "address hasn't stake any tokens yet");
        _;
    }

    function getBalanceOf(address account) external isValidAccount(account) returns (uint256) {
        console.log('getBalanceOf Current Block number: ', block.number);
        _updateReward();
        
        return _balances[account];
    }

    function _calculateReward(address user) private {
        if (_totalRewardsSupply <= 0) {
            return;
        }
        // check for rewardPhase change between blocks
        uint256 phase = block.number - firstBlockNumber;
        uint256 blocksToCalculate = block.number - lastUpdateBlockNumber;
        (uint256 currentRate,) = _getRewardPhaseRate(phase);
        (uint256 previousPhaseRate, uint256 previousRateLimit) = _getRewardPhaseRate(lastUpdateBlockNumber - firstBlockNumber + 1);
        uint256 userBalance = _balances[user];
        uint256 previousCompound;
        uint256 previousBlocksToCalculate;
        // console.log("******block.number: ****** ", block.number);
        // console.log("******lastUpdateBlockNumber: ****** ", lastUpdateBlockNumber);

        //check if last calculated phase + 1's rate is different than current's rate 
        if (currentRate != previousPhaseRate) {
        console.log("******previousPhaseRate: ****** ", previousPhaseRate);
        console.log("******currentRate: ****** ", currentRate);
            console.log("Switching phases:");
            previousBlocksToCalculate = previousRateLimit.sub(lastUpdateBlockNumber);
            previousCompound = _rewardPerBlock(userBalance, previousPhaseRate).mul(previousBlocksToCalculate); 

            blocksToCalculate = block.number.sub(previousRateLimit);
        } 

        // console.log("******currentRate: ****** ", currentRate);
        // console.log("******previousCompound: ****** ", previousCompound);
        // console.log("******_rewardPerBlock: ****** ", _rewardPerBlock(userBalance + previousCompound, currentRate));
        uint256 rewards = _rewardPerBlock(userBalance + previousCompound, currentRate).mul(blocksToCalculate);
        // uint256 newBalance = _rewardPerBlock(userBalance + previousCompound, currentRate);
        //     console.log('****_rewardPerBlock****: ', newBalance);
        //     newBalance = newBalance.mul(blocksToCalculate);

        // console.log("Rate:", currentRate);
        console.log("blocksToCalculate:", blocksToCalculate);
        // console.log("Phase:", phase);
        uint256 newBalance = _balances[user].add(rewards);
        console.log("Rewards:", rewards);
        console.log("User balance:", userBalance);
        // console.log("newBalance:", newBalance);
        _balances[user] = newBalance;
        _totalStakedTemp += newBalance;
        
    }

    function _rewardPerBlock(uint256 balance, uint256 rate) private view returns (uint256) {
        // return (balance.div(_totalStaked)).mul(rate).mul(OGUN_PRECISION_FACTOR);
        return (balance.div(_totalStaked)).mul(rate);
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
        for (uint256 i = 0; i < this.getAddressesSize(); i++){
            _calculateReward(_addresses[i]);
        }
        lastUpdateBlockNumber = block.number;
        _totalStaked = _totalStakedTemp;
        _totalStakedTemp = 0;
        // console.log('_updateReward _totalStaked: ', _totalStaked);

        emit RewardsCalculated(_totalStaked);
    }

    function stake(uint256 _amount) external {
        require(_amount > 0, "Stake: Amount must be greater than 0");
        console.log('STAKE Current Block number: ', block.number);
        // console.log('STAKE AMOUNT: ', _amount);
        stakingToken.safeTransferFrom(msg.sender, address(this), _amount);
        _updateReward();
        _totalStaked += _amount;
        // console.log('STAKE _totalStaked updated: ', _totalStaked);
        _balances[msg.sender] += _amount;
        setAddress(msg.sender);

        emit Stake(msg.sender, _amount);
    }

    function withdraw() external isValidAccount(msg.sender) {
        _updateReward();
        uint256 amount = _balances[msg.sender];
        require(amount > 0, "Current balance is 0");

        // console.log('CONTRACT withdraw Amount : ', amount);
        _balances[msg.sender] = 0;
        // console.log('CONTRACT withdraw _totalStaked : ', _totalStaked);
        // if (amount > _totalRewardsSupply) {
        //     amount = _totalRewardsSupply;
        // }
        _totalStaked -= amount;
        // _totalRewardsSupply -= amount;
        // console.log('CONTRACT withdraw Amount : ', amount);
        // console.log('Withdraw Address: ', msg.sender);
        stakingToken.safeTransfer(msg.sender, amount);

        emit Withdraw(msg.sender, amount);
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

    event Withdraw(address indexed user, uint256 amount);

    event RewardsCalculated(uint256 amount);
}