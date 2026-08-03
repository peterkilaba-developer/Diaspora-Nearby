import hre from "hardhat";

const CORRECT_METAMASK = "0xeef49F2a10f0EF143Cd8c710e013285F137F4dE6";
const TOKEN = "0x55d7e7d006938A15082752225ED44Fd130B87735";
const USDC = "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913";

const ERC20_ABI = [
  "function balanceOf(address) view returns (uint256)",
];

async function main() {
  const connection = await hre.network.getOrCreate();
  const { ethers } = connection;

  const token = new ethers.Contract(TOKEN, ERC20_ABI, ethers.provider);
  const usdc = new ethers.Contract(USDC, ERC20_ABI, ethers.provider);

  const dspBal = await token.balanceOf(CORRECT_METAMASK);
  const usdcBal = await usdc.balanceOf(CORRECT_METAMASK);

  console.log("=".repeat(60));
  console.log("Connected MetaMask Wallet:", CORRECT_METAMASK);
  console.log("  $DIASPORA Balance:", ethers.formatEther(dspBal), "$DIASPORA");
  console.log("  USDC Balance:     ", ethers.formatUnits(usdcBal, 6), "USDC");
  console.log("=".repeat(60));
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
