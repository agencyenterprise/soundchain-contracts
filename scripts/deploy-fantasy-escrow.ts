/**
 * Deploy FantasyLeagueEscrow to Polygon mainnet.
 *
 * Usage:
 *   npx hardhat run scripts/deploy-fantasy-escrow.ts --network polygon
 *
 * Requires:
 *   PRIVATE_KEY in .env — deployer wallet with POL for gas
 *   GNOSIS_SAFE in .env — platform treasury address
 *   POLYGONSCAN_API_KEY in .env — for contract verification
 */
import { ethers, run } from "hardhat";

async function main() {
  const treasuryAddress = process.env.GNOSIS_SAFE;
  if (!treasuryAddress) throw new Error("GNOSIS_SAFE not set in .env");

  const [deployer] = await ethers.getSigners();
  console.log("Deployer:", deployer.address);
  console.log("Balance:", ethers.utils.formatEther(await deployer.getBalance()), "POL");
  console.log("Treasury:", treasuryAddress);

  // Deploy
  const Factory = await ethers.getContractFactory("FantasyLeagueEscrow");
  console.log("\nDeploying FantasyLeagueEscrow...");
  const escrow = await Factory.deploy(treasuryAddress);
  await escrow.deployed();
  console.log("✅ FantasyLeagueEscrow deployed to:", escrow.address);

  // Verify on Polygonscan
  console.log("\nWaiting 30s for Polygonscan indexing...");
  await new Promise(r => setTimeout(r, 30000));

  try {
    await run("verify:verify", {
      address: escrow.address,
      constructorArguments: [treasuryAddress],
    });
    console.log("✅ Contract verified on Polygonscan");
  } catch (e: any) {
    console.log("⚠️  Verification failed (may already be verified):", e.message);
  }

  // Print summary
  console.log("\n═══════════════════════════════════════════");
  console.log("  DEPLOYMENT SUMMARY");
  console.log("═══════════════════════════════════════════");
  console.log("  Contract:  FantasyLeagueEscrow");
  console.log("  Address:  ", escrow.address);
  console.log("  Network:   Polygon Mainnet (137)");
  console.log("  Treasury: ", treasuryAddress);
  console.log("  Platform:  5 bps (0.05%)");
  console.log("═══════════════════════════════════════════");
  console.log("\n📋 Next steps:");
  console.log("  1. Add to Vercel env: FANTASY_ESCROW_ADDRESS=" + escrow.address);
  console.log("  2. Wire /api/arena/fantasy join action to verify depositTxHash");
  console.log("  3. Update league detail page info text");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
