// SPDX-License-Identifier: MIT

pragma solidity ^0.8.2;

interface IEditions {
    // ============ Structs ============

    struct Edition {
        // The id for this edition. --> keccak256(creatorAddress + ID from Backend)
        bytes32 id;
        // The contract´s address where this edition´s tokens were created.
        // address nftContractAddress;
        // The maximum number of tokens that can be sold.
        uint256 quantity;
        // The number of tokens sold so far.
        uint256 numSold;
        // The number of tokens still available.
        uint256 numRemaining;
    }

    // ============ Events ============

    event EditionCreated(
        bytes32 id,
        // address nftContractAddress,
        uint256 quantity,
        uint256 indexed editionNumber
    );

    function createEdition(
        // address nftContractAddress,
        // The number of tokens that can be minted and sold.
        uint256 quantity,
        // The id for this edition. --> keccak256(creatorAddress + ID from Backend)
        bytes32 id
    ) external;

    function getEditionByID(bytes32 id)
        external
        view
        returns (Edition memory retEdition, uint256 editionNumber);

    function getTokenIdsOfEdition(uint256 editionNumber)
        external
        view
        returns (uint256[] memory);

    // function setTokenIdToEdition(uint256 tokenId, uint256 editionNumber)
    //     external;
}
