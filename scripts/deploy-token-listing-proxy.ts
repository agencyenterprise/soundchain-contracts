import { ethers, upgrades } from "hardhat";

/**
 * TokenListingProxy Deployment Script
 *
 * Deploys the multi-token listing contract with support for 32+ tokens.
 *
 * Usage:
 *   npx hardhat run scripts/deploy-token-listing-proxy.ts --network polygon
 */

// Token configurations per chain
const TOKEN_CONFIGS: Record<number, { address: string; symbol: string; decimals: number; zrc20: string }[]> = {
  // Polygon
  137: [
    { address: "0x0000000000000000000000000000000000000000", symbol: "MATIC", decimals: 18, zrc20: "" },
    { address: "0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174", symbol: "USDC", decimals: 6, zrc20: "" },
    { address: "0xc2132D05D31c914a87C6611C10748AEb04B58e8F", symbol: "USDT", decimals: 6, zrc20: "" },
    { address: "0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619", symbol: "WETH", decimals: 18, zrc20: "" },
    { address: "0x1BFD67037B42Cf73acF2047067bd4F2C47D9BfD6", symbol: "WBTC", decimals: 8, zrc20: "" },
    { address: "0x53E0bca35eC356BD5ddDFebbD1Fc0fD03FaBad39", symbol: "LINK", decimals: 18, zrc20: "" },
    { address: "0xD6DF932A45C0f255f85145f286eA0b292B21C90B", symbol: "AAVE", decimals: 18, zrc20: "" },
    { address: "0xb33EaAd8d922B1083446DC23f610c2567fB5180f", symbol: "UNI", decimals: 18, zrc20: "" },
  ],
  // Ethereum
  1: [
    { address: "0x0000000000000000000000000000000000000000", symbol: "ETH", decimals: 18, zrc20: "" },
    { address: "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48", symbol: "USDC", decimals: 6, zrc20: "" },
    { address: "0xdAC17F958D2ee523a2206206994597C13D831ec7", symbol: "USDT", decimals: 6, zrc20: "" },
    { address: "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2", symbol: "WETH", decimals: 18, zrc20: "" },
    { address: "0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599", symbol: "WBTC", decimals: 8, zrc20: "" },
  ],
  // Base
  8453: [
    { address: "0x0000000000000000000000000000000000000000", symbol: "ETH", decimals: 18, zrc20: "" },
    { address: "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913", symbol: "USDC", decimals: 6, zrc20: "" },
    { address: "0x4200000000000000000000000000000000000006", symbol: "WETH", decimals: 18, zrc20: "" },
  ],
};

async function main() {
  const [deployer] = await ethers.getSigners();
  const network = await ethers.provider.getNetwork();
  const chainId = network.chainId;

  console.log("=".repeat(60));
  console.log("TokenListingProxy Deployment");
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

  // Deploy TokenListingProxy with UUPS proxy
  console.log("Deploying TokenListingProxy...");

  const TokenListingProxy = await ethers.getContractFactory("TokenListingProxy");

  const proxy = await upgrades.deployProxy(
    TokenListingProxy,
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

  // Add supported tokens
  const tokens = TOKEN_CONFIGS[chainId] || [];
  if (tokens.length > 0) {
    console.log("");
    console.log("Adding supported tokens...");

    for (const token of tokens) {
      if (token.address === ethers.constants.AddressZero) {
        // Native token already added in initialize
        console.log(`  ✓ ${token.symbol} (native): already supported`);
      } else {
        try {
          const tx = await proxy.addToken(
            token.address,
            token.symbol,
            token.decimals,
            token.zrc20 || ethers.constants.AddressZero,
            0 // No minimum
          );
          await tx.wait();
          console.log(`  ✓ ${token.symbol}: ${token.address}`);
        } catch (error: any) {
          console.log(`  ⚠ ${token.symbol}: ${error.message}`);
        }
      }
    }
  }

  // Verify initial state
  console.log("");
  console.log("Verifying initial state...");
  console.log("- Version:", await proxy.VERSION());
  console.log("- Platform Fee:", (await proxy.platformFee()).toString(), "basis points");
  console.log("- OmnichainRouter:", await proxy.omnichainRouter());
  console.log("- Fee Collector:", await proxy.feeCollector());

  const supportedTokens = await proxy.getSupportedTokens();
  console.log("- Supported Tokens:", supportedTokens.length);
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
    supportedTokens: supportedTokens.length,
    deployer: deployer.address,
    deployedAt: new Date().toISOString(),
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
