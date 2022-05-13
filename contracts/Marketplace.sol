// SPDX-License-Identifier: MIT

pragma solidity ^0.8.10;

import "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/interfaces/IERC2981.sol";


contract SoundchainMarketplace is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;
    using Address for address payable;
    uint256 public rewardsRate;

    /// @notice Events for the contract
    event ItemListed(
        address indexed owner,
        address indexed nft,
        uint256 tokenId,
        uint256 quantity,
        uint256 pricePerItem,
        uint256 OGUNPricePerItem,
        bool acceptsMATIC,
        bool acceptsOGUN,
        uint256 startingTime
    );
    event ItemSold(
        address indexed seller,
        address indexed buyer,
        address indexed nft,
        uint256 tokenId,
        uint256 quantity,
        uint256 pricePerItem,
        bool isPaymentOGUN
    );
    event ItemUpdated(
        address indexed owner,
        address indexed nft,
        uint256 tokenId,
        uint256 newPrice,
        uint256 newOGUNPrice,
        bool acceptsMATIC,
        bool acceptsOGUN,
        uint256 startingTime
    );
    event ItemCanceled(
        address indexed owner,
        address indexed nft,
        uint256 tokenId
    );
    event UpdatePlatformFee(uint16 platformFee);
    event UpdatePlatformFeeRecipient(address payable platformFeeRecipient);

    /// @notice Structure for listed items
    struct Listing {
        uint256 quantity;
        uint256 pricePerItem;
        uint256 OGUNPricePerItem;
        bool acceptsMATIC;
        bool acceptsOGUN;
        uint256 startingTime;
    }

    bytes4 private constant INTERFACE_ID_ERC721 = 0x80ac58cd;

    IERC20 public immutable OGUNToken;

    /// @notice NftAddress -> Token ID -> Owner -> Listing item
    mapping(address => mapping(uint256 => mapping(address => Listing)))
        public listings;

    /// @notice Platform fee
    uint16 public platformFee;

    /// @notice Platform fee recipient
    address payable public feeRecipient;


    modifier isListed(
        address _nftAddress,
        uint256 _tokenId,
        address _owner
    ) {
        Listing memory listing = listings[_nftAddress][_tokenId][_owner];
        require(listing.quantity > 0, "not listed item");
        _;
    }

    modifier notListed(
        address _nftAddress,
        uint256 _tokenId,
        address _owner
    ) {
        Listing memory listing = listings[_nftAddress][_tokenId][_owner];
        require(listing.quantity == 0, "already listed");
        _;
    }

    modifier validListing(
        address _nftAddress,
        uint256 _tokenId,
        address _owner
    ) {
        Listing memory listedItem = listings[_nftAddress][_tokenId][_owner];
        if (IERC165(_nftAddress).supportsInterface(INTERFACE_ID_ERC721)) {
            IERC721 nft = IERC721(_nftAddress);
            require(nft.ownerOf(_tokenId) == _owner, "not owning item");
        } else {
            revert("invalid nft address");
        }
        require(_getNow() >= listedItem.startingTime, "item not buyable");
        _;
    }


    /// @notice Contract constructor
    constructor(address payable _feeRecipient, address _OGUNToken, uint16 _platformFee, uint256 _rewardsRate) {
        OGUNToken = IERC20(_OGUNToken);
        platformFee = _platformFee;
        feeRecipient = _feeRecipient;
        rewardsRate = _rewardsRate;
    }



    /// @notice Method for canceling listed NFT
    function cancelListing(address _nftAddress, uint256 _tokenId)
        external
        nonReentrant
        isListed(_nftAddress, _tokenId, _msgSender())
    {
        _cancelListing(_nftAddress, _tokenId, _msgSender());
    }

    /// @notice Method for updating listed NFT
    /// @param _nftAddress Address of NFT contract
    /// @param _tokenId Token ID of NFT
    /// @param _newPrice New sale price for each iteam
    /// @param _newOGUNPrice New sale price in OGUN for each iteam
    /// @param _acceptsMATIC true in case accepts MATIC as payment
    /// @param _acceptsOGUN true in case accepts OGUN as payment
    /// @param _startingTime scheduling for a future sale
    function updateListing(
        address _nftAddress,
        uint256 _tokenId,
        uint256 _newPrice,
        uint256 _newOGUNPrice,
        bool _acceptsMATIC,
        bool _acceptsOGUN,
        uint256 _startingTime
    ) external nonReentrant isListed(_nftAddress, _tokenId, _msgSender()) {
        Listing storage listedItem = listings[_nftAddress][_tokenId][
            _msgSender()
        ];
        if (IERC165(_nftAddress).supportsInterface(INTERFACE_ID_ERC721)) {
            IERC721 nft = IERC721(_nftAddress);
            require(nft.ownerOf(_tokenId) == _msgSender(), "not owning item");
        } else {
            revert("invalid nft address");
        }

        require(
            (_acceptsMATIC || _acceptsOGUN),
            "item should have a way of payment"
        );

        listedItem.pricePerItem = _newPrice;
        listedItem.acceptsMATIC = _acceptsMATIC;
        listedItem.OGUNPricePerItem = _newOGUNPrice;
        listedItem.acceptsOGUN = _acceptsOGUN;
        listedItem.startingTime = _startingTime;
        emit ItemUpdated(
            _msgSender(),
            _nftAddress,
            _tokenId,
            _newPrice,
            _newOGUNPrice,
            _acceptsMATIC,
            _acceptsOGUN,
            _startingTime
        );
    }

    /// @notice Method for buying listed NFT
    /// @param _nftAddress NFT contract address
    /// @param _tokenId TokenId
    /// @param _isPaymentOGUN true if the payment in OGUN
    function buyItem(
        address _nftAddress,
        uint256 _tokenId,
        address payable _owner,
        bool _isPaymentOGUN
    )
        external
        payable
        nonReentrant
        isListed(_nftAddress, _tokenId, _owner)
        validListing(_nftAddress, _tokenId, _owner)
    {
        Listing memory listedItem = listings[_nftAddress][_tokenId][_owner];
        if (_isPaymentOGUN) {
            uint256 allowance = OGUNToken.allowance(_msgSender(), address(this));
            require(
                allowance >= listedItem.OGUNPricePerItem.mul(listedItem.quantity),
                "insufficient balance to buy"
            );
            require(
                listedItem.acceptsOGUN == true,
                "this purchase can't be done in OGUN"
            );
        } else {
            require(
                msg.value >= listedItem.pricePerItem.mul(listedItem.quantity),
                "insufficient balance to buy"
            );
            require(
                listedItem.acceptsMATIC == true,
                "this purchase can't be done in MATIC"
            );
        }

        _buyItem(_nftAddress, _tokenId, _owner, _isPaymentOGUN);
    }


    function _buyItem(
        address _nftAddress,
        uint256 _tokenId,
        address _owner,
        bool isPaymentOGUN
    ) private {
        Listing memory listedItem = listings[_nftAddress][_tokenId][_owner];
        uint256 price;
        if (isPaymentOGUN) {
            price = listedItem.OGUNPricePerItem.mul(listedItem.quantity);
        } else {
            price = listedItem.pricePerItem.mul(listedItem.quantity);
        }
        uint256 feeAmount = price.mul(platformFee).div(1e4);

        // Platform Fee payment
        if (isPaymentOGUN) {
            OGUNToken.safeTransferFrom(_msgSender(), feeRecipient, feeAmount);
        } else {
            (bool feeTransferSuccess, ) = feeRecipient.call{value: feeAmount}(
                ""
            );
            require(feeTransferSuccess, "fee transfer failed");
        }

        // Royalty Fee payment
        (address minter, uint256 royaltyFee) = IERC2981(_nftAddress).royaltyInfo(_tokenId, price - feeAmount);
        if (minter != address(0)) {
            if (isPaymentOGUN) {
                OGUNToken.safeTransferFrom(_msgSender(), minter, royaltyFee);
            } else {
                (bool royaltyTransferSuccess, ) = payable(minter).call{
                    value: royaltyFee
                }("");
                require(royaltyTransferSuccess, "royalty fee transfer failed");
            }  

            feeAmount = feeAmount.add(royaltyFee);
        }
        // Owner payment
        if (isPaymentOGUN) {
            OGUNToken.safeTransferFrom(_msgSender(), _owner, price.sub(feeAmount));
            
            uint256 rewardValue = price.mul(rewardsRate).div(1e4);
            if(IERC20(OGUNToken).balanceOf(address(this)) >= rewardValue.mul(2)) {
                OGUNToken.safeTransfer(_owner, rewardValue);
                OGUNToken.safeTransfer(_msgSender(), rewardValue);
            }
        } else {
            (bool ownerTransferSuccess, ) = _owner.call{
                value: price.sub(feeAmount)
            }("");
            require(ownerTransferSuccess, "owner transfer failed");
        }

        IERC721(_nftAddress).safeTransferFrom(
            _owner,
            _msgSender(),
            _tokenId
        );

        emit ItemSold(
            _owner,
            _msgSender(),
            _nftAddress,
            _tokenId,
            listedItem.quantity,
            price.div(listedItem.quantity),
            isPaymentOGUN
        );
        delete (listings[_nftAddress][_tokenId][_owner]);
    }

    /// @notice Method for listing NFT
    /// @param _nftAddress Address of NFT contract
    /// @param _tokenId Token ID of NFT
    /// @param _quantity token amount to list
    /// @param _pricePerItem sale price for each iteam
    /// @param _OGUNPricePerItem New sale price in OGUN for each iteam
    /// @param _acceptsMATIC true in case accepts MATIC as payment
    /// @param _acceptsOGUN true in case accepts OGUN as payment
    /// @param _startingTime scheduling for a future sale
    function listItem(
        address _nftAddress,
        uint256 _tokenId,
        uint256 _quantity,
        uint256 _pricePerItem,
        uint256 _OGUNPricePerItem,
        bool _acceptsMATIC,
        bool _acceptsOGUN,
        uint256 _startingTime
    ) external notListed(_nftAddress, _tokenId, _msgSender()) {
        if (IERC165(_nftAddress).supportsInterface(INTERFACE_ID_ERC721)) {
            IERC721 nft = IERC721(_nftAddress);
            require(nft.ownerOf(_tokenId) == _msgSender(), "not owning item");
            require(
                nft.isApprovedForAll(_msgSender(), address(this)),
                "item not approved"
            );
        } else {
            revert("invalid nft address");
        }

        require(
            (_acceptsMATIC || _acceptsOGUN),
            "item should have a way of payment"
        );

        listings[_nftAddress][_tokenId][_msgSender()] = Listing(
            _quantity,
            _pricePerItem,
            _OGUNPricePerItem,
            _acceptsMATIC,
            _acceptsOGUN,
            _startingTime
        );
        emit ItemListed(
            _msgSender(),
            _nftAddress,
            _tokenId,
            _quantity,
            _pricePerItem,
            _OGUNPricePerItem,
            _acceptsMATIC,
            _acceptsOGUN,
            _startingTime
        );
    }

    /**
     @notice Method for updating platform fee
     @dev Only admin
     @param _platformFee uint16 the platform fee to set
     */
    function updatePlatformFee(uint16 _platformFee) external onlyOwner {
        platformFee = _platformFee;
        emit UpdatePlatformFee(_platformFee);
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
        feeRecipient = _platformFeeRecipient;
        emit UpdatePlatformFeeRecipient(_platformFeeRecipient);
    }

    ////////////////////////////
    /// Internal and Private ///
    ////////////////////////////
    
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

    function _getNow() internal view virtual returns (uint256) {
        return block.timestamp;
    }

    function _cancelListing(
        address _nftAddress,
        uint256 _tokenId,
        address _owner
    ) private {
        if (IERC165(_nftAddress).supportsInterface(INTERFACE_ID_ERC721)) {
            IERC721 nft = IERC721(_nftAddress);
            require(nft.ownerOf(_tokenId) == _owner, "not owning item");
        } else {
            revert("invalid nft address");
        }

        delete (listings[_nftAddress][_tokenId][_owner]);
        emit ItemCanceled(_owner, _nftAddress, _tokenId);
    }
}