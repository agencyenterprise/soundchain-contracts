// SPDX-License-Identifier: MIT

pragma solidity ^0.8.10;

import "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/interfaces/IERC2981.sol";
import "./IEditions.sol";

/**
 * @title SoundchainMarketplaceEditions
 * @dev NFT Marketplace supporting multiple payment tokens via ZetaChain omnichain
 */
contract SoundchainMarketplaceEditions is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    // Payment types enum to reduce stack depth (instead of multiple bools)
    enum PaymentType { POL, OGUN, BTC, DOGE, PENGU, BONK, MEATEOR }

    uint256 public rewardsRate;
    uint256 public rewardsLimit;

    // Simplified events to avoid stack too deep
    event ItemListed(
        address indexed owner,
        address indexed nft,
        uint256 tokenId,
        uint256 quantity,
        uint256 chainId
    );

    event ItemSold(
        address indexed seller,
        address indexed buyer,
        address indexed nft,
        uint256 tokenId,
        uint256 quantity,
        uint256 pricePerItem,
        PaymentType paymentType,
        uint256 chainId
    );

    event BulkAirdrop(address indexed sender, address[] recipients, uint256 tokenId, uint256 chainId);
    event EditionCanceled(address indexed nftAddress, uint256 editionNumber, uint256 chainId);
    event ItemCanceled(address indexed owner, address indexed nftAddress, uint256 tokenId, uint256 chainId);
    event UpdatePlatformFee(uint16 platformFee);
    event UpdatePlatformFeeRecipient(address feeRecipient);

    // Prices struct to reduce storage slots
    struct TokenPrices {
        uint256 POL;
        uint256 OGUN;
        uint256 BTC;
        uint256 DOGE;
        uint256 PENGU;
        uint256 BONK;
        uint256 MEATEOR;
    }

    struct Listing {
        uint256 quantity;
        TokenPrices prices;
        uint8 acceptedPayments; // Bitmask: 0x01=POL, 0x02=OGUN, 0x04=BTC, 0x08=DOGE, 0x10=PENGU, 0x20=BONK, 0x40=MEATEOR
        uint256 startingTime;
        uint256 chainId;
    }

    bytes4 private constant INTERFACE_ID_ERC721 = 0x80ac58cd;

    IERC20 public immutable OGUNToken;

    // Token addresses - set by owner
    mapping(PaymentType => address) public paymentTokenAddresses;

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
        Listing storage listedItem = listings[_nftAddress][_tokenId][_owner];
        require(IERC165(_nftAddress).supportsInterface(INTERFACE_ID_ERC721), "invalid nft");
        require(IERC721(_nftAddress).ownerOf(_tokenId) == _owner, "not owning item");
        require(block.timestamp >= listedItem.startingTime, "item not buyable");
        require(supportedChains[listedItem.chainId], "Unsupported chain");
        _;
    }

    constructor(address payable _feeRecipient, address _OGUNToken, uint16 _platformFee, uint256 _rewardsRate, uint256 _rewardsLimit) {
        OGUNToken = IERC20(_OGUNToken);
        platformFee = _platformFee;
        feeRecipient = _feeRecipient;
        rewardsRate = _rewardsRate;
        rewardsLimit = _rewardsLimit;

        // Set OGUN token address
        paymentTokenAddresses[PaymentType.OGUN] = _OGUNToken;

        supportedChains[137] = true; // Polygon
        supportedChains[1] = true;   // Ethereum
        supportedChains[43114] = true; // Avalanche
        supportedChains[8453] = true; // Base
        supportedChains[7000] = true; // ZetaChain
    }

    function setTreasuryWallet(address _treasuryWallet) external onlyOwner {
        treasuryWallet = _treasuryWallet;
    }

    function setPaymentTokenAddress(PaymentType _type, address _tokenAddress) external onlyOwner {
        paymentTokenAddresses[_type] = _tokenAddress;
    }

    function cancelListing(address _nftAddress, uint256 _tokenId) external nonReentrant isListed(_nftAddress, _tokenId, _msgSender()) {
        _cancelListing(_nftAddress, _tokenId, _msgSender());
    }

    function cancelEditionListing(address _nftAddress, uint256 _editionNumber) external nonReentrant isEditionListed(_nftAddress, _editionNumber) {
        IEditions nftEdition = IEditions(_nftAddress);
        uint256[] memory tokensFromEdition = nftEdition.getTokenIdsOfEdition(_editionNumber);
        require(tokensFromEdition.length > 0, "edition has no tokens");

        for (uint256 index = 0; index < tokensFromEdition.length; index++) {
            if (IERC721(_nftAddress).ownerOf(tokensFromEdition[index]) == _msgSender()) {
                _cancelListing(_nftAddress, tokensFromEdition[index], _msgSender());
            }
        }
        editionListings[_nftAddress][_editionNumber] = false;
        emit EditionCanceled(_nftAddress, _editionNumber, block.chainid);
    }

    function listItem(
        address _nftAddress,
        uint256 _tokenId,
        uint256 _quantity,
        uint256[7] calldata _prices, // [POL, OGUN, BTC, DOGE, PENGU, BONK, MEATEOR]
        uint8 _acceptedPayments, // Bitmask
        uint256 _startingTime,
        uint256 _chainId
    ) external notListed(_nftAddress, _tokenId, _msgSender()) {
        require(IERC165(_nftAddress).supportsInterface(INTERFACE_ID_ERC721), "invalid nft");
        IERC721 nft = IERC721(_nftAddress);
        require(nft.ownerOf(_tokenId) == _msgSender(), "not owning item");
        require(nft.isApprovedForAll(_msgSender(), address(this)), "item not approved");
        require(_acceptedPayments > 0, "must accept at least one payment");
        require(supportedChains[_chainId], "Unsupported chain");

        listings[_nftAddress][_tokenId][_msgSender()] = Listing({
            quantity: _quantity,
            prices: TokenPrices({
                POL: _prices[0],
                OGUN: _prices[1],
                BTC: _prices[2],
                DOGE: _prices[3],
                PENGU: _prices[4],
                BONK: _prices[5],
                MEATEOR: _prices[6]
            }),
            acceptedPayments: _acceptedPayments,
            startingTime: _startingTime,
            chainId: _chainId
        });

        emit ItemListed(_msgSender(), _nftAddress, _tokenId, _quantity, _chainId);
    }

    function updateListing(
        address _nftAddress,
        uint256 _tokenId,
        uint256[7] calldata _prices,
        uint8 _acceptedPayments,
        uint256 _startingTime,
        uint256 _chainId
    ) external nonReentrant isListed(_nftAddress, _tokenId, _msgSender()) {
        require(IERC165(_nftAddress).supportsInterface(INTERFACE_ID_ERC721), "invalid nft");
        require(IERC721(_nftAddress).ownerOf(_tokenId) == _msgSender(), "not owning item");
        require(_acceptedPayments > 0, "must accept at least one payment");
        require(supportedChains[_chainId], "Unsupported chain");

        Listing storage listedItem = listings[_nftAddress][_tokenId][_msgSender()];
        listedItem.prices = TokenPrices({
            POL: _prices[0],
            OGUN: _prices[1],
            BTC: _prices[2],
            DOGE: _prices[3],
            PENGU: _prices[4],
            BONK: _prices[5],
            MEATEOR: _prices[6]
        });
        listedItem.acceptedPayments = _acceptedPayments;
        listedItem.startingTime = _startingTime;
        listedItem.chainId = _chainId;

        emit ItemListed(_msgSender(), _nftAddress, _tokenId, listedItem.quantity, _chainId);
    }

    function buyItem(
        address _nftAddress,
        uint256 _tokenId,
        address payable _owner,
        PaymentType _paymentType
    ) external payable nonReentrant isListed(_nftAddress, _tokenId, _owner) validListing(_nftAddress, _tokenId, _owner) {
        _buyItem(_nftAddress, _tokenId, _owner, _paymentType);
    }

    function _buyItem(
        address _nftAddress,
        uint256 _tokenId,
        address _owner,
        PaymentType _paymentType
    ) private {
        Listing storage listedItem = listings[_nftAddress][_tokenId][_owner];

        // Verify payment type is accepted
        uint8 paymentMask = uint8(1 << uint8(_paymentType));
        require(listedItem.acceptedPayments & paymentMask != 0, "Payment type not accepted");

        uint256 price = _getPrice(listedItem, _paymentType);
        uint256 totalPrice = price.mul(listedItem.quantity);
        uint256 feeAmount = totalPrice.mul(platformFee).div(1e4);

        // Handle payment
        if (_paymentType == PaymentType.POL) {
            require(msg.value >= totalPrice, "Insufficient POL");
            (bool feeSuccess, ) = feeRecipient.call{value: feeAmount}("");
            require(feeSuccess, "fee transfer failed");
        } else if (_paymentType == PaymentType.BTC) {
            revert("BTC requires ZetaChain bridge");
        } else {
            IERC20 paymentToken = IERC20(paymentTokenAddresses[_paymentType]);
            require(address(paymentToken) != address(0), "Token not configured");
            paymentToken.safeTransferFrom(_msgSender(), feeRecipient, feeAmount);
        }

        // Handle royalties
        (address minter, uint256 royaltyFee) = IERC2981(_nftAddress).royaltyInfo(_tokenId, totalPrice.sub(feeAmount));
        if (minter != address(0) && royaltyFee > 0) {
            _transferPayment(_paymentType, _msgSender(), minter, royaltyFee);
            feeAmount = feeAmount.add(royaltyFee);
        }

        // Pay seller
        uint256 sellerAmount = totalPrice.sub(feeAmount);
        _transferPayment(_paymentType, _msgSender(), _owner, sellerAmount);

        // Treasury fee (0.05%)
        if (treasuryWallet != address(0)) {
            uint256 treasuryFee = totalPrice.mul(5).div(10000);
            _transferPayment(_paymentType, _msgSender(), treasuryWallet, treasuryFee);
        }

        // Transfer NFT
        IERC721(_nftAddress).safeTransferFrom(_owner, _msgSender(), _tokenId);

        emit ItemSold(_owner, _msgSender(), _nftAddress, _tokenId, listedItem.quantity, price, _paymentType, listedItem.chainId);
        delete listings[_nftAddress][_tokenId][_owner];
    }

    function _getPrice(Listing storage _listing, PaymentType _type) private view returns (uint256) {
        if (_type == PaymentType.POL) return _listing.prices.POL;
        if (_type == PaymentType.OGUN) return _listing.prices.OGUN;
        if (_type == PaymentType.BTC) return _listing.prices.BTC;
        if (_type == PaymentType.DOGE) return _listing.prices.DOGE;
        if (_type == PaymentType.PENGU) return _listing.prices.PENGU;
        if (_type == PaymentType.BONK) return _listing.prices.BONK;
        if (_type == PaymentType.MEATEOR) return _listing.prices.MEATEOR;
        revert("Invalid payment type");
    }

    function _transferPayment(PaymentType _type, address _from, address _to, uint256 _amount) private {
        if (_type == PaymentType.POL) {
            (bool success, ) = payable(_to).call{value: _amount}("");
            require(success, "POL transfer failed");
        } else {
            IERC20 token = IERC20(paymentTokenAddresses[_type]);
            if (_from == address(this)) {
                token.safeTransfer(_to, _amount);
            } else {
                token.safeTransferFrom(_from, _to, _amount);
            }
        }
    }

    function airdropNFTs(address _nftAddress, uint256 _tokenId, address[] calldata _recipients) external nonReentrant {
        IERC721 nft = IERC721(_nftAddress);
        require(nft.ownerOf(_tokenId) == msg.sender, "Not owner");
        require(nft.isApprovedForAll(msg.sender, address(this)), "Not approved");

        for (uint256 i = 0; i < _recipients.length; i++) {
            nft.safeTransferFrom(msg.sender, _recipients[i], _tokenId);
        }
        emit BulkAirdrop(msg.sender, _recipients, _tokenId, block.chainid);
    }

    function updatePlatformFee(uint16 _platformFee) external onlyOwner {
        platformFee = _platformFee;
        emit UpdatePlatformFee(_platformFee);
    }

    function updatePlatformFeeRecipient(address payable _platformFeeRecipient) external onlyOwner {
        feeRecipient = _platformFeeRecipient;
        emit UpdatePlatformFeeRecipient(_platformFeeRecipient);
    }

    function withdraw(address destination) external onlyOwner {
        uint256 balance = OGUNToken.balanceOf(address(this));
        OGUNToken.transfer(destination, balance);
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

    function _isListed(address _nftAddress, uint256 _tokenId, address _owner) private view returns (bool) {
        return listings[_nftAddress][_tokenId][_owner].quantity > 0;
    }

    function _notListed(address _nftAddress, uint256 _tokenId, address _owner) private view returns (bool) {
        return listings[_nftAddress][_tokenId][_owner].quantity == 0;
    }

    function _cancelListing(address _nftAddress, uint256 _tokenId, address _owner) private {
        require(IERC165(_nftAddress).supportsInterface(INTERFACE_ID_ERC721), "invalid nft");
        require(IERC721(_nftAddress).ownerOf(_tokenId) == _owner, "not owning item");
        delete listings[_nftAddress][_tokenId][_owner];
        emit ItemCanceled(_owner, _nftAddress, _tokenId, block.chainid);
    }

    receive() external payable {}
}
