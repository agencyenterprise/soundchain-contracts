
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { expect } from "chai";
import { ethers, network } from "hardhat";
import {
  ERC20,
  MerkleClaimERC20
} from "../typechain";

describe("Airdrop", () => {
  let owner: SignerWithAddress,
    user1: SignerWithAddress,
    user2: SignerWithAddress,
    token: ERC20,
    airdrop: MerkleClaimERC20;

    const transfer200m = ethers.utils.parseEther("200000000");
    const merkleRoot = '0x751fc9b685a61589325ef440b6e87ab9366fa5d18fe6e48b291b930e7cb62fd7';

    beforeEach(async () => {
      await network.provider.send("hardhat_reset");
      [owner, user1, user2] = await ethers.getSigners();
      const tokenContract = await ethers.getContractFactory("SoundchainOGUN20");
      const AirDropContract = await ethers.getContractFactory("MerkleClaimERC20");
      token = await tokenContract.deploy();
      airdrop = await AirDropContract.deploy(token.address, merkleRoot);

      await token.transfer(airdrop.address, transfer200m);
    });

  describe("Airdrop contract", function () {
    describe("Airdrop claim", () => {
      it("should allow users to claim OGUN with their proof codes", async function () {
        let user1Balance = ethers.utils.formatEther(await token.connect(user1).balanceOf(user1.address));
        expect(user1Balance).to.eq('0.0');
        await airdrop.connect(user1).claim(user1.address, '1234559999999999945430', [
          "0x500a663bfb841b568457a9e8e5a1d8171982df51f6969d0c8829070ec6365e2f",
          "0xf8b06c8c95a5e79a787b1feebaff07578707b54a3bc3d221d3a1bd4d1f0b3be6"
        ])
        user1Balance = ethers.utils.formatEther(await token.connect(user1).balanceOf(user1.address));
        expect(user1Balance).to.eq('1234.55999999999994543');

        let user2Balance = ethers.utils.formatEther(await token.connect(user2).balanceOf(user2.address));
        expect(user2Balance).to.eq('0.0');
        await airdrop.connect(user2).claim(user2.address, '5000000000000000000000', [
          "0x3b37f20946d063f4baa3f3caed0a9f118c8e643319b93f2d7896407e339dc3e5",
          "0xf8b06c8c95a5e79a787b1feebaff07578707b54a3bc3d221d3a1bd4d1f0b3be6"
        ])
        user2Balance = ethers.utils.formatEther(await token.connect(user2).balanceOf(user2.address));
        expect(user2Balance).to.eq('5000.0');
      });
    });
  });
});
