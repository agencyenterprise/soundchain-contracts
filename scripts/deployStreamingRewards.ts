import { KmsProvider } from "aws-kms-provider";
import dotenv from "dotenv";
import { ethers, run } from "hardhat";
import Web3 from "web3";

dotenv.config();

const region = "us-east-1";

const {
  AWS_KMS_KEY_ID,
  POLYGON_ALCHEMY_URL,
  OGUN_TOKEN_ADDRESS,
  STAKING_CONTRACT_ADDRESS,
} = process.env;

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
  if (!OGUN_TOKEN_ADDRESS) {
    throw new Error("OGUN_TOKEN_ADDRESS not set in environment");
  }

  console.log("=".repeat(60));
  console.log("    STREAMING REWARDS DISTRIBUTOR DEPLOYMENT");
  console.log("=".repeat(60));
  console.log("");
  console.log("Configuration:");
  console.log(`  OGUN Token: ${OGUN_TOKEN_ADDRESS}`);
  console.log(`  Staking Contract: ${STAKING_CONTRACT_ADDRESS || "Not set (will configure later)"}`);
  console.log("");

  // Deploy StreamingRewardsDistributor
  console.log("💡 Deploying StreamingRewardsDistributor...");
  const StreamingRewardsDistributor = await ethers.getContractFactory("StreamingRewardsDistributor");
  const deployTransaction = StreamingRewardsDistributor.getDeployTransaction(OGUN_TOKEN_ADDRESS);
  const signedTx = await getSignedTransaction(deployTransaction.data);
  const receipt = await sendSignedTransaction(signedTx.raw);

  console.log(`✅ StreamingRewardsDistributor deployed to: ${receipt.contractAddress}`);
  console.log("");

  // If staking contract is set, configure it
  if (STAKING_CONTRACT_ADDRESS) {
    console.log("🔧 Configuring staking contract...");
    // Note: This would require a separate transaction to call setStakingContract
    console.log(`   Staking contract to configure: ${STAKING_CONTRACT_ADDRESS}`);
    console.log("   Run setStakingContract() after deployment");
  }

  console.log("");
  console.log("⏰ Waiting 10 seconds for confirmations...");
  await delay(10000);

  console.log("🪄 Verifying contract on Polygonscan...");

  try {
    await run("verify:verify", {
      address: receipt.contractAddress,
      constructorArguments: [OGUN_TOKEN_ADDRESS],
    });
    console.log("✅ StreamingRewardsDistributor verified on Polygonscan");
  } catch (error) {
    console.log("⚠️  Verification failed (may already be verified):", error.message);
  }

  console.log("");
  console.log("=".repeat(60));
  console.log("    DEPLOYMENT COMPLETE");
  console.log("=".repeat(60));
  console.log("");
  console.log("Next Steps:");
  console.log("1. Fund the contract with OGUN tokens for distribution");
  console.log("2. Call authorizeDistributor() to authorize the backend service");
  console.log("3. If using staking, call setStakingContract()");
  console.log("");
  console.log("Contract Details:");
  console.log(`  Address: ${receipt.contractAddress}`);
  console.log(`  Network: Polygon Mainnet`);
  console.log(`  Owner: ${await getAdminWallet()}`);
  console.log("");
  console.log("Reward Rates (configured in contract):");
  console.log("  NFT Streams: 0.5 OGUN per stream");
  console.log("  Non-NFT Streams: 0.05 OGUN per stream");
  console.log("  Daily Limit: 100 OGUN per track per day");
  console.log("");

  return receipt.contractAddress;
};

main()
  .then((address) => {
    console.log(`Deployed to: ${address}`);
    process.exit(0);
  })
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
