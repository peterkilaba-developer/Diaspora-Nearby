/**
 * Backfill: rebuild user_points.lifetimeEarnings as a proper nested map.
 *
 * Symptom this fixes:
 *   The PoA tab shows "0 earned" for every activity. Inspecting a doc in
 *   the Firestore console reveals top-level fields literally named
 *   `lifetimeEarnings.friend_connection`, `lifetimeEarnings.profile_completion`,
 *   etc. — NOT a nested `lifetimeEarnings` map. The app reads
 *   `userPoints.lifetimeEarnings['friend_connection']` (i.e. the nested
 *   map's value), which doesn't exist, so it falls back to 0.
 *
 *   Root cause: the production `awardPoints` Cloud Function wrote
 *   `batch.set(ref, {"lifetimeEarnings.<action>": increment(...)}, {merge:true})`.
 *   `set({merge:true})` does NOT interpret dotted keys as nested-field
 *   paths — it stores the dot as part of a literal top-level field name.
 *   `awardPoints` has now been patched to use the nested-map increment
 *   form (`lifetimeEarnings: { [action]: increment(...) }`), so future
 *   awards land correctly. This script repairs every existing user_points
 *   doc.
 *
 * Approach (per user_points/{userId}):
 *   1. Read all existing top-level fields whose name starts with
 *      `lifetimeEarnings.` — these are the junk fields.
 *   2. Read the existing nested `lifetimeEarnings` map (in case some
 *      values landed correctly via other code paths).
 *   3. Read `trust_data/{userId}` to compute a floor for connection
 *      milestones (family/friend/QR/verified/vouched).
 *   4. Merge: per action, take MAX(junk, nested, trustFloor). Also stamp
 *      `welcome_bonus = 1000` if missing.
 *   5. Write the consolidated nested map AND delete every junk top-level
 *      field via FieldPath (the only way to address a top-level field
 *      whose name contains a dot in the Admin SDK).
 *
 *   DOES NOT touch totalPoints / availablePoints — we don't retro-mint
 *   DSP. This is UI-only restoration of the PoA earned-counter values.
 *
 * Defaults to dry-run. Pass --apply to actually write.
 *
 * Run:
 *   cd functions
 *   $env:GOOGLE_APPLICATION_CREDENTIALS = "C:\path\to\service-account.json"
 *   node scripts/backfill-lifetime-earnings.js           # dry run
 *   node scripts/backfill-lifetime-earnings.js --apply   # write
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

const TRUST_TO_ACTION = {
  uniqueFamilyCount: "family_connection",
  uniqueFriendCount: "friend_connection",
  uniqueQrCount: "identity_qr_exchange",
  verifiedByCount: "verified_by_peer",
  uniqueVouchCount: "vouched_by_peer",
};
const PER_UNIT = 1000;
const JUNK_PREFIX = "lifetimeEarnings.";

async function main() {
  const mode = APPLY ? "APPLYING CHANGES" : "DRY RUN";
  console.log(`\n📊 lifetimeEarnings rebuild — ${mode}\n`);

  const upSnap = await db.collection("user_points").get();
  console.log(`Found ${upSnap.size} user_points docs.\n`);

  let usersScanned = 0;
  let usersUpdated = 0;
  let junkFieldsDeleted = 0;
  const perActionTotals = {};

  for (const upDoc of upSnap.docs) {
    usersScanned += 1;
    const userId = upDoc.id;
    const up = upDoc.data() || {};

    // (1) Collect junk top-level fields named `lifetimeEarnings.<action>`.
    const junkKeys = Object.keys(up).filter((k) => k.startsWith(JUNK_PREFIX));
    const junkValues = {};
    for (const k of junkKeys) {
      const action = k.slice(JUNK_PREFIX.length);
      junkValues[action] = Number(up[k] || 0);
    }

    // (2) Existing nested map (may be empty/missing).
    const nested = (up.lifetimeEarnings && typeof up.lifetimeEarnings === "object")
      ? up.lifetimeEarnings
      : {};

    // (3) Trust-data floor for connection milestones.
    const tdSnap = await db.collection("trust_data").doc(userId).get();
    const td = tdSnap.exists ? tdSnap.data() || {} : {};
    const trustFloor = {};
    for (const [field, action] of Object.entries(TRUST_TO_ACTION)) {
      const count = Number(td[field] || 0);
      if (count > 0) trustFloor[action] = count * PER_UNIT;
    }

    // (4) Build the consolidated map: max of (junk, nested, trustFloor).
    const allActions = new Set([
      ...Object.keys(junkValues),
      ...Object.keys(nested),
      ...Object.keys(trustFloor),
    ]);
    const consolidated = {};
    for (const action of allActions) {
      const v = Math.max(
        Number(junkValues[action] || 0),
        Number(nested[action] || 0),
        Number(trustFloor[action] || 0),
      );
      if (v > 0) consolidated[action] = v;
    }
    if (!consolidated.welcome_bonus) consolidated.welcome_bonus = 1000;

    // Decide if a write is needed. We need a write if:
    //   - there are junk fields to delete, OR
    //   - the existing nested map differs from `consolidated`.
    let needsWrite = junkKeys.length > 0;
    if (!needsWrite) {
      for (const [k, v] of Object.entries(consolidated)) {
        if (Number(nested[k] || 0) !== v) {
          needsWrite = true;
          break;
        }
      }
    }
    if (!needsWrite) continue;

    usersUpdated += 1;
    junkFieldsDeleted += junkKeys.length;
    for (const [k, v] of Object.entries(consolidated)) {
      const prev = Number(nested[k] || 0);
      if (v > prev) {
        perActionTotals[k] = (perActionTotals[k] || 0) + (v - prev);
      }
    }

    if (APPLY) {
      // Delete each junk top-level field using FieldPath (single-segment
      // path containing the literal dot — `update({"k.v": delete()})`
      // would target the nested path, not the literal-dot top-level key).
      const ref = db.collection("user_points").doc(userId);
      const writes = [];
      for (const k of junkKeys) {
        const fp = new admin.firestore.FieldPath(k);
        writes.push(ref.update(fp, admin.firestore.FieldValue.delete()));
      }
      await Promise.all(writes);

      // Write the consolidated nested map. `update()` with a nested map
      // under `lifetimeEarnings` replaces that field entirely — which is
      // what we want here since we've folded every historical source
      // into `consolidated`.
      await ref.update({
        lifetimeEarnings: consolidated,
        lastUpdated: admin.firestore.FieldValue.serverTimestamp(),
      });
      console.log(`  ✓ ${userId}: deleted ${junkKeys.length} junk fields, wrote ${Object.keys(consolidated).length}-key map`);
    } else {
      console.log(
        `  • ${userId}: would delete ${junkKeys.length} junk field(s), write lifetimeEarnings = ${JSON.stringify(consolidated)}`
      );
    }
  }

  console.log("\n────────────────────────────────────────");
  console.log(`Users scanned        : ${usersScanned}`);
  console.log(`Users updated        : ${usersUpdated}`);
  console.log(`Junk fields deleted  : ${junkFieldsDeleted}`);
  console.log(`Net DSP added by action (consolidated − previous nested value):`);
  for (const [k, v] of Object.entries(perActionTotals)) {
    console.log(`  ${k.padEnd(36)} +${v.toLocaleString()} DSP`);
  }
  console.log(APPLY ? "\n✅ Applied." : "\nℹ️  Dry run. Re-run with --apply to write.");
}

main().catch((e) => {
  console.error("\n❌ Backfill failed:", e);
  process.exit(1);
});
