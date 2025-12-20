import { ethers, upgrades } from "hardhat";

/**
 * ChainConnector Deployment Script
 *
 * Deploys the lightweight ChainConnector on each supported chain.
 * This is the "spoke" contract that relays messages to/from ZetaChain.
 *
 * Usage:
 *   npx hardhat run scripts/deploy-chain-connector.ts --network ethereum
 *   npx hardhat run scripts/deploy-chain-connector.ts --network polygon
 *   npx hardhat run scripts/deploy-chain-connector.ts --network base
 *   ... (repeat for each chain)
 */

// Chain configurations
const CHAIN_CONFIGS: Record<number, { name: string; gateway: string }> = {
  // Mainnets
  1: { name: "Ethereum", gateway: "0x48bEe5e48d30D2017B3c6f3e1C3B8ddF0E94D7C5" },
  137: { name: "Polygon", gateway: "0x48bEe5e48d30D2017B3c6f3e1C3B8ddF0E94D7C5" },
  42161: { name: "Arbitrum", gateway: "0x48bEe5e48d30D2017B3c6f3e1C3B8ddF0E94D7C5" },
  10: { name: "Optimism", gateway: "0x48bEe5e48d30D2017B3c6f3e1C3B8ddF0E94D7C5" },
  8453: { name: "Base", gateway: "0x48bEe5e48d30D2017B3c6f3e1C3B8ddF0E94D7C5" },
  43114: { name: "Avalanche", gateway: "0x48bEe5e48d30D2017B3c6f3e1C3B8ddF0E94D7C5" },
  56: { name: "BSC", gateway: "0x48bEe5e48d30D2017B3c6f3e1C3B8ddF0E94D7C5" },
  250: { name: "Fantom", gateway: "0x48bEe5e48d30D2017B3c6f3e1C3B8ddF0E94D7C5" },
  81457: { name: "Blast", gateway: "0x48bEe5e48d30D2017B3c6f3e1C3B8ddF0E94D7C5" },
  59144: { name: "Linea", gateway: "0x48bEe5e48d30D2017B3c6f3e1C3B8ddF0E94D7C5" },
  534352: { name: "Scroll", gateway: "0x48bEe5e48d30D2017B3c6f3e1C3B8ddF0E94D7C5" },
  324: { name: "zkSync", gateway: "0x48bEe5e48d30D2017B3c6f3e1C3B8ddF0E94D7C5" },
  5000: { name: "Mantle", gateway: "0x48bEe5e48d30D2017B3c6f3e1C3B8ddF0E94D7C5" },
  169: { name: "Manta", gateway: "0x48bEe5e48d30D2017B3c6f3e1C3B8ddF0E94D7C5" },
  34443: { name: "Mode", gateway: "0x48bEe5e48d30D2017B3c6f3e1C3B8ddF0E94D7C5" },
  42220: { name: "Celo", gateway: "0x48bEe5e48d30D2017B3c6f3e1C3B8ddF0E94D7C5" },
  100: { name: "Gnosis", gateway: "0x48bEe5e48d30D2017B3c6f3e1C3B8ddF0E94D7C5" },
  1284: { name: "Moonbeam", gateway: "0x48bEe5e48d30D2017B3c6f3e1C3B8ddF0E94D7C5" },
  1313161554: { name: "Aurora", gateway: "0x48bEe5e48d30D2017B3c6f3e1C3B8ddF0E94D7C5" },
  25: { name: "Cronos", gateway: "0x48bEe5e48d30D2017B3c6f3e1C3B8ddF0E94D7C5" },
  2222: { name: "Kava", gateway: "0x48bEe5e48d30D2017B3c6f3e1C3B8ddF0E94D7C5" },
  1088: { name: "Metis", gateway: "0x48bEe5e48d30D2017B3c6f3e1C3B8ddF0E94D7C5" },

  // Testnets
  11155111: { name: "Sepolia", gateway: "0x5F0b1a82749cb4E2278EC87F8BF6B618dC71a8bf" },
  80002: { name: "Polygon Amoy", gateway: "0x5F0b1a82749cb4E2278EC87F8BF6B618dC71a8bf" },
  421614: { name: "Arbitrum Sepolia", gateway: "0x5F0b1a82749cb4E2278EC87F8BF6B618dC71a8bf" },
  84532: { name: "Base Sepolia", gateway: "0x5F0b1a82749cb4E2278EC87F8BF6B618dC71a8bf" },
};

// Common tokens per chain (native + major stablecoins)
const COMMON_TOKENS: Record<number, { token: string; symbol: string }[]> = {
  1: [
    { token: "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48", symbol: "USDC" },
    { token: "0xdAC17F958D2ee523a2206206994597C13D831ec7", symbol: "USDT" },
    { token: "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2", symbol: "WETH" },
  ],
  137: [
    { token: "0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174", symbol: "USDC" },
    { token: "0xc2132D05D31c914a87C6611C10748AEb04B58e8F", symbol: "USDT" },
    { token: "0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619", symbol: "WETH" },
  ],
  8453: [
    { token: "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913", symbol: "USDC" },
    { token: "0x4200000000000000000000000000000000000006", symbol: "WETH" },
  ],
  42161: [
    { token: "0xaf88d065e77c8cC2239327C5EDb3A432268e5831", symbol: "USDC" },
    { token: "0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9", symbol: "USDT" },
    { token: "0x82aF49447D8a07e3bd95BD0d56f35241523fBab1", symbol: "WETH" },
  ],
  10: [
    { token: "0x0b2C639c533813f4Aa9D7837CAf62653d097Ff85", symbol: "USDC" },
    { token: "0x94b008aA00579c1307B0EF2c499aD98a8ce58e58", symbol: "USDT" },
    { token: "0x4200000000000000000000000000000000000006", symbol: "WETH" },
  ],
};

