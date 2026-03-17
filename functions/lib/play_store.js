/**
 * Play Store Tester Management
 *
 * Records tester signups in Firestore and (if a Google Group is configured)
 * adds the email to a Google Group linked to the closed testing track via
 * the Google Play Developer API.
 *
 * Architecture:
 *   The Google Play Developer API's edits.testers endpoint ONLY supports
 *   Google Groups — not individual email addresses. To programmatically
 *   manage individual testers, we:
 *
 *   1. Record every signup in Firestore (tester_signups collection)
 *   2. Add the email to a Google Group via the Admin Directory API
 *   3. That Google Group is linked to the closed testing track in Play Console
 *
 *   If no Google Group is configured, the function falls back to Firestore-only
 *   recording. Users are still redirected to the internal testing opt-in link,
 *   which is self-service and does not require pre-adding emails.
 *
 * Requirements for Google Group integration:
 *   - A Google Workspace Google Group (e.g. testers@diasporanearby.com)
 *   - Service account with domain-wide delegation for the Admin Directory API
 *   - The Google Group must be linked to the testing track in Play Console
 *
 * Current mode: Firestore-only (Google Group not yet configured)
 */

const { functions, db } = require("./shared");

/**
 * addPlayStoreTester
 *
 * HTTPS callable function that:
 *   1. Receives an email address
 *   2. Records the signup in Firestore for tracking
 *   3. Returns success so the frontend can redirect to the opt-in link
 */
exports.addPlayStoreTester = functions.https.onCall(async (data, context) => {
  const email = (data.email || "").trim().toLowerCase();

  if (!email || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "A valid email address is required."
    );
  }

  try {
    // Check if this email has already signed up
    const existing = await db
      .collection("tester_signups")
      .where("email", "==", email)
      .where("status", "==", "added")
      .limit(1)
      .get();

    if (!existing.empty) {
      console.log(`[PlayStore] ${email} is already registered as a tester`);
      return {
        success: true,
        alreadyTester: true,
        message: "You're already a tester! Head to the Play Store to download.",
      };
    }

    // Record the signup in Firestore
    await recordTesterSignup(email, "added");
    console.log(`[PlayStore] Recorded tester signup for ${email}`);

    return {
      success: true,
      alreadyTester: false,
      message:
        "You've been registered! Accept the invite on Google Play to download.",
    };
  } catch (err) {
    console.error("[PlayStore] Failed to process tester signup:", err.message || err);

    // Attempt to record the signup even if something else failed
    try {
      await recordTesterSignup(email, "error", err.message);
    } catch (e) {
      console.error("[PlayStore] Failed to record error signup:", e);
    }

    return {
      success: false,
      fallback: true,
      message: "We've recorded your signup. You'll be added as a tester shortly.",
      error: err.message,
    };
  }
});

/**
 * Record tester signup in Firestore for tracking.
 */
async function recordTesterSignup(email, status, errorMsg = null) {
  try {
    const docData = {
      email,
      status, // "added", "already_tester", or "error"
      platform: "android",
      source: "landing_page",
      signup_type: "play_store_internal_test",
      timestamp: require("firebase-admin").firestore.FieldValue.serverTimestamp(),
    };
    if (errorMsg) docData.error = errorMsg;

    await db.collection("tester_signups").add(docData);
  } catch (e) {
    console.error("[PlayStore] Failed to record signup:", e);
  }
}
