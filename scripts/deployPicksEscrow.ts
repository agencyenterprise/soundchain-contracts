import { ethers } from "hardhat";

/**
 * Deploy SoundchainPicksEscrow — ZetaChain Universal Contract for 1v1 Arena Pick wagers.
 *
 * Networks:
 *   testnet:  npx hardhat run scripts/deployPicksEscrow.ts --network zetachain_testnet
 *   mainnet:  npx hardhat run scripts/deployPicksEscrow.ts --network zetachain
 *
 * Required env vars:
 *   PRIVATE_KEY      — deployer wallet (must hold ZETA on chainId 7000 for mainnet)
 *   GNOSIS_SAFE      — Gnosis Safe address that receives the 0.05% platform fee
 *   ORACLE_ADDRESS   — backend signer that calls settle() (defaults to deployer if unset)
 *
 * Post-deploy follow-ups:
 *   1. Add `NEXT_PUBLIC_PICKS_ESCROW_7000=<address>` to Vercel
 *   2. Verify on Zetascan: npx hardhat verify --network zetachain <addr> <gateway> <safe> <oracle>
 *   3. Flip `isTokenLive()` in `lib/arena/fantasy/types.ts` to include the cross-chain tokens
 */

const ZETA_GATEWAY_MAINNET = "0x48D67Bb3f5CAB49e0C3E03a7f2D10a8fB04F3694";
const ZETA_GATEWAY_TESTNET = "0x6c533f7fe93fae114d0954697069df33c9b74fd7";

async function main() {
  const network = await ethers.provider.getNetwork();
  const isMainnet = network.chainId === 7000;
  const isTestnet = network.chainId === 7001;

  if (!isMainnet && !isTestnet) {
    throw new Error(
      `Unsupported network (chainId ${network.chainId}). Use --network zetachain or --network zetachain_testnet.`
    );
  }

  const [deployer] = await ethers.getSigners();
  if (!deployer) {
    throw new Error("No deployer signer — check PRIVATE_KEY in .env");
  }

  const balance = await deployer.getBalance();
  const balanceFmt = ethers.utils.formatEther(balance);

  const gateway = isMainnet ? ZETA_GATEWAY_MAINNET : ZETA_GATEWAY_TESTNET;
  const gnosisSafe = process.env.GNOSIS_SAFE;
  const oracle = process.env.ORACLE_ADDRESS || deployer.address;

  if (!gnosisSafe || gnosisSafe === "0x0000000000000000000000000000000000000000") {
    throw new Error("GNOSIS_SAFE not set in .env — refusing to deploy with placeholder");
  }
  if (!ethers.utils.isAddress(gnosisSafe)) {
    throw new Error(`GNOSIS_SAFE is not a valid address: ${gnosisSafe}`);
  }
  if (!ethers.utils.isAddress(oracle)) {
    throw new Error(`ORACLE_ADDRESS is not a valid address: ${oracle}`);
  }

  console.log("================================================================");
  console.log("  SoundchainPicksEscrow Deployment");
  console.log("================================================================");
  console.log(`Network:       ${isMainnet ? "ZetaChain Mainnet" : "ZetaChain Athens (testnet)"} (chainId ${network.chainId})`);
  console.log(`Deployer:      ${deployer.address}`);
  console.log(`Balance:       ${balanceFmt} ZETA`);
  console.log(`Gateway:       ${gateway}`);
  console.log(`Gnosis Safe:   ${gnosisSafe}`);
  console.log(`Oracle:        ${oracle}${oracle === deployer.address ? "  (defaulted to deployer — set ORACLE_ADDRESS to override)" : ""}`);
  console.log("----------------------------------------------------------------");

  // Sanity: deployer must have at least 0.5 ZETA for mainnet, 0.1 for testnet
  const minBalance = ethers.utils.parseEther(isMainnet ? "0.5" : "0.1");
  if (balance.lt(minBalance)) {
    throw new Error(
      `Deployer balance ${balanceFmt} ZETA below minimum ${ethers.utils.formatEther(minBalance)} ZETA — fund the deployer wallet first.`
    );
  }

  console.log("\nDeploying SoundchainPicksEscrow…");
  const Factory = await ethers.getContractFactory("SoundchainPicksEscrow");
  const escrow = await Factory.deploy(gateway, gnosisSafe, oracle);
  await escrow.deployed();

  console.log(`\n✅ SoundchainPicksEscrow deployed at: ${escrow.address}`);
  console.log("\nNext steps:");
  console.log(`  1. Add to web/.env:  NEXT_PUBLIC_PICKS_ESCROW_${network.chainId}=${escrow.address}`);
  console.log(`  2. Verify:           npx hardhat verify --network ${isMainnet ? "zetachain" : "zetachain_testnet"} ${escrow.address} ${gateway} ${gnosisSafe} ${oracle}`);
  console.log(`  3. Confirm oracle wallet is funded with ZETA gas to call settle() on matched picks`);
  console.log(`  4. Flip isTokenLive() in lib/arena/fantasy/types.ts to enable all 24 tokens`);
}

main().catch(err => {
  console.error("\n❌ Deploy failed:", err);
  process.exit(1);
});
