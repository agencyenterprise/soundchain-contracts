// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

import "erc721a/contracts/extensions/ERC721ABurnable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/interfaces/IERC2981.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "./IEditions.sol";

contract Soundchain721Editions is ERC721ABurnable, Ownable, IERC2981, IEditions {
    using Counters for Counters.Counter;

    mapping(uint256 => address) public royaltyReceivers;
    mapping(uint256 => uint8) public royaltyPercentage;
    mapping(uint256 => string) private _tokenURIs;
    string private _contractURI;

    // ============ Mutable Storage ============
    // Mapping of edition id to descriptive data.
    mapping(uint256 => Edition) public editions;
    // Mapping of token id to edition id.
    mapping(uint256 => uint256) public tokenToEdition;
    // Mapping of edition id to token id.
    Counters.Counter private nextEditionId;

    constructor(string memory contractURI_)
        ERC721A("SoundchainCollectible", "SC")
    {
        nextEditionId.increment(); // Start at 1
        _contractURI = contractURI_;
    }

    function contractURI() public view returns (string memory) {
        return _contractURI;
    }

    function safeMint(
        address to,
        string memory _tokenURI,
        uint8 _royaltyPercentage
    ) public {
        uint256 tokenId = _nextTokenId();
        _safeMint(to, 1);
        _setTokenURI(tokenId - 1, _tokenURI);
        setRoyalty(tokenId - 1, to, _royaltyPercentage);
    }

    function safeMintToEdition(
        address to,
        string memory _tokenURI,
        uint256 editionNumber
    ) public {
        Edition storage edition = editions[editionNumber];
        require(edition.quantity > 0, "Invalid editionNumber");
        require(edition.numSold < edition.quantity, "Edition is full");
        require(edition.owner == msg.sender, "Not owner of edition");

        uint256 tokenId = _nextTokenId();
        _safeMint(to, 1);
        _setTokenURI(tokenId - 1, _tokenURI);
        edition.numSold++;
        edition.numRemaining = edition.quantity - edition.numSold;
        tokenToEdition[tokenId - 1] = editionNumber;
    }

    function safeMintToEditionQuantity(
        address to,
        string memory _tokenURI,
        uint256 editionNumber,
        uint16 quantity
    ) public {
        require(quantity <= 1000, "Quantity exceeds 1000 limit"); // Enforce 1000/1000
        for (uint256 i = 0; i < quantity; i++) {
            safeMintToEdition(to, _tokenURI, editionNumber);
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

    function tokenURI(uint256 tokenId)
        public
        view
        override(ERC721A, IERC721A)
        returns (string memory)
    {
        require(
            _exists(tokenId),
            "ERC721URIStorage: URI query for nonexistent token"
        );
        string memory _tokenURI = _tokenURIs[tokenId];
        string memory base = _baseURI();
        if (bytes(base).length == 0) return _tokenURI;
        if (bytes(_tokenURI).length > 0) return string(abi.encodePacked(base, _tokenURI));
        return super.tokenURI(tokenId);
    }

    function _setTokenURI(uint256 tokenId, string memory _tokenURI) internal {
        require(_exists(tokenId), "ERC721URIStorage: URI set of nonexistent token");
        _tokenURIs[tokenId] = _tokenURI;
    }

    function burn(uint256 tokenId) public override(ERC721ABurnable) {
        super._burn(tokenId);
        if (bytes(_tokenURIs[tokenId]).length != 0) delete _tokenURIs[tokenId];
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721A, IERC721A, IERC165)
        returns (bool)
    {
        return type(IERC2981).interfaceId == interfaceId || super.supportsInterface(interfaceId);
    }

    function royaltyInfo(uint256 tokenId, uint256 _salePrice)
        external
        view
        override(IERC2981)
        returns (address receiver, uint256 royaltyAmount)
    {
        uint256 editionId = tokenToEdition[tokenId];
        uint8 percentage = editions[editionId].royaltyPercentage;
        address creatorAddress = editions[editionId].royaltyReceiver;
        uint256 _royalties = (_salePrice * percentage) / 100;
        return (creatorAddress, _royalties);
    }

    function createEdition(
        uint256 editionQuantity,
        address to,
        uint8 _royaltyPercentage
    ) external returns (uint256 retEditionNumber) {
        require(editionQuantity > 0 && editionQuantity <= 1000, "Quantity must be 1-1000"); // Enforce 1000/1000
        editions[nextEditionId.current()] = Edition({
            quantity: editionQuantity,
            numSold: 0,
            numRemaining: editionQuantity,
            owner: to,
            royaltyReceiver: to,
            royaltyPercentage: _royaltyPercentage
        });
        emit EditionCreated(editionQuantity, nextEditionId.current(), to);
        nextEditionId.increment();
        return nextEditionId.current() - 1;
    }

    function createEditionWithNFTs(
        uint256 editionQuantity,
        address to,
        string memory _tokenURI,
        uint8 _royaltyPercentage
    ) external returns (uint256 retEditionNumber) {
        require(editionQuantity > 0 && editionQuantity <= 1000, "Quantity must be 1-1000"); // Enforce 1000/1000
        editions[nextEditionId.current()] = Edition({
            quantity: editionQuantity,
            numSold: 0,
            numRemaining: editionQuantity,
            owner: to,
            royaltyReceiver: to,
            royaltyPercentage: _royaltyPercentage
        });
        for (uint256 i = 0; i < editionQuantity; i++) {
            safeMintToEdition(to, _tokenURI, nextEditionId.current());
        }
        emit EditionCreated(editionQuantity, nextEditionId.current(), to);
        nextEditionId.increment();
        return nextEditionId.current() - 1;
    }

    function getTokenIdsOfEdition(uint256 editionNumber)
        public
        view
        returns (uint256[] memory)
    {
        uint256[] memory tokenIdsOfEdition = new uint256[](editions[editionNumber].numSold);
        uint256 index = 0;
        for (uint256 id = 0; id < _nextTokenId(); id++) {
            if (tokenToEdition[id] == editionNumber) {
                tokenIdsOfEdition[index] = id;
                index++;
            }
        }
        return tokenIdsOfEdition;
    }
}
