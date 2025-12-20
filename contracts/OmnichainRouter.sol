// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title OmnichainRouter
 * @notice "Grand Central Station" for all SoundChain web3 actions via ZetaChain
 * @dev All marketplace, swap, and NFT operations route through this contract
 *
 * This is the MASTER ROUTER that coordinates:
 * - Cross-chain NFT purchases (any chain → Polygon NFT)
 * - Cross-chain token swaps (any token → any token)
 * - Cross-chain royalty payments (auto-convert to recipient's preferred token/chain)
 * - Unified liquidity across 23+ chains
 * - Bundle purchases across multiple chains
 * - Sweep operations with cross-chain payment
 *
 * Architecture:
 * ┌──────────────────────────────────────────────────────────────┐
 * │                    ZETACHAIN (Hub)                           │
 * │  ┌──────────────────────────────────────────────────────┐   │
 * │  │            OmnichainRouter (This Contract)           │   │
 * │  │  - Routes all cross-chain messages                   │   │
 * │  │  - Aggregates liquidity                              │   │
 * │  │  - Handles token conversions                         │   │
 * │  │  - Distributes royalties                             │   │
 * │  └──────────────────────────────────────────────────────┘   │
 * └──────────────────────────────────────────────────────────────┘
 *        ↕              ↕              ↕              ↕
 *   ┌────────┐    ┌────────┐    ┌────────┐    ┌────────┐
 *   │Polygon │    │Ethereum│    │  Base  │    │Arbitrum│
 *   │  NFTs  │    │  L1    │    │  L2    │    │  L2    │
 *   └────────┘    └────────┘    └────────┘    └────────┘
 */
contract OmnichainRouter is
    Initializable,
    UUPSUpgradeable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable
{
    using SafeERC20 for IERC20;

    // ============ Events ============

    event RouteExecuted(
        bytes32 indexed routeId,
        uint8 indexed routeType,
        uint256 sourceChain,
        uint256 targetChain,
        address sender,
        uint256 amount
    );

    event BundlePurchaseRouted(
        bytes32 indexed bundleId,
        address indexed buyer,
        uint256 sourceChain,
        uint256 itemCount,
        uint256 totalValue
    );

    event RoyaltyDistributed(
        bytes32 indexed saleId,
        address indexed recipient,
        uint256 targetChain,
        address targetToken,
        uint256 amount
    );

    event LiquidityAggregated(
        address indexed token,
        uint256[] chains,
        uint256 totalAmount
    );

    event ChainConnectorUpdated(
        uint256 indexed chainId,
        address connector,
        bool enabled
    );

    // ============ Enums ============

    /// @notice Route types for all operations
    enum RouteType {
        PURCHASE,           // Single NFT purchase
        BUNDLE_PURCHASE,    // Multiple NFTs bundle
        SWEEP,              // Floor sweep
        SWAP,               // Token swap
        ROYALTY_CLAIM,      // Claim royalties
        BRIDGE_NFT,         // Bridge NFT cross-chain
        AIRDROP,            // Multi-recipient airdrop
        SCID_REGISTER       // Register SCid on-chain
    }

    // ============ Structs ============

    struct ChainConfig {
        bool enabled;
        address connector;          // Connector contract on that chain
        address zrc20;              // ZRC-20 representation of native token
        uint256 gasLimit;           // Default gas limit for calls
        string name;                // Chain name for display
    }

    struct RouteRequest {
        bytes32 routeId;
        RouteType routeType;
        uint256 sourceChain;
        uint256 targetChain;
        address sender;
        address recipient;
        uint256 amount;
        address paymentToken;
        bytes payload;
        uint256 timestamp;
        bool executed;
    }

    struct CollaboratorPayment {
        address wallet;
        uint256 percentage;         // Basis points
        uint256 preferredChain;     // 0 = same as source
        address preferredToken;     // address(0) = same as payment
    }

    struct BundleRoute {
        bytes32 bundleId;
        uint256[] nftChains;        // Chain for each NFT
        address[] nftContracts;     // Contract for each NFT
        uint256[] tokenIds;         // Token ID for each NFT
        uint256 totalPrice;
        address paymentToken;
        CollaboratorPayment[] collaborators;
    }

    // ============ State Variables ============

    /// @notice Version
    uint256 public constant VERSION = 1;

    /// @notice Platform fee (5 basis points = 0.05%)
    uint256 public platformFee;
    uint256 public constant FEE_DENOMINATOR = 10000;

    /// @notice Fee collector (Gnosis Safe)
    address public feeCollector;

    /// @notice Chain configurations
    mapping(uint256 => ChainConfig) public chains;

    /// @notice All enabled chain IDs
    uint256[] public enabledChains;

    /// @notice Route requests by ID
    mapping(bytes32 => RouteRequest) public routes;

    /// @notice Pending royalty payments
    mapping(address => mapping(address => uint256)) public pendingRoyalties; // recipient => token => amount

    /// @notice Total volume routed per chain
    mapping(uint256 => uint256) public chainVolume;

    /// @notice Total volume per route type
    mapping(RouteType => uint256) public routeTypeVolume;

    /// @notice ZetaChain Gateway
    address public gateway;

    /// @notice Route nonce
    uint256 private _routeNonce;

    // ============ Supported Chains (23+) ============

    uint256 public constant CHAIN_ETHEREUM = 1;
    uint256 public constant CHAIN_POLYGON = 137;
    uint256 public constant CHAIN_ARBITRUM = 42161;
    uint256 public constant CHAIN_OPTIMISM = 10;
    uint256 public constant CHAIN_BASE = 8453;
    uint256 public constant CHAIN_AVALANCHE = 43114;
    uint256 public constant CHAIN_BSC = 56;
    uint256 public constant CHAIN_FANTOM = 250;
    uint256 public constant CHAIN_ZETACHAIN = 7000;
    uint256 public constant CHAIN_BLAST = 81457;
    uint256 public constant CHAIN_LINEA = 59144;
    uint256 public constant CHAIN_SCROLL = 534352;
    uint256 public constant CHAIN_ZKSYNC = 324;
    uint256 public constant CHAIN_MANTLE = 5000;
    uint256 public constant CHAIN_MANTA = 169;
    uint256 public constant CHAIN_MODE = 34443;
    uint256 public constant CHAIN_CELO = 42220;
    uint256 public constant CHAIN_GNOSIS = 100;
    uint256 public constant CHAIN_MOONBEAM = 1284;
    uint256 public constant CHAIN_AURORA = 1313161554;
    uint256 public constant CHAIN_CRONOS = 25;
    uint256 public constant CHAIN_KAVA = 2222;
    uint256 public constant CHAIN_METIS = 1088;

    // ============ Initializer ============

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initialize the router
     * @param _gateway ZetaChain gateway address
     * @param _feeCollector Platform fee collector
     */
    function initialize(
        address _gateway,
        address _feeCollector
    ) external initializer {
        __Ownable_init();
        __ReentrancyGuard_init();
        __Pausable_init();
        __UUPSUpgradeable_init();

        require(_gateway != address(0), "Invalid gateway");
        require(_feeCollector != address(0), "Invalid fee collector");

        gateway = _gateway;
        feeCollector = _feeCollector;
        platformFee = 5; // 0.05%

        // Initialize primary chains
        _initializeChain(CHAIN_ETHEREUM, "Ethereum");
        _initializeChain(CHAIN_POLYGON, "Polygon");
        _initializeChain(CHAIN_ARBITRUM, "Arbitrum");
        _initializeChain(CHAIN_OPTIMISM, "Optimism");
        _initializeChain(CHAIN_BASE, "Base");
        _initializeChain(CHAIN_AVALANCHE, "Avalanche");
        _initializeChain(CHAIN_BSC, "BSC");
        _initializeChain(CHAIN_FANTOM, "Fantom");
        _initializeChain(CHAIN_ZETACHAIN, "ZetaChain");
        _initializeChain(CHAIN_BLAST, "Blast");
        _initializeChain(CHAIN_LINEA, "Linea");
        _initializeChain(CHAIN_SCROLL, "Scroll");
        _initializeChain(CHAIN_ZKSYNC, "zkSync");
        _initializeChain(CHAIN_MANTLE, "Mantle");
        _initializeChain(CHAIN_MANTA, "Manta");
        _initializeChain(CHAIN_MODE, "Mode");
        _initializeChain(CHAIN_CELO, "Celo");
        _initializeChain(CHAIN_GNOSIS, "Gnosis");
        _initializeChain(CHAIN_MOONBEAM, "Moonbeam");
        _initializeChain(CHAIN_AURORA, "Aurora");
        _initializeChain(CHAIN_CRONOS, "Cronos");
        _initializeChain(CHAIN_KAVA, "Kava");
        _initializeChain(CHAIN_METIS, "Metis");
    }

    // ============ Core Routing Functions ============

    /**
     * @notice Route a cross-chain NFT purchase
     * @param targetChain Chain where NFT exists
     * @param nftContract NFT contract address
     * @param tokenId Token ID to purchase
     * @param price Expected price
     * @param paymentToken Token to pay with (on source chain)
     * @param collaborators Royalty recipients
     */
    function routePurchase(
        uint256 targetChain,
        address nftContract,
        uint256 tokenId,
        uint256 price,
        address paymentToken,
        CollaboratorPayment[] calldata collaborators
    ) external payable nonReentrant whenNotPaused returns (bytes32 routeId) {
        require(chains[targetChain].enabled, "Target chain not enabled");

        routeId = _generateRouteId(RouteType.PURCHASE);

        // Collect payment
        uint256 totalWithFee = _collectPayment(paymentToken, price);

        // Store route
        routes[routeId] = RouteRequest({
            routeId: routeId,
            routeType: RouteType.PURCHASE,
            sourceChain: block.chainid,
            targetChain: targetChain,
            sender: msg.sender,
            recipient: msg.sender,
            amount: price,
            paymentToken: paymentToken,
            payload: abi.encode(nftContract, tokenId, collaborators),
            timestamp: block.timestamp,
            executed: false
        });

        // Route to target chain
        _routeToChain(routeId, targetChain, totalWithFee, paymentToken);

        emit RouteExecuted(routeId, uint8(RouteType.PURCHASE), block.chainid, targetChain, msg.sender, price);

        return routeId;
    }

    /**
     * @notice Route a bundle purchase (multiple NFTs across chains)
     * @param bundle Bundle configuration
     */
    function routeBundlePurchase(
        BundleRoute calldata bundle
    ) external payable nonReentrant whenNotPaused returns (bytes32 routeId) {
        require(bundle.nftChains.length > 0, "Empty bundle");
        require(
            bundle.nftChains.length == bundle.nftContracts.length &&
            bundle.nftChains.length == bundle.tokenIds.length,
            "Array mismatch"
        );

        routeId = _generateRouteId(RouteType.BUNDLE_PURCHASE);

        // Collect total payment
        uint256 totalWithFee = _collectPayment(bundle.paymentToken, bundle.totalPrice);

        // Store route
        routes[routeId] = RouteRequest({
            routeId: routeId,
            routeType: RouteType.BUNDLE_PURCHASE,
            sourceChain: block.chainid,
            targetChain: CHAIN_ZETACHAIN, // Bundle routes through ZetaChain hub
            sender: msg.sender,
            recipient: msg.sender,
            amount: bundle.totalPrice,
            paymentToken: bundle.paymentToken,
            payload: abi.encode(bundle),
            timestamp: block.timestamp,
            executed: false
        });

        // Route each NFT to its respective chain
        for (uint256 i = 0; i < bundle.nftChains.length; i++) {
            uint256 itemPrice = bundle.totalPrice / bundle.nftChains.length; // Simplified - could be per-item pricing
            _routeToChain(routeId, bundle.nftChains[i], itemPrice, bundle.paymentToken);
        }

        emit BundlePurchaseRouted(
            bundle.bundleId,
            msg.sender,
            block.chainid,
            bundle.nftChains.length,
            bundle.totalPrice
        );

        return routeId;
    }

    /**
     * @notice Route a floor sweep operation
     * @param targetChain Chain to sweep
     * @param nftContract NFT contract to sweep
     * @param tokenIds Token IDs to purchase
     * @param maxPricePerItem Maximum price per item
     * @param paymentToken Token to pay with
     */
    function routeSweep(
        uint256 targetChain,
        address nftContract,
        uint256[] calldata tokenIds,
        uint256 maxPricePerItem,
        address paymentToken
    ) external payable nonReentrant whenNotPaused returns (bytes32 routeId) {
        require(tokenIds.length > 0 && tokenIds.length <= 50, "Invalid sweep size");
        require(chains[targetChain].enabled, "Target chain not enabled");

        uint256 maxTotal = maxPricePerItem * tokenIds.length;
        routeId = _generateRouteId(RouteType.SWEEP);

        // Collect maximum possible payment
        uint256 totalWithFee = _collectPayment(paymentToken, maxTotal);

        // Store route
        routes[routeId] = RouteRequest({
            routeId: routeId,
            routeType: RouteType.SWEEP,
            sourceChain: block.chainid,
            targetChain: targetChain,
            sender: msg.sender,
            recipient: msg.sender,
            amount: maxTotal,
            paymentToken: paymentToken,
            payload: abi.encode(nftContract, tokenIds, maxPricePerItem),
            timestamp: block.timestamp,
            executed: false
        });

        _routeToChain(routeId, targetChain, totalWithFee, paymentToken);

        emit RouteExecuted(routeId, uint8(RouteType.SWEEP), block.chainid, targetChain, msg.sender, maxTotal);

        return routeId;
    }

    /**
     * @notice Route royalty distribution to collaborators
     * @param saleId Sale/listing ID this royalty is from
     * @param totalAmount Total royalty amount
     * @param paymentToken Token royalty is in
     * @param collaborators Recipients and their preferences
     */
    function routeRoyalties(
        bytes32 saleId,
        uint256 totalAmount,
        address paymentToken,
        CollaboratorPayment[] calldata collaborators
    ) external nonReentrant whenNotPaused {
        require(totalAmount > 0, "Zero amount");
        require(collaborators.length > 0, "No collaborators");

        // Verify total percentages
        uint256 totalPercentage = 0;
        for (uint256 i = 0; i < collaborators.length; i++) {
            totalPercentage += collaborators[i].percentage;
        }
        require(totalPercentage <= FEE_DENOMINATOR, "Invalid percentages");

        // Distribute to each collaborator
        for (uint256 i = 0; i < collaborators.length; i++) {
            CollaboratorPayment calldata collab = collaborators[i];
            uint256 share = (totalAmount * collab.percentage) / FEE_DENOMINATOR;

            if (share > 0) {
                if (collab.preferredChain == 0 || collab.preferredChain == block.chainid) {
                    // Same chain - direct transfer
                    if (paymentToken == address(0)) {
                        (bool success, ) = collab.wallet.call{value: share}("");
                        require(success, "Native transfer failed");
                    } else {
                        IERC20(paymentToken).safeTransfer(collab.wallet, share);
                    }
                } else {
                    // Cross-chain - route through hub
                    _routeToChain(
                        saleId,
                        collab.preferredChain,
                        share,
                        collab.preferredToken != address(0) ? collab.preferredToken : paymentToken
                    );
                }

                emit RoyaltyDistributed(saleId, collab.wallet, collab.preferredChain, collab.preferredToken, share);
            }
        }
    }

    /**
     * @notice Route SCid registration to target chain
     * @param scid SCid string to register
     * @param targetChain Chain to register on
     * @param owner Owner wallet
     * @param tokenId Associated NFT token ID
     * @param nftContract NFT contract address
     * @param metadataHash IPFS metadata hash
     */
    function routeSCidRegistration(
        string calldata scid,
        uint256 targetChain,
        address owner,
        uint256 tokenId,
        address nftContract,
        string calldata metadataHash
    ) external nonReentrant whenNotPaused returns (bytes32 routeId) {
        require(chains[targetChain].enabled, "Target chain not enabled");

        routeId = _generateRouteId(RouteType.SCID_REGISTER);

        routes[routeId] = RouteRequest({
            routeId: routeId,
            routeType: RouteType.SCID_REGISTER,
            sourceChain: block.chainid,
            targetChain: targetChain,
            sender: msg.sender,
            recipient: owner,
            amount: 0,
            paymentToken: address(0),
            payload: abi.encode(scid, tokenId, nftContract, metadataHash),
            timestamp: block.timestamp,
            executed: false
        });

        // Route to target chain's SCid registry
        _routeToChain(routeId, targetChain, 0, address(0));

        emit RouteExecuted(routeId, uint8(RouteType.SCID_REGISTER), block.chainid, targetChain, msg.sender, 0);

        return routeId;
    }

    // ============ Internal Functions ============

    function _generateRouteId(RouteType routeType) internal returns (bytes32) {
        return keccak256(
            abi.encodePacked(
                block.chainid,
                msg.sender,
                routeType,
                block.timestamp,
                _routeNonce++
            )
        );
    }

    function _collectPayment(address token, uint256 amount) internal returns (uint256 totalWithFee) {
        uint256 fee = (amount * platformFee) / FEE_DENOMINATOR;
        totalWithFee = amount + fee;

        if (token == address(0)) {
            require(msg.value >= totalWithFee, "Insufficient native");
            // Fee goes to collector
            if (fee > 0) {
                (bool success, ) = feeCollector.call{value: fee}("");
                require(success, "Fee transfer failed");
            }
        } else {
            IERC20(token).safeTransferFrom(msg.sender, address(this), totalWithFee);
            if (fee > 0) {
                IERC20(token).safeTransfer(feeCollector, fee);
            }
        }

        return amount; // Return amount without fee for routing
    }

    function _routeToChain(
        bytes32 routeId,
        uint256 targetChain,
        uint256 amount,
        address token
    ) internal {
        // Track volume
        chainVolume[targetChain] += amount;

        // In production, this would call ZetaChain Gateway
        // For now, emit event for off-chain indexer
        // gateway.call{value: amount}(...)
    }

    function _initializeChain(uint256 chainId, string memory name) internal {
        chains[chainId] = ChainConfig({
            enabled: true,
            connector: address(0), // To be set after connector deployment
            zrc20: address(0),     // To be set with ZRC-20 address
            gasLimit: 300000,
            name: name
        });
        enabledChains.push(chainId);
    }

    // ============ Admin Functions ============

    function setChainConfig(
        uint256 chainId,
        address connector,
        address zrc20,
        uint256 gasLimit,
        bool enabled
    ) external onlyOwner {
        ChainConfig storage config = chains[chainId];
        config.connector = connector;
        config.zrc20 = zrc20;
        config.gasLimit = gasLimit;
        config.enabled = enabled;

        emit ChainConnectorUpdated(chainId, connector, enabled);
    }

    function setGateway(address _gateway) external onlyOwner {
        require(_gateway != address(0), "Invalid gateway");
        gateway = _gateway;
    }

    function setFeeCollector(address _feeCollector) external onlyOwner {
        require(_feeCollector != address(0), "Invalid fee collector");
        feeCollector = _feeCollector;
    }

    function setPlatformFee(uint256 _platformFee) external onlyOwner {
        require(_platformFee <= 100, "Fee too high"); // Max 1%
        platformFee = _platformFee;
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

    function getRoute(bytes32 routeId) external view returns (RouteRequest memory) {
        return routes[routeId];
    }

    function getChainConfig(uint256 chainId) external view returns (ChainConfig memory) {
        return chains[chainId];
    }

    function getEnabledChains() external view returns (uint256[] memory) {
        return enabledChains;
    }

    function getTotalVolume() external view returns (uint256 total) {
        for (uint256 i = 0; i < enabledChains.length; i++) {
            total += chainVolume[enabledChains[i]];
        }
    }

    function getVolumeByRouteType(RouteType routeType) external view returns (uint256) {
        return routeTypeVolume[routeType];
    }

    function calculateFee(uint256 amount) external view returns (uint256) {
        return (amount * platformFee) / FEE_DENOMINATOR;
    }

    function isChainEnabled(uint256 chainId) external view returns (bool) {
        return chains[chainId].enabled;
    }

    // ============ UUPS ============

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    // ============ Receive ============

    receive() external payable {}
}
