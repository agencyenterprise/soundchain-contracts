import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { expect } from "chai";
import { ethers } from "hardhat";
import { utils } from "ethers";
import {
  ERC20,
  SoundchainMarketplaceEditions,
  SoundchainMarketplaceEditions__factory,
  Soundchain721Editions,
  Soundchain721Editions__factory
} from "../typechain-types";

describe("marketplace", () => {
  const firstTokenId = "0";
  const secondTokenId = "1";
  const platformFee: any = "250"; // marketplace platform fee: 2.5%
  const pricePerItem = "1000000000000000000";
  const OGUNPricePerItem = "1000000000000000000";
  const newPrice = "500000000000000000";
  const newOGUNPrice = "500000000000000000";
  const tokenUri = "ipfs";
  const rewardRate = "1000"; // reward rate: 10%
  const rewardLimit = "1000000000000000000000"; // reward rate: 10%
  const initialOgunBalance = "1000000000000000000000";

  let owner: SignerWithAddress,
    safeMinter: SignerWithAddress,
    buyer: SignerWithAddress,
    buyer2: SignerWithAddress,
    nft: Soundchain721Editions,
    feeAddress: SignerWithAddress,
    OGUN: ERC20,
    marketplace: SoundchainMarketplaceEditions;

  beforeEach(async () => {
    [owner, safeMinter, buyer, feeAddress, buyer2] = await ethers.getSigners();

    const SoundchainCollectible: Soundchain721Editions__factory =
      await ethers.getContractFactory("Soundchain721Editions");
    nft = await SoundchainCollectible.deploy();

    const MarketplaceFactory: SoundchainMarketplaceEditions__factory =
      await ethers.getContractFactory("SoundchainMarketplaceEditions");

    const token = await ethers.getContractFactory("SoundchainOGUN20");
    OGUN = await token.deploy();

    marketplace = await MarketplaceFactory.deploy(
      feeAddress.address,
      OGUN.address,
      platformFee,
      rewardRate,
      rewardLimit
    );

    await nft.safeMint(safeMinter.address, tokenUri, 10);
    await nft.safeMint(owner.address, tokenUri, 10);
    await nft.safeMint(safeMinter.address, tokenUri, 10);

    await OGUN.transfer(buyer2.address, pricePerItem);
    await OGUN.transfer(buyer.address, pricePerItem);

    await OGUN.transfer(marketplace.address, pricePerItem);
  });

  describe("list item", () => {
    it("reverts when not owning NFT", async () => {
      expect(
        marketplace.listItem(nft.address, firstTokenId, "1", pricePerItem, OGUNPricePerItem, true, true, "0")
      ).to.be.revertedWith("not owning item");
    });

    it("reverts when not approved", async () => {
      expect(
        marketplace
          .connect(safeMinter)
          .listItem(nft.address, firstTokenId, "1", pricePerItem, OGUNPricePerItem, true, true, "0")
      ).to.be.revertedWith("item not approved");
    });

    it("reverts when not adding at least one token as way of payment", async () => {
      await nft
        .connect(safeMinter)
        .setApprovalForAll(marketplace.address, true);
      await expect(
        marketplace.connect(safeMinter).listItem(
          nft.address,
          firstTokenId,
          "1",
          pricePerItem,
          OGUNPricePerItem,
          false,
          false,
          "0")
      ).to.be.revertedWith("item should have a way of payment");
    });

    it("successfully lists item", async () => {
      await nft
        .connect(safeMinter)
        .setApprovalForAll(marketplace.address, true);
      await marketplace
        .connect(safeMinter)
        .listItem(nft.address, firstTokenId, "1", pricePerItem, OGUNPricePerItem, true, true, "0");
    });
  });

  describe("cancel listing", () => {
    beforeEach(async () => {
      await nft
        .connect(safeMinter)
        .setApprovalForAll(marketplace.address, true);
      await marketplace
        .connect(safeMinter)
        .listItem(nft.address, firstTokenId, "1", pricePerItem, OGUNPricePerItem, true, true, "0");
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
        .listItem(nft.address, firstTokenId, "1", pricePerItem, OGUNPricePerItem, true, true, "0");
    });

    it("reverts when item is not listed", async () => {
      await expect(
        marketplace.updateListing(nft.address, secondTokenId, newPrice, newOGUNPrice, true, true, "100")
      ).to.be.revertedWith("not listed item");
    });

    it("reverts when not owning the item", async () => {
      await expect(
        marketplace.updateListing(nft.address, firstTokenId, newPrice, newOGUNPrice, true, true, "100")
      ).to.be.revertedWith("not listed item"); // TODO: investigate if there is another way to have the mapping without the owner, here should be not owning item
    });

    it("reverts when not adding at least one token as way of payment", async () => {
      await expect(
        marketplace.connect(safeMinter).updateListing(
          nft.address,
          firstTokenId,
          newPrice,
          newOGUNPrice,
          false,
          false,
          "100"
        )
      ).to.be.revertedWith("item should have a way of payment");
    });

    it("successfully update the item", async () => {
      await marketplace
        .connect(safeMinter)
        .updateListing(nft.address, firstTokenId, newPrice, newOGUNPrice, true, true, "100");
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
        .listItem(nft.address, firstTokenId, "1", pricePerItem, OGUNPricePerItem, true, true, "0");
    });

    it("reverts when seller doesn't own the item", async () => {
      await nft
        .connect(safeMinter)
        .transferFrom(safeMinter.address, owner.address, firstTokenId);
      await expect(
        marketplace.buyItem(nft.address, firstTokenId, safeMinter.address, false, {
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
        OGUNPricePerItem,
        true,
        true,
        2 ** 50
      );
      await expect(
        marketplace
          .connect(buyer)
          .buyItem(nft.address, secondTokenId, owner.address, false, {
            value: pricePerItem,
          })
      ).to.be.revertedWith("item not buyable");
    });

    it("reverts when the amount is not enough", async () => {
      await expect(
        marketplace
          .connect(buyer)
          .buyItem(nft.address, firstTokenId, safeMinter.address, false)
      ).to.be.revertedWith("insufficient balance to buy");
    });

    it("reverts when the amount of OGUN is not enough", async () => {
      await OGUN.connect(buyer).approve(marketplace.address, "90");
      await expect(
        marketplace
          .connect(buyer)
          .buyItem(nft.address, firstTokenId, safeMinter.address, true)
      ).to.be.revertedWith("insufficient balance to buy");
    });

    it("successfully purchase item with MATIC", async () => {
      await expect(() =>
        marketplace
          .connect(buyer)
          .buyItem(nft.address, firstTokenId, safeMinter.address, false, {
            value: pricePerItem,
          })
      ).to.changeEtherBalances(
        [feeAddress, safeMinter],
        [25000000000000000n, 975000000000000000n]
      );

      expect(await nft.ownerOf(firstTokenId)).to.be.equal(buyer.address);
    });


    it("successfully purchase item with OGUN", async () => {
      await OGUN.connect(buyer).approve(marketplace.address, OGUNPricePerItem);
      await marketplace
        .connect(buyer)
        .buyItem(nft.address, firstTokenId, safeMinter.address, true);
      expect(await OGUN.balanceOf(feeAddress.address)).to.be.equal(25000000000000000n);
      expect(await OGUN.balanceOf(safeMinter.address)).to.be.equal(1075000000000000000n); // 975000000000000000 + rewards (100000000000000000)
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
        .listItem(nft.address, "2", "1", pricePerItem, OGUNPricePerItem, true, true, "0");

      await marketplace
        .connect(buyer)
        .buyItem(nft.address, "2", safeMinter.address, false, {
          value: pricePerItem,
        });

      await marketplace
        .connect(buyer)
        .listItem(nft.address, "2", "1", pricePerItem, OGUNPricePerItem, true, true, "0");
      await expect(() =>
        marketplace.connect(buyer2).buyItem(nft.address, "2", buyer.address, false, {
          value: pricePerItem,
        })
      ).to.changeEtherBalances(
        [feeAddress, buyer, safeMinter],
        [25000000000000000n, 877500000000000000n, 97500000000000000n]
      );
    });

    it("successfully transfer royalties with OGUN", async () => {
      await OGUN.connect(buyer).approve(marketplace.address, OGUNPricePerItem);
      await OGUN.connect(buyer2).approve(marketplace.address, OGUNPricePerItem);

      await nft
        .connect(safeMinter)
        .setApprovalForAll(marketplace.address, true);
      await nft.connect(buyer).setApprovalForAll(marketplace.address, true);

      await marketplace
        .connect(safeMinter)
        .listItem(nft.address, "2", "1", pricePerItem, OGUNPricePerItem, true, true, "0");

      // Sell - safeMinter gets 877500000000000000 as an owner + 97500000000000000 for royalty fees
      // reward - safeMinter gets 10000000000000000 and buyer gets 10000000000000000
      await marketplace
        .connect(buyer)
        .buyItem(nft.address, "2", safeMinter.address, true);

      await OGUN.connect(buyer).approve(marketplace.address, OGUNPricePerItem);

      await marketplace
        .connect(buyer)
        .listItem(nft.address, "2", "1", pricePerItem, OGUNPricePerItem, true, true, "0");

      // Sell - safeMinter gets 97500000000000000 for royalty fees
      // reward - buyer gets 10000000000000000 and buyer2 gets 10000000000000000
      await marketplace.connect(buyer2).buyItem(nft.address, "2", buyer.address, true);

      expect(await OGUN.balanceOf(feeAddress.address)).to.be.equal(50000000000000000n);
      expect(await OGUN.balanceOf(buyer.address)).to.be.equal(1077500000000000000n); // 877500000000000000 + rewards * 2 (200000000000000000) - Two actions here Buy and Sell
      expect(await OGUN.balanceOf(safeMinter.address)).to.be.equal(1172500000000000000n); // 1072500000000000000 + rewards (100000000000000000)
      expect(await OGUN.balanceOf(buyer2.address)).to.be.equal(100000000000000000n); // just rewards (100000000000000000)
    });
  });

  describe("Editions", () => {
    beforeEach(async () => {
      const editionNumber = 1;

      await nft.createEdition(50n);
      await nft.safeMintToEdition(safeMinter.address, tokenUri, 10, editionNumber);
      await nft.safeMintToEdition(safeMinter.address, tokenUri, 10, editionNumber);

      await nft.connect(safeMinter).setApprovalForAll(marketplace.address, true);
      await OGUN.transfer(buyer.address, initialOgunBalance);
      await OGUN.connect(buyer).approve(marketplace.address, initialOgunBalance);

      nft.connect(safeMinter).setApprovalForAll(marketplace.address, true);
    });

    it("should create an edition with NFTs", async () => {
      await nft
        .connect(safeMinter)
        .createEditionWithNFTs(50n, safeMinter.address, tokenUri, 10);

      const tokenIdList = await nft.getTokenIdsOfEdition(2);
      expect(tokenIdList.length).to.be.equal(50);
    });

    it("should revert in case of overflow max edition qty", async () => {
      const editionNumber = 2;

      await nft.createEdition(2n);
      await nft.safeMintToEdition(safeMinter.address, tokenUri, 10, editionNumber);
      await nft.safeMintToEdition(safeMinter.address, tokenUri, 10, editionNumber);

      await expect(
        nft.safeMintToEdition(safeMinter.address, tokenUri, 10, editionNumber)
      ).to.be.revertedWith("This edition is already full");

      const editionNumber2 = 3;

      await nft
        .connect(safeMinter)
        .createEditionWithNFTs(50n, safeMinter.address, tokenUri, 10);

      await expect(
        nft.safeMintToEdition(safeMinter.address, tokenUri, 10, editionNumber2)
      ).to.be.revertedWith("This edition is already full");
    });

    it("should list an edition", async () => {
      const editionNumber = 1;
      await marketplace
        .connect(safeMinter)
        .listEdition(nft.address, editionNumber, pricePerItem, OGUNPricePerItem, true, true, "0");

      expect(await marketplace.editionListings(nft.address, editionNumber)).to.be.true;
    });

    it("should cancel listing for an edition", async () => {
      const editionNumber = 1;
      await marketplace
        .connect(safeMinter)
        .listEdition(nft.address, editionNumber, pricePerItem, OGUNPricePerItem, true, true, "0");
      expect(await marketplace.editionListings(nft.address, editionNumber)).to.be.true;
      
      await marketplace
        .connect(safeMinter)
        .cancelEditionListing(nft.address, editionNumber);
      expect(await marketplace.editionListings(nft.address, editionNumber)).to.be.false;
    });

    it("should cancel listing for an edition with an NFT Sold", async () => {
      const tx = await nft
        .connect(safeMinter)
        .createEditionWithNFTs(5n, safeMinter.address, tokenUri, 10);

      const rc = await tx.wait();
      const event = rc.events.find(event => event.event === 'EditionCreated');

      const [retEditionQuantity, editionNumber] = event.args;

      await marketplace
        .connect(safeMinter)
        .listEdition(nft.address, editionNumber, pricePerItem, OGUNPricePerItem, true, true, "0");
      expect(await marketplace.editionListings(nft.address, editionNumber)).to.be.true;
      
      await marketplace
        .connect(buyer)
        .buyItem(nft.address, 5, safeMinter.address, true);

      await marketplace
        .connect(safeMinter)
        .cancelEditionListing(nft.address, editionNumber);
      expect(await marketplace.editionListings(nft.address, editionNumber)).to.be.false;

    });

    it("should create an edition with NFTs, list it and sell it", async () => {

      const tx = await nft
        .connect(safeMinter)
        .createEditionWithNFTs(5n, safeMinter.address, tokenUri, 10);

      const rc = await tx.wait();
      const event = rc.events.find(event => event.event === 'EditionCreated');

      const [retEditionQuantity, editionNumber] = event.args;
      await marketplace
        .connect(safeMinter)
        .listEdition(nft.address, editionNumber.toString(), pricePerItem, OGUNPricePerItem, true, true, "0");

      //Sell edition
      await marketplace
        .connect(buyer)
        .buyItem(nft.address, 5, safeMinter.address, true);
    });

  });
});
