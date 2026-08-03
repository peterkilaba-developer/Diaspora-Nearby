import hre from "hardhat";

const FOUNDERS_ADDRESS = "0xc27f74031f63c24c5E29492e23ecE019E698B46c";
const LIQUIDITY_ADDRESS = "0xF0f15Cf38Ef463E0ff46DC0540489F466E222edB";
const BURN_ADDRESS = "0x000000000000000000000000000000000000dEaD";
const DIASPORA_ADDRESS = "0x55d7e7d006938A15082752225ED44Fd130B87735";

const ERC20_ABI = [
  "function balanceOf(address account) external view returns (uint256)",
  "function decimals() external view returns (uint8)",
];

async function main() {
  const connection = await hre.network.getOrCreate();
  const { ethers } = connection;
  const provider = ethers.provider;

  const diasporaContract = new ethers.Contract(DIASPORA_ADDRESS, ERC20_ABI, provider);

  const fAddr = ethers.getAddress(FOUNDERS_ADDRESS.toLowerCase());
  const lAddr = ethers.getAddress(LIQUIDITY_ADDRESS.toLowerCase());
  const bAddr = ethers.getAddress(BURN_ADDRESS.toLowerCase());

  console.log("=".repeat(60));
  console.log("  🔍 Verifying On-Chain System Reserve Balances on Base");
  console.log("=".repeat(60));

  const fBal = await diasporaContract.balanceOf(fAddr);
  const lBal = await diasporaContract.balanceOf(lAddr);
  const bBal = await diasporaContract.balanceOf(bAddr);

  console.log("1. Founders & Core Team (0xc27f...B46c):");
  console.log("   On-Chain Balance:", ethers.formatEther(fBal), "$DIASPORA");
  console.log();

  console.log("2. Liquidity Treasury (0xF0f1...edB):");
  console.log("   On-Chain Balance:", ethers.formatEther(lBal), "$DIASPORA");
  console.log();

  console.log("3. Natural Burn Pool (0x0000...dEaD):");
  console.log("   On-Chain Balance:", ethers.formatEther(bBal), "$DIASPORA");
  console.log();
  console.log("=".repeat(60));
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
