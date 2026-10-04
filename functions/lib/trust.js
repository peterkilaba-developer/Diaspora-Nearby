/** Server-authoritative trust operations. */
const crypto = require("crypto");
const { functions, admin, db } = require("./shared");
const {
  requireAuth,
  requireAppCheck,
  stableHash,
  consumeRateLimit,
} = require("./security");

const QR_CHALLENGE_TTL_MS = 5 * 60 * 1000;

function displayName(profile) {
  const fullName = String(profile.fullName || "").trim();
  if (fullName) return fullName.slice(0, 200);
  return [profile.firstName, profile.lastName]
    .map((value) => String(value || "").trim())
    .filter(Boolean)
    .join(" ")
    .slice(0, 200) || "Diaspora Nearby member";
}

exports.createQrHandshake = functions.https.onCall(async (data, context) => {
  requireAppCheck(context);
  const uid = requireAuth(context);
  await consumeRateLimit("qr-challenge-create", uid, 30, 60 * 60 * 1000);
  const profile = await db.collection("users").doc(uid).get();
  if (!profile.exists) {
    throw new functions.https.HttpsError("failed-precondition", "Complete your profile first.");
  }

  const token = crypto.randomBytes(32).toString("base64url");
  const now = Date.now();
  await db.collection("qr_handshake_challenges").doc(stableHash(token)).set({
    creatorUid: uid,
    createdAt: admin.firestore.Timestamp.fromMillis(now),
    expiresAt: admin.firestore.Timestamp.fromMillis(now + QR_CHALLENGE_TTL_MS),
    used: false,
  });
  return { token, expiresInSeconds: QR_CHALLENGE_TTL_MS / 1000 };
});

exports.completeQrHandshake = functions.https.onCall(async (data, context) => {
  requireAppCheck(context);
  const scannerUid = requireAuth(context);
  await consumeRateLimit("qr-challenge-complete", scannerUid, 40, 60 * 60 * 1000);

  const token = data && data.token;
  const rawAddress = data && data.locationAddress;
  if (typeof token !== "string" || !/^[A-Za-z0-9_-]{40,64}$/.test(token)) {
    throw new functions.https.HttpsError("invalid-argument", "A valid QR challenge is required.");
  }
  if (rawAddress != null && typeof rawAddress !== "string") {
    throw new functions.https.HttpsError("invalid-argument", "Invalid location label.");
  }
  const locationAddress = String(rawAddress || "Location unavailable").trim().slice(0, 200);
  const challengeRef = db.collection("qr_handshake_challenges").doc(stableHash(token));
  let peerUid;

  await db.runTransaction(async (transaction) => {
    const challenge = await transaction.get(challengeRef);
    if (!challenge.exists) {
      throw new functions.https.HttpsError("not-found", "This QR code is invalid or expired.");
    }
    const challengeData = challenge.data();
    peerUid = challengeData.creatorUid;
    const expiresAt = challengeData.expiresAt && challengeData.expiresAt.toMillis();
    if (!peerUid || peerUid === scannerUid || challengeData.used === true ||
        !expiresAt || expiresAt < Date.now()) {
      throw new functions.https.HttpsError("failed-precondition", "This QR code cannot be used.");
    }

    const orderedUsers = [scannerUid, peerUid].sort();
    const exchangeRef = db.collection("qr_exchanges")
      .doc(stableHash(`${orderedUsers[0]}:${orderedUsers[1]}`));
    const scannerRef = db.collection("users").doc(scannerUid);
    const peerRef = db.collection("users").doc(peerUid);
    const exchange = await transaction.get(exchangeRef);
    const scanner = await transaction.get(scannerRef);
    const peer = await transaction.get(peerRef);
    if (exchange.exists) {
      throw new functions.https.HttpsError("already-exists", "You are already connected.");
    }
    if (!scanner.exists || !peer.exists) {
      throw new functions.https.HttpsError("failed-precondition", "Both profiles must exist.");
    }

    const now = admin.firestore.FieldValue.serverTimestamp();
    transaction.update(challengeRef, { used: true, usedBy: scannerUid, usedAt: now });
    transaction.create(exchangeRef, {
      fromUid: scannerUid,
      toUid: peerUid,
      users: orderedUsers,
      locationAddress,
      timestamp: now,
      verification: "single_use_server_challenge",
    });

    if (!scanner.data().firstQrConnection) {
      transaction.set(scannerRef, { firstQrConnection: {
        otherUid: peerUid,
        otherName: displayName(peer.data()),
        locationAddress,
        timestamp: new Date().toISOString(),
      } }, { merge: true });
    }
    if (!peer.data().firstQrConnection) {
      transaction.set(peerRef, { firstQrConnection: {
        otherUid: scannerUid,
        otherName: displayName(scanner.data()),
        locationAddress,
        timestamp: new Date().toISOString(),
      } }, { merge: true });
    }

    for (const [uid, otherUid] of [[scannerUid, peerUid], [peerUid, scannerUid]]) {
      const trustPatch = {
        identityQRExchange: true,
        uniqueQrCount: admin.firestore.FieldValue.increment(1),
        genesisQrIds: admin.firestore.FieldValue.arrayUnion(otherUid),
        lastUpdated: now,
      };
      transaction.set(db.collection("trust_data").doc(uid), trustPatch, { merge: true });
      transaction.set(db.collection("trust_scores").doc(uid), trustPatch, { merge: true });
      transaction.set(db.collection("user_points").doc(uid), {
        qrConnectionCount: admin.firestore.FieldValue.increment(1),
        lastUpdated: now,
      }, { merge: true });
    }
  });

  // Rewards remain paused until treasury expansion and anti-sybil policy can
  // be committed with the exchange as one economic invariant.
  return { success: true, peerUid, earnedPoints: 0 };
});

