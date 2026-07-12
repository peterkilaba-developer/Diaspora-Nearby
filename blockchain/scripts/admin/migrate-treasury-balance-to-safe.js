/**
 * Sweep a system-treasury smart wallet's full $DIASPORA balance into a Gnosis Safe.
 *
 * Why this script exists
 * ──────────────────────
 * The system treasuries (Founders & Team, Liquidity DEX, Global Fund Reserve)
 * are currently DiasporaSmartWallet contracts whose `owner` is the backend
 * signer EOA. That means a single hot key controls every treasury — unacceptable
 * for a community-owned token.
 *
 * Ideal fix would be `setOwner(safe)` on each smart wallet. But the wallet
 * contract's `changeOwner` is `onlyFactory`, and the factory exposes no
 * external function that calls it. So the ownership pointer is effectively
 * permanent. The practical workaround: drain the treasury smart wallet's
 * full balance into a Safe, then repoint `governance/{slot}.walletAddress`
 * in Firestore so all future TGE distributions and UI reads target the Safe.
 *
 * What this script does (idempotent on completion — re-running on a zero
 * balance is a no-op):
 *   1. Validates env (SLOT, SAFE_ADDRESS, OLD_TREASURY_ADDRESS)
 *   2. Confirms backend signer is the smart wallet's `owner`
 *   3. Reads current $DIASPORA balance of the old treasury
 *   4. Calls oldTreasury.transferToken(DIASPORA, safe, fullBalance)
 *   5. Verifies post-state: old=0, safe=balance moved
 *   6. Prints the exact Firestore patch the operator must apply next
 *
 * It does NOT touch Firestore. That step is intentionally manual / done by
 * `functions/scripts/repoint-treasury-wallet.js` so the operator can confirm
 * the on-chain sweep before flipping the pointer.
 *
 * Usage:
 *   SLOT=founders \
 *   SAFE_ADDRESS=0xYourFoundersSafe \
 *   OLD_TREASURY_ADDRESS=0xda9073CbA407648d5EB3271F6B18CEbBd1290D3F \
 *     npx hardhat run scripts/admin/migrate-treasury-balance-to-safe.js --network base-mainnet
 *
 *   Add DRY_RUN=1 to simulate without sending the transfer.
 *
 * Prerequisites:
 *   - The Safe is already created on Base via https://app.safe.global
 *   - The Safe's signers are confirmed and have access (hardware wallets recommended)
 *   - You hold BACKEND_SIGNER_PRIVATE_KEY (the EOA that owns the smart wallet)
 */
import hre from "hardhat";

const connection = await hre.network.getOrCreate();
const { ethers } = connection;

const TOKEN_ADDRESS = "0x55d7e7d006938A15082752225ED44Fd130B87735";

const ALLOWED_SLOTS = new Set(["founders", "liquidity", "global_community"]);

