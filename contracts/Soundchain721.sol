// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Burnable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/interfaces/IERC2981.sol";

contract Soundchain721 is ERC721, ERC721Enumerable, ERC721URIStorage, ERC721Burnable, Ownable, IERC2981 {
    using Counters for Counters.Counter;

    Counters.Counter private _tokenIdCounter;
    mapping(uint256 => address) public royaltyReceivers;
    mapping(uint256 => uint8) public royaltyPercentage;

    constructor() ERC721("SoundchainCollectible", "SC") {}

    function safeMint(address to, string memory _tokenURI, uint8 _royaltyPercentage) public {
        uint tokenId = _tokenIdCounter.current();

        _safeMint(to, tokenId);
        _setTokenURI(tokenId, _tokenURI);
        _tokenIdCounter.increment();
        setRoyalty(tokenId, to, _royaltyPercentage);
    }

    function setRoyalty(uint256 tokenId, address creator, uint8 _royaltyPercentage) private {
        royaltyReceivers[tokenId] = creator;
        royaltyPercentage[tokenId] = _royaltyPercentage;
    }

    function _beforeTokenTransfer(address from, address to, uint256 tokenId)
        internal
        override(ERC721, ERC721Enumerable)
    {
        super._beforeTokenTransfer(from, to, tokenId);
    }

    function _burn(uint256 tokenId) internal override(ERC721, ERC721URIStorage) {
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
        return type(IERC2981).interfaceId == interfaceId || super.supportsInterface(interfaceId);
    }

    /// @notice Called with the sale price to determine how much royalty
    //          is owed and to whom.
    ///         param _tokenId - the NFT asset queried for royalty information (not used)
    /// @param _salePrice - sale price of the NFT asset specified by _tokenId
    /// @return receiver - address of who should be sent the royalty payment
    /// @return royaltyAmount - the royalty payment amount for _value sale price
    function royaltyInfo(uint256 tokenId, uint256 _salePrice) external view override(IERC2981) returns (address receiver, uint256 royaltyAmount) {
        uint8 percentage = royaltyPercentage[tokenId];
        uint256 _royalties = (_salePrice * percentage) / 100;
        address creatorAddress = royaltyReceivers[tokenId];
        return (creatorAddress, _royalties);
    }
}