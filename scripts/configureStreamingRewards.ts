import { KmsProvider } from "aws-kms-provider";
import dotenv from "dotenv";
import Web3 from "web3";

dotenv.config();

const region = "us-east-1";

const {
  AWS_KMS_KEY_ID,
  POLYGON_ALCHEMY_URL,
} = process.env;

// StreamingRewardsDistributor deployed address (v2 - correct OGUN token)
const STREAMING_REWARDS_ADDRESS = "0xcf9416c49D525f7a50299c71f33606A158F28546";

// KMS Wallet (owner) - using as both treasury and initial distributor
const KMS_WALLET = "0x835669972891a3766f75ee76f9bb8c091b68a5ab";

// ABI for configuration functions
const CONFIG_ABI = [
  {
    "inputs": [{"name": "feeBps", "type": "uint256"}, {"name": "feeRecipient", "type": "address"}],
    "name": "setProtocolFee",
    "outputs": [],
    "stateMutability": "nonpayable",
    "type": "function"
  },
  {
    "inputs": [{"name": "distributor", "type": "address"}],
    "name": "authorizeDistributor",
    "outputs": [],
    "stateMutability": "nonpayable",
    "type": "function"
  },
  {
    "inputs": [],
    "name": "protocolFeeBps",
    "outputs": [{"name": "", "type": "uint256"}],
    "stateMutability": "view",
    "type": "function"
  },
  {
    "inputs": [],
    "name": "protocolFeeRecipient",
    "outputs": [{"name": "", "type": "address"}],
    "stateMutability": "view",
    "type": "function"
  },
  {
    "inputs": [{"name": "", "type": "address"}],
    "name": "authorizedDistributors",
    "outputs": [{"name": "", "type": "bool"}],
    "stateMutability": "view",
    "type": "function"
  }
];

const provider = new KmsProvider(POLYGON_ALCHEMY_URL, {
  region,
  keyIds: [AWS_KMS_KEY_ID],
});

const web3 = new Web3(provider);

const getAdminWallet = async () => {
  const accounts = await web3.eth.getAccounts();
  return accounts[0];
};

const delay = (ms: number) => new Promise((res) => setTimeout(res, ms));

const main = async () => {
  console.log("=".repeat(60));
  console.log("    STREAMING REWARDS CONFIGURATION");
  console.log("=".repeat(60));
  console.log("");

  const adminWallet = await getAdminWallet();
  console.log("Admin Wallet (KMS):", adminWallet);
  console.log("Contract:", STREAMING_REWARDS_ADDRESS);
  console.log("");

  const contract = new web3.eth.Contract(CONFIG_ABI as any, STREAMING_REWARDS_ADDRESS);

  // Step 1: Set Protocol Fee (0.05% = 5 basis points)
  console.log("📊 Step 1: Setting protocol fee to 0.05% (5 bps)...");
  console.log("   Treasury:", KMS_WALLET);

  try {
    const setFeeData = contract.methods.setProtocolFee(5, KMS_WALLET).encodeABI();
    const nonce1 = await web3.eth.getTransactionCount(adminWallet);
    const gasPrice = await web3.eth.getGasPrice();

    const tx1 = {
      from: adminWallet,
      to: STREAMING_REWARDS_ADDRESS,
      data: setFeeData,
      nonce: nonce1,
      gas: 100000,
      gasPrice,
    };

    const signed1 = await web3.eth.signTransaction(tx1, adminWallet);
    const receipt1 = await web3.eth.sendSignedTransaction(signed1.raw);
    console.log("✅ Protocol fee set! Tx:", receipt1.transactionHash);
  } catch (error: any) {
    console.log("⚠️  Set fee error:", error.message);
  }

  await delay(3000);

  // Step 2: Authorize the KMS wallet as distributor
  console.log("");
  console.log("🔑 Step 2: Authorizing distributor...");
  console.log("   Distributor:", KMS_WALLET);

  try {
    const authData = contract.methods.authorizeDistributor(KMS_WALLET).encodeABI();
    const nonce2 = await web3.eth.getTransactionCount(adminWallet);
    const gasPrice = await web3.eth.getGasPrice();

    const tx2 = {
      from: adminWallet,
      to: STREAMING_REWARDS_ADDRESS,
      data: authData,
      nonce: nonce2,
      gas: 100000,
      gasPrice,
    };

    const signed2 = await web3.eth.signTransaction(tx2, adminWallet);
    const receipt2 = await web3.eth.sendSignedTransaction(signed2.raw);
    console.log("✅ Distributor authorized! Tx:", receipt2.transactionHash);
  } catch (error: any) {
    console.log("⚠️  Authorization error:", error.message);
  }

  await delay(3000);

  // Verify configuration
  console.log("");
  console.log("🔍 Verifying configuration...");

  try {
    const feeBps = await contract.methods.protocolFeeBps().call();
    const feeRecipient = await contract.methods.protocolFeeRecipient().call();
    const isAuthorized = await contract.methods.authorizedDistributors(KMS_WALLET).call();

    console.log("   Protocol Fee:", feeBps, "bps (", Number(feeBps) / 100, "% )");
    console.log("   Fee Recipient:", feeRecipient);
    console.log("   KMS Authorized:", isAuthorized);
  } catch (error: any) {
    console.log("   Verification error:", error.message);
  }

  console.log("");
  console.log("=".repeat(60));
  console.log("    CONFIGURATION COMPLETE");
  console.log("=".repeat(60));
  console.log("");
  console.log("Next step: Fund contract with OGUN tokens");
  console.log("Run: npx hardhat run scripts/fundStreamingRewards.ts --network polygon");
  console.log("");
};

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
