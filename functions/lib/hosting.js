/** Mutual-consent hosting session lifecycle. */
const crypto = require("crypto");
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

function sessionParty(session, uid) {
  return session.travelerId === uid || session.hostId === uid;
}

function profileName(profile, fallback) {
  const explicit = profile.fullName || profile.displayName;
  const composed = `${profile.firstName || ""} ${profile.lastName || ""}`.trim();
  return String(explicit || composed || fallback).slice(0, 200);
}

function optionalString(value, maxLength) {
  if (value == null || value === "") return null;
  if (typeof value !== "string" || value.length > maxLength) {
    throw new functions.https.HttpsError("invalid-argument", "Invalid hosting request details.");
  }
  return value;
}

exports.createHostingRequest = functions.https.onCall(async (data, context) => {
  requireAppCheck(context);
  const uid = requireAuth(context);
  await consumeRateLimit("hosting-request-create", uid, 20, 60 * 60 * 1000);
  const requestId = data && data.requestId;
  const communityId = data && data.communityId;
  const arrivalMillis = data && data.arrivalMillis;
  const departureMillis = data && data.departureMillis;
  const guestCount = data && data.guestCount;
  const languages = data && data.languages;
  if (!validId(requestId) || !validId(communityId) ||
      !Number.isSafeInteger(arrivalMillis) || !Number.isSafeInteger(departureMillis) ||
      !Number.isSafeInteger(guestCount) || guestCount < 1 || guestCount > 10 ||
      (languages != null && (!Array.isArray(languages) || languages.length > 10 ||
        languages.some((language) => typeof language !== "string" || language.length > 100)))) {
    throw new functions.https.HttpsError("invalid-argument", "Invalid hosting request.");
  }
  const now = Date.now();
  if (arrivalMillis < now - 24 * 60 * 60 * 1000 || departureMillis <= arrivalMillis ||
      departureMillis - arrivalMillis > 90 * 24 * 60 * 60 * 1000) {
    throw new functions.https.HttpsError("invalid-argument", "Invalid hosting dates.");
  }
  const [profileSnapshot, communitySnapshot] = await Promise.all([
    db.collection("users").doc(uid).get(),
    db.collection("communities").doc(communityId).get(),
  ]);
  if (!profileSnapshot.exists || !communitySnapshot.exists) {
    throw new functions.https.HttpsError("not-found", "Profile or community not found.");
  }
  const profile = profileSnapshot.data();
  const community = communitySnapshot.data();
  const members = Array.isArray(community.members) ? community.members : [];
  const memberIds = Array.isArray(community.memberIds) ? community.memberIds : [];
  if (!members.includes(uid) && !memberIds.includes(uid)) {
    throw new functions.https.HttpsError(
        "permission-denied", "Join the community before requesting a host.");
  }
  const requestRef = db.collection("hosting_requests").doc(requestId);
  try {
    await requestRef.create({
      id: requestId,
      travelerId: uid,
      travelerName: profileName(profile, "Traveler"),
      travelerPhoto: profile.profilePhoto || profile.profileImage || null,
      travelerFlag: profile.homeCountryCode || null,
      communityId,
      communityName: String(community.name || community.displayName || "Community").slice(0, 200),
      arrivalDate: admin.firestore.Timestamp.fromMillis(arrivalMillis),
      departureDate: admin.firestore.Timestamp.fromMillis(departureMillis),
      purpose: optionalString(data.purpose, 500),
      notes: optionalString(data.notes, 5000),
      guestCount,
      preferredArea: optionalString(data.preferredArea, 500),
      languages: languages || [],
      interestedHostIds: [],
      matchedHostId: null,
      matchedHostName: null,
      status: "pending",
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: null,
      chatMessageId: null,
    });
  } catch (error) {
    if (error && (error.code === 6 || error.code === "already-exists")) {
      throw new functions.https.HttpsError("already-exists", "Hosting request already exists.");
    }
    throw error;
  }
  return {success: true, requestId};
});

