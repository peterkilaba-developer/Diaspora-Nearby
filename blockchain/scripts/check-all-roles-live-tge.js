import hre from "hardhat";

const TGE = "0xb6C049D47A2FaE5413c331760C22E715D0bF4d45";

const ACCOUNTS = [
  "0xeef494A14e6e66ec7c3E14e8674dCE2D99144dE6", // Deployer
  "0xE06F8690e96a8BAAbCBe48664Ff1238F69082244", // Admin Safe
  "0x881e6CD5cC081Bf85587A8DC585de1E664BB90A2", // Founders key
];

const TGE_ABI = [
  "function hasRole(bytes32 role, address account) view returns (bool)",
  "function TGE_ORACLE_ROLE() view returns (bytes32)",
  "function DEFAULT_ADMIN_ROLE() view returns (bytes32)",
];

async function main() {
  const connection = await hre.network.getOrCreate();
  const { ethers } = connection;
  const provider = ethers.provider;

  const tge = new ethers.Contract(TGE, TGE_ABI, provider);
  const oracleRole = await tge.TGE_ORACLE_ROLE();
  const adminRole = await tge.DEFAULT_ADMIN_ROLE();

  console.log("=".repeat(60));
  console.log("TGE Controller:", TGE);
  console.log("=".repeat(60));

  for (const raw of ACCOUNTS) {
    const acc = ethers.getAddress(raw.toLowerCase());
    const isOracle = await tge.hasRole(oracleRole, acc);
    const isAdmin = await tge.hasRole(adminRole, acc);
    console.log(`Account: ${acc}`);
    console.log(`  TGE_ORACLE_ROLE:    ${isOracle}`);
    console.log(`  DEFAULT_ADMIN_ROLE: ${isAdmin}`);
    console.log();
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
