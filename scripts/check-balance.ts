import { ethers } from "hardhat";
async function main() {
  const [d] = await ethers.getSigners();
  console.log("Deployer:", d.address);
  console.log("Balance:", ethers.utils.formatEther(await d.getBalance()), "POL");
}
main();
