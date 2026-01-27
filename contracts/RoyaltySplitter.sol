// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title RoyaltySplitter
 * @notice Post-mint royalty splitting for SoundChain NFTs.
 *
 * Deployed per-edition or per-track. The NFT contract's royaltyReceiver
 * is updated to point to this contract. When the marketplace pays
 * royalties (POL or OGUN), this contract splits payments to all
 * collaborators by their configured basis-point shares.
 *
 * - Creator deploys splitter and adds collaborators
 * - Creator updates their NFT edition's royaltyReceiver to this address
 * - Marketplace pays this contract via EIP-2981
 * - Anyone can call distribute() to push funds to collaborators
 * - Creator can update splits (with timelock for fairness)
 *
 * Supports both native POL and ERC-20 (OGUN) payments.
 */
contract RoyaltySplitter is ReentrancyGuard {
    using SafeERC20 for IERC20;

    // --- Types ---

    struct Collaborator {
        address wallet;
        uint256 bps; // basis points (100 = 1%, 10000 = 100%)
    }

    // --- State ---

    address public creator;        // Original NFT creator, can manage splits
    string public scid;            // SoundChain ID (e.g., SC-POL-D038-2600003)
    uint256 public editionId;      // Edition number in Soundchain721Editions

    Collaborator[] public collaborators;
    uint256 public totalBps;       // Sum of all collaborator bps (must be <= 10000)

    // Pending split update (timelock for fairness)
    Collaborator[] private pendingSplits;
    uint256 public pendingSplitsTimestamp;
    uint256 public constant SPLIT_UPDATE_DELAY = 48 hours;

    bool public initialized;

    // --- Events ---

    event SplitterCreated(address indexed creator, string scid, uint256 editionId);
    event CollaboratorsSet(uint256 collaboratorCount, uint256 totalBps);
    event SplitUpdateProposed(uint256 executeAfter);
    event SplitUpdateExecuted(uint256 collaboratorCount, uint256 totalBps);
    event NativeDistributed(uint256 totalAmount, uint256 collaboratorCount);
    event TokenDistributed(address indexed token, uint256 totalAmount, uint256 collaboratorCount);
    event CollaboratorPaid(address indexed wallet, uint256 amount, uint256 bps);

    // --- Modifiers ---

    modifier onlyCreator() {
        require(msg.sender == creator, "Only creator");
        _;
    }

    // --- Constructor ---

    constructor(
        address _creator,
        string memory _scid,
        uint256 _editionId,
        address[] memory _wallets,
        uint256[] memory _bps
    ) {
        require(_creator != address(0), "Invalid creator");
        require(_wallets.length == _bps.length, "Length mismatch");
        require(_wallets.length > 0 && _wallets.length <= 10, "1-10 collaborators");

        creator = _creator;
        scid = _scid;
        editionId = _editionId;

        uint256 total = 0;
        for (uint256 i = 0; i < _wallets.length; i++) {
            require(_wallets[i] != address(0), "Invalid wallet");
            require(_bps[i] > 0, "Zero bps");
            collaborators.push(Collaborator(_wallets[i], _bps[i]));
            total += _bps[i];
        }
        require(total == 10000, "Splits must total 100%");
        totalBps = total;
        initialized = true;

        emit SplitterCreated(_creator, _scid, _editionId);
        emit CollaboratorsSet(_wallets.length, total);
    }

    // --- Receive native currency (POL) ---

    receive() external payable {}

    // --- Distribution ---

    /**
     * @notice Distribute all native currency (POL) to collaborators
     * @dev Anyone can call this - pushes funds to all collaborators
     */
    function distributeNative() external nonReentrant {
        uint256 balance = address(this).balance;
        require(balance > 0, "No balance");

        for (uint256 i = 0; i < collaborators.length; i++) {
            uint256 amount = (balance * collaborators[i].bps) / 10000;
            if (amount > 0) {
                (bool sent,) = payable(collaborators[i].wallet).call{value: amount}("");
                require(sent, "Transfer failed");
                emit CollaboratorPaid(collaborators[i].wallet, amount, collaborators[i].bps);
            }
        }

        emit NativeDistributed(balance, collaborators.length);
    }

    /**
     * @notice Distribute ERC-20 tokens (OGUN) to collaborators
     * @param token The ERC-20 token address to distribute
     */
    function distributeToken(address token) external nonReentrant {
        require(token != address(0), "Invalid token");
        IERC20 erc20 = IERC20(token);
        uint256 balance = erc20.balanceOf(address(this));
        require(balance > 0, "No token balance");

        for (uint256 i = 0; i < collaborators.length; i++) {
            uint256 amount = (balance * collaborators[i].bps) / 10000;
            if (amount > 0) {
                erc20.safeTransfer(collaborators[i].wallet, amount);
                emit CollaboratorPaid(collaborators[i].wallet, amount, collaborators[i].bps);
            }
        }

        emit TokenDistributed(token, balance, collaborators.length);
    }

    // --- Split Management (with timelock) ---

    /**
     * @notice Propose new collaborator splits (48-hour delay before execution)
     * @dev Timelock prevents creator from front-running a sale by changing splits
     */
    function proposeSplitUpdate(
        address[] calldata _wallets,
        uint256[] calldata _bps
    ) external onlyCreator {
        require(_wallets.length == _bps.length, "Length mismatch");
        require(_wallets.length > 0 && _wallets.length <= 10, "1-10 collaborators");

        // Clear previous pending
        delete pendingSplits;

        uint256 total = 0;
        for (uint256 i = 0; i < _wallets.length; i++) {
            require(_wallets[i] != address(0), "Invalid wallet");
            require(_bps[i] > 0, "Zero bps");
            pendingSplits.push(Collaborator(_wallets[i], _bps[i]));
            total += _bps[i];
        }
        require(total == 10000, "Splits must total 100%");

        pendingSplitsTimestamp = block.timestamp + SPLIT_UPDATE_DELAY;

        emit SplitUpdateProposed(pendingSplitsTimestamp);
    }

    /**
     * @notice Execute a pending split update after the timelock expires
     */
    function executeSplitUpdate() external onlyCreator {
        require(pendingSplitsTimestamp > 0, "No pending update");
        require(block.timestamp >= pendingSplitsTimestamp, "Timelock active");

        // Distribute any existing balance before changing splits
        if (address(this).balance > 0) {
            this.distributeNative();
        }

        // Apply new splits
        delete collaborators;
        uint256 total = 0;
        for (uint256 i = 0; i < pendingSplits.length; i++) {
            collaborators.push(pendingSplits[i]);
            total += pendingSplits[i].bps;
        }
        totalBps = total;

        // Clear pending
        delete pendingSplits;
        pendingSplitsTimestamp = 0;

        emit SplitUpdateExecuted(collaborators.length, total);
    }

    // --- View Functions ---

    function getCollaborators() external view returns (address[] memory wallets, uint256[] memory bps) {
        wallets = new address[](collaborators.length);
        bps = new uint256[](collaborators.length);
        for (uint256 i = 0; i < collaborators.length; i++) {
            wallets[i] = collaborators[i].wallet;
            bps[i] = collaborators[i].bps;
        }
    }

    function collaboratorCount() external view returns (uint256) {
        return collaborators.length;
    }

    function hasPendingUpdate() external view returns (bool) {
        return pendingSplitsTimestamp > 0;
    }

    function getPendingSplits() external view returns (address[] memory wallets, uint256[] memory bps, uint256 executeAfter) {
        wallets = new address[](pendingSplits.length);
        bps = new uint256[](pendingSplits.length);
        for (uint256 i = 0; i < pendingSplits.length; i++) {
            wallets[i] = pendingSplits[i].wallet;
            bps[i] = pendingSplits[i].bps;
        }
        executeAfter = pendingSplitsTimestamp;
    }
}

