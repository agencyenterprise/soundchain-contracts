import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { expect } from "chai";
import { ethers } from "hardhat";
import {
  ERC20,
  Soundchain721Editions,
  Soundchain721Editions__factory,
  SoundchainMarketplaceEditions,
  SoundchainMarketplaceEditions__factory,
} from "../typechain";

describe("marketplace", () => {
  const firstTokenId = "0";
  const secondTokenId = "1";
  const overPricedTokenId = "2";
  const platformFee: any = "250"; // marketplace platform fee: 2.5%
  const pricePerItem = "1000000000000000000";
  const OGUNPricePerItem = "1000000000000000000";
  const OGUNOverPricePerItem = "15000000000000000000000"; //15k OGUN
  const newPrice = "500000000000000000";
  const newOGUNPrice = "500000000000000000";
  const tokenUri = "ipfs://QmWbSP1wbBXt2DidjDMZxS2kkt47ip4LRHphCmSXwXz5Cv";
  const rewardRate = "1000"; // reward rate: 10%
  const rewardLimit = "1000000000000000000000"; // reward rate: 10%
  const initialOgunBalance = "1000000000000000000000";

  let owner: SignerWithAddress,
    safeMinter: SignerWithAddress,
    buyer: SignerWithAddress,
    buyer2: SignerWithAddress,
    overPriceBuyer: SignerWithAddress,
    nft: Soundchain721Editions,
    feeAddress: SignerWithAddress,
    OGUN: ERC20,
    marketplace: SoundchainMarketplaceEditions;

  beforeEach(async () => {
    [owner, safeMinter, buyer, feeAddress, buyer2, overPriceBuyer] =
      await ethers.getSigners();

    const SoundchainCollectible: Soundchain721Editions__factory =
      await ethers.getContractFactory("Soundchain721Editions");
    nft = await SoundchainCollectible.deploy("contractUri");

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
    await OGUN.transfer(overPriceBuyer.address, OGUNOverPricePerItem);

    await OGUN.transfer(marketplace.address, pricePerItem);
  });

  describe("list item", () => {
    it("reverts when not owning NFT", async () => {
      expect(
        marketplace.listItem(
          nft.address,
          firstTokenId,
          "1",
          pricePerItem,
          OGUNPricePerItem,
          true,
          true,
          "0"
        )
      ).to.be.revertedWith("not owning item");
    });

    it("reverts when not approved", async () => {
      expect(
        marketplace
          .connect(safeMinter)
          .listItem(
            nft.address,
            firstTokenId,
            "1",
            pricePerItem,
            OGUNPricePerItem,
            true,
            true,
            "0"
          )
      ).to.be.revertedWith("item not approved");
    });

    it("reverts when not adding at least one token as way of payment", async () => {
      await nft
        .connect(safeMinter)
        .setApprovalForAll(marketplace.address, true);
      await expect(
        marketplace
          .connect(safeMinter)
          .listItem(
            nft.address,
            firstTokenId,
            "1",
            pricePerItem,
            OGUNPricePerItem,
            false,
            false,
            "0"
          )
      ).to.be.revertedWith("item should have a way of payment");
    });

    it("successfully lists item", async () => {
      await nft
        .connect(safeMinter)
        .setApprovalForAll(marketplace.address, true);
      await marketplace
        .connect(safeMinter)
        .listItem(
          nft.address,
          firstTokenId,
          "1",
          pricePerItem,
          OGUNPricePerItem,
          true,
          true,
          "0"
        );
    });
  });

  describe("cancel listing", () => {
    beforeEach(async () => {
      await nft
        .connect(safeMinter)
        .setApprovalForAll(marketplace.address, true);
      await marketplace
        .connect(safeMinter)
        .listItem(
          nft.address,
          firstTokenId,
          "1",
          pricePerItem,
          OGUNPricePerItem,
          true,
          true,
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
        .listItem(
          nft.address,
          firstTokenId,
          "1",
          pricePerItem,
          OGUNPricePerItem,
          true,
          true,
          "0"
        );
    });

    it("reverts when item is not listed", async () => {
      await expect(
        marketplace.updateListing(
          nft.address,
          secondTokenId,
          newPrice,
          newOGUNPrice,
          true,
          true,
          "100"
        )
      ).to.be.revertedWith("not listed item");
    });

    it("reverts when not owning the item", async () => {
      await expect(
        marketplace.updateListing(
          nft.address,
          firstTokenId,
          newPrice,
          newOGUNPrice,
          true,
          true,
          "100"
        )
      ).to.be.revertedWith("not listed item"); // TODO: investigate if there is another way to have the mapping without the owner, here should be not owning item
    });

    it("reverts when not adding at least one token as way of payment", async () => {
      await expect(
        marketplace
          .connect(safeMinter)
          .updateListing(
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
        .updateListing(
          nft.address,
          firstTokenId,
          newPrice,
          newOGUNPrice,
          true,
          true,
          "100"
        );
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
        .listItem(
          nft.address,
          firstTokenId,
          "1",
          pricePerItem,
          OGUNPricePerItem,
          true,
          true,
          "0"
        );

      await marketplace
        .connect(safeMinter)
        .listItem(
          nft.address,
          overPricedTokenId,
          "1",
          pricePerItem,
          OGUNOverPricePerItem,
          true,
          true,
          "0"
        );
    });

    it("reverts when seller doesn't own the item", async () => {
      await nft
        .connect(safeMinter)
        .transferFrom(safeMinter.address, owner.address, firstTokenId);
      await expect(
        marketplace.buyItem(
          nft.address,
          firstTokenId,
          safeMinter.address,
          false,
          {
            value: pricePerItem,
          }
        )
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
      expect(await OGUN.balanceOf(feeAddress.address)).to.be.equal(
        25000000000000000n
      );
      expect(await OGUN.balanceOf(safeMinter.address)).to.be.equal(
        1075000000000000000n
      ); // 975000000000000000 + rewards (100000000000000000)
      expect(await nft.ownerOf(firstTokenId)).to.be.equal(buyer.address);
    });

    it("successfully purchase item with OGUN - Over Max Reward Limit", async () => {
      await OGUN.transfer(marketplace.address, OGUNOverPricePerItem);

      await OGUN.connect(overPriceBuyer).approve(
        marketplace.address,
        OGUNOverPricePerItem
      );
      await marketplace
        .connect(overPriceBuyer)
        .buyItem(nft.address, overPricedTokenId, safeMinter.address, true);

      expect(await OGUN.balanceOf(feeAddress.address)).to.be.equal(
        375000000000000000000n
      ); // 2,5% of 15k Ogun - Not earning rewards
      expect(await OGUN.balanceOf(safeMinter.address)).to.be.equal(
        15625000000000000000000n
      ); // 14625 Ogun + rewards of 1k Ogun (10% of 15k Ogun is over the hardcap)
      expect(await OGUN.balanceOf(overPriceBuyer.address)).to.be.equal(
        1000000000000000000000n
      ); // just the rewards of 1k Ogun (10% of 15k Ogun is over the hardcap)
      expect(await nft.ownerOf(overPricedTokenId)).to.be.equal(
        overPriceBuyer.address
      );
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
        .listItem(
          nft.address,
          "2",
          "1",
          pricePerItem,
          OGUNPricePerItem,
          true,
          true,
          "0"
        );

      await marketplace
        .connect(buyer)
        .buyItem(nft.address, "2", safeMinter.address, false, {
          value: pricePerItem,
        });

      await marketplace
        .connect(buyer)
        .listItem(
          nft.address,
          "2",
          "1",
          pricePerItem,
          OGUNPricePerItem,
          true,
          true,
          "0"
        );
      await expect(() =>
        marketplace
          .connect(buyer2)
          .buyItem(nft.address, "2", buyer.address, false, {
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
        .listItem(
          nft.address,
          "2",
          "1",
          pricePerItem,
          OGUNPricePerItem,
          true,
          true,
          "0"
        );

      // Sell - safeMinter gets 877500000000000000 as an owner + 97500000000000000 for royalty fees
      // reward - safeMinter gets 10000000000000000 and buyer gets 10000000000000000
      await marketplace
        .connect(buyer)
        .buyItem(nft.address, "2", safeMinter.address, true);

      await OGUN.connect(buyer).approve(marketplace.address, OGUNPricePerItem);

      await marketplace
        .connect(buyer)
        .listItem(
          nft.address,
          "2",
          "1",
          pricePerItem,
          OGUNPricePerItem,
          true,
          true,
          "0"
        );

      // Sell - safeMinter gets 97500000000000000 for royalty fees
      // reward - buyer gets 10000000000000000 and buyer2 gets 10000000000000000
      await marketplace
        .connect(buyer2)
        .buyItem(nft.address, "2", buyer.address, true);

      expect(await OGUN.balanceOf(feeAddress.address)).to.be.equal(
        50000000000000000n
      );
      expect(await OGUN.balanceOf(buyer.address)).to.be.equal(
        1077500000000000000n
      ); // 877500000000000000 + rewards * 2 (200000000000000000) - Two actions here Buy and Sell
      expect(await OGUN.balanceOf(safeMinter.address)).to.be.equal(
        1172500000000000000n
      ); // 1072500000000000000 + rewards (100000000000000000)
      expect(await OGUN.balanceOf(buyer2.address)).to.be.equal(
        100000000000000000n
      ); // just rewards (100000000000000000)
    });
  });

  describe("Editions", () => {
    beforeEach(async () => {
      const editionNumber = 1;

      await nft.connect(safeMinter).createEdition(50n, safeMinter.address, 10);
      await nft
        .connect(safeMinter)
        .safeMintToEdition(safeMinter.address, tokenUri, editionNumber);
      await nft
        .connect(safeMinter)
        .safeMintToEdition(safeMinter.address, tokenUri, editionNumber);

      await nft
        .connect(safeMinter)
        .setApprovalForAll(marketplace.address, true);
      await OGUN.transfer(buyer.address, initialOgunBalance);
      await OGUN.connect(buyer).approve(
        marketplace.address,
        initialOgunBalance
      );

      nft.connect(safeMinter).setApprovalForAll(marketplace.address, true);
    });

    it("should create an edition with NFTs with big number", async () => {
      await nft
        .connect(safeMinter)
        .createEditionWithNFTs(150, safeMinter.address, tokenUri, 10);
      const tokenIdList = await nft.getTokenIdsOfEdition(2);
      expect(tokenIdList.length).to.be.equal(150);
      expect((await nft.editions(2)).owner).to.be.equal(safeMinter.address);
    });

    it("should create an edition with NFTs and burn nfts", async () => {
      const tx = await nft
        .connect(safeMinter)
        .createEditionWithNFTs(1, safeMinter.address, tokenUri, 10);
      const rc = await tx.wait();
      const event = rc.events.find((event) => event.event === "Transfer");
      const tokenId = event.args["tokenId"];
      await expect(nft.burn(tokenId))
        .to.emit(nft, "Transfer")
        .withArgs(
          safeMinter.address,
          "0x0000000000000000000000000000000000000000",
          tokenId
        );
    });

    it("should create an edition with NFTs and set royalty and token uri", async () => {
      const tx = await nft
        .connect(safeMinter)
        .createEditionWithNFTs(10n, safeMinter.address, tokenUri, 10);
      const rc = await tx.wait();
      const event = rc.events.find((event) => event.event === "Transfer");
      const tokenId = event.args["tokenId"];
      const [creatorAddress, royalties] = await nft.royaltyInfo(tokenId, 1000);
      expect(creatorAddress).to.be.equal(safeMinter.address);
      expect(royalties).to.be.equal("100");
      expect(await nft.tokenURI(tokenId)).to.be.equal(tokenUri);
    });

    it("should create an edition with NFTs and set token uri", async () => {
      const newTokenURI = "https://newTokenURI.com";
      const tx = await nft
        .connect(safeMinter)
        .createEditionWithNFTs(10n, safeMinter.address, newTokenURI, 10);
      const rc = await tx.wait();
      const event = rc.events.find((event) => event.event === "Transfer");
      const tokenId = event.args["tokenId"];

      expect(await nft.tokenURI(tokenId)).to.be.equal(newTokenURI);
    });

    it("should create an edition and mint after", async () => {
      await nft.connect(safeMinter).createEdition(500n, safeMinter.address, 10);

      await nft
        .connect(safeMinter)
        .safeMintToEditionQuantity(safeMinter.address, tokenUri, 2, 100);
      await nft
        .connect(safeMinter)
        .safeMintToEditionQuantity(safeMinter.address, tokenUri, 2, 100);
      await nft
        .connect(safeMinter)
        .safeMintToEditionQuantity(safeMinter.address, tokenUri, 2, 100);
      expect((await nft.getTokenIdsOfEdition(2)).length).to.be.equal(300);
    });

    it("should create an edition and revert if mints more than quantity", async () => {
      await nft.connect(safeMinter).createEdition(10n, safeMinter.address, 10);

      await expect(
        nft
          .connect(safeMinter)
          .safeMintToEditionQuantity(safeMinter.address, tokenUri, 2, 100)
      ).to.be.revertedWith("This edition is already full");
    });

    it("should create an edition and revert if other mints", async () => {
      await nft.connect(safeMinter).createEdition(10n, safeMinter.address, 10);

      await expect(
        nft
          .connect(buyer2)
          .safeMintToEditionQuantity(safeMinter.address, tokenUri, 2, 100)
      ).to.be.revertedWith("Not owner of edition");
    });

    it("should revert in case of overflow max edition qty", async () => {
      const editionNumber = 2;

      await nft.createEdition(2n, safeMinter.address, 10);
      await nft
        .connect(safeMinter)
        .safeMintToEdition(safeMinter.address, tokenUri, editionNumber);
      await nft
        .connect(safeMinter)
        .safeMintToEdition(safeMinter.address, tokenUri, editionNumber);

      await expect(
        nft.safeMintToEdition(safeMinter.address, tokenUri, editionNumber)
      ).to.be.revertedWith("This edition is already full");

      const editionNumber2 = 3;

      await nft
        .connect(safeMinter)
        .createEditionWithNFTs(50n, safeMinter.address, tokenUri, 10);

      await expect(
        nft.safeMintToEdition(safeMinter.address, tokenUri, editionNumber2)
      ).to.be.revertedWith("This edition is already full");
    });

    it("should list an edition", async () => {
      const editionNumber = 1;
      await expect(
        marketplace
          .connect(safeMinter)
          .listEdition(
            nft.address,
            editionNumber,
            pricePerItem,
            OGUNPricePerItem,
            true,
            true,
            "0"
          )
      )
        .to.emit(marketplace, "EditionListed")
        .withArgs(nft.address, editionNumber);

      expect(await marketplace.editionListings(nft.address, editionNumber)).to
        .be.true;
    });

    it("should cancel listing for an edition", async () => {
      const editionNumber = 1;
      await marketplace
        .connect(safeMinter)
        .listEdition(
          nft.address,
          editionNumber,
          pricePerItem,
          OGUNPricePerItem,
          true,
          true,
          "0"
        );
      expect(await marketplace.editionListings(nft.address, editionNumber)).to
        .be.true;

      await expect(
        marketplace
          .connect(safeMinter)
          .cancelEditionListing(nft.address, editionNumber)
      )
        .to.emit(marketplace, "EditionCanceled")
        .withArgs(nft.address, editionNumber);
    });

    it("should cancel listing for an edition with an NFT Sold", async () => {
      const tx = await nft
        .connect(safeMinter)
        .createEditionWithNFTs(5n, safeMinter.address, tokenUri, 10);

      const rc = await tx.wait();
      const event = rc.events.find((event) => event.event === "EditionCreated");

      const [retEditionQuantity, editionNumber] = event.args;

      await marketplace
        .connect(safeMinter)
        .listEdition(
          nft.address,
          editionNumber,
          pricePerItem,
          OGUNPricePerItem,
          true,
          true,
          "0"
        );
      expect(await marketplace.editionListings(nft.address, editionNumber)).to
        .be.true;

      await marketplace
        .connect(buyer)
        .buyItem(nft.address, 5, safeMinter.address, true);

      await expect(
        marketplace
          .connect(safeMinter)
          .cancelEditionListing(nft.address, editionNumber)
      )
        .to.emit(marketplace, "EditionCanceled")
        .withArgs(nft.address, editionNumber);
    });

    it("should create an edition with NFTs, list it and sell it", async () => {
      const tx = await nft
        .connect(safeMinter)
        .createEditionWithNFTs(5n, safeMinter.address, tokenUri, 10);

      const rc = await tx.wait();
      const event = rc.events.find((event) => event.event === "EditionCreated");

      const [retEditionQuantity, editionNumber] = event.args;

      await expect(
        marketplace
          .connect(safeMinter)
          .listEdition(
            nft.address,
            editionNumber.toString(),
            pricePerItem,
            OGUNPricePerItem,
            true,
            true,
            "0"
          )
      )
        .to.emit(marketplace, "EditionListed")
        .withArgs(nft.address, editionNumber);

      //Sell edition
      await marketplace
        .connect(buyer)
        .buyItem(nft.address, 5, safeMinter.address, true);
    });
    
  });
  describe('Batch Listing', () => {
    it('should validate empty tokenId list', async () => {
      expect(
        marketplace.connect(safeMinter)
        .listBatch(nft.address, [], pricePerItem, OGUNPricePerItem, true, true, "0")
      ).to.be.revertedWith('tokenIds is empty');
    })
    it('should validate empty tokenId list', async () => {
      const tx = await nft.connect(safeMinter).createEditionWithNFTs(50n, safeMinter.address, tokenUri, 10);
  
      const receipt = await tx.wait();
      const tokenIds = receipt.events.filter((event) => event.event === "Transfer").map((event) => event.args?.[2]);
  
      expect(
        marketplace.connect(safeMinter)
          .listBatch(nft.address, tokenIds, pricePerItem, OGUNPricePerItem, true, true, "0")
      ).to.be.revertedWith("item not approved");
    })
    it('should list a batch of tokenIds', async () => {
      await nft
        .connect(safeMinter)
        .setApprovalForAll(marketplace.address, true);

      const tx = await nft.connect(safeMinter).createEditionWithNFTs(50n, safeMinter.address, tokenUri, 10);
  
      const receipt = await tx.wait();
      const tokenIds = receipt.events.filter((event) => event.event === "Transfer").map((event) => event.args?.[2]);
  
      const mktTx = await marketplace.connect(safeMinter)
        .listBatch(nft.address, tokenIds, pricePerItem, OGUNPricePerItem, true, true, "0");
  
      const mktReceipt = await mktTx.wait();
  
      const itemListedEvents = mktReceipt.events.filter((event) => event.event === "ItemListed");
      const emittedIds = itemListedEvents.map((event) => event.args?.[2].toString());
  
      expect(itemListedEvents.length).to.equal(50);
      tokenIds.forEach((tokenId) => {
        expect(emittedIds).to.include(tokenId.toString());
      })
    })

    it('should not list the same tokens twice', async () => {
      await nft
        .connect(safeMinter)
        .setApprovalForAll(marketplace.address, true);

      const tx = await nft.connect(safeMinter).createEditionWithNFTs(50n, safeMinter.address, tokenUri, 10);
  
      const receipt = await tx.wait();
      const tokenIds = receipt.events.filter((event) => event.event === "Transfer").map((event) => event.args?.[2]);
  
      const mktTx = await marketplace.connect(safeMinter)
        .listBatch(nft.address, tokenIds, pricePerItem, OGUNPricePerItem, true, true, "0");
  
      const mktReceipt = await mktTx.wait();
  
      const itemListedEvents = mktReceipt.events.filter((event) => event.event === "ItemListed");
      const emittedIds = itemListedEvents.map((event) => event.args?.[2].toString());
  
      expect(itemListedEvents.length).to.equal(50);
      tokenIds.forEach((tokenId) => {
        expect(emittedIds).to.include(tokenId.toString());
      })

      const mktTx2 = await marketplace.connect(safeMinter)
      .listBatch(nft.address, tokenIds, pricePerItem, OGUNPricePerItem, true, true, "0");

    const mktReceipt2 = await mktTx2.wait();

    const itemListedEvents2 = mktReceipt2.events.filter((event) => event.event === "ItemListed");
    expect(itemListedEvents2.length).to.equal(0);
    })
  })
  describe('Batch Cancelling', () => {
    it('should validate empty tokenId list', async () => {
      expect(
        marketplace.connect(safeMinter)
        .cancelListingBatch(nft.address, [])
      ).to.be.revertedWith('tokenIds is empty');
    })
    it('should cancel a batch of tokenIds', async () => {
      await nft
        .connect(safeMinter)
        .setApprovalForAll(marketplace.address, true);

      const tx = await nft.connect(safeMinter).createEditionWithNFTs(50n, safeMinter.address, tokenUri, 10);
  
      const receipt = await tx.wait();
      const tokenIds = receipt.events.filter((event) => event.event === "Transfer").map((event) => event.args?.[2]);
  
      await marketplace.connect(safeMinter)
        .listBatch(nft.address, tokenIds, pricePerItem, OGUNPricePerItem, true, true, "0");

      const mktTx = await marketplace.connect(safeMinter)
        .cancelListingBatch(nft.address, tokenIds);
  
      const mktReceipt = await mktTx.wait();
  
      const itemListedEvents = mktReceipt.events.filter((event) => event.event === "ItemCanceled");
      const emittedIds = itemListedEvents.map((event) => event.args?.[2].toString());
  
      expect(itemListedEvents.length).to.equal(50);
      tokenIds.forEach((tokenId) => {
        expect(emittedIds).to.include(tokenId.toString());
      })
    })

    it('should only cancel listed tokens', async () => {
      await nft
        .connect(safeMinter)
        .setApprovalForAll(marketplace.address, true);

      const tx = await nft.connect(safeMinter).createEditionWithNFTs(50n, safeMinter.address, tokenUri, 10);
  
      const receipt = await tx.wait();
      const tokenIds = receipt.events.filter((event) => event.event === "Transfer").map((event) => event.args?.[2]);

      const mktTx = await marketplace.connect(safeMinter)
        .cancelListingBatch(nft.address, tokenIds);
  
      const mktReceipt = await mktTx.wait();
      const itemListedEvents = mktReceipt.events.filter((event) => event.event === "ItemCanceled");

      expect(itemListedEvents.length).to.equal(0);
    })
  })
});
