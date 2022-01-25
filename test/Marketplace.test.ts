import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { expect } from "chai";
import { ethers } from "hardhat";
import {
  Soundchain721,
  Soundchain721__factory,
  SoundchainMarketplace,
  SoundchainMarketplace__factory,
} from "../typechain-types";

describe("marketplace", () => {
  const firstTokenId = "0";
  const secondTokenId = "1";
  const platformFee = "250"; // marketplace platform fee: 2.5%
  const pricePerItem = "1000000000000000000";
  const newPrice = "500000000000000000";
  const tokenUri = "ipfs";

  let owner: SignerWithAddress,
    safeMinter: SignerWithAddress,
    buyer: SignerWithAddress,
    buyer2: SignerWithAddress,
    nft: Soundchain721,
    feeAddress: SignerWithAddress,
    marketplace: SoundchainMarketplace;

  beforeEach(async () => {
    [owner, safeMinter, buyer, feeAddress, buyer2] = await ethers.getSigners();

    const SoundchainCollectible: Soundchain721__factory =
      await ethers.getContractFactory("Soundchain721");
    nft = await SoundchainCollectible.deploy();

    const MarketplaceFactory: SoundchainMarketplace__factory =
      await ethers.getContractFactory("SoundchainMarketplace");

    marketplace = await MarketplaceFactory.deploy(
      feeAddress.address,
      platformFee
    );

    await nft.safeMint(safeMinter.address, tokenUri, 10);
    await nft.safeMint(owner.address, tokenUri, 10);
    await nft.safeMint(safeMinter.address, tokenUri, 10);
  });

  describe("list item", () => {
    it("reverts when not owning NFT", async () => {
      expect(
        marketplace.listItem(nft.address, firstTokenId, "1", pricePerItem, "0")
      ).to.be.revertedWith("not owning item");
    });

    it("reverts when not approved", async () => {
      expect(
        marketplace
          .connect(safeMinter)
          .listItem(nft.address, firstTokenId, "1", pricePerItem, "0")
      ).to.be.revertedWith("item not approved");
    });

    it("successfully lists item", async () => {
      await nft
        .connect(safeMinter)
        .setApprovalForAll(marketplace.address, true);
      await marketplace
        .connect(safeMinter)
        .listItem(nft.address, firstTokenId, "1", pricePerItem, "0");
    });
  });

  describe("cancel listing", () => {
    beforeEach(async () => {
      await nft
        .connect(safeMinter)
        .setApprovalForAll(marketplace.address, true);
      await marketplace
        .connect(safeMinter)
        .listItem(nft.address, firstTokenId, "1", pricePerItem, "0");
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
        .connect(safeMinter)
        .cancelListing(nft.address, firstTokenId);
    });
  });

  describe("update listing", () => {
    beforeEach(async () => {
      await nft
        .connect(safeMinter)
        .setApprovalForAll(marketplace.address, true);
      await marketplace
        .connect(safeMinter)
        .listItem(nft.address, firstTokenId, "1", pricePerItem, "0");
    });

    it("reverts when item is not listed", async () => {
      await expect(
        marketplace.updateListing(nft.address, secondTokenId, newPrice, "100")
      ).to.be.revertedWith("not listed item");
    });

    it("reverts when not owning the item", async () => {
      await expect(
        marketplace.updateListing(nft.address, firstTokenId, newPrice, "100")
      ).to.be.revertedWith("not listed item"); // TODO: investigate if there is another way to have the mapping without the owner, here should be not owning item
    });

    it("successfully update the item", async () => {
      await marketplace
        .connect(safeMinter)
        .updateListing(nft.address, firstTokenId, newPrice, "100");
      const { pricePerItem, startingTime } = await marketplace.listings(
        nft.address,
        firstTokenId,
        safeMinter.address
      );
      expect(pricePerItem).to.be.eq(newPrice);
      expect(startingTime).to.be.eq("100");
    });
  });

  describe("buy item", () => {
    beforeEach(async () => {
      await nft
        .connect(safeMinter)
        .setApprovalForAll(marketplace.address, true);
      await marketplace
        .connect(safeMinter)
        .listItem(nft.address, firstTokenId, "1", pricePerItem, "0");
    });

    it("reverts when seller doesn't own the item", async () => {
      await nft
        .connect(safeMinter)
        .transferFrom(safeMinter.address, owner.address, firstTokenId);
      await expect(
        marketplace.buyItem(nft.address, firstTokenId, safeMinter.address, {
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
          .buyItem(nft.address, firstTokenId, safeMinter.address)
      ).to.be.revertedWith("insufficient balance to buy");
    });

    it("successfully purchase item", async () => {
      await expect(() =>
        marketplace
          .connect(buyer)
          .buyItem(nft.address, firstTokenId, safeMinter.address, {
            value: pricePerItem,
          })
      ).to.changeEtherBalances(
        [feeAddress, safeMinter],
        [25000000000000000n, 975000000000000000n]
      );

      expect(await nft.ownerOf(firstTokenId)).to.be.equal(buyer.address);
    });
  });

  describe("royalties", () => {
    beforeEach(async () => {
      nft.connect(safeMinter).setApprovalForAll(marketplace.address, true);
    });

    it("successfully transfer royalties", async () => {
      await nft
        .connect(safeMinter)
        .setApprovalForAll(marketplace.address, true);
      await nft.connect(buyer).setApprovalForAll(marketplace.address, true);

      await marketplace
        .connect(safeMinter)
        .listItem(nft.address, "2", "1", pricePerItem, "0");

      await marketplace
        .connect(buyer)
        .buyItem(nft.address, "2", safeMinter.address, {
          value: pricePerItem,
        });

      await marketplace
        .connect(buyer)
        .listItem(nft.address, "2", "1", pricePerItem, "0");
      await expect(() =>
        marketplace.connect(buyer2).buyItem(nft.address, "2", buyer.address, {
          value: pricePerItem,
        })
      ).to.changeEtherBalances(
        [feeAddress, buyer, safeMinter],
        [25000000000000000n, 877500000000000000n, 97500000000000000n]
      );
    });
  });
});
