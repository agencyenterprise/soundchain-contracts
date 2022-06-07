// SPDX-License-Identifier: MIT

pragma solidity ^0.8.10;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/interfaces/IERC2981.sol";

/**
 * @notice Secondary sale auction contract for NFTs
 */
contract SoundchainAuction is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;
    using Address for address payable;
    uint256 public rewardsRate;
    uint256 public rewardsLimit;

    event PauseToggled(bool isPaused);

    event AuctionCreated(
        address indexed nftAddress,
        uint256 indexed tokenId,
        address owner,
        uint256 reservePrice,
        bool isPaymentOGUN,
        uint256 startTimestamp,
        uint256 endTimestamp
    );

    event UpdateAuction(
        address indexed nftAddress,
        uint256 indexed tokenId,
        uint256 reservePrice,
        bool isPaymentOGUN,
        uint256 startTime,
        uint256 endTime
    );

    event UpdatePlatformFee(uint256 platformFee);

    event UpdatePlatformFeeRecipient(address payable platformFeeRecipient);

    event UpdateMinBidIncrement(uint256 minBidIncrement);

    event BidPlaced(
        address indexed nftAddress,
        uint256 indexed tokenId,
        address indexed bidder,
        uint256 bid
    );

    event BidRefunded(
        address indexed nftAddress,
        uint256 indexed tokenId,
        address indexed bidder,
        uint256 bid
    );

    event AuctionResulted(
        address oldOwner,
        address indexed nftAddress,
        uint256 indexed tokenId,
        address indexed winner,
        uint256 winningBid
    );

    event AuctionCancelled(address indexed nftAddress, uint256 indexed tokenId);

    /// @notice Parameters of an auction
    struct Auction {
        address owner;
        uint256 reservePrice;
        bool isPaymentOGUN;
        uint256 startTime;
        uint256 endTime;
        bool resulted;
    }

    /// @notice Information about the sender that placed a bit on an auction
    struct HighestBid {
        address payable bidder;
        uint256 bid;
        uint256 lastBidTime;
    }

    /// @notice ERC721 Address -> Token ID -> Auction Parameters
    mapping(address => mapping(uint256 => Auction)) public auctions;

    /// @notice ERC721 Address -> Token ID -> highest bidder info (if a bid has been received)
    mapping(address => mapping(uint256 => HighestBid)) public highestBids;

    /// @notice globally and across all auctions, the amount by which a bid has to increase in percentage
    uint256 public minBidIncrement = 1;

    /// @notice global platform fee, assumed to always be to 1 decimal place i.e. 25 = 2.5%
    uint256 public platformFee;

    /// @notice where to send platform fee funds to
    address payable public platformFeeRecipient;

    /// @notice token option for payment
    IERC20 public immutable OGUNToken;

    /// @notice for switching off auction creations and bids
    bool public isPaused;

    modifier whenNotPaused() {
        require(!isPaused, "contract paused");
        _;
    }

    constructor(address payable _platformFeeRecipient, address _OGUNToken, uint16 _platformFee, uint256 _rewardsRate, uint256 _rewardsLimit) {
        OGUNToken = IERC20(_OGUNToken);
        require(
            _platformFeeRecipient != address(0),
            "SoundchainAuction: Invalid Platform Fee Recipient"
        );

        platformFee = _platformFee;
        platformFeeRecipient = _platformFeeRecipient;
        rewardsRate = _rewardsRate;
        rewardsLimit = _rewardsLimit;
    }

    /**
     @notice Creates a new auction for a given item
     @dev Only the owner of item can create an auction and must have approved the contract
     @dev In addition to owning the item, the sender also has to have the MINTER role.
     @dev End time for the auction must be in the future.
     @param _nftAddress ERC 721 Address
     @param _tokenId Token ID of the item being auctioned
     @param _reservePrice Item cannot be sold for less than this or minBidIncrement, whichever is higher
     @param _isPaymentOGUN true if the payment is in OGUN
     @param _startTimestamp Unix epoch in seconds for the auction start time
     @param _endTimestamp Unix epoch in seconds for the auction end time.
     */
    function createAuction(
        address _nftAddress,
        uint256 _tokenId,
        uint256 _reservePrice,
        bool _isPaymentOGUN,
        uint256 _startTimestamp,
        uint256 _endTimestamp
    ) external whenNotPaused {
        require(
            IERC721(_nftAddress).ownerOf(_tokenId) == _msgSender() &&
                IERC721(_nftAddress).isApprovedForAll(
                    _msgSender(),
                    address(this)
                ),
            "not owner and or contract not approved"
        );

        _createAuction(
            _nftAddress,
            _tokenId,
            _reservePrice,
            _isPaymentOGUN,
            _startTimestamp,
            _endTimestamp
        );
    }

    /**
     @notice Places a new bid, out bidding the existing bidder if found and criteria is reached
     @dev Only callable when the auction is open
     @dev Bids from smart contracts are prohibited to prevent griefing with always reverting receiver
     @param _nftAddress ERC 721 Address
     @param _tokenId Token ID of the item being auctioned
     @param _bidAmount > 0 if payment is in OGUN
     */
     function placeBid(
        address _nftAddress, 
        uint256 _tokenId,
        bool _isPaymentOGUN,
        uint256 _bidAmount
    )
        external
        payable
        nonReentrant
        whenNotPaused
    {
        require(Address.isContract(_msgSender()) == false, "no contracts permitted");

        Auction memory auction = auctions[_nftAddress][_tokenId];

        require(
            _getNow() >= auction.startTime && _getNow() <= auction.endTime,
            "bidding outside of the auction window"
        );

        if (_isPaymentOGUN) {
            _placeBid(_nftAddress, _tokenId, _bidAmount);
        } else {
            _placeBid(_nftAddress, _tokenId, msg.value);
        }
        
    }

    function _placeBid(
        address _nftAddress,
        uint256 _tokenId,
        uint256 _bidAmount
    ) internal whenNotPaused {
        Auction storage auction = auctions[_nftAddress][_tokenId];

        require(
            _bidAmount >= auction.reservePrice,
            "bid cannot be lower than reserve price"
        );

        HighestBid storage highestBid = highestBids[_nftAddress][_tokenId];
        uint256 minBidRequired = highestBid.bid.add((highestBid.bid * minBidIncrement) / 100);

        require(_bidAmount >= minBidRequired, "failed to outbid highest bidder");

        if (auction.isPaymentOGUN) {
            OGUNToken.safeTransferFrom(_msgSender(), address(this), _bidAmount);
        } 

        if (highestBid.bidder != address(0)) {
            _refundHighestBidder(
                _nftAddress,
                _tokenId,
                highestBid.bidder,
                highestBid.bid,
                auction.isPaymentOGUN
            );
        }

        highestBid.bidder = payable(_msgSender());
        highestBid.bid = _bidAmount;
        highestBid.lastBidTime = _getNow();

        emit BidPlaced(_nftAddress, _tokenId, _msgSender(), _bidAmount);
    }

    /**
     @notice Closes a finished auction and rewards the highest bidder
     @dev Auction can only be resulted if there has been a bidder and reserve met.
     @dev If there have been no bids, the auction needs to be cancelled instead using `cancelAuction()`
     @param _nftAddress ERC 721 Address
     @param _tokenId Token ID of the item being auctioned
     */
    function resultAuction(address _nftAddress, uint256 _tokenId)
        external
        nonReentrant
    {
        Auction storage auction = auctions[_nftAddress][_tokenId];
        HighestBid storage highestBid = highestBids[_nftAddress][_tokenId];
        address winner = highestBid.bidder;
        uint256 winningBid = highestBid.bid;

        require(
            (IERC721(_nftAddress).ownerOf(_tokenId) == _msgSender() &&
                _msgSender() == auction.owner) || _msgSender() == winner,
            "sender must be item owner or winner"
        );

        require(auction.endTime > 0, "no auction exists");

        require(_getNow() > auction.endTime, "auction not ended");

        require(!auction.resulted, "auction already resulted");

        require(winner != address(0), "no open bids");
        require(
            winningBid > auction.reservePrice,
            "highest bid is below reservePrice"
        );

        require(
            IERC721(_nftAddress).isApprovedForAll(auction.owner, address(this)),
            "auction not approved"
        );

        auction.resulted = true;

        delete highestBids[_nftAddress][_tokenId];

        uint256 payAmount;

        if (winningBid > auction.reservePrice) {
            uint256 platformFeeAboveReserve = winningBid
                .mul(platformFee)
                .div(1e4);

            // Send platform fee
            if (auction.isPaymentOGUN) {
                OGUNToken.safeTransfer(platformFeeRecipient, platformFeeAboveReserve);
            } else {
                (bool platformTransferSuccess, ) = platformFeeRecipient.call{
                    value: platformFeeAboveReserve
                }("");
                require(platformTransferSuccess, "failed to send platform fee");
            }

            // Send remaining to designer
            payAmount = winningBid.sub(platformFeeAboveReserve);
        } else {
            payAmount = winningBid;
        }

        (address minter, uint256 royaltyFee) = IERC2981(_nftAddress).royaltyInfo(_tokenId, payAmount);
        if (minter != address(0)) {
            if (auction.isPaymentOGUN) {
                OGUNToken.safeTransfer(minter, royaltyFee);
            } else {
                (bool royaltyTransferSuccess, ) = payable(minter).call{
                    value: royaltyFee
                }("");
                require(
                    royaltyTransferSuccess,
                    "failed to send the owner their royalties"
                );
            }
            payAmount = payAmount.sub(royaltyFee);
        }

        if (payAmount > 0) {
            if (auction.isPaymentOGUN) {
                OGUNToken.safeTransfer(auction.owner, payAmount);

                uint256 rewardValue = winningBid.mul(rewardsRate).div(1e4);
                if (rewardValue > rewardsLimit) {
                    rewardValue = rewardsLimit;
                }
                if(IERC20(OGUNToken).balanceOf(address(this)) >= rewardValue.mul(2)) {
                    OGUNToken.safeTransfer(auction.owner, rewardValue);
                    OGUNToken.safeTransfer(winner, rewardValue);
                }
            } else {
                (bool ownerTransferSuccess, ) = auction.owner.call{
                    value: payAmount
                }("");
                require(
                    ownerTransferSuccess,
                    "failed to send the owner the auction balance"
                );
            }
        }

        IERC721(_nftAddress).safeTransferFrom(
            IERC721(_nftAddress).ownerOf(_tokenId),
            winner,
            _tokenId
        );

        emit AuctionResulted(
            auction.owner,
            _nftAddress,
            _tokenId,
            winner,
            winningBid
        );

        delete auctions[_nftAddress][_tokenId];
    }

    /**
     @notice Cancels and inflight and un-resulted auctions, returning the funds to the top bidder if found
     @dev Only item owner
     @param _nftAddress ERC 721 Address
     @param _tokenId Token ID of the NFT being auctioned
     */
    function cancelAuction(address _nftAddress, uint256 _tokenId)
        external
        nonReentrant
    {
        Auction memory auction = auctions[_nftAddress][_tokenId];

        require(
            IERC721(_nftAddress).ownerOf(_tokenId) == _msgSender() &&
                _msgSender() == auction.owner,
            "sender must be owner"
        );
        require(auction.endTime > 0, "no auction exists");
        require(!auction.resulted, "auction already resulted");
        require(highestBids[_nftAddress][_tokenId].bid == 0, "can not cancel if auction has a bid already");

        delete auctions[_nftAddress][_tokenId];
        emit AuctionCancelled(_nftAddress, _tokenId);
    }

    /**
     @notice Toggling the pause flag
     @dev Only admin
     */
    function toggleIsPaused() external onlyOwner {
        isPaused = !isPaused;
        emit PauseToggled(isPaused);
    }

    /**
     @notice Update the amount by which bids have to increase, across all auctions
     @dev Only admin
     @param _minBidIncrement New bid step in WEI
     */
    function updateMinBidIncrement(uint256 _minBidIncrement)
        external
        onlyOwner
    {
        minBidIncrement = _minBidIncrement;
        emit UpdateMinBidIncrement(_minBidIncrement);
    }

    /**
     @notice Update the all params to auction
     @param _nftAddress ERC 721 Address
     @param _tokenId Token ID of the NFT being auctioned
     @param _reservePrice New Ether reserve price (WEI value)
     @param _isPaymentOGUN true if the payment is in OGUN
     @param _startTime New start time (unix epoch in seconds)
     @param _endTime New end time (unix epoch in seconds)
     */
    function updateAuction(
        address _nftAddress, 
        uint256 _tokenId, 
        uint256 _reservePrice, 
        bool _isPaymentOGUN,
        uint256 _startTime, 
        uint256 _endTime
    ) external {
        Auction storage auction = auctions[_nftAddress][_tokenId];

        require(_msgSender() == auction.owner, "sender must be item owner");
        require(!auction.resulted, "auction already resulted");
        require(auction.endTime > 0, "no auction exists");
        require(_startTime > 0, "invalid start time");
        require(auction.startTime + 60 > _getNow(), "auction already started");
        require(
            _startTime + 300 < _endTime,
            "start time should be less than end time (by 5 minutes)"
        );
        require(
            _startTime < _endTime,
            "end time must be greater than start"
        );
        require(
            _endTime > _getNow() + 300,
            "auction should end after 5 minutes"
        );
        require(highestBids[_nftAddress][_tokenId].bid == 0, "can not update if auction has a bid already");

        auction.endTime = _endTime;
        auction.reservePrice = _reservePrice;
        auction.isPaymentOGUN = _isPaymentOGUN;
        auction.startTime = _startTime;

        emit UpdateAuction(_nftAddress, _tokenId, _reservePrice, _isPaymentOGUN, _startTime, _endTime);
    }

    /**
     @notice Method for updating platform fee
     @dev Only admin
     @param _platformFee uint256 the platform fee to set
     */
    function updatePlatformFee(uint256 _platformFee) external onlyOwner {
        platformFee = _platformFee;
        emit UpdatePlatformFee(_platformFee);
    }

    /**
     @notice Method for updating rewards rate
     @dev Only admin
     @param _rewardsRate rate to be aplyed
     */
    function setRewardsRate(uint256 _rewardsRate) 
        public 
        onlyOwner 
    {
        rewardsRate = _rewardsRate;
    }

    /**
     @notice Method for updating rewards limit
     @dev Only admin
     @param newLimit Hardcap for rewards
     */
    function setRewardsLimit(uint256 newLimit) 
        external 
        onlyOwner 
    {
        rewardsLimit = newLimit;
    }

    /**
     @notice Method for withdraw any leftover OGUN
     @dev Only admin
     @param destination Where the OGUN will be sent
     */
    function withdraw(address destination) 
        external 
        onlyOwner 
    {
        uint256 balance = IERC20(OGUNToken).balanceOf(address(this));
        IERC20(OGUNToken).transfer(destination, balance);
    }

    /**
     @notice Method for updating platform fee address
     @dev Only admin
     @param _platformFeeRecipient payable address the address to sends the funds to
     */
    function updatePlatformFeeRecipient(address payable _platformFeeRecipient)
        external
        onlyOwner
    {
        require(_platformFeeRecipient != address(0), "zero address");

        platformFeeRecipient = _platformFeeRecipient;
        emit UpdatePlatformFeeRecipient(_platformFeeRecipient);
    }


    /**
     @notice Method for getting all info about the auction
     @param _nftAddress ERC 721 Address
     @param _tokenId Token ID of the NFT being auctioned
     */
    function getAuction(address _nftAddress, uint256 _tokenId)
        external
        view
        returns (
            address _owner,
            uint256 _reservePrice,
            bool _isPaymentOGUN,
            uint256 _startTime,
            uint256 _endTime,
            bool _resulted
        )
    {
        Auction storage auction = auctions[_nftAddress][_tokenId];
        return (
            auction.owner,
            auction.reservePrice,
            auction.isPaymentOGUN,
            auction.startTime,
            auction.endTime,
            auction.resulted
        );
    }

    /**
     @notice Method for getting all info about the highest bidder
     @param _tokenId Token ID of the NFT being auctioned
     */
    function getHighestBidder(address _nftAddress, uint256 _tokenId)
        external
        view
        returns (
            address payable _bidder,
            uint256 _bid,
            uint256 _lastBidTime
        )
    {
        HighestBid storage highestBid = highestBids[_nftAddress][_tokenId];
        return (highestBid.bidder, highestBid.bid, highestBid.lastBidTime);
    }

    /**
     @notice Private method doing the heavy lifting of creating an auction
     @param _nftAddress ERC 721 Address
     @param _tokenId Token ID of the NFT being auctioned
     @param _reservePrice Item cannot be sold for less than this or minBidIncrement, whichever is higher
     @param _isPaymentOGUN true if the payment is in OGUN
     @param _startTimestamp Unix epoch in seconds for the auction start time
     @param _endTimestamp Unix epoch in seconds for the auction end time.
     */
    function _createAuction(
        address _nftAddress,
        uint256 _tokenId,
        uint256 _reservePrice,
        bool _isPaymentOGUN,
        uint256 _startTimestamp,
        uint256 _endTimestamp
    ) private {
        require(
            auctions[_nftAddress][_tokenId].endTime == 0,
            "auction already started"
        );

        require(
            _endTimestamp >= _startTimestamp + 300,
            "end time must be greater than start (by 5 minutes)"
        );

        require(_startTimestamp > _getNow(), "invalid start time");

        auctions[_nftAddress][_tokenId] = Auction({
            owner: _msgSender(),
            reservePrice: _reservePrice,
            isPaymentOGUN: _isPaymentOGUN,
            startTime: _startTimestamp,
            endTime: _endTimestamp,
            resulted: false
        });

        emit AuctionCreated(_nftAddress, _tokenId, _msgSender(), _reservePrice, _isPaymentOGUN, _startTimestamp, _endTimestamp);
    }

    /**
     @notice Used for sending back escrowed funds from a previous bid
     @param _currentHighestBidder Address of the last highest bidder
     @param _currentHighestBid Ether or Mona amount in WEI that the bidder sent when placing their bid
     @param _isPaymentOGUN true if the payment is in OGUN
     */
    function _refundHighestBidder(
        address _nftAddress,
        uint256 _tokenId,
        address payable _currentHighestBidder,
        uint256 _currentHighestBid,
        bool _isPaymentOGUN
    ) private {
        if (_isPaymentOGUN) {
            OGUNToken.safeTransfer(_currentHighestBidder, _currentHighestBid);
        } else {
            (bool successRefund, ) = _currentHighestBidder.call{
                value: _currentHighestBid
            }("");
            require(successRefund, "failed to refund previous bidder");
        }
        emit BidRefunded(
            _nftAddress,
            _tokenId,
            _currentHighestBidder,
            _currentHighestBid
        );
    }

    function _getNow() internal view virtual returns (uint256) {
        return block.timestamp;
    }
}