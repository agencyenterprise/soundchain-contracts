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
    }

    // ============ Events ============

    event EditionCreated(
        uint256 quantity,
        uint256 indexed editionNumber
    );

    function createEdition(
        // The number of tokens that can be minted and sold.
        uint256 quantity
    ) external returns (uint256 retEditionNumber);

    function getTokenIdsOfEdition(uint256 editionNumber)
        external
        view
        returns (uint256[] memory);
}
