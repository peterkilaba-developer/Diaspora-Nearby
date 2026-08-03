import hre from "hardhat";

const TGE_CONTROLLER = "0xb6C049D47A2FaE5413c331760C22E715D0bF4d45";
const DEPLOYER = "0xeEf494A14E6e66ec7c3E14E8674dCe2d99144de6";

const TGE_ABI = [
  "function executeTGE(address[] calldata recipients, uint256[] calldata amounts, uint8[] calldata efficiencies) external",
];

async function main() {
  const connection = await hre.network.getOrCreate();
  const { ethers } = connection;
  const [signer] = await ethers.getSigners();

  const tge = new ethers.Contract(TGE_CONTROLLER, TGE_ABI, signer);
  const amount = ethers.parseEther("100");

  console.log("Testing executeTGE with 100 $DIASPORA...");
  const tx = await tge.executeTGE([DEPLOYER], [amount], [100]);
  console.log("Tx Submitted! Hash:", tx.hash);
  await tx.wait();
  console.log("✅ SUCCESS!");
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
