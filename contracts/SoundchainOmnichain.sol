// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/IZetaChain.sol";

/**
 * @title SoundchainOmnichain
 * @notice Universal App for SoundChain cross-chain operations on ZetaChain
 * @dev Enables cross-chain NFT purchases, swaps, and fee collection across 23+ chains
 *
 * Architecture:
 * - Deployed on ZetaChain (chainId: 7000)
 * - Receives calls from all connected chains via Gateway
 * - Routes fees to Gnosis Safe (0.05%)
 * - Supports cross-chain NFT purchases in any token
 */
contract SoundchainOmnichain is UniversalContract, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ============ Events ============

    event CrossChainPurchase(
        uint256 indexed sourceChain,
        address indexed buyer,
        address zrc20Token,
        uint256 amount,
        bytes32 nftId
    );

    event CrossChainSwap(
        uint256 indexed sourceChain,
        address indexed user,
        address fromToken,
        address toToken,
        uint256 amountIn,
        uint256 amountOut
    );

    event FeeCollected(
        address indexed token,
        uint256 amount,
        address indexed recipient
    );

    event ChainRegistered(
        uint256 indexed chainId,
        address indexed connector,
        bool enabled
    );

    // ============ Constants ============

    /// @notice Fee rate in basis points (5 = 0.05%)
    uint256 public constant FEE_RATE = 5;
    uint256 public constant FEE_DENOMINATOR = 10000;

    // ============ State Variables ============

    /// @notice ZetaChain Gateway address
    IGatewayZEVM public gateway;

    /// @notice Gnosis Safe address for fee collection
    address public gnosisSafe;

    /// @notice Total fees collected per token
    mapping(address => uint256) public feesCollected;

    /// @notice Registered chain connectors (chainId => connector address on that chain)
    mapping(uint256 => bytes) public chainConnectors;

    /// @notice Enabled chains for cross-chain operations
    mapping(uint256 => bool) public enabledChains;

    /// @notice ZRC-20 token for each chain's native asset
    mapping(uint256 => address) public chainZRC20;

    /// @notice Supported chains list
    uint256[] public supportedChains;

    // ============ Message Types ============

    uint8 public constant MSG_TYPE_PURCHASE = 1;
    uint8 public constant MSG_TYPE_SWAP = 2;
    uint8 public constant MSG_TYPE_BRIDGE_NFT = 3;
    uint8 public constant MSG_TYPE_CLAIM_ROYALTY = 4;

    // ============ Modifiers ============

    modifier onlyGateway() {
        require(msg.sender == address(gateway), "Only gateway");
        _;
    }

    modifier chainEnabled(uint256 chainId) {
        require(enabledChains[chainId], "Chain not enabled");
        _;
    }

    // ============ Constructor ============

    constructor(address _gateway, address _gnosisSafe) {
        require(_gateway != address(0), "Invalid gateway");
        require(_gnosisSafe != address(0), "Invalid gnosis safe");

        gateway = IGatewayZEVM(_gateway);
        gnosisSafe = _gnosisSafe;

        // Register initial supported chains
        _registerChain(1, true);      // Ethereum
        _registerChain(137, true);    // Polygon (primary)
        _registerChain(43114, true);  // Avalanche
        _registerChain(42161, true);  // Arbitrum
        _registerChain(10, true);     // Optimism
        _registerChain(8453, true);   // Base
        _registerChain(81457, true);  // Blast
        _registerChain(7000, true);   // ZetaChain
    }

    // ============ Universal App Interface ============

    /**
     * @notice Handle incoming cross-chain calls
     * @param context Source chain and sender information
     * @param zrc20 ZRC-20 token representing transferred assets
     * @param amount Amount of tokens received
     * @param message Encoded operation data
     */
    function onCall(
        MessageContext calldata context,
        address zrc20,
        uint256 amount,
        bytes calldata message
    ) external override onlyGateway nonReentrant chainEnabled(context.chainID) {
        // Decode message type
        require(message.length >= 1, "Empty message");
        uint8 msgType = uint8(message[0]);
        bytes memory payload = message[1:];

        // Collect fee (0.05%)
        uint256 fee = (amount * FEE_RATE) / FEE_DENOMINATOR;
        uint256 netAmount = amount - fee;

        if (fee > 0) {
            IERC20(zrc20).safeTransfer(gnosisSafe, fee);
            feesCollected[zrc20] += fee;
            emit FeeCollected(zrc20, fee, gnosisSafe);
        }

        // Route based on message type
        if (msgType == MSG_TYPE_PURCHASE) {
            _handlePurchase(context, zrc20, netAmount, payload);
        } else if (msgType == MSG_TYPE_SWAP) {
            _handleSwap(context, zrc20, netAmount, payload);
        } else if (msgType == MSG_TYPE_BRIDGE_NFT) {
            _handleBridgeNFT(context, zrc20, netAmount, payload);
        } else if (msgType == MSG_TYPE_CLAIM_ROYALTY) {
            _handleClaimRoyalty(context, zrc20, netAmount, payload);
        } else {
            revert("Unknown message type");
        }
    }

    /**
     * @notice Handle reverted cross-chain calls
     * @param context Revert information
     */
    function onRevert(RevertContext calldata context) external override onlyGateway {
        // Log revert for debugging
        emit CrossChainPurchase(
            context.chainID,
            context.sender,
            address(0),
            0,
            bytes32(0)
        );
    }

    // ============ Internal Handlers ============

    /**
     * @notice Handle cross-chain NFT purchase
     * @dev User pays in any token on source chain, NFT minted on Polygon
     */
    function _handlePurchase(
        MessageContext calldata context,
        address zrc20,
        uint256 amount,
        bytes memory payload
    ) internal {
        // Decode: (nftId, recipientOnPolygon, nftContractAddress)
        (bytes32 nftId, address recipient, address nftContract) = abi.decode(
            payload,
            (bytes32, address, address)
        );

        // Emit event for off-chain indexer to trigger Polygon mint
        emit CrossChainPurchase(
            context.chainID,
            recipient,
            zrc20,
            amount,
            nftId
        );

        // If source chain is not Polygon, bridge funds to Polygon
        if (context.chainID != 137) {
            _bridgeToPolygon(zrc20, amount, recipient);
        }
    }

    /**
     * @notice Handle cross-chain token swap
     * @dev Swap any token to any other token across chains
     */
    function _handleSwap(
        MessageContext calldata context,
        address zrc20,
        uint256 amount,
        bytes memory payload
    ) internal {
        // Decode: (targetChainId, targetToken, recipient, minAmountOut)
        (uint256 targetChainId, address targetToken, address recipient, uint256 minAmountOut) = abi.decode(
            payload,
            (uint256, address, address, uint256)
        );

        // For now, emit event - actual swap logic would integrate with ZetaSwap
        emit CrossChainSwap(
            context.chainID,
            recipient,
            zrc20,
            targetToken,
            amount,
            minAmountOut // Placeholder - actual output from swap
        );

        // Bridge to target chain
        if (targetChainId != 7000) {
            _bridgeToChain(targetChainId, zrc20, amount, recipient);
        }
    }

    /**
     * @notice Handle cross-chain NFT bridging
     */
    function _handleBridgeNFT(
        MessageContext calldata context,
        address zrc20,
        uint256 amount,
        bytes memory payload
    ) internal {
        // Decode: (nftContract, tokenId, targetChainId, recipient)
        (address nftContract, uint256 tokenId, uint256 targetChainId, address recipient) = abi.decode(
            payload,
            (address, uint256, uint256, address)
        );

        // Emit event for off-chain bridge coordinator
        emit CrossChainPurchase(
            targetChainId,
            recipient,
            nftContract,
            tokenId,
            bytes32(tokenId)
        );
    }

    /**
     * @notice Handle royalty claims across chains
     */
    function _handleClaimRoyalty(
        MessageContext calldata context,
        address zrc20,
        uint256 amount,
        bytes memory payload
    ) internal {
        // Decode: (recipient, preferredToken, preferredChain)
        (address recipient, address preferredToken, uint256 preferredChain) = abi.decode(
            payload,
            (address, address, uint256)
        );

        // Bridge royalties to preferred chain in preferred token
        _bridgeToChain(preferredChain, zrc20, amount, recipient);
    }

    // ============ Bridge Functions ============

    /**
     * @notice Bridge tokens to Polygon (primary chain)
     */
    function _bridgeToPolygon(address zrc20, uint256 amount, address recipient) internal {
        _bridgeToChain(137, zrc20, amount, recipient);
    }

    /**
     * @notice Bridge tokens to any supported chain
     */
    function _bridgeToChain(
        uint256 targetChainId,
        address zrc20,
        uint256 amount,
        address recipient
    ) internal {
        require(enabledChains[targetChainId], "Target chain not enabled");

        // Approve gateway to spend tokens
        IERC20(zrc20).approve(address(gateway), amount);

        // Get gas fee for withdrawal
        (address gasFeeToken, uint256 gasFee) = IZRC20(zrc20).withdrawGasFee();

        // Ensure we have enough for gas
        require(amount > gasFee, "Insufficient for gas");

        // Create revert options
        RevertOptions memory revertOptions = RevertOptions({
            revertAddress: recipient,
            callOnRevert: false,
            abortAddress: address(0),
            revertMessage: "",
            onRevertGasLimit: 0
        });

        // Withdraw to target chain
        gateway.withdraw(
            abi.encodePacked(recipient),
            amount - gasFee,
            zrc20,
            revertOptions
        );
    }

    // ============ Admin Functions ============

    /**
     * @notice Register a new chain connector
     */
    function registerChainConnector(
        uint256 chainId,
        bytes calldata connector,
        address zrc20Token
    ) external onlyOwner {
        chainConnectors[chainId] = connector;
        chainZRC20[chainId] = zrc20Token;
        _registerChain(chainId, true);

        emit ChainRegistered(chainId, address(bytes20(connector)), true);
    }

    /**
     * @notice Enable or disable a chain
     */
    function setChainEnabled(uint256 chainId, bool enabled) external onlyOwner {
        enabledChains[chainId] = enabled;
    }

    /**
     * @notice Update Gnosis Safe address
     */
    function setGnosisSafe(address _gnosisSafe) external onlyOwner {
        require(_gnosisSafe != address(0), "Invalid address");
        gnosisSafe = _gnosisSafe;
    }

    /**
     * @notice Update Gateway address
     */
    function setGateway(address _gateway) external onlyOwner {
        require(_gateway != address(0), "Invalid address");
        gateway = IGatewayZEVM(_gateway);
    }

    /**
     * @notice Emergency withdrawal
     */
    function emergencyWithdraw(address token, uint256 amount) external onlyOwner {
        IERC20(token).safeTransfer(owner(), amount);
    }

    // ============ Internal Helpers ============

    function _registerChain(uint256 chainId, bool enabled) internal {
        if (!enabledChains[chainId] && enabled) {
            supportedChains.push(chainId);
        }
        enabledChains[chainId] = enabled;
    }

    // ============ View Functions ============

    /**
     * @notice Get all supported chains
     */
    function getSupportedChains() external view returns (uint256[] memory) {
        return supportedChains;
    }

    /**
     * @notice Get total fees collected for a token
     */
    function getFeesCollected(address token) external view returns (uint256) {
        return feesCollected[token];
    }

    /**
     * @notice Calculate fee for a given amount
     */
    function calculateFee(uint256 amount) external pure returns (uint256) {
        return (amount * FEE_RATE) / FEE_DENOMINATOR;
    }
}
