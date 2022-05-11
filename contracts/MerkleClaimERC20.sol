// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.10;

/// ============ Imports ============

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import { MerkleProof } from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol"; // OZ: MerkleProof

/// @title MerkleClaimERC20
/// @notice ERC20 claimable by members of a merkle tree
contract MerkleClaimERC20 is Ownable {

  /// ============ Immutable storage ============

  /// @notice ERC20-claimee inclusion root
  bytes32 public immutable merkleRoot;
  address public immutable ogunToken;

  /// ============ Mutable storage ============

  /// @notice Mapping of addresses who have claimed tokens
  mapping(address => bool) public hasClaimed;
  /// ============ Errors ============

  /// @notice Thrown if address has already claimed
  error AlreadyClaimed();
  /// @notice Thrown if address/amount are not part of Merkle tree
  error NotInMerkle();

  /// ============ Constructor ============

  /// @notice Creates a new MerkleClaimERC20 contract
  /// @param _ogunToken token
  /// @param _merkleRoot of claimees
  constructor(
    address _ogunToken,
    bytes32 _merkleRoot
  ){
    merkleRoot = _merkleRoot; // Update root
    ogunToken = _ogunToken; // Update token Address
  }

  /// ============ Events ============

  /// @notice Emitted after a successful token claim
  /// @param to recipient of claim
  /// @param amount of tokens claimed
  event Claim(address indexed to, uint256 amount);

  /// ============ Functions ============

  /// @notice Allows claiming tokens if address is part of merkle tree
  /// @param to address of claimee
  /// @param amount of tokens owed to claimee
  /// @param proof merkle proof to prove address and amount are in tree
  function claim(address to, uint256 amount, bytes32[] calldata proof) external {
    // Throw if address has already claimed tokens
    if (hasClaimed[to]) revert AlreadyClaimed();

    // Verify merkle proof, or revert if not in tree
    bytes32 leaf = keccak256(abi.encodePacked(to, amount));
    bool isValidLeaf = MerkleProof.verify(proof, merkleRoot, leaf);
    if (!isValidLeaf) revert NotInMerkle();

    // Set address to claimed
    hasClaimed[to] = true;

    // Mint tokens to address
    IERC20(ogunToken).transfer(to, amount);

    // Emit claim event
    emit Claim(to, amount);
  }

  function getLeafValue(address to, uint256 value) public pure returns (bytes32) {
      return keccak256(abi.encodePacked(to, value));
  }

  function withdraw(address destination) external onlyOwner {
      uint256 balance = IERC20(ogunToken).balanceOf(address(this));
      IERC20(ogunToken).transfer(destination, balance);
  }
}