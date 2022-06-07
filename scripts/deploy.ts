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
    from,
    data,
    nonce,
  };
  return await web3.eth.signTransaction(transaction, from);
};

const sendSignedTransaction = async (signedTransaction) => {
  return await web3.eth.sendSignedTransaction(signedTransaction);
};

const { FEE_RECIPIENT_ADDRESS, PLATFORM_FEE, OGUN_TOKEN_ADDRESS_MUMBAI, REWARDS_RATE, REWARDS_LIMIT } = process.env;

const delay = (ms) => new Promise((res) => setTimeout(res, ms));

const main = async () => {
  console.log("💡 Deploying SoundchainCollectible");
  const Soundchain721 = await ethers.getContractFactory("Soundchain721Editions");
  const soundchainNFTDeployTransaction = Soundchain721.getDeployTransaction();
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
    "SoundchainMarketplaceEditions"
  );
  const marketplaceDeployTransaction = MarketplaceFactory.getDeployTransaction(
    FEE_RECIPIENT_ADDRESS,
    OGUN_TOKEN_ADDRESS_MUMBAI,
    PLATFORM_FEE,
    REWARDS_RATE,
    REWARDS_LIMIT
  );
  const marketplaceSigned = await getSignedTransaction(
    marketplaceDeployTransaction.data
  );
  const marketplaceReceipt = await sendSignedTransaction(marketplaceSigned.raw);
  console.log(
    `✅ Marketplace deployed to address: ${marketplaceReceipt.contractAddress}`
  );

  console.log("💡 Deploying Auction");
  const AuctionFactory = await ethers.getContractFactory("SoundchainAuction");
  const auctionDeployTransaction = AuctionFactory.getDeployTransaction(
    FEE_RECIPIENT_ADDRESS,
    OGUN_TOKEN_ADDRESS_MUMBAI,
    PLATFORM_FEE,
    REWARDS_RATE,
    REWARDS_LIMIT
  );
  const auctionSigned = await getSignedTransaction(
    auctionDeployTransaction.data
  );
  const auctionReceipt = await sendSignedTransaction(auctionSigned.raw);
  console.log(
    `✅ Auction deployed to address: ${auctionReceipt.contractAddress}`
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
    constructorArguments: 
    [
      FEE_RECIPIENT_ADDRESS,
      OGUN_TOKEN_ADDRESS_MUMBAI,
      PLATFORM_FEE,
      REWARDS_RATE,
      REWARDS_LIMIT
    ],
  });
  console.log("✅ Marketplace verified on Etherscan");

  await run("verify:verify", {
    address: auctionReceipt.contractAddress,
    constructorArguments:  
    [
      FEE_RECIPIENT_ADDRESS,
      OGUN_TOKEN_ADDRESS_MUMBAI,
      PLATFORM_FEE,
      REWARDS_RATE,
      REWARDS_LIMIT
    ],
  });
  console.log("✅ Auction verified on Etherscan");
};

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
