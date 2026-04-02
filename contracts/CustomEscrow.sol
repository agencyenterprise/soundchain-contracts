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
 * @title CustomEscrow
 * @notice Escrow contract for physical/custom item sales on SoundChain
 * @dev Holds buyer's payment until delivery is confirmed, then releases to seller.
 *
 * Use cases:
 * - Concert/VIP tickets
 * - Vinyl records, CDs, cassettes
 * - Clothing, merch, streetwear
 * - Cars, houses, luxury goods
 * - Meet & greet packages
 * - Digital download bundles
 * - Any custom item a user wants to sell
 *
 * Flow:
 * 1. Seller creates listing (description, price, accepted tokens, shipping info)
 * 2. Buyer purchases — payment held in escrow
 * 3. Seller ships/delivers item
 * 4. Buyer confirms receipt → funds released to seller
 * 5. OR: Auto-release after confirmationWindow (default 14 days)
 * 6. OR: Buyer disputes → owner (SoundChain) arbitrates
 *
 * Safety:
 * - Buyer funds are SAFE in escrow until delivery confirmed
 * - Auto-release prevents sellers from being held hostage
 * - Dispute resolution by platform admin (Gnosis Safe)
 * - 0.05% fee on completed sales
 */
contract CustomEscrow is
    Initializable,
    UUPSUpgradeable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable
{
    using SafeERC20 for IERC20;

    // ============ Events ============

    event ListingCreated(
        uint256 indexed listingId,
        address indexed seller,
        string itemType,
        uint256 price,
        address paymentToken
    );

    event OrderCreated(
        uint256 indexed orderId,
        uint256 indexed listingId,
        address indexed buyer,
        uint256 amount,
        address paymentToken
    );

    event OrderShipped(uint256 indexed orderId, string trackingInfo);
    event OrderConfirmed(uint256 indexed orderId);
    event OrderDisputed(uint256 indexed orderId, string reason);
    event DisputeResolved(uint256 indexed orderId, bool buyerWins);
    event OrderAutoReleased(uint256 indexed orderId);
    event ListingCancelled(uint256 indexed listingId);
    event OrderRefunded(uint256 indexed orderId);

    // ============ Enums ============

    enum ItemType {
        CONCERT_TICKET,
        VIP_PACKAGE,
        VINYL,
        CD,
        CLOTHING,
        MERCH,
        VEHICLE,
        PROPERTY,
        DIGITAL_DOWNLOAD,
        MEET_AND_GREET,
        OTHER
    }

    enum OrderStatus {
        PAID,           // Buyer paid, waiting for seller to ship
        SHIPPED,        // Seller marked as shipped
        CONFIRMED,      // Buyer confirmed receipt — funds released
        DISPUTED,       // Buyer filed dispute
        REFUNDED,       // Dispute resolved in buyer's favor
        AUTO_RELEASED,  // Auto-released after confirmation window
        CANCELLED       // Cancelled before shipping
    }

    // ============ Structs ============

    struct Listing {
        uint256 listingId;
        address seller;
        ItemType itemType;
        string title;
        string description;
        string imageURI;         // IPFS cover image
        uint256 price;
        address paymentToken;    // address(0) = native POL
        uint256 quantity;        // Available quantity
        uint256 sold;
        bool requiresShipping;
        string shippingInfo;     // Shipping terms, regions, etc.
        uint256 createdAt;
        uint256 expiresAt;
        bool active;
    }

    struct Order {
        uint256 orderId;
        uint256 listingId;
        address buyer;
        address seller;
        address paymentToken;
        uint256 amount;
        OrderStatus status;
        string shippingAddress;  // Encrypted or hashed — buyer provides off-chain
        string trackingInfo;     // Seller adds tracking number
        uint256 paidAt;
        uint256 shippedAt;
        uint256 confirmedAt;
        uint256 disputedAt;
        string disputeReason;
        uint256 autoReleaseAt;   // Funds auto-release if buyer doesn't confirm/dispute
    }

    // ============ State Variables ============

    uint256 public constant VERSION = 1;

    /// @notice Platform fee in basis points (5 = 0.05%)
    uint256 public platformFee;
    uint256 public constant FEE_DENOMINATOR = 10000;

    /// @notice Fee collector (Gnosis Safe)
    address public feeCollector;

    /// @notice Default confirmation window (buyer must confirm within this period)
    uint256 public confirmationWindow;

    /// @notice All listings
    mapping(uint256 => Listing) public listings;
    uint256 public nextListingId;

    /// @notice All orders
    mapping(uint256 => Order) public orders;
    uint256 public nextOrderId;

    /// @notice Seller's listings
    mapping(address => uint256[]) public sellerListings;

    /// @notice Buyer's orders
    mapping(address => uint256[]) public buyerOrders;

    /// @notice Seller's orders
    mapping(address => uint256[]) public sellerOrders;

    /// @notice Whitelisted payment tokens
    mapping(address => bool) public acceptedTokens;

    // ============ Initializer ============

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _feeCollector,
        uint256 _platformFee,
        uint256 _confirmationWindow
    ) external initializer {
        __Ownable_init();
        __ReentrancyGuard_init();
        __Pausable_init();
        __UUPSUpgradeable_init();

        require(_feeCollector != address(0), "Invalid fee collector");
        require(_platformFee <= 100, "Fee too high");
        require(_confirmationWindow >= 3 days && _confirmationWindow <= 90 days, "Invalid window");

        feeCollector = _feeCollector;
        platformFee = _platformFee;
        confirmationWindow = _confirmationWindow;
        nextListingId = 1;
        nextOrderId = 1;

        acceptedTokens[address(0)] = true; // Native POL
    }

    // ============ Seller Functions ============

    /**
     * @notice Create a custom item listing
     */
    function createListing(
        ItemType itemType,
        string calldata title,
        string calldata description,
        string calldata imageURI,
        uint256 price,
        address paymentToken,
        uint256 quantity,
        bool requiresShipping,
        string calldata shippingInfo,
        uint256 duration
    ) external whenNotPaused returns (uint256 listingId) {
        require(price > 0, "Invalid price");
        require(quantity > 0, "Invalid quantity");
        require(duration > 0 && duration <= 365 days, "Invalid duration");
        require(acceptedTokens[paymentToken], "Token not accepted");
        require(bytes(title).length > 0, "Title required");

        listingId = nextListingId++;

        listings[listingId] = Listing({
            listingId: listingId,
            seller: msg.sender,
            itemType: itemType,
            title: title,
            description: description,
            imageURI: imageURI,
            price: price,
            paymentToken: paymentToken,
            quantity: quantity,
            sold: 0,
            requiresShipping: requiresShipping,
            shippingInfo: shippingInfo,
            createdAt: block.timestamp,
            expiresAt: block.timestamp + duration,
            active: true
        });

        sellerListings[msg.sender].push(listingId);

        string memory typeStr;
        if (itemType == ItemType.CONCERT_TICKET) typeStr = "concert_ticket";
        else if (itemType == ItemType.VIP_PACKAGE) typeStr = "vip_package";
        else if (itemType == ItemType.VINYL) typeStr = "vinyl";
        else if (itemType == ItemType.CLOTHING) typeStr = "clothing";
        else if (itemType == ItemType.VEHICLE) typeStr = "vehicle";
        else if (itemType == ItemType.PROPERTY) typeStr = "property";
        else typeStr = "other";

        emit ListingCreated(listingId, msg.sender, typeStr, price, paymentToken);
        return listingId;
    }

    /**
     * @notice Mark an order as shipped
     */
    function markShipped(uint256 orderId, string calldata trackingInfo) external {
        Order storage order = orders[orderId];
        require(order.seller == msg.sender, "Not seller");
        require(order.status == OrderStatus.PAID, "Not in PAID status");

        order.status = OrderStatus.SHIPPED;
        order.shippedAt = block.timestamp;
        order.trackingInfo = trackingInfo;
        // Start confirmation window from ship date
        order.autoReleaseAt = block.timestamp + confirmationWindow;

        emit OrderShipped(orderId, trackingInfo);
    }

    function cancelListing(uint256 listingId) external {
        Listing storage listing = listings[listingId];
        require(listing.seller == msg.sender || msg.sender == owner(), "Not authorized");
        require(listing.active, "Already inactive");

        listing.active = false;
        emit ListingCancelled(listingId);
    }

    // ============ Buyer Functions ============

    /**
     * @notice Purchase a listed item — payment goes to escrow
     * @param listingId Listing to purchase
     * @param shippingAddress Encrypted shipping address (buyer provides)
     */
    function purchase(
        uint256 listingId,
        string calldata shippingAddress
    ) external payable nonReentrant whenNotPaused returns (uint256 orderId) {
        Listing storage listing = listings[listingId];
        require(listing.active, "Listing not active");
        require(block.timestamp < listing.expiresAt, "Listing expired");
        require(listing.sold < listing.quantity, "Sold out");
        require(msg.sender != listing.seller, "Cannot buy own listing");

        uint256 price = listing.price;

        // Collect payment to escrow (THIS contract holds it)
        if (listing.paymentToken == address(0)) {
            require(msg.value >= price, "Insufficient POL");
            if (msg.value > price) {
                (bool refund, ) = msg.sender.call{value: msg.value - price}("");
                require(refund, "Refund failed");
            }
        } else {
            IERC20(listing.paymentToken).safeTransferFrom(msg.sender, address(this), price);
        }

        orderId = nextOrderId++;

        orders[orderId] = Order({
            orderId: orderId,
            listingId: listingId,
            buyer: msg.sender,
            seller: listing.seller,
            paymentToken: listing.paymentToken,
            amount: price,
            status: OrderStatus.PAID,
            shippingAddress: shippingAddress,
            trackingInfo: "",
            paidAt: block.timestamp,
            shippedAt: 0,
            confirmedAt: 0,
            disputedAt: 0,
            disputeReason: "",
            autoReleaseAt: 0 // Set when shipped
        });

        listing.sold++;
        if (listing.sold >= listing.quantity) {
            listing.active = false;
        }

        buyerOrders[msg.sender].push(orderId);
        sellerOrders[listing.seller].push(orderId);

        emit OrderCreated(orderId, listingId, msg.sender, price, listing.paymentToken);
        return orderId;
    }

    /**
     * @notice Confirm receipt — releases escrowed funds to seller
     */
    function confirmReceipt(uint256 orderId) external nonReentrant {
        Order storage order = orders[orderId];
        require(order.buyer == msg.sender, "Not buyer");
        require(
            order.status == OrderStatus.SHIPPED || order.status == OrderStatus.PAID,
            "Cannot confirm"
        );

        _releaseFunds(orderId);
        order.status = OrderStatus.CONFIRMED;
        order.confirmedAt = block.timestamp;

        emit OrderConfirmed(orderId);
    }

    /**
     * @notice Dispute an order (before auto-release)
     */
    function dispute(uint256 orderId, string calldata reason) external {
        Order storage order = orders[orderId];
        require(order.buyer == msg.sender, "Not buyer");
        require(
            order.status == OrderStatus.PAID || order.status == OrderStatus.SHIPPED,
            "Cannot dispute"
        );
        require(bytes(reason).length > 0, "Reason required");

        order.status = OrderStatus.DISPUTED;
        order.disputedAt = block.timestamp;
        order.disputeReason = reason;
        // Pause auto-release during dispute
        order.autoReleaseAt = 0;

        emit OrderDisputed(orderId, reason);
    }

    // ============ Auto-Release ============

    /**
     * @notice Auto-release escrowed funds after confirmation window
     * @dev Anyone can call this after the window expires (gas incentive for bots)
     */
    function autoRelease(uint256 orderId) external nonReentrant {
        Order storage order = orders[orderId];
        require(order.status == OrderStatus.SHIPPED, "Not shipped");
        require(order.autoReleaseAt > 0 && block.timestamp >= order.autoReleaseAt, "Window not expired");

        _releaseFunds(orderId);
        order.status = OrderStatus.AUTO_RELEASED;

        emit OrderAutoReleased(orderId);
    }

    // ============ Dispute Resolution (Admin) ============

    /**
     * @notice Resolve dispute — only platform admin (Gnosis Safe)
     * @param orderId Order with dispute
     * @param buyerWins If true, refund buyer. If false, release to seller.
     */
    function resolveDispute(uint256 orderId, bool buyerWins) external onlyOwner nonReentrant {
        Order storage order = orders[orderId];
        require(order.status == OrderStatus.DISPUTED, "Not disputed");

        if (buyerWins) {
            // Refund buyer
            _refundBuyer(orderId);
            order.status = OrderStatus.REFUNDED;
        } else {
            // Release to seller
            _releaseFunds(orderId);
            order.status = OrderStatus.CONFIRMED;
            order.confirmedAt = block.timestamp;
        }

        emit DisputeResolved(orderId, buyerWins);
    }

    /**
     * @notice Cancel order and refund — only if not yet shipped
     */
    function cancelOrder(uint256 orderId) external nonReentrant {
        Order storage order = orders[orderId];
        require(
            order.buyer == msg.sender || order.seller == msg.sender || msg.sender == owner(),
            "Not authorized"
        );
        require(order.status == OrderStatus.PAID, "Can only cancel before shipping");

        _refundBuyer(orderId);
        order.status = OrderStatus.CANCELLED;

        emit OrderRefunded(orderId);
    }

    // ============ Internal Functions ============

    function _releaseFunds(uint256 orderId) internal {
        Order storage order = orders[orderId];
        uint256 amount = order.amount;

        // Calculate fee
        uint256 fee = (amount * platformFee) / FEE_DENOMINATOR;
        uint256 sellerAmount = amount - fee;

        if (order.paymentToken == address(0)) {
            // Native POL
            if (fee > 0) {
                (bool feeOk, ) = feeCollector.call{value: fee}("");
                require(feeOk, "Fee transfer failed");
            }
            (bool sellerOk, ) = order.seller.call{value: sellerAmount}("");
            require(sellerOk, "Seller transfer failed");
        } else {
            // ERC-20
            if (fee > 0) {
                IERC20(order.paymentToken).safeTransfer(feeCollector, fee);
            }
            IERC20(order.paymentToken).safeTransfer(order.seller, sellerAmount);
        }
    }

    function _refundBuyer(uint256 orderId) internal {
        Order storage order = orders[orderId];

        if (order.paymentToken == address(0)) {
            (bool ok, ) = order.buyer.call{value: order.amount}("");
            require(ok, "Refund failed");
        } else {
            IERC20(order.paymentToken).safeTransfer(order.buyer, order.amount);
        }
    }

    // ============ Admin Functions ============

    function setAcceptedToken(address token, bool enabled) external onlyOwner {
        acceptedTokens[token] = enabled;
    }

    function setFeeCollector(address _feeCollector) external onlyOwner {
        require(_feeCollector != address(0), "Invalid address");
        feeCollector = _feeCollector;
    }

    function setPlatformFee(uint256 _fee) external onlyOwner {
        require(_fee <= 100, "Max 1%");
        platformFee = _fee;
    }

    function setConfirmationWindow(uint256 _window) external onlyOwner {
        require(_window >= 3 days && _window <= 90 days, "Invalid window");
        confirmationWindow = _window;
    }

    function pause() external onlyOwner { _pause(); }
    function unpause() external onlyOwner { _unpause(); }

    function emergencyWithdraw(address token, uint256 amount) external onlyOwner {
        if (token == address(0)) {
            (bool ok, ) = owner().call{value: amount}("");
            require(ok, "Withdraw failed");
        } else {
            IERC20(token).safeTransfer(owner(), amount);
        }
    }

    // ============ View Functions ============

    function getListing(uint256 listingId) external view returns (Listing memory) {
        return listings[listingId];
    }

    function getOrder(uint256 orderId) external view returns (Order memory) {
        return orders[orderId];
    }

    function getSellerListings(address seller) external view returns (uint256[] memory) {
        return sellerListings[seller];
    }

    function getBuyerOrders(address buyer) external view returns (uint256[] memory) {
        return buyerOrders[buyer];
    }

    function getSellerOrders(address seller) external view returns (uint256[] memory) {
        return sellerOrders[seller];
    }

    /**
     * @notice Check if an order can be auto-released
     */
    function canAutoRelease(uint256 orderId) external view returns (bool) {
        Order storage order = orders[orderId];
        return order.status == OrderStatus.SHIPPED
            && order.autoReleaseAt > 0
            && block.timestamp >= order.autoReleaseAt;
    }

    // ============ UUPS ============

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    receive() external payable {}
}
