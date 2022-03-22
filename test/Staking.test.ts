
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { expect } from "chai";
import { ethers, network } from "hardhat";
import {
  ERC20,
  StakingRewards,
  StakingRewards__factory
} from "../typechain-types";

// Tests
// Deploy stake contract
// Transfer rewards supply
// Stake from user1 1000000
// check user 1 balance in stake contract
// Stake from user2 300000
// check user 1 balance in stake contract
//  check gas
// Stake from user1 100000
// Withdraw from user1 
// 

describe("Staking", () => {
  let owner: SignerWithAddress,
    user1: SignerWithAddress, 
    user2: SignerWithAddress,
    user3: SignerWithAddress,
    user4: SignerWithAddress,
    token: ERC20,
    stake: StakingRewards;

    const transfer1m = ethers.utils.parseEther("1000000");
    const transfer500k = ethers.utils.parseEther("500000");
    const transfer300m = ethers.utils.parseEther("300000000");
    
    beforeEach(async () => {
      [owner, user1, user2, user3, user4] = await ethers.getSigners();
      const tokenContract = await ethers.getContractFactory("SoundchainOGUN20");
      const StakingContract: StakingRewards__factory =
      await ethers.getContractFactory("StakingRewards");
      token = await tokenContract.deploy();
      stake = await StakingContract.deploy(token.address, transfer300m);

      await token.transfer(stake.address, transfer300m);
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
  describe("Stake contract", function () {

    describe("Stake calculation for different pahses with just 1 user", () => {
      it("reverts if address doesn't exist in balances", async function () {
        await expect(
          stake.callStatic.getBalanceOf(user1.address)
        ).to.be.revertedWith("address hasn't stake any tokens yet");
      });
      
      it("should no increace balance with rewards if there is no new blocks in network", async function () {
        await stake.connect(user1).stake(transfer1m);
        const balance = await stake.callStatic.getBalanceOf(user1.address);
        expect(balance).to.eq(transfer1m);
      });

      it("x1 - should increase balance of user 1 (by 307.692308 phase 1)", async function () {
        await stake.connect(user1).stake(transfer1m);
        await stake.connect(user2).stake(transfer1m);
        const balance = await stake.callStatic.getBalanceOf(user1.address);
        expect(ethers.utils.formatEther(balance)).to.eq('1000307.692308');
      });

      it("x23 - should increase balance of user 1 (by 307.692308 x 23 phase 1)", async function () {
        await stake.connect(user1).stake(transfer1m);
        await network.provider.send('hardhat_mine', ['0x17']);
        const balance = await stake.callStatic.getBalanceOf(user1.address);
        expect(ethers.utils.formatEther(balance)).to.eq('1007076.923084');
      });

      it("x1 - should increase balance of user 1 (by 128.205128 phase 2)", async function () {
        await network.provider.send('hardhat_mine', ['0x2f9b8']);
        await stake.connect(user1).stake(transfer1m);
        await stake.connect(user2).stake(transfer1m);
        const balance = await stake.callStatic.getBalanceOf(user1.address);
        expect(ethers.utils.formatEther(balance)).to.eq('1000128.205128');
      });

      it("x343 - should increase balance of user 1 (by 128.205128 x 343 phase 2)", async function () {
        await network.provider.send('hardhat_mine', ['0x2f9b8']);
        await stake.connect(user1).stake(transfer1m);
        await network.provider.send('hardhat_mine', ['0x157']);
        const balance = await stake.callStatic.getBalanceOf(user1.address);
        expect(ethers.utils.formatEther(balance)).to.eq('1043974.358904');
      });

      it("x1 - should increase balance of user 1 (by 48.0769231 phase 3)", async function () {
        await network.provider.send('hardhat_mine', ['0xbe6e0']);
        await stake.connect(user1).stake(transfer1m);
        await stake.connect(user2).stake(transfer1m);
        const balance = await stake.callStatic.getBalanceOf(user1.address);
        expect(ethers.utils.formatEther(balance)).to.eq('1000048.0769231');
      });
      
      it("x71 - should increase balance of user 1 (by 48.0769231 x 71 phase 3)", async function () {
        await network.provider.send('hardhat_mine', ['0xbe6e0']);
        await stake.connect(user1).stake(transfer1m);
        await network.provider.send('hardhat_mine', ['0x47']);
        const balance = await stake.callStatic.getBalanceOf(user1.address);
        expect(ethers.utils.formatEther(balance)).to.eq('1003413.4615401');
      });

      it("x1 - should increase balance of user 1 (by 38.3590836 phase 4)", async function () {
        await network.provider.send('hardhat_mine', ['0x23b4a0']);
        await stake.connect(user1).stake(transfer1m);
        await stake.connect(user2).stake(transfer1m);
        const balance = await stake.callStatic.getBalanceOf(user1.address);
        expect(ethers.utils.formatEther(balance)).to.eq('1000038.3590836');
      });

      it("x51 - should increase balance of user 1 (by 38.3590836 x 51 phase 4)", async function () {
        await network.provider.send('hardhat_mine', ['0x23b4a0']);
        await stake.connect(user1).stake(transfer1m);
        await network.provider.send('hardhat_mine', ['0x33']);
        const balance = await stake.callStatic.getBalanceOf(user1.address);
        expect(ethers.utils.formatEther(balance)).to.eq('1001956.3132636');
      });

      describe("Stake calculation between phases", () => {
        it("should calculate balance for previous and current phase (Phase 1 - 1 block and Phase 2 - 1 block)", async function () {
          //+10 previous blocks from beforeEach function
          await network.provider.send('hardhat_mine', ['0x2f9ad']); // + 194,989 blocks 
          await stake.connect(user1).stake(transfer1m);// block 194,999
          await network.provider.send("evm_mine");// + block 195,000
          await network.provider.send("evm_mine");// + 1 block
          const balance = await stake.callStatic.getBalanceOf(user1.address); // callStatic doesn't create blocks 
          expect(ethers.utils.formatEther(balance)).to.eq('1000435.897436');
        });
  
        it("should calculate balance for previous and current phase (Phase 2 - 1 block and Phase 3 - 1 block)", async function () {
          //+10 previous blocks from beforeEach function
          await network.provider.send('hardhat_mine', ['0xbe6d5']); // + 779,989 blocks 
          await stake.connect(user1).stake(transfer1m);// + 1 block 
          await network.provider.send("evm_mine");// + 1 block 
          await network.provider.send("evm_mine");// + 1 block
          const balance = await stake.callStatic.getBalanceOf(user1.address); // callStatic doesn't create blocks 
          expect(ethers.utils.formatEther(balance)).to.eq('1000176.2820511');
        });
  
        it("should calculate balance for previous and current phase (Phase 3 - 1 block and Phase 4 - 1 block)", async function () {
          //+10 previous blocks from beforeEach function
          await network.provider.send('hardhat_mine', ['0x23b495']); // + 2,339,989 blocks 
          await stake.connect(user1).stake(transfer1m);// + 1 block 
          await network.provider.send("evm_mine");// + 1 block 
          await network.provider.send("evm_mine");// + 1 block
          const balance = await stake.callStatic.getBalanceOf(user1.address); // callStatic doesn't create blocks 
          expect(ethers.utils.formatEther(balance)).to.eq('1000086.4360067');
        });

        it("should just calculate balance for blocks from phase 4 and not extra blocks ( Phase 4 - Last block and extra 34 blocks)", async function () {
          //+10 previous blocks from beforeEach function
          await network.provider.send('hardhat_mine', ['0x47819f']); // + 4,686,239 blocks 
          await stake.connect(user1).stake(transfer1m);// + 1 block 
          await network.provider.send("evm_mine");// + 1 block 
          await network.provider.send('hardhat_mine', ['0x21']); // + 33 blocks
          const balance = await stake.callStatic.getBalanceOf(user1.address); // callStatic doesn't create blocks 
          expect(ethers.utils.formatEther(balance)).to.eq('1000038.3590836');
        });


        it("should calculate all the blocks from phase 1 to phase 4 ", async function () {
          //+10 previous blocks from beforeEach function (This 10 blocks are 3076.92308 rewards that will not be apply)
          await stake.connect(user1).stake(transfer1m);
          await network.provider.send('hardhat_mine', ['0x2f9ae']); // + 194,989 blocks 
          await stake.connect(user2).stake(ethers.utils.parseEther("1")); // Forces to change _lastUpdatedBlockNumber state
          await network.provider.send('hardhat_mine', ['0x8ed28']); // + 585,000 blocks 
          await stake.connect(user2).stake(ethers.utils.parseEther("1"));
          await network.provider.send('hardhat_mine', ['0x17cdc0']); // + 1,560,000 blocks 
          await stake.connect(user2).stake(ethers.utils.parseEther("1"));
          await network.provider.send('hardhat_mine', ['0x23cd0a']); // + 2,346,250 blocks 
          const balance = await stake.callStatic.getBalanceOf(user1.address); 
          const etherNumber = ethers.utils.formatEther(balance);
          expect(Number.parseFloat(etherNumber).toFixed(6)).to.eq('300996917.374868');
        });
      });
    });

    describe("Stake calculation for different pahses with 2 users ", () => {
      it("should calculate the new balance with rewards for user 1", async function () {
        await stake.connect(user1).stake(transfer1m);
        await stake.connect(user2).stake(transfer500k); 
        await stake.connect(user3).stake(transfer500k);
        const balance = await stake.callStatic.getBalanceOf(user1.address);  
        const etherNumber = ethers.utils.formatEther(balance);
        expect(Number.parseFloat(etherNumber).toFixed(6)).to.eq('1000512.841548');
      });

      it("should calculate the new balance with rewards for user 2", async function () {
        await stake.connect(user1).stake(transfer1m);
        await stake.connect(user2).stake(transfer500k);
        await stake.connect(user3).stake(transfer500k);
        const balance = await stake.callStatic.getBalanceOf(user2.address); 
        const etherNumber = ethers.utils.formatEther(balance);
        expect(Number.parseFloat(etherNumber).toFixed(6)).to.eq('500102.543068');
      });
    });

    describe("Stake calculation for different pahses with at least 3 users ", () => {
      it("should calculate the new balance with rewards for user 1", async function () {
        await stake.connect(user1).stake(transfer1m);
        await stake.connect(user2).stake(transfer500k); 
        await stake.connect(user3).stake(transfer500k);
        await stake.connect(user4).stake(transfer1m);
        const balance = await stake.callStatic.getBalanceOf(user1.address);  
        const etherNumber = ethers.utils.formatEther(balance);
        expect(Number.parseFloat(etherNumber).toFixed(6)).to.eq('1000666.719254');
      });

      it("should calculate the new balance with rewards for user 2", async function () {
        await stake.connect(user1).stake(transfer1m);
        await stake.connect(user2).stake(transfer500k);
        await stake.connect(user3).stake(transfer500k);
        await stake.connect(user4).stake(transfer1m);
        const balance = await stake.callStatic.getBalanceOf(user2.address); 
        const etherNumber = ethers.utils.formatEther(balance);
        expect(Number.parseFloat(etherNumber).toFixed(6)).to.eq('500179.458255');
      });

      it("should calculate the new balance with rewards for user 3", async function () {
        await stake.connect(user1).stake(transfer1m);
        await stake.connect(user2).stake(transfer500k);
        await stake.connect(user3).stake(transfer500k);
        await stake.connect(user4).stake(transfer1m);
        const balance = await stake.callStatic.getBalanceOf(user3.address); 
        const etherNumber = ethers.utils.formatEther(balance);
        expect(Number.parseFloat(etherNumber).toFixed(6)).to.eq('500076.899416');
      });
    });

    describe("Withdraw", () => {
      it("should transfer current balance to user", async function () {
        await stake.connect(user1).stake(transfer1m);
        await stake.connect(user1).withdraw();
        const user1Balance = await token.balanceOf(user1.address);
        expect(ethers.utils.formatEther(user1Balance)).to.eq('1000307.692308');
      });
    });

  });
});
