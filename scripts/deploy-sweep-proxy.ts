import { ethers, upgrades } from "hardhat";

/**
 * SweepProxy Deployment Script
 *
 * Deploys the SweepProxy as a UUPS upgradeable proxy.
 *
 * Usage:
 *   npx hardhat run scripts/deploy-sweep-proxy.ts --network polygon
 */

async function main() {
  const [deployer] = await ethers.getSigners();
  const network = await ethers.provider.getNetwork();

  console.log("=".repeat(60));
  console.log("SweepProxy Deployment");
  console.log("=".repeat(60));
  console.log("Network:", network.name, `(chainId: ${network.chainId})`);
  console.log("Deployer:", deployer.address);

  const balance = await ethers.provider.getBalance(deployer.address);
  console.log("Balance:", ethers.utils.formatEther(balance), "ETH");
  console.log("=".repeat(60));

  // Configuration
  const feeCollector = process.env.FEE_COLLECTOR || deployer.address;
  const platformFee = 50; // 0.5% in basis points

  console.log("Fee Collector:", feeCollector);
  console.log("Platform Fee:", platformFee, "basis points (0.5%)");
  console.log("");

  // Deploy SweepProxy with UUPS proxy
  console.log("Deploying SweepProxy...");

  const SweepProxy = await ethers.getContractFactory("SweepProxy");

  const sweepProxy = await upgrades.deployProxy(
    SweepProxy,
    [feeCollector, platformFee],
    {
      kind: "uups",
      initializer: "initialize",
    }
  );

  await sweepProxy.deployed();

  console.log("");
  console.log("=".repeat(60));
  console.log("Deployment Complete!");
  console.log("=".repeat(60));
  console.log("Proxy Address:", sweepProxy.address);

  const implementationAddress = await upgrades.erc1967.getImplementationAddress(
    sweepProxy.address
  );
  console.log("Implementation Address:", implementationAddress);

  // Verify initial state
  console.log("");
  console.log("Verifying initial state...");
  console.log("- Version:", await sweepProxy.VERSION());
  console.log("- Platform Fee:", (await sweepProxy.platformFee()).toString(), "basis points");
  console.log("- Max Sweep Size:", (await sweepProxy.maxSweepSize()).toString());
  console.log("");

  console.log("=".repeat(60));
  console.log("Contract Verification Command:");
  console.log("=".repeat(60));
  console.log(`npx hardhat verify --network ${network.name} ${implementationAddress}`);

  return {
    network: network.name,
    chainId: network.chainId.toString(),
    proxyAddress: sweepProxy.address,
    implementationAddress,
    feeCollector,
    platformFee,
    deployer: deployer.address,
    deployedAt: new Date().toISOString(),
  };
}

main()
  .then((result) => {
    console.log("\nDeployment Info:");
    console.log(JSON.stringify(result, null, 2));
    process.exit(0);
  })
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