exports.createHostingSession = functions.https.onCall(async (data, context) => {
  requireAppCheck(context);
  const uid = requireAuth(context);
  await consumeRateLimit("hosting-session-create", uid, 30, 60 * 60 * 1000);
  const requestId = data && data.requestId;
  const hostId = data && data.hostId;
  const chatId = data && data.chatId;
  if (!validId(requestId) || !validId(hostId) ||
      (chatId != null && !validId(chatId))) {
    throw new functions.https.HttpsError("invalid-argument", "Invalid hosting session request.");
  }

  const requestRef = db.collection("hosting_requests").doc(requestId);
  const sessionRef = db.collection("hosting_sessions").doc(requestId);
  await db.runTransaction(async (transaction) => {
    const requestSnapshot = await transaction.get(requestRef);
    const existingSession = await transaction.get(sessionRef);
    if (!requestSnapshot.exists) {
      throw new functions.https.HttpsError("not-found", "Hosting request not found.");
    }
    const request = requestSnapshot.data();
    if (request.travelerId !== uid || hostId === uid ||
        !Array.isArray(request.interestedHostIds) ||
        !request.interestedHostIds.includes(hostId) ||
        !["pending", "matched"].includes(request.status)) {
      throw new functions.https.HttpsError(
          "failed-precondition",
          "The selected host must have accepted this open request.",
      );
    }
    if (existingSession.exists) {
      const existing = existingSession.data();
      if (existing.travelerId === uid && existing.hostId === hostId) return;
      throw new functions.https.HttpsError("already-exists", "This request already has a session.");
    }
    if (chatId) {
      const chat = await transaction.get(db.collection("chats").doc(chatId));
      const participants = chat.exists && Array.isArray(chat.data().participants) ?
        chat.data().participants : [];
      if (!participants.includes(uid) || !participants.includes(hostId)) {
        throw new functions.https.HttpsError(
            "failed-precondition",
            "The arrangement chat must contain both participants.",
        );
      }
    }
    const [host, traveler] = await Promise.all([
      transaction.get(db.collection("users").doc(hostId)),
      transaction.get(db.collection("users").doc(uid)),
    ]);
    if (!host.exists || !traveler.exists) {
      throw new functions.https.HttpsError("not-found", "Participant profile not found.");
    }
    const hostData = host.data();
    const travelerData = traveler.data();
    const now = admin.firestore.FieldValue.serverTimestamp();
    transaction.create(sessionRef, {
      id: requestId,
      requestId,
      travelerId: uid,
      travelerName: profileName(travelerData, "Traveler"),
      travelerPhoto: travelerData.profilePhoto || travelerData.profileImage || null,
      hostId,
      hostName: profileName(hostData, "Host"),
      hostPhoto: hostData.profilePhoto || hostData.profileImage || null,
      communityId: request.communityId,
      communityName: String(request.communityName || "").slice(0, 200),
      plannedArrival: request.arrivalDate,
      plannedDeparture: request.departureDate,
      checkInTime: null,
      checkOutTime: null,
      actualDays: null,
      travelerSettled: false,
      hostSettled: false,
      status: "confirmed",
      createdAt: now,
      updatedAt: now,
      chatId: chatId || null,
    });
    transaction.update(requestRef, {
      matchedHostId: hostId,
      matchedHostName: profileName(hostData, "Host"),
      status: "matched",
      updatedAt: now,
    });
  });
  return {success: true, sessionId: requestId};
});

exports.createHostingCheckInChallenge = functions.https.onCall(async (data, context) => {
  requireAppCheck(context);
  const uid = requireAuth(context);
  await consumeRateLimit("hosting-checkin-challenge", uid, 30, 60 * 60 * 1000);
  const sessionId = data && data.sessionId;
  if (!validId(sessionId)) {
    throw new functions.https.HttpsError("invalid-argument", "Invalid sessionId.");
  }
  const session = await db.collection("hosting_sessions").doc(sessionId).get();
  if (!session.exists || session.data().hostId !== uid || session.data().status !== "confirmed") {
    throw new functions.https.HttpsError(
        "permission-denied",
        "Only the confirmed host can issue this check-in.",
    );
  }
  const token = crypto.randomBytes(32).toString("base64url");
  const now = Date.now();
  await db.collection("hosting_checkin_challenges").doc(stableHash(token)).set({
    sessionId,
    hostId: uid,
    used: false,
    createdAt: admin.firestore.Timestamp.fromMillis(now),
    expiresAt: admin.firestore.Timestamp.fromMillis(now + 5 * 60 * 1000),
  });
  return {token};
});

exports.completeHostingCheckIn = functions.https.onCall(async (data, context) => {
  requireAppCheck(context);
  const uid = requireAuth(context);
  await consumeRateLimit("hosting-checkin", uid, 30, 60 * 60 * 1000);
  const sessionId = data && data.sessionId;
  const token = data && data.token;
  if (!validId(sessionId) || typeof token !== "string" ||
      !/^[A-Za-z0-9_-]{40,64}$/.test(token)) {
    throw new functions.https.HttpsError("invalid-argument", "Invalid check-in challenge.");
  }
  const sessionRef = db.collection("hosting_sessions").doc(sessionId);
  const challengeRef = db.collection("hosting_checkin_challenges").doc(stableHash(token));
  await db.runTransaction(async (transaction) => {
    const [sessionSnapshot, challengeSnapshot] = await Promise.all([
      transaction.get(sessionRef),
      transaction.get(challengeRef),
    ]);
    if (!sessionSnapshot.exists || !challengeSnapshot.exists) {
      throw new functions.https.HttpsError("not-found", "Check-in challenge not found.");
    }
    const session = sessionSnapshot.data();
    const challenge = challengeSnapshot.data();
    const expiresAt = challenge.expiresAt && challenge.expiresAt.toMillis();
    if (session.travelerId !== uid || session.status !== "confirmed" ||
        challenge.sessionId !== sessionId || challenge.hostId !== session.hostId ||
        challenge.used === true || !expiresAt || expiresAt < Date.now()) {
      throw new functions.https.HttpsError("failed-precondition", "Check-in challenge is invalid.");
    }
    const now = admin.firestore.FieldValue.serverTimestamp();
    transaction.update(challengeRef, {used: true, usedBy: uid, usedAt: now});
    transaction.update(sessionRef, {status: "active", checkInTime: now, updatedAt: now});
    transaction.update(db.collection("hosting_requests").doc(session.requestId), {
      status: "active",
      updatedAt: now,
    });
  });
  return {success: true};
});

