
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
    
      await network.provider.send('hardhat_mine', ["0x" + blocksToNext.toString(16)]); // +3
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
        await stake.connect(user1).stake(ethers.utils.parseEther("83000")); // +1 block
        await stake.connect(user2).stake(ethers.utils.parseEther("1000000")); // +1 block
        await stake.connect(user3).stake(ethers.utils.parseEther("2000")); // +1 block

        const blocksToActivation = 122 - (await getCurrentBlock());

        await network.provider.send('hardhat_mine', ["0x" + blocksToActivation.toString(16)]);

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

        await stake.updateReward()
        const user1Rewards = (await stake.callStatic.getBalanceOf(user1.address)).map(ethers.utils.formatEther);
        const user2Rewards = (await stake.callStatic.getBalanceOf(user2.address)).map(ethers.utils.formatEther);
        const user3Rewards = (await stake.callStatic.getBalanceOf(user3.address)).map(ethers.utils.formatEther);

        expect(user1Rewards[1]).to.equal('15299539.1704');
        expect(user2Rewards[1]).to.equal('184331797.235');
        expect(user3Rewards[1]).to.equal('368663.5944');

        const user1BalanceBefore = ethers.utils.formatEther(await token.connect(user1).balanceOf(user1.address))
        const user2BalanceBefore = ethers.utils.formatEther(await token.connect(user2).balanceOf(user2.address))
        const user3BalanceBefore = ethers.utils.formatEther(await token.connect(user3).balanceOf(user3.address))

        expect(user1BalanceBefore).to.equal('917000.0')
        expect(user2BalanceBefore).to.equal('4000000.0')
        expect(user3BalanceBefore).to.equal('998000.0')

        const [user1StakedAmount] = await stake.connect(user1).getBalanceOf(user1.address)
        await stake.connect(user1).withdrawStake(user1StakedAmount);
        await stake.connect(user1).withdrawRewards();

        const [user2StakedAmount] = await stake.connect(user2).getBalanceOf(user2.address)
        await stake.connect(user2).withdrawStake(user2StakedAmount);
        await stake.connect(user2).withdrawRewards();

        const [user3StakedAmount] = await stake.connect(user3).getBalanceOf(user3.address)
        await stake.connect(user3).withdrawStake(user3StakedAmount);
        await stake.connect(user3).withdrawRewards();

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

    describe('withdrawStake', () => {

      it('should throw error if withdrawStake amount is NOT greater than 0', async () => {
        await stake.connect(user1).stake(transfer1m)

        const _withdrawStake = stake.connect(user1).withdrawStake(0)
        const errorMessage = 'Withdraw Stake: Amount must be greater than 0'

        await expect(_withdrawStake).to.be.revertedWith(errorMessage)
      })

      it('should throw error if staked amount is LOWER than withdraw amount', async () => {
        const oneThousand = ethers.utils.parseEther("1000")
        const twoThousand = ethers.utils.parseEther("2000")
        
        await stake.connect(user1).stake(oneThousand)

        const _withdrawStake = stake.connect(user1).withdrawStake(twoThousand)
        const errorMessage = 'Withdraw amount is greater than staked amount'

        await expect(_withdrawStake).to.be.revertedWith(errorMessage)
      })

      it("should reduce all balances correctly", async () => {
        const stakeAmount = ethers.utils.parseUnits("1000", "ether")
        const withdrawAmount = ethers.utils.parseUnits("495", "ether")

        const stakeContract = stake.connect(user1)

        await stakeContract.stake(stakeAmount)
        await stakeContract.withdrawStake(withdrawAmount)

        const [user1StakedAmount] = await stakeContract.getBalanceOf(user1.address)

        const totalStaked = await stakeContract._totalStaked()
        const user1TotalStaked = stakeAmount.sub(withdrawAmount)


        expect(user1StakedAmount).to.eq(user1TotalStaked)
        expect(totalStaked).to.eq(user1TotalStaked)
      })
    })
    
    describe('withdrawRewards', () => {
      it('should throw an error if reward is 0', async () => {
        const stakeContract = stake.connect(user1)
        
        await stakeContract.stake(transfer1k)

        const _withdrawRewards = stakeContract.withdrawRewards()
        const errorMessage = 'No reward to be withdrawn'

        await expect(_withdrawRewards).to.be.revertedWith(errorMessage)
      })

      it('should reduce all balances correctly', async () => {
        const stakeContract = stake.connect(user1)
        
        await stakeContract.stake(transfer1k)

        const currentBlock = await getCurrentBlock()
        const moveToPointZero = 122 - currentBlock; // point zero

        await network.provider.send('hardhat_mine', ["0x" + moveToPointZero.toString(16)]);
        await network.provider.send('hardhat_mine', ["0x" + PHASE_ONE_BLOCK.toString(16)]);
        
        const user1RewardBalance = await stake.callStatic.getReward(user1.address)
        const [, balanceBeforeWithdraw] = await stake.callStatic.getUpdatedBalanceOf(user1.address);
        
        expect(user1RewardBalance).to.eq(balanceBeforeWithdraw)

        await stakeContract.withdrawRewards()

        const [, balanceAfterWithdraw] = await stake.callStatic.getUpdatedBalanceOf(user1.address);

        expect(balanceAfterWithdraw).to.eq("0")
      })

      it("should not calculate rewards for account without balance", async function () {
        let blocksToMove = 122 - (await getCurrentBlock());
        await network.provider.send('hardhat_mine', ["0x" + blocksToMove.toString(16)]);
        await stake.connect(user1).stake(transfer1m);
        blocksToMove = PHASE_ONE_BLOCK;
        await network.provider.send('hardhat_mine', ["0x" + blocksToMove.toString(16)]);
        await stake.connect(user2).stake(ethers.utils.parseEther("1")); // Forces to change _lastUpdatedBlockNumber state
        blocksToMove = PHASE_TWO_BLOCK - PHASE_ONE_BLOCK;
        await network.provider.send('hardhat_mine', ["0x" + blocksToMove.toString(16)]);
        await stake.connect(user2).stake(ethers.utils.parseEther("1"));
        const [user1StakedAmount] = await stake.callStatic.getBalanceOf(user1.address);
        await stake.connect(user1).withdrawStake(user1StakedAmount);
        await stake.connect(user1).withdrawRewards();
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
    })

  });
});
