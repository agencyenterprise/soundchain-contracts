// SPDX-License-Identifier: MIT

pragma solidity ^0.8.2;

import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Enumerable.sol";

 contract Editions {

    // ============ Structs ============

    struct Edition {
        // The id for this edition. --> keccak256(creatorAddress + ID from Backend)
        bytes32 id;
        // The contract´s address where this edition´s tokens were created.
        address nftContractAddress;
        // The maximum number of tokens that can be sold.
        uint256 quantity;
        // The number of tokens sold so far.
        uint256 numMinted;
        // The number of tokens still available.
        uint256 numRemaining;
    }
    // ============ Mutable Storage ============

    // Mapping of edition id to descriptive data.
    mapping(uint256 => Edition) public editions;
    // Mapping of token id to edition id.
    mapping(uint256 => uint256) public tokenToEdition;
    // Editions start at 1, in order that unsold tokens don't map to the first edition.
    uint256 private nextEditionId = 1;

    // ============ Events ============

    event EditionCreated(
        bytes32 id,
        address nftContractAddress,
        uint256 quantity,
        uint256 indexed editionNumber
    );

    constructor() {}
    // ============ Edition Methods ============

    function createEdition(
        address nftContractAddress,
        // The number of tokens that can be minted and sold.
        uint256 quantity,
        // The id for this edition. --> keccak256(creatorAddress + ID from Backend)
        bytes32 id
    ) external {
        require(quantity > 0, "Quantity must be greater than zero (0)");
        editions[nextEditionId] = Edition({
            id: id,
            nftContractAddress: nftContractAddress,
            quantity: quantity,
            numMinted: 0,
            numRemaining: quantity
        });

        emit EditionCreated(id, nftContractAddress, quantity, nextEditionId);

        nextEditionId++;
    }

    function getEditionByID(bytes32 id) public view returns (Edition memory retEdition, uint256 editionNumber) {
        for (uint256 editionCounter = 1; editionCounter < nextEditionId; editionCounter++) {
            if (editions[editionCounter].id == id) {
                return (editions[editionCounter], editionCounter);
            }
        }
    }

    /**
        @dev Get token ids for a given edition number
        @param editionNumber edition number
     */
    function getTokenIdsOfEdition(uint256 editionNumber) public view returns (uint256[] memory) {
        uint256[] memory tokenIdsOfEdition = new uint256[](editions[editionNumber].numMinted);
        uint256 index = 0;

        uint256 totalSupply = IERC721Enumerable(editions[editionNumber].nftContractAddress).totalSupply();
        for (uint256 id = 1; id < totalSupply; id++) {
            if (tokenToEdition[id] == editionNumber) {
                tokenIdsOfEdition[index] = id;
                index++;
            }
        }
        return tokenIdsOfEdition;
    }

    function setTokenIdToEdition(uint256 tokenId, uint256 editionNumber) public {
        tokenToEdition[tokenId] = editionNumber;
    }

    function getBytes32(string memory word) public pure returns (bytes32 retBytes) {
        return keccak256(abi.encodePacked(word));
    }

}