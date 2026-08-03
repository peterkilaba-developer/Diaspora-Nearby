import hre from "hardhat";

const TGE_CONTROLLER = "0xb6C049D47A2FaE5413c331760C22E715D0bF4d45";
const TOKEN = "0x55d7e7d006938A15082752225ED44Fd130B87735";

const PAUSABLE_ABI = ["function paused() view returns (bool)"];

async function main() {
  const connection = await hre.network.getOrCreate();
  const { ethers } = connection;
  const provider = ethers.provider;

  const tge = new ethers.Contract(TGE_CONTROLLER, PAUSABLE_ABI, provider);
  const token = new ethers.Contract(TOKEN, PAUSABLE_ABI, provider);

  try {
    console.log("TGE Controller Paused:", await tge.paused());
  } catch (e) {
    console.log("TGE Controller paused() error:", e.message);
  }

  try {
    console.log("Token Paused:", await token.paused());
  } catch (e) {
    console.log("Token paused() error:", e.message);
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
