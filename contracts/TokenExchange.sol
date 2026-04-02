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
 * @title TokenExchange
 * @notice P2P token exchange — sell OGUN, POL, ETH, or any ERC-20 for any other token
 * @dev Approval-based: seller approves this contract, buyer calls purchase.
 *      No escrow needed — instant atomic swap. 0.05% fee to treasury.
 *
 * Use cases:
 * - Sell OGUN competing with Coinbase (0.05% vs 0.08% taker fee)
 * - Any user can become a market maker
 * - 24 tokens supported via ZetaChain omnichain
 * - Every user's shop tab is their OTC desk
 *
 * Flow:
 * 1. Seller approves TokenExchange to spend their tokens
 * 2. Seller calls createListing(sellToken, sellAmount, askToken, askAmount)
 * 3. Listing stored on-chain, visible in shop tab
 * 4. Buyer approves TokenExchange to spend their askToken
 * 5. Buyer calls purchase(listingId) — atomic swap happens
 * 6. 0.05% fee deducted from seller side, sent to treasury
 *
 * Partial fills supported — buyer can purchase a portion of the listing.
 */
contract TokenExchange is
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
        address sellToken,
        uint256 sellAmount,
        address askToken,
        uint256 askAmount
    );

    event ListingFilled(
        uint256 indexed listingId,
        address indexed buyer,
        uint256 sellAmountFilled,
        uint256 askAmountPaid,
        uint256 fee
    );

    event ListingCancelled(uint256 indexed listingId);

    event TokenWhitelisted(address indexed token, string symbol, bool enabled);

    // ============ Structs ============

    struct Listing {
        uint256 listingId;
        address seller;
        address sellToken;       // Token being sold (address(0) = native POL)
        uint256 sellAmount;      // Total amount to sell
        uint256 sellRemaining;   // Amount remaining (partial fills)
        address askToken;        // Token seller wants in return (address(0) = native POL)
        uint256 askAmount;       // Total ask price for full sellAmount
        uint256 createdAt;
        uint256 expiresAt;
        bool active;
    }

    struct TokenInfo {
        string symbol;
        uint8 decimals;
        bool enabled;
    }

    // ============ State Variables ============

    uint256 public constant VERSION = 1;

    /// @notice Platform fee in basis points (5 = 0.05%)
    uint256 public platformFee;
    uint256 public constant FEE_DENOMINATOR = 10000;

    /// @notice Fee collector (Gnosis Safe treasury)
    address public feeCollector;

    /// @notice All listings
    mapping(uint256 => Listing) public listings;

    /// @notice Listing counter
    uint256 public nextListingId;

    /// @notice Whitelisted tokens
    mapping(address => TokenInfo) public whitelistedTokens;
    address[] public tokenList;

    /// @notice User's active listing IDs
    mapping(address => uint256[]) public userListings;

    // ============ Initializer ============

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initialize the exchange
     * @param _feeCollector Gnosis Safe treasury address
     * @param _platformFee Fee in basis points (5 = 0.05%)
     */
    function initialize(
        address _feeCollector,
        uint256 _platformFee
    ) external initializer {
        __Ownable_init();
        __ReentrancyGuard_init();
        __Pausable_init();
        __UUPSUpgradeable_init();

        require(_feeCollector != address(0), "Invalid fee collector");
        require(_platformFee <= 100, "Fee too high"); // Max 1%

        feeCollector = _feeCollector;
        platformFee = _platformFee;
        nextListingId = 1;

        // Native token (POL) is always accepted
        whitelistedTokens[address(0)] = TokenInfo("POL", 18, true);
    }

    // ============ Listing Functions ============

    /**
     * @notice Create a token listing — sell ERC-20 tokens for another token
     * @param sellToken Token to sell (address(0) for native POL)
     * @param sellAmount Amount to sell
     * @param askToken Token to receive (address(0) for native POL)
     * @param askAmount Price — total amount of askToken for the full sellAmount
     * @param duration Listing duration in seconds (max 90 days)
     * @return listingId The new listing ID
     *
     * @dev Seller must approve this contract for sellAmount BEFORE calling.
     *      For native POL listings, send POL with the transaction.
     */
    function createListing(
        address sellToken,
        uint256 sellAmount,
        address askToken,
        uint256 askAmount,
        uint256 duration
    ) external payable nonReentrant whenNotPaused returns (uint256 listingId) {
        require(sellAmount > 0, "Zero sell amount");
        require(askAmount > 0, "Zero ask amount");
        require(sellToken != askToken, "Same token");
        require(duration > 0 && duration <= 90 days, "Invalid duration");
        require(whitelistedTokens[sellToken].enabled, "Sell token not supported");
        require(whitelistedTokens[askToken].enabled, "Ask token not supported");

        // Verify seller has the tokens and has approved
        if (sellToken == address(0)) {
            // Selling native POL — must send with tx
            require(msg.value >= sellAmount, "Send POL with tx");
            // Refund excess
            if (msg.value > sellAmount) {
                (bool refund, ) = msg.sender.call{value: msg.value - sellAmount}("");
                require(refund, "Refund failed");
            }
        } else {
            // Selling ERC-20 — verify allowance (don't transfer yet, approval-based)
            require(
                IERC20(sellToken).allowance(msg.sender, address(this)) >= sellAmount,
                "Approve tokens first"
            );
            require(
                IERC20(sellToken).balanceOf(msg.sender) >= sellAmount,
                "Insufficient balance"
            );
        }

        listingId = nextListingId++;

        listings[listingId] = Listing({
            listingId: listingId,
            seller: msg.sender,
            sellToken: sellToken,
            sellAmount: sellAmount,
            sellRemaining: sellAmount,
            askToken: askToken,
            askAmount: askAmount,
            createdAt: block.timestamp,
            expiresAt: block.timestamp + duration,
            active: true
        });

        userListings[msg.sender].push(listingId);

        emit ListingCreated(listingId, msg.sender, sellToken, sellAmount, askToken, askAmount);
        return listingId;
    }

    /**
     * @notice Purchase tokens from a listing (full or partial)
     * @param listingId Listing to buy from
     * @param buyAmount Amount of sellToken to buy (use sellRemaining for full fill)
     *
     * @dev Buyer must approve this contract for the proportional askToken amount.
     *      For native POL payments, send POL with the transaction.
     *
     * Atomic swap:
     * 1. Calculate proportional cost: cost = (buyAmount / sellAmount) * askAmount
     * 2. Deduct 0.05% fee from seller's side
     * 3. Transfer askToken from buyer → seller
     * 4. Transfer sellToken from seller → buyer (or from contract for native)
     * 5. Fee sent to treasury in sellToken
     */
    function purchase(
        uint256 listingId,
        uint256 buyAmount
    ) external payable nonReentrant whenNotPaused {
        Listing storage listing = listings[listingId];

        require(listing.active, "Listing not active");
        require(block.timestamp < listing.expiresAt, "Listing expired");
        require(buyAmount > 0 && buyAmount <= listing.sellRemaining, "Invalid buy amount");
        require(msg.sender != listing.seller, "Cannot buy own listing");

        // Calculate proportional cost
        // cost = (buyAmount * askAmount) / sellAmount — rounds up to protect seller
        uint256 cost = (buyAmount * listing.askAmount + listing.sellAmount - 1) / listing.sellAmount;

        // Calculate fee on the sell side (0.05%)
        uint256 fee = (buyAmount * platformFee) / FEE_DENOMINATOR;
        uint256 sellerSends = buyAmount - fee; // Buyer gets slightly less, fee goes to treasury

        // === Collect payment from buyer (askToken) ===
        if (listing.askToken == address(0)) {
            require(msg.value >= cost, "Insufficient POL sent");
            // Send payment to seller
            (bool paySuccess, ) = listing.seller.call{value: cost}("");
            require(paySuccess, "Payment to seller failed");
            // Refund excess
            if (msg.value > cost) {
                (bool refund, ) = msg.sender.call{value: msg.value - cost}("");
                require(refund, "Refund failed");
            }
        } else {
            // ERC-20 payment: buyer → seller
            IERC20(listing.askToken).safeTransferFrom(msg.sender, listing.seller, cost);
        }

        // === Send tokens from seller to buyer + fee to treasury ===
        if (listing.sellToken == address(0)) {
            // Native POL was deposited on listing creation
            // Send to buyer
            (bool buyerSuccess, ) = msg.sender.call{value: sellerSends}("");
            require(buyerSuccess, "Transfer to buyer failed");
            // Send fee to treasury
            if (fee > 0) {
                (bool feeSuccess, ) = feeCollector.call{value: fee}("");
                require(feeSuccess, "Fee transfer failed");
            }
        } else {
            // ERC-20: pull from seller (approval-based)
            IERC20(listing.sellToken).safeTransferFrom(listing.seller, msg.sender, sellerSends);
            if (fee > 0) {
                IERC20(listing.sellToken).safeTransferFrom(listing.seller, feeCollector, fee);
            }
        }

        // Update listing
        listing.sellRemaining -= buyAmount;
        if (listing.sellRemaining == 0) {
            listing.active = false;
        }

        emit ListingFilled(listingId, msg.sender, buyAmount, cost, fee);
    }

    /**
     * @notice Cancel a listing and refund any escrowed native tokens
     * @param listingId Listing to cancel
     */
    function cancelListing(uint256 listingId) external nonReentrant {
        Listing storage listing = listings[listingId];
        require(listing.seller == msg.sender || msg.sender == owner(), "Not authorized");
        require(listing.active, "Already inactive");

        listing.active = false;

        // Refund escrowed native tokens if selling POL
        if (listing.sellToken == address(0) && listing.sellRemaining > 0) {
            (bool success, ) = listing.seller.call{value: listing.sellRemaining}("");
            require(success, "Refund failed");
        }

        emit ListingCancelled(listingId);
    }

    // ============ Admin Functions ============

    /**
     * @notice Whitelist a token for trading
     */
    function whitelistToken(
        address token,
        string calldata symbol,
        uint8 decimals
    ) external onlyOwner {
        whitelistedTokens[token] = TokenInfo(symbol, decimals, true);

        // Add to list if not present
        bool exists = false;
        for (uint256 i = 0; i < tokenList.length; i++) {
            if (tokenList[i] == token) { exists = true; break; }
        }
        if (!exists) tokenList.push(token);

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
        require(tokens.length == symbols.length && tokens.length == decimals.length, "Length mismatch");
        for (uint256 i = 0; i < tokens.length; i++) {
            whitelistedTokens[tokens[i]] = TokenInfo(symbols[i], decimals[i], true);
            bool exists = false;
            for (uint256 j = 0; j < tokenList.length; j++) {
                if (tokenList[j] == tokens[i]) { exists = true; break; }
            }
            if (!exists) tokenList.push(tokens[i]);
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

    function setPlatformFee(uint256 _fee) external onlyOwner {
        require(_fee <= 100, "Max 1%");
        platformFee = _fee;
    }

    function pause() external onlyOwner { _pause(); }
    function unpause() external onlyOwner { _unpause(); }

    /// @notice Emergency withdraw stuck tokens (should never be needed for ERC-20 approval-based)
    function emergencyWithdraw(address token, uint256 amount) external onlyOwner {
        if (token == address(0)) {
            (bool success, ) = owner().call{value: amount}("");
            require(success, "Withdraw failed");
        } else {
            IERC20(token).safeTransfer(owner(), amount);
        }
    }

    // ============ View Functions ============

    function getListing(uint256 listingId) external view returns (Listing memory) {
        return listings[listingId];
    }

    function getUserListings(address user) external view returns (uint256[] memory) {
        return userListings[user];
    }

    function getActiveListings(uint256 offset, uint256 limit) external view returns (Listing[] memory) {
        uint256 count = 0;
        uint256 max = nextListingId;

        // Count active listings
        for (uint256 i = 1; i < max; i++) {
            if (listings[i].active && block.timestamp < listings[i].expiresAt) {
                count++;
            }
        }

        if (offset >= count) return new Listing[](0);
        uint256 resultSize = count - offset < limit ? count - offset : limit;
        Listing[] memory result = new Listing[](resultSize);

        uint256 idx = 0;
        uint256 skipped = 0;
        for (uint256 i = 1; i < max && idx < resultSize; i++) {
            if (listings[i].active && block.timestamp < listings[i].expiresAt) {
                if (skipped >= offset) {
                    result[idx++] = listings[i];
                } else {
                    skipped++;
                }
            }
        }

        return result;
    }

    function getWhitelistedTokens() external view returns (address[] memory) {
        return tokenList;
    }

    function isTokenWhitelisted(address token) external view returns (bool) {
        return whitelistedTokens[token].enabled;
    }

    /**
     * @notice Calculate the cost for a partial purchase
     * @param listingId Listing ID
     * @param buyAmount Amount of sellToken to buy
     * @return cost Amount of askToken buyer must pay
     * @return fee Fee deducted from sellToken side
     */
    function quotePurchase(uint256 listingId, uint256 buyAmount) external view returns (
        uint256 cost,
        uint256 fee
    ) {
        Listing storage listing = listings[listingId];
        cost = (buyAmount * listing.askAmount + listing.sellAmount - 1) / listing.sellAmount;
        fee = (buyAmount * platformFee) / FEE_DENOMINATOR;
    }

    // ============ UUPS ============

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    receive() external payable {}
}
