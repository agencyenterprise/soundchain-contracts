
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { expect } from "chai";
import { ContractReceipt, ContractTransaction } from "ethers";
import { ethers, network } from "hardhat";
import {
  ERC20,
  StakingRewards
} from "../typechain";

const PHASE_ONE_BLOCK = 1250000; 
const PHASE_TWO_BLOCK = 3125000 + PHASE_ONE_BLOCK; 
const PHASE_THREE_BLOCK = 10000000 + PHASE_TWO_BLOCK; 
const PHASE_FOUR_BLOCK = 15000000 + PHASE_THREE_BLOCK;

async function getCurrentBlock() {
  return parseInt(await network.provider.send('eth_blockNumber'), 16);
}

async function logCurrentBlock(msg = '') {
  const currentBlock = await getCurrentBlock()
  console.log('current block:', currentBlock, msg);
  return currentBlock;
}

async function getEvent(tx: ContractTransaction, eventName: String) {
  const receipt: ContractReceipt = await tx.wait();
  const event = receipt.events?.filter((x) => {return x.event == eventName});
  return event[0].args;
}

async function logRewardsCalculated(tx: ContractTransaction) {
  const eventArgs = await getEvent(tx, "RewardsCalculated")
  console.log('RewardsCalculated', eventArgs.map(ethers.utils.formatEther))
}

