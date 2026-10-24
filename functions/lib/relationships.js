/** Server-authoritative relationships, blocking, and direct-chat creation. */
const {functions, admin, db} = require("./shared");
const {
  requireAuth,
  requireAppCheck,
  stableHash,
  consumeRateLimit,
} = require("./security");
const {
  syncProfileMilestoneAndTrust,
  distributeUbuntuMatchingSupply,
} = require("./dsp");

const RELATIONSHIP_TYPES = new Map([
  "wife", "husband", "daughter", "son", "mother", "father", "sister",
  "brother", "aunt", "uncle", "nephew", "niece", "cousin", "friend",
  "community member", "business partner", "relative",
].map((value) => [value, value.replace(/\b\w/g, (letter) => letter.toUpperCase())]));

const RECIPROCAL_TYPES = new Map([
  ["father", new Set(["son", "daughter"])],
  ["mother", new Set(["son", "daughter"])],
  ["husband", new Set(["wife"])],
  ["wife", new Set(["husband"])],
  ["brother", new Set(["brother", "sister"])],
  ["sister", new Set(["brother", "sister"])],
  ["son", new Set(["father", "mother"])],
  ["daughter", new Set(["father", "mother"])],
  ["uncle", new Set(["nephew", "niece"])],
  ["aunt", new Set(["nephew", "niece"])],
  ["nephew", new Set(["uncle", "aunt"])],
  ["niece", new Set(["uncle", "aunt"])],
  ["cousin", new Set(["cousin"])],
  ["friend", new Set(["friend"])],
  ["business partner", new Set(["business partner"])],
  ["community member", new Set(["community member"])],
  ["relative", new Set(["relative"])],
]);

const FAMILY_TYPES = new Set([
  "wife", "husband", "daughter", "son", "mother", "father", "sister",
  "brother", "aunt", "uncle", "nephew", "niece", "cousin", "relative",
]);

function validId(value) {
  return typeof value === "string" && /^[A-Za-z0-9_-]{1,128}$/.test(value);
}

function relationshipType(value) {
  if (typeof value !== "string") return null;
  return RELATIONSHIP_TYPES.get(value.trim().toLowerCase()) || null;
}

function displayName(profile) {
  const explicit = String(profile.fullName || "").trim();
  const composed = [profile.firstName, profile.lastName]
      .map((part) => String(part || "").trim())
      .filter(Boolean)
      .join(" ");
  return (explicit || composed || "Diaspora Nearby member").slice(0, 200);
}

function profileFlag(profile) {
  return String(profile.countryFlag || profile.homeCountryFlag || "").slice(0, 16);
}

function profilePhoto(profile) {
  const value = profile.profilePhoto || profile.profileImage || "";
  return typeof value === "string" ? value.slice(0, 2048) : "";
}

function requestRef(fromUserId, toUserId) {
  return db.collection("relationship_requests")
      .doc(stableHash(`${fromUserId}:${toUserId}`));
}

function blockRef(blockerId, blockedId) {
  return db.collection("user_blocks").doc(blockerId)
      .collection("blocked").doc(blockedId);
}

function relationshipRef(userId, peerId) {
  return db.collection("users").doc(userId)
      .collection("relationships").doc(peerId);
}

function slotName(type) {
  const normalized = String(type || "").toLowerCase();
  if (["wife", "husband"].includes(normalized)) return "spouse";
  if (["father", "mother"].includes(normalized)) return normalized;
  return null;
}

function slotRef(userId, type) {
  const slot = slotName(type);
  return slot ? db.collection("users").doc(userId)
      .collection("relationship_slots").doc(slot) : null;
}

function directChatRef(firstUserId, secondUserId) {
  const users = [firstUserId, secondUserId].sort();
  return db.collection("chats")
      .doc(`direct_${stableHash(users.join(":"))}`);
}

function directPairRef(firstUserId, secondUserId) {
  const users = [firstUserId, secondUserId].sort();
  return db.collection("direct_chat_pairs").doc(stableHash(users.join(":")));
}