exports.verifyChatSolution = functions.https.onCall(async (data, context) => {
  requireAppCheck(context);
  const reporterId = requireAuth(context);
  await consumeRateLimit("solution-verification", reporterId, 50, 24 * 60 * 60 * 1000);
  const chatId = data && data.chatId;
  const messageId = data && data.messageId;
  if (typeof chatId !== "string" || !/^[A-Za-z0-9_-]{1,256}$/.test(chatId) ||
      typeof messageId !== "string" || messageId.length < 1 || messageId.length > 1500 ||
      messageId.includes("/")) {
    throw new functions.https.HttpsError("invalid-argument", "Invalid chat message.");
  }
  const chatRef = db.collection("chats").doc(chatId);
  const messageRef = chatRef.collection("messages").doc(messageId);
  const verificationRef = db.collection("verified_solutions")
      .doc(stableHash(`${reporterId}:${chatId}:${messageId}`));
  let senderId;
  let alreadyVerified = false;
  await db.runTransaction(async (transaction) => {
    const [chatSnapshot, messageSnapshot, verificationSnapshot] = await Promise.all([
      transaction.get(chatRef),
      transaction.get(messageRef),
      transaction.get(verificationRef),
    ]);
    if (!chatSnapshot.exists || !messageSnapshot.exists) {
      throw new functions.https.HttpsError("not-found", "Chat message not found.");
    }
    const participants = Array.isArray(chatSnapshot.data().participants) ?
      chatSnapshot.data().participants : [];
    if (!participants.includes(reporterId)) {
      throw new functions.https.HttpsError("permission-denied", "Chat membership is required.");
    }
    senderId = messageSnapshot.data().senderId;
    if (!senderId || senderId === reporterId || senderId === "system") {
      throw new functions.https.HttpsError(
          "failed-precondition", "You cannot verify this message.");
    }
    if (verificationSnapshot.exists) {
      alreadyVerified = true;
      return;
    }
    const now = admin.firestore.FieldValue.serverTimestamp();
    transaction.create(verificationRef, {
      reporterId,
      messageId,
      senderId,
      chatId,
      timestamp: now,
    });
    transaction.set(messageRef, {metadata: {
      isVerifiedSolution: true,
      verifiedSolutionCount: admin.firestore.FieldValue.increment(1),
    }}, {merge: true});
    transaction.set(db.collection("trust_data").doc(senderId), {
      verifiedSolutionsCount: admin.firestore.FieldValue.increment(1),
      lastUpdated: now,
    }, {merge: true});
  });
  return {success: true, alreadyVerified, senderId};
});
