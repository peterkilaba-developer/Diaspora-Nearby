/**
 * Renounce DEFAULT_ADMIN_ROLE and UPGRADER_ROLE from the deployer EOA on the
 * live token, TGE controller, and wallet factory.
 *
 * Prerequisites: scripts/admin/migrate-to-safe.js must have been run first so
 * the Safe holds those roles. This script verifies that before renouncing.
 *
 * `renounceRole(role, account)` requires `msg.sender == account` per OZ
 * AccessControl, so the deployer EOA must be the signer — not the Safe.
 *
 * Idempotent: safe to re-run.
 *
 * Usage:
 *   npx hardhat run scripts/admin/renounce-deployer-roles.js --network base-mainnet
 */
import hre from "hardhat";

const connection = await hre.network.getOrCreate();
const { ethers } = connection;

const TOKEN_ADDRESS = "0x55d7e7d006938A15082752225ED44Fd130B87735";
const TGE_ADDRESS = "0xb6C049D47A2FaE5413c331760C22E715D0bF4d45";
const FACTORY_ADDRESS = "0x9cF797cf332595c00410fc4ee9FdEe5C59501945";
const SAFE_ADDRESS = "0xE06F8690e96a8BAAbCBe48664Ff1238F69082244";

async function renounceIfHeld(contract, role, roleName, deployer, label) {
  const has = await contract.hasRole(role, deployer);
  if (!has) {
    console.log(`   ✓ Deployer doesn't hold ${roleName} on ${label} — skipping`);
    return;
  }
  // Safety check: the Safe MUST hold the role before we drop it from the deployer,
  // otherwise we permanently lock the role.
  const safeHas = await contract.hasRole(role, SAFE_ADDRESS);
  if (!safeHas) {
    throw new Error(
      `ABORT: Safe ${SAFE_ADDRESS} does NOT hold ${roleName} on ${label}. ` +
        `Run migrate-to-safe.js first or this would permanently lose the role.`
    );
  }
  console.log(`   → Renouncing ${roleName} on ${label}...`);
  const tx = await contract.renounceRole(role, deployer);
  await tx.wait();
  console.log(`     ✅ ${tx.hash}`);
}

async function main() {
  const [deployer] = await ethers.getSigners();
  const network = await ethers.provider.getNetwork();
  if (network.chainId !== 8453n) {
    console.error(`❌ Wrong network. Expected Base Mainnet (8453), got ${network.chainId}.`);
    process.exit(1);
  }

  console.log("=".repeat(60));
  console.log("  Renounce deployer admin/upgrader roles");
  console.log("=".repeat(60));
  console.log("  Deployer:", deployer.address);
  console.log("  Safe:    ", SAFE_ADDRESS);

  const token = await ethers.getContractAt("DiasporaToken", TOKEN_ADDRESS);
  const tge = await ethers.getContractAt("DiasporaTGEController", TGE_ADDRESS);
  const factory = await ethers.getContractAt("DiasporaWalletFactory", FACTORY_ADDRESS);

  const DEFAULT_ADMIN_ROLE = await token.DEFAULT_ADMIN_ROLE();
  const UPGRADER_ROLE = await token.UPGRADER_ROLE();

  console.log("\n📜 DiasporaToken:");
  await renounceIfHeld(token, DEFAULT_ADMIN_ROLE, "DEFAULT_ADMIN_ROLE", deployer.address, "DiasporaToken");
  await renounceIfHeld(token, UPGRADER_ROLE,      "UPGRADER_ROLE",      deployer.address, "DiasporaToken");

  console.log("\n📜 DiasporaTGEController:");
  await renounceIfHeld(tge,   DEFAULT_ADMIN_ROLE, "DEFAULT_ADMIN_ROLE", deployer.address, "DiasporaTGEController");
  await renounceIfHeld(tge,   UPGRADER_ROLE,      "UPGRADER_ROLE",      deployer.address, "DiasporaTGEController");

  console.log("\n📜 DiasporaWalletFactory:");
  await renounceIfHeld(factory, DEFAULT_ADMIN_ROLE, "DEFAULT_ADMIN_ROLE", deployer.address, "DiasporaWalletFactory");

  console.log("\n" + "=".repeat(60));
  console.log("  ✅ Deployer admin/upgrader roles renounced.");
  console.log("=".repeat(60));
  console.log("\n  The Safe is now the sole holder of DEFAULT_ADMIN_ROLE and");
  console.log("  UPGRADER_ROLE on all three contracts.");
  console.log("\n  Deployer still holds (intentional — operational keys):");
  console.log("    - DiasporaTGEController.TGE_ORACLE_ROLE  (mint epoch supply, execute TGE)");
  console.log("    - DiasporaWalletFactory.DEPLOYER_ROLE    (create user wallets)");
  console.log("\n  If you ever need to upgrade contracts or grant new roles, do");
  console.log("  it through the Safe at https://app.safe.global");
}

main().catch((e) => {
  console.error(e);
  process.exitCode = 1;
});