/**
 * @title RoyaltySplitterFactory
 * @notice Factory to deploy RoyaltySplitter proxies for any SoundChain NFT.
 * Users call createSplitter() to deploy a new splitter for their edition,
 * then update their NFT's royaltyReceiver to the splitter address.
 */
contract RoyaltySplitterFactory {
    event SplitterDeployed(
        address indexed splitter,
        address indexed creator,
        string scid,
        uint256 editionId
    );

    // Track all deployed splitters
    mapping(address => address[]) public creatorSplitters;
    mapping(string => address) public scidToSplitter; // SCid → splitter address
    address[] public allSplitters;

    /**
     * @notice Deploy a new RoyaltySplitter for an NFT edition
     * @param _scid SoundChain ID (e.g., SC-POL-D038-2600003)
     * @param _editionId Edition number in Soundchain721Editions
     * @param _wallets Collaborator wallet addresses
     * @param _bps Collaborator basis points (must total 10000)
     */
    function createSplitter(
        string calldata _scid,
        uint256 _editionId,
        address[] calldata _wallets,
        uint256[] calldata _bps
    ) external returns (address) {
        require(scidToSplitter[_scid] == address(0), "Splitter already exists for this SCid");

        RoyaltySplitter splitter = new RoyaltySplitter(
            msg.sender,
            _scid,
            _editionId,
            _wallets,
            _bps
        );

        address splitterAddr = address(splitter);
        creatorSplitters[msg.sender].push(splitterAddr);
        scidToSplitter[_scid] = splitterAddr;
        allSplitters.push(splitterAddr);

        emit SplitterDeployed(splitterAddr, msg.sender, _scid, _editionId);

        return splitterAddr;
    }

    function getCreatorSplitters(address _creator) external view returns (address[] memory) {
        return creatorSplitters[_creator];
    }

    function splitterCount() external view returns (uint256) {
        return allSplitters.length;
    }
}
