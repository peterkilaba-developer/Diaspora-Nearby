/**
 * Repoint a system treasury slot in Firestore from an old smart-wallet address
 * to a new Safe (or any externally-controlled address).
 *
 * Run this AFTER `blockchain/scripts/admin/migrate-treasury-balance-to-safe.js`
 * has swept the on-chain balance into the Safe. This script only touches
 * Firestore — it does NOT move any tokens.
 *
 * What it updates:
 *   - governance/{slot}.walletAddress   = NEW_WALLET
 *   - governance/{slot}.walletType      = "safe"
 *   - governance/{slot}.previousWallet  = OLD_WALLET  (for audit trail)
 *   - governance/{slot}.repointedAt     = serverTimestamp
 *   - system_stats/treasury.{slot}Wallet     = NEW_WALLET
 *   - system_stats/treasury.{slot}WalletType = "safe"
 *
 * Slot ID → system_stats field name:
 *   founders         → foundersWallet
 *   liquidity        → liquidityWallet
 *   global_community → globalCommunityWallet
 *
 * Usage:
 *   SLOT=founders \
 *   NEW_WALLET=0xYourFoundersSafe \
 *   OLD_WALLET=0xda9073CbA407648d5EB3271F6B18CEbBd1290D3F \
 *     node functions/scripts/repoint-treasury-wallet.js
 *
 *   Add DRY_RUN=1 to print the patch without writing.
 *
 * Auth: uses Application Default Credentials (run `gcloud auth application-default
 * login` first, or set GOOGLE_APPLICATION_CREDENTIALS to a service-account JSON).
 */
const admin = require("firebase-admin");

const ALLOWED_SLOTS = {
  founders:         { sysField: "foundersWallet" },
  liquidity:        { sysField: "liquidityWallet" },
  global_community: { sysField: "globalCommunityWallet" },
};

function isAddress(addr) {
  return typeof addr === "string" && /^0x[0-9a-fA-F]{40}$/.test(addr);
}

async function main() {
  const slot = (process.env.SLOT || "").trim().toLowerCase();
  const newWallet = (process.env.NEW_WALLET || "").trim();
  const oldWallet = (process.env.OLD_WALLET || "").trim();
  const dryRun = process.env.DRY_RUN === "1";

  const slotSpec = ALLOWED_SLOTS[slot];
  if (!slotSpec) {
    console.error(`❌ SLOT must be one of: ${Object.keys(ALLOWED_SLOTS).join(", ")}`);
    console.error(`   Got: "${slot}"`);
    process.exit(1);
  }
  if (!isAddress(newWallet)) {
    console.error(`❌ NEW_WALLET is not a valid 0x-prefixed address: "${newWallet}"`);
    process.exit(1);
  }
  if (!isAddress(oldWallet)) {
    console.error(`❌ OLD_WALLET is not a valid 0x-prefixed address: "${oldWallet}"`);
    process.exit(1);
  }
  if (newWallet.toLowerCase() === oldWallet.toLowerCase()) {
    console.error(`❌ NEW_WALLET equals OLD_WALLET — nothing to repoint.`);
    process.exit(1);
  }

  const projectId =
    process.env.GCLOUD_PROJECT ||
    process.env.GOOGLE_CLOUD_PROJECT ||
    process.env.FIREBASE_PROJECT_ID ||
    "diaspora-nearby-a3dac";

  if (!admin.apps.length) {
    admin.initializeApp({
      credential: admin.credential.applicationDefault(),
      projectId,
    });
  }
  const db = admin.firestore();
  console.log(`(using project: ${projectId})`);

  const govRef = db.collection("governance").doc(slot);
  const sysRef = db.collection("system_stats").doc("treasury");

  const govSnap = await govRef.get();
  if (!govSnap.exists) {
    console.error(`❌ governance/${slot} does not exist. Aborting.`);
    process.exit(1);
  }
  const currentWallet = (govSnap.data() || {}).walletAddress;
  if (currentWallet && currentWallet.toLowerCase() !== oldWallet.toLowerCase()) {
    console.error(`❌ governance/${slot}.walletAddress is "${currentWallet}",`);
    console.error(`   but OLD_WALLET was passed as "${oldWallet}".`);
    console.error(`   Refusing to repoint — confirm the slot's current state before retrying.`);
    process.exit(1);
  }

  console.log(`Repointing slot "${slot}":`);
  console.log(`  governance/${slot}.walletAddress: ${currentWallet || "(unset)"} → ${newWallet}`);
  console.log(`  governance/${slot}.walletType:    "safe"`);
  console.log(`  system_stats/treasury.${slotSpec.sysField}: → ${newWallet}`);

  if (dryRun) {
    console.log(`\n🟡 DRY RUN — no writes. Re-run without DRY_RUN=1 to apply.`);
    return;
  }

  const now = admin.firestore.FieldValue.serverTimestamp();
  const batch = db.batch();

  batch.set(govRef, {
    walletAddress: newWallet,
    walletType: "safe",
    previousWallet: oldWallet,
    repointedAt: now,
    updatedAt: now,
  }, { merge: true });

  batch.set(sysRef, {
    [slotSpec.sysField]: newWallet,
    [`${slotSpec.sysField}Type`]: "safe",
    [`${slotSpec.sysField}RepointedAt`]: now,
  }, { merge: true });

  await batch.commit();
  console.log(`\n✅ Firestore updated. Future TGE distributions and UI reads will target the Safe.`);
  console.log(`   Old wallet ${oldWallet} is now a dead artifact.`);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
