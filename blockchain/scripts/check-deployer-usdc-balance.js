import hre from "hardhat";

const DEPLOYER_ADDRESS = "0xeef494A14e6e66ec7c3E14e8674dCe2d99144de6";
const USDC_ADDRESS = "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913";
const DIASPORA_ADDRESS = "0x55d7e7d006938A15082752225ED44Fd130B87735";

const ERC20_ABI = [
  "function balanceOf(address account) external view returns (uint256)",
  "function decimals() external view returns (uint8)",
];

async function main() {
  const connection = await hre.network.getOrCreate();
  const { ethers } = connection;
  const provider = ethers.provider;

  const addr = ethers.getAddress(DEPLOYER_ADDRESS.toLowerCase());
  const usdc = new ethers.Contract(USDC_ADDRESS, ERC20_ABI, provider);
  const dsp = new ethers.Contract(DIASPORA_ADDRESS, ERC20_ABI, provider);

  const usdcBal = await usdc.balanceOf(addr);
  const usdcDec = await usdc.decimals();

  const dspBal = await dsp.balanceOf(addr);
  const dspDec = await dsp.decimals();

  console.log("=".repeat(60));
  console.log("Deployer Address: ", addr);
  console.log("USDC Balance:     ", ethers.formatUnits(usdcBal, usdcDec), "USDC");
  console.log("$DIASPORA Balance:", ethers.formatUnits(dspBal, dspDec), "$DIASPORA");
  console.log("=".repeat(60));
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
