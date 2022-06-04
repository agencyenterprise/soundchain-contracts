// SPDX-License-Identifier: MIT

pragma solidity ^0.8.10;

import "./Auction.sol";

contract SoundchainAuctionMock is SoundchainAuction {
    uint256 public nowOverride;

    constructor(address payable _platformFeeRecipient, address _OGUNToken, uint16 _platformFee, uint256 _rewardsRate, uint256 _rewardsLimit) SoundchainAuction(_platformFeeRecipient, _OGUNToken, _platformFee, _rewardsRate, _rewardsLimit) {}

    function setNowOverride(uint256 _now) external {
        nowOverride = _now;
    }

    function _getNow() internal override view returns (uint256) {
        return nowOverride;
    }
}