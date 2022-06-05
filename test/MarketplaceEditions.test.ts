import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { utils } from "ethers";
import { expect } from "chai";
import { ethers } from "hardhat";
import {
  ERC20, Soundchain721,
  Soundchain721__factory,
  // SoundchainMarketplace,
  // SoundchainMarketplace__factory,
  SoundchainMarketplaceEditions,
  SoundchainMarketplaceEditions__factory,
  Soundchain721Editions,
  Soundchain721Editions__factory
} from "../typechain-types";

describe("marketplace", () => {
  const platformFee: any = "250"; // marketplace platform fee: 2.5%
  const pricePerItem = "1000000000000000000";
  const OGUNPricePerItem = "1000000000000000000";
  const initialOgunBalance = "1000000000000000000000";
  const tokenUri = "ipfs";
  const rewardRate = "1000"; // reward rate: 10%
  const rewardLimit = "1000000000000000000000"; // reward rate: 10%

  let owner: SignerWithAddress,
    safeMinter: SignerWithAddress,
    buyer: SignerWithAddress,
    nft: Soundchain721,
    nftEditions: Soundchain721Editions,
    feeAddress: SignerWithAddress,
    OGUN: ERC20,
    marketplace: SoundchainMarketplaceEditions;

  beforeEach(async () => {
    [owner, safeMinter, buyer, feeAddress] = await ethers.getSigners();

    const SoundchainCollectible: Soundchain721__factory =
      await ethers.getContractFactory("Soundchain721");
    nft = await SoundchainCollectible.deploy();

    const SoundchainCollectibleEditions: Soundchain721Editions__factory =
      await ethers.getContractFactory("Soundchain721Editions");
    nftEditions = await SoundchainCollectibleEditions.deploy();

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

    await OGUN.transfer(buyer.address, initialOgunBalance);

    await OGUN.transfer(marketplace.address, pricePerItem);
  });

  describe("Editions", () => {
    beforeEach(async () => {
      // keccak256(creatorAddress + ID from Backend)
      const editionId = utils.hashMessage(nftEditions.address + "1");
      const editionNumber = 1;

      await nftEditions.createEdition(50n, editionId);
      await nftEditions.safeMint(safeMinter.address, tokenUri, 10, editionNumber);
      await nftEditions.safeMint(safeMinter.address, tokenUri, 10, editionNumber);

      await nftEditions.connect(safeMinter).setApprovalForAll(marketplace.address, true);
      await OGUN.connect(buyer).approve(marketplace.address, initialOgunBalance);

      nft.connect(safeMinter).setApprovalForAll(marketplace.address, true);
    });

    it("should create an edition with NFTs", async () => {
      const editionId = utils.hashMessage(nftEditions.address + "1");
      await nftEditions
        .connect(safeMinter)
        .createEditionWithNFTs(50n, editionId, safeMinter.address, tokenUri, 10);

      const tokenIdList = await nftEditions.getTokenIdsOfEdition(2);
      expect(tokenIdList.length).to.be.equal(50);
    });

    it("should revert in case of overflow max edition qty", async () => {
      const editionId = utils.hashMessage(nftEditions.address + "2");
      const editionNumber = 2;

      await nftEditions.createEdition(2n, editionId);
      await nftEditions.safeMint(safeMinter.address, tokenUri, 10, editionNumber);
      await nftEditions.safeMint(safeMinter.address, tokenUri, 10, editionNumber);

      await expect(
        nftEditions.safeMint(safeMinter.address, tokenUri, 10, editionNumber)
      ).to.be.revertedWith("This edition is already full");

      const editionId2 = utils.hashMessage(nftEditions.address + "3");
      const editionNumber2 = 3;

      await nftEditions
        .connect(safeMinter)
        .createEditionWithNFTs(50n, editionId2, safeMinter.address, tokenUri, 10);

        await expect(
          nftEditions.safeMint(safeMinter.address, tokenUri, 10, editionNumber2)
        ).to.be.revertedWith("This edition is already full");
    });

    it("should list an edition", async () => {
      const editionNumber = 1;
      await marketplace
        .connect(safeMinter)
        .listEdition(nftEditions.address, editionNumber, pricePerItem, OGUNPricePerItem, true, true, "0");
    });

    it("should create an edition with NFTs, list it and sell it", async () => {
      //Create edition with some NFTs
      const editionId = utils.hashMessage(nftEditions.address + "2");
      await nftEditions
        .connect(safeMinter)
        .createEditionWithNFTs(5n, editionId, safeMinter.address, tokenUri, 10);

      //List edition
      const editionNumber = 2;
      await marketplace
        .connect(safeMinter)
        .listEdition(nftEditions.address, editionNumber, pricePerItem, OGUNPricePerItem, true, true, "0");

      //Sell edition
      await marketplace
            .connect(buyer)
            .buyItem(nftEditions.address, "2", safeMinter.address, true);
    });

  });

});
