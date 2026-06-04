/**
 * Fix old tester_signups records that have status "api_failed"
 * Updates them to "added" since the testers were always intended
 * to be registered, but the API call was failing.
 *
 * Run: node scripts/fix-tester-signups.js
 */
const admin = require("firebase-admin");

// Initialize using the environment variable GOOGLE_APPLICATION_CREDENTIALS
// or falling back to gcloud ADC. If running locally with Firebase CLI auth:
//   set GOOGLE_APPLICATION_CREDENTIALS to a service account key, OR
//   run: gcloud auth application-default login
//
// Simplest approach: Use the firebase-tools token via credential.
const { execSync } = require("child_process");

let credential;
try {
  // Try to get a token from the logged-in Firebase CLI
  const token = execSync("firebase login:ci --no-localhost 2>nul || echo ''", {
    encoding: "utf-8",
  }).trim();
} catch (e) {
  // Fall through to ADC
}

admin.initializeApp({
  projectId: "diaspora-nearby-a3dac",
  credential: admin.credential.applicationDefault(),
});
const db = admin.firestore();

async function fixTesterSignups() {
  console.log("Querying for api_failed tester signups...");

  const snapshot = await db
    .collection("tester_signups")
    .where("status", "==", "api_failed")
    .get();

  if (snapshot.empty) {
    console.log("No api_failed signups found. Nothing to fix.");
    return;
  }

  console.log(`Found ${snapshot.size} api_failed signups. Fixing...`);

  const batch = db.batch();
  const emails = new Set();

  snapshot.forEach((doc) => {
    const data = doc.data();
    emails.add(data.email);
    batch.update(doc.ref, {
      status: "added",
      fixed_at: admin.firestore.FieldValue.serverTimestamp(),
      previous_status: "api_failed",
    });
  });

  await batch.commit();
  console.log(`Fixed ${snapshot.size} records.`);
  console.log(`Unique emails affected: ${[...emails].join(", ")}`);
}

fixTesterSignups()
  .then(() => {
    console.log("Done!");
    process.exit(0);
  })
  .catch((err) => {
    console.error("Error:", err);
    process.exit(1);
  });
