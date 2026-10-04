/** Abuse-resistant, server-authoritative report intake. */
const { functions, admin, db } = require("./shared");
const {
  requireAuth,
  requireAppCheck,
  consumeRateLimit,
  stableHash,
} = require("./security");

function validId(value) {
  return typeof value === "string" && /^[A-Za-z0-9_-]{1,256}$/.test(value);
}

exports.submitReport = functions.https.onCall(async (data, context) => {
  requireAppCheck(context);
  const uid = requireAuth(context);
  await consumeRateLimit("report-submit", uid, 30, 24 * 60 * 60 * 1000);
  const type = data && data.type;
  const reportedUserId = data && data.reportedUserId;
  const reason = data && data.reason;
  if (!["user", "message", "marketplace_listing"].includes(type) ||
      !validId(reportedUserId) || reportedUserId === uid ||
      typeof reason !== "string" || reason.trim().length < 1 || reason.length > 2000) {
    throw new functions.https.HttpsError("invalid-argument", "Invalid report.");
  }

  let subjectId = reportedUserId;
  let listingRef = null;
  if (type === "message") {
    const chatId = data && data.chatId;
    const messageId = data && data.messageId;
    if (!validId(chatId) || !validId(messageId)) {
      throw new functions.https.HttpsError("invalid-argument", "Invalid message report.");
    }
    const [chat, message] = await Promise.all([
      db.collection("chats").doc(chatId).get(),
      db.collection("chats").doc(chatId).collection("messages").doc(messageId).get(),
    ]);
    const participants = chat.exists && Array.isArray(chat.data().participants) ?
      chat.data().participants : [];
    if (!message.exists || !participants.includes(uid) ||
        message.data().senderId !== reportedUserId) {
      throw new functions.https.HttpsError("permission-denied", "Message report denied.");
    }
    subjectId = `${chatId}:${messageId}`;
  } else if (type === "marketplace_listing") {
    const listingId = data && data.listingId;
    if (!validId(listingId)) {
      throw new functions.https.HttpsError("invalid-argument", "Invalid listing report.");
    }
    listingRef = db.collection("marketplace_listings").doc(listingId);
    const listing = await listingRef.get();
    const ownerId = listing.exists && (listing.data().sellerId || listing.data().ownerId);
    if (!listing.exists || ownerId !== reportedUserId || ownerId === uid) {
      throw new functions.https.HttpsError("failed-precondition", "Listing report denied.");
    }
    subjectId = listingId;
  } else {
    const user = await db.collection("users").doc(reportedUserId).get();
    if (!user.exists) {
      throw new functions.https.HttpsError("not-found", "Reported user not found.");
    }
  }

  const reportId = stableHash(`${uid}:${type}:${subjectId}`);
  const reportRef = db.collection("reports").doc(reportId);
  const duplicate = await db.runTransaction(async (transaction) => {
    const existing = await transaction.get(reportRef);
    if (existing.exists) return true;
    transaction.create(reportRef, {
      reporterId: uid,
      reportedUserId,
      type,
      reason: reason.trim(),
      status: "pending",
      subjectId,
      chatId: type === "message" ? data.chatId : null,
      messageId: type === "message" ? data.messageId : null,
      listingId: type === "marketplace_listing" ? data.listingId : null,
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
    });
    if (listingRef) {
      transaction.update(listingRef, {
        reportCount: admin.firestore.FieldValue.increment(1),
      });
    }
    return false;
  });
  return {success: true, duplicate};
});
