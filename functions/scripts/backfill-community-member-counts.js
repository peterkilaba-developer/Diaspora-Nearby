/**
 * Backfill: reconcile communities.memberCount / totalMembers with reality.
 *
 * Symptom this fixes:
 *   "Global Community — 2 members worldwide" while four members are visible
 *   in the same screen. The communities collection's counters were
 *   incremented inside the `joinCommunity` write path but never reconciled
 *   when users were created, deleted, or had their memberships rewritten
 *   outside that path.
 *
 * Approach:
 *   For each communities/{id}, count
 *     users.where('communityMemberships', array-contains, id).count()
 *   and write `memberCount` (and `totalMembers` when present) to match.
 *
 * Defaults to dry-run. Pass --apply to actually write.
 *
 * Run:
 *   cd functions
 *   GOOGLE_APPLICATION_CREDENTIALS=/path/to/key.json \
 *     node scripts/backfill-community-member-counts.js
 *   GOOGLE_APPLICATION_CREDENTIALS=/path/to/key.json \
 *     node scripts/backfill-community-member-counts.js --apply
 *
 * Idempotent — safe to re-run.
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
  console.log(`\n📊 Community member-count reconciliation — ${mode}\n`);

  const communitiesSnap = await db.collection("communities").get();
  console.log(`Found ${communitiesSnap.size} community docs.\n`);

  let scanned = 0;
  let drifted = 0;
  let inSync = 0;
  let written = 0;

  for (const doc of communitiesSnap.docs) {
    scanned += 1;
    const data = doc.data();
    const storedMemberCount = (data.memberCount ?? 0) | 0;
    const storedTotalMembers =
      data.totalMembers === undefined ? null : (data.totalMembers | 0);

    // Source of truth: users whose communityMemberships array contains the id.
    const usersSnap = await db
      .collection("users")
      .where("communityMemberships", "array-contains", doc.id)
      .count()
      .get();
    const actual = usersSnap.data().count;

    const memberMismatch = storedMemberCount !== actual;
    const totalMismatch =
      storedTotalMembers !== null && storedTotalMembers !== actual;

    if (!memberMismatch && !totalMismatch) {
      inSync += 1;
      continue;
    }

    drifted += 1;
    console.log(
      `  ${doc.id.padEnd(40)} ` +
        `memberCount ${storedMemberCount} → ${actual}` +
        (storedTotalMembers !== null
          ? `, totalMembers ${storedTotalMembers} → ${actual}`
          : ""),
    );

    if (APPLY) {
      const update = { memberCount: actual };
      if (storedTotalMembers !== null) update.totalMembers = actual;
      update.memberCountReconciledAt =
        admin.firestore.FieldValue.serverTimestamp();
      await doc.ref.update(update);
      written += 1;
    }
  }

  console.log(`\n📊 Summary`);
  console.log(`  Scanned:        ${scanned}`);
  console.log(`  In sync:        ${inSync}`);
  console.log(`  Drifted:        ${drifted}`);
  console.log(`  Written:        ${written}`);

  if (!APPLY && drifted > 0) {
    console.log(`\n👀 Dry run only. Re-run with --apply to write changes.\n`);
  } else if (APPLY) {
    console.log(`\n✅ Done.\n`);
  } else {
    console.log(`\n✅ Nothing to reconcile.\n`);
  }
}

main().catch((err) => {
  console.error("Backfill failed:", err);
  process.exit(1);
});
