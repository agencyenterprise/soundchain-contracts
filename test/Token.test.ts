import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { expect } from "chai";
import { utils } from "ethers";
import { ethers } from "hardhat";
import { ERC20 } from "../typechain-types";

describe("OGUN", () => {
  let owner: SignerWithAddress,
    newWallet: SignerWithAddress,
    token: ERC20;

  describe("supply", function () {

    beforeEach(async () => {
      [owner, newWallet] = await ethers.getSigners();
      const OGUN = await ethers.getContractFactory("SoundchainOGUN20");
      token = await OGUN.deploy();

    });

    describe("contract supply", () => {
      it("successfully returns total supply", async function () {
        const totalSupply = await token.totalSupply();
        const expectedBalance = utils.parseEther("1000000000");
        expect(totalSupply).to.eq(expectedBalance);
      });
    }); 
    describe("token transactions by owner", () => {
      const transferAmount = ethers.utils.parseEther("1000000");
      const failedAmount = utils.parseEther("1000000001");

      it("sustracts token amount from senders balance", async function () {
        await token.transfer(newWallet.address, transferAmount);
        const expectedBalance = utils.parseEther("999000000");
        const balance = await token.balanceOf(owner.address);
        expect(balance).to.eq(expectedBalance);
      });

      it("adds token amount to destination wallet", async function () {
        await token.transfer(newWallet.address, transferAmount);
        const balance = await token.balanceOf(newWallet.address);
        expect(balance).to.eq(transferAmount);
      });

      it("reverts tranfer when transfer amount exceeds balance from new wallet", async function () {
        await expect(
          token.connect(newWallet)
          .transfer(owner.address, failedAmount)
        ).to.be.revertedWith("ERC20: transfer amount exceeds balance");
      });

      it("reverts tranfer when transfer amount exceeds balance of owner", async function () {
        await expect(
          token.transfer(newWallet.address, failedAmount)
        ).to.be.revertedWith("ERC20: transfer amount exceeds balance");
      });
    });

        //1- approve
        //3. connect to destination wallect 
        //4. transfer from
    describe("token transactions on behalf owner", () => {
      const transferAmount = utils.parseEther("1000000");
      
      it("approves wallet to transfer on behalf of another wallet", async function () {
        await token.approve(newWallet.address, transferAmount);
        const allowance = await token.allowance(owner.address, newWallet.address);
        expect(allowance).to.eq(transferAmount);
      });

      it("substracts tokens from onwer on transferFrom", async function () {
        const expectedBalance = utils.parseEther("999000000");
        await token.approve(newWallet.address, transferAmount);
        await token.connect(newWallet).transferFrom(owner.address, newWallet.address, transferAmount);
        const balance = await token.balanceOf(owner.address);
        expect(balance).to.eq(expectedBalance);
      });

      it("adds tokens to new wallet on transferFrom", async function () {
        await token.approve(newWallet.address, transferAmount);
        await token.connect(newWallet).transferFrom(owner.address, newWallet.address, transferAmount);
        const balance = await token.balanceOf(newWallet.address);
        expect(balance).to.eq(transferAmount);
      });

      it("reverts tranfer when transfer amount exceeds allowance", async function () {
        const failedAmount = utils.parseEther("1000001");
        await token.approve(newWallet.address, transferAmount);
        await expect(
          token.connect(newWallet)
          .transferFrom(owner.address, newWallet.address, failedAmount)
        ).to.be.revertedWith("ERC20: transfer amount exceeds allowance");
      });

    });
  });
});