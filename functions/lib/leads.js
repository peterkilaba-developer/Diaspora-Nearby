/** Server-authoritative feedback and interest intake. */
const { functions, admin, db } = require("./shared");
const {
  requireAuth,
  requireAppCheck,
  consumeRateLimit,
  stableHash,
} = require("./security");

function normalizeEmail(value) {
  const email = String(value || "").trim().toLowerCase();
  if (email.length > 254 || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
    throw new functions.https.HttpsError("invalid-argument", "A valid email is required.");
  }
  return email;
}

function publicRequestSubject(context) {
  const raw = context.rawRequest || {};
  const forwarded = String(raw.headers && raw.headers["x-forwarded-for"] || "")
      .split(",")[0].trim();
  return stableHash(forwarded || raw.ip || raw.socket && raw.socket.remoteAddress || "unknown");
}

exports.submitLiquidityInterest = functions.https.onCall(async (data, context) => {
  const email = normalizeEmail(data && data.email);
  const epoch = data && data.epoch;
  const tge = data && data.tge;
  const type = data && data.type;
  if (!Number.isSafeInteger(epoch) || epoch < 1 || epoch > 1000 ||
      !Number.isSafeInteger(tge) || tge < 0 || tge > 10 ||
      !["epoch", "tge"].includes(type) ||
      (type === "epoch" && tge !== 0) || (type === "tge" && tge === 0)) {
    throw new functions.https.HttpsError("invalid-argument", "Invalid interest selection.");
  }
  await Promise.all([
    consumeRateLimit("liquidity-interest-ip", publicRequestSubject(context), 20, 24 * 60 * 60 * 1000),
    consumeRateLimit("liquidity-interest-email", stableHash(email), 3, 24 * 60 * 60 * 1000),
  ]);
  const interest = type === "epoch" ? `Epoch ${epoch} (Full)` : `Epoch ${epoch}, TDE ${tge}`;
  await db.collection("liquidity_interest").doc(stableHash(`liquidity:${email}`)).set({
    email,
    interest,
    epoch,
    tge,
    type,
    source: "landing_page",
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, {merge: true});
  return {success: true};
});

exports.submitFeedback = functions.https.onCall(async (data, context) => {
  requireAppCheck(context);
  const uid = requireAuth(context);
  await consumeRateLimit("feedback-submit", uid, 10, 24 * 60 * 60 * 1000);
  const content = String(data && data.content || "").trim();
  if (!content || content.length > 5000) {
    throw new functions.https.HttpsError("invalid-argument", "Feedback must be 1-5000 characters.");
  }
  await db.collection("feedback").add({
    userId: uid,
    content,
    type: "user_feedback",
    platform: "flutter_app",
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    status: "new",
  });
  return {success: true};
});

exports.submitAppRequest = functions.https.onCall(async (data, context) => {
  requireAppCheck(context);
  const uid = requireAuth(context);
  await consumeRateLimit("app-request", uid, 5, 24 * 60 * 60 * 1000);
  const email = normalizeEmail(data && data.email);
  const feature = String(data && data.feature || "").trim();
  const platform = String(data && data.platform || "").trim();
  if (!feature || feature.length > 100 || !["ios", "android", "desktop"].includes(platform)) {
    throw new functions.https.HttpsError("invalid-argument", "Invalid app request.");
  }
  await db.collection("app_requests").doc(stableHash(`${uid}:${feature}:${platform}`)).set({
    userId: uid,
    email,
    feature,
    platform,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, {merge: true});
  return {success: true};
});
