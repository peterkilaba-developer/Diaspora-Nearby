/**
 * Audit: detect Firebase Auth users whose phone numbers were stored with a
 * national trunk-prefix zero retained after the country dial code.
 *
 * Example contamination: a Tanzanian user typed `0712345678` into the old
 * onboarding screen, which concatenated `+255` + `0712345678` and persisted
 * `+2550712345678` in Firebase Auth. That string is also the salt used by
 * `computePhoneHash` in lib/wallet.js, so any smart wallet derived from it
 * lives at the "wrong" CREATE2 address.
 *
 * This script is READ-ONLY. It enumerates all Auth users, parses each phone
 * number with libphonenumber-js, compares the parsed E.164 to the stored
 * value, and reports any mismatch.
 *
 * Run:
 *   cd functions
 *   npm install --no-save libphonenumber-js
 *   GOOGLE_APPLICATION_CREDENTIALS=/path/to/key.json node scripts/audit-phone-trunk-prefix.js
 *
 * Output: prints a table to stdout and writes
 *   functions/scripts/.audit-phone-trunk-prefix.json
 * with the full list of affected users (uid, stored, expected, hasWallet).
 */
const fs = require("fs");
const path = require("path");
const admin = require("firebase-admin");

let parsePhoneNumberFromString;
try {
  ({ parsePhoneNumberFromString } = require("libphonenumber-js"));
} catch (e) {
  console.error(
    "Missing dependency: libphonenumber-js.\n" +
      "Run from the functions/ directory:\n" +
      "  npm install --no-save libphonenumber-js"
  );
  process.exit(1);
}

admin.initializeApp();
const db = admin.firestore();

async function* allAuthUsers() {
  let pageToken;
  do {
    const res = await admin.auth().listUsers(1000, pageToken);
    for (const u of res.users) yield u;
    pageToken = res.pageToken;
  } while (pageToken);
}

(async () => {
  const affected = [];
  let scanned = 0;
  let noPhone = 0;
  let unparseable = 0;

  for await (const user of allAuthUsers()) {
    scanned++;
    const stored = user.phoneNumber;
    if (!stored) {
      noPhone++;
      continue;
    }

    const parsed = parsePhoneNumberFromString(stored);
    if (!parsed) {
      unparseable++;
      console.warn(`[unparseable] uid=${user.uid} stored=${stored}`);
      continue;
    }
    const expected = parsed.number; // E.164 with libphonenumber's trunk-prefix handling

    if (expected !== stored) {
      // Check whether the user has a smart wallet already
      let hasWallet = false;
      let walletAddress = null;
      try {
        const doc = await db.collection("users").doc(user.uid).get();
        if (doc.exists) {
          walletAddress = doc.data().walletAddress || null;
          hasWallet = !!walletAddress;
        }
      } catch (_) {}

      affected.push({
        uid: user.uid,
        stored,
        expected,
        country: parsed.country || null,
        valid: parsed.isValid(),
        hasWallet,
        walletAddress,
      });
    }
  }

  console.log("\n=== Phone Trunk-Prefix Audit ===");
  console.log(`Total Auth users scanned : ${scanned}`);
  console.log(`Without phone number     : ${noPhone}`);
  console.log(`Unparseable phone        : ${unparseable}`);
  console.log(`Affected (mismatch)      : ${affected.length}`);

  if (affected.length) {
    console.log("\nuid                              | country | stored              -> expected            | wallet?");
    console.log("-".repeat(110));
    for (const a of affected) {
      console.log(
        `${a.uid.padEnd(32)} | ${(a.country || "??").padEnd(7)} | ${a.stored.padEnd(19)} -> ${a.expected.padEnd(19)} | ${a.hasWallet ? "YES " + a.walletAddress : "no"}`
      );
    }

    const outPath = path.join(__dirname, ".audit-phone-trunk-prefix.json");
    fs.writeFileSync(outPath, JSON.stringify(affected, null, 2));
    console.log(`\nFull report written to: ${outPath}`);
  }
})()
  .then(() => process.exit(0))
  .catch((e) => {
    console.error("Audit failed:", e);
    process.exit(1);
  });
