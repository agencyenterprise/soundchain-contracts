import { ethers } from "hardhat";

/**
 * Deploy SoundChain Omnichain Contracts
 *
 * Deployment Order:
 * 1. SoundchainFeeCollector (on each chain)
 * 2. SoundchainNFTBridge (on each chain)
 * 3. SoundchainOmnichain (on ZetaChain only)
 *
 * Usage:
 *   npx hardhat run scripts/deployOmnichain.ts --network polygon
 *   npx hardhat run scripts/deployOmnichain.ts --network zetachain
 */

// Configuration - UPDATE THESE BEFORE DEPLOYMENT
const CONFIG = {
  // Gnosis Safe address for fee collection
  gnosisSafe: process.env.GNOSIS_SAFE || "0x0000000000000000000000000000000000000000",

  // Fee rate in basis points (5 = 0.05%)
  feeRate: 5,

  // Bridge fee in native currency (0.001 ETH/MATIC)
  bridgeFee: ethers.utils.parseEther("0.001"),

  // ZetaChain Gateway address (mainnet)
  zetaGateway: "0x48D67Bb3f5CAB49e0C3E03a7f2D10a8fB04F3694",

  // ZetaChain Gateway address (testnet)
  zetaGatewayTestnet: "0x6c533f7fe93fae114d0954697069df33c9b74fd7",
};

async function main() {
  const [deployer] = await ethers.getSigners();
  const network = await ethers.provider.getNetwork();

  console.log("========================================");
  console.log("  SoundChain Omnichain Deployment");
  console.log("========================================");
  console.log(`Network: ${network.name} (chainId: ${network.chainId})`);
  console.log(`Deployer: ${deployer.address}`);
  console.log(`Balance: ${ethers.utils.formatEther(await deployer.getBalance())} ETH`);
  console.log("----------------------------------------");

  // Validate Gnosis Safe
  if (CONFIG.gnosisSafe === "0x0000000000000000000000000000000000000000") {
    console.warn("⚠️  WARNING: Using zero address for Gnosis Safe!");
    console.warn("   Set GNOSIS_SAFE env variable before mainnet deployment.");
  }

  // Deploy FeeCollector
  console.log("\n1. Deploying SoundchainFeeCollector...");
  const FeeCollector = await ethers.getContractFactory("SoundchainFeeCollector");
  const feeCollector = await FeeCollector.deploy(CONFIG.gnosisSafe, CONFIG.feeRate);
  await feeCollector.deployed();
  console.log(`   ✅ FeeCollector deployed at: ${feeCollector.address}`);

  // Deploy NFT Bridge
  console.log("\n2. Deploying SoundchainNFTBridge...");
  const NFTBridge = await ethers.getContractFactory("SoundchainNFTBridge");
  const nftBridge = await NFTBridge.deploy(
    network.chainId,
    feeCollector.address,
    CONFIG.bridgeFee
  );
  await nftBridge.deployed();
  console.log(`   ✅ NFTBridge deployed at: ${nftBridge.address}`);

  // Deploy Omnichain (only on ZetaChain)
  if (network.chainId === 7000 || network.chainId === 7001) {
    const gateway = network.chainId === 7000
      ? CONFIG.zetaGateway
      : CONFIG.zetaGatewayTestnet;

    console.log("\n3. Deploying SoundchainOmnichain (ZetaChain Universal App)...");
    const Omnichain = await ethers.getContractFactory("SoundchainOmnichain");
    const omnichain = await Omnichain.deploy(gateway, CONFIG.gnosisSafe);
    await omnichain.deployed();
    console.log(`   ✅ Omnichain deployed at: ${omnichain.address}`);
  } else {
    console.log("\n3. Skipping SoundchainOmnichain (not on ZetaChain)");
  }

  // Authorize FeeCollector contracts
  console.log("\n4. Setting up permissions...");

  // Authorize NFT Bridge to collect fees
  await feeCollector.setAuthorizedCollector(nftBridge.address, true);
  console.log(`   ✅ NFTBridge authorized as fee collector`);

  // Print deployment summary
  console.log("\n========================================");
  console.log("  Deployment Complete!");
  console.log("========================================");
  console.log(`
DEPLOYED CONTRACTS (${network.name}):

FeeCollector:  ${feeCollector.address}
NFTBridge:     ${nftBridge.address}
${network.chainId === 7000 || network.chainId === 7001 ? `Omnichain:     (see above)` : ''}

CONFIGURATION:
- Gnosis Safe:  ${CONFIG.gnosisSafe}
- Fee Rate:     ${CONFIG.feeRate} basis points (${CONFIG.feeRate / 100}%)
- Bridge Fee:   ${ethers.utils.formatEther(CONFIG.bridgeFee)} native

NEXT STEPS:
1. Verify contracts on block explorer
2. Whitelist Soundchain721 NFT contract in NFTBridge
3. Set relayer address for NFTBridge
4. Deploy on other chains and register connectors
5. Update frontend with new contract addresses
`);

  // Output for easy copying
  console.log("\n// Copy this to your .env or config:");
  console.log(`NEXT_PUBLIC_FEE_COLLECTOR_${network.chainId}=${feeCollector.address}`);
  console.log(`NEXT_PUBLIC_NFT_BRIDGE_${network.chainId}=${nftBridge.address}`);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