exports.updateHostingSessionState = functions.https.onCall(async (data, context) => {
  requireAppCheck(context);
  const uid = requireAuth(context);
  await consumeRateLimit("hosting-session-state", uid, 60, 60 * 60 * 1000);
  const sessionId = data && data.sessionId;
  const operation = data && data.operation;
  if (!validId(sessionId) || !["request_end", "confirm_end", "cancel"].includes(operation)) {
    throw new functions.https.HttpsError("invalid-argument", "Invalid session operation.");
  }
  const sessionRef = db.collection("hosting_sessions").doc(sessionId);
  await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(sessionRef);
    if (!snapshot.exists || !sessionParty(snapshot.data(), uid)) {
      throw new functions.https.HttpsError("permission-denied", "Session access denied.");
    }
    const session = snapshot.data();
    const requestRef = db.collection("hosting_requests").doc(session.requestId);
    const now = admin.firestore.Timestamp.now();
    if (operation === "request_end") {
      if (session.status !== "active") {
        throw new functions.https.HttpsError("failed-precondition", "The stay is not active.");
      }
      transaction.update(sessionRef, {
        status: "endRequested",
        endRequestedBy: uid,
        endRequestedAt: now,
        updatedAt: now,
      });
      return;
    }
    if (operation === "confirm_end") {
      if (session.status !== "endRequested" || session.endRequestedBy === uid) {
        throw new functions.https.HttpsError(
            "failed-precondition",
            "The other participant must confirm the end of the stay.",
        );
      }
      const checkIn = session.checkInTime && session.checkInTime.toDate();
      const actualDays = checkIn ? Math.max(1, Math.ceil((now.toDate() - checkIn) / 86400000)) : 1;
      transaction.update(sessionRef, {
        status: "settled",
        checkOutTime: now,
        actualDays,
        travelerSettled: true,
        hostSettled: true,
        updatedAt: now,
      });
      transaction.update(requestRef, {status: "completed", updatedAt: now});
      return;
    }
    if (session.status !== "confirmed") {
      throw new functions.https.HttpsError("failed-precondition", "Only an unstarted stay can be cancelled.");
    }
    transaction.update(sessionRef, {status: "cancelled", updatedAt: now});
    transaction.update(requestRef, {
      status: "pending",
      matchedHostId: null,
      matchedHostName: null,
      updatedAt: now,
    });
  });
  return {success: true};
});

exports.updateHostingRequestState = functions.https.onCall(async (data, context) => {
  requireAppCheck(context);
  const uid = requireAuth(context);
  await consumeRateLimit("hosting-request-state", uid, 60, 60 * 60 * 1000);
  const requestId = data && data.requestId;
  const operation = data && data.operation;
  if (!validId(requestId) || !["show_interest", "withdraw_interest", "cancel"].includes(operation)) {
    throw new functions.https.HttpsError("invalid-argument", "Invalid hosting request operation.");
  }

  const requestRef = db.collection("hosting_requests").doc(requestId);
  await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(requestRef);
    if (!snapshot.exists) {
      throw new functions.https.HttpsError(
          "not-found", "This hosting request no longer exists. It may have expired.",
      );
    }
    const request = snapshot.data();
    const now = admin.firestore.FieldValue.serverTimestamp();

    if (operation === "cancel") {
      if (request.travelerId !== uid) {
        throw new functions.https.HttpsError(
            "permission-denied", "Only the traveler can cancel this hosting request.",
        );
      }
      if (!["pending", "matched"].includes(request.status)) {
        throw new functions.https.HttpsError(
            "failed-precondition", "This request cannot be cancelled in its current state.",
        );
      }
      transaction.update(requestRef, {
        status: "cancelled",
        updatedAt: now,
      });
      return;
    }

    if (operation === "show_interest") {
      if (request.travelerId === uid) {
        throw new functions.https.HttpsError(
            "failed-precondition", "You cannot offer to host your own request.",
        );
      }
      if (!["pending", "matched"].includes(request.status)) {
        throw new functions.https.HttpsError(
            "failed-precondition", "This hosting request is no longer accepting hosts.",
        );
      }
      transaction.update(requestRef, {
        interestedHostIds: admin.firestore.FieldValue.arrayUnion(uid),
        updatedAt: now,
      });
      return;
    }

    if (operation === "withdraw_interest") {
      transaction.update(requestRef, {
        interestedHostIds: admin.firestore.FieldValue.arrayRemove(uid),
        updatedAt: now,
      });
    }
  });
  return {success: true};
});
