
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { expect } from "chai";
import { ContractReceipt, ContractTransaction } from "ethers";
import { ethers, network } from "hardhat";
import {
  LiquidityPoolRewards,
  LiquidityPoolRewards__factory,
  SoundchainOGUN20,
  SoundchainOGUN20__factory,
} from "../typechain";

describe("LP Staking", () => {
  let owner: SignerWithAddress,
    user1: SignerWithAddress,
    user2: SignerWithAddress,
    user3: SignerWithAddress,
    user4: SignerWithAddress,
    token: SoundchainOGUN20,
    stake: LiquidityPoolRewards;

  const transfer1k = ethers.utils.parseEther("1000");
  const transfer1m = ethers.utils.parseEther("1000000");
  const transfer500k = ethers.utils.parseEther("500000");
  const transfer20m = ethers.utils.parseEther("20000000");

  beforeEach(async () => {
    [owner, user1, user2, user3, user4] = await ethers.getSigners();
    const tokenContract: SoundchainOGUN20__factory =
      await ethers.getContractFactory("SoundchainOGUN20");
    const StakingContract: LiquidityPoolRewards__factory =
      await ethers.getContractFactory("LiquidityPoolRewards");
    token = await tokenContract.deploy();

    //LP token is going to be the same as the rewards token for the tests
    stake = await StakingContract.deploy(
      token.address,
      token.address,
      transfer20m
    );

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

      it("should not increase balance with rewards if there are no new blocks in the network", async function () {
        await stake.connect(user1).stake(transfer1m);
        const [stakedLP, rewards] = await stake.callStatic.getUpdatedBalanceOf(
          user1.address
        );
        expect(rewards).to.eq(0);
      });

      it("x1 - should increase rewards balance of user 1 by 5", async function () {
        await stake.connect(user1).stake(transfer1m);
        await stake.connect(user2).stake(transfer1m);
        const [stakedLP, rewards] = await stake.callStatic.getBalanceOf(
          user1.address
        );
        expect(ethers.utils.formatEther(rewards)).to.eq("5.0");
      });

      it("x23 - should increase rewards balance of user 1 by 115", async function () {
        await stake.connect(user1).stake(transfer1m);
        await network.provider.send("hardhat_mine", ["0x17"]);
        const [stakedLP, rewards] = await stake.callStatic.getUpdatedBalanceOf(
          user1.address
        );
        expect(ethers.utils.formatEther(rewards)).to.eq("115.0");
      });

      it("x23 - balance of lp tokens should be the same as initial stake", async function () {
        await stake.connect(user1).stake(transfer1m);
        await network.provider.send("hardhat_mine", ["0x17"]);
        const [stakedLP, rewards] = await stake.callStatic.getUpdatedBalanceOf(
          user1.address
        );
        expect(ethers.utils.formatEther(stakedLP)).to.eq("1000000.0");
      });

      it("x1000000 - balance of rewards should be 5000000", async function () {
        //+10 previous blocks from beforeEach function
        await stake.connect(user1).stake(transfer1m);
        await network.provider.send("hardhat_mine", ["0xf4240"]); // + 1000000 blocks
        const [stakedLP, rewards] = await stake.callStatic.getUpdatedBalanceOf(
          user1.address
        );
        expect(ethers.utils.formatEther(rewards)).to.eq("5000000.0"); // 999990 x 5
      });
    });

    describe("Stake calculation for more than 1 user ", () => {
      it("x1 - should increase rewards balance of user 2 by 2.5", async function () {
        await stake.connect(user1).stake(transfer1m);
        await stake.connect(user2).stake(transfer1m);
        await stake.connect(user3).stake(transfer1m);
        const [stakedLP, rewards] = await stake.callStatic.getBalanceOf(
          user2.address
        );
        expect(ethers.utils.formatEther(rewards)).to.eq("2.5");
      });

      it("x2 - should increase rewards balance of user 1 by 7.5", async function () {
        await stake.connect(user1).stake(transfer1m);
        await stake.connect(user2).stake(transfer1m);
        await stake.connect(user3).stake(transfer1m);
        const [stakedLP, rewards] = await stake.callStatic.getBalanceOf(
          user1.address
        );
        expect(ethers.utils.formatEther(rewards)).to.eq("7.5");
      });

      it("x3 - should increase rewards balance of user 1 by 9.166667", async function () {
        await stake.connect(user1).stake(transfer1m);
        await stake.connect(user2).stake(transfer1m); //user 1 = 5
        await stake.connect(user3).stake(transfer1m); // user 1 = 7.5, user 2 = 2.5
        await stake.connect(user4).stake(transfer1m); // user 1 = 9.166667, user 2 = ..., user 3 = ...
        const [stakedLP, rewards] = await stake.callStatic.getBalanceOf(
          user1.address
        );
        const etherNumber = ethers.utils.formatEther(rewards);
        expect(Number.parseFloat(etherNumber).toFixed(6)).to.eq("9.166667");
      });

      it("x3 - should increase rewards balance of user 2 by 4.166667", async function () {
        await stake.connect(user1).stake(transfer1m);
        await stake.connect(user2).stake(transfer1m);
        await stake.connect(user3).stake(transfer1m);
        await stake.connect(user4).stake(transfer1m);
        const [stakedLP, rewards] = await stake.callStatic.getBalanceOf(
          user2.address
        );
        const etherNumber = ethers.utils.formatEther(rewards);
        expect(Number.parseFloat(etherNumber).toFixed(6)).to.eq("4.166667");
      });

      it("x3 - should increase rewards balance of user 3 by 1.666667", async function () {
        await stake.connect(user1).stake(transfer1m);
        await stake.connect(user2).stake(transfer1m);
        await stake.connect(user3).stake(transfer1m);
        await stake.connect(user4).stake(transfer1m);
        const [stakedLP, rewards] = await stake.callStatic.getBalanceOf(
          user3.address
        );
        const etherNumber = ethers.utils.formatEther(rewards);
        expect(Number.parseFloat(etherNumber).toFixed(6)).to.eq("1.666667");
      });
    });

    describe("******** Testing RewardsCalculatedOf event *********", () => {
      it("x24 - should calculate and modify the balance and return new state", async function () {
        await stake.connect(user1).stake(transfer1m);
        await network.provider.send("hardhat_mine", ["0x17"]);
        const tx: ContractTransaction = await stake.getUpdatedBalanceOf(
          user1.address
        );
        const receipt: ContractReceipt = await tx.wait();
        const event = receipt.events?.filter((x) => {
          return x.event == "RewardsCalculatedOf";
        });
        expect(ethers.utils.formatEther(event[0].args?.rewards)).to.eq("120.0");
      });
    });

    describe("withdrawStake", () => {
      it("should transfer current balance to user 1 of 4899820", async function () {
        await stake.connect(user1).stake(transfer1m); // + 1 block
        await network.provider.send("hardhat_mine", ["0x2f9ae"]); // + 194,989 blocks
        const [user1StakedAmount] = await stake
          .connect(user1)
          .getBalanceOf(user1.address);
        await stake.connect(user1).withdrawStake(user1StakedAmount); // + 1 block
        await stake.connect(user1).withdrawRewards();
        const user1Balance = await token.balanceOf(user1.address);

        expect(ethers.utils.formatEther(user1Balance)).to.eq("1974955.0");
      });

      it("should throw error if withdrawStake amount is NOT greater than 0", async () => {
        await stake.connect(user1).stake(transfer1m);

        const _withdrawStake = stake.connect(user1).withdrawStake(0);
        const errorMessage = "Withdraw Stake: Amount must be greater than 0";

        await expect(_withdrawStake).to.be.revertedWith(errorMessage);
      });

      it("should throw error if staked amount is LOWER than withdraw amount", async () => {
        const oneThousand = ethers.utils.parseEther("1000");
        const twoThousand = ethers.utils.parseEther("2000");

        await stake.connect(user1).stake(oneThousand);

        const _withdrawStake = stake.connect(user1).withdrawStake(twoThousand);
        const errorMessage = "Withdraw amount is greater than staked amount";

        await expect(_withdrawStake).to.be.revertedWith(errorMessage);
      });

      it("should reduce all balances correctly", async () => {
        const stakeAmount = ethers.utils.parseUnits("1000", "ether");
        const withdrawAmount = ethers.utils.parseUnits("495", "ether");

        const stakeContract = stake.connect(user1);

        await stakeContract.stake(stakeAmount);
        await stakeContract.withdrawStake(withdrawAmount);

        const [user1StakedAmount] = await stakeContract.getBalanceOf(
          user1.address
        );

        const totalStaked = await stakeContract.totalLpStaked();
        const user1TotalStaked = stakeAmount.sub(withdrawAmount);

        expect(user1StakedAmount).to.eq(user1TotalStaked);
        expect(totalStaked).to.eq(user1TotalStaked);
      });
    });

    describe("withdrawRewards", () => {
      it("should throw an error if reward is 0", async () => {
        const stakeContract = stake.connect(user1);

        await stakeContract.stake(transfer1k);

        const _withdrawRewards = stakeContract.callStatic.withdrawRewards();

        const errorMessage = "No reward to be withdrawn";

        await expect(_withdrawRewards).to.be.revertedWith(errorMessage);
      });

      it("should reduce all balances correctly", async () => {
        const stakeContract = stake.connect(user1);

        await stakeContract.stake(transfer1k);

        const user1RewardBalance = await stake.callStatic.getReward(
          user1.address
        );
        const [, balanceBeforeWithdraw] =
          await stake.callStatic.getUpdatedBalanceOf(user1.address);

        expect(user1RewardBalance).to.eq(balanceBeforeWithdraw);

        await stakeContract.withdrawRewards();

        const [, balanceAfterWithdraw] =
          await stake.callStatic.getUpdatedBalanceOf(user1.address);

        expect(balanceAfterWithdraw).to.eq("0");
      });
    });
  });
});
