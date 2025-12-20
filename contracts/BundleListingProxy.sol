// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title BundleListingProxy
 * @notice Advanced bundle listing system - unique to SoundChain
 * @dev No other marketplace has this! Create and sell curated NFT collections.
 *
 * Features unique to SoundChain:
 * - Cross-chain bundles (NFTs from multiple chains in one listing)
 * - Themed collections (albums, EP bundles, artist collections)
 * - Tiered bundles (Bronze/Silver/Gold/Platinum editions)
 * - Time-limited bundles (flash sales, limited editions)
 * - Dynamic pricing (price changes based on demand)
 * - Collaborator bundles (multiple artists, split royalties)
 *
 * Bundle Types:
 * 1. ALBUM - Full album with all tracks
 * 2. EP - Extended play (4-6 tracks)
 * 3. COLLECTION - Curated artist collection
 * 4. COLLABORATION - Multi-artist bundle
 * 5. LIMITED_EDITION - Time/quantity limited
 * 6. CROSS_CHAIN - NFTs from multiple chains
 */
contract BundleListingProxy is
    Initializable,
    UUPSUpgradeable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable
{
    using SafeERC20 for IERC20;

    // ============ Events ============

    event BundleCreated(
        bytes32 indexed bundleId,
        address indexed seller,
        BundleType bundleType,
        uint256 itemCount,
        uint256 price
    );

    event BundlePurchased(
        bytes32 indexed bundleId,
        address indexed buyer,
        address paymentToken,
        uint256 price,
        uint256 sourceChain
    );

    event BundleUpdated(
        bytes32 indexed bundleId,
        uint256 newPrice,
        uint256 newExpiry
    );

    event BundleCancelled(bytes32 indexed bundleId);

    event TierPurchased(
        bytes32 indexed bundleId,
        address indexed buyer,
        BundleTier tier,
        uint256 price
    );

    event CollaboratorAdded(
        bytes32 indexed bundleId,
        address indexed collaborator,
        uint256 sharePercentage
    );

    // ============ Enums ============

    enum BundleType {
        ALBUM,
        EP,
        COLLECTION,
        COLLABORATION,
        LIMITED_EDITION,
        CROSS_CHAIN
    }

    enum BundleTier {
        STANDARD,
        BRONZE,
        SILVER,
        GOLD,
        PLATINUM,
        DIAMOND
    }

    // ============ Structs ============

    struct BundleItem {
        uint256 chainId;            // Chain where NFT exists
        address nftContract;        // NFT contract address
        uint256 tokenId;            // Token ID
        bool isERC1155;             // ERC1155 or ERC721
        uint256 amount;             // Amount for ERC1155
    }

    struct Collaborator {
        address wallet;
        uint256 sharePercentage;    // Basis points (100 = 1%)
        uint256 preferredChain;     // 0 = same chain
        address preferredToken;     // address(0) = same as payment
    }

    struct TierConfig {
        uint256 price;              // Price for this tier
        uint256 maxSupply;          // Max purchases at this tier
        uint256 sold;               // Number sold at this tier
        string[] bonusItems;        // Bonus content URIs (exclusive tracks, etc.)
        bool enabled;
    }

    struct Bundle {
        bytes32 bundleId;
        address seller;
        BundleType bundleType;
        string name;
        string description;
        string coverImageURI;
        BundleItem[] items;
        Collaborator[] collaborators;
        mapping(BundleTier => TierConfig) tiers;
        address[] acceptedTokens;
        uint256 basePrice;
        uint256 createdAt;
        uint256 expiresAt;
        uint256 totalSold;
        uint256 maxSupply;          // 0 = unlimited
        bool active;
        bool isCrossChain;
    }

    // ============ State Variables ============

    /// @notice Version
    uint256 public constant VERSION = 1;

    /// @notice Platform fee (50 basis points = 0.5%)
    uint256 public platformFee;
    uint256 public constant FEE_DENOMINATOR = 10000;

    /// @notice Fee collector
    address public feeCollector;

    /// @notice OmnichainRouter for cross-chain bundles
    address public omnichainRouter;

    /// @notice Bundles by ID
    mapping(bytes32 => Bundle) internal bundles;

    /// @notice Bundle existence check
    mapping(bytes32 => bool) public bundleExists;

    /// @notice Seller's bundles
    mapping(address => bytes32[]) public sellerBundles;

    /// @notice Bundle nonce
    uint256 private _bundleNonce;

    /// @notice Featured bundles
    bytes32[] public featuredBundles;

    // ============ Initializer ============

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _feeCollector,
        uint256 _platformFee,
        address _omnichainRouter
    ) external initializer {
        __Ownable_init();
        __ReentrancyGuard_init();
        __Pausable_init();
        __UUPSUpgradeable_init();

        feeCollector = _feeCollector;
        platformFee = _platformFee;
        omnichainRouter = _omnichainRouter;
    }

    // ============ Bundle Creation ============

    /**
     * @notice Create a new bundle listing
     * @param bundleType Type of bundle
     * @param name Bundle name
     * @param description Bundle description
     * @param coverImageURI Cover image IPFS URI
     * @param items Array of NFTs in the bundle
     * @param acceptedTokens Tokens accepted for payment
     * @param basePrice Base price for standard tier
     * @param duration Listing duration in seconds
     * @param maxSupply Maximum bundles to sell (0 = unlimited)
     */
    function createBundle(
        BundleType bundleType,
        string calldata name,
        string calldata description,
        string calldata coverImageURI,
        BundleItem[] calldata items,
        address[] calldata acceptedTokens,
        uint256 basePrice,
        uint256 duration,
        uint256 maxSupply
    ) external nonReentrant whenNotPaused returns (bytes32 bundleId) {
        require(items.length > 0 && items.length <= 100, "Invalid item count");
        require(acceptedTokens.length > 0, "No accepted tokens");
        require(basePrice > 0, "Invalid price");
        require(duration > 0 && duration <= 365 days, "Invalid duration");

        bundleId = _generateBundleId();

        Bundle storage bundle = bundles[bundleId];
        bundle.bundleId = bundleId;
        bundle.seller = msg.sender;
        bundle.bundleType = bundleType;
        bundle.name = name;
        bundle.description = description;
        bundle.coverImageURI = coverImageURI;
        bundle.acceptedTokens = acceptedTokens;
        bundle.basePrice = basePrice;
        bundle.createdAt = block.timestamp;
        bundle.expiresAt = block.timestamp + duration;
        bundle.maxSupply = maxSupply;
        bundle.active = true;

        // Check for cross-chain bundle
        uint256 currentChain = block.chainid;
        for (uint256 i = 0; i < items.length; i++) {
            bundle.items.push(items[i]);
            if (items[i].chainId != currentChain) {
                bundle.isCrossChain = true;
            }
        }

        // Set up default tier
        bundle.tiers[BundleTier.STANDARD] = TierConfig({
            price: basePrice,
            maxSupply: maxSupply,
            sold: 0,
            bonusItems: new string[](0),
            enabled: true
        });

        bundleExists[bundleId] = true;
        sellerBundles[msg.sender].push(bundleId);

        _emitBundleCreated(bundle);

        return bundleId;
    }

    /**
     * @notice Add tiered pricing to a bundle
     * @param bundleId Bundle ID
     * @param tier Tier level
     * @param price Tier price
     * @param tierMaxSupply Max supply for this tier
     * @param bonusItems Bonus content URIs
     */
    function addTier(
        bytes32 bundleId,
        BundleTier tier,
        uint256 price,
        uint256 tierMaxSupply,
        string[] calldata bonusItems
    ) external {
        Bundle storage bundle = bundles[bundleId];
        require(bundle.seller == msg.sender, "Not seller");
        require(bundle.active, "Bundle not active");

        bundle.tiers[tier] = TierConfig({
            price: price,
            maxSupply: tierMaxSupply,
            sold: 0,
            bonusItems: bonusItems,
            enabled: true
        });
    }

    /**
     * @notice Add collaborators to bundle
     * @param bundleId Bundle ID
     * @param collaborators Array of collaborators
     */
    function addCollaborators(
        bytes32 bundleId,
        Collaborator[] calldata collaborators
    ) external {
        Bundle storage bundle = bundles[bundleId];
        require(bundle.seller == msg.sender, "Not seller");
        require(bundle.active, "Bundle not active");

        uint256 totalShares = 0;
        for (uint256 i = 0; i < collaborators.length; i++) {
            bundle.collaborators.push(collaborators[i]);
            totalShares += collaborators[i].sharePercentage;

            emit CollaboratorAdded(bundleId, collaborators[i].wallet, collaborators[i].sharePercentage);
        }

        require(totalShares <= 9000, "Shares exceed 90%"); // Leave room for platform fee
    }

    // ============ Purchase Functions ============

    /**
     * @notice Purchase a bundle with native token
     * @param bundleId Bundle ID to purchase
     * @param tier Tier to purchase
     */
    function purchaseWithNative(
        bytes32 bundleId,
        BundleTier tier
    ) external payable nonReentrant whenNotPaused {
        Bundle storage bundle = bundles[bundleId];
        require(bundle.active, "Bundle not active");
        require(block.timestamp < bundle.expiresAt, "Bundle expired");
        require(_isTokenAccepted(bundle, address(0)), "Native not accepted");

        TierConfig storage tierConfig = bundle.tiers[tier];
        require(tierConfig.enabled, "Tier not enabled");
        require(tierConfig.maxSupply == 0 || tierConfig.sold < tierConfig.maxSupply, "Tier sold out");

        uint256 price = tierConfig.price;
        require(msg.value >= price, "Insufficient payment");

        // Process purchase
        _processPurchase(bundleId, tier, address(0), price);

        // Refund excess
        if (msg.value > price) {
            (bool success, ) = msg.sender.call{value: msg.value - price}("");
            require(success, "Refund failed");
        }
    }

    /**
     * @notice Purchase a bundle with ERC20 token
     * @param bundleId Bundle ID to purchase
     * @param tier Tier to purchase
     * @param paymentToken Token to pay with
     */
    function purchaseWithToken(
        bytes32 bundleId,
        BundleTier tier,
        address paymentToken
    ) external nonReentrant whenNotPaused {
        require(paymentToken != address(0), "Use purchaseWithNative");

        Bundle storage bundle = bundles[bundleId];
        require(bundle.active, "Bundle not active");
        require(block.timestamp < bundle.expiresAt, "Bundle expired");
        require(_isTokenAccepted(bundle, paymentToken), "Token not accepted");

        TierConfig storage tierConfig = bundle.tiers[tier];
        require(tierConfig.enabled, "Tier not enabled");
        require(tierConfig.maxSupply == 0 || tierConfig.sold < tierConfig.maxSupply, "Tier sold out");

        uint256 price = tierConfig.price;

        // Transfer payment
        IERC20(paymentToken).safeTransferFrom(msg.sender, address(this), price);

        // Process purchase
        _processPurchase(bundleId, tier, paymentToken, price);
    }

    /**
     * @notice Cross-chain bundle purchase (via OmnichainRouter)
     */
    function crossChainPurchase(
        bytes32 bundleId,
        BundleTier tier,
        address buyer,
        uint256 sourceChain,
        address paymentToken,
        uint256 amount
    ) external nonReentrant whenNotPaused {
        require(msg.sender == omnichainRouter, "Only router");

        Bundle storage bundle = bundles[bundleId];
        require(bundle.active, "Bundle not active");
        require(bundle.isCrossChain, "Not cross-chain bundle");

        TierConfig storage tierConfig = bundle.tiers[tier];
        require(tierConfig.enabled, "Tier not enabled");
        require(amount >= tierConfig.price, "Insufficient payment");

        // Process (buyer receives NFTs via cross-chain message)
        _processCrossChainPurchase(bundleId, tier, buyer, sourceChain, paymentToken, amount);
    }

    // ============ Internal Functions ============

    function _generateBundleId() internal returns (bytes32) {
        return keccak256(
            abi.encodePacked(msg.sender, block.timestamp, _bundleNonce++)
        );
    }

    function _emitBundleCreated(Bundle storage bundle) internal {
        emit BundleCreated(
            bundle.bundleId,
            bundle.seller,
            bundle.bundleType,
            bundle.items.length,
            bundle.basePrice
        );
    }

    function _isTokenAccepted(Bundle storage bundle, address token) internal view returns (bool) {
        for (uint256 i = 0; i < bundle.acceptedTokens.length; i++) {
            if (bundle.acceptedTokens[i] == token) return true;
        }
        return false;
    }

    function _processPurchase(
        bytes32 bundleId,
        BundleTier tier,
        address paymentToken,
        uint256 price
    ) internal {
        Bundle storage bundle = bundles[bundleId];
        TierConfig storage tierConfig = bundle.tiers[tier];

        // Calculate splits
        uint256 fee = (price * platformFee) / FEE_DENOMINATOR;
        uint256 remaining = price - fee;

        // Pay platform fee
        _transfer(paymentToken, feeCollector, fee);

        // Pay collaborators
        uint256 collaboratorPaid = 0;
        for (uint256 i = 0; i < bundle.collaborators.length; i++) {
            uint256 share = (remaining * bundle.collaborators[i].sharePercentage) / FEE_DENOMINATOR;
            if (share > 0) {
                _transfer(paymentToken, bundle.collaborators[i].wallet, share);
                collaboratorPaid += share;
            }
        }

        // Pay seller (remainder)
        _transfer(paymentToken, bundle.seller, remaining - collaboratorPaid);

        // Transfer NFTs (same-chain items)
        for (uint256 i = 0; i < bundle.items.length; i++) {
            BundleItem storage item = bundle.items[i];
            if (item.chainId == block.chainid) {
                if (item.isERC1155) {
                    IERC1155(item.nftContract).safeTransferFrom(
                        bundle.seller, msg.sender, item.tokenId, item.amount, ""
                    );
                } else {
                    IERC721(item.nftContract).safeTransferFrom(
                        bundle.seller, msg.sender, item.tokenId
                    );
                }
            }
        }

        // Update stats
        tierConfig.sold++;
        bundle.totalSold++;

        // Check if bundle should be deactivated
        if (bundle.maxSupply > 0 && bundle.totalSold >= bundle.maxSupply) {
            bundle.active = false;
        }

        emit TierPurchased(bundleId, msg.sender, tier, price);
        emit BundlePurchased(bundleId, msg.sender, paymentToken, price, block.chainid);
    }

    function _processCrossChainPurchase(
        bytes32 bundleId,
        BundleTier tier,
        address buyer,
        uint256 sourceChain,
        address paymentToken,
        uint256 amount
    ) internal {
        Bundle storage bundle = bundles[bundleId];
        TierConfig storage tierConfig = bundle.tiers[tier];

        // Calculate and distribute payments (same as regular purchase)
        uint256 fee = (amount * platformFee) / FEE_DENOMINATOR;
        uint256 remaining = amount - fee;

        _transfer(paymentToken, feeCollector, fee);

        uint256 collaboratorPaid = 0;
        for (uint256 i = 0; i < bundle.collaborators.length; i++) {
            uint256 share = (remaining * bundle.collaborators[i].sharePercentage) / FEE_DENOMINATOR;
            if (share > 0) {
                // For cross-chain, route to collaborator's preferred chain
                // In production, this would call OmnichainRouter
                _transfer(paymentToken, bundle.collaborators[i].wallet, share);
                collaboratorPaid += share;
            }
        }

        _transfer(paymentToken, bundle.seller, remaining - collaboratorPaid);

        // NFTs are transferred via cross-chain messages to buyer
        // The OmnichainRouter handles this

        tierConfig.sold++;
        bundle.totalSold++;

        emit BundlePurchased(bundleId, buyer, paymentToken, amount, sourceChain);
    }

    function _transfer(address token, address to, uint256 amount) internal {
        if (amount == 0) return;

        if (token == address(0)) {
            (bool success, ) = to.call{value: amount}("");
            require(success, "Native transfer failed");
        } else {
            IERC20(token).safeTransfer(to, amount);
        }
    }

    // ============ Admin Functions ============

    function cancelBundle(bytes32 bundleId) external {
        Bundle storage bundle = bundles[bundleId];
        require(bundle.seller == msg.sender || msg.sender == owner(), "Not authorized");
        require(bundle.active, "Already inactive");

        bundle.active = false;
        emit BundleCancelled(bundleId);
    }

    function setFeatured(bytes32[] calldata bundleIds) external onlyOwner {
        featuredBundles = bundleIds;
    }

    function setFeeCollector(address _feeCollector) external onlyOwner {
        feeCollector = _feeCollector;
    }

    function setPlatformFee(uint256 _platformFee) external onlyOwner {
        require(_platformFee <= 500, "Fee too high");
        platformFee = _platformFee;
    }

    function setOmnichainRouter(address _router) external onlyOwner {
        omnichainRouter = _router;
    }

    function pause() external onlyOwner { _pause(); }
    function unpause() external onlyOwner { _unpause(); }

    function emergencyWithdraw(address token, uint256 amount) external onlyOwner {
        if (token == address(0)) {
            (bool success, ) = owner().call{value: amount}("");
            require(success, "ETH withdrawal failed");
        } else {
            IERC20(token).safeTransfer(owner(), amount);
        }
    }

    // ============ View Functions ============

    function getBundleInfo(bytes32 bundleId) external view returns (
        address seller,
        BundleType bundleType,
        string memory name,
        uint256 basePrice,
        uint256 totalSold,
        uint256 maxSupply,
        bool active,
        bool isCrossChain
    ) {
        Bundle storage bundle = bundles[bundleId];
        return (
            bundle.seller,
            bundle.bundleType,
            bundle.name,
            bundle.basePrice,
            bundle.totalSold,
            bundle.maxSupply,
            bundle.active,
            bundle.isCrossChain
        );
    }

    function getBundleItems(bytes32 bundleId) external view returns (BundleItem[] memory) {
        return bundles[bundleId].items;
    }

    function getBundleCollaborators(bytes32 bundleId) external view returns (Collaborator[] memory) {
        return bundles[bundleId].collaborators;
    }

    function getTierInfo(bytes32 bundleId, BundleTier tier) external view returns (TierConfig memory) {
        return bundles[bundleId].tiers[tier];
    }

    function getFeaturedBundles() external view returns (bytes32[] memory) {
        return featuredBundles;
    }

    function getSellerBundles(address seller) external view returns (bytes32[] memory) {
        return sellerBundles[seller];
    }

    // ============ UUPS ============

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    receive() external payable {}
}
