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
    Counters.Counter private nextEditionId;

    constructor() ERC721("SoundchainCollectible", "SC") {
        nextEditionId.increment(); //lets start at 1 ;)
    }

    function safeMint(address to, string memory _tokenURI, uint8 _royaltyPercentage) public {
        uint tokenId = _tokenIdCounter.current();

        _safeMint(to, tokenId);
        _setTokenURI(tokenId, _tokenURI);
        _tokenIdCounter.increment();
        setRoyalty(tokenId, to, _royaltyPercentage);
    }

    function safeMintToEdition(
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
        require(editions[editionNumber].owner == msg.sender, "Not owner of edition");

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

    function safeMintToEditionQuantity(
        address to,
        string memory _tokenURI,
        uint8 _royaltyPercentage,
        uint256 editionNumber,
        uint16 quantity
    ) public {
        for (uint256 i = 0; i < quantity; i++) {
            safeMintToEdition(to, _tokenURI, _royaltyPercentage, editionNumber);
        }
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
        uint256 quantity
    ) external  returns (uint256 retEditionNumber) {
        require(quantity > 0, "Quantity must be greater than zero (0)");
        editions[nextEditionId.current()] = Edition({
            quantity: quantity,
            numSold: 0,
            numRemaining: quantity,
            owner: msg.sender
        });

        emit EditionCreated(quantity, nextEditionId.current(), msg.sender);

        nextEditionId.increment();
        return nextEditionId.current() - 1;
    }

    function createEditionWithNFTs(
        // The number of tokens that can be minted and sold.
        uint256 editionQuantity,
        address to,
        string memory _tokenURI,
        uint8 _royaltyPercentage
    ) external  returns (uint256 retEditionNumber) {
        require(editionQuantity > 0, "Quantity must be greater than zero (0)");

        editions[nextEditionId.current()] = Edition({
            quantity: editionQuantity,
            numSold: 0,
            numRemaining: editionQuantity,
            owner: msg.sender
        });

        for (uint256 i = 0; i < editionQuantity; i++) {
            safeMintToEdition(to, _tokenURI, _royaltyPercentage, nextEditionId.current());
        }

        emit EditionCreated(editionQuantity, nextEditionId.current(), msg.sender);

        nextEditionId.increment();
        return nextEditionId.current() - 1;
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
}
