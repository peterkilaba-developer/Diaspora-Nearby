import hre from "hardhat";

const TGE_CONTROLLER = "0xb6C049D47A2FaE5413c331760C22E715D0bF4d45";
const DEPLOYER = "0xeEf494A14E6e66ec7c3E14E8674dCe2d99144de6";

const TGE_V2_ABI = [
  "function executeTGE(address[] calldata recipients, uint256[] calldata amounts, uint8[] calldata efficiencies, bytes32 merkleRoot) external",
  "function getStats() view returns (uint256,uint256,uint256,uint256,uint256,uint256,uint256)",
];

async function main() {
  const connection = await hre.network.getOrCreate();
  const { ethers } = connection;
  const [signer] = await ethers.getSigners();

  console.log("=".repeat(60));
  console.log("  🚀 Triggering TDE 2 Release Payout via V2 Controller");
  console.log("=".repeat(60));
  console.log("Oracle Signer:", signer.address);

  const tge = new ethers.Contract(TGE_CONTROLLER, TGE_V2_ABI, signer);

  let stats = await tge.getStats();
  console.log(`Current Epoch: ${stats[0]} | TDE Event: ${stats[1]}`);

  // Payout 10,000 $DIASPORA to deployer for DEX seeding
  const amount = ethers.parseEther("10000");
  const dummyMerkleRoot = ethers.id("TDE2_LIQUIDITY_SEEDING_AUDIT");

  console.log(`Executing V2 executeTGE for 10,000 $DIASPORA to ${DEPLOYER}...`);
  console.log(`Merkle Root: ${dummyMerkleRoot}`);

  const tx = await tge.executeTGE([DEPLOYER], [amount], [100], dummyMerkleRoot);
  console.log(`Transaction submitted! Hash: ${tx.hash}`);
  await tx.wait();

  console.log("✅ TDE 2 Payout executed successfully on-chain!");

  stats = await tge.getStats();
  console.log(`Updated Epoch: ${stats[0]} | TDE Event: ${stats[1]}`);
  console.log("=".repeat(60));
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
