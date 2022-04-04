
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { expect } from "chai";
import { ContractReceipt, ContractTransaction } from "ethers";
import { ethers, network } from "hardhat";
import {
  LiquidityPoolRewards,
  LiquidityPoolRewards__factory,
  SoundchainOGUN20,
  SoundchainOGUN20__factory
} from "../typechain-types";

describe("Staking", () => {
  let owner: SignerWithAddress,
    user1: SignerWithAddress, 
    user2: SignerWithAddress,
    user3: SignerWithAddress,
    user4: SignerWithAddress,
    token: SoundchainOGUN20,
    stake: LiquidityPoolRewards;

    const transfer1m = ethers.utils.parseEther("1000000");
    const transfer500k = ethers.utils.parseEther("500000");
    const transfer20m = ethers.utils.parseEther("20000000");
    
    beforeEach(async () => {
      [owner, user1, user2, user3, user4] = await ethers.getSigners();
      const tokenContract: SoundchainOGUN20__factory = await ethers.getContractFactory("SoundchainOGUN20");
      const StakingContract: LiquidityPoolRewards__factory = await ethers.getContractFactory("LiquidityPoolRewards");
      token = await tokenContract.deploy();
      //LP token is going to be the same as the rewards token for the tests
      stake = await StakingContract.deploy(token.address, token.address, transfer20m);

      await token.transfer(stake.address, transfer20m);
      await token.transfer(user1.address, transfer1m);
      await token.transfer(user2.address, transfer1m);
      await token.transfer(user3.address, transfer1m);
      await token.transfer(user4.address, transfer1m);

      await token.connect(user1).approve(stake.address, transfer1m);
      await token.connect(user2).approve(stake.address, transfer1m);
      await token.connect(user3).approve(stake.address, transfer1m);
      await token.connect(user4).approve(stake.address, transfer1m);
      //+10 new blocks in nectwork until now
    });
  describe("LP Stake contract", function () {

    describe("LP Stake calculation", () => {
      it("reverts if address doesn't exist in balances", async function () {
        await expect(
          stake.callStatic.getUpdatedBalanceOf(user1.address)
        ).to.be.revertedWith("address hasn't stake any tokens yet");
      });
      
      it("should no increace balance with rewards if there is no new blocks in network", async function () {
        await stake.connect(user1).stake(transfer1m);
        const [stakedLP, rewards] = await stake.callStatic.getUpdatedBalanceOf(user1.address);
        expect(rewards).to.eq(0);
      });

      it("x1 - should increase rewards balance of user 1 by 20", async function () {
        await stake.connect(user1).stake(transfer1m);
        await stake.connect(user2).stake(transfer1m);
        const [stakedLP, rewards] = await stake.callStatic.getLastCalculatedBalanceOf(user1.address);
        expect(ethers.utils.formatEther(rewards)).to.eq('20.0');
      });

      it("x23 - should increase rewards balance of user 1 by 460", async function () {
        await stake.connect(user1).stake(transfer1m);
        await network.provider.send('hardhat_mine', ['0x17']);
        const [stakedLP, rewards] = await stake.callStatic.getUpdatedBalanceOf(user1.address);
        expect(ethers.utils.formatEther(rewards)).to.eq('460.0');
      });

      it("x23 - balance of lp tokens should be the same as initial stake", async function () {
        await stake.connect(user1).stake(transfer1m);
        await network.provider.send('hardhat_mine', ['0x17']);
        const [stakedLP, rewards] = await stake.callStatic.getUpdatedBalanceOf(user1.address);
        expect(ethers.utils.formatEther(stakedLP)).to.eq('1000000.0');
      });

      it("x1000000 - balance of rewards should be 19997640", async function () {
        //+10 previous blocks from beforeEach function
        await stake.connect(user1).stake(transfer1m);
        await network.provider.send('hardhat_mine', ['0xf4240']); // + 1000000 blocks
        const [stakedLP, rewards] = await stake.callStatic.getUpdatedBalanceOf(user1.address);
        expect(ethers.utils.formatEther(rewards)).to.eq('19999800.0'); // 999990 x 20
      });
    });

    describe("Stake calculation for more than 1 user ", () => {
      it("x1 - should increase rewards balance of user 2 by 10", async function () {
        await stake.connect(user1).stake(transfer1m);
        await stake.connect(user2).stake(transfer1m);
        await stake.connect(user3).stake(transfer1m);
        const [stakedLP, rewards] = await stake.callStatic.getLastCalculatedBalanceOf(user2.address);
        expect(ethers.utils.formatEther(rewards)).to.eq('10.0');
      });
      
      it("x2 - should increase rewards balance of user 1 by 30", async function () {
        await stake.connect(user1).stake(transfer1m);
        await stake.connect(user2).stake(transfer1m);
        await stake.connect(user3).stake(transfer1m);
        const [stakedLP, rewards] = await stake.callStatic.getLastCalculatedBalanceOf(user1.address);
        expect(ethers.utils.formatEther(rewards)).to.eq('30.0');
      });

      it("x3 - should increase rewards balance of user 1 by 36.666666", async function () {
        await stake.connect(user1).stake(transfer1m);
        await stake.connect(user2).stake(transfer1m); //user 1 = 20
        await stake.connect(user3).stake(transfer1m); // user 1 = 30, user 2 =10
        await stake.connect(user4).stake(transfer1m); // user 1  = 36.666, user 2 = 16.6666, user 3= 6.6666
        const [stakedLP, rewards] = await stake.callStatic.getLastCalculatedBalanceOf(user1.address);
        const etherNumber = ethers.utils.formatEther(rewards);
        expect(Number.parseFloat(etherNumber).toFixed(6)).to.eq('36.666667');
      });

      it("x3 - should increase rewards balance of user 1 by 36.666666", async function () {
        await stake.connect(user1).stake(transfer1m);
        await stake.connect(user2).stake(transfer1m); //user 1 = 20
        await stake.connect(user3).stake(transfer1m); // user 1 = 30, user 2 =10
        await stake.connect(user4).stake(transfer1m); // user 1  = 36.666, user 2 = 16.6666, user 3= 6.6666
        const [stakedLP, rewards] = await stake.callStatic.getLastCalculatedBalanceOf(user1.address);
        const etherNumber = ethers.utils.formatEther(rewards);
        expect(Number.parseFloat(etherNumber).toFixed(6)).to.eq('36.666667');
      });

      it("x3 - should increase rewards balance of user 2 by 16.666667", async function () {
        await stake.connect(user1).stake(transfer1m);
        await stake.connect(user2).stake(transfer1m); 
        await stake.connect(user3).stake(transfer1m); 
        await stake.connect(user4).stake(transfer1m);
        const [stakedLP, rewards] = await stake.callStatic.getLastCalculatedBalanceOf(user2.address);
        const etherNumber = ethers.utils.formatEther(rewards);
        expect(Number.parseFloat(etherNumber).toFixed(6)).to.eq('16.666667');
      });

      it("x3 - should increase rewards balance of user 3 by 6.666667", async function () {
        await stake.connect(user1).stake(transfer1m);
        await stake.connect(user2).stake(transfer1m); 
        await stake.connect(user3).stake(transfer1m); 
        await stake.connect(user4).stake(transfer1m); 
        const [stakedLP, rewards] = await stake.callStatic.getLastCalculatedBalanceOf(user3.address);
        const etherNumber = ethers.utils.formatEther(rewards);
        expect(Number.parseFloat(etherNumber).toFixed(6)).to.eq('6.666667');
      });
    });

    describe("******** Testing RewardsCalculatedOf event *********", () => {
      it("x24 - should alculate and modify the balance and return new state", async function () {
        await stake.connect(user1).stake(transfer1m);
        await network.provider.send('hardhat_mine', ['0x17']);
        const tx: ContractTransaction = await stake.getUpdatedBalanceOf(user1.address);
        const receipt: ContractReceipt = await tx.wait();
        const event = receipt.events?.filter((x) => {return x.event == "RewardsCalculatedOf"});
        expect(ethers.utils.formatEther(event[0].args?.rewards)).to.eq('480.0');
      });
    });



    describe("Withdraw", () => {
        it("should transfer current balance to user", async function () {
          await stake.connect(user1).stake(transfer1m);
          await stake.connect(user1).withdraw();
          const user1Balance = await token.balanceOf(user1.address);
          expect(ethers.utils.formatEther(user1Balance)).to.eq('1000020.0');
        });

        it("should transfer current balance to user 1 of 4899820", async function () {
          await stake.connect(user1).stake(transfer1m);// + 1 block
          await network.provider.send('hardhat_mine', ['0x2f9ae']); // + 194,989 blocks
          await stake.connect(user1).withdraw();// + 1 block
          const user1Balance = await token.balanceOf(user1.address);
          const [stakedLP, rewards] = await stake.callStatic.getLastCalculatedBalanceOf(user1.address);
          expect(ethers.utils.formatEther(user1Balance)).to.eq('4899820.0');
        });
    });

  });
});

