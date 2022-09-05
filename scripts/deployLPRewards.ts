import { KmsProvider } from "aws-kms-provider";
import dotenv from "dotenv";
import { ethers, run } from "hardhat";
import Web3 from "web3";

dotenv.config();

const region = "us-east-1";

const { AWS_KMS_KEY_ID, POLYGON_ALCHEMY_URL, OGUN_TOKEN_ADDRESS, LP_TOKEN_ADDRESS } = process.env;

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

const delay = (ms) => new Promise((res) => setTimeout(res, ms));

const main = async () => {

  console.log("💡 Deploying LiquidityPoolRewards");
  const totalOGUNLPStaking = web3.utils.toWei('100000000'); // 100 million
  const LiquidityPoolRewards = await ethers.getContractFactory("LiquidityPoolRewards");
  const LiquidityPoolRewardsDeployTransaction = LiquidityPoolRewards.getDeployTransaction(OGUN_TOKEN_ADDRESS, LP_TOKEN_ADDRESS, totalOGUNLPStaking);
  const LiquidityPoolRewardsSigned = await getSignedTransaction(
    LiquidityPoolRewardsDeployTransaction.data
  );
  const LiquidityPoolRewardsReceipt = await sendSignedTransaction(
    LiquidityPoolRewardsSigned.raw
  );
  console.log(
    `✅ LiquidityPoolRewards deployed to address: ${LiquidityPoolRewardsReceipt.contractAddress}`
  );

  // console.log("💡 Deploying TestContract");
  // const TestContract = await ethers.getContractFactory("TestContract");
  // const TestContractTx = TestContract.getDeployTransaction(OGUN_TOKEN_ADDRESS);
  // const TestContractSigned = await getSignedTransaction(
  //   TestContractTx.data
  // );
  // const LiquidityPoolRewardsReceipt = await sendSignedTransaction(
  //   TestContractSigned.raw
  // );
  // console.log(
  //   `✅ TestContract deployed to address: ${LiquidityPoolRewardsReceipt.contractAddress}`
  // );
};

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
