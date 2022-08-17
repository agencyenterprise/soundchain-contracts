import { KmsProvider } from "aws-kms-provider";
import dotenv from "dotenv";
import { ethers, run } from "hardhat";
import Web3 from "web3";

dotenv.config();

const region = "us-east-1";

const { AWS_KMS_KEY_ID, POLYGON_ALCHEMY_URL, CONTRACT_URI } = process.env;

const provider = new KmsProvider(POLYGON_ALCHEMY_URL, {
  region,
  keyIds: [AWS_KMS_KEY_ID],
});

const web3 = new Web3(provider);

const getAdminWallet = async () => {
  const accounts = await web3.eth.getAccounts();
  return accounts[0];
};

const getSignedTransaction = async (data) => {
  const from = await getAdminWallet();
  const nonce = await web3.eth.getTransactionCount(from);
  const transaction = {
    from,
    data,
    nonce,
  };
  return await web3.eth.signTransaction(transaction, from);
};

const sendSignedTransaction = async (signedTransaction) => {
  return await web3.eth.sendSignedTransaction(signedTransaction);
};

const { OGUN_TOKEN_ADDRESS, LP_TOKEN_ADDRESS } = process.env;

const delay = (ms) => new Promise((res) => setTimeout(res, ms));

const main = async () => {

  console.log("💡 Deploying StakingRewards");
  const totalOGUNStaking = web3.utils.toWei('10000'); // 200 million
  const StakingRewards = await ethers.getContractFactory("StakingRewards");
  const StakingRewardsDeployTransaction = StakingRewards.getDeployTransaction(OGUN_TOKEN_ADDRESS, totalOGUNStaking);
  const StakingRewardsSigned = await getSignedTransaction(
    StakingRewardsDeployTransaction.data
  );
  const StakingRewardsReceipt = await sendSignedTransaction(
    StakingRewardsSigned.raw
  );
  console.log(
    `✅ StakingRewards deployed to address: ${StakingRewardsReceipt.contractAddress}`
  );

  // console.log("💡 Deploying LiquidityPoolRewards");
  // const totalOGUNLPStaking = web3.utils.toWei('100000000'); // 100 million
  // const LiquidityPoolRewards = await ethers.getContractFactory("LiquidityPoolRewards");
  // const LiquidityPoolRewardsDeployTransaction = LiquidityPoolRewards.getDeployTransaction(OGUN_TOKEN_ADDRESS, LP_TOKEN_ADDRESS, totalOGUNLPStaking);
  // const LiquidityPoolRewardsSigned = await getSignedTransaction(
  //   LiquidityPoolRewardsDeployTransaction.data
  // );
  // const LiquidityPoolRewardsReceipt = await sendSignedTransaction(
  //   LiquidityPoolRewardsSigned.raw
  // );
  // console.log(
  //   `✅ LiquidityPoolRewards deployed to address: ${LiquidityPoolRewardsReceipt.contractAddress}`
  // );

  console.log("⏰ Waiting confirmations");
  await delay(10000);

  console.log("🪄  Verifying contracts");

  // await run("verify:verify", {
  //   address: LiquidityPoolRewardsReceipt.contractAddress,
  //   constructorArguments: [ OGUN_TOKEN_ADDRESS, LP_TOKEN_ADDRESS, totalOGUNLPStaking],
  // });

  // console.log("✅ LiquidityPoolRewardsContract verified on Etherscan");
  
};

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
