import hre from "hardhat";

const LIQUIDITY_ADDRESS = "0xF0f15Cf38Ef463E0ff46DC0540489F466E222edB";

const SAFE_ABI = [
  "function getOwners() view returns (address[])",
  "function getThreshold() view returns (uint256)",
];

const ERC1967_IMPL_SLOT = "0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc";

async function main() {
  const connection = await hre.network.getOrCreate();
  const { ethers } = connection;
  const provider = ethers.provider;

  const lAddr = ethers.getAddress(LIQUIDITY_ADDRESS.toLowerCase());
  const implSlotValue = await provider.getStorage(lAddr, ERC1967_IMPL_SLOT);
  console.log("Implementation Slot:", implSlotValue);

  try {
    const safe = new ethers.Contract(lAddr, SAFE_ABI, provider);
    const owners = await safe.getOwners();
    const threshold = await safe.getThreshold();
    console.log("Gnosis Safe Owners:", owners);
    console.log("Threshold:", threshold.toString());
  } catch (e) {
    console.log("Not a Gnosis Safe or failed to call getOwners():", e.message);
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
