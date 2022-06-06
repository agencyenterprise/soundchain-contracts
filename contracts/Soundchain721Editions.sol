// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Burnable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/interfaces/IERC2981.sol";
import "./IEditions.sol";

contract Soundchain721Editions is
    ERC721,
    ERC721Enumerable,
    ERC721URIStorage,
    ERC721Burnable,
    Ownable,
    IERC2981,
    IEditions
{
    using Counters for Counters.Counter;

    Counters.Counter private _tokenIdCounter;
    mapping(uint256 => address) public royaltyReceivers;
    mapping(uint256 => uint8) public royaltyPercentage;

    // ============ Mutable Storage ============
    // Mapping of edition id to descriptive data.
    mapping(uint256 => Edition) public editions;
    // Mapping of token id to edition id.
    mapping(uint256 => uint256) public tokenToEdition;
    // Mapping of edition id to token id.
    uint256 private nextEditionId = 1;

    constructor() ERC721("SoundchainCollectible", "SC") {}

    function safeMint(
        address to,
        string memory _tokenURI,
        uint8 _royaltyPercentage,
        uint256 editionNumber
    ) public {
        require(editions[editionNumber].quantity > 0, "Invalid editionNumber");
        require(
            editions[editionNumber].numSold < editions[editionNumber].quantity,
            "This edition is already full"
        );

        uint256 tokenId = _tokenIdCounter.current();

        _safeMint(to, tokenId);
        _setTokenURI(tokenId, _tokenURI);
        _tokenIdCounter.increment();
        setRoyalty(tokenId, to, _royaltyPercentage);

        editions[editionNumber].numSold++;
        editions[editionNumber].numRemaining =
            editions[editionNumber].quantity -
            editions[editionNumber].numSold;
        tokenToEdition[tokenId] = editionNumber;
    }

    function setRoyalty(
        uint256 tokenId,
        address creator,
        uint8 _royaltyPercentage
    ) private {
        royaltyReceivers[tokenId] = creator;
        royaltyPercentage[tokenId] = _royaltyPercentage;
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId
    ) internal override(ERC721, ERC721Enumerable) {
        super._beforeTokenTransfer(from, to, tokenId);
    }

    function _burn(uint256 tokenId)
        internal
        override(ERC721, ERC721URIStorage)
    {
        super._burn(tokenId);
    }

    function tokenURI(uint256 tokenId)
        public
        view
        override(ERC721, ERC721URIStorage)
        returns (string memory)
    {
        return super.tokenURI(tokenId);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, ERC721Enumerable, IERC165)
        returns (bool)
    {
        return
            type(IERC2981).interfaceId == interfaceId ||
            super.supportsInterface(interfaceId);
    }

    /// @notice Called with the sale price to determine how much royalty
    //          is owed and to whom.
    ///         param _tokenId - the NFT asset queried for royalty information (not used)
    /// @param _salePrice - sale price of the NFT asset specified by _tokenId
    /// @return receiver - address of who should be sent the royalty payment
    /// @return royaltyAmount - the royalty payment amount for _value sale price
    function royaltyInfo(uint256 tokenId, uint256 _salePrice)
        external
        view
        override(IERC2981)
        returns (address receiver, uint256 royaltyAmount)
    {
        uint8 percentage = royaltyPercentage[tokenId];
        uint256 _royalties = (_salePrice * percentage) / 100;
        address creatorAddress = royaltyReceivers[tokenId];
        return (creatorAddress, _royalties);
    }

    // ============ Edition Methods ============

    function createEdition(
        // The number of tokens that can be minted and sold.
        uint256 quantity,
        // The id for this edition. --> keccak256(creatorAddress + ID from Backend)
        bytes32 id
    ) external {
        require(quantity > 0, "Quantity must be greater than zero (0)");
        editions[nextEditionId] = Edition({
            id: id,
            quantity: quantity,
            numSold: 0,
            numRemaining: quantity
        });

        emit EditionCreated(id, quantity, nextEditionId);

        nextEditionId++;
    }

    function createEditionWithNFTs(
        // The number of tokens that can be minted and sold.
        uint256 editionQuantity,
        // The id for this edition. --> keccak256(creatorAddress + ID from Backend)
        bytes32 editionId,
        address to,
        string memory _tokenURI,
        uint8 _royaltyPercentage
    ) external {
        require(editionQuantity > 0, "Quantity must be greater than zero (0)");

        editions[nextEditionId] = Edition({
            id: editionId,
            quantity: editionQuantity,
            numSold: 0,
            numRemaining: editionQuantity
        });

        for (uint256 i = 0; i < editionQuantity; i++) {
            safeMint(to, _tokenURI, _royaltyPercentage, nextEditionId);
        }

        emit EditionCreated(editionId, editionQuantity, nextEditionId);

        nextEditionId++;
    }

    function getEditionByID(bytes32 id)
        public
        view
        returns (Edition memory retEdition, uint256 editionNumber)
    {
        for (
            uint256 editionCounter = 1;
            editionCounter < nextEditionId;
            editionCounter++
        ) {
            if (editions[editionCounter].id == id) {
                return (editions[editionCounter], editionCounter);
            }
        }
    }

    /**
        @dev Get token ids for a given edition number
        @param editionNumber edition number
     */
    function getTokenIdsOfEdition(uint256 editionNumber)
        public
        view
        returns (uint256[] memory)
    {
        uint256[] memory tokenIdsOfEdition = new uint256[](
            editions[editionNumber].numSold
        );
        uint256 index = 0;

        for (uint256 id = 1; id < _tokenIdCounter.current(); id++) {
            if (tokenToEdition[id] == editionNumber) {
                tokenIdsOfEdition[index] = id;
                index++;
            }
        }
        return tokenIdsOfEdition;
    }

    // From https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/utils/Strings.sol
    function _toString(uint256 value) internal pure returns (string memory) {
        // Inspired by OraclizeAPI's implementation - MIT licence
        // https://github.com/oraclize/ethereum-api/blob/b42146b063c7d6ee1358846c198246239e9360e8/oraclizeAPI_0.4.25.sol

        if (value == 0) {
            return "0";
        }
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }

    function getBytes32(string memory word)
        public
        pure
        returns (bytes32 retBytes)
    {
        return keccak256(abi.encodePacked(word));
    }
}
