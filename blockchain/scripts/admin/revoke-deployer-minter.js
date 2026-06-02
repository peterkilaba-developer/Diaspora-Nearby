/**
 * Revoke MINTER_ROLE from the deployer EOA on the live $DIASPORA token.
 *
 * Before: deployer EOA can call token.mint() directly (bypasses TGE accounting).
 * After:  only DiasporaTGEController can mint. Deployer continues to drive minting
 *         indirectly via TGEController.mintEpochSupply() (which requires
 *         TGE_ORACLE_ROLE, still held by deployer).
 *
 * Reversible: if DEFAULT_ADMIN_ROLE is still on the deployer, the deployer can
 * grant MINTER_ROLE back to itself at any time. After migrate-to-safe.js has
 * renounced DEFAULT_ADMIN_ROLE from the deployer, this becomes irreversible
 * (the Safe would need to re-grant).
 *
 * Verifies pre/post state. Usage:
 *   npx hardhat run scripts/admin/revoke-deployer-minter.js --network base-mainnet
 */
const { ethers } = require("hardhat");

const TOKEN_ADDRESS = "0x55d7e7d006938A15082752225ED44Fd130B87735";
const TGE_ADDRESS = "0xb6C049D47A2FaE5413c331760C22E715D0bF4d45";

async function main() {
  const [deployer] = await ethers.getSigners();
  const network = await ethers.provider.getNetwork();
  if (network.chainId !== 8453n) {
    console.error(`❌ Wrong network. Expected Base Mainnet (8453), got ${network.chainId}.`);
    process.exit(1);
  }

  console.log("=".repeat(60));
  console.log("  Revoke MINTER_ROLE from deployer EOA");
  console.log("=".repeat(60));
  console.log("  Deployer:", deployer.address);
  console.log("  Token:   ", TOKEN_ADDRESS);

  const token = await ethers.getContractAt("DiasporaToken", TOKEN_ADDRESS);
  const MINTER_ROLE = await token.MINTER_ROLE();

  const deployerHas = await token.hasRole(MINTER_ROLE, deployer.address);
  const tgeHas = await token.hasRole(MINTER_ROLE, TGE_ADDRESS);

  console.log("\n  Current state:");
  console.log("    Deployer MINTER_ROLE:", deployerHas);
  console.log("    TGE      MINTER_ROLE:", tgeHas);

  if (!tgeHas) {
    console.error("\n❌ ABORT: TGE controller does NOT have MINTER_ROLE.");
    console.error("   Revoking the deployer's role now would brick all future minting.");
    console.error("   Grant MINTER_ROLE to the TGE controller first.");
    process.exit(1);
  }

  if (!deployerHas) {
    console.log("\n  ✓ Deployer already does not have MINTER_ROLE — nothing to do.");
    return;
  }

  console.log("\n  → Revoking MINTER_ROLE from deployer...");
  const tx = await token.revokeRole(MINTER_ROLE, deployer.address);
  console.log("    tx:", tx.hash);
  await tx.wait();
  console.log("    ✅ revoked");

  // Post-check
  const stillHas = await token.hasRole(MINTER_ROLE, deployer.address);
  if (stillHas) {
    console.error("\n❌ Post-check failed: deployer STILL has MINTER_ROLE.");
    process.exit(1);
  }
  console.log("\n  Final state:");
  console.log("    Deployer MINTER_ROLE: false ✓");
  console.log("    TGE      MINTER_ROLE: true  ✓");
  console.log("\n✅ MINTER_ROLE consolidated to TGE controller only.");
}

main().catch((e) => {
  console.error(e);
  process.exitCode = 1;
});
