import { ethers, upgrades } from "hardhat";

/**
 * MultiTokenMarketplace Deployment Script
 *
 * Deploys the MultiTokenMarketplace with 32 supported tokens.
 *
 * Usage:
 *   npx hardhat run scripts/deploy-multi-token-marketplace.ts --network polygon
 */

// Token addresses on Polygon Mainnet
const POLYGON_TOKENS: Record<string, { address: string; symbol: string; decimals: number }> = {
  // Native
  MATIC: { address: "0x0000000000000000000000000000000000000000", symbol: "MATIC", decimals: 18 },
  // Stablecoins
  USDC: { address: "0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174", symbol: "USDC", decimals: 6 },
  USDT: { address: "0xc2132D05D31c914a87C6611C10748AEb04B58e8F", symbol: "USDT", decimals: 6 },
  // Major tokens (wrapped on Polygon)
  WETH: { address: "0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619", symbol: "ETH", decimals: 18 },
  WBTC: { address: "0x1BFD67037B42Cf73acF2047067bd4F2C47D9BfD6", symbol: "BTC", decimals: 8 },
  // DeFi tokens
  LINK: { address: "0x53E0bca35eC356BD5ddDFebbD1Fc0fD03FaBad39", symbol: "LINK", decimals: 18 },
  AAVE: { address: "0xD6DF932A45C0f255f85145f286eA0b292B21C90B", symbol: "AAVE", decimals: 18 },
  UNI: { address: "0xb33EaAd8d922B1083446DC23f610c2567fB5180f", symbol: "UNI", decimals: 18 },
  // Meme tokens
  SHIB: { address: "0x6f8a06447Ff6FcF75d803135a7de15CE88C1d4ec", symbol: "SHIB", decimals: 18 },
  DOGE: { address: "0xbA777aE3a3C91fCD83EF85bfe65410592Bdd0f7c", symbol: "DOGE", decimals: 8 },
  PEPE: { address: "0x8e4a79813079c46F0A34B1a0F1b9E6C0E0c7C3D0", symbol: "PEPE", decimals: 18 },
  BONK: { address: "0xe5B49820e5A1063F6F4DdF851327b5E8B2301048", symbol: "BONK", decimals: 5 },
  // L2 tokens
  OP: { address: "0x0000000000000000000000000000000000000000", symbol: "OP", decimals: 18 }, // Placeholder
  ARB: { address: "0x0000000000000000000000000000000000000000", symbol: "ARB", decimals: 18 }, // Placeholder
  // SoundChain native
  OGUN: { address: "0x0000000000000000000000000000000000000000", symbol: "OGUN", decimals: 18 }, // To be set
};

// Token addresses on ZetaChain (ZRC-20 wrapped tokens)
const ZETACHAIN_TOKENS: Record<string, { address: string; symbol: string; decimals: number }> = {
  ZETA: { address: "0x0000000000000000000000000000000000000000", symbol: "ZETA", decimals: 18 },
  // ZRC-20 wrapped tokens will be added after deployment
};

async function main() {
  const [deployer] = await ethers.getSigners();
  const network = await ethers.provider.getNetwork();

  console.log("=".repeat(60));
  console.log("MultiTokenMarketplace Deployment");
  console.log("=".repeat(60));
  console.log("Network:", network.name, `(chainId: ${network.chainId})`);
  console.log("Deployer:", deployer.address);

  const balance = await ethers.provider.getBalance(deployer.address);
  console.log("Balance:", ethers.utils.formatEther(balance), "ETH");
  console.log("=".repeat(60));

  // Configuration
  const feeCollector = process.env.FEE_COLLECTOR || deployer.address;
  const platformFee = 50; // 0.5% in basis points
  const omnichainContract = process.env.OMNICHAIN_CONTRACT || ethers.constants.AddressZero;

  console.log("Fee Collector:", feeCollector);
  console.log("Platform Fee:", platformFee, "basis points (0.5%)");
  console.log("Omnichain Contract:", omnichainContract);
  console.log("");

  // Deploy MultiTokenMarketplace with UUPS proxy
  console.log("Deploying MultiTokenMarketplace...");

  const MultiTokenMarketplace = await ethers.getContractFactory("MultiTokenMarketplace");

  const marketplace = await upgrades.deployProxy(
    MultiTokenMarketplace,
    [feeCollector, platformFee, omnichainContract],
    {
      kind: "uups",
      initializer: "initialize",
    }
  );

  await marketplace.deployed();

  console.log("");
  console.log("=".repeat(60));
  console.log("Deployment Complete!");
  console.log("=".repeat(60));
  console.log("Proxy Address:", marketplace.address);

  const implementationAddress = await upgrades.erc1967.getImplementationAddress(
    marketplace.address
  );
  console.log("Implementation Address:", implementationAddress);

  // Whitelist tokens based on network
  console.log("");
  console.log("Whitelisting tokens...");

  const tokens = network.chainId === 137 ? POLYGON_TOKENS : ZETACHAIN_TOKENS;
  const tokenAddresses: string[] = [];
  const tokenSymbols: string[] = [];
  const tokenDecimals: number[] = [];

  for (const [name, info] of Object.entries(tokens)) {
    if (info.address !== ethers.constants.AddressZero) {
      tokenAddresses.push(info.address);
      tokenSymbols.push(info.symbol);
      tokenDecimals.push(info.decimals);
      console.log(`  - ${info.symbol}: ${info.address}`);
    }
  }

  if (tokenAddresses.length > 0) {
    const tx = await marketplace.whitelistTokensBulk(
      tokenAddresses,
      tokenSymbols,
      tokenDecimals
    );
    await tx.wait();
    console.log(`Whitelisted ${tokenAddresses.length} tokens`);
  }

  // Always whitelist native token (address(0))
  const nativeTx = await marketplace.whitelistToken(
    ethers.constants.AddressZero,
    network.chainId === 137 ? "MATIC" : "ZETA",
    18,
    ethers.constants.AddressZero
  );
  await nativeTx.wait();
  console.log("Whitelisted native token");

  // Verify initial state
  console.log("");
  console.log("Verifying initial state...");
  console.log("- Version:", await marketplace.VERSION());
  console.log("- Platform Fee:", (await marketplace.platformFee()).toString(), "basis points");
  console.log("- Default Royalty:", (await marketplace.defaultRoyaltyPercentage()).toString(), "basis points");
  console.log("- Whitelisted Tokens:", (await marketplace.getWhitelistedTokens()).length);
  console.log("");

  console.log("=".repeat(60));
  console.log("Contract Verification Command:");
  console.log("=".repeat(60));
  console.log(`npx hardhat verify --network ${network.name} ${implementationAddress}`);

  return {
    network: network.name,
    chainId: network.chainId.toString(),
    proxyAddress: marketplace.address,
    implementationAddress,
    feeCollector,
    platformFee,
    omnichainContract,
    whitelistedTokens: tokenAddresses.length + 1, // +1 for native
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