async function findDirectChatCandidate(firstUserId, secondUserId) {
  const pair = await directPairRef(firstUserId, secondUserId).get();
  if (pair.exists && validId(pair.data().chatId)) {
    return db.collection("chats").doc(pair.data().chatId);
  }
  const deterministic = directChatRef(firstUserId, secondUserId);
  if ((await deterministic.get()).exists) return deterministic;
  const legacy = await db.collection("chats")
      .where("participants", "array-contains", firstUserId)
      .where("type", "==", "direct")
      .limit(500)
      .get();
  const match = legacy.docs.find((snapshot) => {
    const participants = snapshot.data().participants;
    return Array.isArray(participants) && participants.length === 2 &&
      participants.includes(firstUserId) && participants.includes(secondUserId);
  });
  return match ? match.ref : deterministic;
}

function writeDirectChat(transaction, chatRef, users, createdBy, exists) {
  const now = admin.firestore.FieldValue.serverTimestamp();
  const chat = {
    id: chatRef.id,
    type: "direct",
    participants: users,
    memberCount: 2,
    updatedAt: now,
  };
  if (!exists) {
    chat.createdBy = createdBy;
    chat.adminId = createdBy;
    chat.createdAt = now;
  }
  transaction.set(chatRef, chat, {merge: true});
  for (const userId of users) {
    const userChatPatch = {
      chatId: chatRef.id,
      type: "direct",
      isDeleted: false,
    };
    if (!exists) {
      userChatPatch.updatedAt = Date.now();
      userChatPatch.addedAt = now;
    }
    transaction.set(
        db.collection("users").doc(userId)
            .collection("userChats").doc(chatRef.id),
        userChatPatch,
        {merge: true},
    );
  }
}

async function assertNoBlock(transaction, firstUserId, secondUserId) {
  const [firstBlock, secondBlock] = await Promise.all([
    transaction.get(blockRef(firstUserId, secondUserId)),
    transaction.get(blockRef(secondUserId, firstUserId)),
  ]);
  if (firstBlock.exists || secondBlock.exists) {
    throw new functions.https.HttpsError(
        "permission-denied", "This connection is unavailable.",
    );
  }
}

function computeRelationshipTrustPatch(relsDocs, extraEntry, removedPeerId, now) {
  const familyIds = new Set();
  const friendIds = new Set();
  const relationshipTypes = {};
  for (const doc of relsDocs) {
    const peerId = doc.id;
    if (peerId === removedPeerId) continue;
    if (extraEntry && peerId === extraEntry.peerId) continue;
    const data = doc.data() || {};
    if (data.status !== "active") continue;
    const rawType = String(data.type || "").trim();
    const t = rawType.toLowerCase();
    if (rawType) {
      relationshipTypes[peerId] = rawType;
    }
    if (FAMILY_TYPES.has(t)) {
      familyIds.add(peerId);
    } else {
      friendIds.add(peerId);
    }
  }
  if (extraEntry && extraEntry.peerId && extraEntry.type) {
    const rawType = String(extraEntry.type).trim();
    const t = rawType.toLowerCase();
    if (rawType) {
      relationshipTypes[extraEntry.peerId] = rawType;
    }
    if (FAMILY_TYPES.has(t)) {
      familyIds.add(extraEntry.peerId);
    } else {
      friendIds.add(extraEntry.peerId);
    }
  }
  for (const fid of familyIds) {
    friendIds.delete(fid);
  }
  const familyList = Array.from(familyIds);
  const friendList = Array.from(friendIds);
  return {
    uniqueFamilyCount: familyList.length,
    uniqueFriendCount: friendList.length,
    genesisFamilyIds: familyList.slice(0, 10),
    genesisFriendIds: friendList.slice(0, 10),
    relationshipTypes,
    lastUpdated: now,
  };
}

function writeRelationshipTrustProjection(transaction, uid, patch) {
  const payload = {uid, ...patch};
  transaction.set(db.collection("trust_data").doc(uid), payload, {merge: true});
  transaction.set(db.collection("trust_scores").doc(uid), payload, {merge: true});
}

