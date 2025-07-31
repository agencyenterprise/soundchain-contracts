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

    event ItemListed(
        address indexed owner,
        address indexed nft,
        uint256 tokenId,
        uint256 quantity,
        uint256 pricePerItem,
        uint256 OGUNPricePerItem,
        uint256 BTCPricePerItem,
        uint256 DOGEPricePerItem, // Dogecoin
        uint256 PENGUPricePerItem, // Pengu
        uint256 BONKPricePerItem, // Bonk
        uint256 MEATEORPricePerItem, // Meateor
        bool acceptsMATIC,
        bool acceptsOGUN,
        bool acceptsBTC,
        bool acceptsDOGE,
        bool acceptsPENGU,
        bool acceptsBONK,
        bool acceptsMEATEOR,
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
        bool isPaymentBTC,
        bool isPaymentDOGE,
        bool isPaymentPENGU,
        bool isPaymentBONK,
        bool isPaymentMEATEOR,
        uint256 chainId
    );
    event BulkAirdrop(address indexed sender, address[] recipients, uint256 tokenId, uint256 chainId);

    struct Listing {
        uint256 quantity;
        uint256 pricePerItem;
        uint256 OGUNPricePerItem;
        uint256 BTCPricePerItem;
        uint256 DOGEPricePerItem;
        uint256 PENGUPricePerItem;
        uint256 BONKPricePerItem;
        uint256 MEATEORPricePerItem;
        bool acceptsMATIC;
        bool acceptsOGUN;
        bool acceptsBTC;
        bool acceptsDOGE;
        bool acceptsPENGU;
        bool acceptsBONK;
        bool acceptsMEATEOR;
        uint256 startingTime;
        uint256 chainId;
    }

    bytes4 private constant INTERFACE_ID_ERC721 = 0x80ac58cd;

    IERC20 public immutable OGUNToken;
    mapping(uint256 => bool) public supportedChains;
    mapping(address => mapping(uint256 => mapping(address => Listing))) public listings;
    mapping(address => mapping(uint256 => bool)) public editionListings;
    uint16 public platformFee;
    address payable public feeRecipient;
    address public treasuryWallet;

    modifier isListed(address _nftAddress, uint256 _tokenId, address _owner) {
        require(_isListed(_nftAddress, _tokenId, _owner), "not listed item");
        _;
    }

    modifier notListed(address _nftAddress, uint256 _tokenId, address _owner) {
        require(_notListed(_nftAddress, _tokenId, _owner), "already listed");
        _;
    }

    modifier editionNotListed(address nftAddress, uint256 _editionNumber) {
        require(!editionListings[nftAddress][_editionNumber], "edition already listed");
        _;
    }

    modifier isEditionListed(address _nftAddress, uint256 _editionNumber) {
        require(editionListings[_nftAddress][_editionNumber], "edition not listed item");
        _;
    }

    modifier validListing(address _nftAddress, uint256 _tokenId, address _owner) {
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

    constructor(address payable _feeRecipient, address _OGUNToken, uint16 _platformFee, uint256 _rewardsRate, uint256 _rewardsLimit) {
        OGUNToken = IERC20(_OGUNToken);
        platformFee = _platformFee;
        feeRecipient = _feeRecipient;
        rewardsRate = _rewardsRate;
        rewardsLimit = _rewardsLimit;
        supportedChains[137] = true; // Polygon
        supportedChains[1] = true;   // Ethereum
        supportedChains[43114] = true; // Solana
        supportedChains[8453] = true; // Base
        supportedChains[205] = true;  // Tezos
        supportedChains[0] = true;    // Bitcoin (placeholder)
    }

    function setTreasuryWallet(address _treasuryWallet) external onlyOwner {
        treasuryWallet = _treasuryWallet;
    }

    function cancelListing(address _nftAddress, uint256 _tokenId) external nonReentrant isListed(_nftAddress, _tokenId, _msgSender()) {
        _cancelListing(_nftAddress, _tokenId, _msgSender());
    }

    function cancelEditionListing(address _nftAddress, uint256 _editionNumber) external nonReentrant isEditionListed(_nftAddress, _editionNumber) {
        IERC721 nft = IERC721(_nftAddress);
        IEditions nftEdition = IEditions(_nftAddress);
        uint256[] memory tokensFromEdition = nftEdition.getTokenIdsOfEdition(_editionNumber);
        require(tokensFromEdition.length > 0, "edition has no tokens");
        for (uint256 index = 0; index < tokensFromEdition.length; index++) {
            if (nft.ownerOf(tokensFromEdition[index]) == _msgSender()) {
                _cancelListing(_nftAddress, tokensFromEdition[index], _msgSender());
            }
        }
        editionListings[_nftAddress][_editionNumber] = false;
        emit EditionCanceled(_nftAddress, _editionNumber, block.chainid);
    }

    function cancelListingBatch(address _nftAddress, uint256[] memory tokenIds) external nonReentrant {
        IERC721 nft = IERC721(_nftAddress);
        require(tokenIds.length > 0, "tokenIds is empty");
        for (uint256 index = 0; index < tokenIds.length; index++) {
            if (nft.ownerOf(tokenIds[index]) == _msgSender()) {
                require(_isListed(_nftAddress, tokenIds[index], _msgSender()), "item not listed");
                _cancelListing(_nftAddress, tokenIds[index], _msgSender());
            }
        }
    }

    function updateListing(
        address _nftAddress,
        uint256 _tokenId,
        uint256 _newPrice,
        uint256 _newOGUNPrice,
        uint256 _newBTCPrice,
        uint256 _newDOGEPrice,
        uint256 _newPENGUPrice,
        uint256 _newBONKPrice,
        uint256 _newMEATEORPrice,
        bool _acceptsMATIC,
        bool _acceptsOGUN,
        bool _acceptsBTC,
        bool _acceptsDOGE,
        bool _acceptsPENGU,
        bool _acceptsBONK,
        bool _acceptsMEATEOR,
        uint256 _startingTime,
        uint256 _chainId
    ) external nonReentrant isListed(_nftAddress, _tokenId, _msgSender()) {
        Listing storage listedItem = listings[_nftAddress][_tokenId][_msgSender()];
        if (IERC165(_nftAddress).supportsInterface(INTERFACE_ID_ERC721)) {
            IERC721 nft = IERC721(_nftAddress);
            require(nft.ownerOf(_tokenId) == _msgSender(), "not owning item");
        } else {
            revert("invalid nft address");
        }
        require(_acceptsMATIC || _acceptsOGUN || _acceptsBTC || _acceptsDOGE || _acceptsPENGU || _acceptsBONK || _acceptsMEATEOR, "item should have a way of payment");
        require(supportedChains[_chainId], "Unsupported chain");
        listedItem.pricePerItem = _newPrice;
        listedItem.acceptsMATIC = _acceptsMATIC;
        listedItem.OGUNPricePerItem = _newOGUNPrice;
        listedItem.acceptsOGUN = _acceptsOGUN;
        listedItem.BTCPricePerItem = _newBTCPrice;
        listedItem.acceptsBTC = _acceptsBTC;
        listedItem.DOGEPricePerItem = _newDOGEPrice;
        listedItem.acceptsDOGE = _acceptsDOGE;
        listedItem.PENGUPricePerItem = _newPENGUPrice;
        listedItem.acceptsPENGU = _acceptsPENGU;
        listedItem.BONKPricePerItem = _newBONKPrice;
        listedItem.acceptsBONK = _acceptsBONK;
        listedItem.MEATEORPricePerItem = _newMEATEORPrice;
        listedItem.acceptsMEATEOR = _acceptsMEATEOR;
        listedItem.startingTime = _startingTime;
        listedItem.chainId = _chainId;
        emit ItemListed(_msgSender(), _nftAddress, _tokenId, listedItem.quantity, _newPrice, _newOGUNPrice, _newBTCPrice, _newDOGEPrice, _newPENGUPrice, _newBONKPrice, _newMEATEORPrice, _acceptsMATIC, _acceptsOGUN, _acceptsBTC, _acceptsDOGE, _acceptsPENGU, _acceptsBONK, _acceptsMEATEOR, _startingTime, _chainId);
    }

    function buyItem(
        address _nftAddress,
        uint256 _tokenId,
        address payable _owner,
        bool _isPaymentOGUN,
        bool _isPaymentBTC,
        bool _isPaymentDOGE,
        bool _isPaymentPENGU,
        bool _isPaymentBONK,
        bool _isPaymentMEATEOR
    ) external payable nonReentrant isListed(_nftAddress, _tokenId, _owner) validListing(_nftAddress, _tokenId, _owner) {
        Listing memory listedItem = listings[_nftAddress][_tokenId][_owner];
        require(!(_isPaymentOGUN && (_isPaymentBTC || _isPaymentDOGE || _isPaymentPENGU || _isPaymentBONK || _isPaymentMEATEOR)), "Choose one payment type");
        uint256 price;
        if (_isPaymentOGUN) {
            price = listedItem.OGUNPricePerItem.mul(listedItem.quantity);
            require(listedItem.acceptsOGUN, "OGUN not accepted");
        } else if (_isPaymentBTC) {
            price = listedItem.BTCPricePerItem.mul(listedItem.quantity);
            require(listedItem.acceptsBTC, "BTC not accepted");
            revert("BTC payment requires ZetaChain bridge");
        } else if (_isPaymentDOGE) {
            price = listedItem.DOGEPricePerItem.mul(listedItem.quantity);
            require(listedItem.acceptsDOGE, "DOGE not accepted");
        } else if (_isPaymentPENGU) {
            price = listedItem.PENGUPricePerItem.mul(listedItem.quantity);
            require(listedItem.acceptsPENGU, "PENGU not accepted");
        } else if (_isPaymentBONK) {
            price = listedItem.BONKPricePerItem.mul(listedItem.quantity);
            require(listedItem.acceptsBONK, "BONK not accepted");
        } else if (_isPaymentMEATEOR) {
            price = listedItem.MEATEORPricePerItem.mul(listedItem.quantity);
            require(listedItem.acceptsMEATEOR, "MEATEOR not accepted");
        } else {
            price = listedItem.pricePerItem.mul(listedItem.quantity);
            require(listedItem.acceptsMATIC, "MATIC not accepted");
        }
        _buyItem(_nftAddress, _tokenId, _owner, _isPaymentOGUN, _isPaymentBTC, _isPaymentDOGE, _isPaymentPENGU, _isPaymentBONK, _isPaymentMEATEOR, price);
    }

    function _buyItem(
        address _nftAddress,
        uint256 _tokenId,
        address _owner,
        bool isPaymentOGUN,
        bool isPaymentBTC,
        bool isPaymentDOGE,
        bool isPaymentPENGU,
        bool isPaymentBONK,
        bool isPaymentMEATEOR,
        uint256 price
    ) private {
        uint256 feeAmount = price.mul(platformFee).div(1e4);
        IERC20 paymentToken;
        if (isPaymentOGUN) {
            paymentToken = OGUNToken;
        } else if (isPaymentBTC) {
            revert("BTC payment requires ZetaChain bridge");
        } else if (isPaymentDOGE) {
            paymentToken = IERC20(0xbA2aE424d960c26247Dd6c32edC70B295c744c43); // Example DOGE address
        } else if (isPaymentPENGU) {
            paymentToken = IERC20(0xYourPENGUAddress); // Replace with actual PENGU address
        } else if (isPaymentBONK) {
            paymentToken = IERC20(0xYourBONKAddress); // Replace with actual BONK address
        } else if (isPaymentMEATEOR) {
            paymentToken = IERC20(0xYourMEATEORAddress); // Replace with actual MEATEOR address
        } else {
            // MATIC handled via msg.value
        }
        if (isPaymentOGUN || isPaymentDOGE || isPaymentPENGU || isPaymentBONK || isPaymentMEATEOR) {
            paymentToken.safeTransferFrom(_msgSender(), feeRecipient, feeAmount);
        } else {
            (bool feeTransferSuccess, ) = feeRecipient.call{value: feeAmount}("");
            require(feeTransferSuccess, "fee transfer failed");
        }
        (address minter, uint256 royaltyFee) = IERC2981(_nftAddress).royaltyInfo(_tokenId, price.sub(feeAmount));
        if (minter != address(0)) {
            if (isPaymentOGUN) paymentToken.safeTransferFrom(_msgSender(), minter, royaltyFee);
            else if (isPaymentBTC) revert("BTC payment requires ZetaChain bridge");
            else if (isPaymentDOGE || isPaymentPENGU || isPaymentBONK || isPaymentMEATEOR) paymentToken.safeTransferFrom(_msgSender(), minter, royaltyFee);
            else (bool royaltyTransferSuccess, ) = payable(minter).call{value: royaltyFee}("");
            require(royaltyTransferSuccess, "royalty fee transfer failed");
            feeAmount = feeAmount.add(royaltyFee);
        }
        if (isPaymentOGUN || isPaymentDOGE || isPaymentPENGU || isPaymentBONK || isPaymentMEATEOR) {
            paymentToken.safeTransferFrom(_msgSender(), _owner, price.sub(feeAmount));
            if (treasuryWallet != address(0)) paymentToken.safeTransferFrom(_msgSender(), treasuryWallet, price.mul(5).div(10000)); // 0.05% fee
        } else {
            (bool ownerTransferSuccess, ) = _owner.call{value: price.sub(feeAmount)}("");
            require(ownerTransferSuccess, "owner transfer failed");
            if (treasuryWallet != address(0)) (bool treasurySuccess, ) = treasuryWallet.call{value: price.mul(5).div(10000)}("");
            require(treasurySuccess, "treasury transfer failed");
        }
        IERC721(_nftAddress).safeTransferFrom(_owner, _msgSender(), _tokenId);
        emit ItemSold(_owner, _msgSender(), _nftAddress, _tokenId, listedItem.quantity, price.div(listedItem.quantity), isPaymentOGUN, isPaymentBTC, isPaymentDOGE, isPaymentPENGU, isPaymentBONK, isPaymentMEATEOR, listedItem.chainId);
        delete (listings[_nftAddress][_tokenId][_owner]);
    }

    function listItem(
        address _nftAddress,
        uint256 _tokenId,
        uint256 _quantity,
        uint256 _pricePerItem,
        uint256 _OGUNPricePerItem,
        uint256 _BTCPricePerItem,
        uint256 _DOGEPricePerItem,
        uint256 _PENGUPricePerItem,
        uint256 _BONKPricePerItem,
        uint256 _MEATEORPricePerItem,
        bool _acceptsMATIC,
        bool _acceptsOGUN,
        bool _acceptsBTC,
        bool _acceptsDOGE,
        bool _acceptsPENGU,
        bool _acceptsBONK,
        bool _acceptsMEATEOR,
        uint256 _startingTime,
        uint256 _chainId
    ) external notListed(_nftAddress, _tokenId, _msgSender()) {
        if (IERC165(_nftAddress).supportsInterface(INTERFACE_ID_ERC721)) {
            IERC721 nft = IERC721(_nftAddress);
            require(nft.ownerOf(_tokenId) == _msgSender(), "not owning item");
            require(nft.isApprovedForAll(_msgSender(), address(this)), "item not approved");
        } else {
            revert("invalid nft address");
        }
        require(_acceptsMATIC || _acceptsOGUN || _acceptsBTC || _acceptsDOGE || _acceptsPENGU || _acceptsBONK || _acceptsMEATEOR, "item should have a way of payment");
        require(supportedChains[_chainId], "Unsupported chain");
        listings[_nftAddress][_tokenId][_msgSender()] = Listing(_quantity, _pricePerItem, _OGUNPricePerItem, _BTCPricePerItem, _DOGEPricePerItem, _PENGUPricePerItem, _BONKPricePerItem, _MEATEORPricePerItem, _acceptsMATIC, _acceptsOGUN, _acceptsBTC, _acceptsDOGE, _acceptsPENGU, _acceptsBONK, _acceptsMEATEOR, _startingTime, _chainId);
        emit ItemListed(_msgSender(), _nftAddress, _tokenId, _quantity, _pricePerItem, _OGUNPricePerItem, _BTCPricePerItem, _DOGEPricePerItem, _PENGUPricePerItem, _BONKPricePerItem, _MEATEORPricePerItem, _acceptsMATIC, _acceptsOGUN, _acceptsBTC, _acceptsDOGE, _acceptsPENGU, _acceptsBONK, _acceptsMEATEOR, _startingTime, _chainId);
    }

    function airdropNFTs(address _nftAddress, uint256 _tokenId, address[] memory _recipients) external nonReentrant {
        IERC721 nft = IERC721(_nftAddress);
        require(nft.ownerOf(_tokenId) == msg.sender, "Not owner");
        require(nft.isApprovedForAll(msg.sender, address(this)), "Not approved");
        for (uint256 i = 0; i < _recipients.length; i++) {
            nft.safeTransferFrom(msg.sender, _recipients[i], _tokenId);
            (address royaltyReceiver, uint256 royaltyAmount) = IERC2981(_nftAddress).royaltyInfo(_tokenId, 0);
            if (royaltyReceiver != address(0) && treasuryWallet != address(0)) {
                // Placeholder for royalty payment (requires payment context)
            }
        }
        emit BulkAirdrop(msg.sender, _recipients, _tokenId, block.chainid);
    }

    function sweepEdition(
        address _nftEditionAddress,
        uint256 _editionNumber,
        uint256 _quantity,
        bool _isPaymentOGUN,
        bool _isPaymentBTC,
        bool _isPaymentDOGE,
        bool _isPaymentPENGU,
        bool _isPaymentBONK,
        bool _isPaymentMEATEOR
    ) external payable nonReentrant isEditionListed(_nftEditionAddress, _editionNumber) {
        IEditions nftEdition = IEditions(_nftEditionAddress);
        uint256[] memory tokenIds = nftEdition.getTokenIdsOfEdition(_editionNumber);
        require(tokenIds.length >= _quantity, "Insufficient tokens");
        require(_quantity > 0 && _quantity <= 1000, "Quantity must be 1-1000");
        Listing storage listedItem = listings[_nftEditionAddress][tokenIds[0]][msg.sender];
        uint256 totalPrice = _isPaymentOGUN ? listedItem.OGUNPricePerItem.mul(_quantity)
            : _isPaymentBTC ? listedItem.BTCPricePerItem.mul(_quantity)
            : _isPaymentDOGE ? listedItem.DOGEPricePerItem.mul(_quantity)
            : _isPaymentPENGU ? listedItem.PENGUPricePerItem.mul(_quantity)
            : _isPaymentBONK ? listedItem.BONKPricePerItem.mul(_quantity)
            : _isPaymentMEATEOR ? listedItem.MEATEORPricePerItem.mul(_quantity)
            : listedItem.pricePerItem.mul(_quantity);
        require(!(_isPaymentOGUN && (_isPaymentBTC || _isPaymentDOGE || _isPaymentPENGU || _isPaymentBONK || _isPaymentMEATEOR)), "Choose one payment");
        IERC20 paymentToken;
        if (_isPaymentOGUN) {
            paymentToken = OGUNToken;
            require(listedItem.acceptsOGUN, "OGUN not accepted");
        } else if (_isPaymentBTC) {
            paymentToken = IERC20(0xYourBTCAddress); // Replace
            require(listedItem.acceptsBTC, "BTC not accepted");
            revert("BTC requires ZetaChain");
        } else if (_isPaymentDOGE) {
            paymentToken = IERC20(0xbA2aE424d960c26247Dd6c32edC70B295c744c43); // Example
            require(listedItem.acceptsDOGE, "DOGE not accepted");
        } else if (_isPaymentPENGU) {
            paymentToken = IERC20(0xYourPENGUAddress); // Replace
            require(listedItem.acceptsPENGU, "PENGU not accepted");
        } else if (_isPaymentBONK) {
            paymentToken = IERC20(0xYourBONKAddress); // Replace
            require(listedItem.acceptsBONK, "BONK not accepted");
        } else if (_isPaymentMEATEOR) {
            paymentToken = IERC20(0xYourMEATEORAddress); // Replace
            require(listedItem.acceptsMEATEOR, "MEATEOR not accepted");
        } else {
            require(msg.value >= totalPrice, "Insufficient MATIC");
            require(listedItem.acceptsMATIC, "MATIC not accepted");
        }
        if (_isPaymentOGUN || _isPaymentDOGE || _isPaymentPENGU || _isPaymentBONK || _isPaymentMEATEOR) {
            paymentToken.safeTransferFrom(msg.sender, address(this), totalPrice);
        }
        for (uint256 i = 0; i < _quantity; i++) {
            if (IERC721(_nftEditionAddress).ownerOf(tokenIds[i]) != msg.sender) {
                _buyItem(_nftEditionAddress, tokenIds[i], IERC721(_nftEditionAddress).ownerOf(tokenIds[i]), _isPaymentOGUN, _isPaymentBTC, _isPaymentDOGE, _isPaymentPENGU, _isPaymentBONK, _isPaymentMEATEOR, totalPrice.div(_quantity));
            }
        }
        emit ItemSold(msg.sender, msg.sender, _nftEditionAddress, _editionNumber, _quantity, totalPrice.div(_quantity), _isPaymentOGUN, _isPaymentBTC, _isPaymentDOGE, _isPaymentPENGU, _isPaymentBONK, _isPaymentMEATEOR, block.chainid);
    }

    // Additional functions...

    function updatePlatformFee(uint16 _platformFee) external onlyOwner {
        platformFee = _platformFee;
        emit UpdatePlatformFee(_platformFee);
    }

    function updatePlatformFeeRecipient(address payable _platformFeeRecipient) external onlyOwner {
        feeRecipient = _platformFeeRecipient;
        emit UpdatePlatformFeeRecipient(_platformFeeRecipient);
    }

    function withdraw(address destination) external onlyOwner {
        uint256 balance = IERC20(OGUNToken).balanceOf(address(this));
        IERC20(OGUNToken).transfer(destination, balance);
    }

    function setRewardsRate(uint256 _rewardsRate) public onlyOwner {
        rewardsRate = _rewardsRate;
    }

    function setRewardsLimit(uint256 newLimit) external onlyOwner {
        rewardsLimit = newLimit;
    }

    function addSupportedChain(uint256 _chainId) external onlyOwner {
        supportedChains[_chainId] = true;
    }

    function _getNow() internal view virtual returns (uint256) {
        return block.timestamp;
    }

    function _isListed(address _nftAddress, uint256 _tokenId, address _owner) private view returns (bool) {
        Listing memory listing = listings[_nftAddress][_tokenId][_owner];
        return listing.quantity > 0;
    }

    function _notListed(address _nftAddress, uint256 _tokenId, address _owner) private view returns (bool) {
        Listing memory listing = listings[_nftAddress][_tokenId][_owner];
        return listing.quantity == 0;
    }

    function _cancelListing(address _nftAddress, uint256 _tokenId, address _owner) private {
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
