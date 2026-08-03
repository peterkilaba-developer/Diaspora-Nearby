import hre from "hardhat";

const TGE_CONTROLLER = "0xb6C049D47A2FaE5413c331760C22E715D0bF4d45";
const CORRECT_METAMASK = "0xeef49F2a10f0EF143Cd8c710e013285F137F4dE6";

const TGE_V2_ABI = [
  "function executeTGE(address[] calldata recipients, uint256[] calldata amounts, uint8[] calldata efficiencies, bytes32 merkleRoot) external",
];

const TOKEN_ABI = [
  "function balanceOf(address) view returns (uint256)",
];

async function main() {
  const connection = await hre.network.getOrCreate();
  const { ethers } = connection;
  const [signer] = await ethers.getSigners();

  console.log("=".repeat(60));
  console.log("  🚀 Sending 10,000 $DIASPORA to Correct MetaMask Wallet");
  console.log("=".repeat(60));
  console.log("Recipient:", CORRECT_METAMASK);

  const tge = new ethers.Contract(TGE_CONTROLLER, TGE_V2_ABI, signer);
  const amount = ethers.parseEther("10000");
  const dummyMerkleRoot = ethers.id("TDE2_LIQUIDITY_SEEDING_CORRECT_WALLET");

  const tx = await tge.executeTGE([CORRECT_METAMASK], [amount], [100], dummyMerkleRoot);
  console.log("Tx Submitted! Hash:", tx.hash);
  await tx.wait();

  const token = new ethers.Contract("0x55d7e7d006938A15082752225ED44Fd130B87735", TOKEN_ABI, signer);
  const bal = await token.balanceOf(CORRECT_METAMASK);

  console.log("✅ 10,000 $DIASPORA Payout Complete!");
  console.log("MetaMask Wallet Balance:", ethers.formatEther(bal), "$DIASPORA");
  console.log("=".repeat(60));
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
