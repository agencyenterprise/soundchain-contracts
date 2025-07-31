// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Burnable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "./ERC1155Metadata.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract Soundchain1155 is ERC1155Metadata, ERC1155, Ownable, ERC1155Burnable {
    using Counters for Counters.Counter;

    Counters.Counter public _tokenIdCounter;
    address private _implementation;
    mapping(uint256 => address) private _chainImplementations;

    constructor(string memory uri) ERC1155(uri) Ownable() {
        _implementation = address(this);
        _chainImplementations[1] = address(this);   // Ethereum
        _chainImplementations[137] = address(this); // Polygon
        _chainImplementations[43114] = address(this); // Avalanche (proxy for Solana)
        _chainImplementations[8453] = address(this); // Base
        _chainImplementations[205] = address(this);  // Tezos
    }

    function setURI(string memory newuri) public onlyOwner {
        _setURI(newuri);
    }

    function mint(address account, uint256 amount, string memory _tokenURI) public {
        uint256 tokenId = _tokenIdCounter.current();
        _mint(account, tokenId, amount, bytes(_tokenURI));
        _setTokenURI(tokenId, _tokenURI);
        _tokenIdCounter.increment();
    }

    function uri(uint256 _id) public view virtual override(ERC1155, ERC1155Metadata) returns (string memory) {
        return super._tokenURI(_id);
    }

    function upgradeTo(address newImplementation) external onlyOwner {
        _implementation = newImplementation;
        uint256 chainId;
        assembly { chainId := chainid() }
        _chainImplementations[chainId] = newImplementation;
    }

    function _implementation() internal view returns (address) {
        uint256 chainId;
        assembly { chainId := chainid() }
        return _chainImplementations[chainId] != address(0) ? _chainImplementations[chainId] : _implementation;
    }

    fallback() external payable {
        address impl = _implementation();
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
