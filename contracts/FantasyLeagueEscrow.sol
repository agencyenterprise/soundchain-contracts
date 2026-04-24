// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title FantasyLeagueEscrow
 * @notice On-chain escrow + prize distribution for SoundChain Arena fantasy leagues.
 *
 * Flow:
 *   1. Anyone calls createLeague(...) — returns a leagueId. Creator is the commissioner.
 *   2. Each team calls join(leagueId) (payable for native POL, or ERC-20 path with allowance).
 *   3. Commissioner calls lock(leagueId) once roster is full → no more joins.
 *   4. When season ends, commissioner calls settle(leagueId, first, second, third).
 *      Contract pays winners per basis-point split, minus platform fee to treasury.
 *   5. Before lock: commissioner can cancel(leagueId) → full refund to all joined teams.
 *
 * Token support: address(0) = native POL. Any ERC-20 (OGUN, USDC, WXRP, etc.) otherwise.
 * Prize split: bps (basis points). First + second + third + platform == 10000.
 * Any dust from integer division goes to first place.
 */
contract FantasyLeagueEscrow is ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;

    // --- Types ---

    enum LeagueStatus { Open, Locked, Settled, Cancelled }

    struct League {
        address commissioner;
        address token;           // address(0) for native
        uint256 entryFee;
        uint8   maxTeams;
        uint8   joinedTeams;
        uint16  firstBps;
        uint16  secondBps;
        uint16  thirdBps;
        uint16  platformBps;
        LeagueStatus status;
        uint256 pot;
    }

    // --- State ---

    address public platformTreasury;
    uint16  public defaultPlatformBps = 5; // 0.05%
    uint256 public nextLeagueId = 1;

    mapping(uint256 => League) public leagues;
    mapping(uint256 => address[]) public leagueMembers;
    mapping(uint256 => mapping(address => bool)) public hasJoined;

    // --- Events ---

    event LeagueCreated(
        uint256 indexed leagueId,
        address indexed commissioner,
        address token,
        uint256 entryFee,
        uint8 maxTeams,
        uint16 firstBps,
        uint16 secondBps,
        uint16 thirdBps
    );
    event TeamJoined(uint256 indexed leagueId, address indexed team, uint256 amount);
    event LeagueLocked(uint256 indexed leagueId, uint256 pot);
    event LeagueSettled(
        uint256 indexed leagueId,
        address indexed first,
        address indexed second,
        address third,
        uint256 firstPayout,
        uint256 secondPayout,
        uint256 thirdPayout,
        uint256 platformFee
    );
    event LeagueCancelled(uint256 indexed leagueId);
    event RefundIssued(uint256 indexed leagueId, address indexed team, uint256 amount);

    // --- Constructor ---

    constructor(address _platformTreasury) Ownable(msg.sender) {
        require(_platformTreasury != address(0), "treasury required");
        platformTreasury = _platformTreasury;
    }

    // --- Admin ---

    function setPlatformTreasury(address t) external onlyOwner {
        require(t != address(0), "zero addr");
        platformTreasury = t;
    }

    function setDefaultPlatformBps(uint16 bps) external onlyOwner {
        require(bps <= 500, "max 5%");
        defaultPlatformBps = bps;
    }

    // --- League lifecycle ---

    function createLeague(
        address token,
        uint256 entryFee,
        uint8 maxTeams,
        uint16 firstBps,
        uint16 secondBps,
        uint16 thirdBps
    ) external returns (uint256 leagueId) {
        require(maxTeams >= 2 && maxTeams <= 32, "teams 2..32");
        require(entryFee > 0, "entryFee > 0");
        require(firstBps + secondBps + thirdBps + defaultPlatformBps == 10000, "bps must sum to 10000");
        require(firstBps >= secondBps && secondBps >= thirdBps, "placement order");

        leagueId = nextLeagueId++;
        League storage L = leagues[leagueId];
        L.commissioner = msg.sender;
        L.token = token;
        L.entryFee = entryFee;
        L.maxTeams = maxTeams;
        L.firstBps = firstBps;
        L.secondBps = secondBps;
        L.thirdBps = thirdBps;
        L.platformBps = defaultPlatformBps;
        L.status = LeagueStatus.Open;

        emit LeagueCreated(leagueId, msg.sender, token, entryFee, maxTeams, firstBps, secondBps, thirdBps);
    }

    function join(uint256 leagueId) external payable nonReentrant {
        League storage L = leagues[leagueId];
        require(L.commissioner != address(0), "league missing");
        require(L.status == LeagueStatus.Open, "not open");
        require(L.joinedTeams < L.maxTeams, "full");
        require(!hasJoined[leagueId][msg.sender], "already joined");

        if (L.token == address(0)) {
            require(msg.value == L.entryFee, "bad native amount");
        } else {
            require(msg.value == 0, "no native");
            IERC20(L.token).safeTransferFrom(msg.sender, address(this), L.entryFee);
        }

        hasJoined[leagueId][msg.sender] = true;
        leagueMembers[leagueId].push(msg.sender);
        L.joinedTeams += 1;
        L.pot += L.entryFee;

        emit TeamJoined(leagueId, msg.sender, L.entryFee);
    }

    function lock(uint256 leagueId) external {
        League storage L = leagues[leagueId];
        require(msg.sender == L.commissioner, "not commissioner");
        require(L.status == LeagueStatus.Open, "not open");
        require(L.joinedTeams >= 2, "need 2+ teams");
        L.status = LeagueStatus.Locked;
        emit LeagueLocked(leagueId, L.pot);
    }

    function settle(
        uint256 leagueId,
        address first,
        address second,
        address third
    ) external nonReentrant {
        League storage L = leagues[leagueId];
        require(msg.sender == L.commissioner, "not commissioner");
        require(L.status == LeagueStatus.Locked, "not locked");
        require(first != address(0), "first required");
        require(hasJoined[leagueId][first], "first not in league");
        if (second != address(0)) require(hasJoined[leagueId][second], "second not in league");
        if (third != address(0)) require(hasJoined[leagueId][third], "third not in league");
        require(first != second && first != third && (second == address(0) || second != third), "duplicate winners");

        uint256 pot = L.pot;
        uint256 platformFee = (pot * L.platformBps) / 10000;
        uint256 secondPayout = second == address(0) ? 0 : (pot * L.secondBps) / 10000;
        uint256 thirdPayout  = third  == address(0) ? 0 : (pot * L.thirdBps)  / 10000;
        // First gets the remainder (captures dust + unpaid 2nd/3rd when missing).
        uint256 firstPayout = pot - platformFee - secondPayout - thirdPayout;

        L.status = LeagueStatus.Settled;
        L.pot = 0;

        _payOut(L.token, platformTreasury, platformFee);
        _payOut(L.token, first, firstPayout);
        if (secondPayout > 0) _payOut(L.token, second, secondPayout);
        if (thirdPayout  > 0) _payOut(L.token, third,  thirdPayout);

        emit LeagueSettled(leagueId, first, second, third, firstPayout, secondPayout, thirdPayout, platformFee);
    }

    function cancel(uint256 leagueId) external nonReentrant {
        League storage L = leagues[leagueId];
        require(msg.sender == L.commissioner, "not commissioner");
        require(L.status == LeagueStatus.Open, "only open leagues cancellable");

        L.status = LeagueStatus.Cancelled;
        address[] memory members = leagueMembers[leagueId];
        uint256 refund = L.entryFee;
        L.pot = 0;

        for (uint256 i = 0; i < members.length; i++) {
            _payOut(L.token, members[i], refund);
            emit RefundIssued(leagueId, members[i], refund);
        }
        emit LeagueCancelled(leagueId);
    }

    // --- Views ---

    function getMembers(uint256 leagueId) external view returns (address[] memory) {
        return leagueMembers[leagueId];
    }

    // --- Internals ---

    function _payOut(address token, address to, uint256 amount) internal {
        if (amount == 0) return;
        if (token == address(0)) {
            (bool ok, ) = to.call{value: amount}("");
            require(ok, "native transfer failed");
        } else {
            IERC20(token).safeTransfer(to, amount);
        }
    }

    // Allow the contract to receive native refunds or residuals.
    receive() external payable {}
}
