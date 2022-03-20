
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
    token: ERC20,
    stake: StakingRewards;

    const transfer1m = ethers.utils.parseEther("1000000");
    const transfer10k = ethers.utils.parseEther("10000");
    const transfer300m = ethers.utils.parseEther("300000000");
    
    beforeEach(async () => {
      [owner, user1, user2, user3] = await ethers.getSigners();
      const tokenContract = await ethers.getContractFactory("SoundchainOGUN20");
      const StakingContract: StakingRewards__factory =
      await ethers.getContractFactory("StakingRewards");
      token = await tokenContract.deploy();
      stake = await StakingContract.deploy(token.address, transfer300m);

      await token.transfer(stake.address, transfer300m);
      await token.transfer(user1.address, transfer1m);
      await token.transfer(user2.address, transfer1m);
      await token.transfer(user3.address, transfer1m);


      await token.connect(user1).approve(stake.address, transfer1m);
      await token.connect(user2).approve(stake.address, transfer1m);
      await token.connect(user3).approve(stake.address, transfer1m);
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
        await network.provider.send('hardhat_mine', ['0x30000']);
        await stake.connect(user1).stake(transfer1m);
        await stake.connect(user2).stake(transfer1m);
        const balance = await stake.callStatic.getBalanceOf(user1.address);
        expect(ethers.utils.formatEther(balance)).to.eq('1000128.205128');
      });


      it("x343 - should increase balance of user 1 (by 128.205128 x 343 phase 2)", async function () {
        await network.provider.send('hardhat_mine', ['0x30000']);
        await stake.connect(user1).stake(transfer1m);
        await network.provider.send('hardhat_mine', ['0x157']);
        const balance = await stake.callStatic.getBalanceOf(user1.address);
        expect(ethers.utils.formatEther(balance)).to.eq('1043974.358904');
      });

      it("x1 - should increase balance of user 1 (by 48.0769231 phase 3)", async function () {
        await network.provider.send('hardhat_mine', ['0x90000']);
        await stake.connect(user1).stake(transfer1m);
        await stake.connect(user2).stake(transfer1m);
        const balance = await stake.callStatic.getBalanceOf(user1.address);
        expect(ethers.utils.formatEther(balance)).to.eq('1000048.0769231');
      });
      
      it("x71 - should increase balance of user 1 (by 48.0769231 x 71 phase 3)", async function () {
        await network.provider.send('hardhat_mine', ['0x90000']);
        await stake.connect(user1).stake(transfer1m);
        await network.provider.send('hardhat_mine', ['0x47']);
        const balance = await stake.callStatic.getBalanceOf(user1.address);
        expect(ethers.utils.formatEther(balance)).to.eq('1003413.4615401');
      });

      it("x1 - should increase balance of user 1 (by 38.3590836 phase 4)", async function () {
        await network.provider.send('hardhat_mine', ['0x180000']);
        await stake.connect(user1).stake(transfer1m);
        await stake.connect(user2).stake(transfer1m);
        const balance = await stake.callStatic.getBalanceOf(user1.address);
        expect(ethers.utils.formatEther(balance)).to.eq('1000038.3590836');
      });

      it("x51 - should increase balance of user 1 (by 38.3590836 x 51 phase 4)", async function () {
        await network.provider.send('hardhat_mine', ['0x180000']);
        await stake.connect(user1).stake(transfer1m);
        await network.provider.send('hardhat_mine', ['0x33']);
        const balance = await stake.callStatic.getBalanceOf(user1.address);
        expect(ethers.utils.formatEther(balance)).to.eq('1001956.3132636');
      });

    describe("Withdraw", () => {
      it("should transfer current balance to user", async function () {
        await stake.connect(user1).stake(transfer1m);
        await stake.connect(user1).withdraw();
        const user1Balance = await token.balanceOf(user1.address);
        expect(ethers.utils.formatEther(user1Balance)).to.eq('1000307.692308');
      });

      // it("should substract transfer current balance to user", async function () {
      //   await stake.connect(user1).stake(transfer1m);
      //   await stake.connect(user1).withdraw();

      //   const user1Balance = await token.balanceOf(user1.address);
      //   const tokenBalance = await token.balanceOf(stake.address);
      //   console.log('New TOKEN BALANCE USER string: ', user1Balance.toString());
      //   console.log('New TOKEN BALANCE USER 1: ', ethers.utils.formatEther(user1Balance));
      //   console.log('New TOKEN BALANCE Stake contrect: ', ethers.utils.formatEther(tokenBalance));
      //   expect(ethers.utils.formatEther(user1Balance)).to.eq('1000307.692308');
      // });
    });


        // await stake.connect(user2).stake(transfer1m);
        // const balance = await stake.callStatic.getBalanceOf(user1.address);
        // const rc = await tx.wait();
        // console.log('Withdrwa TX: ', tx);


        // await stake.connect(user1).stake(transfer1m);
        // await stake.connect(user2).stake(transfer1m);

      //   // await network.provider.send('hardhat_mine', ['0x180000']);
        // await network.provider.send('hardhat_mine', ['0x1']);
        // const addres2Bal = await token.balanceOf(user1.address);
        // console.log('addres2Bal: ', addres2Bal.toString());
      //   // const stakingContractBalance = await token.balanceOf(stake.address);
      //   // console.log('New Staking Contract bal: ', stakingContractBalance.toString());
      //   // await stake.connect(user1).withdraw();
      //   // expect(balance.toString()).to.eq('10000480769231000000000000');

        // await network.provider.send("evm_mine");
        // await ethers.provider.send('hardhat_mine', ['0x100']);

        // console.log('balance  after stakes of contract stake: ', (await token.balanceOf(stake.address)).toString());
        // console.log('balances in stakeof user 1: ', await (await stake.getBalanceOf(user1.address)).toString());

        // const supplyreward = await stake.totalStakeSupply();
        // console.log('reward supply: ', supplyreward.toString());

    });



  });
});

