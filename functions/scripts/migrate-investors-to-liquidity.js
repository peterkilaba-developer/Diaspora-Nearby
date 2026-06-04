/**
 * One-shot Firestore migration: investors → liquidity rename.
 *
 * Context: pre-2026-06-04 the system treasury slot now called "Liquidity (DEX)"
 * was historically called "Investors & Partners". The on-chain side was already
 * migrated (governance/liquidity.walletAddress points at the Liquidity Safe),
 * but two streams of DSP-point data still flow to the legacy "investors"
 * names:
 *
 *   • governance/investors.treasuryBalance   ← should be governance/liquidity.treasuryBalance
 *   • system_stats/treasury.investorsPoints  ← should be system_stats/treasury.liquidityPoints
 *
 * This script:
 *   1. Reads both legacy + canonical values for both balances.
 *   2. Sums legacy into canonical (idempotent — re-running on already-migrated
 *      data is a no-op because legacy will be 0).
 *   3. Zeros the legacy field so a re-run is safe and so it's obvious in
 *      Firestore that the migration ran.
 *   4. Does NOT delete the governance/investors doc — kept as an audit trail
 *      pointing at the old (abandoned) smart wallet.
 *
 * Run order:
 *   (a) Deploy the new backend (functions/lib/dsp.js) that writes to
 *       governance/liquidity / liquidityPoints, NOT investors. This stops
 *       the bleeding.
 *   (b) Run this script LIVE so the existing legacy balance moves to the
 *       canonical doc.
 *   (c) Deploy the updated Flutter app that reads the canonical doc.
 *
 * If (b) runs before (a), new awards land in governance/investors and get
 * orphaned. Better: dry-run first to see the numbers, deploy backend,
 * then run live.
 *
 * Usage:
 *   DRY_RUN=1 node functions/scripts/migrate-investors-to-liquidity.js
 *   # then live:
 *   node functions/scripts/migrate-investors-to-liquidity.js
 *
 * Auth: ADC. Set GOOGLE_APPLICATION_CREDENTIALS to a service-account JSON
 * if not using gcloud auth.
 */
const admin = require("firebase-admin");

async function main() {
  const dryRun = process.env.DRY_RUN === "1";

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
  console.log(`Mode: ${dryRun ? "DRY RUN (no writes)" : "LIVE"}`);

  // ── 1. Read governance/investors and governance/liquidity ──
  const govInvRef = db.collection("governance").doc("investors");
  const govLiqRef = db.collection("governance").doc("liquidity");
  const sysRef = db.collection("system_stats").doc("treasury");

  const [govInvSnap, govLiqSnap, sysSnap] = await Promise.all([
    govInvRef.get(),
    govLiqRef.get(),
    sysRef.get(),
  ]);

  const govInv = govInvSnap.exists ? (govInvSnap.data() || {}) : {};
  const govLiq = govLiqSnap.exists ? (govLiqSnap.data() || {}) : {};
  const sys = sysSnap.exists ? (sysSnap.data() || {}) : {};

  const invTreasury = Number(govInv.treasuryBalance) || 0;
  const liqTreasury = Number(govLiq.treasuryBalance) || 0;
  const invPoints = Number(sys.investorsPoints) || 0;
  const liqPoints = Number(sys.liquidityPoints) || 0;

  console.log(`
Current state:
  governance/investors.treasuryBalance:   ${invTreasury}
  governance/liquidity.treasuryBalance:   ${liqTreasury}
  system_stats/treasury.investorsPoints:  ${invPoints}
  system_stats/treasury.liquidityPoints:  ${liqPoints}
`);

  const newLiqTreasury = liqTreasury + invTreasury;
  const newLiqPoints = liqPoints + invPoints;

  console.log(`Will sum to:
  governance/liquidity.treasuryBalance:   ${liqTreasury} + ${invTreasury} = ${newLiqTreasury}
  system_stats/treasury.liquidityPoints:  ${liqPoints} + ${invPoints} = ${newLiqPoints}

Then zero:
  governance/investors.treasuryBalance:   0
  system_stats/treasury.investorsPoints:  0
`);

  if (invTreasury === 0 && invPoints === 0) {
    console.log("✅ Nothing to migrate — legacy balances are already zero. Safe to re-run.");
    return;
  }

  if (!govLiqSnap.exists) {
    console.error(`❌ governance/liquidity does not exist. Aborting — the canonical doc must exist before migration (it should have walletAddress = Liquidity Safe).`);
    process.exit(1);
  }

  if (dryRun) {
    console.log("🟡 DRY RUN — no writes. Re-run without DRY_RUN=1 to apply.");
    return;
  }

  // ── 2. Apply the migration atomically ──
  const now = admin.firestore.FieldValue.serverTimestamp();
  const batch = db.batch();

  if (invTreasury > 0) {
    batch.set(govLiqRef, {
      treasuryBalance: newLiqTreasury,
      mergedFromInvestorsAt: now,
      updatedAt: now,
    }, { merge: true });

    batch.set(govInvRef, {
      treasuryBalance: 0,
      // Keep id/name/walletAddress untouched so the doc remains as an audit
      // trail. Just stamp the migration.
      migratedToLiquidityAt: now,
      migratedAmount: invTreasury,
      updatedAt: now,
    }, { merge: true });
  }

  if (invPoints > 0) {
    batch.set(sysRef, {
      liquidityPoints: newLiqPoints,
      investorsPoints: 0,
      investorsPointsMigratedToLiquidityAt: now,
      investorsPointsMigratedAmount: invPoints,
    }, { merge: true });
  }

  await batch.commit();
  console.log(`
✅ Migration committed.
   governance/liquidity.treasuryBalance:   ${newLiqTreasury}
   governance/investors.treasuryBalance:   0  (was ${invTreasury})
   system_stats/treasury.liquidityPoints:  ${newLiqPoints}
   system_stats/treasury.investorsPoints:  0  (was ${invPoints})
`);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
