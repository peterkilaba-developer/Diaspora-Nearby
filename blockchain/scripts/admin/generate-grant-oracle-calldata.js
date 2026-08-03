import hre from "hardhat";

const TGE_CONTROLLER = "0xb6C049D47A2FaE5413c331760C22E715D0bF4d45";
const DEPLOYER = "0xeEf494A14E6e66ec7c3E14E8674dCe2d99144de6";
const FOUNDER_KEY = "0x881e6CD5cC081Bf85587A8DC585de1E664BB90A2";

const TGE_ABI = [
  "function grantRole(bytes32 role, address account) external",
  "function TGE_ORACLE_ROLE() view returns (bytes32)",
];

async function main() {
  const connection = await hre.network.getOrCreate();
  const { ethers } = connection;
  const provider = ethers.provider;

  const tge = new ethers.Contract(TGE_CONTROLLER, TGE_ABI, provider);
  const oracleRole = await tge.TGE_ORACLE_ROLE();

  console.log("=".repeat(60));
  console.log("  📋 Safe Transaction Builder Calldata Generator");
  console.log("=".repeat(60));
  console.log("Target Contract (TGEController):", TGE_CONTROLLER);
  console.log("TGE_ORACLE_ROLE Hash:", oracleRole);
  console.log();

  const iface = new ethers.Interface(TGE_ABI);

  // Calldata for Deployer
  const calldataDeployer = iface.encodeFunctionData("grantRole", [
    oracleRole,
    ethers.getAddress(DEPLOYER.toLowerCase()),
  ]);

  // Calldata for Founder Key
  const calldataFounder = iface.encodeFunctionData("grantRole", [
    oracleRole,
    ethers.getAddress(FOUNDER_KEY.toLowerCase()),
  ]);

  console.log("1. Grant TGE_ORACLE_ROLE to Deployer EOA (0xeEf494...4de6):");
  console.log("   Calldata:", calldataDeployer);
  console.log();

  console.log("2. Grant TGE_ORACLE_ROLE to Founder Key (0x881e6...90A2):");
  console.log("   Calldata:", calldataFounder);
  console.log("=".repeat(60));
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
