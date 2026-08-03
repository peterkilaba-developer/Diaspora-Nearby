import hre from "hardhat";

const LIQUIDITY_ADDRESS = "0xF0f15Cf38Ef463E0ff46DC0540489F466E222edB";

const SMART_WALLET_ABI = [
  "function owner() view returns (address)",
  "function execute(address target, uint256 value, bytes calldata data) external returns (bytes memory)",
];

async function main() {
  const connection = await hre.network.getOrCreate();
  const { ethers } = connection;
  const provider = ethers.provider;
  const [signer] = await ethers.getSigners();

  const lAddr = ethers.getAddress(LIQUIDITY_ADDRESS.toLowerCase());

  console.log("=".repeat(60));
  console.log("  🔍 Inspecting Liquidity Treasury Wallet Contract");
  console.log("=".repeat(60));
  console.log("Signer EOA:      ", signer.address);
  console.log("Treasury Address:", lAddr);

  const code = await provider.getCode(lAddr);
  console.log("Is Contract:     ", code !== "0x");

  if (code !== "0x") {
    try {
      const wallet = new ethers.Contract(lAddr, SMART_WALLET_ABI, provider);
      const owner = await wallet.owner();
      console.log("Wallet Owner:    ", owner);
      console.log("Signer is Owner: ", owner.toLowerCase() === signer.address.toLowerCase());
    } catch (e) {
      console.log("Could not read owner():", e.message);
    }
  }

  console.log("=".repeat(60));
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
