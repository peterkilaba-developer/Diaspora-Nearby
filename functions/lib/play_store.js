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

const { functions, admin, db } = require("./shared");
const { consumeRateLimit, stableHash } = require("./security");

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

  if (!email || email.length > 254 || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "A valid email address is required."
    );
  }
  const rawRequest = context.rawRequest || {};
  const forwarded = String(rawRequest.headers && rawRequest.headers["x-forwarded-for"] || "")
      .split(",")[0].trim();
  const requestSubject = stableHash(
      forwarded || rawRequest.ip || rawRequest.socket && rawRequest.socket.remoteAddress || "unknown");
  await Promise.all([
    consumeRateLimit("play-tester-ip", requestSubject, 20, 24 * 60 * 60 * 1000),
    consumeRateLimit("play-tester-email", stableHash(email), 3, 24 * 60 * 60 * 1000),
  ]);

  try {
    const signupRef = db.collection("tester_signups").doc(stableHash(`tester:${email}`));
    const alreadyTester = await db.runTransaction(async (transaction) => {
      const existing = await transaction.get(signupRef);
      if (existing.exists) return true;
      const platform = ["android", "ios", "desktop"].includes(data.platform) ?
        data.platform : "android";
      const signupType = String(data.signupType || "early_access").slice(0, 64);
      transaction.create(signupRef, {
        email,
        status: "pending",
        platform,
        source: "landing_page",
        signup_type: signupType,
        referred_by: typeof data.referralCode === "string" ?
          data.referralCode.slice(0, 128) : null,
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
      });
      return false;
    });

    if (alreadyTester) {
      console.log("[PlayStore] Tester is already registered");
      return {
        success: true,
        alreadyTester: true,
        message: "You're already a tester! Head to the Play Store to download.",
      };
    }

    console.log("[PlayStore] Recorded tester signup");

    return {
      success: true,
      alreadyTester: false,
      message:
        "Your request was recorded. Follow the Play Store access steps to download.",
    };
  } catch (err) {
    console.error("[PlayStore] Failed to process tester signup:", err.message || err);

    throw new functions.https.HttpsError("unavailable", "Tester signup is temporarily unavailable.");
  }
});