describe("Staking", () => {
  let owner: SignerWithAddress,
    user1: SignerWithAddress,
    user2: SignerWithAddress,
    user3: SignerWithAddress,
    user4: SignerWithAddress,
    token: ERC20,
    stake: StakingRewards;

    async function nextPhase(blocksToNext) {
      await stake.updateReward()
      // await logRewardsCalculated(await stake.updateReward())
      // await logCurrentBlock('after update reward');
    
      await network.provider.send('hardhat_mine', ["0x" + blocksToNext.toString(16)]); // +3
      // await logCurrentBlock('end of phase');
    }

    const transfer1k = ethers.utils.parseEther("1000");
    const transfer10k = ethers.utils.parseEther("10000");
    const transfer1m = ethers.utils.parseEther("1000000");
    const transfer5m = ethers.utils.parseEther("5000000");
    const transfer500k = ethers.utils.parseEther("500000");
    const transfer200m = ethers.utils.parseEther("200000000");
    const transfer300m = ethers.utils.parseEther("300000000");

    beforeEach(async () => {
      await network.provider.send("hardhat_reset");
      [owner, user1, user2, user3, user4] = await ethers.getSigners();
      const tokenContract = await ethers.getContractFactory("SoundchainOGUN20");
      const StakingContract = await ethers.getContractFactory("StakingRewards");
      token = await tokenContract.deploy();
      stake = await StakingContract.deploy(token.address, transfer200m);

      await token.transfer(stake.address, transfer200m);
      await token.transfer(user1.address, transfer1m);
      await token.transfer(user2.address, transfer5m);
      await token.transfer(user3.address, transfer1m);
      await token.transfer(user4.address, transfer1m);

      await token.connect(user1).approve(stake.address, transfer1m);
      await token.connect(user2).approve(stake.address, transfer5m);
      await token.connect(user3).approve(stake.address, transfer1m);
      await token.connect(user4).approve(stake.address, transfer1m);
      // +11 new blocks in network until now
    });

  describe("Stake contract", function () {
    describe("Staking rewards", () => {
      it("should be given proportionally to each user", async function () {
        // await logCurrentBlock('starting point');
        await stake.connect(user1).stake(ethers.utils.parseEther("83000")); // +1 block
        // await logCurrentBlock('user 1 staked');
        await stake.connect(user2).stake(ethers.utils.parseEther("1000000")); // +1 block
        // await logCurrentBlock('user 2 staked');
        await stake.connect(user3).stake(ethers.utils.parseEther("2000")); // +1 block
        // await logCurrentBlock('user 3 staked');

        const blocksToActivation = 122 - (await getCurrentBlock());

        await network.provider.send('hardhat_mine', ["0x" + blocksToActivation.toString(16)]);
        // await logCurrentBlock('activation point');

        await nextPhase(1250000)
        const user1Phase1Rewards = ethers.utils.formatEther(await stake.callStatic.getReward(user1.address));
        expect(user1Phase1Rewards).to.equal('3059909.058043133632')

        await nextPhase(3125000)
        const user1Phase2Rewards = ethers.utils.formatEther(await stake.callStatic.getReward(user1.address));
        expect(user1Phase2Rewards).to.equal('6884793.39165695852')

        await nextPhase(10000000)
        const user1Phase3Rewards = ethers.utils.formatEther(await stake.callStatic.getReward(user1.address));
        expect(user1Phase3Rewards).to.equal('10709678.337252350224')

        await nextPhase(15000000)
        const user1Phase4Rewards = ethers.utils.formatEther(await stake.callStatic.getReward(user1.address));
        expect(user1Phase4Rewards).to.equal('15299539.1704')

        // await logRewardsCalculated(await stake.updateReward())
        await stake.updateReward()
        const user1Rewards = (await stake.callStatic.getBalanceOf(user1.address)).map(ethers.utils.formatEther);
        const user2Rewards = (await stake.callStatic.getBalanceOf(user2.address)).map(ethers.utils.formatEther);
        const user3Rewards = (await stake.callStatic.getBalanceOf(user3.address)).map(ethers.utils.formatEther);
        // await logCurrentBlock('done');

        expect(user1Rewards[1]).to.equal('15299539.1704');
        expect(user2Rewards[1]).to.equal('184331797.235');
        expect(user3Rewards[1]).to.equal('368663.5944');

        const user1BalanceBefore = ethers.utils.formatEther(await token.connect(user1).balanceOf(user1.address))
        const user2BalanceBefore = ethers.utils.formatEther(await token.connect(user2).balanceOf(user2.address))
        const user3BalanceBefore = ethers.utils.formatEther(await token.connect(user3).balanceOf(user3.address))

        expect(user1BalanceBefore).to.equal('917000.0')
        expect(user2BalanceBefore).to.equal('4000000.0')
        expect(user3BalanceBefore).to.equal('998000.0')

        await stake.connect(user1).withdraw();
        await stake.connect(user2).withdraw();
        await stake.connect(user3).withdraw();

        const user1BalanceAfter = ethers.utils.formatEther(await token.connect(user1).balanceOf(user1.address))
        const user2BalanceAfter = ethers.utils.formatEther(await token.connect(user2).balanceOf(user2.address))
        const user3BalanceAfter = ethers.utils.formatEther(await token.connect(user3).balanceOf(user3.address))

        expect(user1BalanceAfter).to.equal('16299539.1704')
        expect(user2BalanceAfter).to.equal('189331797.235')
        expect(user3BalanceAfter).to.equal('1368663.5944')

      });

      it("should return the user reward as ZERO with no staked tokens", async function () {
        const reward = await stake.callStatic.getReward(user1.address);
        const etherNumber = ethers.utils.formatEther(reward);
        expect(etherNumber).to.eq("0.0");
      });

      it("should allow users to stake and withdraw multiple times", async function () {
        const blocksToMove = 122 - (await getCurrentBlock());
        await network.provider.send('hardhat_mine', ["0x" + blocksToMove.toString(16)]);
        await stake.connect(user1).stake(transfer10k);
        await network.provider.send('hardhat_mine', ["0x9"]);
        await stake.connect(user1).withdraw();
        await network.provider.send('hardhat_mine', ["0x9"]);
        await stake.connect(user1).stake(transfer10k);
        await network.provider.send('hardhat_mine', ["0x9"]);
        await stake.connect(user1).withdraw();
        await network.provider.send('hardhat_mine', ["0x9"]);
        await stake.connect(user1).stake(transfer10k);
        await network.provider.send('hardhat_mine', ["0x9"]);
        await stake.connect(user1).withdraw();
      });
    });

    describe("Stake calculation for different phases with just 1 user", () => {
      it("reverts if address doesn't exist in balances", async function () {
        await expect(
          stake.callStatic.getUpdatedBalanceOf(user1.address)
        ).to.be.revertedWith("address hasn't stake any tokens yet");
      });

      it("should not increase balance with rewards if there are no new blocks in network", async function () {
        const blocksToMove = 122 - (await getCurrentBlock());
        await network.provider.send('hardhat_mine', ["0x" + blocksToMove.toString(16)]);
        await stake.connect(user1).stake(transfer1m);
        const [,balance] = await stake.callStatic.getUpdatedBalanceOf(user1.address);
        expect(ethers.utils.formatEther(balance)).to.eq('0.0');
      });

      it("x1 - should increase balance of user 1 (by 32.0 phase 1)", async function () {
        let blocksToMove = 122 - (await getCurrentBlock());
        await network.provider.send('hardhat_mine', ["0x" + blocksToMove.toString(16)]);
        await stake.connect(user1).stake(transfer1m);
        blocksToMove = 1;
        await network.provider.send('hardhat_mine', ["0x" + blocksToMove.toString(16)]);
        const [_, balance] = await stake.callStatic.getUpdatedBalanceOf(user1.address);
        expect(ethers.utils.formatEther(balance)).to.eq('32.0');
      });

      it("x23 - should increase balance of user 1 (by 32.0 x 23 phase 1)", async function () {
        let blocksToMove = 122 - (await getCurrentBlock());
        await network.provider.send('hardhat_mine', ["0x" + blocksToMove.toString(16)]);
        await stake.connect(user1).stake(transfer1m);
        blocksToMove = 23;
        await network.provider.send('hardhat_mine', ["0x" + blocksToMove.toString(16)]);
        const [_, balance] = await stake.callStatic.getUpdatedBalanceOf(user1.address);
        expect(ethers.utils.formatEther(balance)).to.eq('736.0');
      });

      it("x1 - should increase balance of user 1 (by 16.0 phase 2)", async function () {
        let blocksToMove = PHASE_ONE_BLOCK + 122 - (await getCurrentBlock());
        await network.provider.send('hardhat_mine', ["0x" + blocksToMove.toString(16)]);
        await stake.connect(user1).stake(transfer1m);
        await network.provider.send('hardhat_mine', ["0x1"]);
        const [_, balance] = await stake.callStatic.getUpdatedBalanceOf(user1.address);
        expect(ethers.utils.formatEther(balance)).to.eq('16.0');
      });

      it("x343 - should increase balance of user 1 (by 16.0 x 343 phase 2)", async function () {
        let blocksToMove = PHASE_ONE_BLOCK + 122 - (await getCurrentBlock());
        await network.provider.send('hardhat_mine', ["0x" + blocksToMove.toString(16)]);
        await stake.connect(user1).stake(transfer1m);
        blocksToMove = 343;
        await network.provider.send('hardhat_mine', ["0x" + blocksToMove.toString(16)]);
        const [_, balance] = await stake.callStatic.getUpdatedBalanceOf(user1.address);
        expect(ethers.utils.formatEther(balance)).to.eq('5488.0');
      });

      it("x1 - should increase balance of user 1 (by 5.0 phase 3)", async function () {
        let blocksToMove = PHASE_TWO_BLOCK + 1250000 + 122 - (await getCurrentBlock());
        await network.provider.send('hardhat_mine', ["0x" + blocksToMove.toString(16)]);
        await stake.connect(user1).stake(transfer1m);
        await network.provider.send('hardhat_mine', ["0x1"]);
        const [_, balance] = await stake.callStatic.getUpdatedBalanceOf(user1.address);
        expect(ethers.utils.formatEther(balance)).to.eq('5.0');
      });

      it("x71 - should increase balance of user 1 (by 5.0 x 71 phase 3)", async function () {
        let blocksToMove = PHASE_TWO_BLOCK + 122 - (await getCurrentBlock());
        await network.provider.send('hardhat_mine', ["0x" + blocksToMove.toString(16)]);
        await stake.connect(user1).stake(transfer1m);
        blocksToMove = 71;
        await network.provider.send('hardhat_mine', ["0x" + blocksToMove.toString(16)]);
        const [_, balance] = await stake.callStatic.getUpdatedBalanceOf(user1.address);
        expect(ethers.utils.formatEther(balance)).to.eq('355.0');
      });

      it("x1 - should increase balance of user 1 (by 4 phase 4)", async function () {
        let blocksToMove = PHASE_THREE_BLOCK + 1250000 + 122 - (await getCurrentBlock());
        await network.provider.send('hardhat_mine', ["0x" + blocksToMove.toString(16)]);
        await stake.connect(user1).stake(transfer1m);
        await network.provider.send('hardhat_mine', ["0x1"]);
        const [_, balance] = await stake.callStatic.getUpdatedBalanceOf(user1.address);
        expect(ethers.utils.formatEther(balance)).to.eq('4.0');
      });

      it("x51 - should increase balance of user 1 (by 4 x 51 phase 4)", async function () {
        let blocksToMove = PHASE_THREE_BLOCK + 122 - (await getCurrentBlock());
        await network.provider.send('hardhat_mine', ["0x" + blocksToMove.toString(16)]);
        await stake.connect(user1).stake(transfer1m);
        blocksToMove = 51;
        await network.provider.send('hardhat_mine', ["0x" + blocksToMove.toString(16)]);
        const [_, balance] = await stake.callStatic.getUpdatedBalanceOf(user1.address);
        expect(ethers.utils.formatEther(balance)).to.eq('204.0');
      });

      describe("Testing RewardsCalculatedOf event ", () => {
        it("x24 - should calculate and modify the balance and return new state", async function () {
          let blocksToMove = 122 - (await getCurrentBlock());
          await network.provider.send('hardhat_mine', ["0x" + blocksToMove.toString(16)]);
          await stake.connect(user1).stake(transfer1m);
          await network.provider.send('hardhat_mine', ['0x17']);
          const tx: ContractTransaction = await stake.getUpdatedBalanceOf(user1.address);
          const receipt: ContractReceipt = await tx.wait();
          const event = receipt.events?.filter((x) => {return x.event == "RewardsCalculatedOf"});
          expect(ethers.utils.formatEther(event[0].args?.[1])).to.eq('768.0');
        });
      });

      describe("Stake calculation between phases", () => {
        it("should calculate balance for previous and current phase (Phase 1 - 1 block and Phase 2 - 1 block)", async function () {
          let blocksToMove = (PHASE_ONE_BLOCK - 2) + 122 - (await getCurrentBlock());
          await network.provider.send('hardhat_mine', ["0x" + blocksToMove.toString(16)]);
          await stake.connect(user1).stake(transfer1m);
          await network.provider.send("evm_mine");
          await network.provider.send("evm_mine");
          const [_, balance] = await stake.callStatic.getUpdatedBalanceOf(user1.address); // callStatic doesn't create blocks
          expect(ethers.utils.formatEther(balance)).to.eq('48.0');
        });

        it("should calculate balance for previous and current phase (Phase 2 - 1 block and Phase 3 - 1 block)", async function () {
          let blocksToMove = (PHASE_TWO_BLOCK - 2) + 122 - (await getCurrentBlock());
          await network.provider.send('hardhat_mine', ["0x" + blocksToMove.toString(16)]);
          await stake.connect(user1).stake(transfer1m);
          await network.provider.send("evm_mine");
          await network.provider.send("evm_mine");
          const [_, balance] = await stake.callStatic.getUpdatedBalanceOf(user1.address); // callStatic doesn't create blocks
          expect(ethers.utils.formatEther(balance)).to.eq('21.0');
        });

        it("should calculate balance for previous and current phase (Phase 3 - 1 block and Phase 4 - 1 block)", async function () {
          let blocksToMove = (PHASE_THREE_BLOCK - 2) + 122 - (await getCurrentBlock());
          await network.provider.send('hardhat_mine', ["0x" + blocksToMove.toString(16)]);
          await stake.connect(user1).stake(transfer1m);
          await network.provider.send("evm_mine");
          await network.provider.send("evm_mine");
          const [_, balance] = await stake.callStatic.getUpdatedBalanceOf(user1.address); // callStatic doesn't create blocks
          expect(ethers.utils.formatEther(balance)).to.eq('9.0');
        });

        it("should just calculate balance for blocks from phase 4 and not extra blocks ( Phase 4 - Last block and extra 34 blocks)", async function () {
          let blocksToMove = (PHASE_FOUR_BLOCK - 2) + 122 - (await getCurrentBlock());
          await network.provider.send('hardhat_mine', ["0x" + blocksToMove.toString(16)]);
          await stake.connect(user1).stake(transfer1m);
          blocksToMove = 34;
          await network.provider.send('hardhat_mine', ["0x" + blocksToMove.toString(16)]);
          const [_, balance] = await stake.callStatic.getUpdatedBalanceOf(user1.address); // callStatic doesn't create blocks
          expect(ethers.utils.formatEther(balance)).to.eq('4.0');
        });

        it("should calculate all the blocks from phase 1 to phase 4 ", async function () {
          let blocksToMove = 122 - (await getCurrentBlock());
          await network.provider.send('hardhat_mine', ["0x" + blocksToMove.toString(16)]);
          await stake.connect(user1).stake(transfer1m);
          blocksToMove = PHASE_ONE_BLOCK;
          await network.provider.send('hardhat_mine', ["0x" + blocksToMove.toString(16)]);
          await stake.connect(user2).stake(ethers.utils.parseEther("1")); // Forces to change _lastUpdatedBlockNumber state
          blocksToMove = PHASE_TWO_BLOCK - PHASE_ONE_BLOCK;
          await network.provider.send('hardhat_mine', ["0x" + blocksToMove.toString(16)]);
          await stake.connect(user2).stake(ethers.utils.parseEther("1"));
          blocksToMove = PHASE_THREE_BLOCK - PHASE_TWO_BLOCK;
          await network.provider.send('hardhat_mine', ["0x" + blocksToMove.toString(16)]);
          await stake.connect(user2).stake(ethers.utils.parseEther("1"));
          blocksToMove = PHASE_FOUR_BLOCK - PHASE_THREE_BLOCK;
          await network.provider.send('hardhat_mine', ["0x" + blocksToMove.toString(16)]);
          const [_,balance] = await stake.callStatic.getUpdatedBalanceOf(user1.address);
          const etherNumber = ethers.utils.formatEther(balance);
          expect(etherNumber).to.eq('199999962.463131058819');
        });
      });
    });

    describe("Stake calculation for different phases with 2 users ", () => {
      it("should calculate the new balance with rewards for user 1", async function () {
        const blocksToMove = 122 - (await getCurrentBlock());
        await network.provider.send('hardhat_mine', ["0x" + blocksToMove.toString(16)]);
        await stake.connect(user1).stake(transfer1m);
        await stake.connect(user2).stake(transfer500k);
        await stake.connect(user3).stake(transfer500k);
        const [,balance] = await stake.callStatic.getUpdatedBalanceOf(user1.address);
        const etherNumber = ethers.utils.formatEther(balance);
        expect(etherNumber).to.eq('53.333560884032');
      });

      it("should calculate the new balance with rewards for user 2", async function () {
        const blocksToMove = 122 - (await getCurrentBlock());
        await network.provider.send('hardhat_mine', ["0x" + blocksToMove.toString(16)]);
        await stake.connect(user1).stake(transfer1m);
        await stake.connect(user2).stake(transfer500k);
        await stake.connect(user3).stake(transfer500k);
        const [,balance] = await stake.callStatic.getUpdatedBalanceOf(user2.address);
        const etherNumber = ethers.utils.formatEther(balance);
        expect(etherNumber).to.eq('10.666439115936');
      });
    });

    describe("Stake calculation for different phases with at least 3 users ", () => {
      it("should calculate the new balance with rewards for user 1", async function () {
        const blocksToMove = 122 - (await getCurrentBlock());
        await network.provider.send('hardhat_mine', ["0x" + blocksToMove.toString(16)]);
        await stake.connect(user1).stake(transfer1m);
        await stake.connect(user2).stake(transfer500k);
        await stake.connect(user3).stake(transfer500k);
        await stake.connect(user4).stake(transfer1m);
        const [,balance] = await stake.callStatic.getUpdatedBalanceOf(user1.address);
        const etherNumber = ethers.utils.formatEther(balance);
        expect(etherNumber).to.eq('69.33390221008');
      });

      it("should calculate the new balance with rewards for user 2", async function () {
        const blocksToMove = 122 - (await getCurrentBlock());
        await network.provider.send('hardhat_mine', ["0x" + blocksToMove.toString(16)]);
        await stake.connect(user1).stake(transfer1m);
        await stake.connect(user2).stake(transfer500k);
        await stake.connect(user3).stake(transfer500k);
        await stake.connect(user4).stake(transfer1m);
        const [,balance] = await stake.callStatic.getUpdatedBalanceOf(user2.address);
        const etherNumber = ethers.utils.formatEther(balance);
        expect(etherNumber).to.eq('18.666353781664');
      });

      it("should calculate the new balance with rewards for user 3", async function () {
        const blocksToMove = 122 - (await getCurrentBlock());
        await network.provider.send('hardhat_mine', ["0x" + blocksToMove.toString(16)]);
        await stake.connect(user1).stake(transfer1m);
        await stake.connect(user2).stake(transfer500k);
        await stake.connect(user3).stake(transfer500k);
        await stake.connect(user4).stake(transfer1m);
        const [,balance] = await stake.callStatic.getUpdatedBalanceOf(user3.address);
        const etherNumber = ethers.utils.formatEther(balance);
        expect(etherNumber).to.eq('7.99974400816');
      });
    });

    describe("Withdraw", () => {
      it("should transfer current balance to user", async function () {
        const blocksToMove = 122 - (await getCurrentBlock());
        await network.provider.send('hardhat_mine', ["0x" + blocksToMove.toString(16)]);
        await stake.connect(user1).stake(transfer1m);
        await stake.connect(user1).withdraw();
        const user1Balance = await token.balanceOf(user1.address);
        expect(ethers.utils.formatEther(user1Balance)).to.eq('1000032.0');
      });

      it("after withdraw, should not calculate rewards for account without balance", async function () {
        let blocksToMove = 122 - (await getCurrentBlock());
        await network.provider.send('hardhat_mine', ["0x" + blocksToMove.toString(16)]);
        await stake.connect(user1).stake(transfer1m);
        blocksToMove = PHASE_ONE_BLOCK;
        await network.provider.send('hardhat_mine', ["0x" + blocksToMove.toString(16)]);
        await stake.connect(user2).stake(ethers.utils.parseEther("1")); // Forces to change _lastUpdatedBlockNumber state
        blocksToMove = PHASE_TWO_BLOCK - PHASE_ONE_BLOCK;
        await network.provider.send('hardhat_mine', ["0x" + blocksToMove.toString(16)]);
        await stake.connect(user2).stake(ethers.utils.parseEther("1"));
        await stake.connect(user1).withdraw();
        await stake.connect(user2).stake(transfer500k);
        blocksToMove = PHASE_THREE_BLOCK - PHASE_TWO_BLOCK;
        await network.provider.send('hardhat_mine', ["0x" + blocksToMove.toString(16)]);
        await stake.connect(user2).stake(ethers.utils.parseEther("1"));
        blocksToMove = PHASE_FOUR_BLOCK - PHASE_THREE_BLOCK;
        await network.provider.send('hardhat_mine', ["0x" + blocksToMove.toString(16)]);
        const [,balanceUser1] = await stake.callStatic.getUpdatedBalanceOf(user1.address); ;
        const etherNumber = ethers.utils.formatEther(balanceUser1);
        expect(etherNumber).to.eq('0.0');
      });
    });

  });
});
