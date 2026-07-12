/**
 * Migrate DEFAULT_ADMIN_ROLE + UPGRADER_ROLE from the deployer EOA to a Gnosis Safe.
 *
 * Prerequisites:
 *   1. Create a 2-of-3 Gnosis Safe on Base at https://app.safe.global
 *   2. Set SAFE_ADDRESS below (or export SAFE_ADDRESS in env)
 *   3. Confirm signers on the Safe and back them up (hardware wallets recommended)
 *
 * What this script does (idempotent, safe to re-run):
 *   - Grants DEFAULT_ADMIN_ROLE on DiasporaToken to the Safe
 *   - Grants UPGRADER_ROLE on DiasporaToken to the Safe
 *   - Grants DEFAULT_ADMIN_ROLE on TGEController to the Safe
 *   - Grants UPGRADER_ROLE on TGEController to the Safe
 *   - Grants DEFAULT_ADMIN_ROLE on WalletFactory to the Safe
 *   - Prints follow-up steps the Safe needs to take (renouncing deployer's roles)
 *
 * Operational roles (TGE_ORACLE_ROLE, DEPLOYER_ROLE, MINTER_ROLE) are intentionally
 * left on the deployer EOA / backend signer — those are call-frequent and need a hot key.
 * Compromise of those keys is bounded (can burn the current epoch supply, can deploy
 * extra wallets) but cannot drain the project (no admin/upgrader privileges).
 *
 * Usage:
 *   SAFE_ADDRESS=0xYourSafeAddress \
 *     npx hardhat run scripts/admin/migrate-to-safe.js --network base-mainnet
 *
 * After this completes, ask the Safe signers to execute the second-phase script
 * (renounce deployer's roles) — see the printed instructions at the end.
 */
import hre from "hardhat";

const connection = await hre.network.getOrCreate();
const { ethers } = connection;

const TOKEN_ADDRESS = "0x55d7e7d006938A15082752225ED44Fd130B87735";
const TGE_ADDRESS = "0xb6C049D47A2FaE5413c331760C22E715D0bF4d45";
const FACTORY_ADDRESS = "0x9cF797cf332595c00410fc4ee9FdEe5C59501945";

async function main() {
  const safeAddress = process.env.SAFE_ADDRESS;
  if (!safeAddress || !ethers.isAddress(safeAddress)) {
    console.error("❌ SAFE_ADDRESS env var must be set to a valid address.");
    console.error("   Create a Safe at https://app.safe.global first.");
    process.exit(1);
  }

  const [deployer] = await ethers.getSigners();
  const network = await ethers.provider.getNetwork();
  if (network.chainId !== 8453n) {
    console.error(`❌ Wrong network. Expected Base Mainnet (8453), got ${network.chainId}.`);
    process.exit(1);
  }

  console.log("=".repeat(60));
  console.log("  Migrating admin roles → Gnosis Safe");
  console.log("=".repeat(60));
  console.log("  Deployer:", deployer.address);
  console.log("  Safe:    ", safeAddress);

  // Sanity check: Safe address must have code (be a contract)
  const safeCode = await ethers.provider.getCode(safeAddress);
  if (safeCode === "0x") {
    console.error(`❌ ${safeAddress} has no code — it's not a deployed contract.`);
    console.error("   Did you create the Safe yet? https://app.safe.global");
    process.exit(1);
  }

  const token = await ethers.getContractAt("DiasporaToken", TOKEN_ADDRESS);
  const tge = await ethers.getContractAt("DiasporaTGEController", TGE_ADDRESS);
  const factory = await ethers.getContractAt("DiasporaWalletFactory", FACTORY_ADDRESS);

  const DEFAULT_ADMIN_ROLE = await token.DEFAULT_ADMIN_ROLE();
  const UPGRADER_ROLE = await token.UPGRADER_ROLE();

  // ── Token ──
  console.log("\n📜 DiasporaToken:");
  if (await token.hasRole(DEFAULT_ADMIN_ROLE, safeAddress)) {
    console.log("   ✓ Safe already has DEFAULT_ADMIN_ROLE — skipping");
  } else {
    console.log("   → Granting DEFAULT_ADMIN_ROLE to Safe...");
    await (await token.grantRole(DEFAULT_ADMIN_ROLE, safeAddress)).wait();
  }
  if (await token.hasRole(UPGRADER_ROLE, safeAddress)) {
    console.log("   ✓ Safe already has UPGRADER_ROLE — skipping");
  } else {
    console.log("   → Granting UPGRADER_ROLE to Safe...");
    await (await token.grantRole(UPGRADER_ROLE, safeAddress)).wait();
  }

  // ── TGE Controller ──
  console.log("\n📜 DiasporaTGEController:");
  if (await tge.hasRole(DEFAULT_ADMIN_ROLE, safeAddress)) {
    console.log("   ✓ Safe already has DEFAULT_ADMIN_ROLE — skipping");
  } else {
    console.log("   → Granting DEFAULT_ADMIN_ROLE to Safe...");
    await (await tge.grantRole(DEFAULT_ADMIN_ROLE, safeAddress)).wait();
  }
  if (await tge.hasRole(UPGRADER_ROLE, safeAddress)) {
    console.log("   ✓ Safe already has UPGRADER_ROLE — skipping");
  } else {
    console.log("   → Granting UPGRADER_ROLE to Safe...");
    await (await tge.grantRole(UPGRADER_ROLE, safeAddress)).wait();
  }

  // ── Wallet Factory ──
  console.log("\n📜 DiasporaWalletFactory:");
  if (await factory.hasRole(DEFAULT_ADMIN_ROLE, safeAddress)) {
    console.log("   ✓ Safe already has DEFAULT_ADMIN_ROLE — skipping");
  } else {
    console.log("   → Granting DEFAULT_ADMIN_ROLE to Safe...");
    await (await factory.grantRole(DEFAULT_ADMIN_ROLE, safeAddress)).wait();
  }

  console.log("\n" + "=".repeat(60));
  console.log("  ✅ Safe now holds admin/upgrader on all 3 contracts.");
  console.log("=".repeat(60));
  console.log("\n📋 NEXT STEPS — execute these from the Safe (NOT from the deployer):\n");
  console.log("   On DiasporaToken:");
  console.log(`     renounceRole(DEFAULT_ADMIN_ROLE, ${deployer.address})`);
  console.log(`     renounceRole(UPGRADER_ROLE,     ${deployer.address})`);
  console.log("   On DiasporaTGEController:");
  console.log(`     renounceRole(DEFAULT_ADMIN_ROLE, ${deployer.address})`);
  console.log(`     renounceRole(UPGRADER_ROLE,     ${deployer.address})`);
  console.log("   On DiasporaWalletFactory:");
  console.log(`     renounceRole(DEFAULT_ADMIN_ROLE, ${deployer.address})`);
  console.log("\n   These calls must be initiated through the Safe transaction builder");
  console.log("   (https://app.safe.global → Apps → Transaction Builder), since");
  console.log("   renouncing a role requires the caller to BE the role-holder.");
  console.log("\n   Roles intentionally LEFT on the deployer (operational keys):");
  console.log("     - DiasporaToken.MINTER_ROLE (revoked separately by revoke-deployer-minter.js)");
  console.log("     - DiasporaTGEController.TGE_ORACLE_ROLE");
  console.log("     - DiasporaWalletFactory.DEPLOYER_ROLE");
}

main().catch((e) => {
  console.error(e);
  process.exitCode = 1;
});
