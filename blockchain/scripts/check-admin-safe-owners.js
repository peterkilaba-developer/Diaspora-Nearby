import hre from "hardhat";

const ADMIN_SAFE = "0xE06F8690e96a8BAAbCBe48664Ff1238F69082244";

const SAFE_ABI = [
  "function getOwners() view returns (address[])",
  "function getThreshold() view returns (uint256)",
];

async function main() {
  const connection = await hre.network.getOrCreate();
  const { ethers } = connection;
  const provider = ethers.provider;

  const safeAddr = ethers.getAddress(ADMIN_SAFE.toLowerCase());
  const safe = new ethers.Contract(safeAddr, SAFE_ABI, provider);

  const owners = await safe.getOwners();
  const threshold = await safe.getThreshold();

  console.log("=".repeat(60));
  console.log("  🔍 Admin Safe Configuration (0xE06F...2244)");
  console.log("=".repeat(60));
  console.log("Threshold Required:", threshold.toString(), "of", owners.length);
  console.log("Safe Owners:");
  owners.forEach((o, i) => console.log(`  [${i + 1}] ${o}`));
  console.log("=".repeat(60));
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
