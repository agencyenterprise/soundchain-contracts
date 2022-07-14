// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/interfaces/IERC2981.sol";
import "./IEditions.sol";
import "erc721a/contracts/ERC721A.sol";

contract Soundchain721Editions is
    ERC721A,
    IERC2981,
    IEditions
{
    using Counters for Counters.Counter;

    mapping(uint256 => address) public royaltyReceivers;
    mapping(uint256 => uint8) public royaltyPercentage;
    mapping(uint256 => string) private _tokenURIs;

    // ============ Mutable Storage ============
    // Mapping of edition id to descriptive data.
    mapping(uint256 => Edition) public editions;
    // Mapping of token id to edition id.
    mapping(uint256 => uint256) public tokenToEdition;
    // Mapping of edition id to token id.
    Counters.Counter private nextEditionId;

    constructor() ERC721A("SoundchainCollectible", "SC") {
        nextEditionId.increment(); //lets start at 1 ;)
    }

    function safeMint(address to, string memory _tokenURI, uint8 _royaltyPercentage) public {
        _mint(to, 1);
        _setTokenURI(_nextTokenId() - 1, _tokenURI);
        setRoyalty(_nextTokenId() - 1, to, _royaltyPercentage);
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


        _safeMint(to, 1);
        _setTokenURI(_nextTokenId() - 1, _tokenURI);
        setRoyalty(_nextTokenId() - 1, to, _royaltyPercentage);

        editions[editionNumber].numSold++;
        editions[editionNumber].numRemaining =
            editions[editionNumber].quantity -
            editions[editionNumber].numSold;
        tokenToEdition[_nextTokenId() - 1] = editionNumber;
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

    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        require(_exists(tokenId), "ERC721URIStorage: URI query for nonexistent token");

        string memory _tokenURI = _tokenURIs[tokenId];
        string memory base = _baseURI();

        // If there is no base URI, return the token URI.
        if (bytes(base).length == 0) {
            return _tokenURI;
        }
        // If both are set, concatenate the baseURI and tokenURI (via abi.encodePacked).
        if (bytes(_tokenURI).length > 0) {
            return string(abi.encodePacked(base, _tokenURI));
        }

        return super.tokenURI(tokenId);
    }

    function _setTokenURI(uint256 tokenId, string memory _tokenURI) internal virtual {
        require(_exists(tokenId), "ERC721URIStorage: URI set of nonexistent token");
        _tokenURIs[tokenId] = _tokenURI;
    }

    function _burn(uint256 tokenId) internal virtual override {
        super._burn(tokenId);

        if (bytes(_tokenURIs[tokenId]).length != 0) {
            delete _tokenURIs[tokenId];
        }
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721A, IERC165)
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

        for (uint256 id = 1; id < _nextTokenId() - 1; id++) {
            if (tokenToEdition[id] == editionNumber) {
                tokenIdsOfEdition[index] = id;
                index++;
            }
        }
        return tokenIdsOfEdition;
    }
}
