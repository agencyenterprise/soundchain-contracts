// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";

/**
 * @title SCidRegistry
 * @notice On-chain registry for SoundChain IDs (SCids) - Web3 replacement for ISRC
 * @dev Upgradeable proxy contract for registering and verifying SCids
 *
 * SCid Format: SC-[CHAIN]-[ARTIST_HASH]-[YEAR][SEQUENCE]
 * Example: SC-POL-7B3A-2400001
 *
 * This contract provides:
 * - On-chain proof of SCid registration
 * - Ownership verification
 * - Link to NFT token IDs
 * - Cross-chain compatibility
 * - OGUN reward tracking integration
 */
contract SCidRegistry is
    Initializable,
    UUPSUpgradeable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable
{
    // ============ Events ============

    event SCidRegistered(
        bytes32 indexed scidHash,
        string scid,
        address indexed owner,
        uint256 indexed tokenId,
        address nftContract,
        string metadataHash
    );

    event SCidTransferred(
        bytes32 indexed scidHash,
        address indexed previousOwner,
        address indexed newOwner,
        uint256 timestamp
    );

    event SCidRevoked(
        bytes32 indexed scidHash,
        address indexed revokedBy,
        string reason
    );

    event SCidMetadataUpdated(
        bytes32 indexed scidHash,
        string oldMetadataHash,
        string newMetadataHash
    );

    event RegistrarUpdated(address indexed registrar, bool authorized);

    event BatchRegistered(
        address indexed owner,
        uint256 count,
        uint256 startIndex
    );

    // ============ Structs ============

    struct SCidRecord {
        string scid;              // Full SCid string (SC-POL-7B3A-2400001)
        address owner;            // Current owner's wallet
        uint256 tokenId;          // Associated NFT token ID
        address nftContract;      // NFT contract address
        string metadataHash;      // IPFS hash of track metadata
        uint8 chainCode;          // 0=POL, 1=ZET, 2=ETH, 3=BAS, etc.
        bytes4 artistHash;        // 4-byte artist identifier
        uint16 year;              // 2-digit year (24 = 2024)
        uint32 sequence;          // Sequence number (max 99999)
        uint64 registeredAt;      // Registration timestamp
        bool active;              // Whether SCid is active
    }

    // ============ State Variables ============

    /// @notice Version for upgrades
    uint256 public constant VERSION = 1;

    /// @notice Mapping of SCid hash to record
    mapping(bytes32 => SCidRecord) public scidRecords;

    /// @notice Mapping of owner to their SCid hashes
    mapping(address => bytes32[]) public ownerScids;

    /// @notice Mapping of token ID to SCid hash (for NFT lookup)
    mapping(address => mapping(uint256 => bytes32)) public tokenToScid;

    /// @notice Mapping of artist hash to their sequence counter
    mapping(bytes4 => uint32) public artistSequenceCounter;

    /// @notice Authorized registrars (API backend, minting contracts)
    mapping(address => bool) public registrars;

    /// @notice Total number of registered SCids
    uint256 public totalRegistrations;

    /// @notice Chain code for this deployment
    uint8 public chainCode;

    /// @notice Fee collector address
    address public feeCollector;

    /// @notice Registration fee (optional, can be 0)
    uint256 public registrationFee;

    /// @notice Chain codes enum
    uint8 public constant CHAIN_POL = 0;
    uint8 public constant CHAIN_ZET = 1;
    uint8 public constant CHAIN_ETH = 2;
    uint8 public constant CHAIN_BAS = 3;
    uint8 public constant CHAIN_SOL = 4;
    uint8 public constant CHAIN_BNB = 5;
    uint8 public constant CHAIN_AVA = 6;
    uint8 public constant CHAIN_ARB = 7;

    // ============ Initializer ============

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initialize the contract
     * @param _chainCode Chain code for this deployment (0=POL, 1=ZET, etc.)
     * @param _feeCollector Address to receive registration fees
     */
    function initialize(
        uint8 _chainCode,
        address _feeCollector
    ) external initializer {
        __Ownable_init();
        __ReentrancyGuard_init();
        __Pausable_init();
        __UUPSUpgradeable_init();

        chainCode = _chainCode;
        feeCollector = _feeCollector;
        registrationFee = 0; // Free by default

        // Owner is automatically a registrar
        registrars[msg.sender] = true;
    }

    // ============ Modifiers ============

    modifier onlyRegistrar() {
        require(registrars[msg.sender] || msg.sender == owner(), "Not authorized registrar");
        _;
    }

    // ============ Registration Functions ============

    /**
     * @notice Register a new SCid
     * @param scid Full SCid string (e.g., "SC-POL-7B3A-2400001")
     * @param owner Owner's wallet address
     * @param tokenId Associated NFT token ID
     * @param nftContract NFT contract address
     * @param metadataHash IPFS hash of track metadata
     * @return scidHash The keccak256 hash of the SCid (used as ID)
     */
    function register(
        string calldata scid,
        address owner,
        uint256 tokenId,
        address nftContract,
        string calldata metadataHash
    ) external payable nonReentrant whenNotPaused onlyRegistrar returns (bytes32 scidHash) {
        require(bytes(scid).length > 0, "SCid cannot be empty");
        require(owner != address(0), "Invalid owner address");

        // Calculate SCid hash
        scidHash = keccak256(abi.encodePacked(scid));

        // Check if already registered
        require(!scidRecords[scidHash].active, "SCid already registered");

        // Parse SCid components
        (bytes4 artistHash, uint16 year, uint32 sequence) = _parseScid(scid);

        // Collect fee if set
        if (registrationFee > 0) {
            require(msg.value >= registrationFee, "Insufficient registration fee");
            if (feeCollector != address(0)) {
                (bool success, ) = feeCollector.call{value: registrationFee}("");
                require(success, "Fee transfer failed");
            }
            // Return excess
            if (msg.value > registrationFee) {
                (bool refundSuccess, ) = msg.sender.call{value: msg.value - registrationFee}("");
                require(refundSuccess, "Refund failed");
            }
        }

        // Store record
        scidRecords[scidHash] = SCidRecord({
            scid: scid,
            owner: owner,
            tokenId: tokenId,
            nftContract: nftContract,
            metadataHash: metadataHash,
            chainCode: chainCode,
            artistHash: artistHash,
            year: year,
            sequence: sequence,
            registeredAt: uint64(block.timestamp),
            active: true
        });

        // Update mappings
        ownerScids[owner].push(scidHash);
        if (nftContract != address(0)) {
            tokenToScid[nftContract][tokenId] = scidHash;
        }

        // Update artist sequence if this is higher
        if (sequence > artistSequenceCounter[artistHash]) {
            artistSequenceCounter[artistHash] = sequence;
        }

        totalRegistrations++;

        emit SCidRegistered(scidHash, scid, owner, tokenId, nftContract, metadataHash);

        return scidHash;
    }

    /**
     * @notice Register multiple SCids in batch
     * @param scids Array of SCid strings
     * @param owners Array of owner addresses
     * @param tokenIds Array of token IDs
     * @param nftContracts Array of NFT contract addresses
     * @param metadataHashes Array of metadata IPFS hashes
     */
    function registerBatch(
        string[] calldata scids,
        address[] calldata owners,
        uint256[] calldata tokenIds,
        address[] calldata nftContracts,
        string[] calldata metadataHashes
    ) external payable nonReentrant whenNotPaused onlyRegistrar {
        uint256 count = scids.length;
        require(count > 0 && count <= 100, "Invalid batch size");
        require(
            owners.length == count &&
            tokenIds.length == count &&
            nftContracts.length == count &&
            metadataHashes.length == count,
            "Array length mismatch"
        );

        // Check total fee
        if (registrationFee > 0) {
            require(msg.value >= registrationFee * count, "Insufficient fees");
        }

        uint256 startIndex = totalRegistrations;

        for (uint256 i = 0; i < count; i++) {
            _registerSingle(scids[i], owners[i], tokenIds[i], nftContracts[i], metadataHashes[i]);
        }

        // Handle fees
        if (registrationFee > 0 && feeCollector != address(0)) {
            uint256 totalFee = registrationFee * count;
            (bool success, ) = feeCollector.call{value: totalFee}("");
            require(success, "Fee transfer failed");

            if (msg.value > totalFee) {
                (bool refundSuccess, ) = msg.sender.call{value: msg.value - totalFee}("");
                require(refundSuccess, "Refund failed");
            }
        }

        emit BatchRegistered(msg.sender, count, startIndex);
    }

    /**
     * @dev Internal function to register a single SCid (reduces stack depth)
     */
    function _registerSingle(
        string calldata scid,
        address owner,
        uint256 tokenId,
        address nftContract,
        string calldata metadataHash
    ) internal {
        bytes32 scidHash = keccak256(abi.encodePacked(scid));
        require(!scidRecords[scidHash].active, "SCid already registered");

        (bytes4 artistHash, uint16 year, uint32 sequence) = _parseScid(scid);

        scidRecords[scidHash] = SCidRecord({
            scid: scid,
            owner: owner,
            tokenId: tokenId,
            nftContract: nftContract,
            metadataHash: metadataHash,
            chainCode: chainCode,
            artistHash: artistHash,
            year: year,
            sequence: sequence,
            registeredAt: uint64(block.timestamp),
            active: true
        });

        ownerScids[owner].push(scidHash);
        if (nftContract != address(0)) {
            tokenToScid[nftContract][tokenId] = scidHash;
        }

        if (sequence > artistSequenceCounter[artistHash]) {
            artistSequenceCounter[artistHash] = sequence;
        }

        totalRegistrations++;

        emit SCidRegistered(scidHash, scid, owner, tokenId, nftContract, metadataHash);
    }

    /**
     * @notice Transfer SCid ownership
     * @param scidHash Hash of the SCid to transfer
     * @param newOwner New owner's address
     */
    function transfer(
        bytes32 scidHash,
        address newOwner
    ) external nonReentrant whenNotPaused {
        SCidRecord storage record = scidRecords[scidHash];

        require(record.active, "SCid not registered");
        require(record.owner == msg.sender, "Not SCid owner");
        require(newOwner != address(0), "Invalid new owner");
        require(newOwner != msg.sender, "Cannot transfer to self");

        address previousOwner = record.owner;
        record.owner = newOwner;

        // Update owner mappings
        ownerScids[newOwner].push(scidHash);
        // Note: We don't remove from previous owner's array to save gas
        // The record.owner field is the source of truth

        emit SCidTransferred(scidHash, previousOwner, newOwner, block.timestamp);
    }

    /**
     * @notice Update metadata hash for an SCid
     * @param scidHash Hash of the SCid to update
     * @param newMetadataHash New IPFS metadata hash
     */
    function updateMetadata(
        bytes32 scidHash,
        string calldata newMetadataHash
    ) external whenNotPaused {
        SCidRecord storage record = scidRecords[scidHash];

        require(record.active, "SCid not registered");
        require(record.owner == msg.sender || registrars[msg.sender], "Not authorized");

        string memory oldHash = record.metadataHash;
        record.metadataHash = newMetadataHash;

        emit SCidMetadataUpdated(scidHash, oldHash, newMetadataHash);
    }

    /**
     * @notice Revoke an SCid (admin only, for disputes)
     * @param scidHash Hash of the SCid to revoke
     * @param reason Reason for revocation
     */
    function revoke(
        bytes32 scidHash,
        string calldata reason
    ) external onlyOwner {
        SCidRecord storage record = scidRecords[scidHash];
        require(record.active, "SCid not registered or already revoked");

        record.active = false;

        emit SCidRevoked(scidHash, msg.sender, reason);
    }

    // ============ View Functions ============

    /**
     * @notice Get SCid record by hash
     */
    function getScid(bytes32 scidHash) external view returns (SCidRecord memory) {
        return scidRecords[scidHash];
    }

    /**
     * @notice Get SCid record by string
     */
    function getScidByString(string calldata scid) external view returns (SCidRecord memory) {
        bytes32 scidHash = keccak256(abi.encodePacked(scid));
        return scidRecords[scidHash];
    }

    /**
     * @notice Check if SCid is registered and active
     */
    function isRegistered(bytes32 scidHash) external view returns (bool) {
        return scidRecords[scidHash].active;
    }

    /**
     * @notice Check if SCid string is registered
     */
    function isRegisteredByString(string calldata scid) external view returns (bool) {
        bytes32 scidHash = keccak256(abi.encodePacked(scid));
        return scidRecords[scidHash].active;
    }

    /**
     * @notice Get owner of an SCid
     */
    function ownerOf(bytes32 scidHash) external view returns (address) {
        require(scidRecords[scidHash].active, "SCid not registered");
        return scidRecords[scidHash].owner;
    }

    /**
     * @notice Get all SCid hashes owned by an address
     */
    function getScidsByOwner(address owner) external view returns (bytes32[] memory) {
        return ownerScids[owner];
    }

    /**
     * @notice Get SCid hash by NFT token
     */
    function getScidByToken(address nftContract, uint256 tokenId) external view returns (bytes32) {
        return tokenToScid[nftContract][tokenId];
    }

    /**
     * @notice Get next sequence number for an artist
     */
    function getNextSequence(bytes4 artistHash) external view returns (uint32) {
        return artistSequenceCounter[artistHash] + 1;
    }

    /**
     * @notice Verify SCid ownership
     */
    function verifyOwnership(
        bytes32 scidHash,
        address claimedOwner
    ) external view returns (bool) {
        SCidRecord storage record = scidRecords[scidHash];
        return record.active && record.owner == claimedOwner;
    }

    /**
     * @notice Get SCid hash from string
     */
    function getScidHash(string calldata scid) external pure returns (bytes32) {
        return keccak256(abi.encodePacked(scid));
    }

    // ============ Admin Functions ============

    /**
     * @notice Add or remove a registrar
     */
    function setRegistrar(address registrar, bool authorized) external onlyOwner {
        registrars[registrar] = authorized;
        emit RegistrarUpdated(registrar, authorized);
    }

    /**
     * @notice Update registration fee
     */
    function setRegistrationFee(uint256 newFee) external onlyOwner {
        registrationFee = newFee;
    }

    /**
     * @notice Update fee collector
     */
    function setFeeCollector(address newCollector) external onlyOwner {
        feeCollector = newCollector;
    }

    /**
     * @notice Pause contract
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @notice Unpause contract
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @notice Emergency ETH recovery
     */
    function emergencyRecoverETH(address to, uint256 amount) external onlyOwner {
        (bool success, ) = to.call{value: amount}("");
        require(success, "Transfer failed");
    }

    // ============ Internal Functions ============

    /**
     * @notice Parse SCid string into components
     * @dev Expected format: SC-POL-7B3A-2400001
     */
    function _parseScid(string calldata scid) internal pure returns (
        bytes4 artistHash,
        uint16 year,
        uint32 sequence
    ) {
        bytes memory scidBytes = bytes(scid);
        require(scidBytes.length >= 18, "Invalid SCid length");

        // Extract artist hash (positions 7-10, "7B3A")
        artistHash = bytes4(
            (uint32(uint8(scidBytes[7])) << 24) |
            (uint32(uint8(scidBytes[8])) << 16) |
            (uint32(uint8(scidBytes[9])) << 8) |
            uint32(uint8(scidBytes[10]))
        );

        // Extract year (positions 12-13, "24")
        year = uint16(
            (uint8(scidBytes[12]) - 48) * 10 +
            (uint8(scidBytes[13]) - 48)
        );

        // Extract sequence (positions 14-18, "00001")
        sequence = uint32(
            (uint8(scidBytes[14]) - 48) * 10000 +
            (uint8(scidBytes[15]) - 48) * 1000 +
            (uint8(scidBytes[16]) - 48) * 100 +
            (uint8(scidBytes[17]) - 48) * 10 +
            (uint8(scidBytes[18]) - 48)
        );

        return (artistHash, year, sequence);
    }

    /**
     * @notice Required for UUPS upgrades
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    // ============ Receive ============

    receive() external payable {}
}
