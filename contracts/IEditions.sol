// SPDX-License-Identifier: MIT

pragma solidity ^0.8.2;

interface IEditions {
    // ============ Structs ============

    struct Edition {
        // The maximum number of tokens that can be sold.
        uint256 quantity;
        // The number of tokens sold so far.
        uint256 numSold;
        // The number of tokens still available.
        uint256 numRemaining;
        // Owner of the edition.
        address owner;
        // Royalty receiver of the edition.
        address royaltyReceiver;
        // Royalty percentage of the edition.
        uint8 royaltyPercentage;
    }

    // ============ Events ============

    event EditionCreated(
        uint256 quantity,
        uint256 indexed editionNumber,
        address owner
    );

    function createEdition(
        // The number of tokens that can be minted and sold.
        uint256 editionQuantity,
        address to,
        uint8 _royaltyPercentage
    ) external returns (uint256 retEditionNumber);

    function getTokenIdsOfEdition(uint256 editionNumber)
        external
        view
        returns (uint256[] memory);
}
