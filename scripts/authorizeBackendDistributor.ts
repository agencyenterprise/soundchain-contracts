import { KmsProvider } from "aws-kms-provider";
import dotenv from "dotenv";
import Web3 from "web3";

dotenv.config();

const region = "us-east-1";

const {
  AWS_KMS_KEY_ID,
  POLYGON_ALCHEMY_URL,
} = process.env;

// StreamingRewardsDistributor deployed address (v2)
const STREAMING_REWARDS_ADDRESS = "0xcf9416c49D525f7a50299c71f33606A158F28546";

// Backend wallet to authorize for Piggy Bank claims
const BACKEND_WALLET = "0xf93160bFcb223235Ea4fdA5D9E069B98C0205Fb6";

// ABI for authorization functions
const AUTH_ABI = [
  {
    "inputs": [{"name": "distributor", "type": "address"}],
    "name": "authorizeDistributor",
    "outputs": [],
    "stateMutability": "nonpayable",
    "type": "function"
  },
  {
    "inputs": [{"name": "", "type": "address"}],
    "name": "authorizedDistributors",
    "outputs": [{"name": "", "type": "bool"}],
    "stateMutability": "view",
    "type": "function"
  },
  {
    "inputs": [],
    "name": "owner",
    "outputs": [{"name": "", "type": "address"}],
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

const main = async () => {
  console.log("=".repeat(60));
  console.log("    AUTHORIZE BACKEND WALLET FOR PIGGY BANK CLAIMS");
  console.log("=".repeat(60));
  console.log("");

  // Get KMS wallet address
  const adminWallet = await getAdminWallet();
  console.log("KMS Wallet (Owner):", adminWallet);
  console.log("Contract:", STREAMING_REWARDS_ADDRESS);
  console.log("Backend Wallet to Authorize:", BACKEND_WALLET);
  console.log("");

  const contract = new web3.eth.Contract(AUTH_ABI as any, STREAMING_REWARDS_ADDRESS);

  // Step 1: Verify ownership
  console.log("🔍 Step 1: Verifying contract ownership...");
  try {
    const owner = await contract.methods.owner().call();
    console.log("   Contract Owner:", owner);

    if (owner.toLowerCase() !== adminWallet.toLowerCase()) {
      console.error("❌ ERROR: KMS wallet is NOT the contract owner!");
      console.error("   Expected:", adminWallet);
      console.error("   Actual:", owner);
      process.exit(1);
    }
    console.log("✅ Ownership verified!");
  } catch (error: any) {
    console.log("⚠️  Could not verify ownership:", error.message);
  }

  console.log("");

  // Step 2: Check if already authorized
  console.log("🔍 Step 2: Checking current authorization status...");
  try {
    const isAlreadyAuthorized = await contract.methods.authorizedDistributors(BACKEND_WALLET).call();
    console.log("   Currently Authorized:", isAlreadyAuthorized);

    if (isAlreadyAuthorized) {
      console.log("✅ Backend wallet is ALREADY authorized! No action needed.");
      process.exit(0);
    }
  } catch (error: any) {
    console.log("⚠️  Could not check status:", error.message);
  }

  console.log("");

  // Step 3: Authorize the backend wallet
  console.log("🔑 Step 3: Authorizing backend wallet...");
  console.log("   Wallet:", BACKEND_WALLET);

  try {
    const authData = contract.methods.authorizeDistributor(BACKEND_WALLET).encodeABI();
    const nonce = await web3.eth.getTransactionCount(adminWallet);
    const gasPrice = await web3.eth.getGasPrice();

    console.log("   Nonce:", nonce);
    console.log("   Gas Price:", gasPrice, "wei");

    const tx = {
      from: adminWallet,
      to: STREAMING_REWARDS_ADDRESS,
      data: authData,
      nonce: nonce,
      gas: 100000,
      gasPrice,
    };

    console.log("   Signing transaction with AWS KMS...");
    const signed = await web3.eth.signTransaction(tx, adminWallet);

    console.log("   Broadcasting transaction...");
    const receipt = await web3.eth.sendSignedTransaction(signed.raw);

    console.log("✅ Transaction successful!");
    console.log("   TX Hash:", receipt.transactionHash);
    console.log("   Block:", receipt.blockNumber);
    console.log("   Gas Used:", receipt.gasUsed);
  } catch (error: any) {
    console.error("❌ Authorization failed:", error.message);
    process.exit(1);
  }

  console.log("");

  // Step 4: Verify authorization
  console.log("🔍 Step 4: Verifying authorization...");
  try {
    const isAuthorized = await contract.methods.authorizedDistributors(BACKEND_WALLET).call();
    console.log("   Backend Wallet Authorized:", isAuthorized);

    if (isAuthorized) {
      console.log("✅ SUCCESS! Backend wallet is now authorized to distribute rewards.");
    } else {
      console.log("⚠️  WARNING: Authorization may not have taken effect yet.");
    }
  } catch (error: any) {
    console.log("   Verification error:", error.message);
  }

  console.log("");
  console.log("=".repeat(60));
  console.log("    AUTHORIZATION COMPLETE");
  console.log("=".repeat(60));
  console.log("");
  console.log("Next steps:");
  console.log("1. Test Piggy Bank claim flow in the app");
  console.log("2. Backend wallet can now call distributeRewards()");
  console.log("");
};

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
