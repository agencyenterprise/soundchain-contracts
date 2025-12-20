// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title ChainConnector
 * @notice Lightweight connector deployed on each supported chain
 * @dev Relays messages to/from ZetaChain OmnichainRouter
 *
 * This is the "spoke" contract - one deployed per chain.
 * It's lightweight and only handles:
 * - Receiving user payments
 * - Sending messages to ZetaChain via Gateway
 * - Receiving messages from ZetaChain
 * - Executing local actions (mint, transfer, etc.)
 *
 * Deployment: One per chain (Ethereum, Base, Arbitrum, etc.)
 * Total: ~23 identical contracts with different chain configs
 */
contract ChainConnector is
    Initializable,
    UUPSUpgradeable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable
{
    using SafeERC20 for IERC20;

    // ============ Events ============

    event MessageSent(
        bytes32 indexed messageId,
        uint256 targetChain,
        uint8 messageType,
        address sender,
        uint256 amount
    );

    event MessageReceived(
        bytes32 indexed messageId,
        uint256 sourceChain,
        uint8 messageType,
        address recipient,
        uint256 amount
    );

    event ActionExecuted(
        bytes32 indexed messageId,
        uint8 actionType,
        bool success
    );

    // ============ Enums ============

    enum MessageType {
        PURCHASE,
        BUNDLE_PURCHASE,
        SWEEP,
        SWAP,
        ROYALTY_CLAIM,
        BRIDGE_NFT,
        AIRDROP,
        SCID_REGISTER,
        MINT_REQUEST
    }

    // ============ Structs ============

    struct PendingMessage {
        bytes32 messageId;
        MessageType messageType;
        address sender;
        uint256 amount;
        address token;
        bytes payload;
        uint256 timestamp;
        bool executed;
    }

    // ============ State Variables ============

    /// @notice This chain's ID
    uint256 public chainId;

    /// @notice This chain's name
    string public chainName;

    /// @notice ZetaChain Gateway address (for cross-chain messaging)
    address public gateway;

    /// @notice OmnichainRouter address on ZetaChain
    address public omnichainRouter;

    /// @notice ZetaChain chain ID
    uint256 public constant ZETACHAIN_ID = 7000;

    /// @notice Polygon chain ID (primary NFT chain)
    uint256 public constant POLYGON_ID = 137;

    /// @notice Pending messages
    mapping(bytes32 => PendingMessage) public pendingMessages;

    /// @notice Supported tokens on this chain
    mapping(address => bool) public supportedTokens;

    /// @notice Token to ZRC-20 mapping (for ZetaChain conversion)
    mapping(address => address) public tokenToZRC20;

    /// @notice Message nonce
    uint256 private _messageNonce;

    /// @notice Whitelisted executors (can execute received messages)
    mapping(address => bool) public executors;

    // ============ Initializer ============

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initialize the connector
     * @param _chainId This chain's ID
     * @param _chainName This chain's name
     * @param _gateway ZetaChain Gateway address
     * @param _omnichainRouter OmnichainRouter address on ZetaChain
     */
    function initialize(
        uint256 _chainId,
        string calldata _chainName,
        address _gateway,
        address _omnichainRouter
    ) external initializer {
        __Ownable_init();
        __ReentrancyGuard_init();
        __Pausable_init();
        __UUPSUpgradeable_init();

        chainId = _chainId;
        chainName = _chainName;
        gateway = _gateway;
        omnichainRouter = _omnichainRouter;

        // Owner is an executor
        executors[msg.sender] = true;

        // Native token is always supported
        supportedTokens[address(0)] = true;
    }

    // ============ Modifiers ============

    modifier onlyGateway() {
        require(msg.sender == gateway, "Only gateway");
        _;
    }

    modifier onlyExecutor() {
        require(executors[msg.sender] || msg.sender == owner(), "Not executor");
        _;
    }

    // ============ User-Facing Functions ============

    /**
     * @notice Request NFT purchase on another chain
     * @param targetChain Chain where NFT exists
     * @param nftContract NFT contract address
     * @param tokenId Token ID to purchase
     * @param paymentToken Token to pay with (address(0) for native)
     */
    function requestPurchase(
        uint256 targetChain,
        address nftContract,
        uint256 tokenId,
        address paymentToken
    ) external payable nonReentrant whenNotPaused returns (bytes32 messageId) {
        uint256 amount = _collectPayment(paymentToken);

        messageId = _generateMessageId(MessageType.PURCHASE);

        bytes memory payload = abi.encode(
            targetChain,
            nftContract,
            tokenId,
            msg.sender // recipient
        );

        _sendToZetaChain(messageId, MessageType.PURCHASE, amount, paymentToken, payload);

        emit MessageSent(messageId, ZETACHAIN_ID, uint8(MessageType.PURCHASE), msg.sender, amount);

        return messageId;
    }

    /**
     * @notice Request bundle purchase
     * @param bundleId Bundle ID on marketplace
     * @param paymentToken Token to pay with
     */
    function requestBundlePurchase(
        bytes32 bundleId,
        address paymentToken
    ) external payable nonReentrant whenNotPaused returns (bytes32 messageId) {
        uint256 amount = _collectPayment(paymentToken);

        messageId = _generateMessageId(MessageType.BUNDLE_PURCHASE);

        bytes memory payload = abi.encode(bundleId, msg.sender);

        _sendToZetaChain(messageId, MessageType.BUNDLE_PURCHASE, amount, paymentToken, payload);

        emit MessageSent(messageId, ZETACHAIN_ID, uint8(MessageType.BUNDLE_PURCHASE), msg.sender, amount);

        return messageId;
    }

    /**
     * @notice Request floor sweep
     * @param targetChain Chain to sweep
     * @param nftContract NFT contract
     * @param maxItems Maximum items to sweep
     * @param maxPricePerItem Maximum price per item
     * @param paymentToken Token to pay with
     */
    function requestSweep(
        uint256 targetChain,
        address nftContract,
        uint256 maxItems,
        uint256 maxPricePerItem,
        address paymentToken
    ) external payable nonReentrant whenNotPaused returns (bytes32 messageId) {
        uint256 amount = _collectPayment(paymentToken);

        messageId = _generateMessageId(MessageType.SWEEP);

        bytes memory payload = abi.encode(
            targetChain,
            nftContract,
            maxItems,
            maxPricePerItem,
            msg.sender
        );

        _sendToZetaChain(messageId, MessageType.SWEEP, amount, paymentToken, payload);

        emit MessageSent(messageId, ZETACHAIN_ID, uint8(MessageType.SWEEP), msg.sender, amount);

        return messageId;
    }

    /**
     * @notice Request mint on user's chosen chain
     * @dev User selects their preferred chain for minting
     * @param targetChain Chain to mint on (usually Polygon)
     * @param metadataURI Token metadata URI
     * @param royaltyPercentage Royalty percentage (basis points)
     * @param editionSize Edition size (1 for single, up to 1000 for editions)
     * @param paymentToken Token to pay mint fee with
     */
    function requestMint(
        uint256 targetChain,
        string calldata metadataURI,
        uint8 royaltyPercentage,
        uint256 editionSize,
        address paymentToken
    ) external payable nonReentrant whenNotPaused returns (bytes32 messageId) {
        uint256 amount = _collectPayment(paymentToken);

        messageId = _generateMessageId(MessageType.MINT_REQUEST);

        bytes memory payload = abi.encode(
            targetChain,
            metadataURI,
            royaltyPercentage,
            editionSize,
            msg.sender // creator/recipient
        );

        _sendToZetaChain(messageId, MessageType.MINT_REQUEST, amount, paymentToken, payload);

        emit MessageSent(messageId, ZETACHAIN_ID, uint8(MessageType.MINT_REQUEST), msg.sender, amount);

        return messageId;
    }

    /**
     * @notice Claim royalties to this chain
     * @param preferredToken Token to receive royalties in
     */
    function claimRoyalties(
        address preferredToken
    ) external nonReentrant whenNotPaused returns (bytes32 messageId) {
        messageId = _generateMessageId(MessageType.ROYALTY_CLAIM);

        bytes memory payload = abi.encode(
            chainId,
            preferredToken,
            msg.sender
        );

        _sendToZetaChain(messageId, MessageType.ROYALTY_CLAIM, 0, address(0), payload);

        emit MessageSent(messageId, ZETACHAIN_ID, uint8(MessageType.ROYALTY_CLAIM), msg.sender, 0);

        return messageId;
    }

    // ============ Receive Functions (from ZetaChain) ============

    /**
     * @notice Receive cross-chain message from ZetaChain
     * @dev Called by ZetaChain Gateway
     */
    function onReceive(
        bytes32 messageId,
        uint256 sourceChain,
        address sender,
        uint256 amount,
        address token,
        bytes calldata payload
    ) external onlyGateway nonReentrant {
        // Decode message type from payload
        (uint8 messageType, bytes memory data) = abi.decode(payload, (uint8, bytes));

        pendingMessages[messageId] = PendingMessage({
            messageId: messageId,
            messageType: MessageType(messageType),
            sender: sender,
            amount: amount,
            token: token,
            payload: data,
            timestamp: block.timestamp,
            executed: false
        });

        emit MessageReceived(messageId, sourceChain, messageType, sender, amount);

        // Auto-execute if possible
        _executeMessage(messageId);
    }

    /**
     * @notice Execute a pending message
     * @dev Can be called by executors for manual execution
     */
    function executeMessage(bytes32 messageId) external onlyExecutor {
        _executeMessage(messageId);
    }

    // ============ Internal Functions ============

    function _collectPayment(address token) internal returns (uint256) {
        if (token == address(0)) {
            require(msg.value > 0, "No native payment");
            return msg.value;
        } else {
            require(supportedTokens[token], "Token not supported");
            uint256 amount = IERC20(token).allowance(msg.sender, address(this));
            require(amount > 0, "No token allowance");
            IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
            return amount;
        }
    }

    function _generateMessageId(MessageType messageType) internal returns (bytes32) {
        return keccak256(
            abi.encodePacked(
                chainId,
                msg.sender,
                messageType,
                block.timestamp,
                _messageNonce++
            )
        );
    }

    function _sendToZetaChain(
        bytes32 messageId,
        MessageType messageType,
        uint256 amount,
        address token,
        bytes memory payload
    ) internal {
        // In production, this calls the ZetaChain Gateway
        // gateway.call{value: amount}(...)

        // For now, store for off-chain indexer
        pendingMessages[messageId] = PendingMessage({
            messageId: messageId,
            messageType: messageType,
            sender: msg.sender,
            amount: amount,
            token: token,
            payload: payload,
            timestamp: block.timestamp,
            executed: false
        });
    }

    function _executeMessage(bytes32 messageId) internal {
        PendingMessage storage message = pendingMessages[messageId];
        require(!message.executed, "Already executed");

        bool success = false;

        // Execute based on message type
        if (message.messageType == MessageType.ROYALTY_CLAIM) {
            // Transfer tokens to recipient
            (,, address recipient) = abi.decode(message.payload, (uint256, address, address));
            if (message.token == address(0)) {
                (success, ) = recipient.call{value: message.amount}("");
            } else {
                IERC20(message.token).safeTransfer(recipient, message.amount);
                success = true;
            }
        }
        // Add more message type handlers as needed

        message.executed = true;

        emit ActionExecuted(messageId, uint8(message.messageType), success);
    }

    // ============ Admin Functions ============

    function setGateway(address _gateway) external onlyOwner {
        gateway = _gateway;
    }

    function setOmnichainRouter(address _router) external onlyOwner {
        omnichainRouter = _router;
    }

    function setSupportedToken(address token, bool supported) external onlyOwner {
        supportedTokens[token] = supported;
    }

    function setTokenZRC20(address token, address zrc20) external onlyOwner {
        tokenToZRC20[token] = zrc20;
    }

    function setExecutor(address executor, bool authorized) external onlyOwner {
        executors[executor] = authorized;
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function emergencyWithdraw(address token, uint256 amount) external onlyOwner {
        if (token == address(0)) {
            (bool success, ) = owner().call{value: amount}("");
            require(success, "ETH withdrawal failed");
        } else {
            IERC20(token).safeTransfer(owner(), amount);
        }
    }

    // ============ View Functions ============

    function getMessage(bytes32 messageId) external view returns (PendingMessage memory) {
        return pendingMessages[messageId];
    }

    function isTokenSupported(address token) external view returns (bool) {
        return supportedTokens[token];
    }

    function getChainInfo() external view returns (uint256, string memory) {
        return (chainId, chainName);
    }

    // ============ UUPS ============

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    // ============ Receive ============

    receive() external payable {}
}
