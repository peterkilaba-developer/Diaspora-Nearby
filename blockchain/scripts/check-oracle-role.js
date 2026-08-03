import hre from "hardhat";

const TGE_CONTROLLER = "0xb6C049D47A2FaE5413c331760C22E715D0bF4d45";
const RAW_DEPLOYER = "0xeef494A14e6e66ec7c3E14e8674dCE2D99144dE6";

const TGE_ABI = [
  "function hasRole(bytes32 role, address account) view returns (bool)",
  "function TGE_ORACLE_ROLE() view returns (bytes32)",
];

async function main() {
  const connection = await hre.network.getOrCreate();
  const { ethers } = connection;
  const provider = ethers.provider;

  const deployer = ethers.getAddress(RAW_DEPLOYER.toLowerCase());
  const tge = new ethers.Contract(TGE_CONTROLLER, TGE_ABI, provider);
  const oracleRole = await tge.TGE_ORACLE_ROLE();
  const isOracle = await tge.hasRole(oracleRole, deployer);

  console.log("Deployer:", deployer);
  console.log("Has TGE_ORACLE_ROLE on TGEController:", isOracle);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
