// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract StakingRewards is ReentrancyGuard {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    event Stake(address indexed user, uint256 amount);

    event Withdraw(address indexed user, uint256 stakedAmount, uint256 rewardAmount);

    event RewardsCalculated(uint256 totalRewardsAllocated, uint256 totalUserBalances, uint256 totalStakedPlusRewards);

    event RewardsCalculatedOf(uint256 stakedAmount, uint256 inclusiveRewardAmount, uint256 newRewardAmount, address account);

    // event PhaseInfo(uint256 currentBlock, uint256 relativeBlock, string currentPhase);
    // emit PhaseInfo(block.number, _blockNumber, "");

    uint256 public constant OGUN_PRECISION_FACTOR = 10**12;
    uint256 public constant PHASE_ONE_BLOCK = 1250000; 
    uint256 public constant PHASE_TWO_BLOCK = 3125000 + PHASE_ONE_BLOCK; 
    uint256 public constant PHASE_THREE_BLOCK = 10000000 + PHASE_TWO_BLOCK; 
    uint256 public constant PHASE_FOUR_BLOCK = 15000000 + PHASE_THREE_BLOCK;
    uint256 public constant REWARDS_PHASE_ONE = 32 * (10**18);
    uint256 public constant REWARDS_PHASE_TWO = 16 * (10**18); 
    uint256 public constant REWARDS_PHASE_THREE = 5 * (10**18); 
    uint256 public constant REWARDS_PHASE_FOUR = 4 * (10**18);

    IERC20 public immutable stakingToken;

    uint256 private _lastUpdatedBlockNumber;
    uint256 public immutable firstBlockNumber;
    uint256 private _totalRewardsSupply;
    uint256 public _totalRewardsAllocated;
    uint256 public _totalStaked;

    mapping(address => uint256) private _stakedBalances;
    mapping(address => uint256) private _rewardBalances;
    mapping(address => bool) private _addressInserted;
    address[] private _addresses;

    constructor(address _stakingToken, uint256 _rewardsSupply) {
        stakingToken = IERC20(_stakingToken);
        _totalRewardsSupply = _rewardsSupply;
        firstBlockNumber = block.number.add(120);
        _lastUpdatedBlockNumber = block.number.add(120);
    }

    modifier isValidAccount(address _account) {
        require(_addressInserted[_account], "address hasn't stake any tokens yet");
        _;
    }

    function getUpdatedBalanceOf(address _account) external nonReentrant isValidAccount(_account) returns (uint256, uint256, uint256) {
        uint256 newUserReward = _calculateNewRewardAmount(_account);
        _updateReward();
        emit RewardsCalculatedOf(_stakedBalances[_account], _rewardBalances[_account], newUserReward, _account);
        return (_stakedBalances[_account], _rewardBalances[_account], newUserReward);
    }

    function getBalanceOf(address _account) external view isValidAccount(_account) returns (uint256, uint256, uint256) {
        uint256 newUserReward = _calculateNewRewardAmount(_account);
        return (_stakedBalances[_account], _rewardBalances[_account], newUserReward);
    } 

    function _rewardPerBlock(uint256 _balance, uint256 _rate, uint256 _blocks) private view returns (uint256) {
        uint256 balanceScaled = (_balance.mul(OGUN_PRECISION_FACTOR)).div(_totalStaked.add(_totalRewardsAllocated));
        return (balanceScaled.mul(_rate).div(OGUN_PRECISION_FACTOR)).mul(_blocks);
    }

    function _getRewardPhaseRate(uint256 _relativeBlockNumber) private pure returns (uint256 rate, uint256 phaseLimit, uint256) {
        if (_relativeBlockNumber == 0) {
            return (0, 0, 0);
        }

        if (_relativeBlockNumber <= PHASE_ONE_BLOCK) {
            return (REWARDS_PHASE_ONE, PHASE_ONE_BLOCK, 1);
        }

        if (_relativeBlockNumber <= PHASE_TWO_BLOCK) {
            return (REWARDS_PHASE_TWO, PHASE_TWO_BLOCK, 2);
        }

        if (_relativeBlockNumber <= PHASE_THREE_BLOCK) {
            return (REWARDS_PHASE_THREE, PHASE_THREE_BLOCK, 3);
        }

        return (REWARDS_PHASE_FOUR, PHASE_FOUR_BLOCK, 4);
    }

    function _calculateNewRewardAmount(address _user) private view returns (uint256) {

        if (_totalRewardsSupply <= 0 || block.number <= firstBlockNumber || _lastUpdatedBlockNumber >= PHASE_FOUR_BLOCK.add(firstBlockNumber)) {
            return 0;
        }

        uint256 stakedUserBalance = _stakedBalances[_user];
        uint256 rewardedUserBalance = _rewardBalances[_user];
        uint256 combinedUserBalance = stakedUserBalance.add(rewardedUserBalance);

        if (stakedUserBalance <= 0) {
            return 0;
        }

        (uint256 currentRate, , uint256 currentPhase) = _getRewardPhaseRate(block.number.sub(firstBlockNumber));

        // how many blocks from each phase have passed since the last updated block
        // calculate user reward for the amount of blocks in each phase missed

        uint256 lastRelativeBlockNumber = _lastUpdatedBlockNumber.sub(firstBlockNumber);

        (uint256 lastUpdatedPhaseRate, uint256 lastUpdatedRateLimit, uint256 lastUpdatedPhase) = _getRewardPhaseRate(lastRelativeBlockNumber);

        if (block.number <= PHASE_ONE_BLOCK.add(firstBlockNumber)) {
            return _rewardPerBlock(combinedUserBalance, currentRate, block.number.sub(_lastUpdatedBlockNumber));
        }

        uint256 totalNewRewards = 0;
        uint256 tempRelativeBlockNumber = lastRelativeBlockNumber;
        uint256 tempBlocksToCalculate = lastUpdatedRateLimit.sub(lastRelativeBlockNumber);
        uint256 tempBlocksLeft = block.number.sub(tempRelativeBlockNumber.add(firstBlockNumber));

        uint256 tempPhaseRate = lastUpdatedPhaseRate;
        uint256 tempRateLimit = lastUpdatedRateLimit;

        for (uint256 i = lastUpdatedPhase; i <= currentPhase; i++) {
            if (tempBlocksToCalculate > tempBlocksLeft) {
                tempBlocksToCalculate = tempBlocksLeft;
            }

            totalNewRewards = totalNewRewards.add(_rewardPerBlock(combinedUserBalance, tempPhaseRate, tempBlocksToCalculate));
            tempRelativeBlockNumber = tempRelativeBlockNumber.add(tempBlocksToCalculate);
            (tempPhaseRate, tempRateLimit, ) = _getRewardPhaseRate(tempRelativeBlockNumber.add(1));
            tempBlocksToCalculate = tempRateLimit.sub(tempRelativeBlockNumber);
            tempBlocksLeft = block.number.sub(tempRelativeBlockNumber.add(firstBlockNumber));
        }

        return totalNewRewards;
    }

    function getReward(address _user) external view returns (uint256) {
        return _rewardBalances[_user].add(_calculateNewRewardAmount(_user));
    }

    function _updateReward() internal {
        if (block.number <= _lastUpdatedBlockNumber) {
            return;
        }

        uint256 totalStakedPlusRewards = _totalStaked.add(_totalRewardsAllocated);
        uint256 totalNewRewards = 0;
        uint256 totalUserBalances = 0;
        for (uint256 i = 0; i < this.getAddressesSize(); i++){
            totalUserBalances = totalUserBalances.add(_stakedBalances[_addresses[i]].add(_rewardBalances[_addresses[i]]));
            uint256 newUserRewards = _calculateNewRewardAmount(_addresses[i]);
            _rewardBalances[_addresses[i]] = _rewardBalances[_addresses[i]].add(newUserRewards);
            totalNewRewards = totalNewRewards.add(newUserRewards);
        }

        _totalRewardsAllocated = _totalRewardsAllocated.add(totalNewRewards);
        _lastUpdatedBlockNumber = block.number;
        emit RewardsCalculated(_totalRewardsAllocated, totalUserBalances, totalStakedPlusRewards);
    }

    function updateReward() external {
        _updateReward();
    }

    function stake(uint256 _amount) external nonReentrant {
        require(_amount > 0, "Stake: Amount must be greater than 0");
        stakingToken.safeTransferFrom(msg.sender, address(this), _amount);
        _updateReward();
        _totalStaked = _totalStaked.add(_amount); // initial stake
        _stakedBalances[msg.sender] = _stakedBalances[msg.sender].add(_amount);
        addAddress(msg.sender);
        emit Stake(msg.sender, _amount);
    }

    function withdraw() external nonReentrant isValidAccount(msg.sender) {
        _updateReward();
        uint256 stakedAmount = _stakedBalances[msg.sender];
        uint256 rewardAmount = _rewardBalances[msg.sender];
        uint256 totalAmount = stakedAmount.add(rewardAmount);
        require(totalAmount > 0, "Current balance is 0");

        if (totalAmount > _totalRewardsSupply) {
            totalAmount = _totalRewardsSupply;
        }

        _totalStaked = _totalStaked.sub(stakedAmount);
        _totalRewardsSupply = _totalRewardsSupply.sub(rewardAmount);
        _totalRewardsAllocated = _totalRewardsAllocated.sub(rewardAmount);
        _stakedBalances[msg.sender] = 0;
        _rewardBalances[msg.sender] = 0;

        stakingToken.safeTransfer(msg.sender, stakedAmount);
        stakingToken.safeTransfer(msg.sender, rewardAmount);
        emit Withdraw(msg.sender, stakedAmount, rewardAmount);
    }

    function addAddress(address account) internal {

        if (!_addressInserted[account]) {
            _addressInserted[account] = true;
            _addresses.push(account);
        }
    }

    function getAddressesSize() external view returns (uint256) {
        return _addresses.length;
    }
}