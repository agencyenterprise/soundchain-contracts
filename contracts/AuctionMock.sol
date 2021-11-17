// SPDX-License-Identifier: MIT

pragma solidity ^0.8.10;

import "./Auction.sol";

contract SoundchainAuctionMock is SoundchainAuction {
    uint256 public nowOverride;

    constructor(address payable _platformFeeRecipient, uint16 _platformFee) SoundchainAuction(_platformFeeRecipient, _platformFee) {}

    function setNowOverride(uint256 _now) external {
        nowOverride = _now;
    }

    function _getNow() internal override view returns (uint256) {
        return nowOverride;
    }
}