import dotenv from "dotenv";
import { ethers, run, upgrades } from "hardhat";

dotenv.config();

const { FEE_RECIPIENT_ADDRESS, PLATFORM_FEE } = process.env;

const delay = (ms) => new Promise((res) => setTimeout(res, ms));

const main = async () => {
  console.log("💡 Deploying SoundchainCollectible");
  const SoundchainCollectible = await ethers.getContractFactory(
    "SoundchainCollectible"
  );
  const soundchainCollectible = await SoundchainCollectible.deploy();
  console.log(
    `✅ SoundchainCollectible deployed to address: ${soundchainCollectible.address}`
  );

  console.log("💡 Deploying Marketplace");
  const MarketplaceFactory = await ethers.getContractFactory(
    "SoundchainMarketplace"
  );
  const marketplace = await upgrades.deployProxy(MarketplaceFactory, [
    FEE_RECIPIENT_ADDRESS,
    PLATFORM_FEE,
  ]);
  console.log(`✅ Marketplace deployed to address: ${marketplace.address}`);

  console.log("⏰ Waiting confirmations");
  await delay(240000);

  console.log("🪄  Verifying contracts");

  await run("verify:verify", {
    address: soundchainCollectible.address,
  });
  console.log("✅ SoundchainCollectible verified on Etherscan");
};

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
