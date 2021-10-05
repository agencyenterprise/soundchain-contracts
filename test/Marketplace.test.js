const {
  BN,
  constants,
  expectRevert,
  balance,
} = require("@openzeppelin/test-helpers");
const { ZERO_ADDRESS } = constants;
const { expect } = require("chai");
const SoundchainNFT = artifacts.require("SoundchainCollectible");
const Marketplace = artifacts.require("SoundchainMarketplace");
const BundleMarketplace = artifacts.require("SoundchainBundleMarketplace");
const AddressRegistry = artifacts.require("SoundchainAddressRegistry");

contract("Core ERC721 tests for SoundchainNFT", ([owner, minter, buyer]) => {
  const firstTokenId = new BN("0");
  const secondTokenId = new BN("1");
  const platformFee = new BN("25"); // marketplace platform fee: 2.5%
  const pricePerItem = new BN("1000000000000000000");
  const newPrice = new BN("500000000000000000");
  const randomTokenURI = "ipfs";

  beforeEach(async () => {
    this.bundleMarketplace = await BundleMarketplace.new(
      "0xFC00FACE00000000000000000000000000000000",
      platformFee,
      { from: owner }
    );
    this.nft = await SoundchainNFT.new({ from: owner });
    this.marketplace = await Marketplace.new(
      "0xFC00FACE00000000000000000000000000000000",
      platformFee,
      { from: owner }
    );
    this.addressRegistry = await AddressRegistry.new({ from: owner });
    await this.addressRegistry.updateMarketplace(this.marketplace.address, {
      from: owner,
    });
    await this.addressRegistry.updateBundleMarketplace(
      this.bundleMarketplace.address,
      {
        from: owner,
      }
    );

    await this.nft.safeMint(minter, randomTokenURI, { from: owner });
    await this.nft.safeMint(owner, randomTokenURI, { from: owner });
  });

  describe("Listing Item", () => {
    it("reverts when not owning NFT", async () => {
      await expectRevert(
        this.marketplace.listItem(
          this.nft.address,
          firstTokenId,
          "1",
          ZERO_ADDRESS,
          pricePerItem,
          "0",
          { from: owner }
        ),
        "not owning item"
      );
    });

    it("reverts when not approved", async () => {
      await expectRevert(
        this.marketplace.listItem(
          this.nft.address,
          firstTokenId,
          "1",
          ZERO_ADDRESS,
          pricePerItem,
          "0",
          { from: minter }
        ),
        "item not approved"
      );
    });

    it("successfuly lists item", async () => {
      await this.nft.setApprovalForAll(this.marketplace.address, true, {
        from: minter,
      });
      await this.marketplace.listItem(
        this.nft.address,
        firstTokenId,
        "1",
        ZERO_ADDRESS,
        pricePerItem,
        "0",
        { from: minter }
      );
    });
  });

  describe("Canceling Item", () => {
    beforeEach(async () => {
      await this.nft.setApprovalForAll(this.marketplace.address, true, {
        from: minter,
      });
      await this.marketplace.listItem(
        this.nft.address,
        firstTokenId,
        "1",
        ZERO_ADDRESS,
        pricePerItem,
        "0",
        { from: minter }
      );
    });

    it("reverts when item is not listed", async () => {
      await expectRevert(
        this.marketplace.cancelListing(this.nft.address, secondTokenId, {
          from: owner,
        }),
        "not listed item"
      );
    });

    it("reverts when not owning the item", async () => {
      await expectRevert(
        this.marketplace.cancelListing(this.nft.address, firstTokenId, {
          from: owner,
        }),
        "not listed item" // TODO: investigate if there is another way to have the mapping without the owner, here should be not owning item
      );
    });

    it("successfully cancel the item", async () => {
      await this.marketplace.cancelListing(this.nft.address, firstTokenId, {
        from: minter,
      });
    });
  });

  describe("Updating Item Price", () => {
    beforeEach(async () => {
      await this.nft.setApprovalForAll(this.marketplace.address, true, {
        from: minter,
      });
      await this.marketplace.listItem(
        this.nft.address,
        firstTokenId,
        "1",
        ZERO_ADDRESS,
        pricePerItem,
        "0",
        { from: minter }
      );
    });

    it("reverts when item is not listed", async () => {
      await expectRevert(
        this.marketplace.updateListing(
          this.nft.address,
          secondTokenId,
          ZERO_ADDRESS,
          newPrice,
          { from: owner }
        ),
        "not listed item"
      );
    });

    it("reverts when not owning the item", async () => {
      await expectRevert(
        this.marketplace.updateListing(
          this.nft.address,
          firstTokenId,
          ZERO_ADDRESS,
          newPrice,
          { from: owner }
        ),
        "not listed item" // TODO: investigate if there is another way to have the mapping without the owner, here should be not owning item
      );
    });

    it("successfully update the item", async () => {
      await this.marketplace.updateListing(
        this.nft.address,
        firstTokenId,
        ZERO_ADDRESS,
        newPrice,
        { from: minter }
      );
    });
  });

  describe("Buying Item", () => {
    beforeEach(async () => {
      await this.nft.setApprovalForAll(this.marketplace.address, true, {
        from: minter,
      });
      await this.marketplace.listItem(
        this.nft.address,
        firstTokenId,
        "1",
        ZERO_ADDRESS,
        pricePerItem,
        "0",
        { from: minter }
      );
    });

    it("reverts when seller doesnt own the item", async () => {
      await this.nft.safeTransferFrom(minter, owner, firstTokenId, {
        from: minter,
      });
      await expectRevert(
        this.marketplace.buyItem(this.nft.address, firstTokenId, minter, {
          from: buyer,
          value: pricePerItem,
        }),
        "not owning item"
      );
    });

    it("reverts when buying before the scheduled time", async () => {
      await this.nft.setApprovalForAll(this.marketplace.address, true, {
        from: owner,
      });
      await this.marketplace.listItem(
        this.nft.address,
        secondTokenId,
        "1",
        ZERO_ADDRESS,
        pricePerItem,
        constants.MAX_UINT256,
        { from: owner }
      );
      await expectRevert(
        this.marketplace.buyItem(this.nft.address, secondTokenId, owner, {
          from: buyer,
          value: pricePerItem,
        }),
        "item not buyable"
      );
    });

    it("reverts when the amount is not enough", async () => {
      await expectRevert(
        this.marketplace.buyItem(this.nft.address, firstTokenId, minter, {
          from: buyer,
        }),
        "insufficient balance to buy"
      );
    });

    it("successfully purchase item", async () => {
      const feeBalanceTracker = await balance.tracker(
        "0xFC00FACE00000000000000000000000000000000",
        "ether"
      );
      const minterBalanceTracker = await balance.tracker(minter, "ether");
      const receipt = await this.marketplace.buyItem(
        this.nft.address,
        firstTokenId,
        minter,
        {
          from: buyer,
          value: pricePerItem,
        }
      );
      const cost = await getGasCosts(receipt);
      expect(await this.nft.ownerOf(firstTokenId)).to.be.equal(buyer);
      expect(await feeBalanceTracker.delta("ether")).to.be.bignumber.equal("0");
      expect(await minterBalanceTracker.delta("ether")).to.be.bignumber.equal(
        "1"
      );
    });
  });

  const getGasCosts = async (receipt) => {
    const tx = await web3.eth.getTransaction(receipt.tx);
    const gasPrice = new BN(tx.gasPrice);
    return gasPrice.mul(new BN(receipt.receipt.gasUsed));
  };
});
