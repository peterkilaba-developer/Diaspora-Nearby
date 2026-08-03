import hre from "hardhat";

const DESTINATION_METAMASK = "0xeef49F2a10f0EF143Cd8c710e013285F137F4dE6";
const SOURCE_ACCOUNT = "0xeEf494A14E6e66ec7c3E14E8674dCe2d99144de6";

const USDC_ADDRESS = "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913";
const TOKEN_ADDRESS = "0x55d7e7d006938A15082752225ED44Fd130B87735";

const ERC20_ABI = [
  "function transfer(address to, uint256 amount) external returns (bool)",
  "function balanceOf(address account) external view returns (uint256)",
];

async function main() {
  const connection = await hre.network.getOrCreate();
  const { ethers } = connection;
  const [signer] = await ethers.getSigners();

  console.log("=".repeat(60));
  console.log("  🚀 Transferring Pool Assets to Connected MetaMask Wallet");
  console.log("=".repeat(60));
  console.log("Source Wallet:     ", signer.address);
  console.log("Destination Wallet:", DESTINATION_METAMASK);

  const usdc = new ethers.Contract(USDC_ADDRESS, ERC20_ABI, signer);
  const token = new ethers.Contract(TOKEN_ADDRESS, ERC20_ABI, signer);

  const usdcBal = await usdc.balanceOf(signer.address);
  const dspBal = await token.balanceOf(signer.address);

  console.log("Current Source Balances:");
  console.log(`  USDC:      ${ethers.formatUnits(usdcBal, 6)}`);
  console.log(`  $DIASPORA: ${ethers.formatEther(dspBal)}`);

  if (usdcBal > 0n) {
    console.log(`Transferring ${ethers.formatUnits(usdcBal, 6)} USDC to ${DESTINATION_METAMASK}...`);
    const tx1 = await usdc.transfer(DESTINATION_METAMASK, usdcBal);
    await tx1.wait();
    console.log("  ✅ USDC Transfer Complete!");
  }

  if (dspBal > 0n) {
    console.log(`Transferring ${ethers.formatEther(dspBal)} $DIASPORA to ${DESTINATION_METAMASK}...`);
    const tx2 = await token.transfer(DESTINATION_METAMASK, dspBal);
    await tx2.wait();
    console.log("  ✅ $DIASPORA Transfer Complete!");
  }

  const finalUsdc = await usdc.balanceOf(DESTINATION_METAMASK);
  const finalDsp = await token.balanceOf(DESTINATION_METAMASK);

  console.log("=".repeat(60));
  console.log(`Destination Wallet (${DESTINATION_METAMASK}) Final Balances:`);
  console.log(`  USDC:      ${ethers.formatUnits(finalUsdc, 6)} USDC`);
  console.log(`  $DIASPORA: ${ethers.formatEther(finalDsp)} $DIASPORA`);
  console.log("=".repeat(60));
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
