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
 * @title SweepProxy
 * @notice Batch NFT operations for SoundChain - sweep, bundle, and batch transfers
 * @dev Upgradeable proxy contract for gas-efficient multi-NFT transactions
 *
 * Features:
 * - Sweep floor: Buy multiple NFTs in one transaction
 * - Bundle purchase: Buy a curated set of NFTs
 * - Batch transfer: Send multiple NFTs to one or many recipients
 * - Batch approve: Approve marketplace for multiple NFTs
 * - Airdrop: Distribute NFTs to multiple wallets
 */
contract SweepProxy is
    Initializable,
    UUPSUpgradeable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable
{
    using SafeERC20 for IERC20;

    // ============ Events ============

    event SweepExecuted(
        address indexed buyer,
        address indexed nftContract,
        uint256[] tokenIds,
        uint256 totalPrice,
        address paymentToken
    );

    event BundlePurchased(
        address indexed buyer,
        bytes32 indexed bundleId,
        uint256 itemCount,
        uint256 totalPrice
    );

    event BatchTransfer(
        address indexed from,
        address indexed nftContract,
        uint256[] tokenIds,
        address[] recipients
    );

    event AirdropExecuted(
        address indexed sender,
        address indexed nftContract,
        uint256[] tokenIds,
        address[] recipients
    );

    event MarketplaceUpdated(address indexed marketplace, bool approved);

    event FeeUpdated(uint256 oldFee, uint256 newFee);

    // ============ Structs ============

    struct SweepOrder {
        address nftContract;
        uint256 tokenId;
        uint256 price;
        address seller;
        address paymentToken; // address(0) for native
        bytes signature;
    }

    struct BundleItem {
        address nftContract;
        uint256 tokenId;
        bool isERC1155;
        uint256 amount; // For ERC1155
    }

    struct Bundle {
        bytes32 bundleId;
        BundleItem[] items;
        uint256 price;
        address paymentToken;
        address seller;
        uint256 expiresAt;
        bool active;
    }

    // ============ State Variables ============

    /// @notice Version for upgrades
    uint256 public constant VERSION = 1;

    /// @notice Platform fee in basis points (100 = 1%)
    uint256 public platformFee;

    /// @notice Fee denominator
    uint256 public constant FEE_DENOMINATOR = 10000;

    /// @notice Fee collector address
    address public feeCollector;

    /// @notice Approved marketplaces for order execution
    mapping(address => bool) public approvedMarketplaces;

    /// @notice Bundles by ID
    mapping(bytes32 => Bundle) public bundles;

    /// @notice Maximum items per sweep
    uint256 public maxSweepSize;

    /// @notice Nonce for bundle ID generation
    uint256 private _bundleNonce;

    // ============ Initializer ============

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initialize the contract
     * @param _feeCollector Address to receive platform fees
     * @param _platformFee Platform fee in basis points
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
        require(_platformFee <= 1000, "Fee too high"); // Max 10%

        feeCollector = _feeCollector;
        platformFee = _platformFee;
        maxSweepSize = 50; // Default max 50 NFTs per sweep
    }

    // ============ Sweep Functions ============

    /**
     * @notice Sweep multiple NFTs from the floor
     * @param orders Array of sweep orders
     * @dev Executes purchases and transfers all NFTs to caller
     */
    function sweep(
        SweepOrder[] calldata orders
    ) external payable nonReentrant whenNotPaused {
        require(orders.length > 0 && orders.length <= maxSweepSize, "Invalid order count");

        uint256 totalNativeRequired = 0;
        uint256[] memory tokenIds = new uint256[](orders.length);

        for (uint256 i = 0; i < orders.length; i++) {
            SweepOrder calldata order = orders[i];

            if (order.paymentToken == address(0)) {
                totalNativeRequired += order.price;
            }

            tokenIds[i] = order.tokenId;
        }

        // Check native balance
        require(msg.value >= totalNativeRequired, "Insufficient native payment");

        // Execute each order
        for (uint256 i = 0; i < orders.length; i++) {
            _executeSweepOrder(orders[i], msg.sender);
        }

        // Refund excess
        if (msg.value > totalNativeRequired) {
            (bool success, ) = msg.sender.call{value: msg.value - totalNativeRequired}("");
            require(success, "Refund failed");
        }

        emit SweepExecuted(
            msg.sender,
            orders[0].nftContract,
            tokenIds,
            totalNativeRequired,
            address(0)
        );
    }

    /**
     * @notice Sweep with ERC20 token payment
     * @param orders Array of sweep orders
     * @param paymentToken ERC20 token for payment
     * @param maxTotalPrice Maximum total to spend
     */
    function sweepWithToken(
        SweepOrder[] calldata orders,
        address paymentToken,
        uint256 maxTotalPrice
    ) external nonReentrant whenNotPaused {
        require(orders.length > 0 && orders.length <= maxSweepSize, "Invalid order count");
        require(paymentToken != address(0), "Use sweep() for native");

        uint256 totalRequired = 0;
        uint256[] memory tokenIds = new uint256[](orders.length);

        for (uint256 i = 0; i < orders.length; i++) {
            require(orders[i].paymentToken == paymentToken, "Token mismatch");
            totalRequired += orders[i].price;
            tokenIds[i] = orders[i].tokenId;
        }

        require(totalRequired <= maxTotalPrice, "Exceeds max price");

        // Transfer tokens from buyer
        IERC20(paymentToken).safeTransferFrom(msg.sender, address(this), totalRequired);

        // Execute each order
        for (uint256 i = 0; i < orders.length; i++) {
            _executeSweepOrder(orders[i], msg.sender);
        }

        emit SweepExecuted(
            msg.sender,
            orders[0].nftContract,
            tokenIds,
            totalRequired,
            paymentToken
        );
    }

    // ============ Bundle Functions ============

    /**
     * @notice Create a bundle for sale
     * @param items Array of NFTs in the bundle
     * @param price Bundle price
     * @param paymentToken Payment token (address(0) for native)
     * @param duration Bundle validity duration in seconds
     */
    function createBundle(
        BundleItem[] calldata items,
        uint256 price,
        address paymentToken,
        uint256 duration
    ) external nonReentrant returns (bytes32 bundleId) {
        require(items.length > 0 && items.length <= 100, "Invalid bundle size");
        require(duration > 0 && duration <= 30 days, "Invalid duration");

        bundleId = keccak256(
            abi.encodePacked(msg.sender, block.timestamp, _bundleNonce++)
        );

        Bundle storage bundle = bundles[bundleId];
        bundle.bundleId = bundleId;
        bundle.price = price;
        bundle.paymentToken = paymentToken;
        bundle.seller = msg.sender;
        bundle.expiresAt = block.timestamp + duration;
        bundle.active = true;

        // Copy items and verify ownership
        for (uint256 i = 0; i < items.length; i++) {
            BundleItem calldata item = items[i];

            if (item.isERC1155) {
                require(
                    IERC1155(item.nftContract).balanceOf(msg.sender, item.tokenId) >= item.amount,
                    "Insufficient ERC1155 balance"
                );
            } else {
                require(
                    IERC721(item.nftContract).ownerOf(item.tokenId) == msg.sender,
                    "Not ERC721 owner"
                );
            }

            bundle.items.push(item);
        }

        return bundleId;
    }

    /**
     * @notice Purchase a bundle
     * @param bundleId Bundle ID to purchase
     */
    function purchaseBundle(
        bytes32 bundleId
    ) external payable nonReentrant whenNotPaused {
        Bundle storage bundle = bundles[bundleId];

        require(bundle.active, "Bundle not active");
        require(block.timestamp < bundle.expiresAt, "Bundle expired");

        uint256 fee = (bundle.price * platformFee) / FEE_DENOMINATOR;
        uint256 sellerAmount = bundle.price - fee;

        if (bundle.paymentToken == address(0)) {
            require(msg.value >= bundle.price, "Insufficient payment");

            // Pay seller
            (bool sellerSuccess, ) = bundle.seller.call{value: sellerAmount}("");
            require(sellerSuccess, "Seller payment failed");

            // Pay fee
            if (fee > 0) {
                (bool feeSuccess, ) = feeCollector.call{value: fee}("");
                require(feeSuccess, "Fee payment failed");
            }

            // Refund excess
            if (msg.value > bundle.price) {
                (bool refundSuccess, ) = msg.sender.call{value: msg.value - bundle.price}("");
                require(refundSuccess, "Refund failed");
            }
        } else {
            IERC20(bundle.paymentToken).safeTransferFrom(msg.sender, bundle.seller, sellerAmount);
            if (fee > 0) {
                IERC20(bundle.paymentToken).safeTransferFrom(msg.sender, feeCollector, fee);
            }
        }

        // Transfer all NFTs
        for (uint256 i = 0; i < bundle.items.length; i++) {
            BundleItem storage item = bundle.items[i];

            if (item.isERC1155) {
                IERC1155(item.nftContract).safeTransferFrom(
                    bundle.seller,
                    msg.sender,
                    item.tokenId,
                    item.amount,
                    ""
                );
            } else {
                IERC721(item.nftContract).safeTransferFrom(
                    bundle.seller,
                    msg.sender,
                    item.tokenId
                );
            }
        }

        bundle.active = false;

        emit BundlePurchased(msg.sender, bundleId, bundle.items.length, bundle.price);
    }

    /**
     * @notice Cancel a bundle
     * @param bundleId Bundle ID to cancel
     */
    function cancelBundle(bytes32 bundleId) external {
        Bundle storage bundle = bundles[bundleId];
        require(bundle.seller == msg.sender, "Not bundle owner");
        require(bundle.active, "Already inactive");

        bundle.active = false;
    }

    // ============ Batch Transfer Functions ============

    /**
     * @notice Transfer multiple ERC721 NFTs to one recipient
     * @param nftContract NFT contract address
     * @param tokenIds Array of token IDs
     * @param recipient Recipient address
     */
    function batchTransfer(
        address nftContract,
        uint256[] calldata tokenIds,
        address recipient
    ) external nonReentrant {
        require(tokenIds.length > 0 && tokenIds.length <= 100, "Invalid count");
        require(recipient != address(0), "Invalid recipient");

        for (uint256 i = 0; i < tokenIds.length; i++) {
            IERC721(nftContract).safeTransferFrom(msg.sender, recipient, tokenIds[i]);
        }

        address[] memory recipients = new address[](1);
        recipients[0] = recipient;

        emit BatchTransfer(msg.sender, nftContract, tokenIds, recipients);
    }

    /**
     * @notice Transfer multiple NFTs to multiple recipients (1:1)
     * @param nftContract NFT contract address
     * @param tokenIds Array of token IDs
     * @param recipients Array of recipient addresses
     */
    function batchTransferToMany(
        address nftContract,
        uint256[] calldata tokenIds,
        address[] calldata recipients
    ) external nonReentrant {
        require(tokenIds.length == recipients.length, "Length mismatch");
        require(tokenIds.length > 0 && tokenIds.length <= 100, "Invalid count");

        for (uint256 i = 0; i < tokenIds.length; i++) {
            require(recipients[i] != address(0), "Invalid recipient");
            IERC721(nftContract).safeTransferFrom(msg.sender, recipients[i], tokenIds[i]);
        }

        emit BatchTransfer(msg.sender, nftContract, tokenIds, recipients);
    }

    /**
     * @notice Airdrop NFTs to multiple recipients
     * @param nftContract NFT contract address
     * @param tokenIds Array of token IDs
     * @param recipients Array of recipient addresses
     */
    function airdrop(
        address nftContract,
        uint256[] calldata tokenIds,
        address[] calldata recipients
    ) external nonReentrant {
        require(tokenIds.length == recipients.length, "Length mismatch");
        require(tokenIds.length > 0 && tokenIds.length <= 100, "Invalid count");

        for (uint256 i = 0; i < tokenIds.length; i++) {
            require(recipients[i] != address(0), "Invalid recipient");
            IERC721(nftContract).safeTransferFrom(msg.sender, recipients[i], tokenIds[i]);
        }

        emit AirdropExecuted(msg.sender, nftContract, tokenIds, recipients);
    }

    // ============ Internal Functions ============

    function _executeSweepOrder(
        SweepOrder calldata order,
        address buyer
    ) internal {
        uint256 fee = (order.price * platformFee) / FEE_DENOMINATOR;
        uint256 sellerAmount = order.price - fee;

        if (order.paymentToken == address(0)) {
            // Native payment
            (bool sellerSuccess, ) = order.seller.call{value: sellerAmount}("");
            require(sellerSuccess, "Seller payment failed");

            if (fee > 0) {
                (bool feeSuccess, ) = feeCollector.call{value: fee}("");
                require(feeSuccess, "Fee payment failed");
            }
        } else {
            // ERC20 payment
            IERC20(order.paymentToken).safeTransfer(order.seller, sellerAmount);
            if (fee > 0) {
                IERC20(order.paymentToken).safeTransfer(feeCollector, fee);
            }
        }

        // Transfer NFT to buyer
        IERC721(order.nftContract).safeTransferFrom(order.seller, buyer, order.tokenId);
    }

    // ============ Admin Functions ============

    function setFeeCollector(address _feeCollector) external onlyOwner {
        require(_feeCollector != address(0), "Invalid address");
        feeCollector = _feeCollector;
    }

    function setPlatformFee(uint256 _platformFee) external onlyOwner {
        require(_platformFee <= 1000, "Fee too high");
        uint256 oldFee = platformFee;
        platformFee = _platformFee;
        emit FeeUpdated(oldFee, _platformFee);
    }

    function setMaxSweepSize(uint256 _maxSize) external onlyOwner {
        require(_maxSize > 0 && _maxSize <= 100, "Invalid size");
        maxSweepSize = _maxSize;
    }

    function setMarketplace(address marketplace, bool approved) external onlyOwner {
        approvedMarketplaces[marketplace] = approved;
        emit MarketplaceUpdated(marketplace, approved);
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

    function getBundle(bytes32 bundleId) external view returns (
        address seller,
        uint256 price,
        address paymentToken,
        uint256 expiresAt,
        bool active,
        uint256 itemCount
    ) {
        Bundle storage bundle = bundles[bundleId];
        return (
            bundle.seller,
            bundle.price,
            bundle.paymentToken,
            bundle.expiresAt,
            bundle.active,
            bundle.items.length
        );
    }

    function getBundleItems(bytes32 bundleId) external view returns (BundleItem[] memory) {
        return bundles[bundleId].items;
    }

    function calculateTotalWithFee(uint256 amount) external view returns (uint256) {
        return amount + (amount * platformFee) / FEE_DENOMINATOR;
    }

    // ============ UUPS ============

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    // ============ Receive ============

    receive() external payable {}
}
