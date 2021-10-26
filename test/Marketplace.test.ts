import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { expect } from "chai";
import { Contract } from "ethers";
import { ethers } from "hardhat";
import {
  SoundchainCollectible,
  SoundchainCollectible__factory,
  SoundchainMarketplace__factory,
} from "../typechain";

describe("Marketplace and Soundchain Token", () => {
  const firstTokenId = "0";
  const secondTokenId = "1";
  const platformFee = "25"; // marketplace platform fee: 2.5%
  const pricePerItem = "1000000000000000000";
  const newPrice = "500000000000000000";
  const tokenUri = "ipfs";

  let owner: SignerWithAddress,
    minter: SignerWithAddress,
    buyer: SignerWithAddress,
    buyer2: SignerWithAddress,
    nft: SoundchainCollectible,
    feeAddress: SignerWithAddress,
    marketplace: Contract;

  beforeEach(async () => {
    [owner, minter, buyer, feeAddress, buyer2] = await ethers.getSigners();

    const SoundchainCollectible: SoundchainCollectible__factory =
      await ethers.getContractFactory("SoundchainCollectible");
    nft = await SoundchainCollectible.deploy();

    const MarketplaceFactory: SoundchainMarketplace__factory =
      await ethers.getContractFactory("SoundchainMarketplace");

    marketplace = await MarketplaceFactory.deploy(
      feeAddress.address,
      platformFee
    );

    await nft.mint(minter.address, 1, tokenUri);
    await nft.mint(owner.address, 1, tokenUri);
    await nft.mint(minter.address, 1, tokenUri);
  });

  describe("Listing Item", () => {
    it("reverts when not owning NFT", async () => {
      expect(
        marketplace.listItem(
          nft.address,
          firstTokenId,
          "1",
          pricePerItem,
          "0",
          0
        )
      ).to.be.revertedWith("must hold enough nfts");
    });

    it("reverts when not approved", async () => {
      expect(
        marketplace
          .connect(minter)
          .listItem(nft.address, firstTokenId, "1", pricePerItem, "0", 0)
      ).to.be.revertedWith("item not approved");
    });

    it("successfully lists item", async () => {
      await nft.connect(minter).setApprovalForAll(marketplace.address, true);
      await marketplace
        .connect(minter)
        .listItem(nft.address, firstTokenId, "1", pricePerItem, "0", 0);
    });
  });

  describe("Canceling Item", () => {
    beforeEach(async () => {
      await nft.connect(minter).setApprovalForAll(marketplace.address, true);
      await marketplace
        .connect(minter)
        .listItem(nft.address, firstTokenId, "1", pricePerItem, "0", 0);
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
      await marketplace
        .connect(minter)
        .listItem(nft.address, firstTokenId, "1", pricePerItem, "0", 0);
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
      await marketplace
        .connect(minter)
        .listItem(nft.address, firstTokenId, "1", pricePerItem, "0", 0);
    });

    it("reverts when seller doesn't own the item", async () => {
      await nft
        .connect(minter)
        .safeTransferFrom(
          minter.address,
          owner.address,
          firstTokenId,
          1,
          "0x6d6168616d000000000000000000000000000000000000000000000000000000"
        );
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
        2 ** 50,
        0
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

      expect(await nft.balanceOf(buyer.address, firstTokenId)).to.be.equal(1);
    });
  });

  describe("Royalties", () => {
    beforeEach(async () => {
      nft.connect(minter).setApprovalForAll(marketplace.address, true);
    });

    it("reverts when royalty is greater than 100%", async () => {
      expect(
        marketplace
          .connect(minter)
          .listItem(nft.address, "2", "1", pricePerItem, "0", "20000")
      ).to.be.revertedWith("invalid royalty");
    });

    it("successfully set royalties on map", async () => {
      await marketplace
        .connect(minter)
        .listItem(nft.address, "2", "1", pricePerItem, "0", "100");

      expect(await marketplace.royalties(nft.address, "2")).to.be.eq(100);
    });

    it("successfully transfer royalties", async () => {
      await nft.connect(minter).setApprovalForAll(marketplace.address, true);
      await nft.connect(buyer).setApprovalForAll(marketplace.address, true);

      await marketplace
        .connect(minter)
        .listItem(nft.address, "2", "1", pricePerItem, "0", 1000);

      await marketplace
        .connect(buyer)
        .buyItem(nft.address, "2", minter.address, {
          value: pricePerItem,
        });

      await marketplace
        .connect(buyer)
        .listItem(nft.address, "2", "1", pricePerItem, "0", 0);
      await expect(() =>
        marketplace.connect(buyer2).buyItem(nft.address, "2", buyer.address, {
          value: pricePerItem,
        })
      ).to.changeEtherBalances(
        [feeAddress, buyer, minter],
        [25000000000000000n, 877500000000000000n, 97500000000000000n]
      );
    });
  });
});
