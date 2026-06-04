/**
 * Audit governance/* docs for TGE readiness.
 *
 * Post-TGE-1 forensic: the silent-skip path in performTGE() dropped every
 * community treasury that was missing walletAddress, and zero-defaulted every
 * one that was missing averagePoCT. The hardened performTGE() now refuses to
 * fire when any governance doc with treasuryBalance > 0 has either field
 * missing. Run this script before any TGE attempt to surface the problems
 * up front instead of finding them at execution time.
 *
 * Usage:
 *   GOOGLE_APPLICATION_CREDENTIALS=/path/to/sa.json \
 *     node functions/scripts/audit-governance-tge-readiness.js
 *
 * Exits non-zero if any blocking issue is found, so CI can gate on it.
 */
const admin = require("firebase-admin");

if (!admin.apps.length) {
  admin.initializeApp({
    credential: admin.credential.applicationDefault(),
    projectId: process.env.GCLOUD_PROJECT || "diaspora-nearby",
  });
}

const db = admin.firestore();
const SYSTEM_DOC_IDS = new Set(["founders", "liquidity", "investors", "burn"]);

async function main() {
  console.log("=== Governance / TGE readiness audit ===\n");

  const snap = await db.collection("governance").get();
  console.log(`Found ${snap.size} governance docs\n`);

  const blocking = [];
  const warnings = [];
  let okCount = 0;
  let zeroBalanceCount = 0;

  for (const doc of snap.docs) {
    const d = doc.data();
    const id = doc.id;
    const bal = d.treasuryBalance || 0;
    const wallet = d.walletAddress;
    const avgPoCT = d.averagePoCT;
    const isSystem = SYSTEM_DOC_IDS.has(id);

    if (bal <= 0) {
      zeroBalanceCount++;
      // System docs with zero balance and no wallet are fine — they'll be
      // skipped by performTGE's "no funds, no problem" path. Surface as a
      // soft warning only if it's a system doc you might want to re-wire.
      if (isSystem && (!wallet || wallet.length < 10)) {
        warnings.push(`governance/${id}: SYSTEM treasury missing walletAddress (no balance today, but you'll want this set before more accrues)`);
      }
      continue;
    }

    if (!wallet || wallet.length < 10) {
      if (isSystem) {
        warnings.push(
          `governance/${id}: SYSTEM treasury has treasuryBalance=${bal} but no walletAddress — performTGE will skip this slot with a WARN log. Set either the env override or the govDoc.walletAddress to include it.`
        );
      } else {
        blocking.push(
          `governance/${id}: treasuryBalance=${bal} but walletAddress is ${JSON.stringify(wallet)} — performTGE will throw`
        );
      }
      continue;
    }

    if (!isSystem && (avgPoCT === undefined || avgPoCT === null)) {
      blocking.push(
        `governance/${id}: treasuryBalance=${bal}, wallet=${wallet}, but averagePoCT is unset — performTGE will throw (would have silently burned 100% in V1)`
      );
      continue;
    }

    if (!isSystem && avgPoCT === 0) {
      warnings.push(
        `governance/${id}: averagePoCT=0 → efficiency=0 → 100% of ${bal} DSP would be burned. Confirm this is intentional.`
      );
    }

    okCount++;
  }

  console.log(`OK:                ${okCount}`);
  console.log(`Zero-balance:      ${zeroBalanceCount}`);
  console.log(`Warnings:          ${warnings.length}`);
  console.log(`Blocking issues:   ${blocking.length}\n`);

  if (warnings.length > 0) {
    console.log("--- WARNINGS ---");
    warnings.forEach((w) => console.log("  " + w));
    console.log();
  }

  if (blocking.length > 0) {
    console.log("--- BLOCKING ISSUES (performTGE will refuse to fire) ---");
    blocking.forEach((b) => console.log("  " + b));
    console.log();
    process.exit(1);
  }

  console.log("✅ Governance docs are TGE-ready.");
}

main().catch((err) => {
  console.error("Audit failed:", err);
  process.exit(2);
});
