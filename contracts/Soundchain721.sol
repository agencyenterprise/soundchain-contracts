// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Burnable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/interfaces/IERC2981.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract Soundchain721 is ERC721, ERC721Enumerable, ERC721URIStorage, ERC721Burnable, Ownable, IERC2981 {
    using Counters for Counters.Counter;

    Counters.Counter private _tokenIdCounter;
    mapping(uint256 => address) public royaltyReceivers;
    mapping(uint256 => uint8) public royaltyPercentage;
    address private _implAddress;
    mapping(uint256 => address) private _chainImplementations;

    constructor() ERC721("SoundchainCollectible", "SC") Ownable() {
        _implAddress = address(this);
        _chainImplementations[1] = address(this);   // Ethereum
        _chainImplementations[137] = address(this); // Polygon
        _chainImplementations[43114] = address(this); // Avalanche (proxy for Solana)
        _chainImplementations[8453] = address(this); // Base
        _chainImplementations[205] = address(this);  // Tezos
    }

    function safeMint(address to, string memory _tokenURI, uint8 _royaltyPercentage) public {
        uint256 tokenId = _tokenIdCounter.current();
        _safeMint(to, tokenId);
        _setTokenURI(tokenId, _tokenURI);
        _tokenIdCounter.increment();
        setRoyalty(tokenId, to, _royaltyPercentage);
    }

    function setRoyalty(uint256 tokenId, address creator, uint8 _royaltyPercentage) private {
        royaltyReceivers[tokenId] = creator;
        royaltyPercentage[tokenId] = _royaltyPercentage;
    }

    function _beforeTokenTransfer(address from, address to, uint256 firstTokenId, uint256 batchSize)
        internal
        override(ERC721, ERC721Enumerable)
    {
        super._beforeTokenTransfer(from, to, firstTokenId, batchSize);
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
        override(ERC721, ERC721Enumerable, ERC721URIStorage, IERC165)
        returns (bool)
    {
        return type(IERC2981).interfaceId == interfaceId || super.supportsInterface(interfaceId);
    }

    function royaltyInfo(uint256 tokenId, uint256 _salePrice) external view override(IERC2981) returns (address receiver, uint256 royaltyAmount) {
        uint8 percentage = royaltyPercentage[tokenId];
        uint256 _royalties = (_salePrice * percentage) / 100;
        address creatorAddress = royaltyReceivers[tokenId];
        return (creatorAddress, _royalties);
    }

    function upgradeTo(address newImplementation) external onlyOwner {
        _implAddress = newImplementation;
        uint256 chainId;
        assembly { chainId := chainid() }
        _chainImplementations[chainId] = newImplementation;
    }

    function _getImplementation() internal view returns (address) {
        uint256 chainId;
        assembly { chainId := chainid() }
        return _chainImplementations[chainId] != address(0) ? _chainImplementations[chainId] : _implAddress;
    }

    receive() external payable {}

    fallback() external payable {
        address impl = _getImplementation();
        assembly {
            calldatacopy(0, 0, calldatasize())
            let result := delegatecall(gas(), impl, 0, calldatasize(), 0, 0)
            returndatacopy(0, 0, returndatasize())
            switch result
            case 0 { revert(0, returndatasize()) }
            default { return(0, returndatasize()) }
        }
    }
}