exports.sendRelationshipRequest = functions.https.onCall(async (data, context) => {
  requireAppCheck(context);
  const fromUserId = requireAuth(context);
  await consumeRateLimit("relationship-request", fromUserId, 30, 24 * 60 * 60 * 1000);
  const toUserId = data && data.toUserId;
  const canonicalType = relationshipType(data && data.relationshipType);
  if (!validId(toUserId) || toUserId === fromUserId || !canonicalType) {
    throw new functions.https.HttpsError("invalid-argument", "Invalid relationship request.");
  }

  // Enforce Circle of Trust prerequisite: Bilateral dialogue in Direct Chat
  const candidateChatRef = await findDirectChatCandidate(fromUserId, toUserId);
  const chatDoc = await candidateChatRef.get();
  if (!chatDoc.exists) {
    throw new functions.https.HttpsError(
        "failed-precondition",
        "A mutual direct chat is required before requesting a relationship. Both users must send at least one message.",
    );
  }
  const [fromMsgs, toMsgs] = await Promise.all([
    candidateChatRef.collection("messages").where("senderId", "==", fromUserId).limit(20).get(),
    candidateChatRef.collection("messages").where("senderId", "==", toUserId).limit(20).get(),
  ]);
  const hasActiveMessage = (snap) => snap.docs.some((doc) => {
    const d = doc.data() || {};
    return d.deletedForEveryone !== true && d.isDeleted !== true;
  });
  if (!hasActiveMessage(fromMsgs) || !hasActiveMessage(toMsgs)) {
    throw new functions.https.HttpsError(
        "failed-precondition",
        "A mutual direct chat is required before requesting a relationship. Both users must send at least one message.",
    );
  }

  const fromRef = db.collection("users").doc(fromUserId);
  const toRef = db.collection("users").doc(toUserId);
  const pendingRef = requestRef(fromUserId, toUserId);
  let requestId;
  await db.runTransaction(async (transaction) => {
    const protectedRefs = [
      fromRef,
      toRef,
      pendingRef,
      relationshipRef(fromUserId, toUserId),
      relationshipRef(toUserId, fromUserId),
      blockRef(fromUserId, toUserId),
      blockRef(toUserId, fromUserId),
    ];
    if (FAMILY_TYPES.has(canonicalType.toLowerCase())) {
      protectedRefs.push(
          db.collection("field_verifications").doc(`${fromUserId}_${toUserId}`),
          db.collection("field_verifications").doc(`${toUserId}_${fromUserId}`),
          db.collection("vouches").doc(`${fromUserId}_${toUserId}`),
          db.collection("vouches").doc(`${toUserId}_${fromUserId}`),
      );
    }
    const snapshots = await Promise.all(protectedRefs.map((ref) => transaction.get(ref)));
    const [fromSnapshot, toSnapshot, pendingSnapshot, firstRelationship,
      secondRelationship, firstBlock, secondBlock, ...conflicts] = snapshots;
    if (!fromSnapshot.exists || !toSnapshot.exists) {
      throw new functions.https.HttpsError("not-found", "Both profiles must exist.");
    }
    if (firstBlock.exists || secondBlock.exists) {
      throw new functions.https.HttpsError("permission-denied", "This connection is unavailable.");
    }
    if (firstRelationship.exists || secondRelationship.exists) {
      throw new functions.https.HttpsError("already-exists", "This relationship already exists.");
    }
    if (pendingSnapshot.exists && pendingSnapshot.data().status === "pending") {
      throw new functions.https.HttpsError("already-exists", "A request is already pending.");
    }
    if (conflicts.some((snapshot) => snapshot.exists)) {
      throw new functions.https.HttpsError(
          "failed-precondition",
          "Family relationships cannot overlap an existing verification or vouch.",
      );
    }

    const from = fromSnapshot.data();
    const to = toSnapshot.data();
    requestId = pendingRef.id;
    transaction.set(pendingRef, {
      id: pendingRef.id,
      fromUserId,
      fromUserName: displayName(from),
      fromUserFlag: profileFlag(from),
      fromUserPhoto: profilePhoto(from),
      toUserId,
      toUserName: displayName(to),
      toUserPhoto: profilePhoto(to),
      relationshipType: canonicalType,
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      status: "pending",
    });
  });
  return {success: true, requestId};
});

