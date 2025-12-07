// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title SoundchainNFTBridge
 * @notice Cross-chain NFT bridge for SoundChain music NFTs
 * @dev Locks NFTs on source chain, mints wrapped version on destination
 *
 * Bridge Flow:
 * 1. User locks NFT on source chain (e.g., Polygon)
 * 2. Bridge emits LockEvent with metadata
 * 3. Relayer picks up event and calls mint on destination chain
 * 4. Wrapped NFT minted on destination (e.g., Ethereum)
 *
 * For ZetaChain integration, this contract works with SoundchainOmnichain
 * to enable seamless cross-chain NFT transfers via the gateway.
 */
contract SoundchainNFTBridge is Ownable, ReentrancyGuard, Pausable, IERC721Receiver {
    using SafeERC20 for IERC20;

    // ============ Events ============

    event NFTLocked(
        uint256 indexed sourceChainId,
        uint256 indexed targetChainId,
        address indexed nftContract,
        uint256 tokenId,
        address owner,
        string tokenURI,
        bytes32 bridgeId
    );

    event NFTUnlocked(
        bytes32 indexed bridgeId,
        address indexed nftContract,
        uint256 tokenId,
        address recipient
    );

    event WrappedNFTMinted(
        bytes32 indexed bridgeId,
        uint256 indexed sourceChainId,
        address indexed recipient,
        uint256 newTokenId
    );

    event WrappedNFTBurned(
        bytes32 indexed bridgeId,
        uint256 tokenId,
        address owner
    );

    event RelayerUpdated(address indexed relayer, bool authorized);

    event BridgeFeeUpdated(uint256 oldFee, uint256 newFee);

    // ============ Structs ============

    struct BridgeRequest {
        uint256 sourceChainId;
        uint256 targetChainId;
        address nftContract;
        uint256 tokenId;
        address owner;
        string tokenURI;
        uint256 timestamp;
        bool completed;
    }

    struct WrappedNFTInfo {
        uint256 sourceChainId;
        address originalContract;
        uint256 originalTokenId;
        bytes32 bridgeId;
    }

    // ============ State Variables ============

    /// @notice Chain ID of this network
    uint256 public immutable chainId;

    /// @notice Fee collector contract address
    address public feeCollector;

    /// @notice Bridge fee in native currency
    uint256 public bridgeFee;

    /// @notice Authorized relayers
    mapping(address => bool) public relayers;

    /// @notice Bridge requests by ID
    mapping(bytes32 => BridgeRequest) public bridgeRequests;

    /// @notice Locked NFTs: nftContract => tokenId => bridgeId
    mapping(address => mapping(uint256 => bytes32)) public lockedNFTs;

    /// @notice Wrapped NFT info: wrappedTokenId => info
    mapping(uint256 => WrappedNFTInfo) public wrappedNFTs;

    /// @notice Nonce for bridge ID generation
    uint256 private _nonce;

    /// @notice Supported destination chains
    mapping(uint256 => bool) public supportedChains;

    /// @notice Original NFT contracts that can be bridged
    mapping(address => bool) public whitelistedContracts;

    // ============ Constructor ============

    constructor(
        uint256 _chainId,
        address _feeCollector,
        uint256 _bridgeFee
    ) {
        chainId = _chainId;
        feeCollector = _feeCollector;
        bridgeFee = _bridgeFee;

        // Whitelist Soundchain NFT contracts
        // Add your contract addresses here after deployment

        // Enable supported chains
        supportedChains[1] = true;      // Ethereum
        supportedChains[137] = true;    // Polygon
        supportedChains[43114] = true;  // Avalanche
        supportedChains[42161] = true;  // Arbitrum
        supportedChains[10] = true;     // Optimism
        supportedChains[8453] = true;   // Base
        supportedChains[7000] = true;   // ZetaChain
    }

    // ============ Modifiers ============

    modifier onlyRelayer() {
        require(relayers[msg.sender], "Not authorized relayer");
        _;
    }

    modifier validChain(uint256 targetChainId) {
        require(supportedChains[targetChainId], "Unsupported chain");
        require(targetChainId != chainId, "Cannot bridge to same chain");
        _;
    }

    modifier validContract(address nftContract) {
        require(whitelistedContracts[nftContract], "Contract not whitelisted");
        _;
    }

    // ============ Bridge Functions ============

    /**
     * @notice Lock NFT and initiate bridge to another chain
     * @param nftContract Address of the NFT contract
     * @param tokenId Token ID to bridge
     * @param targetChainId Destination chain ID
     * @param tokenURI Token metadata URI
     * @return bridgeId Unique identifier for this bridge request
     */
    function lockAndBridge(
        address nftContract,
        uint256 tokenId,
        uint256 targetChainId,
        string calldata tokenURI
    ) external payable
      nonReentrant
      whenNotPaused
      validChain(targetChainId)
      validContract(nftContract)
      returns (bytes32 bridgeId)
    {
        require(msg.value >= bridgeFee, "Insufficient bridge fee");

        // Verify ownership
        require(
            IERC721(nftContract).ownerOf(tokenId) == msg.sender,
            "Not token owner"
        );

        // Generate unique bridge ID
        bridgeId = keccak256(
            abi.encodePacked(
                chainId,
                targetChainId,
                nftContract,
                tokenId,
                msg.sender,
                block.timestamp,
                _nonce++
            )
        );

        // Lock NFT
        IERC721(nftContract).safeTransferFrom(msg.sender, address(this), tokenId);

        // Store bridge request
        bridgeRequests[bridgeId] = BridgeRequest({
            sourceChainId: chainId,
            targetChainId: targetChainId,
            nftContract: nftContract,
            tokenId: tokenId,
            owner: msg.sender,
            tokenURI: tokenURI,
            timestamp: block.timestamp,
            completed: false
        });

        lockedNFTs[nftContract][tokenId] = bridgeId;

        // Collect fee
        if (bridgeFee > 0 && feeCollector != address(0)) {
            (bool success, ) = feeCollector.call{value: bridgeFee}("");
            require(success, "Fee transfer failed");
        }

        // Return excess
        if (msg.value > bridgeFee) {
            (bool refundSuccess, ) = msg.sender.call{value: msg.value - bridgeFee}("");
            require(refundSuccess, "Refund failed");
        }

        emit NFTLocked(
            chainId,
            targetChainId,
            nftContract,
            tokenId,
            msg.sender,
            tokenURI,
            bridgeId
        );

        return bridgeId;
    }

    /**
     * @notice Unlock NFT after bridge return (relayer only)
     * @param bridgeId Bridge request ID
     * @param recipient Address to receive the NFT
     */
    function unlockNFT(
        bytes32 bridgeId,
        address recipient
    ) external onlyRelayer nonReentrant whenNotPaused {
        BridgeRequest storage request = bridgeRequests[bridgeId];

        require(request.sourceChainId == chainId, "Wrong source chain");
        require(!request.completed, "Already completed");
        require(recipient != address(0), "Invalid recipient");

        request.completed = true;
        delete lockedNFTs[request.nftContract][request.tokenId];

        IERC721(request.nftContract).safeTransferFrom(
            address(this),
            recipient,
            request.tokenId
        );

        emit NFTUnlocked(bridgeId, request.nftContract, request.tokenId, recipient);
    }

    /**
     * @notice Cancel bridge request and return NFT (owner only, before completion)
     * @param bridgeId Bridge request ID
     */
    function cancelBridge(bytes32 bridgeId) external nonReentrant {
        BridgeRequest storage request = bridgeRequests[bridgeId];

        require(request.owner == msg.sender, "Not request owner");
        require(!request.completed, "Already completed");
        require(request.sourceChainId == chainId, "Wrong chain");

        // Allow cancellation after 24 hours if not processed
        require(
            block.timestamp > request.timestamp + 24 hours,
            "Must wait 24 hours"
        );

        request.completed = true;
        delete lockedNFTs[request.nftContract][request.tokenId];

        IERC721(request.nftContract).safeTransferFrom(
            address(this),
            msg.sender,
            request.tokenId
        );

        emit NFTUnlocked(bridgeId, request.nftContract, request.tokenId, msg.sender);
    }

    // ============ Admin Functions ============

    /**
     * @notice Add or remove a relayer
     */
    function setRelayer(address relayer, bool authorized) external onlyOwner {
        relayers[relayer] = authorized;
        emit RelayerUpdated(relayer, authorized);
    }

    /**
     * @notice Update bridge fee
     */
    function setBridgeFee(uint256 newFee) external onlyOwner {
        uint256 oldFee = bridgeFee;
        bridgeFee = newFee;
        emit BridgeFeeUpdated(oldFee, newFee);
    }

    /**
     * @notice Update fee collector
     */
    function setFeeCollector(address newCollector) external onlyOwner {
        require(newCollector != address(0), "Invalid address");
        feeCollector = newCollector;
    }

    /**
     * @notice Enable or disable a chain
     */
    function setSupportedChain(uint256 targetChainId, bool supported) external onlyOwner {
        supportedChains[targetChainId] = supported;
    }

    /**
     * @notice Whitelist or remove an NFT contract
     */
    function setWhitelistedContract(address nftContract, bool whitelisted) external onlyOwner {
        whitelistedContracts[nftContract] = whitelisted;
    }

    /**
     * @notice Pause bridge operations
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @notice Unpause bridge operations
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @notice Emergency NFT recovery (owner only)
     */
    function emergencyRecoverNFT(
        address nftContract,
        uint256 tokenId,
        address to
    ) external onlyOwner {
        IERC721(nftContract).safeTransferFrom(address(this), to, tokenId);
    }

    /**
     * @notice Emergency ETH recovery
     */
    function emergencyRecoverETH(address to, uint256 amount) external onlyOwner {
        (bool success, ) = to.call{value: amount}("");
        require(success, "Transfer failed");
    }

    // ============ View Functions ============

    /**
     * @notice Get bridge request details
     */
    function getBridgeRequest(bytes32 bridgeId)
        external
        view
        returns (BridgeRequest memory)
    {
        return bridgeRequests[bridgeId];
    }

    /**
     * @notice Check if NFT is locked
     */
    function isNFTLocked(address nftContract, uint256 tokenId)
        external
        view
        returns (bool)
    {
        return lockedNFTs[nftContract][tokenId] != bytes32(0);
    }

    /**
     * @notice Get locked NFT bridge ID
     */
    function getLockedNFTBridgeId(address nftContract, uint256 tokenId)
        external
        view
        returns (bytes32)
    {
        return lockedNFTs[nftContract][tokenId];
    }

    // ============ ERC721 Receiver ============

    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external pure override returns (bytes4) {
        return this.onERC721Received.selector;
    }

    // ============ Receive ============

    receive() external payable {}
}
