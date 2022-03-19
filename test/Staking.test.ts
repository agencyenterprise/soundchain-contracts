
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

const advanceBlocks = async (blocks: number) =>  {
  // for (let index = 0; index < blocks; index++) {
    await network.provider.send('hardhat_mine', ['0x' + blocks.toString(16)]);
  // }
}

describe("Staking", () => {
  let owner: SignerWithAddress,
    user1: SignerWithAddress, 
    user2: SignerWithAddress,
    user3: SignerWithAddress,
    token: ERC20,
    stake: StakingRewards;
    
  describe("Stake contract", function () {
    const transfer1m = ethers.utils.parseEther("1000000");
    const transfer10k = ethers.utils.parseEther("10000");
    const transfer300m = ethers.utils.parseEther("300000000");

    beforeEach(async () => {
      [owner, user1, user2, user3] = await ethers.getSigners();
      const tokenContract = await ethers.getContractFactory("SoundchainOGUN20");
      const StakingContract: StakingRewards__factory =
      await ethers.getContractFactory("StakingRewards");
      token = await tokenContract.deploy();
      stake = await StakingContract.deploy(token.address);

      await token.transfer(stake.address, transfer300m);
      await token.transfer(user1.address, transfer1m);
      await token.transfer(user2.address, transfer1m);
      await token.transfer(user3.address, transfer1m);


      await token.connect(user1).approve(stake.address, transfer1m);
      await token.connect(user2).approve(stake.address, transfer1m);
      await token.connect(user3).approve(stake.address, transfer1m);
    });

    describe("User1 stake 1 million tokens", () => {
      it("reverts if address doesn't exist in balances", async function () {
        await expect(
          stake.callStatic.getBalanceOf(user1.address)
        ).to.be.revertedWith("address hasn't stake any tokens yet");
      });
      
      it("should no increace balance if there is no new blocks in network", async function () {
        await stake.connect(user1).stake(transfer1m);
        const balance = await stake.callStatic.getBalanceOf(user1.address);
        expect(balance).to.eq(transfer1m);
      });

      it("should increase balance of user 1 (by 307.6923080 phase 1)", async function () {
        await stake.connect(user1).stake(transfer1m);
        await stake.connect(user2).stake(transfer1m);
        const balance = await stake.callStatic.getBalanceOf(user1.address);
        expect(balance.toString()).to.eq('1000307692308000000000000');
      });

      it("should increase balance of user 1 (by 128.205128 phase 2)", async function () {
        await network.provider.send('hardhat_mine', ['0x30000']);
        await stake.connect(user1).stake(transfer1m);
        await stake.connect(user2).stake(transfer1m);
        const balance = await stake.callStatic.getBalanceOf(user1.address);
        expect(balance.toString()).to.eq('1000128205128000000000000');
      });


      it("should increase balance of user 1 (by 48.0769231 phase 3)", async function () {
        // await network.provider.send('hardhat_mine', ['0x180000']);
        await network.provider.send('hardhat_mine', ['0x90000']);
        await stake.connect(user1).stake(transfer1m);
        await stake.connect(user2).stake(transfer1m);
        const balance = await stake.callStatic.getBalanceOf(user1.address);
        expect(balance.toString()).to.eq('10000480769231000000000000');
      });
        // await stake.connect(user2).stake(transfer1m);
        // await stake.connect(user3).stake(transfer1m);
              //await (await stake.getBalanceOf(user1.address)).toString()
        // const result = await stake.getBalanceOf(user1.address);
        // console.log('CUERRENT BALANCE user1: ', result);

        // await network.provider.send("evm_mine");
        // await ethers.provider.send('hardhat_mine', ['0x100']);
        // advanceBlocks(256);
        // await stake.addBlock();
        // await stake.addBlock();
        
        // //approve user2 and stake 1000000
        // await token.connect(user2).approve(stake.address, transfer1m);
        // await stake.connect(user2).stake(transfer1m);


        // console.log('balance  after stakes of contract stake: ', (await token.balanceOf(stake.address)).toString());
        // console.log('balances in stakeof user 1: ', await (await stake.getBalanceOf(user1.address)).toString());






        // await token.connect(user3).approve(stake.address, transfer1m);
        // await stake.connect(user3).stake(transfer1m);
        // console.log('balances in stakeof user 1: ', await (await stake.getBalanceOf(user1.address)).toString());
        // console.log('balances in stakeof user 2: ', await (await stake.getBalanceOf(user2.address)).toString());

        
        // console.log('balance  token user 1: ', (await token.balanceOf(user1.address)).toString());
        // console.log('STAKE CONTRACT: ', stake);
        
        // const supplyreward = await stake.totalStakeSupply();
        // console.log('reward supply: ', supplyreward.toString());

        // const supplyreward = await stake.totalStakeSupply;
        // console.log('reward supply: ', supplyreward);
        // await stake.connect(user2).stake(transferAmount);
        // const reward = await stake.connect(user1).withdraw;
        // console.log('reward: ', reward);

        // setTimeout(() => {console.log("wait 5 sec")}, 5000);

        

        // const expectedBalance = utils.parseEther("999000000");
        // const balance = await token.balanceOf(owner.address);
        // expect(balance).to.eq(expectedBalance);

    });
  });
});


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