exports.respondRelationshipRequest = functions.https.onCall(async (data, context) => {
  requireAppCheck(context);
  const responderId = requireAuth(context);
  await consumeRateLimit("relationship-response", responderId, 50, 24 * 60 * 60 * 1000);
  const requestId = data && data.requestId;
  const decision = data && data.decision;
  const reciprocal = relationshipType(data && data.reciprocalType);
  if (!validId(requestId) || !["accepted", "rejected"].includes(decision) ||
      (decision === "accepted" && !reciprocal)) {
    throw new functions.https.HttpsError("invalid-argument", "Invalid relationship response.");
  }

  const ref = db.collection("relationship_requests").doc(requestId);
  const initialRequest = await ref.get();
  if (!initialRequest.exists || initialRequest.data().toUserId !== responderId) {
    throw new functions.https.HttpsError("not-found", "Relationship request not found.");
  }
  const candidateChatRef = decision === "accepted" ?
    await findDirectChatCandidate(initialRequest.data().fromUserId, responderId) : null;
  let resultChatId = null;
  await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(ref);
    if (!snapshot.exists) {
      throw new functions.https.HttpsError("not-found", "Relationship request not found.");
    }
    const request = snapshot.data();
    if (request.toUserId !== responderId) {
      throw new functions.https.HttpsError("permission-denied", "Only the recipient can respond.");
    }
    if (request.status !== "pending") {
      if (request.status === decision) {
        resultChatId = request.chatId || null;
        return;
      }
      throw new functions.https.HttpsError("failed-precondition", "This request is already closed.");
    }
    if (decision === "rejected") {
      transaction.update(ref, {
        status: "rejected",
        respondedAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      return;
    }

    const fromUserId = request.fromUserId;
    const requestedType = relationshipType(request.relationshipType);
    const reciprocalSet = requestedType &&
      RECIPROCAL_TYPES.get(requestedType.toLowerCase());
    if (!validId(fromUserId) || !requestedType || !reciprocalSet ||
        !reciprocalSet.has(reciprocal.toLowerCase())) {
      throw new functions.https.HttpsError("invalid-argument", "Invalid reciprocal relationship.");
    }

    const fromProfileRef = db.collection("users").doc(fromUserId);
    const responderProfileRef = db.collection("users").doc(responderId);
    const fromRelationshipRef = relationshipRef(fromUserId, responderId);
    const responderRelationshipRef = relationshipRef(responderId, fromUserId);
    const reverseRequestRef = requestRef(responderId, fromUserId);
    const pairRef = directPairRef(fromUserId, responderId);
    const fromRelsSnapPromise = transaction.get(
        db.collection("users").doc(fromUserId).collection("relationships")
            .where("status", "==", "active").limit(200),
    );
    const responderRelsSnapPromise = transaction.get(
        db.collection("users").doc(responderId).collection("relationships")
            .where("status", "==", "active").limit(200),
    );
    const [fromProfile, responderProfile, oldFromRelationship,
      oldResponderRelationship, reverseRequest, pairSnapshot,
      fromRelsSnap, responderRelsSnap] = await Promise.all([
      transaction.get(fromProfileRef),
      transaction.get(responderProfileRef),
      transaction.get(fromRelationshipRef),
      transaction.get(responderRelationshipRef),
      transaction.get(reverseRequestRef),
      transaction.get(pairRef),
      fromRelsSnapPromise,
      responderRelsSnapPromise,
    ]);
    await assertNoBlock(transaction, fromUserId, responderId);
    if (!fromProfile.exists || !responderProfile.exists) {
      throw new functions.https.HttpsError("not-found", "Both profiles must exist.");
    }
    const chatRef = pairSnapshot.exists && validId(pairSnapshot.data().chatId) ?
      db.collection("chats").doc(pairSnapshot.data().chatId) : candidateChatRef;
    const chatSnapshot = await transaction.get(chatRef);

    const newSlots = [
      slotRef(fromUserId, requestedType),
      slotRef(responderId, reciprocal),
    ].filter(Boolean);
    const oldSlots = [
      oldFromRelationship.exists ?
        slotRef(fromUserId, oldFromRelationship.data().type) : null,
      oldResponderRelationship.exists ?
        slotRef(responderId, oldResponderRelationship.data().type) : null,
    ].filter(Boolean);
    const uniqueSlotRefs = [...new Map([...newSlots, ...oldSlots]
        .map((slot) => [slot.path, slot])).values()];
    const slotSnapshots = await Promise.all(
        uniqueSlotRefs.map((slot) => transaction.get(slot)),
    );
    for (let index = 0; index < newSlots.length; index += 1) {
      const slot = newSlots[index];
      const slotSnapshot = slotSnapshots[uniqueSlotRefs
          .findIndex((candidate) => candidate.path === slot.path)];
      const expectedPeer = index === 0 ? responderId : fromUserId;
      if (slotSnapshot.exists && slotSnapshot.data().relatedUserId !== expectedPeer) {
        throw new functions.https.HttpsError(
            "failed-precondition", "A unique family relationship is already assigned.",
        );
      }
    }

    const now = admin.firestore.FieldValue.serverTimestamp();
    for (const oldSlot of oldSlots) {
      if (!newSlots.some((slot) => slot.path === oldSlot.path)) {
        const oldSlotSnapshot = slotSnapshots[uniqueSlotRefs
            .findIndex((candidate) => candidate.path === oldSlot.path)];
        if (oldSlotSnapshot.exists &&
            [fromUserId, responderId].includes(oldSlotSnapshot.data().relatedUserId)) {
          transaction.delete(oldSlot);
        }
      }
    }
    for (let index = 0; index < newSlots.length; index += 1) {
      transaction.set(newSlots[index], {
        relatedUserId: index === 0 ? responderId : fromUserId,
        updatedAt: now,
      });
    }

    transaction.set(fromRelationshipRef, {
      id: responderId,
      type: requestedType,
      name: displayName(responderProfile.data()),
      flag: profileFlag(responderProfile.data()),
      createdAt: now,
      status: "active",
    });
    transaction.set(responderRelationshipRef, {
      id: fromUserId,
      type: reciprocal,
      name: displayName(fromProfile.data()),
      flag: profileFlag(fromProfile.data()),
      createdAt: now,
      status: "active",
    });
    writeRelationshipTrustProjection(
        transaction,
        fromUserId,
        computeRelationshipTrustPatch(
            fromRelsSnap.docs,
            {peerId: responderId, type: requestedType},
            null,
            now,
        ),
    );
    writeRelationshipTrustProjection(
        transaction,
        responderId,
        computeRelationshipTrustPatch(
            responderRelsSnap.docs,
            {peerId: fromUserId, type: reciprocal},
            null,
            now,
        ),
    );
    const users = [fromUserId, responderId].sort();
    writeDirectChat(transaction, chatRef, users, fromUserId, chatSnapshot.exists);
    transaction.set(pairRef, {chatId: chatRef.id, users, updatedAt: now});
    resultChatId = chatRef.id;
    transaction.update(ref, {
      status: "accepted",
      reciprocalType: reciprocal,
      chatId: chatRef.id,
      respondedAt: now,
      updatedAt: now,
    });
    if (reverseRequest.exists && reverseRequest.data().status === "pending") {
      transaction.update(reverseRequestRef, {
        status: "cancelled",
        updatedAt: now,
      });
    }
  });

  if (decision === "accepted") {
    const fromUserId = initialRequest.data().fromUserId;
    const requestedType = relationshipType(initialRequest.data().relationshipType);
    try {
      const rewardBatch = db.batch();
      const now = admin.firestore.FieldValue.serverTimestamp();
      const pairKey = [fromUserId, responderId].sort().join(":");
      const rewardDocRef = db.collection("relationship_rewards").doc(stableHash(pairKey));
      const rewardSnap = await rewardDocRef.get();
      if (!rewardSnap.exists) {
        rewardBatch.set(rewardDocRef, {
          users: [fromUserId, responderId].sort(),
          fromUserId,
          responderId,
          requestedType,
          reciprocalType: reciprocal,
          awardedAt: now,
        });

        for (const [uid, relType, peerId] of [
          [fromUserId, requestedType, responderId],
          [responderId, reciprocal, fromUserId],
        ]) {
          const isFamily = FAMILY_TYPES.has(String(relType || "").toLowerCase());
          const action = isFamily ? "family_connection" : "friend_connection";
          const points = 1000;
          const upRef = db.collection("user_points").doc(uid);
          rewardBatch.set(
              upRef,
              {
                userId: uid,
                totalPoints: admin.firestore.FieldValue.increment(points),
                availablePoints: admin.firestore.FieldValue.increment(points),
                ...(isFamily ? {familyConnectionCount: admin.firestore.FieldValue.increment(1)} : {}),
                lastUpdated: now,
                lifetimeEarnings: {
                  [action]: admin.firestore.FieldValue.increment(points),
                },
              },
              {merge: true},
          );
          rewardBatch.set(db.collection("points_transactions").doc(), {
            userId: uid,
            type: "earn",
            action,
            points,
            amount: points,
            timestamp: now,
            metadata: {peerId, relationshipType: relType},
          });
          await distributeUbuntuMatchingSupply(rewardBatch, uid, points, now, `${action}_match`);
        }
        await rewardBatch.commit();
      }
    } catch (rewardErr) {
      console.warn(`[respondRelationshipRequest] Connection reward warning: ${rewardErr.message}`);
    }

    try {
      await Promise.all([
        syncProfileMilestoneAndTrust(fromUserId),
        syncProfileMilestoneAndTrust(responderId),
      ]);
    } catch (syncErr) {
      console.warn(`[respondRelationshipRequest] syncProfileMilestoneAndTrust warning: ${syncErr.message}`);
    }
  }

  return {success: true, status: decision, chatId: resultChatId};
});

