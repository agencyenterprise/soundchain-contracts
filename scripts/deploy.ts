import { KmsProvider } from "aws-kms-provider";
import dotenv from "dotenv";
import { ethers, run } from "hardhat";
import Web3 from "web3";

dotenv.config();

const region = "us-east-1";

const { AWS_KMS_KEY_ID, POLYGON_ALCHEMY_URL } = process.env;

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
    type: 0, // for building a legacy transaction
    from,
    data,
    nonce,
  };
  return await web3.eth.signTransaction(transaction, from);
};

const sendSignedTransaction = async (signedTransaction) => {
  return await web3.eth.sendSignedTransaction(signedTransaction);
};

const { FEE_RECIPIENT_ADDRESS, PLATFORM_FEE } = process.env;

const delay = (ms) => new Promise((res) => setTimeout(res, ms));

const main = async () => {
  console.log("💡 Deploying SoundchainCollectible");
  const SoundchainCollectible = await ethers.getContractFactory(
    "SoundchainCollectible"
  );
  const soundchainNFTDeployTransaction =
    SoundchainCollectible.getDeployTransaction();
  const soundchainNFTSigned = await getSignedTransaction(
    soundchainNFTDeployTransaction.data
  );
  const soundchainNFTReceipt = await sendSignedTransaction(
    soundchainNFTSigned.raw
  );
  console.log(
    `✅ SoundchainCollectible deployed to address: ${soundchainNFTReceipt.contractAddress}`
  );

  console.log("💡 Deploying Marketplace");
  const MarketplaceFactory = await ethers.getContractFactory(
    "SoundchainMarketplace"
  );
  const marketplaceDeployTransaction = MarketplaceFactory.getDeployTransaction(
    FEE_RECIPIENT_ADDRESS,
    PLATFORM_FEE
  );
  const marketplaceSigned = await getSignedTransaction(
    marketplaceDeployTransaction.data
  );
  const marketplaceReceipt = await sendSignedTransaction(marketplaceSigned.raw);
  console.log(
    `✅ Marketplace deployed to address: ${marketplaceReceipt.contractAddress}`
  );

  console.log("⏰ Waiting confirmations");
  await delay(240000);

  console.log("🪄  Verifying contracts");

  await run("verify:verify", {
    address: soundchainNFTReceipt.contractAddress,
  });
  console.log("✅ SoundchainCollectible verified on Etherscan");

  await run("verify:verify", {
    address: marketplaceReceipt.contractAddress,
    constructorArguments: [FEE_RECIPIENT_ADDRESS, PLATFORM_FEE],
  });
  console.log("✅ Marketplace verified on Etherscan");
};

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
