import hre from "hardhat";

const TGE_CONTROLLER = "0xb6C049D47A2FaE5413c331760C22E715D0bF4d45";
const DEPLOYER = "0xeEf494A14E6e66ec7c3E14E8674dCe2d99144de6";

const TGE_ABI = [
  "function executeTGE(address[] calldata recipients, uint256[] calldata amounts, uint8[] calldata efficiencies) external",
];

async function main() {
  const connection = await hre.network.getOrCreate();
  const { ethers } = connection;
  const provider = ethers.provider;
  const [signer] = await ethers.getSigners();

  const tge = new ethers.Contract(TGE_CONTROLLER, TGE_ABI, signer);
  const amount = ethers.parseEther("10000");

  try {
    const tx = await tge.executeTGE.staticCall([DEPLOYER], [amount], [100]);
    console.log("Static call succeeded!", tx);
  } catch (err) {
    console.error("Revert error details:", err.message);
    if (err.data) {
      console.error("Revert data:", err.data);
    }
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