exports.cancelRelationshipRequest = functions.https.onCall(async (data, context) => {
  requireAppCheck(context);
  const userId = requireAuth(context);
  await consumeRateLimit("relationship-cancel", userId, 50, 24 * 60 * 60 * 1000);
  const requestId = data && data.requestId;
  if (!validId(requestId)) {
    throw new functions.https.HttpsError("invalid-argument", "Invalid request.");
  }
  const ref = db.collection("relationship_requests").doc(requestId);
  await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(ref);
    if (!snapshot.exists || snapshot.data().fromUserId !== userId) {
      throw new functions.https.HttpsError("not-found", "Pending request not found.");
    }
    if (snapshot.data().status !== "pending") {
      throw new functions.https.HttpsError("failed-precondition", "This request is already closed.");
    }
    transaction.update(ref, {
      status: "cancelled",
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  });
  return {success: true};
});

exports.ensureDirectChat = functions.https.onCall(async (data, context) => {
  requireAppCheck(context);
  const userId = requireAuth(context);
  await consumeRateLimit("direct-chat-create", userId, 100, 60 * 60 * 1000);
  const otherUserId = data && data.otherUserId;
  const create = !data || data.create !== false;
  if (!validId(otherUserId) || otherUserId === userId) {
    throw new functions.https.HttpsError("invalid-argument", "Invalid chat participant.");
  }
  const candidateChatRef = await findDirectChatCandidate(userId, otherUserId);
  const pairRef = directPairRef(userId, otherUserId);
  let resultChatId = null;
  let exists = false;
  await db.runTransaction(async (transaction) => {
    const [firstProfile, secondProfile, pairSnapshot] = await Promise.all([
      transaction.get(db.collection("users").doc(userId)),
      transaction.get(db.collection("users").doc(otherUserId)),
      transaction.get(pairRef),
    ]);
    await assertNoBlock(transaction, userId, otherUserId);
    if (!firstProfile.exists || !secondProfile.exists) {
      throw new functions.https.HttpsError("not-found", "Both profiles must exist.");
    }
    const chatRef = pairSnapshot.exists && validId(pairSnapshot.data().chatId) ?
      db.collection("chats").doc(pairSnapshot.data().chatId) : candidateChatRef;
    const chatSnapshot = await transaction.get(chatRef);
    exists = chatSnapshot.exists;
    if (chatSnapshot.exists || create) {
      const users = [userId, otherUserId].sort();
      writeDirectChat(transaction, chatRef, users, userId, chatSnapshot.exists);
      transaction.set(pairRef, {
        chatId: chatRef.id,
        users,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      exists = true;
    }
    resultChatId = exists ? chatRef.id : null;
  });
  return {success: true, exists, chatId: resultChatId};
});

exports.setUserBlocked = functions.https.onCall(async (data, context) => {
  requireAppCheck(context);
  const userId = requireAuth(context);
  await consumeRateLimit("user-block", userId, 100, 24 * 60 * 60 * 1000);
  const otherUserId = data && data.otherUserId;
  const blocked = data && data.blocked;
  if (!validId(otherUserId) || otherUserId === userId || typeof blocked !== "boolean") {
    throw new functions.https.HttpsError("invalid-argument", "Invalid block request.");
  }

  const ref = blockRef(userId, otherUserId);
  await db.runTransaction(async (transaction) => {
    const privateRef = db.collection("user_private").doc(userId);
    const trustRef = db.collection("trust_data").doc(otherUserId);
    const ownRelationship = relationshipRef(userId, otherUserId);
    const peerRelationship = relationshipRef(otherUserId, userId);
    const outgoingRequest = requestRef(userId, otherUserId);
    const incomingRequest = requestRef(otherUserId, userId);
    const ownRelsSnapPromise = blocked ? transaction.get(
        db.collection("users").doc(userId).collection("relationships")
            .where("status", "==", "active").limit(200),
    ) : Promise.resolve({docs: []});
    const peerRelsSnapPromise = blocked ? transaction.get(
        db.collection("users").doc(otherUserId).collection("relationships")
            .where("status", "==", "active").limit(200),
    ) : Promise.resolve({docs: []});
    const [targetProfile, blockSnapshot, trustSnapshot, ownRelationshipSnapshot,
      peerRelationshipSnapshot, outgoingSnapshot, incomingSnapshot,
      ownRelsSnap, peerRelsSnap] = await Promise.all([
      transaction.get(db.collection("users").doc(otherUserId)),
      transaction.get(ref),
      transaction.get(trustRef),
      transaction.get(ownRelationship),
      transaction.get(peerRelationship),
      transaction.get(outgoingRequest),
      transaction.get(incomingRequest),
      ownRelsSnapPromise,
      peerRelsSnapPromise,
    ]);
    if (!targetProfile.exists) {
      throw new functions.https.HttpsError("not-found", "User not found.");
    }
    const wasBlocked = blockSnapshot.exists;
    if (blocked === wasBlocked) return;

    const relationshipSlots = [
      ownRelationshipSnapshot.exists ?
        slotRef(userId, ownRelationshipSnapshot.data().type) : null,
      peerRelationshipSnapshot.exists ?
        slotRef(otherUserId, peerRelationshipSnapshot.data().type) : null,
    ].filter(Boolean);
    const slotSnapshots = blocked ? await Promise.all(
        relationshipSlots.map((slot) => transaction.get(slot)),
    ) : [];
    const now = admin.firestore.FieldValue.serverTimestamp();
    const currentCount = trustSnapshot.exists ?
      Math.max(0, Number(trustSnapshot.data().blockedByCount || 0)) : 0;
    if (blocked) {
      transaction.create(ref, {blockerId: userId, blockedId: otherUserId, createdAt: now});
      transaction.set(privateRef, {
        blockedUsers: admin.firestore.FieldValue.arrayUnion(otherUserId),
        updatedAt: now,
      }, {merge: true});
      transaction.set(trustRef, {
        uid: otherUserId,
        blockedByCount: currentCount + 1,
        lastUpdated: now,
      }, {merge: true});
      transaction.delete(ownRelationship);
      transaction.delete(peerRelationship);
      relationshipSlots.forEach((slot, index) => {
        const slotSnapshot = slotSnapshots[index];
        if (slotSnapshot.exists &&
            [userId, otherUserId].includes(slotSnapshot.data().relatedUserId)) {
          transaction.delete(slot);
        }
      });
      if (ownRelationshipSnapshot.exists || peerRelationshipSnapshot.exists) {
        writeRelationshipTrustProjection(
            transaction,
            userId,
            computeRelationshipTrustPatch(ownRelsSnap.docs, null, otherUserId, now),
        );
        writeRelationshipTrustProjection(
            transaction,
            otherUserId,
            computeRelationshipTrustPatch(peerRelsSnap.docs, null, userId, now),
        );
      }
      for (const [requestSnapshot, pendingRequestRef] of [
        [outgoingSnapshot, outgoingRequest], [incomingSnapshot, incomingRequest],
      ]) {
        if (requestSnapshot.exists && requestSnapshot.data().status === "pending") {
          transaction.update(pendingRequestRef, {status: "cancelled", updatedAt: now});
        }
      }
    } else {
      transaction.delete(ref);
      transaction.set(privateRef, {
        blockedUsers: admin.firestore.FieldValue.arrayRemove(otherUserId),
        updatedAt: now,
      }, {merge: true});
      transaction.set(trustRef, {
        uid: otherUserId,
        blockedByCount: Math.max(0, currentCount - 1),
        lastUpdated: now,
      }, {merge: true});
    }
  });
  try {
    await Promise.all([
      syncProfileMilestoneAndTrust(userId),
      syncProfileMilestoneAndTrust(otherUserId),
    ]);
  } catch (syncErr) {
    console.warn(`[setUserBlocked] syncProfileMilestoneAndTrust warning: ${syncErr.message}`);
  }
  return {success: true, blocked};
});

exports.removeRelationship = functions.https.onCall(async (data, context) => {
  requireAppCheck(context);
  const userId = requireAuth(context);
  await consumeRateLimit("relationship-remove", userId, 50, 24 * 60 * 60 * 1000);
  const otherUserId = data && data.otherUserId;
  if (!validId(otherUserId) || otherUserId === userId) {
    throw new functions.https.HttpsError("invalid-argument", "Invalid relationship.");
  }
  await db.runTransaction(async (transaction) => {
    const ownRef = relationshipRef(userId, otherUserId);
    const peerRef = relationshipRef(otherUserId, userId);
    const ownRelsSnapPromise = transaction.get(
        db.collection("users").doc(userId).collection("relationships")
            .where("status", "==", "active").limit(200),
    );
    const peerRelsSnapPromise = transaction.get(
        db.collection("users").doc(otherUserId).collection("relationships")
            .where("status", "==", "active").limit(200),
    );
    const [own, peer, ownRelsSnap, peerRelsSnap] = await Promise.all([
      transaction.get(ownRef),
      transaction.get(peerRef),
      ownRelsSnapPromise,
      peerRelsSnapPromise,
    ]);
    const slots = [
      own.exists ? slotRef(userId, own.data().type) : null,
      peer.exists ? slotRef(otherUserId, peer.data().type) : null,
    ].filter(Boolean);
    const slotSnapshots = await Promise.all(slots.map((slot) => transaction.get(slot)));
    const now = admin.firestore.FieldValue.serverTimestamp();
    transaction.delete(ownRef);
    transaction.delete(peerRef);
    slots.forEach((slot, index) => {
      if (slotSnapshots[index].exists &&
          [userId, otherUserId].includes(slotSnapshots[index].data().relatedUserId)) {
        transaction.delete(slot);
      }
    });
    writeRelationshipTrustProjection(
        transaction,
        userId,
        computeRelationshipTrustPatch(ownRelsSnap.docs, null, otherUserId, now),
    );
    writeRelationshipTrustProjection(
        transaction,
        otherUserId,
        computeRelationshipTrustPatch(peerRelsSnap.docs, null, userId, now),
    );
  });
  try {
    await Promise.all([
      syncProfileMilestoneAndTrust(userId),
      syncProfileMilestoneAndTrust(otherUserId),
    ]);
  } catch (syncErr) {
    console.warn(`[removeRelationship] syncProfileMilestoneAndTrust warning: ${syncErr.message}`);
  }
  return {success: true};
});

exports.markRelationshipDeceased = functions.https.onCall(async (data, context) => {
  requireAppCheck(context);
  const userId = requireAuth(context);
  await consumeRateLimit("relationship-bereavement", userId, 10, 24 * 60 * 60 * 1000);
  const otherUserId = data && data.otherUserId;
  const details = data && data.details;
  if (!validId(otherUserId) || otherUserId === userId || !details ||
      typeof details !== "object" || Array.isArray(details) ||
      JSON.stringify(details).length > 4000) {
    throw new functions.https.HttpsError("invalid-argument", "Invalid bereavement details.");
  }
  const ref = relationshipRef(userId, otherUserId);
  await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(ref);
    if (!snapshot.exists) {
      throw new functions.https.HttpsError("not-found", "Relationship not found.");
    }
    transaction.update(ref, {
      status: "deceased",
      bereavementDetails: details,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  });
  return {success: true};
});
