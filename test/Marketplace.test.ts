import { expect } from "chai";
import { ethers, upgrades } from "hardhat";

describe("Marketplace and Soundchain Token", () => {
  const firstTokenId = "0";
  const secondTokenId = "1";
  const platformFee = "25"; // marketplace platform fee: 2.5%
  const pricePerItem = "1000000000000000000";
  const newPrice = "500000000000000000";
  const tokenUri = "ipfs";

  let owner, minter, buyer, nft, feeAddress, marketplace;

  beforeEach(async () => {
    [owner, minter, buyer, feeAddress] = await ethers.getSigners();

    const SoundchainCollectible = await ethers.getContractFactory(
      "SoundchainCollectible"
    );
    nft = await SoundchainCollectible.deploy();

    const MarketplaceFactory = await ethers.getContractFactory(
      "SoundchainMarketplace"
    );
    marketplace = await upgrades.deployProxy(MarketplaceFactory, [
      feeAddress.address,
      platformFee,
    ]);

    await nft.safeMint(minter.address, tokenUri);
    await nft.safeMint(owner.address, tokenUri);
  });

  describe("Listing Item", () => {
    it("reverts when not owning NFT", async () => {
      expect(
        marketplace.listItem(nft.address, firstTokenId, "1", pricePerItem, "0")
      ).to.be.revertedWith("not owning item");
    });

    it("reverts when not approved", async () => {
      expect(
        marketplace
          .connect(minter)
          .listItem(nft.address, firstTokenId, "1", pricePerItem, "0")
      ).to.be.revertedWith("item not approved");
    });

    it("successfully lists item", async () => {
      await nft.connect(minter).setApprovalForAll(marketplace.address, true);
      await marketplace.connect(minter).listItem(
        nft.address,
        firstTokenId,
        "1",

        pricePerItem,
        "0"
      );
    });
  });

  describe("Canceling Item", () => {
    beforeEach(async () => {
      await nft.connect(minter).setApprovalForAll(marketplace.address, true);
      await marketplace.connect(minter).listItem(
        nft.address,
        firstTokenId,
        "1",

        pricePerItem,
        "0"
      );
    });

    it("reverts when item is not listed", async () => {
      await expect(
        marketplace.cancelListing(nft.address, secondTokenId)
      ).to.be.revertedWith("not listed item");
    });

    it("reverts when not owning the item", async () => {
      await expect(
        marketplace.cancelListing(nft.address, firstTokenId)
      ).to.be.revertedWith("not listed item"); // TODO: investigate if there is another way to have the mapping without the owner, here should be not owning item
    });

    it("successfully cancel the item", async () => {
      await marketplace
        .connect(minter)
        .cancelListing(nft.address, firstTokenId);
    });
  });

  describe("Updating Item Price", () => {
    beforeEach(async () => {
      await nft.connect(minter).setApprovalForAll(marketplace.address, true);
      await marketplace.connect(minter).listItem(
        nft.address,
        firstTokenId,
        "1",

        pricePerItem,
        "0"
      );
    });

    it("reverts when item is not listed", async () => {
      await expect(
        marketplace.updateListing(nft.address, secondTokenId, newPrice)
      ).to.be.revertedWith("not listed item");
    });

    it("reverts when not owning the item", async () => {
      await expect(
        marketplace.updateListing(nft.address, firstTokenId, newPrice)
      ).to.be.revertedWith("not listed item"); // TODO: investigate if there is another way to have the mapping without the owner, here should be not owning item
    });

    it("successfully update the item", async () => {
      await marketplace
        .connect(minter)
        .updateListing(nft.address, firstTokenId, newPrice);
    });
  });

  describe("Buying Item", () => {
    beforeEach(async () => {
      await nft.connect(minter).setApprovalForAll(marketplace.address, true);
      await marketplace.connect(minter).listItem(
        nft.address,
        firstTokenId,
        "1",

        pricePerItem,
        "0"
      );
    });

    it("reverts when seller doesn't own the item", async () => {
      await nft
        .connect(minter)
        .transferFrom(minter.address, owner.address, firstTokenId);
      await expect(
        marketplace.buyItem(nft.address, firstTokenId, minter.address, {
          value: pricePerItem,
        })
      ).to.be.revertedWith("not owning item");
    });

    it("reverts when buying before the scheduled time", async () => {
      await nft.setApprovalForAll(marketplace.address, true);
      await marketplace.listItem(
        nft.address,
        secondTokenId,
        "1",

        pricePerItem,
        2 ** 50
      );
      await expect(
        marketplace
          .connect(buyer)
          .buyItem(nft.address, secondTokenId, owner.address, {
            value: pricePerItem,
          })
      ).to.be.revertedWith("item not buyable");
    });

    it("reverts when the amount is not enough", async () => {
      await expect(
        marketplace
          .connect(buyer)
          .buyItem(nft.address, firstTokenId, minter.address)
      ).to.be.revertedWith("insufficient balance to buy");
    });

    it("successfully purchase item", async () => {
      await expect(() =>
        marketplace
          .connect(buyer)
          .buyItem(nft.address, firstTokenId, minter.address, {
            value: pricePerItem,
          })
      ).to.changeEtherBalances(
        [feeAddress, minter],
        [25000000000000000n, 975000000000000000n]
      );

      expect(await nft.ownerOf(firstTokenId)).to.be.equal(buyer.address);
    });
  });
});
