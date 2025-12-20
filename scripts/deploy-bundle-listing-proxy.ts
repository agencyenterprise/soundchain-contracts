import { ethers, upgrades } from "hardhat";

/**
 * BundleListingProxy Deployment Script
 *
 * Deploys the advanced bundle listing system with tiered pricing.
 *
 * Usage:
 *   npx hardhat run scripts/deploy-bundle-listing-proxy.ts --network polygon
 */

async function main() {
  const [deployer] = await ethers.getSigners();
  const network = await ethers.provider.getNetwork();
  const chainId = network.chainId;

  console.log("=".repeat(60));
  console.log("BundleListingProxy Deployment");
  console.log("=".repeat(60));
  console.log("Network:", network.name, `(chainId: ${chainId})`);
  console.log("Deployer:", deployer.address);

  const balance = await ethers.provider.getBalance(deployer.address);
  console.log("Balance:", ethers.utils.formatEther(balance), "ETH");
  console.log("=".repeat(60));

  // Configuration
  const omnichainRouter = process.env.OMNICHAIN_ROUTER || ethers.constants.AddressZero;
  const feeCollector = process.env.FEE_COLLECTOR || deployer.address;
  const platformFee = 50; // 0.5% in basis points

  console.log("OmnichainRouter:", omnichainRouter);
  console.log("Fee Collector:", feeCollector);
  console.log("Platform Fee:", platformFee, "basis points (0.5%)");
  console.log("");

  // Deploy BundleListingProxy with UUPS proxy
  console.log("Deploying BundleListingProxy...");

  const BundleListingProxy = await ethers.getContractFactory("BundleListingProxy");

  const proxy = await upgrades.deployProxy(
    BundleListingProxy,
    [omnichainRouter, feeCollector, platformFee],
    {
      kind: "uups",
      initializer: "initialize",
    }
  );

  await proxy.deployed();

  console.log("");
  console.log("=".repeat(60));
  console.log("🚀 Deployment Complete!");
  console.log("=".repeat(60));
  console.log("Proxy Address:", proxy.address);

  const implementationAddress = await upgrades.erc1967.getImplementationAddress(
    proxy.address
  );
  console.log("Implementation Address:", implementationAddress);

  // Verify initial state
  console.log("");
  console.log("Verifying initial state...");
  console.log("- Version:", await proxy.VERSION());
  console.log("- Platform Fee:", (await proxy.platformFee()).toString(), "basis points");
  console.log("- OmnichainRouter:", await proxy.omnichainRouter());
  console.log("- Fee Collector:", await proxy.feeCollector());
  console.log("");

  // Show tier configurations
  console.log("=".repeat(60));
  console.log("Bundle Tiers:");
  console.log("=".repeat(60));

  const tierNames = ["STANDARD", "BRONZE", "SILVER", "GOLD", "PLATINUM", "DIAMOND"];
  for (let i = 0; i < tierNames.length; i++) {
    try {
      const tier = await proxy.getTier(i);
      console.log(`  ${tierNames[i]}:`);
      console.log(`    - Name: ${tier.name}`);
      console.log(`    - Max NFTs: ${tier.maxNfts}`);
      console.log(`    - Max Chains: ${tier.maxChains}`);
      console.log(`    - Fee Discount: ${tier.feeDiscount} basis points`);
      console.log(`    - Min Price: ${ethers.utils.formatEther(tier.minPrice)} ETH`);
    } catch {
      // Tier not configured
    }
  }
  console.log("");

  // Show bundle types
  console.log("=".repeat(60));
  console.log("Bundle Types Supported:");
  console.log("=".repeat(60));
  console.log("  0: ALBUM          - Full album of tracks");
  console.log("  1: EP             - Extended play (3-6 tracks)");
  console.log("  2: COLLECTION     - Curated collection");
  console.log("  3: COLLABORATION  - Multi-artist collaboration");
  console.log("  4: LIMITED_EDITION - Limited edition bundle");
  console.log("  5: CROSS_CHAIN    - Cross-chain bundle");
  console.log("");

  console.log("=".repeat(60));
  console.log("Contract Verification Command:");
  console.log("=".repeat(60));
  console.log(`npx hardhat verify --network ${network.name} ${implementationAddress}`);
  console.log("");

  const deploymentInfo = {
    network: network.name,
    chainId: chainId.toString(),
    proxyAddress: proxy.address,
    implementationAddress,
    omnichainRouter,
    feeCollector,
    platformFee,
    deployer: deployer.address,
    deployedAt: new Date().toISOString(),
    features: {
      bundleTypes: ["ALBUM", "EP", "COLLECTION", "COLLABORATION", "LIMITED_EDITION", "CROSS_CHAIN"],
      tiers: tierNames,
      maxNftsPerBundle: 100,
      maxCollaborators: 20,
    },
  };

  console.log("=".repeat(60));
  console.log("Deployment Info (save this!):");
  console.log("=".repeat(60));
  console.log(JSON.stringify(deploymentInfo, null, 2));

  return deploymentInfo;
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
