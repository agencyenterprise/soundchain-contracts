// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract StakingRewards is ReentrancyGuard {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    uint256 public constant OGUN_PRECISION_FACTOR = 10**12;
    uint256 public constant REWARDS_PHASE_ONE = 307692308000000000000;
    uint256 public constant REWARDS_PHASE_TWO = 128205128000000000000; 
    uint256 public constant REWARDS_PHASE_THREE = 48076923100000000000; 
    uint256 public constant REWARDS_PHASE_FOUR = 38359083600000000000; 
    uint256 public constant PHASE_ONE_BLOCK = 195000; 
    uint256 public constant PHASE_TWO_BLOCK = 780000; 
    uint256 public constant PHASE_THREE_BLOCK = 2340000; 
    uint256 public constant PHASE_FOUR_BLOCK = 4686250; 
    
    IERC20 public immutable stakingToken;

    uint256 private _lastUpdatedBlockNumber;
    uint256 public immutable firstBlockNumber;
    uint256 private _totalRewardsSupply;
    uint256 private _totalStaked;
    uint256 private _totalStakedTemp;

    mapping(address => uint256) private _balances;
    mapping(address => bool) private _addressInserted;
    address[] private _addresses;

    constructor(address _stakingToken, uint256 _rewardsSupply) {
        stakingToken = IERC20(_stakingToken);
        _totalRewardsSupply = _rewardsSupply;
        firstBlockNumber = block.number;
        _lastUpdatedBlockNumber = block.number;
    }

    modifier isValidAccount(address _account) {
        require(_addressInserted[_account], "address hasn't stake any tokens yet");
        _;
    }

    function getUpdatedBalanceOf(address _account) external nonReentrant isValidAccount(_account) returns (uint256) {
        _updateReward();
        emit RewardsCalculatedOf(_balances[_account], _account);
        return _balances[_account];
    }

    function getBalanceOf(address _account) external view isValidAccount(_account) returns (uint256) {
        return _balances[_account];
    } 

    function _calculateReward(address _user) private {
        if (_totalRewardsSupply <= 0) {
            return;
        }
        uint256 userBalance = _balances[_user];
        if (userBalance <= 0) {
            return;
        }
        uint256 phase = block.number - firstBlockNumber;
        uint256 blocksToCalculate = block.number - _lastUpdatedBlockNumber;
        (uint256 currentRate,) = _getRewardPhaseRate(phase);
        (uint256 previousPhaseRate, uint256 previousRateLimit) = _getRewardPhaseRate(_lastUpdatedBlockNumber - firstBlockNumber + 1);
        uint256 previousPhaseRewards;
        uint256 previousBlocksToCalculate;

        //Check if there are blocks to calculate from a previous phase
        if (currentRate != previousPhaseRate) {
            previousBlocksToCalculate = previousRateLimit.sub(_lastUpdatedBlockNumber.sub(firstBlockNumber));
            previousPhaseRewards = _rewardPerBlock(userBalance, previousPhaseRate, previousBlocksToCalculate); 
            blocksToCalculate -= previousBlocksToCalculate;
        } 

        uint256 rewards = _rewardPerBlock(userBalance, currentRate, blocksToCalculate);
        uint256 newBalance = userBalance.add(rewards).add(previousPhaseRewards);
        _balances[_user] = newBalance;
        _totalStakedTemp += newBalance;
    }

    function _rewardPerBlock(uint256 _balance, uint256 _rate, uint256 _blocks) private view returns (uint256) {
        uint256 balanceScaled = (_balance.mul(OGUN_PRECISION_FACTOR)).div(_totalStaked);
        return (balanceScaled.mul(_rate).div(OGUN_PRECISION_FACTOR)).mul(_blocks);
    }

    function _getRewardPhaseRate(uint256 _blockNumber) private pure returns (uint256 rate, uint256 phaseLimit) {
        if (_blockNumber <= PHASE_ONE_BLOCK) {
            return (REWARDS_PHASE_ONE, PHASE_ONE_BLOCK);
        }

        if (_blockNumber <= PHASE_TWO_BLOCK) {
            return (REWARDS_PHASE_TWO, PHASE_TWO_BLOCK);
        }

        if (_blockNumber <= PHASE_THREE_BLOCK) {
            return (REWARDS_PHASE_THREE, PHASE_THREE_BLOCK);
        }

        if (_blockNumber <= PHASE_FOUR_BLOCK) {
            return (REWARDS_PHASE_FOUR, PHASE_FOUR_BLOCK);
        }

        return (0, 0);
    }

    function _updateReward() internal {
        if (block.number <= _lastUpdatedBlockNumber) {
            return;
        }
        for (uint256 i = 0; i < this.getAddressesSize(); i++){
            _calculateReward(_addresses[i]);
        }
        _lastUpdatedBlockNumber = block.number;
        _totalStaked = _totalStakedTemp;
        _totalStakedTemp = 0;

        emit RewardsCalculated(_totalStaked);
    }

    function updateReward() external {
        _updateReward();
    }

    function stake(uint256 _amount) external nonReentrant {
        require(_amount > 0, "Stake: Amount must be greater than 0");
        stakingToken.safeTransferFrom(msg.sender, address(this), _amount);
        _updateReward();
        _totalStaked += _amount;
        _totalRewardsSupply += _amount;
        _balances[msg.sender] += _amount;
        setAddress(msg.sender);

        emit Stake(msg.sender, _amount);
    }

    function withdraw() external nonReentrant isValidAccount(msg.sender) {
        _updateReward();
        uint256 amount = _balances[msg.sender];
        require(amount > 0, "Current balance is 0");

        if (amount > _totalRewardsSupply) {
            amount = _totalRewardsSupply;
        }

        _balances[msg.sender] = 0;
        _totalStaked -= amount;
        _totalRewardsSupply -= amount;
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

    event RewardsCalculatedOf(uint256 amount, address account);
}