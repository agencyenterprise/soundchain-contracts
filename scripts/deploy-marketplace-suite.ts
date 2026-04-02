import { ethers, upgrades } from "hardhat";

/**
 * Deploy the full SoundChain Marketplace Suite
 *
 * Contracts:
 * 1. TokenExchange — P2P token-to-token swaps (sell OGUN for POL)
 * 2. CustomEscrow — Physical goods escrow (merch, vinyl, tickets, cars)
 * 3. MultiTokenMarketplace — NFT listings with 32+ token payments
 * 4. TokenListingProxy — NFT escrow with auctions + offers
 * 5. BundleListingProxy — Bundle sales (albums, collections, tiered)
 *
 * All contracts:
 * - UUPS upgradeable
 * - 0.05% fee (5 basis points) to Gnosis Safe treasury
 * - Pausable for emergencies
 * - ReentrancyGuard protected
 */

const GNOSIS_SAFE = "0x519BED3fE32272Fa8f1AECaf86DbFbd674Ee703B"; // SoundChain Treasury
const OGUN_TOKEN = "0x45f1af89486aeec2da0b06340cd9cd3bd741a15c";
const PLATFORM_FEE = 5; // 5 basis points = 0.05%
const CONFIRMATION_WINDOW = 14 * 24 * 60 * 60; // 14 days for custom escrow

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying with:", deployer.address);
  console.log("Balance:", ethers.utils.formatEther(await deployer.getBalance()), "POL");
  console.log("Treasury:", GNOSIS_SAFE);
  console.log("Platform Fee:", PLATFORM_FEE, "basis points (0.05%)");
  console.log("");

  // =============================================
  // 1. DEPLOY TokenExchange
  // =============================================
  console.log("1/5 Deploying TokenExchange...");
  const TokenExchange = await ethers.getContractFactory("TokenExchange");
  const tokenExchange = await upgrades.deployProxy(
    TokenExchange,
    [GNOSIS_SAFE, PLATFORM_FEE],
    { kind: "uups" }
  );
  await tokenExchange.deployed();
  console.log("   TokenExchange:", tokenExchange.address);

  // Whitelist OGUN token
  await tokenExchange.whitelistToken(OGUN_TOKEN, "OGUN", 18);
  console.log("   Whitelisted OGUN");
  console.log("");

  // =============================================
  // 2. DEPLOY CustomEscrow
  // =============================================
  console.log("2/5 Deploying CustomEscrow...");
  const CustomEscrow = await ethers.getContractFactory("CustomEscrow");
  const customEscrow = await upgrades.deployProxy(
    CustomEscrow,
    [GNOSIS_SAFE, PLATFORM_FEE, CONFIRMATION_WINDOW],
    { kind: "uups" }
  );
  await customEscrow.deployed();
  console.log("   CustomEscrow:", customEscrow.address);

  // Accept OGUN as payment
  await customEscrow.setAcceptedToken(OGUN_TOKEN, true);
  console.log("   OGUN accepted for payments");
  console.log("");

  // =============================================
  // 3. DEPLOY MultiTokenMarketplace
  // =============================================
  console.log("3/5 Deploying MultiTokenMarketplace...");
  const MultiTokenMarketplace = await ethers.getContractFactory("MultiTokenMarketplace");
  const multiTokenMarketplace = await upgrades.deployProxy(
    MultiTokenMarketplace,
    [GNOSIS_SAFE, PLATFORM_FEE, ethers.constants.AddressZero], // omnichain later
    { kind: "uups" }
  );
  await multiTokenMarketplace.deployed();
  console.log("   MultiTokenMarketplace:", multiTokenMarketplace.address);

  // Whitelist tokens
  await multiTokenMarketplace.whitelistTokensBulk(
    [OGUN_TOKEN],
    ["OGUN"],
    [18]
  );
  console.log("   Whitelisted OGUN");
  console.log("");

  // =============================================
  // 4. DEPLOY TokenListingProxy
  // =============================================
  console.log("4/5 Deploying TokenListingProxy...");
  const TokenListingProxy = await ethers.getContractFactory("TokenListingProxy");
  const tokenListingProxy = await upgrades.deployProxy(
    TokenListingProxy,
    [ethers.constants.AddressZero, GNOSIS_SAFE, PLATFORM_FEE], // omnichain later
    { kind: "uups" }
  );
  await tokenListingProxy.deployed();
  console.log("   TokenListingProxy:", tokenListingProxy.address);

  // Add OGUN token
  await tokenListingProxy.addToken(OGUN_TOKEN, "OGUN", 18, ethers.constants.AddressZero, 0);
  console.log("   OGUN added");
  console.log("");

  // =============================================
  // 5. DEPLOY BundleListingProxy
  // =============================================
  console.log("5/5 Deploying BundleListingProxy...");
  const BundleListingProxy = await ethers.getContractFactory("BundleListingProxy");
  const bundleListingProxy = await upgrades.deployProxy(
    BundleListingProxy,
    [GNOSIS_SAFE, PLATFORM_FEE, ethers.constants.AddressZero], // omnichain later
    { kind: "uups" }
  );
  await bundleListingProxy.deployed();
  console.log("   BundleListingProxy:", bundleListingProxy.address);
  console.log("");

  // =============================================
  // SUMMARY
  // =============================================
  console.log("=".repeat(60));
  console.log("SOUNDCHAIN MARKETPLACE SUITE — DEPLOYED");
  console.log("=".repeat(60));
  console.log("");
  console.log("Contract Addresses:");
  console.log(`  TokenExchange:          ${tokenExchange.address}`);
  console.log(`  CustomEscrow:           ${customEscrow.address}`);
  console.log(`  MultiTokenMarketplace:  ${multiTokenMarketplace.address}`);
  console.log(`  TokenListingProxy:      ${tokenListingProxy.address}`);
  console.log(`  BundleListingProxy:     ${bundleListingProxy.address}`);
  console.log("");
  console.log("Configuration:");
  console.log(`  Fee Collector:          ${GNOSIS_SAFE}`);
  console.log(`  Platform Fee:           ${PLATFORM_FEE} bps (0.05%)`);
  console.log(`  Escrow Window:          ${CONFIRMATION_WINDOW / 86400} days`);
  console.log(`  OGUN Token:             ${OGUN_TOKEN}`);
  console.log("");
  console.log("Add these to Vercel env vars:");
  console.log(`  NEXT_PUBLIC_TOKEN_EXCHANGE=${tokenExchange.address}`);
  console.log(`  NEXT_PUBLIC_CUSTOM_ESCROW=${customEscrow.address}`);
  console.log(`  NEXT_PUBLIC_MULTI_TOKEN_MARKETPLACE=${multiTokenMarketplace.address}`);
  console.log(`  NEXT_PUBLIC_TOKEN_LISTING_PROXY=${tokenListingProxy.address}`);
  console.log(`  NEXT_PUBLIC_BUNDLE_LISTING_PROXY=${bundleListingProxy.address}`);
  console.log("");
  console.log("Next steps:");
  console.log("  1. Verify on Polygonscan: npx hardhat verify --network polygon <address>");
  console.log("  2. Add contract addresses to web/src/config.ts");
  console.log("  3. Wire CreateTokenListingModal to TokenExchange.createListing()");
  console.log("  4. Wire CreateBundleListingModal to BundleListingProxy.createBundle()");
  console.log("  5. Add custom item listing UI for CustomEscrow.createListing()");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
