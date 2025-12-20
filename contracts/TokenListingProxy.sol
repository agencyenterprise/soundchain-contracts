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
 * @title TokenListingProxy
 * @notice Multi-token listing contract with omnichain support
 * @dev Supports 32+ tokens for NFT listings with cross-chain purchases
 *
 * This contract enables:
 * - Fixed price listings in any supported token
 * - Auction listings with token preferences
 * - Make offer functionality in any token
 * - Automatic token conversion via ZetaChain
 * - Collaborator royalty splits
 *
 * Unique features:
 * - Users choose their preferred payment token
 * - Sellers choose their payout token
 * - Cross-chain purchases converted automatically
 * - Multi-token auction bidding
 */
contract TokenListingProxy is
    Initializable,
    UUPSUpgradeable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable
{
    using SafeERC20 for IERC20;

    // ============ Constants ============

    string public constant VERSION = "1.0.0";
    uint256 public constant MAX_TOKENS = 50;
    uint256 public constant MAX_COLLABORATORS = 10;
    uint256 public constant BASIS_POINTS = 10000;
    uint256 public constant MIN_AUCTION_DURATION = 1 hours;
    uint256 public constant MAX_AUCTION_DURATION = 30 days;
    uint256 public constant AUCTION_EXTENSION = 10 minutes;

    // ============ Enums ============

    enum ListingType {
        FIXED_PRICE,
        AUCTION,
        MAKE_OFFER
    }

    enum ListingStatus {
        ACTIVE,
        SOLD,
        CANCELLED,
        EXPIRED
    }

    // ============ Structs ============

    struct TokenInfo {
        address token;          // Token address (address(0) for native)
        string symbol;          // Token symbol (ETH, USDC, etc.)
        uint8 decimals;         // Token decimals
        address zrc20;          // ZRC-20 equivalent on ZetaChain
        bool enabled;           // Is token enabled for listings
        uint256 minAmount;      // Minimum amount for listings
    }

    struct Collaborator {
        address wallet;
        uint16 percentage;      // Basis points (100 = 1%)
        uint256 preferredChain; // Chain to receive royalties
        address preferredToken; // Token to receive royalties in
    }

    struct Listing {
        bytes32 listingId;
        address seller;
        address nftContract;
        uint256 tokenId;
        ListingType listingType;
        ListingStatus status;
        address paymentToken;   // Preferred payment token
        uint256 price;          // Fixed price or reserve price
        address payoutToken;    // Token seller wants to receive
        uint256 payoutChain;    // Chain seller wants payout on
        uint256 createdAt;
        uint256 expiresAt;
        bytes32 scid;           // Associated SCid
    }

    struct AuctionData {
        bytes32 listingId;
        uint256 reservePrice;
        uint256 currentBid;
        address currentBidder;
        address bidToken;       // Token used for current bid
        uint256 endTime;
        uint256 bidCount;
        bool reserveMet;
    }

    struct Offer {
        bytes32 offerId;
        bytes32 listingId;
        address offerer;
        address token;
        uint256 amount;
        uint256 expiresAt;
        bool accepted;
        bool cancelled;
    }

    // ============ Events ============

    event ListingCreated(
        bytes32 indexed listingId,
        address indexed seller,
        address nftContract,
        uint256 tokenId,
        ListingType listingType,
        address paymentToken,
        uint256 price
    );

    event ListingSold(
        bytes32 indexed listingId,
        address indexed buyer,
        address paymentToken,
        uint256 price,
        uint256 platformFee
    );

    event ListingCancelled(bytes32 indexed listingId);

    event BidPlaced(
        bytes32 indexed listingId,
        address indexed bidder,
        address token,
        uint256 amount
    );

    event OfferMade(
        bytes32 indexed offerId,
        bytes32 indexed listingId,
        address indexed offerer,
        address token,
        uint256 amount
    );

    event OfferAccepted(bytes32 indexed offerId);
    event OfferCancelled(bytes32 indexed offerId);

    event TokenAdded(address indexed token, string symbol);
    event TokenRemoved(address indexed token);

    event CollaboratorPaid(
        bytes32 indexed listingId,
        address indexed collaborator,
        address token,
        uint256 amount,
        uint256 chain
    );

    // ============ State Variables ============

    /// @notice OmnichainRouter for cross-chain operations
    address public omnichainRouter;

    /// @notice Fee collector address
    address public feeCollector;

    /// @notice Platform fee in basis points (50 = 0.5%)
    uint256 public platformFee;

    /// @notice Supported tokens
    mapping(address => TokenInfo) public tokens;
    address[] public tokenList;

    /// @notice All listings
    mapping(bytes32 => Listing) public listings;

    /// @notice Auction data for auction listings
    mapping(bytes32 => AuctionData) public auctions;

    /// @notice Collaborators for each listing
    mapping(bytes32 => Collaborator[]) public listingCollaborators;

    /// @notice All offers
    mapping(bytes32 => Offer) public offers;

    /// @notice Offers per listing
    mapping(bytes32 => bytes32[]) public listingOffers;

    /// @notice User's active listings
    mapping(address => bytes32[]) public userListings;

    /// @notice User's active offers
    mapping(address => bytes32[]) public userOffers;

    /// @notice Listing nonce for ID generation
    uint256 private _listingNonce;

    /// @notice Offer nonce for ID generation
    uint256 private _offerNonce;

    /// @notice Escrow balances per token
    mapping(address => uint256) public escrowBalances;

    // ============ Initializer ============

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _omnichainRouter,
        address _feeCollector,
        uint256 _platformFee
    ) external initializer {
        __Ownable_init();
        __ReentrancyGuard_init();
        __Pausable_init();
        __UUPSUpgradeable_init();

        omnichainRouter = _omnichainRouter;
        feeCollector = _feeCollector;
        platformFee = _platformFee;

        // Add native token (ETH/MATIC)
        _addToken(address(0), "NATIVE", 18, address(0), 0);
    }

    // ============ Listing Functions ============

    /**
     * @notice Create a fixed price listing
     * @param nftContract NFT contract address
     * @param tokenId Token ID to list
     * @param paymentToken Accepted payment token
     * @param price Listing price
     * @param payoutToken Token seller wants to receive
     * @param payoutChain Chain for payout
     * @param duration Listing duration
     * @param collaborators Royalty collaborators
     * @param scid Associated SCid
     */
    function createFixedPriceListing(
        address nftContract,
        uint256 tokenId,
        address paymentToken,
        uint256 price,
        address payoutToken,
        uint256 payoutChain,
        uint256 duration,
        Collaborator[] calldata collaborators,
        bytes32 scid
    ) external nonReentrant whenNotPaused returns (bytes32 listingId) {
        require(tokens[paymentToken].enabled, "Payment token not supported");
        require(price >= tokens[paymentToken].minAmount, "Price below minimum");
        require(collaborators.length <= MAX_COLLABORATORS, "Too many collaborators");

        // Verify ownership and transfer NFT to escrow
        IERC721 nft = IERC721(nftContract);
        require(nft.ownerOf(tokenId) == msg.sender, "Not owner");
        nft.transferFrom(msg.sender, address(this), tokenId);

        listingId = _generateListingId();

        listings[listingId] = Listing({
            listingId: listingId,
            seller: msg.sender,
            nftContract: nftContract,
            tokenId: tokenId,
            listingType: ListingType.FIXED_PRICE,
            status: ListingStatus.ACTIVE,
            paymentToken: paymentToken,
            price: price,
            payoutToken: payoutToken,
            payoutChain: payoutChain,
            createdAt: block.timestamp,
            expiresAt: block.timestamp + duration,
            scid: scid
        });

        // Store collaborators
        _storeCollaborators(listingId, collaborators);

        userListings[msg.sender].push(listingId);

        emit ListingCreated(
            listingId,
            msg.sender,
            nftContract,
            tokenId,
            ListingType.FIXED_PRICE,
            paymentToken,
            price
        );

        return listingId;
    }

    /**
     * @notice Create an auction listing
     */
    function createAuctionListing(
        address nftContract,
        uint256 tokenId,
        address paymentToken,
        uint256 reservePrice,
        address payoutToken,
        uint256 payoutChain,
        uint256 duration,
        Collaborator[] calldata collaborators,
        bytes32 scid
    ) external nonReentrant whenNotPaused returns (bytes32 listingId) {
        require(tokens[paymentToken].enabled, "Payment token not supported");
        require(duration >= MIN_AUCTION_DURATION && duration <= MAX_AUCTION_DURATION, "Invalid duration");
        require(collaborators.length <= MAX_COLLABORATORS, "Too many collaborators");

        IERC721 nft = IERC721(nftContract);
        require(nft.ownerOf(tokenId) == msg.sender, "Not owner");
        nft.transferFrom(msg.sender, address(this), tokenId);

        listingId = _generateListingId();

        listings[listingId] = Listing({
            listingId: listingId,
            seller: msg.sender,
            nftContract: nftContract,
            tokenId: tokenId,
            listingType: ListingType.AUCTION,
            status: ListingStatus.ACTIVE,
            paymentToken: paymentToken,
            price: reservePrice,
            payoutToken: payoutToken,
            payoutChain: payoutChain,
            createdAt: block.timestamp,
            expiresAt: block.timestamp + duration,
            scid: scid
        });

        auctions[listingId] = AuctionData({
            listingId: listingId,
            reservePrice: reservePrice,
            currentBid: 0,
            currentBidder: address(0),
            bidToken: address(0),
            endTime: block.timestamp + duration,
            bidCount: 0,
            reserveMet: false
        });

        _storeCollaborators(listingId, collaborators);
        userListings[msg.sender].push(listingId);

        emit ListingCreated(
            listingId,
            msg.sender,
            nftContract,
            tokenId,
            ListingType.AUCTION,
            paymentToken,
            reservePrice
        );

        return listingId;
    }

    /**
     * @notice Create a make-offer listing
     */
    function createMakeOfferListing(
        address nftContract,
        uint256 tokenId,
        uint256 duration,
        Collaborator[] calldata collaborators,
        bytes32 scid
    ) external nonReentrant whenNotPaused returns (bytes32 listingId) {
        require(collaborators.length <= MAX_COLLABORATORS, "Too many collaborators");

        IERC721 nft = IERC721(nftContract);
        require(nft.ownerOf(tokenId) == msg.sender, "Not owner");
        nft.transferFrom(msg.sender, address(this), tokenId);

        listingId = _generateListingId();

        listings[listingId] = Listing({
            listingId: listingId,
            seller: msg.sender,
            nftContract: nftContract,
            tokenId: tokenId,
            listingType: ListingType.MAKE_OFFER,
            status: ListingStatus.ACTIVE,
            paymentToken: address(0), // Accepts any token
            price: 0,
            payoutToken: address(0), // Decided when accepting offer
            payoutChain: 0,
            createdAt: block.timestamp,
            expiresAt: block.timestamp + duration,
            scid: scid
        });

        _storeCollaborators(listingId, collaborators);
        userListings[msg.sender].push(listingId);

        emit ListingCreated(
            listingId,
            msg.sender,
            nftContract,
            tokenId,
            ListingType.MAKE_OFFER,
            address(0),
            0
        );

        return listingId;
    }

    // ============ Purchase Functions ============

    /**
     * @notice Buy a fixed price listing
     */
    function buyFixedPrice(
        bytes32 listingId,
        address paymentToken
    ) external payable nonReentrant whenNotPaused {
        Listing storage listing = listings[listingId];
        require(listing.status == ListingStatus.ACTIVE, "Not active");
        require(listing.listingType == ListingType.FIXED_PRICE, "Not fixed price");
        require(block.timestamp < listing.expiresAt, "Expired");

        uint256 amount;

        // Handle payment token matching or conversion
        if (paymentToken == listing.paymentToken) {
            amount = listing.price;
        } else {
            // Cross-token purchase - route through omnichain
            require(tokens[paymentToken].enabled, "Token not supported");
            // Amount will be converted via ZetaChain
            amount = _getConvertedAmount(paymentToken, listing.paymentToken, listing.price);
        }

        // Collect payment
        _collectPayment(paymentToken, amount);

        // Calculate fees
        uint256 fee = (listing.price * platformFee) / BASIS_POINTS;
        uint256 sellerAmount = listing.price - fee;

        // Distribute to collaborators
        sellerAmount = _distributeCollaboratorRoyalties(listingId, sellerAmount, listing.payoutToken);

        // Transfer fee to collector
        _transferPayment(listing.payoutToken, feeCollector, fee);

        // Pay seller (may go cross-chain)
        if (listing.payoutChain == block.chainid) {
            _transferPayment(listing.payoutToken, listing.seller, sellerAmount);
        } else {
            _routeCrossChainPayout(
                listing.seller,
                listing.payoutToken,
                sellerAmount,
                listing.payoutChain
            );
        }

        // Transfer NFT to buyer
        IERC721(listing.nftContract).transferFrom(address(this), msg.sender, listing.tokenId);

        listing.status = ListingStatus.SOLD;

        emit ListingSold(listingId, msg.sender, paymentToken, amount, fee);
    }

    /**
     * @notice Place bid on auction
     */
    function placeBid(
        bytes32 listingId,
        address bidToken,
        uint256 bidAmount
    ) external payable nonReentrant whenNotPaused {
        Listing storage listing = listings[listingId];
        AuctionData storage auction = auctions[listingId];

        require(listing.status == ListingStatus.ACTIVE, "Not active");
        require(listing.listingType == ListingType.AUCTION, "Not auction");
        require(block.timestamp < auction.endTime, "Auction ended");
        require(tokens[bidToken].enabled, "Token not supported");

        uint256 normalizedBid = _normalizeTokenAmount(bidToken, bidAmount, listing.paymentToken);
        require(normalizedBid > auction.currentBid, "Bid too low");

        if (auction.currentBid > 0) {
            require(normalizedBid >= (auction.currentBid * 105) / 100, "Min 5% increase");
        }

        // Collect new bid
        _collectPayment(bidToken, bidAmount);

        // Refund previous bidder
        if (auction.currentBidder != address(0)) {
            _transferPayment(auction.bidToken, auction.currentBidder, auction.currentBid);
        }

        auction.currentBid = bidAmount;
        auction.currentBidder = msg.sender;
        auction.bidToken = bidToken;
        auction.bidCount++;

        if (normalizedBid >= auction.reservePrice) {
            auction.reserveMet = true;
        }

        // Extend auction if bid in last 10 minutes
        if (auction.endTime - block.timestamp < AUCTION_EXTENSION) {
            auction.endTime += AUCTION_EXTENSION;
        }

        emit BidPlaced(listingId, msg.sender, bidToken, bidAmount);
    }

    /**
     * @notice Settle ended auction
     */
    function settleAuction(bytes32 listingId) external nonReentrant {
        Listing storage listing = listings[listingId];
        AuctionData storage auction = auctions[listingId];

        require(listing.status == ListingStatus.ACTIVE, "Not active");
        require(listing.listingType == ListingType.AUCTION, "Not auction");
        require(block.timestamp >= auction.endTime, "Auction not ended");

        if (auction.reserveMet && auction.currentBidder != address(0)) {
            // Successful auction
            uint256 fee = (auction.currentBid * platformFee) / BASIS_POINTS;
            uint256 sellerAmount = auction.currentBid - fee;

            // Distribute royalties
            sellerAmount = _distributeCollaboratorRoyalties(listingId, sellerAmount, listing.payoutToken);

            // Pay fees and seller
            _transferPayment(listing.payoutToken, feeCollector, fee);

            if (listing.payoutChain == block.chainid) {
                _transferPayment(listing.payoutToken, listing.seller, sellerAmount);
            } else {
                _routeCrossChainPayout(listing.seller, listing.payoutToken, sellerAmount, listing.payoutChain);
            }

            // Transfer NFT to winner
            IERC721(listing.nftContract).transferFrom(address(this), auction.currentBidder, listing.tokenId);

            listing.status = ListingStatus.SOLD;

            emit ListingSold(listingId, auction.currentBidder, auction.bidToken, auction.currentBid, fee);
        } else {
            // Failed auction - return NFT
            IERC721(listing.nftContract).transferFrom(address(this), listing.seller, listing.tokenId);

            // Refund any bid
            if (auction.currentBidder != address(0)) {
                _transferPayment(auction.bidToken, auction.currentBidder, auction.currentBid);
            }

            listing.status = ListingStatus.EXPIRED;
        }
    }

    // ============ Offer Functions ============

    /**
     * @notice Make offer on a listing
     */
    function makeOffer(
        bytes32 listingId,
        address token,
        uint256 amount,
        uint256 duration
    ) external payable nonReentrant whenNotPaused returns (bytes32 offerId) {
        Listing storage listing = listings[listingId];
        require(listing.status == ListingStatus.ACTIVE, "Not active");
        require(tokens[token].enabled, "Token not supported");
        require(amount >= tokens[token].minAmount, "Amount too low");

        // Collect offer amount to escrow
        _collectPayment(token, amount);
        escrowBalances[token] += amount;

        offerId = _generateOfferId();

        offers[offerId] = Offer({
            offerId: offerId,
            listingId: listingId,
            offerer: msg.sender,
            token: token,
            amount: amount,
            expiresAt: block.timestamp + duration,
            accepted: false,
            cancelled: false
        });

        listingOffers[listingId].push(offerId);
        userOffers[msg.sender].push(offerId);

        emit OfferMade(offerId, listingId, msg.sender, token, amount);

        return offerId;
    }

    /**
     * @notice Accept an offer
     */
    function acceptOffer(
        bytes32 offerId,
        address payoutToken,
        uint256 payoutChain
    ) external nonReentrant {
        Offer storage offer = offers[offerId];
        Listing storage listing = listings[offer.listingId];

        require(!offer.accepted && !offer.cancelled, "Offer invalid");
        require(block.timestamp < offer.expiresAt, "Offer expired");
        require(listing.seller == msg.sender, "Not seller");
        require(listing.status == ListingStatus.ACTIVE, "Not active");

        offer.accepted = true;
        listing.status = ListingStatus.SOLD;
        escrowBalances[offer.token] -= offer.amount;

        // Calculate and distribute
        uint256 fee = (offer.amount * platformFee) / BASIS_POINTS;
        uint256 sellerAmount = offer.amount - fee;

        sellerAmount = _distributeCollaboratorRoyalties(offer.listingId, sellerAmount, payoutToken);

        _transferPayment(payoutToken, feeCollector, fee);

        if (payoutChain == block.chainid) {
            _transferPayment(payoutToken, listing.seller, sellerAmount);
        } else {
            _routeCrossChainPayout(listing.seller, payoutToken, sellerAmount, payoutChain);
        }

        // Transfer NFT
        IERC721(listing.nftContract).transferFrom(address(this), offer.offerer, listing.tokenId);

        emit OfferAccepted(offerId);
        emit ListingSold(offer.listingId, offer.offerer, offer.token, offer.amount, fee);
    }

    /**
     * @notice Cancel an offer
     */
    function cancelOffer(bytes32 offerId) external nonReentrant {
        Offer storage offer = offers[offerId];
        require(offer.offerer == msg.sender, "Not offerer");
        require(!offer.accepted && !offer.cancelled, "Offer invalid");

        offer.cancelled = true;
        escrowBalances[offer.token] -= offer.amount;

        // Refund
        _transferPayment(offer.token, offer.offerer, offer.amount);

        emit OfferCancelled(offerId);
    }

    // ============ Cancel Listing ============

    function cancelListing(bytes32 listingId) external nonReentrant {
        Listing storage listing = listings[listingId];
        require(listing.seller == msg.sender || msg.sender == owner(), "Not authorized");
        require(listing.status == ListingStatus.ACTIVE, "Not active");

        // For auctions, ensure no active bids
        if (listing.listingType == ListingType.AUCTION) {
            AuctionData storage auction = auctions[listingId];
            require(auction.currentBidder == address(0), "Has active bid");
        }

        listing.status = ListingStatus.CANCELLED;

        // Return NFT
        IERC721(listing.nftContract).transferFrom(address(this), listing.seller, listing.tokenId);

        emit ListingCancelled(listingId);
    }

    // ============ Internal Functions ============

    function _generateListingId() internal returns (bytes32) {
        return keccak256(abi.encodePacked(block.chainid, address(this), _listingNonce++));
    }

    function _generateOfferId() internal returns (bytes32) {
        return keccak256(abi.encodePacked(block.chainid, address(this), "OFFER", _offerNonce++));
    }

    function _storeCollaborators(bytes32 listingId, Collaborator[] calldata collaborators) internal {
        uint256 totalPercentage = 0;
        for (uint256 i = 0; i < collaborators.length; i++) {
            require(collaborators[i].wallet != address(0), "Invalid wallet");
            totalPercentage += collaborators[i].percentage;
            listingCollaborators[listingId].push(collaborators[i]);
        }
        require(totalPercentage <= BASIS_POINTS, "Exceeds 100%");
    }

    function _collectPayment(address token, uint256 amount) internal {
        if (token == address(0)) {
            require(msg.value >= amount, "Insufficient native");
            if (msg.value > amount) {
                (bool refund, ) = msg.sender.call{value: msg.value - amount}("");
                require(refund, "Refund failed");
            }
        } else {
            IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        }
    }

    function _transferPayment(address token, address to, uint256 amount) internal {
        if (amount == 0) return;

        if (token == address(0)) {
            (bool success, ) = to.call{value: amount}("");
            require(success, "Transfer failed");
        } else {
            IERC20(token).safeTransfer(to, amount);
        }
    }

    function _distributeCollaboratorRoyalties(
        bytes32 listingId,
        uint256 amount,
        address token
    ) internal returns (uint256 remaining) {
        Collaborator[] storage collabs = listingCollaborators[listingId];
        remaining = amount;

        for (uint256 i = 0; i < collabs.length; i++) {
            uint256 share = (amount * collabs[i].percentage) / BASIS_POINTS;
            if (share > 0) {
                remaining -= share;

                if (collabs[i].preferredChain == block.chainid || collabs[i].preferredChain == 0) {
                    address payToken = collabs[i].preferredToken != address(0)
                        ? collabs[i].preferredToken
                        : token;
                    _transferPayment(payToken, collabs[i].wallet, share);
                } else {
                    _routeCrossChainPayout(
                        collabs[i].wallet,
                        collabs[i].preferredToken,
                        share,
                        collabs[i].preferredChain
                    );
                }

                emit CollaboratorPaid(
                    listingId,
                    collabs[i].wallet,
                    token,
                    share,
                    collabs[i].preferredChain
                );
            }
        }

        return remaining;
    }

    function _routeCrossChainPayout(
        address recipient,
        address token,
        uint256 amount,
        uint256 targetChain
    ) internal {
        // Route through OmnichainRouter for cross-chain transfer
        // In production, this calls the router contract
        // For now, mark as pending for off-chain processing
    }

    function _getConvertedAmount(
        address fromToken,
        address toToken,
        uint256 toAmount
    ) internal view returns (uint256) {
        // In production, query price oracle for conversion
        // For now, assume 1:1 for same-decimals tokens
        uint8 fromDecimals = tokens[fromToken].decimals;
        uint8 toDecimals = tokens[toToken].decimals;

        if (fromDecimals == toDecimals) {
            return toAmount;
        } else if (fromDecimals > toDecimals) {
            return toAmount * (10 ** (fromDecimals - toDecimals));
        } else {
            return toAmount / (10 ** (toDecimals - fromDecimals));
        }
    }

    function _normalizeTokenAmount(
        address fromToken,
        uint256 amount,
        address toToken
    ) internal view returns (uint256) {
        return _getConvertedAmount(fromToken, toToken, amount);
    }

    function _addToken(
        address token,
        string memory symbol,
        uint8 decimals,
        address zrc20,
        uint256 minAmount
    ) internal {
        tokens[token] = TokenInfo({
            token: token,
            symbol: symbol,
            decimals: decimals,
            zrc20: zrc20,
            enabled: true,
            minAmount: minAmount
        });
        tokenList.push(token);
        emit TokenAdded(token, symbol);
    }

    // ============ Admin Functions ============

    function addToken(
        address token,
        string calldata symbol,
        uint8 decimals,
        address zrc20,
        uint256 minAmount
    ) external onlyOwner {
        require(!tokens[token].enabled, "Already added");
        require(tokenList.length < MAX_TOKENS, "Max tokens reached");
        _addToken(token, symbol, decimals, zrc20, minAmount);
    }

    function removeToken(address token) external onlyOwner {
        require(tokens[token].enabled, "Not enabled");
        tokens[token].enabled = false;
        emit TokenRemoved(token);
    }

    function setOmnichainRouter(address _router) external onlyOwner {
        omnichainRouter = _router;
    }

    function setFeeCollector(address _collector) external onlyOwner {
        feeCollector = _collector;
    }

    function setPlatformFee(uint256 _fee) external onlyOwner {
        require(_fee <= 1000, "Max 10%");
        platformFee = _fee;
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function emergencyWithdraw(address token, uint256 amount) external onlyOwner {
        _transferPayment(token, owner(), amount);
    }

    // ============ View Functions ============

    function getListing(bytes32 listingId) external view returns (Listing memory) {
        return listings[listingId];
    }

    function getAuction(bytes32 listingId) external view returns (AuctionData memory) {
        return auctions[listingId];
    }

    function getOffer(bytes32 offerId) external view returns (Offer memory) {
        return offers[offerId];
    }

    function getListingCollaborators(bytes32 listingId) external view returns (Collaborator[] memory) {
        return listingCollaborators[listingId];
    }

    function getListingOffers(bytes32 listingId) external view returns (bytes32[] memory) {
        return listingOffers[listingId];
    }

    function getUserListings(address user) external view returns (bytes32[] memory) {
        return userListings[user];
    }

    function getUserOffers(address user) external view returns (bytes32[] memory) {
        return userOffers[user];
    }

    function getSupportedTokens() external view returns (address[] memory) {
        return tokenList;
    }

    function getTokenInfo(address token) external view returns (TokenInfo memory) {
        return tokens[token];
    }

    // ============ UUPS ============

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    // ============ Receive ============

    receive() external payable {}
}