async function main() {
  const slot = (process.env.SLOT || "").trim().toLowerCase();
  const safeAddress = (process.env.SAFE_ADDRESS || "").trim();
  const oldTreasury = (process.env.OLD_TREASURY_ADDRESS || "").trim();
  const dryRun = process.env.DRY_RUN === "1";

  if (!ALLOWED_SLOTS.has(slot)) {
    console.error(`❌ SLOT must be one of: ${[...ALLOWED_SLOTS].join(", ")}`);
    console.error(`   Got: "${slot}"`);
    console.error(`   Note: community treasuries are NOT migrated here — they are`);
    console.error(`   spent only via DDI/FDDI governance votes, not via Safe.`);
    process.exit(1);
  }
  if (!ethers.isAddress(safeAddress)) {
    console.error(`❌ SAFE_ADDRESS is not a valid address: "${safeAddress}"`);
    console.error(`   Create a Safe at https://app.safe.global first.`);
    process.exit(1);
  }
  if (!ethers.isAddress(oldTreasury)) {
    console.error(`❌ OLD_TREASURY_ADDRESS is not a valid address: "${oldTreasury}"`);
    process.exit(1);
  }
  if (safeAddress.toLowerCase() === oldTreasury.toLowerCase()) {
    console.error(`❌ SAFE_ADDRESS equals OLD_TREASURY_ADDRESS — nothing to migrate.`);
    process.exit(1);
  }

  const [signer] = await ethers.getSigners();
  const network = await ethers.provider.getNetwork();
  if (network.chainId !== 8453n) {
    console.error(`❌ Wrong network. Expected Base Mainnet (8453), got ${network.chainId}.`);
    process.exit(1);
  }

  console.log("=".repeat(64));
  console.log(`  Treasury balance migration — slot: ${slot}`);
  console.log("=".repeat(64));
  console.log(`  Signer (backend):    ${signer.address}`);
  console.log(`  Old treasury wallet: ${oldTreasury}`);
  console.log(`  New Safe address:    ${safeAddress}`);
  console.log(`  Mode:                ${dryRun ? "DRY RUN (no tx)" : "LIVE"}`);

  // Safe must be a deployed contract — protects against typos sending funds
  // to a CREATE2 prediction that hasn't been deployed yet.
  const safeCode = await ethers.provider.getCode(safeAddress);
  if (safeCode === "0x") {
    console.error(`\n❌ Safe address ${safeAddress} has no contract code on Base.`);
    console.error(`   Deploy the Safe at https://app.safe.global before running this script.`);
    process.exit(1);
  }

  // Old treasury must be a deployed smart wallet
  const oldCode = await ethers.provider.getCode(oldTreasury);
  if (oldCode === "0x") {
    console.error(`\n❌ Old treasury ${oldTreasury} has no contract code on Base.`);
    console.error(`   Either it was never deployed via the factory, or you have the`);
    console.error(`   wrong address. Confirm against governance/${slot}.walletAddress.`);
    process.exit(1);
  }

  const wallet = await ethers.getContractAt("DiasporaSmartWallet", oldTreasury);
  const token = await ethers.getContractAt("DiasporaToken", TOKEN_ADDRESS);

  const currentOwner = await wallet.owner();
  if (currentOwner.toLowerCase() !== signer.address.toLowerCase()) {
    console.error(`\n❌ Signer is not the owner of the old treasury wallet.`);
    console.error(`   wallet.owner() = ${currentOwner}`);
    console.error(`   signer         = ${signer.address}`);
    console.error(`   You must run this script with BACKEND_SIGNER_PRIVATE_KEY.`);
    process.exit(1);
  }

  const decimals = await token.decimals();
  const fmt = (v) => ethers.formatUnits(v, decimals);

  const oldBalBefore = await token.balanceOf(oldTreasury);
  const safeBalBefore = await token.balanceOf(safeAddress);

  console.log(`\n📊 Before:`);
  console.log(`   Old treasury: ${fmt(oldBalBefore)} $DIASPORA`);
  console.log(`   Safe:         ${fmt(safeBalBefore)} $DIASPORA`);

  if (oldBalBefore === 0n) {
    console.log(`\n✅ Old treasury balance is already 0 — nothing to sweep.`);
    console.log(`   If the Safe is the live treasury, the migration is complete.`);
    console.log(`   Apply the Firestore patch below if you haven't yet:\n`);
    printFirestorePatch(slot, safeAddress, oldTreasury);
    return;
  }

  if (dryRun) {
    console.log(`\n🟡 DRY RUN — would call:`);
    console.log(`     wallet.transferToken(${TOKEN_ADDRESS}, ${safeAddress}, ${oldBalBefore.toString()})`);
    console.log(`     (= ${fmt(oldBalBefore)} $DIASPORA)`);
    console.log(`\n   Re-run without DRY_RUN=1 to execute.`);
    return;
  }

  console.log(`\n💸 Sweeping ${fmt(oldBalBefore)} $DIASPORA → Safe...`);
  const tx = await wallet.transferToken(TOKEN_ADDRESS, safeAddress, oldBalBefore);
  console.log(`   TX: ${tx.hash}`);
  const receipt = await tx.wait();
  console.log(`   ✅ Confirmed in block ${receipt.blockNumber} (gas ${receipt.gasUsed.toString()})`);

  const oldBalAfter = await token.balanceOf(oldTreasury);
  const safeBalAfter = await token.balanceOf(safeAddress);
  console.log(`\n📊 After:`);
  console.log(`   Old treasury: ${fmt(oldBalAfter)} $DIASPORA`);
  console.log(`   Safe:         ${fmt(safeBalAfter)} $DIASPORA`);

  if (oldBalAfter !== 0n) {
    console.error(`\n❌ Post-sweep old balance is non-zero. Something went wrong — investigate before repointing Firestore.`);
    process.exitCode = 1;
    return;
  }
  if (safeBalAfter - safeBalBefore !== oldBalBefore) {
    console.error(`\n❌ Safe balance delta (${fmt(safeBalAfter - safeBalBefore)}) does not equal sweep amount (${fmt(oldBalBefore)}).`);
    process.exitCode = 1;
    return;
  }

  console.log(`\n` + "=".repeat(64));
  console.log(`  ✅ On-chain sweep complete.`);
  console.log("=".repeat(64));
  printFirestorePatch(slot, safeAddress, oldTreasury);
}

function printFirestorePatch(slot, safeAddress, oldTreasury) {
  console.log(`\n📋 NEXT STEP — repoint the treasury in Firestore so future TGEs target the Safe.`);
  console.log(`   Run from project root (uses firebase-admin):\n`);
  console.log(`     SLOT=${slot} \\`);
  console.log(`     NEW_WALLET=${safeAddress} \\`);
  console.log(`     OLD_WALLET=${oldTreasury} \\`);
  console.log(`       node functions/scripts/repoint-treasury-wallet.js`);
  console.log(`\n   After that, the governance/${slot}.walletAddress and the matching`);
  console.log(`   system_stats/treasury.*Wallet field will both point at the Safe.`);
  console.log(`   The old smart wallet at ${oldTreasury} becomes a dead artifact;`);
  console.log(`   any stray future deposits to it are still recoverable by the backend signer.`);
}

main().catch((e) => {
  console.error(e);
  process.exitCode = 1;
});
