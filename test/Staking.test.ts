
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { ethers } from "hardhat";
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
    
  describe("supply", function () {
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
      // console.log('stake contract: ', stake);

    });

    describe("Stake contract", () => {
      // const failedAmount = utils.parseEther("1000000001");

      it("sustracts token amount from senders balance", async function () {
        // console.log('TOKEN ADDRESS: ', stake.address);
        console.log('First balance of contract stake: ', (await token.balanceOf(stake.address)).toString());
        //transfer to users
        await token.transfer(user1.address, transfer1m);
        await token.transfer(user2.address, transfer1m);
        await token.transfer(user3.address, transfer1m);
        
        //approve user1 and stake 1000000
        await token.connect(user1).approve(stake.address, transfer1m);
        await stake.connect(user1).stake(transfer1m);

        await stake.addBlock();
        await stake.addBlock();
        
        //approve user2 and stake 1000000
        await token.connect(user2).approve(stake.address, transfer1m);
        await stake.connect(user2).stake(transfer1m);


        console.log('balance  after stakes of contract stake: ', (await token.balanceOf(stake.address)).toString());
        console.log('balances in stakeof user 1: ', await (await stake.getBalanceOf(user1.address)).toString());


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
});