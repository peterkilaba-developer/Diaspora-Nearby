import hre from "hardhat";

const TGE_CONTROLLER = "0xb6C049D47A2FaE5413c331760C22E715D0bF4d45";
const TOKEN = "0x55d7e7d006938A15082752225ED44Fd130B87735";

const TGE_ABI = [
  "function getLockedBalance() view returns (uint256)",
  "function getStats() view returns (uint256,uint256,uint256,uint256,uint256,uint256,uint256)",
];

const TOKEN_ABI = [
  "function balanceOf(address) view returns (uint256)",
];

async function main() {
  const connection = await hre.network.getOrCreate();
  const { ethers } = connection;
  const provider = ethers.provider;

  const tge = new ethers.Contract(TGE_CONTROLLER, TGE_ABI, provider);
  const token = new ethers.Contract(TOKEN, TOKEN_ABI, provider);

  const locked = await tge.getLockedBalance();
  const stats = await tge.getStats();

  console.log("=".repeat(60));
  console.log("TGE Controller Address:", TGE_CONTROLLER);
  console.log("Locked $DIASPORA Balance:", ethers.formatEther(locked));
  console.log("Epoch:", stats[0].toString(), "| Event (TDE):", stats[1].toString());
  console.log("Total Minted:", ethers.formatEther(stats[2]));
  console.log("Total Distributed:", ethers.formatEther(stats[3]));
  console.log("Total Burned:", ethers.formatEther(stats[4]));
  console.log("=".repeat(60));
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
