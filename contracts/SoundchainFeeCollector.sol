// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title SoundchainFeeCollector
 * @notice Collects platform fees and routes them to Gnosis Safe
 * @dev Deployed on each chain where SoundChain operates
 *
 * Fee Structure:
 * - Platform fee: 0.05% (5 basis points) - down from legacy 2%
 * - All fees go to Gnosis Safe multisig
 * - Supports any ERC-20 token + native currency
 */
contract SoundchainFeeCollector is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ============ Events ============

    event FeeCollected(
        address indexed token,
        uint256 amount,
        address indexed from,
        string indexed transactionType
    );

    event FeeWithdrawn(
        address indexed token,
        uint256 amount,
        address indexed to
    );

    event GnosisSafeUpdated(
        address indexed oldSafe,
        address indexed newSafe
    );

    event FeeRateUpdated(
        uint256 oldRate,
        uint256 newRate
    );

    event AuthorizedCollectorUpdated(
        address indexed collector,
        bool authorized
    );

    // ============ Constants ============

    /// @notice Maximum fee rate (1% = 100 basis points)
    uint256 public constant MAX_FEE_RATE = 100;

    /// @notice Basis points denominator
    uint256 public constant FEE_DENOMINATOR = 10000;

    // ============ State Variables ============

    /// @notice Current fee rate in basis points (5 = 0.05%)
    uint256 public feeRate;

    /// @notice Gnosis Safe address for fee withdrawal
    address public gnosisSafe;

    /// @notice Authorized contracts that can collect fees
    mapping(address => bool) public authorizedCollectors;

    /// @notice Total fees collected per token (for analytics)
    mapping(address => uint256) public totalFeesCollected;

    /// @notice Pending fees per token (before withdrawal)
    mapping(address => uint256) public pendingFees;

    /// @notice Native currency marker
    address public constant NATIVE = address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);

    // ============ Constructor ============

    /**
     * @notice Initialize the fee collector
     * @param _gnosisSafe Gnosis Safe multisig address
     * @param _feeRate Initial fee rate (default: 5 = 0.05%)
     */
    constructor(address _gnosisSafe, uint256 _feeRate) {
        require(_gnosisSafe != address(0), "Invalid Gnosis Safe");
        require(_feeRate <= MAX_FEE_RATE, "Fee rate too high");

        gnosisSafe = _gnosisSafe;
        feeRate = _feeRate;

        emit GnosisSafeUpdated(address(0), _gnosisSafe);
        emit FeeRateUpdated(0, _feeRate);
    }

    // ============ Modifiers ============

    modifier onlyAuthorized() {
        require(
            authorizedCollectors[msg.sender] || msg.sender == owner(),
            "Not authorized"
        );
        _;
    }

    // ============ Fee Collection ============

    /**
     * @notice Collect fee from an ERC-20 token transfer
     * @param token ERC-20 token address
     * @param amount Total transaction amount
     * @param from Address paying the fee
     * @param transactionType Type of transaction (e.g., "NFT_SALE", "SWAP", "AUCTION")
     * @return fee Amount of fee collected
     * @return netAmount Amount after fee deduction
     */
    function collectFeeERC20(
        address token,
        uint256 amount,
        address from,
        string calldata transactionType
    ) external onlyAuthorized nonReentrant returns (uint256 fee, uint256 netAmount) {
        require(token != address(0), "Invalid token");
        require(amount > 0, "Amount must be > 0");

        fee = calculateFee(amount);
        netAmount = amount - fee;

        if (fee > 0) {
            // Transfer fee from sender to this contract
            IERC20(token).safeTransferFrom(from, address(this), fee);

            pendingFees[token] += fee;
            totalFeesCollected[token] += fee;

            emit FeeCollected(token, fee, from, transactionType);
        }

        return (fee, netAmount);
    }

    /**
     * @notice Collect fee from native currency (MATIC, ETH, etc.)
     * @param transactionType Type of transaction
     * @return fee Amount of fee collected
     * @return netAmount Amount after fee deduction
     */
    function collectFeeNative(
        string calldata transactionType
    ) external payable onlyAuthorized nonReentrant returns (uint256 fee, uint256 netAmount) {
        require(msg.value > 0, "No value sent");

        fee = calculateFee(msg.value);
        netAmount = msg.value - fee;

        if (fee > 0) {
            pendingFees[NATIVE] += fee;
            totalFeesCollected[NATIVE] += fee;

            emit FeeCollected(NATIVE, fee, msg.sender, transactionType);
        }

        // Return excess to sender
        if (netAmount > 0) {
            (bool success, ) = msg.sender.call{value: netAmount}("");
            require(success, "Return transfer failed");
        }

        return (fee, netAmount);
    }

    /**
     * @notice Collect a specific fee amount (for integration with existing contracts)
     * @param token Token address (or NATIVE for native currency)
     * @param feeAmount Exact fee amount to collect
     * @param from Payer address
     * @param transactionType Transaction type for logging
     */
    function collectExactFee(
        address token,
        uint256 feeAmount,
        address from,
        string calldata transactionType
    ) external payable onlyAuthorized nonReentrant {
        if (token == NATIVE) {
            require(msg.value >= feeAmount, "Insufficient native fee");
            pendingFees[NATIVE] += feeAmount;
            totalFeesCollected[NATIVE] += feeAmount;

            // Return excess
            if (msg.value > feeAmount) {
                (bool success, ) = msg.sender.call{value: msg.value - feeAmount}("");
                require(success, "Return transfer failed");
            }
        } else {
            IERC20(token).safeTransferFrom(from, address(this), feeAmount);
            pendingFees[token] += feeAmount;
            totalFeesCollected[token] += feeAmount;
        }

        emit FeeCollected(token, feeAmount, from, transactionType);
    }

    // ============ Fee Withdrawal ============

    /**
     * @notice Withdraw accumulated fees to Gnosis Safe
     * @param token Token to withdraw (use NATIVE for native currency)
     */
    function withdrawFees(address token) external nonReentrant {
        uint256 amount = pendingFees[token];
        require(amount > 0, "No pending fees");

        pendingFees[token] = 0;

        if (token == NATIVE) {
            (bool success, ) = gnosisSafe.call{value: amount}("");
            require(success, "Native withdrawal failed");
        } else {
            IERC20(token).safeTransfer(gnosisSafe, amount);
        }

        emit FeeWithdrawn(token, amount, gnosisSafe);
    }

    /**
     * @notice Withdraw all fees for multiple tokens
     * @param tokens Array of token addresses to withdraw
     */
    function withdrawAllFees(address[] calldata tokens) external nonReentrant {
        for (uint256 i = 0; i < tokens.length; i++) {
            address token = tokens[i];
            uint256 amount = pendingFees[token];

            if (amount > 0) {
                pendingFees[token] = 0;

                if (token == NATIVE) {
                    (bool success, ) = gnosisSafe.call{value: amount}("");
                    require(success, "Native withdrawal failed");
                } else {
                    IERC20(token).safeTransfer(gnosisSafe, amount);
                }

                emit FeeWithdrawn(token, amount, gnosisSafe);
            }
        }
    }

    // ============ Admin Functions ============

    /**
     * @notice Update fee rate
     * @param newFeeRate New fee rate in basis points
     */
    function setFeeRate(uint256 newFeeRate) external onlyOwner {
        require(newFeeRate <= MAX_FEE_RATE, "Fee rate too high");

        uint256 oldRate = feeRate;
        feeRate = newFeeRate;

        emit FeeRateUpdated(oldRate, newFeeRate);
    }

    /**
     * @notice Update Gnosis Safe address
     * @param newGnosisSafe New Gnosis Safe address
     */
    function setGnosisSafe(address newGnosisSafe) external onlyOwner {
        require(newGnosisSafe != address(0), "Invalid address");

        address oldSafe = gnosisSafe;
        gnosisSafe = newGnosisSafe;

        emit GnosisSafeUpdated(oldSafe, newGnosisSafe);
    }

    /**
     * @notice Authorize or revoke a fee collector
     * @param collector Address to update
     * @param authorized Whether to authorize or revoke
     */
    function setAuthorizedCollector(address collector, bool authorized) external onlyOwner {
        authorizedCollectors[collector] = authorized;
        emit AuthorizedCollectorUpdated(collector, authorized);
    }

    /**
     * @notice Emergency withdrawal (owner only)
     * @param token Token to withdraw
     * @param amount Amount to withdraw
     * @param to Recipient address
     */
    function emergencyWithdraw(
        address token,
        uint256 amount,
        address to
    ) external onlyOwner {
        require(to != address(0), "Invalid recipient");

        if (token == NATIVE) {
            (bool success, ) = to.call{value: amount}("");
            require(success, "Transfer failed");
        } else {
            IERC20(token).safeTransfer(to, amount);
        }
    }

    // ============ View Functions ============

    /**
     * @notice Calculate fee for a given amount
     * @param amount Transaction amount
     * @return fee Fee amount
     */
    function calculateFee(uint256 amount) public view returns (uint256) {
        return (amount * feeRate) / FEE_DENOMINATOR;
    }

    /**
     * @notice Get pending fees for a token
     * @param token Token address
     * @return Pending fee amount
     */
    function getPendingFees(address token) external view returns (uint256) {
        return pendingFees[token];
    }

    /**
     * @notice Get total fees collected for a token
     * @param token Token address
     * @return Total fees collected
     */
    function getTotalFeesCollected(address token) external view returns (uint256) {
        return totalFeesCollected[token];
    }

    /**
     * @notice Check if an address is an authorized collector
     * @param collector Address to check
     * @return Whether the address is authorized
     */
    function isAuthorizedCollector(address collector) external view returns (bool) {
        return authorizedCollectors[collector];
    }

    // ============ Receive ============

    /// @notice Receive native currency
    receive() external payable {}
}
