// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Burnable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "./ERC1155Metadata.sol";

contract SoundchainCollectible is ERC1155Metadata, ERC1155, Ownable, ERC1155Burnable {
    using Counters for Counters.Counter;

    Counters.Counter private _tokenIdCounter;

    constructor() ERC1155("") {}

    function setURI(string memory newuri) public onlyOwner {
        _setURI(newuri);
    }

    function mint(address account, uint256 amount, string memory _tokenURI)
        public
    {
        uint tokenId = _tokenIdCounter.current();

        _mint(account, tokenId, amount, bytes(_tokenURI));
        _setTokenURI(tokenId, _tokenURI);
        _tokenIdCounter.increment();
    }

    function uri(uint256 _id) public view virtual override(ERC1155, ERC1155Metadata) returns (string memory) {
        return super._tokenURI(_id);
    }
}