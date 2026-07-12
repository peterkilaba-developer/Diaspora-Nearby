/**
 * Backfill: rebuild trust_data.flaggedMessagesCount from the reports collection.
 *
 * Why this exists:
 *   Prior to the v8 fix this field had a triple-bug — recordActivity only
 *   incremented at exact multiples of 10 reporters, recalculateTrustScore
 *   then clobbered the trust_data value with profile.flaggedMessagesCount
 *   (which nothing writes to), and the penalty formula divided again by 10.
 *   Net effect: the spam/ad penalty has been silently zero for every user
 *   regardless of how often they were reported.
 *
 *   The post-fix code increments trust_data.flaggedMessagesCount by 1 per
 *   unique reporter and applies -10 PoCT per 10 flags. This script seeds
 *   that counter with the true count of unique reporters per user, drawn
 *   from the `reports` collection (the only source of truth that survived
 *   the bug).
 *
 * What it does:
 *   For each user that appears as `reportedUserId` in `reports`, count the
 *   number of UNIQUE reporters across BOTH message-type and user-type reports,
 *   and write that number to `trust_data/{userId}.flaggedMessagesCount`.
 *
 *   Idempotent — re-running with the same data produces the same result.
 *   Will OVERWRITE the existing trust_data value (which is the point — the
 *   stored value is wrong under the pre-fix bug).
 *
 *   Skips users whose true count is 0 (nothing to write) and users whose
 *   trust_data already matches the computed count (no-op).
 *
 *   Defaults to dry-run. Pass --apply to actually write.
 *
 * Run:
 *   cd functions
 *   $env:GOOGLE_APPLICATION_CREDENTIALS = "C:\path\to\service-account.json"
 *   node scripts/backfill-flagged-messages.js           # dry run
 *   node scripts/backfill-flagged-messages.js --apply   # write
 */
const admin = require("firebase-admin");

const APPLY = process.argv.includes("--apply");

if (admin.apps.length === 0) {
  admin.initializeApp({
    credential: admin.credential.applicationDefault(),
  });
}
const db = admin.firestore();

async function main() {
  const mode = APPLY ? "APPLYING CHANGES" : "DRY RUN";
  console.log(`\n🚩 flaggedMessagesCount backfill — ${mode}\n`);

  // (1) Walk every report and accumulate unique reporters per reportedUserId.
  //     Use a Map<reportedUserId, Set<reporterId>> so we naturally dedupe
  //     across both message and user report types.
  const reportsSnap = await db.collection("reports").get();
  console.log(`Found ${reportsSnap.size} report docs.\n`);

  const uniqueByReported = new Map();
  let skippedNoTarget = 0;
  let skippedNoReporter = 0;

  for (const doc of reportsSnap.docs) {
    const r = doc.data() || {};
    const reportedUserId = r.reportedUserId;
    const reporterId = r.reporterId;
    if (!reportedUserId) {
      skippedNoTarget += 1;
      continue;
    }
    if (!reporterId) {
      skippedNoReporter += 1;
      continue;
    }
    if (!uniqueByReported.has(reportedUserId)) {
      uniqueByReported.set(reportedUserId, new Set());
    }
    uniqueByReported.get(reportedUserId).add(reporterId);
  }

  if (skippedNoTarget > 0) {
    console.log(`  ⚠ skipped ${skippedNoTarget} report(s) with no reportedUserId`);
  }
  if (skippedNoReporter > 0) {
    console.log(`  ⚠ skipped ${skippedNoReporter} report(s) with no reporterId`);
  }
  console.log(`Computed counts for ${uniqueByReported.size} unique reported user(s).\n`);

  // (2) For each reported user, compare the computed count against the
  //     current trust_data value and write if different.
  let usersScanned = 0;
  let usersWritten = 0;
  let usersUnchanged = 0;
  let totalFlagsBefore = 0;
  let totalFlagsAfter = 0;

  for (const [userId, reporterSet] of uniqueByReported.entries()) {
    usersScanned += 1;
    const trueCount = reporterSet.size;
    totalFlagsAfter += trueCount;

    const tdRef = db.collection("trust_data").doc(userId);
    const tdSnap = await tdRef.get();
    const currentCount = tdSnap.exists
      ? Number(tdSnap.data().flaggedMessagesCount || 0)
      : 0;
    totalFlagsBefore += currentCount;

    if (currentCount === trueCount) {
      usersUnchanged += 1;
      continue;
    }

    usersWritten += 1;
    const delta = trueCount - currentCount;
    const arrow = delta > 0 ? `+${delta}` : `${delta}`;

    if (APPLY) {
      // .set({merge:true}) so we don't disturb other trust_data fields, and
      // we create the doc if it doesn't exist (rare but possible for users
      // who were reported before their trust_data was initialized).
      await tdRef.set(
        {
          flaggedMessagesCount: trueCount,
          lastUpdated: new Date().toISOString(),
        },
        { merge: true }
      );
      console.log(`  ✓ ${userId}: ${currentCount} → ${trueCount} (${arrow})`);
    } else {
      console.log(`  • ${userId}: would set ${currentCount} → ${trueCount} (${arrow})`);
    }
  }

  // (3) Summary.
  console.log("\n────────────────────────────────────────");
  console.log(`Users scanned             : ${usersScanned}`);
  console.log(`Users written             : ${usersWritten}`);
  console.log(`Users unchanged           : ${usersUnchanged}`);
  console.log(`Total flags stored before : ${totalFlagsBefore}`);
  console.log(`Total flags after backfill: ${totalFlagsAfter}`);
  console.log(
    `Net PoCT delta (estimated): ${
      -10 * (Math.floor(totalFlagsAfter / 10) - Math.floor(totalFlagsBefore / 10))
    } PoCT across all affected users`
  );
  console.log(APPLY ? "\n✅ Applied." : "\nℹ️  Dry run. Re-run with --apply to write.");
}

main().catch((e) => {
  console.error("\n❌ Backfill failed:", e);
  process.exit(1);
});