async function main() {
  const [deployer] = await ethers.getSigners();
  const network = await ethers.provider.getNetwork();
  const chainId = network.chainId;

  console.log("=".repeat(70));
  console.log("ChainConnector Deployment");
  console.log("=".repeat(70));
  console.log("Network:", network.name, `(chainId: ${chainId})`);
  console.log("Deployer:", deployer.address);

  const balance = await ethers.provider.getBalance(deployer.address);
  console.log("Balance:", ethers.utils.formatEther(balance), "ETH");
  console.log("=".repeat(70));

  // Get chain configuration
  const chainConfig = CHAIN_CONFIGS[chainId];
  if (!chainConfig) {
    console.error(`❌ No configuration for chain ${chainId}`);
    process.exit(1);
  }

  console.log("Chain Name:", chainConfig.name);
  console.log("Gateway:", chainConfig.gateway);
  console.log("");

  // OmnichainRouter address (should be set after deploying to ZetaChain)
  const omnichainRouter = process.env.OMNICHAIN_ROUTER || ethers.constants.AddressZero;
  console.log("OmnichainRouter:", omnichainRouter);

  if (omnichainRouter === ethers.constants.AddressZero) {
    console.log("⚠️  WARNING: OmnichainRouter not set. Update after deployment.");
    console.log("");
  }

  // Deploy ChainConnector with UUPS proxy
  console.log("Deploying ChainConnector...");

  const ChainConnector = await ethers.getContractFactory("ChainConnector");

  const connector = await upgrades.deployProxy(
    ChainConnector,
    [
      chainId,
      chainConfig.name,
      chainConfig.gateway,
      omnichainRouter,
    ],
    {
      kind: "uups",
      initializer: "initialize",
    }
  );

  await connector.deployed();

  console.log("");
  console.log("=".repeat(70));
  console.log("🚀 Deployment Complete!");
  console.log("=".repeat(70));
  console.log("Proxy Address:", connector.address);

  const implementationAddress = await upgrades.erc1967.getImplementationAddress(
    connector.address
  );
  console.log("Implementation Address:", implementationAddress);

  // Whitelist common tokens
  const tokens = COMMON_TOKENS[chainId] || [];
  if (tokens.length > 0) {
    console.log("");
    console.log("Whitelisting tokens...");
    for (const token of tokens) {
      const tx = await connector.setSupportedToken(token.token, true);
      await tx.wait();
      console.log(`  ✓ ${token.symbol}: ${token.token}`);
    }
  }

  // Verify initial state
  console.log("");
  console.log("Verifying initial state...");
  const [id, name] = await connector.getChainInfo();
  console.log("- Chain ID:", id.toString());
  console.log("- Chain Name:", name);
  console.log("- Gateway:", await connector.gateway());
  console.log("- OmnichainRouter:", await connector.omnichainRouter());
  console.log("- Native Token Supported:", await connector.supportedTokens(ethers.constants.AddressZero));
  console.log("");

  console.log("=".repeat(70));
  console.log("Contract Verification Command:");
  console.log("=".repeat(70));
  console.log(`npx hardhat verify --network ${network.name} ${implementationAddress}`);
  console.log("");

  const deploymentInfo = {
    network: network.name,
    chainId: chainId.toString(),
    chainName: chainConfig.name,
    proxyAddress: connector.address,
    implementationAddress,
    gateway: chainConfig.gateway,
    omnichainRouter,
    whitelistedTokens: tokens.map(t => t.symbol),
    deployer: deployer.address,
    deployedAt: new Date().toISOString(),
  };

  console.log("=".repeat(70));
  console.log("Deployment Info (save this!):");
  console.log("=".repeat(70));
  console.log(JSON.stringify(deploymentInfo, null, 2));

  // Instructions for multi-chain deployment
  console.log("");
  console.log("=".repeat(70));
  console.log("Multi-Chain Deployment Instructions:");
  console.log("=".repeat(70));
  console.log("1. Deploy OmnichainRouter on ZetaChain first");
  console.log("2. Set OMNICHAIN_ROUTER environment variable");
  console.log("3. Deploy ChainConnector on each chain:");
  console.log("");
  console.log("   export OMNICHAIN_ROUTER=0x...");
  console.log("");
  Object.entries(CHAIN_CONFIGS).forEach(([id, config]) => {
    if (parseInt(id) !== chainId) {
      console.log(`   npx hardhat run scripts/deploy-chain-connector.ts --network ${config.name.toLowerCase().replace(" ", "-")}`);
    }
  });
  console.log("");
  console.log("4. After all deployments, register connectors with OmnichainRouter");

  return deploymentInfo;
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
