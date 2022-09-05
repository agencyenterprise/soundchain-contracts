import { KmsProvider } from "aws-kms-provider";
import dotenv from "dotenv";
import { ethers, run } from "hardhat";
import Web3 from "web3";

dotenv.config();

const region = "us-east-1";

const { 
  AWS_KMS_KEY_ID,
  POLYGON_ALCHEMY_URL,
  CONTRACT_URI,
  FEE_RECIPIENT_ADDRESS, 
  PLATFORM_FEE, 
  REWARDS_RATE, 
  REWARDS_LIMIT, 
  MERKLE_ROOT, 
  OGUN_TOKEN_ADDRESS,
  DEPLOY_ALL = false,
  DEPLOY_OGUN_TOKEN = false,
  DEPLOY_STAKING = false,
  DEPLOY_AIRDROP = false,
  DEPLOY_SOUNDCHAIN_COLLECTIBLE = false,
  DEPLOY_MARKETPLACE_EDITIONS = false,
  DEPLOY_AUCTION = false,
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

  let contractAddressOGUNToken = OGUN_TOKEN_ADDRESS;

  let SoundchainOGUN20Receipt;
  if (DEPLOY_OGUN_TOKEN || DEPLOY_ALL) {
    console.log("💡 Deploying SoundchainOGUN20");
    const SoundchainOGUN20 = await ethers.getContractFactory("SoundchainOGUN20");
    const SoundchainOGUN20DeployTransaction = SoundchainOGUN20.getDeployTransaction();
    const SoundchainOGUN20Signed = await getSignedTransaction(
      SoundchainOGUN20DeployTransaction.data
    );
    SoundchainOGUN20Receipt = await sendSignedTransaction(
      SoundchainOGUN20Signed.raw
    );
    console.log(
      `✅ SoundchainOGUN20 deployed to address: ${SoundchainOGUN20Receipt.contractAddress}`
    );

    contractAddressOGUNToken = SoundchainOGUN20Receipt.contractAddress;
  }

  let StakingRewardsReceipt;
  const totalOGUNStaking = web3.utils.toWei('200000000'); // 200 million
  if (DEPLOY_STAKING || DEPLOY_ALL) {
    console.log("💡 Deploying StakingRewards");
    const StakingRewards = await ethers.getContractFactory("StakingRewards");
    const StakingRewardsDeployTransaction = StakingRewards.getDeployTransaction(contractAddressOGUNToken, totalOGUNStaking);
    const StakingRewardsSigned = await getSignedTransaction(
      StakingRewardsDeployTransaction.data
    );
    StakingRewardsReceipt = await sendSignedTransaction(
      StakingRewardsSigned.raw
    );
    console.log(
      `✅ StakingRewards deployed to address: ${StakingRewardsReceipt.contractAddress}`
    );
  }

  let airdropReceipt;
  if (DEPLOY_AIRDROP || DEPLOY_ALL) {
    console.log("💡 Deploying Airdrop Contract");
    const AirDropContract = await ethers.getContractFactory("MerkleClaimERC20");
    const airdropTransaction = AirDropContract.getDeployTransaction(OGUN_TOKEN_ADDRESS, MERKLE_ROOT);
    const airdropSigned = await getSignedTransaction(
        airdropTransaction.data
    );
    airdropReceipt = await sendSignedTransaction(
      airdropSigned.raw
    );
    console.log(
      `✅ Airdrop deployed to address: ${airdropReceipt.contractAddress}`
    );  
  }

  let soundchainNFTReceipt;
  if (DEPLOY_SOUNDCHAIN_COLLECTIBLE || DEPLOY_ALL) {
    console.log("💡 Deploying SoundchainCollectible");
    const Soundchain721 = await ethers.getContractFactory("Soundchain721Editions");
    const soundchainNFTDeployTransaction = Soundchain721.getDeployTransaction(CONTRACT_URI);
    const soundchainNFTSigned = await getSignedTransaction(
      soundchainNFTDeployTransaction.data
    );
    soundchainNFTReceipt = await sendSignedTransaction(
      soundchainNFTSigned.raw
    );
    console.log(
      `✅ SoundchainCollectible deployed to address: ${soundchainNFTReceipt.contractAddress}`
    );
  }

  let marketplaceReceipt;
  if (DEPLOY_MARKETPLACE_EDITIONS || DEPLOY_ALL) {
    console.log("💡 Deploying Marketplace");
    const MarketplaceFactory = await ethers.getContractFactory(
      "SoundchainMarketplaceEditions"
    );
    const marketplaceDeployTransaction = MarketplaceFactory.getDeployTransaction(
      FEE_RECIPIENT_ADDRESS,
      contractAddressOGUNToken,
      PLATFORM_FEE,
      REWARDS_RATE,
      REWARDS_LIMIT
    );
    const marketplaceSigned = await getSignedTransaction(
      marketplaceDeployTransaction.data
    );
    marketplaceReceipt = await sendSignedTransaction(marketplaceSigned.raw);
    console.log(
      `✅ Marketplace deployed to address: ${marketplaceReceipt.contractAddress}`
    );
  }

  let auctionReceipt;
  if (DEPLOY_AUCTION || DEPLOY_ALL) {
    console.log("💡 Deploying Auction");
    const AuctionFactory = await ethers.getContractFactory("SoundchainAuction");
    const auctionDeployTransaction = AuctionFactory.getDeployTransaction(
      FEE_RECIPIENT_ADDRESS,
      contractAddressOGUNToken,
      PLATFORM_FEE,
      REWARDS_RATE,
      REWARDS_LIMIT
    );
    const auctionSigned = await getSignedTransaction(
      auctionDeployTransaction.data
    );
    auctionReceipt = await sendSignedTransaction(auctionSigned.raw);
    console.log(
      `✅ Auction deployed to address: ${auctionReceipt.contractAddress}`
    );
  }

  console.log("⏰ Waiting 10 seconds for confirmations...");
  await delay(10000);

  console.log("🪄 Verifying contracts");

  if (SoundchainOGUN20Receipt) {
    await run("verify:verify", {
      address: SoundchainOGUN20Receipt.contractAddress,
      constructorArguments: [],
    });
    console.log("✅ SoundchainOGUN20Contract verified on Etherscan");
  }

  if (StakingRewardsReceipt) {
    await run("verify:verify", {
      address: StakingRewardsReceipt.contractAddress,
      constructorArguments: [ contractAddressOGUNToken, totalOGUNStaking ],
    });
  
    console.log("✅ StakingRewardsContract verified on Etherscan");
  }

  if (airdropReceipt) {
    await run("verify:verify", {
      address: airdropReceipt.contractAddress,
      constructorArguments: [ contractAddressOGUNToken, MERKLE_ROOT ],
    });
  
    console.log("✅ AirDropContract verified on Etherscan");
  }
  
  if (soundchainNFTReceipt) {
    await run("verify:verify", {
      address: soundchainNFTReceipt.contractAddress,
      constructorArguments:
      [
        CONTRACT_URI
      ],
    });
  
    console.log("✅ SoundchainCollectible verified on Etherscan");
  }

  if (marketplaceReceipt) {
    await run("verify:verify", {
      address: marketplaceReceipt.contractAddress,
      constructorArguments:
      [
        FEE_RECIPIENT_ADDRESS,
        contractAddressOGUNToken,
        PLATFORM_FEE,
        REWARDS_RATE,
        REWARDS_LIMIT
      ],
    });
    console.log("✅ Marketplace verified on Etherscan");
  }

  if (auctionReceipt) {
    await run("verify:verify", {
      address: auctionReceipt.contractAddress,
      constructorArguments:
      [
        FEE_RECIPIENT_ADDRESS,
        contractAddressOGUNToken,
        PLATFORM_FEE,
        REWARDS_RATE,
        REWARDS_LIMIT
      ],
    });
    console.log("✅ Auction verified on Etherscan");
  }
};

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
