import hre from "hardhat";

const PROXY = "0xb6C049D47A2FaE5413c331760C22E715D0bF4d45";
const ERC1967_IMPL_SLOT = "0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc";

async function main() {
  const connection = await hre.network.getOrCreate();
  const { ethers } = connection;
  const provider = ethers.provider;

  const implSlotValue = await provider.getStorage(PROXY, ERC1967_IMPL_SLOT);
  const implAddress = ethers.getAddress("0x" + implSlotValue.slice(26));

  console.log("Proxy Address:         ", PROXY);
  console.log("Implementation Address:", implAddress);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
