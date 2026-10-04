/**
 * Shared authorization, attestation, validation, and abuse-control helpers.
 */
const crypto = require("crypto");
const { functions, admin, db } = require("./shared");

function requireAuth(context) {
  if (!context.auth || !context.auth.uid) {
    throw new functions.https.HttpsError(
        "unauthenticated",
        "Authentication is required.",
    );
  }
  return context.auth.uid;
}

function requireAppCheck(context) {
  if (process.env.FUNCTIONS_EMULATOR === "true") return;
  if (!context.app) {
    throw new functions.https.HttpsError(
        "failed-precondition",
        "This request must come from an attested app instance.",
    );
  }
}

function requireAdmin(context) {
  const uid = requireAuth(context);
  if (context.auth.token.admin !== true) {
    throw new functions.https.HttpsError(
        "permission-denied",
        "Administrator privileges are required.",
    );
  }
  return uid;
}

function requireSelf(context, requestedUid) {
  const uid = requireAuth(context);
  if (requestedUid && requestedUid !== uid) {
    throw new functions.https.HttpsError(
        "permission-denied",
        "The requested user must match the authenticated user.",
    );
  }
  return uid;
}

function stableHash(value) {
  return crypto.createHash("sha256").update(String(value)).digest("hex");
}

async function consumeRateLimit(scope, subject, limit, windowMs) {
  const key = stableHash(`${scope}:${subject}`);
  const ref = db.collection("security_rate_limits").doc(key);
  const now = Date.now();
  const allowed = await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(ref);
    const current = snapshot.exists ? snapshot.data() : null;
    const windowStartedAt = current && current.windowStartedAt ?
      current.windowStartedAt.toMillis() : 0;
    const withinWindow = now - windowStartedAt < windowMs;
    const count = withinWindow ? Number(current.count || 0) : 0;
    if (count >= limit) return false;
    const effectiveStart = withinWindow ? windowStartedAt : now;
    transaction.set(ref, {
      scope,
      count: count + 1,
      windowStartedAt: admin.firestore.Timestamp.fromMillis(effectiveStart),
      expireAt: admin.firestore.Timestamp.fromMillis(effectiveStart + windowMs * 2),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return true;
  });
  if (!allowed) {
    throw new functions.https.HttpsError(
        "resource-exhausted",
        "Too many requests. Please try again later.",
    );
  }
}

module.exports = {
  requireAuth,
  requireAppCheck,
  requireAdmin,
  requireSelf,
  stableHash,
  consumeRateLimit,
};
