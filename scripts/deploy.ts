import { ethers, upgrades } from "hardhat";
import dotenv from "dotenv";

dotenv.config();

const { FEE_RECIPIENT_ADDRESS, PLATFORM_FEE } = process.env;

const main = async () => {
  console.log("Deploying SoundchainCollectible");
  const SoundchainCollectible = await ethers.getContractFactory(
    "SoundchainCollectible"
  );
  const soundchainCollectible = await SoundchainCollectible.deploy();
  console.log("Contract deployed to address: ", soundchainCollectible.address);

  console.log("Deploying Marketplace");
  const MarketplaceFactory = await ethers.getContractFactory(
    "SoundchainMarketplace"
  );
  const marketplace = await upgrades.deployProxy(MarketplaceFactory, [
    FEE_RECIPIENT_ADDRESS,
    PLATFORM_FEE,
  ]);
  console.log("Marketplace deployed to address: ", marketplace.address);
};

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
