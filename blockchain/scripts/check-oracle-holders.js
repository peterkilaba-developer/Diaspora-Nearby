import hre from "hardhat";

const TGE_CONTROLLER = "0xb6C049D47A2FaE5413c331760C22E715D0bF4d45";
const SAFE = "0xE06F8690e96a8BAAbCBe48664Ff1238F69082244";
const BACKEND_ORACLE = "0x881e6CD5cC081Bf85587A8DC585de1E664BB90A2";

const TGE_ABI = [
  "function hasRole(bytes32 role, address account) view returns (bool)",
  "function TGE_ORACLE_ROLE() view returns (bytes32)",
  "function DEFAULT_ADMIN_ROLE() view returns (bytes32)",
];

async function main() {
  const connection = await hre.network.getOrCreate();
  const { ethers } = connection;
  const provider = ethers.provider;

  const tge = new ethers.Contract(TGE_CONTROLLER, TGE_ABI, provider);
  const oracleRole = await tge.TGE_ORACLE_ROLE();
  const adminRole = await tge.DEFAULT_ADMIN_ROLE();

  console.log("Checking Safe:", SAFE);
  console.log("  Has TGE_ORACLE_ROLE:    ", await tge.hasRole(oracleRole, SAFE));
  console.log("  Has DEFAULT_ADMIN_ROLE:", await tge.hasRole(adminRole, SAFE));
  console.log();

  console.log("Checking Backend Oracle / Signer:", BACKEND_ORACLE);
  console.log("  Has TGE_ORACLE_ROLE:    ", await tge.hasRole(oracleRole, BACKEND_ORACLE));
  console.log("  Has DEFAULT_ADMIN_ROLE:", await tge.hasRole(adminRole, BACKEND_ORACLE));
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
