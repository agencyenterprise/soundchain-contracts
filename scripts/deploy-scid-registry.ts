import { ethers, upgrades } from "hardhat";

/**
 * SCidRegistry Deployment Script
 *
 * Deploys the SCidRegistry as a UUPS upgradeable proxy.
 *
 * Usage:
 *   npx hardhat run scripts/deploy-scid-registry.ts --network polygon
 *   npx hardhat run scripts/deploy-scid-registry.ts --network base
 *   npx hardhat run scripts/deploy-scid-registry.ts --network zetachain
 */

// Chain codes matching SCidGenerator.ts
const CHAIN_CODES: Record<string, number> = {
  polygon: 0,      // POL
  zetachain: 1,    // ZET
  ethereum: 2,     // ETH
  base: 3,         // BAS
  solana: 4,       // SOL
  bsc: 5,          // BNB
  avalanche: 6,    // AVA
  arbitrum: 7,     // ARB
};

async function main() {
  const [deployer] = await ethers.getSigners();
  const network = await ethers.provider.getNetwork();

  console.log("=".repeat(60));
  console.log("SCidRegistry Deployment");
  console.log("=".repeat(60));
  console.log("Network:", network.name, `(chainId: ${network.chainId})`);
  console.log("Deployer:", deployer.address);

  const balance = await ethers.provider.getBalance(deployer.address);
  console.log("Balance:", ethers.utils.formatEther(balance), "ETH");
  console.log("=".repeat(60));

  // Determine chain code
  const chainCode = CHAIN_CODES[network.name] ?? 0; // Default to POL
  console.log("Chain Code:", chainCode);

  // Fee collector (can be updated later)
  // Using SoundchainFeeCollector if deployed, otherwise deployer
  const feeCollector = deployer.address; // TODO: Update to actual fee collector

  console.log("Fee Collector:", feeCollector);
  console.log("");

  // Deploy SCidRegistry with UUPS proxy
  console.log("Deploying SCidRegistry...");

  const SCidRegistry = await ethers.getContractFactory("SCidRegistry");

  const scidRegistry = await upgrades.deployProxy(
    SCidRegistry,
    [chainCode, feeCollector],
    {
      kind: "uups",
      initializer: "initialize",
    }
  );

  await scidRegistry.deployed();

  console.log("");
  console.log("=".repeat(60));
  console.log("Deployment Complete!");
  console.log("=".repeat(60));
  console.log("Proxy Address:", scidRegistry.address);

  // Get implementation address
  const implementationAddress = await upgrades.erc1967.getImplementationAddress(
    scidRegistry.address
  );
  console.log("Implementation Address:", implementationAddress);

  // Get admin address
  const adminAddress = await upgrades.erc1967.getAdminAddress(
    scidRegistry.address
  );
  console.log("Admin Address:", adminAddress);
  console.log("=".repeat(60));

  // Verify initial state
  console.log("");
  console.log("Verifying initial state...");
  console.log("- Version:", await scidRegistry.VERSION());
  console.log("- Chain Code:", await scidRegistry.chainCode());
  console.log("- Total Registrations:", (await scidRegistry.totalRegistrations()).toString());
  console.log("- Registration Fee:", ethers.utils.formatEther(await scidRegistry.registrationFee()));
  console.log("- Deployer is Registrar:", await scidRegistry.registrars(deployer.address));
  console.log("");

  // Output deployment info for verification
  console.log("=".repeat(60));
  console.log("Contract Verification Command:");
  console.log("=".repeat(60));
  console.log(`npx hardhat verify --network ${network.name} ${implementationAddress}`);
  console.log("");

  // Save deployment info
  const deploymentInfo = {
    network: network.name,
    chainId: network.chainId.toString(),
    chainCode,
    proxyAddress: scidRegistry.address,
    implementationAddress,
    adminAddress,
    feeCollector,
    deployer: deployer.address,
    deployedAt: new Date().toISOString(),
    version: 1,
  };

  console.log("Deployment Info (save this!):");
  console.log(JSON.stringify(deploymentInfo, null, 2));

  return deploymentInfo;
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
