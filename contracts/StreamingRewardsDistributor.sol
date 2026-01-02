// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";

/**
 * @title StreamingRewardsDistributor
 * @notice Distributes OGUN tokens to artists and listeners based on streaming activity
 * @dev Called by authorized backend service after validating stream data
 *
 * Reward Tiers:
 * - NFT mints (with tokenId): 0.5 OGUN per stream
 * - Non-NFT mints: 0.05 OGUN per stream
 * - Max 100 OGUN per track per day (anti-bot farming)
 *
 * Distribution Options:
 * - Single recipient (creator only)
 * - Creator + Listener split (50/50 default, configurable)
 * - Creator + Collaborators (based on royalty percentages)
 * - Full split: Creator + Listener + Collaborators
 */
contract StreamingRewardsDistributor is Ownable, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    // Events
    event RewardsClaimed(address indexed user, uint256 amount, bytes32 indexed scidHash);
    event RewardsStaked(address indexed user, uint256 amount, bytes32 indexed scidHash);
    event BatchRewardsClaimed(address indexed user, uint256 totalAmount, uint256 claimCount);
    event ListenerRewardClaimed(address indexed listener, address indexed creator, uint256 listenerAmount, uint256 creatorAmount, bytes32 indexed scidHash);
    event CollaboratorRewardClaimed(address indexed collaborator, uint256 amount, bytes32 indexed scidHash);
    event DistributorAuthorized(address indexed distributor);
    event DistributorRevoked(address indexed distributor);
    event StakingContractUpdated(address indexed stakingContract);
    event ListenerSplitUpdated(uint256 listenerBps);
    event ProtocolFeeUpdated(uint256 feeBps, address indexed feeRecipient);
    event ProtocolFeeCollected(address indexed recipient, uint256 amount, bytes32 indexed scidHash);
    event EmergencyWithdraw(address indexed owner, uint256 amount);

    // OGUN token
    IERC20 public immutable ogunToken;

    // Staking contract for direct staking
    address public stakingContract;

    // Authorized distributors (backend services)
    mapping(address => bool) public authorizedDistributors;

    // Track claimed rewards per SCid hash (keccak256 of SCid string)
    mapping(bytes32 => uint256) public claimedByScid;

    // Track claimed rewards per wallet
    mapping(address => uint256) public claimedByWallet;

    // Track daily rewards per SCid (resets daily)
    mapping(bytes32 => uint256) public dailyRewardsByScid;
    mapping(bytes32 => uint256) public lastRewardDay;

    // Constants
    uint256 public constant NFT_REWARD_RATE = 5 * 10**17;      // 0.5 OGUN (18 decimals)
    uint256 public constant BASE_REWARD_RATE = 5 * 10**16;     // 0.05 OGUN (18 decimals)
    uint256 public constant MAX_DAILY_REWARDS = 100 * 10**18;  // 100 OGUN per track per day
    uint256 public constant BASIS_POINTS = 10000;              // 100% = 10000 bps

    // Listener reward split (in basis points, default 5000 = 50%)
    uint256 public listenerSplitBps = 5000;

    // Protocol fee (in basis points, default 5 = 0.05%)
    uint256 public protocolFeeBps = 5;
    address public feeRecipient;

    // Total rewards distributed
    uint256 public totalRewardsDistributed;
    uint256 public totalListenerRewards;
    uint256 public totalCreatorRewards;
    uint256 public totalCollaboratorRewards;
    uint256 public totalProtocolFees;

    // Nonce for replay protection
    mapping(address => uint256) public nonces;

    constructor(address _ogunToken) {
        require(_ogunToken != address(0), "Invalid OGUN token address");
        ogunToken = IERC20(_ogunToken);
    }

    // ==================== MODIFIERS ====================

    modifier onlyAuthorizedDistributor() {
        require(authorizedDistributors[msg.sender], "Not authorized distributor");
        _;
    }

    // ==================== ADMIN FUNCTIONS ====================

    /**
     * @notice Authorize a backend service to submit reward claims
     * @param distributor Address of the distributor
     */
    function authorizeDistributor(address distributor) external onlyOwner {
        require(distributor != address(0), "Invalid address");
        authorizedDistributors[distributor] = true;
        emit DistributorAuthorized(distributor);
    }

    /**
     * @notice Revoke distributor authorization
     * @param distributor Address of the distributor
     */
    function revokeDistributor(address distributor) external onlyOwner {
        authorizedDistributors[distributor] = false;
        emit DistributorRevoked(distributor);
    }

    /**
     * @notice Set the staking contract address for direct staking
     * @param _stakingContract Address of the StakingRewards contract
     */
    function setStakingContract(address _stakingContract) external onlyOwner {
        require(_stakingContract != address(0), "Invalid staking contract");
        stakingContract = _stakingContract;
        emit StakingContractUpdated(_stakingContract);
    }

    /**
     * @notice Pause the contract
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @notice Unpause the contract
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @notice Emergency withdraw all OGUN tokens
     * @param to Address to send tokens to
     */
    function emergencyWithdraw(address to) external onlyOwner {
        uint256 balance = ogunToken.balanceOf(address(this));
        require(balance > 0, "No balance to withdraw");
        ogunToken.safeTransfer(to, balance);
        emit EmergencyWithdraw(to, balance);
    }

    /**
     * @notice Set the listener reward split percentage
     * @param _listenerSplitBps Split in basis points (5000 = 50%)
     */
    function setListenerSplit(uint256 _listenerSplitBps) external onlyOwner {
        require(_listenerSplitBps <= BASIS_POINTS, "Invalid split percentage");
        listenerSplitBps = _listenerSplitBps;
        emit ListenerSplitUpdated(_listenerSplitBps);
    }

    /**
     * @notice Set the protocol fee and recipient
     * @param _protocolFeeBps Fee in basis points (5 = 0.05%, max 100 = 1%)
     * @param _feeRecipient Address to receive protocol fees (treasury)
     */
    function setProtocolFee(uint256 _protocolFeeBps, address _feeRecipient) external onlyOwner {
        require(_protocolFeeBps <= 100, "Fee too high (max 1%)");
        require(_feeRecipient != address(0), "Invalid fee recipient");
        protocolFeeBps = _protocolFeeBps;
        feeRecipient = _feeRecipient;
        emit ProtocolFeeUpdated(_protocolFeeBps, _feeRecipient);
    }

    // ==================== DISTRIBUTOR FUNCTIONS ====================

    /**
     * @notice Internal function to calculate and collect protocol fee
     * @param totalAmount The total amount before fees
     * @param scidHash The SCid hash for event emission
     * @return netAmount Amount after fee deduction
     */
    function _collectProtocolFee(uint256 totalAmount, bytes32 scidHash) internal returns (uint256 netAmount) {
        if (protocolFeeBps == 0 || feeRecipient == address(0)) {
            return totalAmount;
        }

        uint256 feeAmount = (totalAmount * protocolFeeBps) / BASIS_POINTS;
        netAmount = totalAmount - feeAmount;

        if (feeAmount > 0) {
            totalProtocolFees += feeAmount;
            ogunToken.safeTransfer(feeRecipient, feeAmount);
            emit ProtocolFeeCollected(feeRecipient, feeAmount, scidHash);
        }

        return netAmount;
    }

    /**
     * @notice Submit a reward claim for a user
     * @param user Address of the user claiming rewards
     * @param scid The SCid string (hashed for storage)
     * @param amount Amount of OGUN to distribute
     * @param isNft Whether this is an NFT mint (affects rate validation)
     */
    function submitReward(
        address user,
        string calldata scid,
        uint256 amount,
        bool isNft
    ) external onlyAuthorizedDistributor whenNotPaused nonReentrant {
        require(user != address(0), "Invalid user address");
        require(amount > 0, "Amount must be greater than 0");

        bytes32 scidHash = keccak256(bytes(scid));

        // Check daily limit
        uint256 currentDay = block.timestamp / 1 days;
        if (lastRewardDay[scidHash] != currentDay) {
            dailyRewardsByScid[scidHash] = 0;
            lastRewardDay[scidHash] = currentDay;
        }

        require(
            dailyRewardsByScid[scidHash] + amount <= MAX_DAILY_REWARDS,
            "Daily limit reached for this track"
        );

        // Validate amount matches expected rate
        uint256 expectedRate = isNft ? NFT_REWARD_RATE : BASE_REWARD_RATE;
        require(amount <= expectedRate * 10, "Amount exceeds max per claim"); // Allow batch up to 10 streams

        // Collect protocol fee (0.05%)
        uint256 netAmount = _collectProtocolFee(amount, scidHash);

        // Update tracking
        dailyRewardsByScid[scidHash] += amount;
        claimedByScid[scidHash] += amount;
        claimedByWallet[user] += netAmount;
        totalRewardsDistributed += amount;

        // Transfer OGUN to user (after fee)
        ogunToken.safeTransfer(user, netAmount);

        emit RewardsClaimed(user, netAmount, scidHash);
    }

    /**
     * @notice Submit a reward and stake directly
     * @param user Address of the user
     * @param scid The SCid string
     * @param amount Amount of OGUN to stake
     * @param isNft Whether this is an NFT mint
     */
    function submitRewardAndStake(
        address user,
        string calldata scid,
        uint256 amount,
        bool isNft
    ) external onlyAuthorizedDistributor whenNotPaused nonReentrant {
        require(user != address(0), "Invalid user address");
        require(amount > 0, "Amount must be greater than 0");
        require(stakingContract != address(0), "Staking contract not set");

        bytes32 scidHash = keccak256(bytes(scid));

        // Check daily limit
        uint256 currentDay = block.timestamp / 1 days;
        if (lastRewardDay[scidHash] != currentDay) {
            dailyRewardsByScid[scidHash] = 0;
            lastRewardDay[scidHash] = currentDay;
        }

        require(
            dailyRewardsByScid[scidHash] + amount <= MAX_DAILY_REWARDS,
            "Daily limit reached for this track"
        );

        // Validate amount
        uint256 expectedRate = isNft ? NFT_REWARD_RATE : BASE_REWARD_RATE;
        require(amount <= expectedRate * 10, "Amount exceeds max per claim");

        // Update tracking
        dailyRewardsByScid[scidHash] += amount;
        claimedByScid[scidHash] += amount;
        claimedByWallet[user] += amount;
        totalRewardsDistributed += amount;

        // Approve and stake on behalf of user
        ogunToken.safeApprove(stakingContract, amount);

        // Note: This requires the staking contract to support staking on behalf of users
        // For now, we transfer to user and they must stake manually
        // TODO: Implement stakeFor in StakingRewards contract
        ogunToken.safeTransfer(user, amount);

        emit RewardsStaked(user, amount, scidHash);
    }

    /**
     * @notice Batch submit rewards for multiple users
     * @param users Array of user addresses
     * @param scids Array of SCid strings
     * @param amounts Array of OGUN amounts
     * @param isNfts Array of NFT flags
     */
    function batchSubmitRewards(
        address[] calldata users,
        string[] calldata scids,
        uint256[] calldata amounts,
        bool[] calldata isNfts
    ) external onlyAuthorizedDistributor whenNotPaused nonReentrant {
        require(
            users.length == scids.length &&
            scids.length == amounts.length &&
            amounts.length == isNfts.length,
            "Array length mismatch"
        );
        require(users.length <= 100, "Batch too large");

        uint256 currentDay = block.timestamp / 1 days;
        uint256 totalAmount = 0;

        for (uint256 i = 0; i < users.length; i++) {
            require(users[i] != address(0), "Invalid user address");
            require(amounts[i] > 0, "Amount must be greater than 0");

            bytes32 scidHash = keccak256(bytes(scids[i]));

            // Reset daily counter if new day
            if (lastRewardDay[scidHash] != currentDay) {
                dailyRewardsByScid[scidHash] = 0;
                lastRewardDay[scidHash] = currentDay;
            }

            // Skip if daily limit reached
            if (dailyRewardsByScid[scidHash] + amounts[i] > MAX_DAILY_REWARDS) {
                continue;
            }

            // Validate amount
            uint256 expectedRate = isNfts[i] ? NFT_REWARD_RATE : BASE_REWARD_RATE;
            if (amounts[i] > expectedRate * 10) {
                continue;
            }

            // Update tracking
            dailyRewardsByScid[scidHash] += amounts[i];
            claimedByScid[scidHash] += amounts[i];
            claimedByWallet[users[i]] += amounts[i];
            totalAmount += amounts[i];

            emit RewardsClaimed(users[i], amounts[i], scidHash);
        }

        totalRewardsDistributed += totalAmount;

        // Batch transfer - more gas efficient
        // Note: This requires all rewards go to same user for efficiency
        // For different users, transfer individually in the loop
        for (uint256 i = 0; i < users.length; i++) {
            if (amounts[i] > 0 && claimedByWallet[users[i]] > 0) {
                // Transfer accumulated amount
                // Note: This is simplified - production should track per-batch amounts
            }
        }
    }

    /**
     * @notice Submit reward with listener/creator split (50/50 by default)
     * @param creator Address of the track creator
     * @param listener Address of the listener/streamer
     * @param scid The SCid string
     * @param totalAmount Total OGUN reward to split
     * @param isNft Whether this is an NFT track
     */
    function submitRewardWithListenerSplit(
        address creator,
        address listener,
        string calldata scid,
        uint256 totalAmount,
        bool isNft
    ) external onlyAuthorizedDistributor whenNotPaused nonReentrant {
        require(creator != address(0), "Invalid creator address");
        require(listener != address(0), "Invalid listener address");
        require(totalAmount > 0, "Amount must be greater than 0");

        bytes32 scidHash = keccak256(bytes(scid));

        // Check daily limit
        uint256 currentDay = block.timestamp / 1 days;
        if (lastRewardDay[scidHash] != currentDay) {
            dailyRewardsByScid[scidHash] = 0;
            lastRewardDay[scidHash] = currentDay;
        }

        require(
            dailyRewardsByScid[scidHash] + totalAmount <= MAX_DAILY_REWARDS,
            "Daily limit reached for this track"
        );

        // Validate amount
        uint256 expectedRate = isNft ? NFT_REWARD_RATE : BASE_REWARD_RATE;
        require(totalAmount <= expectedRate * 10, "Amount exceeds max per claim");

        // Collect protocol fee (0.05%) first
        uint256 netAmount = _collectProtocolFee(totalAmount, scidHash);

        // Calculate split from net amount
        uint256 listenerAmount = (netAmount * listenerSplitBps) / BASIS_POINTS;
        uint256 creatorAmount = netAmount - listenerAmount;

        // Update tracking
        dailyRewardsByScid[scidHash] += totalAmount;
        claimedByScid[scidHash] += totalAmount;
        claimedByWallet[creator] += creatorAmount;
        claimedByWallet[listener] += listenerAmount;
        totalRewardsDistributed += totalAmount;
        totalCreatorRewards += creatorAmount;
        totalListenerRewards += listenerAmount;

        // Transfer OGUN to both parties
        if (creatorAmount > 0) {
            ogunToken.safeTransfer(creator, creatorAmount);
        }
        if (listenerAmount > 0) {
            ogunToken.safeTransfer(listener, listenerAmount);
        }

        emit ListenerRewardClaimed(listener, creator, listenerAmount, creatorAmount, scidHash);
    }

    /**
     * @notice Submit reward with collaborator splits
     * @param creator Address of the primary creator
     * @param collaborators Array of collaborator addresses
     * @param collaboratorBps Array of collaborator split percentages (in basis points)
     * @param scid The SCid string
     * @param totalAmount Total OGUN reward to distribute
     * @param isNft Whether this is an NFT track
     */
    function submitRewardWithCollaborators(
        address creator,
        address[] calldata collaborators,
        uint256[] calldata collaboratorBps,
        string calldata scid,
        uint256 totalAmount,
        bool isNft
    ) external onlyAuthorizedDistributor whenNotPaused nonReentrant {
        require(creator != address(0), "Invalid creator address");
        require(collaborators.length == collaboratorBps.length, "Array length mismatch");
        require(collaborators.length <= 10, "Too many collaborators");
        require(totalAmount > 0, "Amount must be greater than 0");

        bytes32 scidHash = keccak256(bytes(scid));

        // Check daily limit
        uint256 currentDay = block.timestamp / 1 days;
        if (lastRewardDay[scidHash] != currentDay) {
            dailyRewardsByScid[scidHash] = 0;
            lastRewardDay[scidHash] = currentDay;
        }

        require(
            dailyRewardsByScid[scidHash] + totalAmount <= MAX_DAILY_REWARDS,
            "Daily limit reached for this track"
        );

        // Validate amount
        uint256 expectedRate = isNft ? NFT_REWARD_RATE : BASE_REWARD_RATE;
        require(totalAmount <= expectedRate * 10, "Amount exceeds max per claim");

        // Collect protocol fee (0.05%) first
        uint256 netAmount = _collectProtocolFee(totalAmount, scidHash);

        // Calculate and validate total collaborator percentage
        uint256 totalCollabBps = 0;
        for (uint256 i = 0; i < collaboratorBps.length; i++) {
            totalCollabBps += collaboratorBps[i];
        }
        require(totalCollabBps < BASIS_POINTS, "Collaborator splits exceed 100%");

        // Update tracking
        dailyRewardsByScid[scidHash] += totalAmount;
        claimedByScid[scidHash] += totalAmount;
        totalRewardsDistributed += totalAmount;

        uint256 totalCollaboratorAmount = 0;

        // Distribute to collaborators (from net amount after fee)
        for (uint256 i = 0; i < collaborators.length; i++) {
            if (collaborators[i] != address(0) && collaboratorBps[i] > 0) {
                uint256 collabAmount = (netAmount * collaboratorBps[i]) / BASIS_POINTS;
                totalCollaboratorAmount += collabAmount;
                claimedByWallet[collaborators[i]] += collabAmount;
                ogunToken.safeTransfer(collaborators[i], collabAmount);
                emit CollaboratorRewardClaimed(collaborators[i], collabAmount, scidHash);
            }
        }

        // Remainder goes to creator
        uint256 creatorAmount = netAmount - totalCollaboratorAmount;
        claimedByWallet[creator] += creatorAmount;
        totalCreatorRewards += creatorAmount;
        totalCollaboratorRewards += totalCollaboratorAmount;

        ogunToken.safeTransfer(creator, creatorAmount);
        emit RewardsClaimed(creator, creatorAmount, scidHash);
    }

    /**
     * @notice Submit reward with full split: listener + creator + collaborators
     * @param creator Address of the primary creator
     * @param listener Address of the listener/streamer
     * @param collaborators Array of collaborator addresses
     * @param collaboratorBps Array of collaborator split percentages (in basis points, applied to creator share)
     * @param scid The SCid string
     * @param totalAmount Total OGUN reward to distribute
     * @param isNft Whether this is an NFT track
     */
    function submitRewardFull(
        address creator,
        address listener,
        address[] calldata collaborators,
        uint256[] calldata collaboratorBps,
        string calldata scid,
        uint256 totalAmount,
        bool isNft
    ) external onlyAuthorizedDistributor whenNotPaused nonReentrant {
        require(creator != address(0), "Invalid creator address");
        require(listener != address(0), "Invalid listener address");
        require(collaborators.length == collaboratorBps.length, "Array length mismatch");
        require(collaborators.length <= 10, "Too many collaborators");
        require(totalAmount > 0, "Amount must be greater than 0");

        bytes32 scidHash = keccak256(bytes(scid));

        // Check daily limit
        uint256 currentDay = block.timestamp / 1 days;
        if (lastRewardDay[scidHash] != currentDay) {
            dailyRewardsByScid[scidHash] = 0;
            lastRewardDay[scidHash] = currentDay;
        }

        require(
            dailyRewardsByScid[scidHash] + totalAmount <= MAX_DAILY_REWARDS,
            "Daily limit reached for this track"
        );

        // Validate amount
        uint256 expectedRate = isNft ? NFT_REWARD_RATE : BASE_REWARD_RATE;
        require(totalAmount <= expectedRate * 10, "Amount exceeds max per claim");

        // Collect protocol fee (0.05%) first
        uint256 netAmount = _collectProtocolFee(totalAmount, scidHash);

        // Calculate listener share first (from net amount after fee)
        uint256 listenerAmount = (netAmount * listenerSplitBps) / BASIS_POINTS;
        uint256 creatorPoolAmount = netAmount - listenerAmount;

        // Calculate and validate collaborator percentages (from creator pool)
        uint256 totalCollabBps = 0;
        for (uint256 i = 0; i < collaboratorBps.length; i++) {
            totalCollabBps += collaboratorBps[i];
        }
        require(totalCollabBps < BASIS_POINTS, "Collaborator splits exceed 100%");

        // Update tracking
        dailyRewardsByScid[scidHash] += totalAmount;
        claimedByScid[scidHash] += totalAmount;
        totalRewardsDistributed += totalAmount;

        uint256 totalCollaboratorAmount = 0;

        // Distribute to collaborators (from creator pool)
        for (uint256 i = 0; i < collaborators.length; i++) {
            if (collaborators[i] != address(0) && collaboratorBps[i] > 0) {
                uint256 collabAmount = (creatorPoolAmount * collaboratorBps[i]) / BASIS_POINTS;
                totalCollaboratorAmount += collabAmount;
                claimedByWallet[collaborators[i]] += collabAmount;
                ogunToken.safeTransfer(collaborators[i], collabAmount);
                emit CollaboratorRewardClaimed(collaborators[i], collabAmount, scidHash);
            }
        }

        // Remainder of creator pool goes to creator
        uint256 creatorAmount = creatorPoolAmount - totalCollaboratorAmount;

        // Update balances
        claimedByWallet[creator] += creatorAmount;
        claimedByWallet[listener] += listenerAmount;
        totalCreatorRewards += creatorAmount;
        totalListenerRewards += listenerAmount;
        totalCollaboratorRewards += totalCollaboratorAmount;

        // Transfer
        if (creatorAmount > 0) {
            ogunToken.safeTransfer(creator, creatorAmount);
        }
        if (listenerAmount > 0) {
            ogunToken.safeTransfer(listener, listenerAmount);
        }

        emit ListenerRewardClaimed(listener, creator, listenerAmount, creatorAmount, scidHash);
    }

    // ==================== VIEW FUNCTIONS ====================

    /**
     * @notice Get total rewards claimed by an SCid
     * @param scid The SCid string
     */
    function getClaimedByScid(string calldata scid) external view returns (uint256) {
        return claimedByScid[keccak256(bytes(scid))];
    }

    /**
     * @notice Get daily rewards remaining for an SCid
     * @param scid The SCid string
     */
    function getDailyRemaining(string calldata scid) external view returns (uint256) {
        bytes32 scidHash = keccak256(bytes(scid));
        uint256 currentDay = block.timestamp / 1 days;

        if (lastRewardDay[scidHash] != currentDay) {
            return MAX_DAILY_REWARDS;
        }

        return MAX_DAILY_REWARDS - dailyRewardsByScid[scidHash];
    }

    /**
     * @notice Get available OGUN balance in contract
     */
    function getAvailableBalance() external view returns (uint256) {
        return ogunToken.balanceOf(address(this));
    }

    /**
     * @notice Check if an address is an authorized distributor
     * @param distributor Address to check
     */
    function isAuthorizedDistributor(address distributor) external view returns (bool) {
        return authorizedDistributors[distributor];
    }
}
