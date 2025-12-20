import { ethers, upgrades } from "hardhat";

/**
 * OmnichainRouter Deployment Script
 *
 * Deploys the "Grand Central Station" for all SoundChain cross-chain operations.
 * This contract coordinates all marketplace, swap, and NFT operations across 23+ chains.
 *
 * Usage:
 *   npx hardhat run scripts/deploy-omnichain-router.ts --network zetachain
 */

// ZetaChain Gateway addresses
const ZETACHAIN_GATEWAYS: Record<number, string> = {
  7000: "0x48bEe5e48d30D2017B3c6f3e1C3B8ddF0E94D7C5", // ZetaChain Mainnet Gateway
  7001: "0x5F0b1a82749cb4E2278EC87F8BF6B618dC71a8bf", // ZetaChain Testnet Gateway
};

async function main() {
  const [deployer] = await ethers.getSigners();
  const network = await ethers.provider.getNetwork();

  console.log("=".repeat(70));
  console.log("OmnichainRouter Deployment - Grand Central Station");
  console.log("=".repeat(70));
  console.log("Network:", network.name, `(chainId: ${network.chainId})`);
  console.log("Deployer:", deployer.address);

  const balance = await ethers.provider.getBalance(deployer.address);
  console.log("Balance:", ethers.utils.formatEther(balance), network.chainId === 7000 ? "ZETA" : "ETH");
  console.log("=".repeat(70));

  // Verify we're on ZetaChain (recommended)
  if (network.chainId !== 7000 && network.chainId !== 7001) {
    console.log("⚠️  WARNING: OmnichainRouter should be deployed on ZetaChain for optimal cross-chain routing.");
    console.log("   Current network:", network.name);
    console.log("   Continuing anyway...");
    console.log("");
  }

  // Configuration
  const gateway = ZETACHAIN_GATEWAYS[network.chainId] || process.env.GATEWAY_ADDRESS || ethers.constants.AddressZero;
  const feeCollector = process.env.FEE_COLLECTOR || deployer.address;

  console.log("Gateway Address:", gateway);
  console.log("Fee Collector:", feeCollector);
  console.log("");

  if (gateway === ethers.constants.AddressZero) {
    console.log("⚠️  WARNING: Gateway not set. Cross-chain functionality will be limited.");
    console.log("   Set GATEWAY_ADDRESS in environment or update after deployment.");
    console.log("");
  }

  // Deploy OmnichainRouter with UUPS proxy
  console.log("Deploying OmnichainRouter...");

  const OmnichainRouter = await ethers.getContractFactory("OmnichainRouter");

  const router = await upgrades.deployProxy(
    OmnichainRouter,
    [gateway || deployer.address, feeCollector], // Use deployer if no gateway
    {
      kind: "uups",
      initializer: "initialize",
    }
  );

  await router.deployed();

  console.log("");
  console.log("=".repeat(70));
  console.log("🚀 Deployment Complete!");
  console.log("=".repeat(70));
  console.log("Proxy Address:", router.address);

  const implementationAddress = await upgrades.erc1967.getImplementationAddress(
    router.address
  );
  console.log("Implementation Address:", implementationAddress);

  // Verify initial state
  console.log("");
  console.log("Verifying initial state...");
  console.log("- Version:", await router.VERSION());
  console.log("- Platform Fee:", (await router.platformFee()).toString(), "basis points (0.05%)");
  console.log("- Gateway:", await router.gateway());
  console.log("- Fee Collector:", await router.feeCollector());

  // Get enabled chains
  const enabledChains = await router.getEnabledChains();
  console.log("- Enabled Chains:", enabledChains.length);
  console.log("  Chains:", enabledChains.map((c: any) => c.toString()).join(", "));
  console.log("");

  // Show chain breakdown
  console.log("=".repeat(70));
  console.log("Supported Chains (23+):");
  console.log("=".repeat(70));

  const CHAIN_NAMES: Record<string, string> = {
    "1": "Ethereum",
    "137": "Polygon",
    "42161": "Arbitrum",
    "10": "Optimism",
    "8453": "Base",
    "43114": "Avalanche",
    "56": "BSC",
    "250": "Fantom",
    "7000": "ZetaChain",
    "81457": "Blast",
    "59144": "Linea",
    "534352": "Scroll",
    "324": "zkSync",
    "5000": "Mantle",
    "169": "Manta",
    "34443": "Mode",
    "42220": "Celo",
    "100": "Gnosis",
    "1284": "Moonbeam",
    "1313161554": "Aurora",
    "25": "Cronos",
    "2222": "Kava",
    "1088": "Metis",
  };

  for (const chainId of enabledChains) {
    const config = await router.getChainConfig(chainId);
    const name = CHAIN_NAMES[chainId.toString()] || `Chain ${chainId}`;
    console.log(`  ✓ ${name} (${chainId}): ${config.enabled ? "enabled" : "disabled"}`);
  }

  console.log("");
  console.log("=".repeat(70));
  console.log("Route Types Supported:");
  console.log("=".repeat(70));
  console.log("  0: PURCHASE        - Single NFT purchase");
  console.log("  1: BUNDLE_PURCHASE - Multiple NFTs bundle");
  console.log("  2: SWEEP           - Floor sweep");
  console.log("  3: SWAP            - Token swap");
  console.log("  4: ROYALTY_CLAIM   - Claim royalties");
  console.log("  5: BRIDGE_NFT      - Bridge NFT cross-chain");
  console.log("  6: AIRDROP         - Multi-recipient airdrop");
  console.log("  7: SCID_REGISTER   - Register SCid on-chain");
  console.log("");

  console.log("=".repeat(70));
  console.log("Contract Verification Command:");
  console.log("=".repeat(70));
  console.log(`npx hardhat verify --network ${network.name} ${implementationAddress}`);
  console.log("");

  const deploymentInfo = {
    network: network.name,
    chainId: network.chainId.toString(),
    proxyAddress: router.address,
    implementationAddress,
    gateway,
    feeCollector,
    enabledChains: enabledChains.map((c: any) => c.toString()),
    deployer: deployer.address,
    deployedAt: new Date().toISOString(),
    version: 1,
  };

  console.log("=".repeat(70));
  console.log("Deployment Info (save this!):");
  console.log("=".repeat(70));
  console.log(JSON.stringify(deploymentInfo, null, 2));

  return deploymentInfo;
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
