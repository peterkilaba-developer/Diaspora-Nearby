import hre from "hardhat";

const RAW_TREASURY = "0xF0f15Cf38Ef463E0ff46DC0540489F466E222edB";
const USDC_ADDRESS = "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913";
const DIASPORA_ADDRESS = "0x55d7e7d006938A15082752225ED44Fd130B87735";

const ERC20_ABI = [
  "function balanceOf(address account) external view returns (uint256)",
  "function decimals() external view returns (uint8)",
  "function symbol() external view returns (string)",
];

async function main() {
  const connection = await hre.network.getOrCreate();
  const { ethers } = connection;
  const provider = ethers.provider;

  const LIQUIDITY_TREASURY = ethers.getAddress(RAW_TREASURY.toLowerCase());

  console.log("=".repeat(60));
  console.log("  🔍 Checking Liquidity Treasury Balances on Base Mainnet");
  console.log("=".repeat(60));
  console.log("Target Address:", LIQUIDITY_TREASURY);
  console.log();

  // 1. Check ETH Balance
  const ethBalance = await provider.getBalance(LIQUIDITY_TREASURY);
  console.log("  Base ETH Balance:  ", ethers.formatEther(ethBalance), "ETH");

  // 2. Check USDC Balance
  try {
    const usdcContract = new ethers.Contract(USDC_ADDRESS, ERC20_ABI, provider);
    const usdcBal = await usdcContract.balanceOf(LIQUIDITY_TREASURY);
    const usdcDecimals = await usdcContract.decimals();
    console.log("  USDC Balance:      ", ethers.formatUnits(usdcBal, usdcDecimals), "USDC");
  } catch (err) {
    console.error("  ❌ Failed to fetch USDC balance:", err.message);
  }

  // 3. Check $DIASPORA Balance
  try {
    const diasporaContract = new ethers.Contract(DIASPORA_ADDRESS, ERC20_ABI, provider);
    const dspBal = await diasporaContract.balanceOf(LIQUIDITY_TREASURY);
    const dspDecimals = await diasporaContract.decimals();
    console.log("  $DIASPORA Balance: ", ethers.formatUnits(dspBal, dspDecimals), "$DIASPORA");
  } catch (err) {
    console.error("  ❌ Failed to fetch $DIASPORA balance:", err.message);
  }

  console.log("=".repeat(60));
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
