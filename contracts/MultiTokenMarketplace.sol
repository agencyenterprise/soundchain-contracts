// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title MultiTokenMarketplace
 * @notice Multi-token NFT marketplace supporting 32+ cryptocurrencies
 * @dev Upgradeable proxy contract with ZetaChain cross-chain integration
 *
 * Supported Tokens (32):
 * MATIC, OGUN, PENGU, ETH, USDC, USDT, SOL, BNB, DOGE, BONK,
 * MEATEOR, PEPE, BASE, XTZ, AVAX, SHIB, XRP, SUI, HBAR, LINK,
 * LTC, ZETA, BTC, YZY, ADA, DOT, ATOM, FTM, NEAR, OP, ARB, ONDO
 *
 * Features:
 * - List NFTs for sale in any supported token
 * - Accept multiple tokens per listing
 * - Cross-chain purchases via ZetaChain
 * - Collaborator royalty splits
 * - Platform fee collection
 */
contract MultiTokenMarketplace is
    Initializable,
    UUPSUpgradeable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable
{
    using SafeERC20 for IERC20;

    // ============ Events ============

    event ListingCreated(
        bytes32 indexed listingId,
        address indexed seller,
        address indexed nftContract,
        uint256 tokenId,
        uint256 price,
        address[] acceptedTokens
    );

    event ListingUpdated(
        bytes32 indexed listingId,
        uint256 newPrice,
        address[] acceptedTokens
    );

    event ListingCancelled(bytes32 indexed listingId);

    event Sale(
        bytes32 indexed listingId,
        address indexed buyer,
        address indexed paymentToken,
        uint256 price,
        uint256 platformFee,
        uint256 royaltyAmount
    );

    event CrossChainSale(
        bytes32 indexed listingId,
        address indexed buyer,
        uint256 sourceChainId,
        address paymentToken,
        uint256 price
    );

    event TokenWhitelisted(address indexed token, string symbol, bool enabled);

    event CollaboratorPaid(
        bytes32 indexed listingId,
        address indexed collaborator,
        uint256 amount,
        address token
    );

    // ============ Structs ============

    struct Listing {
        bytes32 listingId;
        address seller;
        address nftContract;
        uint256 tokenId;
        uint256 price;              // Price in base units
        address priceToken;         // Primary price denomination
        address[] acceptedTokens;   // Tokens accepted for payment
        uint256 createdAt;
        uint256 expiresAt;
        bool active;
    }

    struct Collaborator {
        address wallet;
        uint256 sharePercentage;    // In basis points (100 = 1%)
        uint256 chainId;            // Preferred chain for payment (0 = same chain)
    }

    struct TokenInfo {
        string symbol;
        uint8 decimals;
        bool enabled;
        address priceFeed;          // Chainlink price feed (optional)
    }

    // ============ State Variables ============

    /// @notice Version for upgrades
    uint256 public constant VERSION = 1;

    /// @notice Platform fee in basis points (50 = 0.5%)
    uint256 public platformFee;

    /// @notice Fee denominator
    uint256 public constant FEE_DENOMINATOR = 10000;

    /// @notice Fee collector (Gnosis Safe)
    address public feeCollector;

    /// @notice Listings by ID
    mapping(bytes32 => Listing) public listings;

    /// @notice Collaborators by listing ID
    mapping(bytes32 => Collaborator[]) public listingCollaborators;

    /// @notice Whitelisted tokens
    mapping(address => TokenInfo) public whitelistedTokens;

    /// @notice All whitelisted token addresses
    address[] public tokenList;

    /// @notice ZetaChain omnichain contract
    address public omnichainContract;

    /// @notice Listing nonce
    uint256 private _listingNonce;

    /// @notice Royalty percentage for original creator (in basis points)
    uint256 public defaultRoyaltyPercentage;

    /// @notice NFT contract to royalty receiver
    mapping(address => mapping(uint256 => address)) public royaltyReceivers;

    // ============ Initializer ============

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initialize the marketplace
     * @param _feeCollector Platform fee collector
     * @param _platformFee Platform fee in basis points
     * @param _omnichainContract ZetaChain omnichain contract address
     */
    function initialize(
        address _feeCollector,
        uint256 _platformFee,
        address _omnichainContract
    ) external initializer {
        __Ownable_init();
        __ReentrancyGuard_init();
        __Pausable_init();
        __UUPSUpgradeable_init();

        require(_feeCollector != address(0), "Invalid fee collector");
        require(_platformFee <= 500, "Fee too high"); // Max 5%

        feeCollector = _feeCollector;
        platformFee = _platformFee;
        omnichainContract = _omnichainContract;
        defaultRoyaltyPercentage = 1000; // 10% default royalty
    }

    // ============ Listing Functions ============

    /**
     * @notice Create a new listing
     * @param nftContract NFT contract address
     * @param tokenId Token ID to list
     * @param price Price in priceToken units
     * @param priceToken Primary price denomination
     * @param acceptedTokens Array of accepted payment tokens
     * @param duration Listing duration in seconds
     * @param collaborators Array of collaborators for royalty split
     */
    function createListing(
        address nftContract,
        uint256 tokenId,
        uint256 price,
        address priceToken,
        address[] calldata acceptedTokens,
        uint256 duration,
        Collaborator[] calldata collaborators
    ) external nonReentrant whenNotPaused returns (bytes32 listingId) {
        require(price > 0, "Invalid price");
        require(duration > 0 && duration <= 365 days, "Invalid duration");
        require(acceptedTokens.length > 0 && acceptedTokens.length <= 32, "Invalid token count");
        require(
            IERC721(nftContract).ownerOf(tokenId) == msg.sender,
            "Not token owner"
        );
        require(
            IERC721(nftContract).isApprovedForAll(msg.sender, address(this)) ||
            IERC721(nftContract).getApproved(tokenId) == address(this),
            "Not approved"
        );

        // Validate accepted tokens
        for (uint256 i = 0; i < acceptedTokens.length; i++) {
            require(
                whitelistedTokens[acceptedTokens[i]].enabled || acceptedTokens[i] == address(0),
                "Token not whitelisted"
            );
        }

        // Validate collaborator shares
        uint256 totalShares = 0;
        for (uint256 i = 0; i < collaborators.length; i++) {
            require(collaborators[i].wallet != address(0), "Invalid collaborator");
            require(collaborators[i].sharePercentage <= 5000, "Share too high"); // Max 50%
            totalShares += collaborators[i].sharePercentage;
        }
        require(totalShares <= 9000, "Total shares exceed 90%"); // Leave room for platform fee

        listingId = keccak256(
            abi.encodePacked(msg.sender, nftContract, tokenId, block.timestamp, _listingNonce++)
        );

        listings[listingId] = Listing({
            listingId: listingId,
            seller: msg.sender,
            nftContract: nftContract,
            tokenId: tokenId,
            price: price,
            priceToken: priceToken,
            acceptedTokens: acceptedTokens,
            createdAt: block.timestamp,
            expiresAt: block.timestamp + duration,
            active: true
        });

        // Store collaborators
        for (uint256 i = 0; i < collaborators.length; i++) {
            listingCollaborators[listingId].push(collaborators[i]);
        }

        emit ListingCreated(
            listingId,
            msg.sender,
            nftContract,
            tokenId,
            price,
            acceptedTokens
        );

        return listingId;
    }

    /**
     * @notice Update a listing
     * @param listingId Listing ID to update
     * @param newPrice New price
     * @param newAcceptedTokens New accepted tokens array
     */
    function updateListing(
        bytes32 listingId,
        uint256 newPrice,
        address[] calldata newAcceptedTokens
    ) external {
        Listing storage listing = listings[listingId];
        require(listing.seller == msg.sender, "Not seller");
        require(listing.active, "Listing not active");

        if (newPrice > 0) {
            listing.price = newPrice;
        }

        if (newAcceptedTokens.length > 0) {
            for (uint256 i = 0; i < newAcceptedTokens.length; i++) {
                require(
                    whitelistedTokens[newAcceptedTokens[i]].enabled || newAcceptedTokens[i] == address(0),
                    "Token not whitelisted"
                );
            }
            listing.acceptedTokens = newAcceptedTokens;
        }

        emit ListingUpdated(listingId, listing.price, listing.acceptedTokens);
    }

    /**
     * @notice Cancel a listing
     * @param listingId Listing ID to cancel
     */
    function cancelListing(bytes32 listingId) external {
        Listing storage listing = listings[listingId];
        require(listing.seller == msg.sender || msg.sender == owner(), "Not authorized");
        require(listing.active, "Already inactive");

        listing.active = false;

        emit ListingCancelled(listingId);
    }

    // ============ Purchase Functions ============

    /**
     * @notice Purchase a listing with native token
     * @param listingId Listing ID to purchase
     */
    function purchaseWithNative(
        bytes32 listingId
    ) external payable nonReentrant whenNotPaused {
        Listing storage listing = listings[listingId];
        require(listing.active, "Listing not active");
        require(block.timestamp < listing.expiresAt, "Listing expired");
        require(_isTokenAccepted(listing.acceptedTokens, address(0)), "Native not accepted");

        uint256 price = listing.price;
        require(msg.value >= price, "Insufficient payment");

        // Calculate fees and royalties
        (uint256 fee, uint256 royalty, uint256 sellerAmount) = _calculateSplit(listingId, price);

        // Execute transfers
        _executeNativePayment(listingId, listing.seller, sellerAmount, fee, royalty);

        // Transfer NFT
        IERC721(listing.nftContract).safeTransferFrom(
            listing.seller,
            msg.sender,
            listing.tokenId
        );

        listing.active = false;

        // Refund excess
        if (msg.value > price) {
            (bool success, ) = msg.sender.call{value: msg.value - price}("");
            require(success, "Refund failed");
        }

        emit Sale(listingId, msg.sender, address(0), price, fee, royalty);
    }

    /**
     * @notice Purchase a listing with ERC20 token
     * @param listingId Listing ID to purchase
     * @param paymentToken Token to pay with
     * @param maxAmount Maximum amount to spend (slippage protection)
     */
    function purchaseWithToken(
        bytes32 listingId,
        address paymentToken,
        uint256 maxAmount
    ) external nonReentrant whenNotPaused {
        require(paymentToken != address(0), "Use purchaseWithNative()");

        Listing storage listing = listings[listingId];
        require(listing.active, "Listing not active");
        require(block.timestamp < listing.expiresAt, "Listing expired");
        require(_isTokenAccepted(listing.acceptedTokens, paymentToken), "Token not accepted");

        uint256 price = listing.price;
        require(maxAmount >= price, "Exceeds max amount");

        // Calculate fees and royalties
        (uint256 fee, uint256 royalty, uint256 sellerAmount) = _calculateSplit(listingId, price);

        // Execute transfers
        _executeTokenPayment(listingId, paymentToken, listing.seller, sellerAmount, fee, royalty);

        // Transfer NFT
        IERC721(listing.nftContract).safeTransferFrom(
            listing.seller,
            msg.sender,
            listing.tokenId
        );

        listing.active = false;

        emit Sale(listingId, msg.sender, paymentToken, price, fee, royalty);
    }

    /**
     * @notice Handle cross-chain purchase from ZetaChain
     * @dev Only callable by omnichain contract
     */
    function crossChainPurchase(
        bytes32 listingId,
        address buyer,
        uint256 sourceChainId,
        address paymentToken,
        uint256 amount
    ) external nonReentrant whenNotPaused {
        require(msg.sender == omnichainContract, "Only omnichain");

        Listing storage listing = listings[listingId];
        require(listing.active, "Listing not active");
        require(block.timestamp < listing.expiresAt, "Listing expired");

        // Note: Funds already received via ZetaChain bridge
        // Calculate fees
        (uint256 fee, uint256 royalty, uint256 sellerAmount) = _calculateSplit(listingId, amount);

        // Distribute payments (tokens already in this contract)
        _executeTokenPayment(listingId, paymentToken, listing.seller, sellerAmount, fee, royalty);

        // Transfer NFT to buyer
        IERC721(listing.nftContract).safeTransferFrom(
            listing.seller,
            buyer,
            listing.tokenId
        );

        listing.active = false;

        emit CrossChainSale(listingId, buyer, sourceChainId, paymentToken, amount);
    }

    // ============ Internal Functions ============

    function _isTokenAccepted(address[] storage acceptedTokens, address token) internal view returns (bool) {
        for (uint256 i = 0; i < acceptedTokens.length; i++) {
            if (acceptedTokens[i] == token) return true;
        }
        return false;
    }

    function _calculateSplit(bytes32 listingId, uint256 price) internal view returns (
        uint256 fee,
        uint256 royalty,
        uint256 sellerAmount
    ) {
        fee = (price * platformFee) / FEE_DENOMINATOR;

        // Calculate collaborator royalties
        Collaborator[] storage collaborators = listingCollaborators[listingId];
        for (uint256 i = 0; i < collaborators.length; i++) {
            royalty += (price * collaborators[i].sharePercentage) / FEE_DENOMINATOR;
        }

        sellerAmount = price - fee - royalty;
        return (fee, royalty, sellerAmount);
    }

    function _executeNativePayment(
        bytes32 listingId,
        address seller,
        uint256 sellerAmount,
        uint256 fee,
        uint256 royalty
    ) internal {
        // Pay platform fee
        if (fee > 0) {
            (bool feeSuccess, ) = feeCollector.call{value: fee}("");
            require(feeSuccess, "Fee payment failed");
        }

        // Pay collaborators
        Collaborator[] storage collaborators = listingCollaborators[listingId];
        uint256 royaltyPaid = 0;
        for (uint256 i = 0; i < collaborators.length; i++) {
            uint256 share = (royalty * collaborators[i].sharePercentage) / _getTotalShares(listingId);
            if (share > 0) {
                (bool collabSuccess, ) = collaborators[i].wallet.call{value: share}("");
                require(collabSuccess, "Collaborator payment failed");
                royaltyPaid += share;
                emit CollaboratorPaid(listingId, collaborators[i].wallet, share, address(0));
            }
        }

        // Pay seller (remainder goes to seller to handle rounding)
        (bool sellerSuccess, ) = seller.call{value: sellerAmount + (royalty - royaltyPaid)}("");
        require(sellerSuccess, "Seller payment failed");
    }

    function _executeTokenPayment(
        bytes32 listingId,
        address token,
        address seller,
        uint256 sellerAmount,
        uint256 fee,
        uint256 royalty
    ) internal {
        // Pay platform fee
        if (fee > 0) {
            IERC20(token).safeTransferFrom(msg.sender, feeCollector, fee);
        }

        // Pay collaborators
        Collaborator[] storage collaborators = listingCollaborators[listingId];
        uint256 royaltyPaid = 0;
        for (uint256 i = 0; i < collaborators.length; i++) {
            uint256 share = (royalty * collaborators[i].sharePercentage) / _getTotalShares(listingId);
            if (share > 0) {
                IERC20(token).safeTransferFrom(msg.sender, collaborators[i].wallet, share);
                royaltyPaid += share;
                emit CollaboratorPaid(listingId, collaborators[i].wallet, share, token);
            }
        }

        // Pay seller
        IERC20(token).safeTransferFrom(msg.sender, seller, sellerAmount + (royalty - royaltyPaid));
    }

    function _getTotalShares(bytes32 listingId) internal view returns (uint256) {
        Collaborator[] storage collaborators = listingCollaborators[listingId];
        uint256 total = 0;
        for (uint256 i = 0; i < collaborators.length; i++) {
            total += collaborators[i].sharePercentage;
        }
        return total > 0 ? total : 1; // Avoid division by zero
    }

    // ============ Admin Functions ============

    /**
     * @notice Whitelist a new token
     * @param token Token address (address(0) for native)
     * @param symbol Token symbol
     * @param decimals Token decimals
     * @param priceFeed Chainlink price feed (optional)
     */
    function whitelistToken(
        address token,
        string calldata symbol,
        uint8 decimals,
        address priceFeed
    ) external onlyOwner {
        whitelistedTokens[token] = TokenInfo({
            symbol: symbol,
            decimals: decimals,
            enabled: true,
            priceFeed: priceFeed
        });

        // Add to list if not already present
        bool exists = false;
        for (uint256 i = 0; i < tokenList.length; i++) {
            if (tokenList[i] == token) {
                exists = true;
                break;
            }
        }
        if (!exists) {
            tokenList.push(token);
        }

        emit TokenWhitelisted(token, symbol, true);
    }

    /**
     * @notice Bulk whitelist tokens
     */
    function whitelistTokensBulk(
        address[] calldata tokens,
        string[] calldata symbols,
        uint8[] calldata decimals
    ) external onlyOwner {
        require(
            tokens.length == symbols.length && tokens.length == decimals.length,
            "Length mismatch"
        );

        for (uint256 i = 0; i < tokens.length; i++) {
            whitelistedTokens[tokens[i]] = TokenInfo({
                symbol: symbols[i],
                decimals: decimals[i],
                enabled: true,
                priceFeed: address(0)
            });

            bool exists = false;
            for (uint256 j = 0; j < tokenList.length; j++) {
                if (tokenList[j] == tokens[i]) {
                    exists = true;
                    break;
                }
            }
            if (!exists) {
                tokenList.push(tokens[i]);
            }

            emit TokenWhitelisted(tokens[i], symbols[i], true);
        }
    }

    function disableToken(address token) external onlyOwner {
        whitelistedTokens[token].enabled = false;
        emit TokenWhitelisted(token, whitelistedTokens[token].symbol, false);
    }

    function setFeeCollector(address _feeCollector) external onlyOwner {
        require(_feeCollector != address(0), "Invalid address");
        feeCollector = _feeCollector;
    }

    function setPlatformFee(uint256 _platformFee) external onlyOwner {
        require(_platformFee <= 500, "Fee too high");
        platformFee = _platformFee;
    }

    function setOmnichainContract(address _omnichainContract) external onlyOwner {
        omnichainContract = _omnichainContract;
    }

    function setDefaultRoyalty(uint256 percentage) external onlyOwner {
        require(percentage <= 2000, "Royalty too high"); // Max 20%
        defaultRoyaltyPercentage = percentage;
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

    function getListing(bytes32 listingId) external view returns (Listing memory) {
        return listings[listingId];
    }

    function getListingCollaborators(bytes32 listingId) external view returns (Collaborator[] memory) {
        return listingCollaborators[listingId];
    }

    function getWhitelistedTokens() external view returns (address[] memory) {
        return tokenList;
    }

    function isTokenWhitelisted(address token) external view returns (bool) {
        return whitelistedTokens[token].enabled;
    }

    function getTokenInfo(address token) external view returns (TokenInfo memory) {
        return whitelistedTokens[token];
    }

    function calculatePurchaseTotal(bytes32 listingId) external view returns (
        uint256 price,
        uint256 fee,
        uint256 royalty,
        uint256 total
    ) {
        Listing storage listing = listings[listingId];
        price = listing.price;
        fee = (price * platformFee) / FEE_DENOMINATOR;

        Collaborator[] storage collaborators = listingCollaborators[listingId];
        for (uint256 i = 0; i < collaborators.length; i++) {
            royalty += (price * collaborators[i].sharePercentage) / FEE_DENOMINATOR;
        }

        total = price;
        return (price, fee, royalty, total);
    }

    // ============ UUPS ============

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    // ============ Receive ============

    receive() external payable {}
}
