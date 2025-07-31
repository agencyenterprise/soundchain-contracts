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
import "./IEditions.sol";

contract SoundchainMarketplaceEditions is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;
    using Address for address payable;
    uint256 public rewardsRate;
    uint256 public rewardsLimit;

    /// @notice Events for the contract
    event ItemListed(
        address indexed owner,
        address indexed nft,
        uint256 tokenId,
        uint256 quantity,
        uint256 pricePerItem,
        uint256 OGUNPricePerItem,
        uint256 BTCPricePerItem, // Added for Bitcoin
        bool acceptsMATIC,
        bool acceptsOGUN,
        bool acceptsBTC, // Added for Bitcoin
        uint256 startingTime,
        uint256 chainId
    );
    event ItemSold(
        address indexed seller,
        address indexed buyer,
        address indexed nft,
        uint256 tokenId,
        uint256 quantity,
        uint256 pricePerItem,
        bool isPaymentOGUN,
        bool isPaymentBTC, // Added for Bitcoin
        uint256 chainId
    );
    event ItemUpdated(
        address indexed owner,
        address indexed nft,
        uint256 tokenId,
        uint256 newPrice,
        uint256 newOGUNPrice,
        uint256 newBTCPrice, // Added for Bitcoin
        bool acceptsMATIC,
        bool acceptsOGUN,
        bool acceptsBTC, // Added for Bitcoin
        uint256 startingTime,
        uint256 chainId
    );
    event ItemCanceled(
        address indexed owner,
        address indexed nft,
        uint256 tokenId,
        uint256 chainId
    );
    event EditionListed(address indexed nft, uint256 editionId, uint256 chainId);
    event EditionCanceled(address indexed nft, uint256 editionId, uint256 chainId);
    event UpdatePlatformFee(uint16 platformFee);
    event UpdatePlatformFeeRecipient(address payable platformFeeRecipient);

    /// @notice Structure for listed items
    struct Listing {
        uint256 quantity;
        uint256 pricePerItem;
        uint256 OGUNPricePerItem;
        uint256 BTCPricePerItem; // Added for Bitcoin
        bool acceptsMATIC;
        bool acceptsOGUN;
        bool acceptsBTC; // Added for Bitcoin
        uint256 startingTime;
        uint256 chainId; // Added for multi-chain tracking
    }

    bytes4 private constant INTERFACE_ID_ERC721 = 0x80ac58cd;

    IERC20 public immutable OGUNToken;
    mapping(uint256 => bool) public supportedChains; // Track supported chains

    /// @notice NftAddress -> Token ID -> Owner -> Listing item
    mapping(address => mapping(uint256 => mapping(address => Listing)))
        public listings;

    /// @notice NftAddress -> Edition Number -> True/False (Edition listed or not)
    mapping(address => mapping(uint256 => bool)) public editionListings;

    /// @notice Platform fee
    uint16 public platformFee;

    /// @notice Platform fee recipient
    address payable public feeRecipient;

    modifier isListed(
        address _nftAddress,
        uint256 _tokenId,
        address _owner
    ) {
        require(_isListed(_nftAddress, _tokenId, _owner), "not listed item");
        _;
    }

    modifier notListed(
        address _nftAddress,
        uint256 _tokenId,
        address _owner
    ) {
        require(_notListed(_nftAddress, _tokenId, _owner), "already listed");
        _;
    }

    modifier editionNotListed(address nftAddress, uint256 _editionNumber) {
        require(
            !editionListings[nftAddress][_editionNumber],
            "edition already listed"
        );
        _;
    }

    modifier isEditionListed(address _nftAddress, uint256 _editionNumber) {
        require(
            editionListings[_nftAddress][_editionNumber],
            "edition not listed item"
        );
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
        require(supportedChains[listedItem.chainId], "Unsupported chain");
        _;
    }

    /// @notice Contract constructor
    constructor(
        address payable _feeRecipient,
        address _OGUNToken,
        uint16 _platformFee,
        uint256 _rewardsRate,
        uint256 _rewardsLimit
    ) {
        OGUNToken = IERC20(_OGUNToken);
        platformFee = _platformFee;
        feeRecipient = _feeRecipient;
        rewardsRate = _rewardsRate;
        rewardsLimit = _rewardsLimit;
        // Initialize supported chains
        supportedChains[1] = true;   // Ethereum
        supportedChains[137] = true; // Polygon
        supportedChains[43114] = true; // Avalanche (proxy for Solana)
        supportedChains[8453] = true; // Base
        supportedChains[205] = true;  // Tezos
    }

    /// @notice Method for canceling listed NFT
    function cancelListing(address _nftAddress, uint256 _tokenId)
        external
        nonReentrant
        isListed(_nftAddress, _tokenId, _msgSender())
    {
        _cancelListing(_nftAddress, _tokenId, _msgSender());
    }

    /// @notice Method for canceling Edition listed NFT
    function cancelEditionListing(address _nftAddress, uint256 _editionNumber)
        external
        nonReentrant
        isEditionListed(_nftAddress, _editionNumber)
    {
        IERC721 nft = IERC721(_nftAddress);
        IEditions nftEdition = IEditions(_nftAddress);

        uint256[] memory tokensFromEdition = nftEdition.getTokenIdsOfEdition(
            _editionNumber
        );

        require(tokensFromEdition.length > 0, "edition has no tokens");

        for (uint256 index = 0; index < tokensFromEdition.length; index++) {
            if (nft.ownerOf(tokensFromEdition[index]) == _msgSender()) {
                _cancelListing(
                    _nftAddress,
                    tokensFromEdition[index],
                    _msgSender()
                );
            }
        }
        editionListings[_nftAddress][_editionNumber] = false;

        emit EditionCanceled(_nftAddress, _editionNumber, block.chainid);
    }

    /// @notice Method for batch canceling listed NFT
    function cancelListingBatch(address _nftAddress, uint256[] memory tokenIds)
        external
        nonReentrant
    {
        IERC721 nft = IERC721(_nftAddress);

        require(tokenIds.length > 0, "tokenIds is empty");

        for (uint256 index = 0; index < tokenIds.length; index++) {
            if (nft.ownerOf(tokenIds[index]) == _msgSender()) {
                require(
                    _isListed(_nftAddress, tokenIds[index], _msgSender()),
                    "item not listed"
                );
                _cancelListing(_nftAddress, tokenIds[index], _msgSender());
            }
        }
    }

    /// @notice Method for updating listed NFT
    /// @param _nftAddress Address of NFT contract
    /// @param _tokenId Token ID of NFT
    /// @param _newPrice New sale price for each iteam
    /// @param _newOGUNPrice New sale price in OGUN for each iteam
    /// @param _newBTCPrice New sale price in BTC for each item
    /// @param _acceptsMATIC true in case accepts MATIC as payment
    /// @param _acceptsOGUN true in case accepts OGUN as payment
    /// @param _acceptsBTC true in case accepts BTC as payment
    /// @param _startingTime scheduling for a future sale
    /// @param _chainId Chain ID for the listing
    function updateListing(
        address _nftAddress,
        uint256 _tokenId,
        uint256 _newPrice,
        uint256 _newOGUNPrice,
        uint256 _newBTCPrice,
        bool _acceptsMATIC,
        bool _acceptsOGUN,
        bool _acceptsBTC,
        uint256 _startingTime,
        uint256 _chainId
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
            (_acceptsMATIC || _acceptsOGUN || _acceptsBTC),
            "item should have a way of payment"
        );
        require(supportedChains[_chainId], "Unsupported chain");

        listedItem.pricePerItem = _newPrice;
        listedItem.acceptsMATIC = _acceptsMATIC;
        listedItem.OGUNPricePerItem = _newOGUNPrice;
        listedItem.acceptsOGUN = _acceptsOGUN;
        listedItem.BTCPricePerItem = _newBTCPrice; // Added for Bitcoin
        listedItem.acceptsBTC = _acceptsBTC; // Added for Bitcoin
        listedItem.startingTime = _startingTime;
        listedItem.chainId = _chainId;
        emit ItemUpdated(
            _msgSender(),
            _nftAddress,
            _tokenId,
            _newPrice,
            _newOGUNPrice,
            _newBTCPrice,
            _acceptsMATIC,
            _acceptsOGUN,
            _acceptsBTC,
            _startingTime,
            _chainId
        );
    }

    /// @notice Method for buying listed NFT
    /// @param _nftAddress NFT contract address
    /// @param _tokenId TokenId
    /// @param _isPaymentOGUN true if the payment in OGUN
    /// @param _isPaymentBTC true if the payment in BTC
    function buyItem(
        address _nftAddress,
        uint256 _tokenId,
        address payable _owner,
        bool _isPaymentOGUN,
        bool _isPaymentBTC
    )
        external
        payable
        nonReentrant
        isListed(_nftAddress, _tokenId, _owner)
        validListing(_nftAddress, _tokenId, _owner)
    {
        Listing memory listedItem = listings[_nftAddress][_tokenId][_owner];
        require(!(_isPaymentOGUN && _isPaymentBTC), "Choose one payment type");
        if (_isPaymentOGUN) {
            uint256 allowance = OGUNToken.allowance(
                _msgSender(),
                address(this)
            );
            require(
                allowance >= listedItem.OGUNPricePerItem.mul(listedItem.quantity),
                "insufficient OGUN balance to buy"
            );
            require(
                listedItem.acceptsOGUN == true,
                "this purchase can't be done in OGUN"
            );
        } else if (_isPaymentBTC) {
            // Placeholder: BTC payment requires off-chain settlement (e.g., via oracle or bridge)
            require(listedItem.acceptsBTC == true, "BTC not accepted");
            // Implement BTC payment logic (e.g., via wrapped BTC or oracle)
            revert("BTC payment not yet implemented; requires bridge integration");
        } else {
            require(
                msg.value >= listedItem.pricePerItem.mul(listedItem.quantity),
                "insufficient MATIC balance to buy"
            );
            require(
                listedItem.acceptsMATIC == true,
                "this purchase can't be done in MATIC"
            );
        }

        _buyItem(_nftAddress, _tokenId, _owner, _isPaymentOGUN, _isPaymentBTC);
    }

    function _buyItem(
        address _nftAddress,
        uint256 _tokenId,
        address _owner,
        bool isPaymentOGUN,
        bool isPaymentBTC
    ) private {
        Listing memory listedItem = listings[_nftAddress][_tokenId][_owner];
        uint256 price;
        if (isPaymentOGUN) {
            price = listedItem.OGUNPricePerItem.mul(listedItem.quantity);
        } else if (isPaymentBTC) {
            price = listedItem.BTCPricePerItem.mul(listedItem.quantity); // Placeholder
            revert("BTC payment not yet implemented; requires bridge integration");
        } else {
            price = listedItem.pricePerItem.mul(listedItem.quantity);
        }
        uint256 feeAmount = price.mul(platformFee).div(1e4);

        // Platform Fee payment
        if (isPaymentOGUN) {
            OGUNToken.safeTransferFrom(_msgSender(), feeRecipient, feeAmount);
        } else if (isPaymentBTC) {
            // Placeholder for BTC fee payment
            revert("BTC payment not yet implemented; requires bridge integration");
        } else {
            (bool feeTransferSuccess, ) = feeRecipient.call{value: feeAmount}(
                ""
            );
            require(feeTransferSuccess, "fee transfer failed");
        }

        // Royalty Fee payment
        (address minter, uint256 royaltyFee) = IERC2981(_nftAddress)
            .royaltyInfo(_tokenId, price - feeAmount);
        if (minter != address(0)) {
            if (isPaymentOGUN) {
                OGUNToken.safeTransferFrom(_msgSender(), minter, royaltyFee);
            } else if (isPaymentBTC) {
                // Placeholder for BTC royalty
                revert("BTC payment not yet implemented; requires bridge integration");
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
            OGUNToken.safeTransferFrom(
                _msgSender(),
                _owner,
                price.sub(feeAmount)
            );

            uint256 rewardValue = price.mul(rewardsRate).div(1e4);
            if (rewardValue > rewardsLimit) {
                rewardValue = rewardsLimit;
            }
            if (
                IERC20(OGUNToken).balanceOf(address(this)) >= rewardValue.mul(2)
            ) {
                OGUNToken.safeTransfer(_owner, rewardValue);
                OGUNToken.safeTransfer(_msgSender(), rewardValue);
            }
        } else if (isPaymentBTC) {
            // Placeholder for BTC owner payment
            revert("BTC payment not yet implemented; requires bridge integration");
        } else {
            (bool ownerTransferSuccess, ) = _owner.call{
                value: price.sub(feeAmount)
            }("");
            require(ownerTransferSuccess, "owner transfer failed");
        }

        IERC721(_nftAddress).safeTransferFrom(_owner, _msgSender(), _tokenId);

        emit ItemSold(
            _owner,
            _msgSender(),
            _nftAddress,
            _tokenId,
            listedItem.quantity,
            price.div(listedItem.quantity),
            isPaymentOGUN,
            isPaymentBTC,
            listedItem.chainId
        );
        delete (listings[_nftAddress][_tokenId][_owner]);
    }

    /// @notice Method for listing NFT
    /// @param _nftAddress Address of NFT contract
    /// @param _tokenId Token ID of NFT
    /// @param _quantity token amount to list
    /// @param _pricePerItem sale price for each iteam
    /// @param _OGUNPricePerItem New sale price in OGUN for each iteam
    /// @param _BTCPricePerItem New sale price in BTC for each item
    /// @param _acceptsMATIC true in case accepts MATIC as payment
    /// @param _acceptsOGUN true in case accepts OGUN as payment
    /// @param _acceptsBTC true in case accepts BTC as payment
    /// @param _startingTime scheduling for a future sale
    /// @param _chainId Chain ID for the listing
    function listItem(
        address _nftAddress,
        uint256 _tokenId,
        uint256 _quantity,
        uint256 _pricePerItem,
        uint256 _OGUNPricePerItem,
        uint256 _BTCPricePerItem,
        bool _acceptsMATIC,
        bool _acceptsOGUN,
        bool _acceptsBTC,
        uint256 _startingTime,
        uint256 _chainId
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
            (_acceptsMATIC || _acceptsOGUN || _acceptsBTC),
            "item should have a way of payment"
        );
        require(supportedChains[_chainId], "Unsupported chain");

        listings[_nftAddress][_tokenId][_msgSender()] = Listing(
            _quantity,
            _pricePerItem,
            _OGUNPricePerItem,
            _BTCPricePerItem,
            _acceptsMATIC,
            _acceptsOGUN,
            _acceptsBTC,
            _startingTime,
            _chainId
        );
        emit ItemListed(
            _msgSender(),
            _nftAddress,
            _tokenId,
            _quantity,
            _pricePerItem,
            _OGUNPricePerItem,
            _BTCPricePerItem,
            _acceptsMATIC,
            _acceptsOGUN,
            _acceptsBTC,
            _startingTime,
            _chainId
        );
    }

    /// @notice Method for batch listing NFT
    /// @param editionNumber edition number
    /// @param _pricePerItem sale price for each iteam
    /// @param _OGUNPricePerItem New sale price in OGUN for each iteam
    /// @param _BTCPricePerItem New sale price in BTC for each item
    /// @param _acceptsMATIC true in case accepts MATIC as payment
    /// @param _acceptsOGUN true in case accepts OGUN as payment
    /// @param _acceptsBTC true in case accepts BTC as payment
    /// @param _startingTime scheduling for a future sale
    /// @param _chainId Chain ID for the listing
    function listEdition(
        address _nftEditionAddress,
        uint256 editionNumber,
        uint256 _pricePerItem,
        uint256 _OGUNPricePerItem,
        uint256 _BTCPricePerItem,
        bool _acceptsMATIC,
        bool _acceptsOGUN,
        bool _acceptsBTC,
        uint256 _startingTime,
        uint256 _chainId
    ) external editionNotListed(_nftEditionAddress, editionNumber) {
        editionListings[_nftEditionAddress][editionNumber] = true;

        require(
            (_acceptsMATIC || _acceptsOGUN || _acceptsBTC),
            "item should have a way of payment"
        );
        require(supportedChains[_chainId], "Unsupported chain");

        if (
            IERC165(_nftEditionAddress).supportsInterface(INTERFACE_ID_ERC721)
        ) {
            IERC721 nft = IERC721(_nftEditionAddress);
            IEditions nftEdition = IEditions(_nftEditionAddress);

            require(
                nft.isApprovedForAll(_msgSender(), address(this)),
                "item not approved"
            );

            uint256[] memory tokensFromEdition = nftEdition
                .getTokenIdsOfEdition(editionNumber);

            require(tokensFromEdition.length > 0, "edition has no tokens");

            for (uint256 index = 0; index < tokensFromEdition.length; index++) {
                if (nft.ownerOf(tokensFromEdition[index]) == _msgSender()) {
                    listings[_nftEditionAddress][tokensFromEdition[index]][
                        _msgSender()
                    ] = Listing(
                        1,
                        _pricePerItem,
                        _OGUNPricePerItem,
                        _BTCPricePerItem,
                        _acceptsMATIC,
                        _acceptsOGUN,
                        _acceptsBTC,
                        _startingTime,
                        _chainId
                    );
                    emit ItemListed(
                        _msgSender(),
                        _nftEditionAddress,
                        tokensFromEdition[index],
                        1,
                        _pricePerItem,
                        _OGUNPricePerItem,
                        _BTCPricePerItem,
                        _acceptsMATIC,
                        _acceptsOGUN,
                        _acceptsBTC,
                        _startingTime,
                        _chainId
                    );
                }
            }

            emit EditionListed(_nftEditionAddress, editionNumber, _chainId);
        } else {
            revert("invalid nft address");
        }
    }

    /// @notice Method for batch listing NFT
    /// @param tokenIds all token IDs to list
    /// @param _pricePerItem sale price for each iteam
    /// @param _OGUNPricePerItem New sale price in OGUN for each iteam
    /// @param _BTCPricePerItem New sale price in BTC for each item
    /// @param _acceptsMATIC true in case accepts MATIC as payment
    /// @param _acceptsOGUN true in case accepts OGUN as payment
    /// @param _acceptsBTC true in case accepts BTC as payment
    /// @param _startingTime scheduling for a future sale
    /// @param _chainId Chain ID for the listing
    function listBatch(
        address _nftAddress,
        uint256[] memory tokenIds,
        uint256 _pricePerItem,
        uint256 _OGUNPricePerItem,
        uint256 _BTCPricePerItem,
        bool _acceptsMATIC,
        bool _acceptsOGUN,
        bool _acceptsBTC,
        uint256 _startingTime,
        uint256 _chainId
    ) external {
        require(
            (_acceptsMATIC || _acceptsOGUN || _acceptsBTC),
            "item should have a way of payment"
        );
        require(supportedChains[_chainId], "Unsupported chain");

        require(tokenIds.length > 0, "tokenIds is empty");

        if (IERC165(_nftAddress).supportsInterface(INTERFACE_ID_ERC721)) {
            IERC721 nft = IERC721(_nftAddress);

            require(
                nft.isApprovedForAll(_msgSender(), address(this)),
                "item not approved"
            );

            for (uint256 index = 0; index < tokenIds.length; index++) {
                if (nft.ownerOf(tokenIds[index]) == _msgSender()) {
                    require(
                        _notListed(_nftAddress, tokenIds[index], _msgSender()),
                        "item already listed"
                    );

                    listings[_nftAddress][tokenIds[index]][
                        _msgSender()
                    ] = Listing(
                        1,
                        _pricePerItem,
                        _OGUNPricePerItem,
                        _BTCPricePerItem,
                        _acceptsMATIC,
                        _acceptsOGUN,
                        _acceptsBTC,
                        _startingTime,
                        _chainId
                    );
                    emit ItemListed(
                        _msgSender(),
                        _nftAddress,
                        tokenIds[index],
                        1,
                        _pricePerItem,
                        _OGUNPricePerItem,
                        _BTCPricePerItem,
                        _acceptsMATIC,
                        _acceptsOGUN,
                        _acceptsBTC,
                        _startingTime,
                        _chainId
                    );
                }
            }
        } else {
            revert("invalid nft address");
        }
    }

    /// @notice Method for sweeping multiple NFTs from an edition
    /// @param _nftEditionAddress Address of NFT edition contract
    /// @param _editionNumber Edition number to sweep
    /// @param _quantity Quantity to purchase
    /// @param _isPaymentOGUN true if payment in OGUN
    /// @param _isPaymentBTC true if payment in BTC
    function sweepEdition(
        address _nftEditionAddress,
        uint256 _editionNumber,
        uint256 _quantity,
        bool _isPaymentOGUN,
        bool _isPaymentBTC
    ) external payable nonReentrant isEditionListed(_nftEditionAddress, _editionNumber) {
        IEditions nftEdition = IEditions(_nftEditionAddress);
        uint256[] memory tokenIds = nftEdition.getTokenIdsOfEdition(_editionNumber);
        require(tokenIds.length >= _quantity, "Insufficient tokens in edition");
        require(_quantity > 0 && _quantity <= 1000, "Quantity must be 1-1000"); // Match 1000/1000 limit

        Listing storage listedItem = listings[_nftEditionAddress][tokenIds[0]][msg.sender]; // Assume uniform pricing
        uint256 totalPrice = listedItem.pricePerItem.mul(_quantity);
        if (_isPaymentOGUN) totalPrice = listedItem.OGUNPricePerItem.mul(_quantity);
        else if (_isPaymentBTC) totalPrice = listedItem.BTCPricePerItem.mul(_quantity);

        require(!(_isPaymentOGUN && _isPaymentBTC), "Choose one payment type");
        if (_isPaymentOGUN) {
            uint256 allowance = OGUNToken.allowance(msg.sender, address(this));
            require(allowance >= totalPrice, "Insufficient OGUN allowance");
            require(listedItem.acceptsOGUN, "OGUN not accepted");
        } else if (_isPaymentBTC) {
            require(listedItem.acceptsBTC, "BTC not accepted");
            revert("BTC payment not yet implemented; requires bridge integration");
        } else {
            require(msg.value >= totalPrice, "Insufficient MATIC");
            require(listedItem.acceptsMATIC, "MATIC not accepted");
        }

        for (uint256 i = 0; i < _quantity; i++) {
            if (IERC721(_nftEditionAddress).ownerOf(tokenIds[i]) == msg.sender) continue; // Skip owned tokens
            _buyItem(_nftEditionAddress, tokenIds[i], IERC721(_nftEditionAddress).ownerOf(tokenIds[i]), _isPaymentOGUN, _isPaymentBTC);
        }

        emit ItemSold(msg.sender, msg.sender, _nftEditionAddress, _editionNumber, _quantity, totalPrice.div(_quantity), _isPaymentOGUN, _isPaymentBTC, block.chainid);
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

    /**
     @notice Method for withdraw any leftover OGUN
     @dev Only admin
     @param destination Where the OGUN will be sent
     */
    function withdraw(address destination) external onlyOwner {
        uint256 balance = IERC20(OGUNToken).balanceOf(address(this));
        IERC20(OGUNToken).transfer(destination, balance);
    }

    /**
     @notice Method for updating rewards rate
     @dev Only admin
     @param _rewardsRate rate to be aplyed
     */
    function setRewardsRate(uint256 _rewardsRate) public onlyOwner {
        rewardsRate = _rewardsRate;
    }

    /**
     @notice Method for updating rewards limit
     @dev Only admin
     @param newLimit Hardcap for rewards
     */
    function setRewardsLimit(uint256 newLimit) external onlyOwner {
        rewardsLimit = newLimit;
    }

    /**
     @notice Method for adding a new supported chain
     @dev Only admin
     @param _chainId Chain ID to add
     */
    function addSupportedChain(uint256 _chainId) external onlyOwner {
        supportedChains[_chainId] = true;
    }

    ////////////////////////////
    /// Internal and Private ///
    ////////////////////////////

    function _getNow() internal view virtual returns (uint256) {
        return block.timestamp;
    }

    function _isListed(
        address _nftAddress,
        uint256 _tokenId,
        address _owner
    ) private view returns (bool) {
        Listing memory listing = listings[_nftAddress][_tokenId][_owner];
        return listing.quantity > 0;
    }

    function _notListed(
        address _nftAddress,
        uint256 _tokenId,
        address _owner
    ) private view returns (bool) {
        Listing memory listing = listings[_nftAddress][_tokenId][_owner];
        return listing.quantity == 0;
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
        emit ItemCanceled(_owner, _nftAddress, _tokenId, block.chainid);
    }
}
