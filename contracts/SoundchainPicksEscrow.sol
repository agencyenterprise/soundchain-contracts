// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/IZetaChain.sol";

/**
 * @title SoundchainPicksEscrow
 * @notice ZetaChain Universal Contract holding 1v1 Arena Pick wagers across all 24 supported tokens.
 * @dev Deployed on ZetaChain (chainId 7000). Receives stakes via Gateway from any connected chain.
 *
 * Flow:
 *  1. Creator deposits stake on source chain → onCall(CREATE) on ZetaChain → pick locked, status=Open.
 *  2. Taker deposits matching stake on (any) source chain → onCall(TAKE) → status=Matched.
 *  3. Oracle (SoundChain backend wallet) calls settle(pickId, winner) once game finalizes.
 *  4. Loser's stake + winner's stake → winner. 0.05% platform fee → Gnosis Safe.
 *
 * Same-chain (ZetaChain native) paths are also exposed (createPickOnZeta / takePickOnZeta) so
 * users already on ZetaChain can skip the gateway and pay only direct ERC-20 approval.
 */
contract SoundchainPicksEscrow is UniversalContract, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ============ Events ============

    event PickCreated(
        bytes32 indexed pickId,
        address indexed creator,
        address indexed token,
        uint256 stake,
        uint256 sourceChain
    );

    event PickMatched(
        bytes32 indexed pickId,
        address indexed taker,
        uint256 sourceChain
    );

    event PickSettled(
        bytes32 indexed pickId,
        address indexed winner,
        uint256 payout,
        uint256 fee
    );

    event PickCancelled(bytes32 indexed pickId);

    event PickRefunded(bytes32 indexed pickId, address indexed creator, address indexed taker);

    event OracleUpdated(address indexed previous, address indexed next);

    event FeeCollectorUpdated(address indexed previous, address indexed next);

    // ============ Constants ============

    /// @notice Fee rate in basis points (5 = 0.05%) — matches SoundchainOmnichain
    uint256 public constant FEE_RATE = 5;
    uint256 public constant FEE_DENOMINATOR = 10000;

    /// @notice Maximum age before a matched-but-unsettled pick can be force-refunded (14 days)
    uint256 public constant REFUND_WINDOW = 14 days;

    /// @notice Message types for Gateway onCall payloads
    uint8 public constant ACTION_CREATE = 1;
    uint8 public constant ACTION_TAKE = 2;

    // ============ State ============

    enum Status { None, Open, Matched, Settled, Cancelled, Refunded }

    struct Pick {
        address creator;       // EOA on source chain (or ZetaChain if native)
        address taker;
        address token;         // ZRC-20 address representing the wager asset on ZetaChain
        uint256 stakePerSide;  // After-fee net per side (creator stake = taker stake)
        Status status;
        uint64 createdAt;
        uint64 matchedAt;
    }

    IGatewayZEVM public immutable gateway;
    address public gnosisSafe;
    address public oracle;

    /// @notice pickId (keccak256 of off-chain MongoDB id) → escrow record
    mapping(bytes32 => Pick) public picks;

    /// @notice Cumulative fees collected per token (audit / analytics)
    mapping(address => uint256) public feesCollected;

    // ============ Modifiers ============

    modifier onlyGateway() {
        require(msg.sender == address(gateway), "only gateway");
        _;
    }

    modifier onlyOracle() {
        require(msg.sender == oracle, "only oracle");
        _;
    }

    // ============ Constructor ============

    constructor(address _gateway, address _gnosisSafe, address _oracle) {
        require(_gateway != address(0), "gateway=0");
        require(_gnosisSafe != address(0), "safe=0");
        require(_oracle != address(0), "oracle=0");
        gateway = IGatewayZEVM(_gateway);
        gnosisSafe = _gnosisSafe;
        oracle = _oracle;
    }

    // ============ Universal Contract Entry ============

    /**
     * @notice Called by ZetaChain Gateway when a user deposits a wager from any source chain.
     * @param context Source chain + sender info (sender = EOA on source chain).
     * @param zrc20 The ZRC-20 token address representing the deposited asset on ZetaChain.
     * @param amount Gross amount delivered by Gateway (we deduct fee from this).
     * @param message abi.encode(uint8 action, bytes32 pickId).
     */
    function onCall(
        MessageContext calldata context,
        address zrc20,
        uint256 amount,
        bytes calldata message
    ) external override onlyGateway nonReentrant {
        require(amount > 0, "zero amount");
        (uint8 action, bytes32 pickId) = abi.decode(message, (uint8, bytes32));

        // Take 0.05% platform fee at the gateway entry — matches Polygon-side flow
        uint256 fee = (amount * FEE_RATE) / FEE_DENOMINATOR;
        uint256 net = amount - fee;
        if (fee > 0) {
            IERC20(zrc20).safeTransfer(gnosisSafe, fee);
            feesCollected[zrc20] += fee;
        }

        if (action == ACTION_CREATE) {
            _createPick(pickId, context.sender, zrc20, net, context.chainID);
        } else if (action == ACTION_TAKE) {
            _takePick(pickId, context.sender, zrc20, net, context.chainID);
        } else {
            revert("bad action");
        }
    }

    /// @notice Gateway can revert if destination logic fails — refund handled off-chain via the gateway's revertOptions.
    function onRevert(RevertContext calldata) external override onlyGateway {
        // No-op: ZetaChain Gateway already returns funds to revertAddress per RevertOptions.
        // We log nothing on purpose to keep this minimal — the fee was never taken if onCall reverted.
    }

    // ============ Same-chain (ZetaChain native) Entries ============

    /// @notice Same-chain creator path. Caller approves `amount` of `token` to this contract first.
    function createPickOnZeta(bytes32 pickId, address token, uint256 amount) external nonReentrant {
        require(amount > 0, "zero amount");
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);

        uint256 fee = (amount * FEE_RATE) / FEE_DENOMINATOR;
        uint256 net = amount - fee;
        if (fee > 0) {
            IERC20(token).safeTransfer(gnosisSafe, fee);
            feesCollected[token] += fee;
        }
        _createPick(pickId, msg.sender, token, net, 7000);
    }

    /// @notice Same-chain taker path. Stake must equal the pick's per-side stake.
    function takePickOnZeta(bytes32 pickId) external nonReentrant {
        Pick storage p = picks[pickId];
        require(p.status == Status.Open, "not open");

        // Taker pays gross including fee — matches gateway path so both sides bear equal fee.
        uint256 gross = (p.stakePerSide * FEE_DENOMINATOR) / (FEE_DENOMINATOR - FEE_RATE);
        IERC20(p.token).safeTransferFrom(msg.sender, address(this), gross);

        uint256 fee = gross - p.stakePerSide;
        if (fee > 0) {
            IERC20(p.token).safeTransfer(gnosisSafe, fee);
            feesCollected[p.token] += fee;
        }
        _takePick(pickId, msg.sender, p.token, p.stakePerSide, 7000);
    }

    // ============ Internal State Transitions ============

    function _createPick(
        bytes32 pickId,
        address creator,
        address token,
        uint256 net,
        uint256 sourceChain
    ) internal {
        Pick storage p = picks[pickId];
        require(p.status == Status.None, "exists");
        require(creator != address(0), "creator=0");

        p.creator = creator;
        p.token = token;
        p.stakePerSide = net;
        p.status = Status.Open;
        p.createdAt = uint64(block.timestamp);

        emit PickCreated(pickId, creator, token, net, sourceChain);
    }

    function _takePick(
        bytes32 pickId,
        address taker,
        address token,
        uint256 net,
        uint256 sourceChain
    ) internal {
        Pick storage p = picks[pickId];
        require(p.status == Status.Open, "not open");
        require(p.token == token, "token mismatch");
        require(p.creator != taker, "creator cannot take");
        require(net == p.stakePerSide, "stake mismatch");

        p.taker = taker;
        p.status = Status.Matched;
        p.matchedAt = uint64(block.timestamp);

        emit PickMatched(pickId, taker, sourceChain);
    }

    // ============ Settlement ============

    /**
     * @notice Settle a matched pick. Only callable by the off-chain oracle (SoundChain backend signer).
     *         Winner gets the full pot (both stakes already net of fee). Loser gets nothing.
     * @param pickId Pick identifier.
     * @param winner Must be either the creator or taker address.
     */
    function settle(bytes32 pickId, address winner) external onlyOracle nonReentrant {
        Pick storage p = picks[pickId];
        require(p.status == Status.Matched, "not matched");
        require(winner == p.creator || winner == p.taker, "winner not participant");

        uint256 payout = p.stakePerSide * 2;
        p.status = Status.Settled;

        IERC20(p.token).safeTransfer(winner, payout);
        emit PickSettled(pickId, winner, payout, 0);
    }

    /**
     * @notice Tie / push outcome — refund both sides their net stake.
     */
    function settleTie(bytes32 pickId) external onlyOracle nonReentrant {
        Pick storage p = picks[pickId];
        require(p.status == Status.Matched, "not matched");
        p.status = Status.Refunded;
        IERC20(p.token).safeTransfer(p.creator, p.stakePerSide);
        IERC20(p.token).safeTransfer(p.taker, p.stakePerSide);
        emit PickRefunded(pickId, p.creator, p.taker);
    }

    /**
     * @notice Creator cancels an unmatched pick — refund their stake.
     */
    function cancel(bytes32 pickId) external nonReentrant {
        Pick storage p = picks[pickId];
        require(p.status == Status.Open, "not open");
        require(msg.sender == p.creator, "only creator");
        p.status = Status.Cancelled;
        IERC20(p.token).safeTransfer(p.creator, p.stakePerSide);
        emit PickCancelled(pickId);
    }

    /**
     * @notice Anyone can force-refund a matched pick that the oracle never settled within REFUND_WINDOW.
     *         Protects users from stuck stakes if the backend dies / oracle key compromised.
     */
    function forceRefund(bytes32 pickId) external nonReentrant {
        Pick storage p = picks[pickId];
        require(p.status == Status.Matched, "not matched");
        require(block.timestamp > p.matchedAt + REFUND_WINDOW, "window");
        p.status = Status.Refunded;
        IERC20(p.token).safeTransfer(p.creator, p.stakePerSide);
        IERC20(p.token).safeTransfer(p.taker, p.stakePerSide);
        emit PickRefunded(pickId, p.creator, p.taker);
    }

    // ============ Admin ============

    function setOracle(address next) external onlyOwner {
        require(next != address(0), "oracle=0");
        emit OracleUpdated(oracle, next);
        oracle = next;
    }

    function setFeeCollector(address next) external onlyOwner {
        require(next != address(0), "safe=0");
        emit FeeCollectorUpdated(gnosisSafe, next);
        gnosisSafe = next;
    }

    // ============ View ============

    function getPick(bytes32 pickId) external view returns (Pick memory) {
        return picks[pickId];
    }
}