// describe("Staking 2", () => {
//   let owner: SignerWithAddress,
//     user1: SignerWithAddress, 
//     user2: SignerWithAddress,
//     user3: SignerWithAddress,
//     token: ERC20,
//     stake: StakingRewards;


//   // describe("Stake contract", function () {
//   //   const transfer1m = ethers.utils.parseEther("1000000");
//   //   const transfer10k = ethers.utils.parseEther("10000");
//   //   const transfer300m = ethers.utils.parseEther("300000000");

//   //   beforeEach(async () => {
//   //     [owner, user1, user2, user3] = await ethers.getSigners();
//   //     const tokenContract = await ethers.getContractFactory("SoundchainOGUN20");
//   //     const StakingContract: StakingRewards__factory =
//   //     await ethers.getContractFactory("StakingRewards");
//   //     token = await tokenContract.deploy();
//   //     stake = await StakingContract.deploy(token.address);

//   //     await token.transfer(stake.address, transfer300m);
//   //     await token.transfer(user1.address, transfer1m);
//   //     await token.transfer(user2.address, transfer1m);
//   //     await token.transfer(user3.address, transfer1m);


//   //     await token.connect(user1).approve(stake.address, transfer1m);
//   //     await token.connect(user2).approve(stake.address, transfer1m);
//   //     await token.connect(user3).approve(stake.address, transfer1m);
//   //   });


//   //   // describe("Withdraw", () => {
//   //   //   // it("Balance shoudl be higher of 1m", async function () {

//   //   //   //   await stake.connect(user1).stake(transfer1m);
//   //   //   //   await network.provider.send("evm_mine");
//   //   //   //   const stakeBalance = await stake.callStatic.getBalanceOf(user1.address);
//   //   //   //   // await stake.connect(user1).withdraw();
//   //   //   //   // await stake.connect(user2).stake(transfer1m);
//   //   //   //   // await network.provider.send('hardhat_mine', ['0x1']);
//   //   //   //   // await stake.connect(user1).stake(transfer1m);
//   //   //   //   // const addres2Bal = await token.balanceOf(user1.address);
//   //   //   //   // console.log('addres1Bal: ', stakeBalance.toString());
//   //   //   //   // await stake.connect(user2).stake(transfer1m);
//   //   //   // });


//   //   //   it("**** s in network ******", async function () {
//   //   //     await stake.connect(user1).stake(transfer1m);
//   //   //     await stake.connect(user2).stake(transfer1m);
//   //   //     // await network.provider.send("evm_mine");
//   //   //     const balance = await stake.callStatic.getBalanceOf(user1.address);
//   //   //     expect(balance).to.eq(transfer1m);
//   //   //   });

//   //   // });


    

//   // });

// });


        //approve user1 and stake 1000000
        // await network.provider.send("evm_mine");
        // const balance = await stake.callStatic.getBalanceOf(user1.address);
        // const tx = await stake.getBalanceOf(user1.address);
        // const rc = await tx.wait();
        // const event = rc.events.find(event => event.event === 'RewardsCalculated');
        // const [amount] = event.args;
        // console.log('EVENT***: ', amount);
        // console.log('RC***: ', rc.events[0].args[0].toString());



        // const tx = await stake.getBalanceOf(user1.address);
        // const rc = await tx.wait();
        // const event = rc.events.find(event => event.event === 'RewardsCalculated');
        // const [amount] = event.args;
        // console.log('EVENT***: ', amount);
        // console.log('RC***: ', rc.events[0].args[0].toString());




        // DECIMALS
        // const expectedResult = Web3.utils.fromWei('1000307692308000000000000', 'ether');
        // const balanceDecimals = Web3.utils.fromWei(balance.toString(), 'ether');