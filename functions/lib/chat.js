/**
 * Chat Notifications module.
 */
const crypto = require("crypto");
const { functions, admin, db, sendPushToUser } = require("./shared");
const {
  requireAuth,
  requireAppCheck,
  consumeRateLimit,
  stableHash,
} = require("./security");

const MAX_CHAT_PARTICIPANTS = 500;

function validUid(value) {
  return typeof value === "string" && value.length > 0 && value.length <= 128;
}

function validDocumentId(value) {
  return typeof value === "string" &&
    /^[A-Za-z0-9_-]{1,256}$/.test(value);
}

function optionalText(value, maximum, fieldName) {
  if (value == null || value === "") return null;
  if (typeof value !== "string" || value.trim().length > maximum) {
    throw new functions.https.HttpsError(
        "invalid-argument",
        `${fieldName} is invalid.`,
    );
  }
  return value.trim();
}

function validHttpsUrl(value) {
  return value == null || value === "" ||
    (typeof value === "string" && value.length <= 2048 &&
      value.startsWith("https://"));
}

function boundedDetails(value) {
  if (value == null) return {};
  if (typeof value !== "object" || Array.isArray(value)) {
    throw new functions.https.HttpsError("invalid-argument", "Invalid details.");
  }
  const serialized = JSON.stringify(value);
  if (serialized.length > 5000) {
    throw new functions.https.HttpsError("invalid-argument", "Details are too large.");
  }
  return JSON.parse(serialized);
}

function baseChat({
  chatId,
  type,
  name,
  uid,
  participants,
  admins,
  photoUrl,
  description,
}) {
  const now = admin.firestore.FieldValue.serverTimestamp();
  return {
    id: chatId,
    type,
    name,
    participants: [...new Set(participants.filter(validUid))],
    admins: [...new Set(admins.filter(validUid))],
    createdBy: uid,
    createdAt: now,
    updatedAt: now,
    memberCount: [...new Set(participants.filter(validUid))].length,
    photoUrl: photoUrl || null,
    description: description || null,
    lastMessage: {
      content: "Group created",
      timestamp: Date.now(),
      senderId: "system",
      senderName: "System",
      type: "system",
      status: "sent",
    },
  };
}

async function blockedEitherDirection(firstUid, secondUid) {
  const [first, second] = await Promise.all([
    db.collection("user_blocks").doc(firstUid).collection("blocked").doc(secondUid).get(),
    db.collection("user_blocks").doc(secondUid).collection("blocked").doc(firstUid).get(),
  ]);
  return first.exists || second.exists;
}

async function runBounded(values, worker, concurrency = 25) {
  for (let index = 0; index < values.length; index += concurrency) {
    await Promise.all(values.slice(index, index + concurrency).map(worker));
  }
}

async function deliverMessageIndex(chatId, messageId, message, participants) {
  const typeLabels = {
    image: "Photo",
    video: "Video",
    audio: "Voice message",
    audio_file: "Audio",
    document: "Document",
    location: "Location",
    dsp_transfer: "Sent $DIASPORA",
    "money-transfer": "Remittance",
  };
  let rawContent = String(message.content || typeLabels[message.type] || "Message");
  if (message.type === "system" &&
      message.senderName &&
      String(message.senderName).toLowerCase() !== "system" &&
      !rawContent.toLowerCase().startsWith(String(message.senderName).toLowerCase())) {
    rawContent = `${String(message.senderName).trim()} ${rawContent}`;
  }
  const preview = rawContent.slice(0, 2000);
  await runBounded(participants, async (recipientId) => {
    if (!validUid(recipientId)) return;
    const ref = db.collection("users").doc(recipientId)
        .collection("userChats").doc(chatId);
    await db.runTransaction(async (transaction) => {
      const snapshot = await transaction.get(ref);
      const existing = snapshot.exists ? snapshot.data() : {};
      if (existing.lastDeliveredMessageId === messageId) return;
      const isSender = recipientId === message.senderId;
      transaction.set(ref, {
        chatId,
        lastMessage: {
          id: messageId,
          content: preview,
          timestamp: message.timestamp || Date.now(),
          senderId: message.senderId,
          senderName: String(message.senderName || "").slice(0, 200),
          type: message.type || "text",
          status: message.status || "sent",
        },
        lastDeliveredMessageId: messageId,
        updatedAt: message.timestamp || Date.now(),
        isDeleted: false,
        ...(!isSender && {
          unreadCount: Number(existing.unreadCount || 0) + 1,
        }),
      }, { merge: true });
    });
  });
}

/** Synchronize trusted per-user chat indexes from the canonical chat doc. */
exports.onChatWritten = functions.firestore
  .document("chats/{chatId}")
  .onWrite(async (change, context) => {
    const chatId = context.params.chatId;
    const before = change.before.exists ? change.before.data() : {};
    const after = change.after.exists ? change.after.data() : null;
    const previous = new Set(Array.isArray(before.participants) ? before.participants : []);
    const current = new Set(after && Array.isArray(after.participants) ? after.participants : []);
    const added = [...current].filter((uid) => !previous.has(uid));
    const removed = [...previous].filter((uid) => !current.has(uid));
    const projectionChanged = !change.before.exists || !after ||
      ["name", "type", "subtype", "photoUrl"].some((field) =>
        JSON.stringify(before[field] ?? null) !== JSON.stringify(after[field] ?? null));
    const indexTargets = projectionChanged ? [...current] : added;
    const updatedAtMs = (after && typeof after.updatedAt === "number")
      ? after.updatedAt
      : (after && after.updatedAt && typeof after.updatedAt.toMillis === "function"
          ? after.updatedAt.toMillis()
          : Date.now());

    await runBounded(indexTargets, async (uid) => {
      if (!validUid(uid)) return;
      await db.collection("users").doc(uid).collection("userChats").doc(chatId).set({
        chatId,
        name: after.name || null,
        type: after.type || null,
        subtype: after.subtype || null,
        photoUrl: after.photoUrl || null,
        ...(after && after.lastMessage ? { lastMessage: after.lastMessage } : {}),
        updatedAt: updatedAtMs,
        isDeleted: false,
      }, { merge: true });
    });
    await runBounded(removed, async (uid) => {
      if (validUid(uid)) {
        await db.collection("users").doc(uid).collection("userChats").doc(chatId).delete();
      }
    });

    const discoverableRef = db.collection("discoverableChats").doc(chatId);
    const discoveryProjection = (value) => value ? {
      isPublic: value.isPublic === true,
      name: value.name || null,
      photoUrl: value.photoUrl || null,
      description: value.description || null,
      communityId: value.communityId || null,
      category: value.category || null,
      listingId: (value.metadata && value.metadata.listingId) || null,
      isChamber: Boolean(value.metadata && value.metadata.isChamber === true),
      isDdiDiscussion: Boolean(value.metadata && value.metadata.isDdiDiscussion === true),
      memberCount: Array.isArray(value.participants) ? value.participants.length : 0,
    } : null;
    const discoveryChanged = JSON.stringify(discoveryProjection(before)) !==
      JSON.stringify(discoveryProjection(after));
    if (after && after.isPublic === true && discoveryChanged) {
      await discoverableRef.set({
        id: chatId,
        name: String(after.name || "").slice(0, 200),
        photoUrl: after.photoUrl || null,
        description: String(after.description || "").slice(0, 2000),
        communityId: after.communityId || null,
        category: after.category || null,
        listingId: (after.metadata && after.metadata.listingId) || null,
        isChamber: Boolean(after.metadata && after.metadata.isChamber === true),
        isDdiDiscussion: Boolean(after.metadata && after.metadata.isDdiDiscussion === true),
        memberCount: current.size,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });
    } else if ((!after || after.isPublic !== true) && before.isPublic === true) {
      await discoverableRef.delete().catch(() => undefined);
    }
  });

/**
 * Creates canonical chat documents. Clients cannot write chat membership or
 * reserved routing metadata directly; each specialized mode is derived from
 * its authoritative parent document.
 */
exports.createChat = functions.https.onCall(async (data, context) => {
  requireAppCheck(context);
  const uid = requireAuth(context);
  await consumeRateLimit("chat-create", uid, 60, 60 * 60 * 1000);

  const mode = data && data.mode;
  if (!["group", "family", "listing", "event", "organization", "community",
    "bereavement"].includes(mode)) {
    throw new functions.https.HttpsError("invalid-argument", "Invalid chat mode.");
  }

  const requestedName = optionalText(data && data.name, 200, "Chat name");
  const description = optionalText(data && data.description, 2000, "Description");
  const category = optionalText(data && data.category, 100, "Category");
  const photoUrl = data && data.photoUrl;
  if (!validHttpsUrl(photoUrl)) {
    throw new functions.https.HttpsError("invalid-argument", "Invalid chat image URL.");
  }

  let chatId;
  let chatData;
  let addCallerToExisting = false;

  if (mode === "group") {
    if (!requestedName) {
      throw new functions.https.HttpsError("invalid-argument", "A chat name is required.");
    }
    chatId = `group_${db.collection("chats").doc().id}`;
    chatData = baseChat({
      chatId,
      type: "group",
      name: requestedName,
      uid,
      participants: [uid],
      admins: [uid],
      photoUrl,
      description,
    });
    const communityId = data && data.communityId;
    if (communityId != null) {
      if (!validDocumentId(communityId)) {
        throw new functions.https.HttpsError("invalid-argument", "Invalid community ID.");
      }
      const community = await db.collection("communities").doc(communityId).get();
      const communityData = community.exists ? community.data() : {};
      const members = Array.isArray(communityData.members) ? communityData.members : [];
      const admins = Array.isArray(communityData.admins) ? communityData.admins : [];
      if (!community.exists || (!members.includes(uid) && !admins.includes(uid))) {
        throw new functions.https.HttpsError(
            "permission-denied",
            "Community membership is required.",
        );
      }
      chatData.communityId = communityId;
    }
    chatData.isPublic = data && data.isPublic === true;
    if (category) chatData.category = category;
  } else if (mode === "family") {
    const otherUserId = data && data.otherUserId;
    const familyTier = data && data.familyTier;
    if (!validUid(otherUserId) || otherUserId === uid ||
        !["immediate", "extended"].includes(familyTier)) {
      throw new functions.https.HttpsError("invalid-argument", "Invalid family chat request.");
    }
    const relationship = await db.collection("users").doc(uid)
        .collection("relationships").doc(otherUserId).get();
    if (!relationship.exists || relationship.data().status !== "active") {
      throw new functions.https.HttpsError(
          "failed-precondition",
          "An accepted relationship is required.",
      );
    }
    if (await blockedEitherDirection(uid, otherUserId)) {
      throw new functions.https.HttpsError("permission-denied", "This chat is unavailable.");
    }
    chatId = `family_${stableHash(`${uid}:${familyTier}`).slice(0, 40)}`;
    chatData = baseChat({
      chatId,
      type: "group",
      name: familyTier === "immediate" ? "Immediate Family" : "Extended Family",
      uid,
      participants: [uid, otherUserId],
      admins: [uid],
      photoUrl: null,
      description: null,
    });
    chatData.metadata = { familyTier, familyOwnerId: uid };
    addCallerToExisting = true;
  } else if (mode === "listing") {
    const listingId = data && data.listingId;
    if (!validDocumentId(listingId)) {
      throw new functions.https.HttpsError("invalid-argument", "Invalid listing ID.");
    }
    const listing = await db.collection("marketplace_listings").doc(listingId).get();
    if (!listing.exists) {
      throw new functions.https.HttpsError("not-found", "Listing not found.");
    }
    const listingData = listing.data();
    const sellerId = listingData.sellerId;
    if (!validUid(sellerId)) {
      throw new functions.https.HttpsError("failed-precondition", "Listing owner is invalid.");
    }
    if (sellerId !== uid && await blockedEitherDirection(uid, sellerId)) {
      throw new functions.https.HttpsError("permission-denied", "This listing chat is unavailable.");
    }
    const images = Array.isArray(listingData.images) ? listingData.images : [];
    const canonicalPhoto = validHttpsUrl(images[0]) ? images[0] : null;
    chatId = `listing_${stableHash(listingId).slice(0, 40)}`;
    chatData = baseChat({
      chatId,
      type: "group",
      name: String(listingData.title || "Listing discussion").slice(0, 200),
      uid: sellerId,
      participants: sellerId === uid ? [uid] : [sellerId, uid],
      admins: [sellerId],
      photoUrl: canonicalPhoto,
      description: null,
    });
    chatData.isPublic = true;
    chatData.metadata = {
      isListingChat: true,
      listingId,
      listingType: String(listingData.listingType || "marketplace").slice(0, 100),
    };
    addCallerToExisting = true;
  } else if (mode === "event") {
    const eventId = data && data.eventId;
    if (!validDocumentId(eventId)) {
      throw new functions.https.HttpsError("invalid-argument", "Invalid event ID.");
    }
    const event = await db.collection("events").doc(eventId).get();
    const eventData = event.exists ? event.data() : {};
    if (!event.exists || (eventData.creatorId !== uid && eventData.createdBy !== uid)) {
      throw new functions.https.HttpsError("permission-denied", "Event owner access is required.");
    }
    chatId = `event_${eventId}`;
    chatData = baseChat({
      chatId,
      type: "event",
      name: String(eventData.title || "Event").slice(0, 200),
      uid,
      participants: [uid],
      admins: [uid],
      photoUrl: validHttpsUrl(eventData.imageUrl) ? eventData.imageUrl : null,
      description: null,
    });
    chatData.eventId = eventId;
  } else if (mode === "organization") {
    const organizationId = data && data.organizationId;
    if (!validDocumentId(organizationId)) {
      throw new functions.https.HttpsError("invalid-argument", "Invalid organization ID.");
    }
    const organization = await db.collection("organizations").doc(organizationId).get();
    const organizationData = organization.exists ? organization.data() : {};
    const admins = Array.isArray(organizationData.admins) ? organizationData.admins : [];
    if (!organization.exists || (organizationData.superAdminId !== uid && !admins.includes(uid))) {
      throw new functions.https.HttpsError(
          "permission-denied",
          "Organization administrator access is required.",
      );
    }
    chatId = `org_${organizationId}`;
    chatData = baseChat({
      chatId,
      type: "organization",
      name: String(organizationData.businessName || organizationData.name || "Organization")
          .slice(0, 200),
      uid,
      participants: [uid],
      admins: [uid],
      photoUrl: validHttpsUrl(organizationData.profileImage) ? organizationData.profileImage : null,
      description: null,
    });
    chatData.organizationId = organizationId;
  } else if (mode === "community") {
    const communityId = data && data.communityId;
    if (!validDocumentId(communityId)) {
      throw new functions.https.HttpsError("invalid-argument", "Invalid community ID.");
    }
    const community = await db.collection("communities").doc(communityId).get();
    const communityData = community.exists ? community.data() : {};
    const members = Array.isArray(communityData.members) ? communityData.members : [];
    const admins = Array.isArray(communityData.admins) ? communityData.admins : [];
    if (!community.exists || (!members.includes(uid) && !admins.includes(uid))) {
      throw new functions.https.HttpsError(
          "permission-denied",
          "Community membership is required.",
      );
    }
    chatId = typeof communityData.chatId === "string" && communityData.chatId.length <= 256 ?
      communityData.chatId : `chat_${communityId}`;
    chatData = baseChat({
      chatId,
      type: "community",
      name: String(communityData.name || "Community").slice(0, 200),
      uid,
      participants: [uid],
      admins: admins.includes(uid) ? [uid] : [],
      photoUrl: validHttpsUrl(communityData.profileImage) ? communityData.profileImage : null,
      description: null,
    });
    chatData.communityId = communityId;
    chatData.isPublic = communityData.isPrivate !== true;
  } else {
    const deceasedUserId = data && data.deceasedUserId;
    if (!validUid(deceasedUserId) || deceasedUserId === uid) {
      throw new functions.https.HttpsError("invalid-argument", "Invalid bereavement request.");
    }
    const relationship = await db.collection("users").doc(uid)
        .collection("relationships").doc(deceasedUserId).get();
    if (!relationship.exists || relationship.data().status !== "deceased") {
      throw new functions.https.HttpsError(
          "failed-precondition",
          "A recorded deceased relationship is required.",
      );
    }
    const activeRelationships = await db.collection("users").doc(uid)
        .collection("relationships").where("status", "==", "active").limit(99).get();
    const participants = [uid, ...activeRelationships.docs.map((document) => document.id)];
    chatId = `bereavement_${stableHash(`${uid}:${deceasedUserId}`).slice(0, 40)}`;
    chatData = baseChat({
      chatId,
      type: "group",
      name: `Bereaving ${String(relationship.data().name || "a loved one").slice(0, 150)}`,
      uid,
      participants,
      admins: [uid],
      photoUrl: null,
      description: null,
    });
    chatData.metadata = {
      isBereavement: true,
      deceasedId: deceasedUserId,
      deceasedName: String(relationship.data().name || "").slice(0, 200),
      announcerId: uid,
      details: boundedDetails(data && data.details),
    };
  }

  const chatRef = db.collection("chats").doc(chatId);
  let created = false;
  await db.runTransaction(async (transaction) => {
    const existing = await transaction.get(chatRef);
    if (!existing.exists) {
      transaction.create(chatRef, chatData);
      created = true;
    } else if (addCallerToExisting) {
      const existingData = existing.data();
      const participants = Array.isArray(existingData.participants) ?
        [...new Set(existingData.participants.filter(validUid))] : [];
      for (const participant of chatData.participants) {
        if (!participants.includes(participant)) participants.push(participant);
      }
      if (participants.length > MAX_CHAT_PARTICIPANTS) {
        throw new functions.https.HttpsError("resource-exhausted", "This chat is full.");
      }
      transaction.update(chatRef, {
        participants,
        memberCount: participants.length,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }
    if (mode === "event") {
      transaction.set(db.collection("events").doc(data.eventId), {
        chatId,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });
    } else if (mode === "organization") {
      transaction.set(db.collection("organizations").doc(data.organizationId), {
        chatId,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });
    } else if (mode === "community") {
      transaction.set(db.collection("communities").doc(data.communityId), {
        chatId,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });
    }
  });

  return { chatId, created };
});

exports.setOrganizationFollow = functions.https.onCall(async (data, context) => {
  requireAppCheck(context);
  const uid = requireAuth(context);
  await consumeRateLimit("organization-follow", uid, 120, 60 * 60 * 1000);
  const organizationId = data && data.organizationId;
  const following = data && data.following;
  if (!validDocumentId(organizationId) || typeof following !== "boolean") {
    throw new functions.https.HttpsError("invalid-argument", "Invalid follow request.");
  }

  const organizationRef = db.collection("organizations").doc(organizationId);
  await db.runTransaction(async (transaction) => {
    const organization = await transaction.get(organizationRef);
    if (!organization.exists) {
      throw new functions.https.HttpsError("not-found", "Organization not found.");
    }
    const organizationData = organization.data();
    if (organizationData.kind === "corridor_chamber") {
      throw new functions.https.HttpsError(
          "failed-precondition",
          "Use the chamber membership workflow.",
      );
    }
    const chatId = typeof organizationData.chatId === "string" ?
      organizationData.chatId : `org_${organizationId}`;
    const chatRef = db.collection("chats").doc(chatId);
    const chat = await transaction.get(chatRef);
    const followers = Array.isArray(organizationData.followers) ?
      [...new Set(organizationData.followers.filter(validUid))] : [];
    const followerIndex = followers.indexOf(uid);
    if (following && followerIndex < 0) followers.push(uid);
    if (!following && followerIndex >= 0) followers.splice(followerIndex, 1);

    const organizationAdmins = Array.isArray(organizationData.admins) ?
      [...new Set(organizationData.admins.filter(validUid))] : [];
    const ownerId = validUid(organizationData.superAdminId) ?
      organizationData.superAdminId : organizationAdmins[0];
    if (!validUid(ownerId)) {
      throw new functions.https.HttpsError(
          "failed-precondition",
          "Organization owner is invalid.",
      );
    }

    let participants = chat.exists && Array.isArray(chat.data().participants) ?
      [...new Set(chat.data().participants.filter(validUid))] : organizationAdmins;
    const participantIndex = participants.indexOf(uid);
    if (following && participantIndex < 0) participants.push(uid);
    const callerIsAdmin = organizationAdmins.includes(uid) || ownerId === uid;
    if (!following && participantIndex >= 0 && !callerIsAdmin) {
      participants.splice(participantIndex, 1);
    }
    if (participants.length > MAX_CHAT_PARTICIPANTS) {
      throw new functions.https.HttpsError("resource-exhausted", "This organization chat is full.");
    }

    transaction.update(organizationRef, {
      followers,
      chatId,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    if (chat.exists) {
      transaction.update(chatRef, {
        participants,
        memberCount: participants.length,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    } else {
      transaction.create(chatRef, {
        ...baseChat({
          chatId,
          type: "organization",
          name: String(organizationData.businessName || organizationData.name || "Organization")
              .slice(0, 200),
          uid: ownerId,
          participants,
          admins: organizationAdmins.length ? organizationAdmins : [ownerId],
          photoUrl: validHttpsUrl(organizationData.profileImage) ?
            organizationData.profileImage : null,
          description: null,
        }),
        organizationId,
      });
    }
  });
  return { success: true };
});

exports.manageOrganizationAdmin = functions.https.onCall(async (data, context) => {
  requireAppCheck(context);
  const uid = requireAuth(context);
  await consumeRateLimit("organization-admin", uid, 60, 24 * 60 * 60 * 1000);
  const organizationId = data && data.organizationId;
  const action = data && data.action;
  const requestedTarget = data && data.userId;
  if (!validDocumentId(organizationId) ||
      !["invite", "accept", "decline", "remove"].includes(action)) {
    throw new functions.https.HttpsError("invalid-argument", "Invalid admin operation.");
  }
  const targetUid = action === "accept" || action === "decline" ? uid : requestedTarget;
  if (!validUid(targetUid)) {
    throw new functions.https.HttpsError("invalid-argument", "Invalid administrator user.");
  }

  const organizationRef = db.collection("organizations").doc(organizationId);
  await db.runTransaction(async (transaction) => {
    const organization = await transaction.get(organizationRef);
    const targetUser = await transaction.get(db.collection("users").doc(targetUid));
    if (!organization.exists || !targetUser.exists) {
      throw new functions.https.HttpsError("not-found", "Organization or user not found.");
    }
    const organizationData = organization.data();
    if (organizationData.kind === "corridor_chamber") {
      throw new functions.https.HttpsError(
          "failed-precondition",
          "Chamber leadership uses the reviewed appointment workflow.",
      );
    }
    const admins = Array.isArray(organizationData.admins) ?
      [...new Set(organizationData.admins.filter(validUid))] : [];
    const pendingAdmins = Array.isArray(organizationData.pendingAdmins) ?
      [...new Set(organizationData.pendingAdmins.filter(validUid))] : [];
    const callerIsAdmin = organizationData.superAdminId === uid || admins.includes(uid);
    if ((action === "invite" || action === "remove") && !callerIsAdmin) {
      throw new functions.https.HttpsError("permission-denied", "Organization admin access required.");
    }
    if ((action === "accept" || action === "decline") && !pendingAdmins.includes(uid)) {
      throw new functions.https.HttpsError("failed-precondition", "No pending invitation exists.");
    }
    if (action === "remove" && organizationData.superAdminId === targetUid) {
      throw new functions.https.HttpsError("failed-precondition", "The organization owner cannot be removed.");
    }

    if (action === "invite" && !admins.includes(targetUid) && !pendingAdmins.includes(targetUid)) {
      pendingAdmins.push(targetUid);
    } else if (action === "accept") {
      pendingAdmins.splice(pendingAdmins.indexOf(uid), 1);
      if (!admins.includes(uid)) admins.push(uid);
    } else if (action === "decline") {
      pendingAdmins.splice(pendingAdmins.indexOf(uid), 1);
    } else if (action === "remove") {
      const adminIndex = admins.indexOf(targetUid);
      if (adminIndex >= 0) admins.splice(adminIndex, 1);
      const pendingIndex = pendingAdmins.indexOf(targetUid);
      if (pendingIndex >= 0) pendingAdmins.splice(pendingIndex, 1);
    }
    if (admins.length > 50 || pendingAdmins.length > 50) {
      throw new functions.https.HttpsError("resource-exhausted", "Administrator limit reached.");
    }

    const chatId = organizationData.chatId;
    const chatRef = typeof chatId === "string" ? db.collection("chats").doc(chatId) : null;
    const chat = chatRef ? await transaction.get(chatRef) : null;
    transaction.update(organizationRef, {
      admins,
      pendingAdmins,
      status: "active",
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    if (chatRef && chat && chat.exists) {
      const participants = Array.isArray(chat.data().participants) ?
        [...new Set(chat.data().participants.filter(validUid))] : [];
      if (action === "accept" && !participants.includes(uid)) participants.push(uid);
      if (participants.length > MAX_CHAT_PARTICIPANTS) {
        throw new functions.https.HttpsError("resource-exhausted", "Organization chat is full.");
      }
      transaction.update(chatRef, {
        admins,
        participants,
        memberCount: participants.length,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }
  });
  return { success: true };
});

exports.setBusinessChamberLink = functions.https.onCall(async (data, context) => {
  requireAppCheck(context);
  const uid = requireAuth(context);
  await consumeRateLimit("business-chamber-link", uid, 30, 24 * 60 * 60 * 1000);
  const chamberId = data && data.chamberId;
  const businessId = data && data.businessId;
  const linked = data && data.linked;
  if (!validDocumentId(chamberId) || !validDocumentId(businessId) ||
      typeof linked !== "boolean" || chamberId === businessId) {
    throw new functions.https.HttpsError("invalid-argument", "Invalid chamber link request.");
  }
  const chamberRef = db.collection("organizations").doc(chamberId);
  const businessRef = db.collection("organizations").doc(businessId);
  await db.runTransaction(async (transaction) => {
    const chamber = await transaction.get(chamberRef);
    const business = await transaction.get(businessRef);
    if (!chamber.exists || !business.exists || chamber.data().kind !== "corridor_chamber" ||
        business.data().kind === "corridor_chamber") {
      throw new functions.https.HttpsError("failed-precondition", "Invalid chamber or business.");
    }
    const businessAdmins = Array.isArray(business.data().admins) ? business.data().admins : [];
    if (business.data().superAdminId !== uid && !businessAdmins.includes(uid)) {
      throw new functions.https.HttpsError("permission-denied", "Business admin access required.");
    }
    const chamberMembers = Array.isArray(chamber.data().members) ? chamber.data().members : [];
    if (linked && !chamberMembers.includes(uid)) {
      throw new functions.https.HttpsError("failed-precondition", "Join the chamber first.");
    }
    const linkedBusinesses = Array.isArray(chamber.data().linkedBusinesses) ?
      [...new Set(chamber.data().linkedBusinesses.filter(validDocumentId))] : [];
    const linkedChambers = Array.isArray(business.data().linkedChamberIds) ?
      [...new Set(business.data().linkedChamberIds.filter(validDocumentId))] : [];
    const businessIndex = linkedBusinesses.indexOf(businessId);
    const chamberIndex = linkedChambers.indexOf(chamberId);
    if (linked && businessIndex < 0) linkedBusinesses.push(businessId);
    if (!linked && businessIndex >= 0) linkedBusinesses.splice(businessIndex, 1);
    if (linked && chamberIndex < 0) linkedChambers.push(chamberId);
    if (!linked && chamberIndex >= 0) linkedChambers.splice(chamberIndex, 1);
    if (linkedBusinesses.length > 500 || linkedChambers.length > 100) {
      throw new functions.https.HttpsError("resource-exhausted", "Organization link limit reached.");
    }
    transaction.update(chamberRef, {
      linkedBusinesses,
      memberBusinessCount: linkedBusinesses.length,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    transaction.update(businessRef, {
      linkedChamberIds: linkedChambers,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  });
  return { success: true };
});

exports.joinChat = functions.https.onCall(async (data, context) => {
  requireAppCheck(context);
  const uid = requireAuth(context);
  await consumeRateLimit("chat-join", uid, 120, 60 * 60 * 1000);
  const chatId = data && data.chatId;
  if (typeof chatId !== "string" || chatId.length < 1 || chatId.length > 256) {
    throw new functions.https.HttpsError("invalid-argument", "A valid chatId is required.");
  }
  const ref = db.collection("chats").doc(chatId);
  const invitationRef = db.collection("users").doc(uid)
      .collection("userChats").doc(chatId);
  await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(ref);
    if (!snapshot.exists) {
      throw new functions.https.HttpsError("not-found", "Chat not found.");
    }
    const chat = snapshot.data();
    const invitation = await transaction.get(invitationRef);
    const isInvited = invitation.exists && invitation.data().invitationOnly === true;
    let canJoin = chat.isPublic === true;
    if (!canJoin && chat.type === "community" && chat.communityId) {
      const community = await transaction.get(
          db.collection("communities").doc(chat.communityId),
      );
      canJoin = community.exists && community.data().isPrivate !== true;
    }
    canJoin = canJoin || isInvited;
    if (!canJoin || (chat.metadata &&
        (chat.metadata.isChamber === true || chat.metadata.isDdiDiscussion === true))) {
      throw new functions.https.HttpsError("permission-denied", "This chat cannot be joined directly.");
    }
    const participants = Array.isArray(chat.participants) ? [...new Set(chat.participants)] : [];
    if (participants.includes(uid)) {
      if (isInvited) transaction.set(invitationRef, { invitationOnly: false }, { merge: true });
      return;
    }
    if (participants.length >= MAX_CHAT_PARTICIPANTS) {
      throw new functions.https.HttpsError("resource-exhausted", "This chat is full.");
    }
    participants.push(uid);
    transaction.update(ref, {
      participants,
      memberCount: participants.length,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    if (isInvited) {
      transaction.set(invitationRef, {
        invitationOnly: false,
        acceptedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });
    }
  });
  return { success: true };
});

exports.joinCommunity = functions.https.onCall(async (data, context) => {
  requireAppCheck(context);
  const uid = requireAuth(context);
  await consumeRateLimit("community-join", uid, 120, 60 * 60 * 1000);
  const communityId = data && data.communityId;
  if (typeof communityId !== "string" || !/^[A-Za-z0-9_-]{1,256}$/.test(communityId)) {
    throw new functions.https.HttpsError("invalid-argument", "A valid communityId is required.");
  }
  const communityRef = db.collection("communities").doc(communityId);
  const userRef = db.collection("users").doc(uid);
  await db.runTransaction(async (transaction) => {
    const community = await transaction.get(communityRef);
    const user = await transaction.get(userRef);
    if (!community.exists || !user.exists) {
      throw new functions.https.HttpsError("not-found", "Community or profile not found.");
    }
    const communityData = community.data();
    const userData = user.data() || {};
    const canonicalMemberships = Array.isArray(userData.communityMemberships) ?
      userData.communityMemberships : [];
    if (!canonicalMemberships.includes(communityId)) {
      throw new functions.https.HttpsError(
          "permission-denied",
          "Use canonical community provisioning for your profile locations.",
      );
    }
    if (communityData.isPrivate === true) {
      throw new functions.https.HttpsError("permission-denied", "This community requires an invitation.");
    }
    const chatId = String(communityData.chatId || `chat_${communityId}`);
    const chatRef = db.collection("chats").doc(chatId);
    const chat = await transaction.get(chatRef);
    const members = Array.isArray(communityData.members) ?
      [...new Set(communityData.members.filter(validUid))] : [];
    const wasMember = members.includes(uid);
    if (!wasMember) members.push(uid);
    if (members.length > MAX_CHAT_PARTICIPANTS) {
      throw new functions.https.HttpsError("resource-exhausted", "This community is full.");
    }
    transaction.update(communityRef, {
      members,
      memberCount: members.length,
      totalMembers: members.length,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    transaction.set(userRef, {
      communityMemberships: admin.firestore.FieldValue.arrayUnion(communityId),
    }, { merge: true });
    if (chat.exists) {
      const chatData = chat.data();
      const participants = Array.isArray(chatData.participants) ?
        [...new Set(chatData.participants.filter(validUid))] : [];
      const wasParticipant = participants.includes(uid);
      if (!wasParticipant) participants.push(uid);
      if (participants.length > MAX_CHAT_PARTICIPANTS) {
        throw new functions.https.HttpsError("resource-exhausted", "This community is full.");
      }
      const nowMs = Date.now();
      const fullName = [userData.firstName, userData.lastName]
        .filter((s) => typeof s === "string" && s.trim().length > 0)
        .join(" ")
        .trim() || "Member";
      const msgRef = chatRef.collection("messages").doc();
      const lastMessageData = {
        id: msgRef.id,
        content: `${fullName} joined the community`,
        timestamp: nowMs,
        senderId: uid,
        senderName: fullName,
        type: "system",
        status: "read",
      };
      transaction.update(chatRef, {
        participants,
        memberCount: participants.length,
        updatedAt: nowMs,
        ...(!wasParticipant ? { lastMessage: lastMessageData } : {}),
      });
      if (!wasParticipant) {
        transaction.set(msgRef, {
          id: msgRef.id,
          chatId,
          senderId: uid,
          senderName: fullName,
          content: "joined the community",
          type: "system",
          timestamp: nowMs,
          status: "read",
        });
      }
    }
  });
  return { success: true };
});

exports.setEventAttendance = functions.https.onCall(async (data, context) => {
  requireAppCheck(context);
  const uid = requireAuth(context);
  await consumeRateLimit("event-attendance", uid, 120, 60 * 60 * 1000);
  const eventId = data && data.eventId;
  const attending = data && data.attending;
  if (typeof eventId !== "string" || eventId.length < 1 || eventId.length > 256 ||
      typeof attending !== "boolean") {
    throw new functions.https.HttpsError("invalid-argument", "Invalid attendance request.");
  }
  const eventRef = db.collection("events").doc(eventId);
  await db.runTransaction(async (transaction) => {
    const eventSnapshot = await transaction.get(eventRef);
    if (!eventSnapshot.exists) throw new functions.https.HttpsError("not-found", "Event not found.");
    const eventData = eventSnapshot.data();
    if (eventData.isPrivate === true && eventData.createdBy !== uid &&
        eventData.creatorId !== uid &&
        !(Array.isArray(eventData.invitedUserIds) && eventData.invitedUserIds.includes(uid))) {
      throw new functions.https.HttpsError("permission-denied", "This event requires an invitation.");
    }
    const paidAttendees = Array.isArray(eventData.paidAttendeeIds) ?
      eventData.paidAttendeeIds : [];
    if (attending && eventData.isPaid === true && eventData.createdBy !== uid &&
        eventData.creatorId !== uid && !paidAttendees.includes(uid)) {
      throw new functions.https.HttpsError(
          "failed-precondition",
          "A verified ticket payment is required before joining this event.",
      );
    }
    const chatId = eventData.chatId;
    const chatRef = chatId ? db.collection("chats").doc(chatId) : null;
    const chatSnapshot = chatRef ? await transaction.get(chatRef) : null;
    const historyRef = db.collection("event_attendance_history")
        .doc(stableHash(`${eventId}:${uid}`));
    const historySnapshot = await transaction.get(historyRef);
    const attendees = Array.isArray(eventData.attendees) ?
      [...new Set(eventData.attendees.filter(validUid))] : [];
    const wasAttending = attendees.includes(uid);
    const configuredMaximum = Number(eventData.maxAttendees || MAX_CHAT_PARTICIPANTS);
    const maximum = Math.min(
        MAX_CHAT_PARTICIPANTS,
        Number.isSafeInteger(configuredMaximum) && configuredMaximum > 0 ?
          configuredMaximum : MAX_CHAT_PARTICIPANTS,
    );
    if (attending && !wasAttending && attendees.length >= maximum) {
      throw new functions.https.HttpsError("resource-exhausted", "This event is full.");
    }
    if (attending && !wasAttending) attendees.push(uid);
    if (!attending && wasAttending) attendees.splice(attendees.indexOf(uid), 1);
    transaction.update(eventRef, {
      attendees,
      attendeeCount: attendees.length,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    if (chatRef && chatSnapshot && chatSnapshot.exists) {
      const chatData = chatSnapshot.data();
      const participants = Array.isArray(chatData.participants) ?
        [...new Set(chatData.participants.filter(validUid))] : [];
      const participantIndex = participants.indexOf(uid);
      if (attending && participantIndex < 0) participants.push(uid);
      if (!attending && participantIndex >= 0 && chatData.createdBy !== uid) {
        participants.splice(participantIndex, 1);
      }
      transaction.update(chatRef, {
        participants,
        memberCount: participants.length,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }
    if (attending) {
      transaction.set(historyRef, {
        eventId,
        userId: uid,
        active: true,
        lastJoinedAt: admin.firestore.FieldValue.serverTimestamp(),
        ...(!historySnapshot.exists && {
          firstJoinedAt: admin.firestore.FieldValue.serverTimestamp(),
        }),
      }, { merge: true });
    } else if (historySnapshot.exists) {
      transaction.update(historyRef, {
        active: false,
        leftAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }
    if (attending && !wasAttending && !historySnapshot.exists) {
      transaction.set(db.collection("trust_data").doc(uid), {
        joinedEventsCount: admin.firestore.FieldValue.increment(1),
        lastUpdated: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });
    }
  });
  return { success: true };
});

exports.setEventInterest = functions.https.onCall(async (data, context) => {
  requireAppCheck(context);
  const uid = requireAuth(context);
  const eventId = data && data.eventId;
  const interested = data && data.interested;
  if (typeof eventId !== "string" || typeof interested !== "boolean") {
    throw new functions.https.HttpsError("invalid-argument", "Invalid interest request.");
  }
  const ref = db.collection("events").doc(eventId);
  await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(ref);
    if (!snapshot.exists) throw new functions.https.HttpsError("not-found", "Event not found.");
    const values = Array.isArray(snapshot.data().interested) ?
      [...new Set(snapshot.data().interested.filter(validUid))] : [];
    const index = values.indexOf(uid);
    if (interested && index < 0) values.push(uid);
    if (!interested && index >= 0) values.splice(index, 1);
    transaction.update(ref, { interested: values, interestedCount: values.length });
  });
  return { success: true };
});

exports.createEventCheckInChallenge = functions.https.onCall(async (data, context) => {
  requireAppCheck(context);
  const uid = requireAuth(context);
  const eventId = data && data.eventId;
  if (typeof eventId !== "string" || eventId.length < 1 || eventId.length > 256) {
    throw new functions.https.HttpsError("invalid-argument", "A valid eventId is required.");
  }
  const event = await db.collection("events").doc(eventId).get();
  if (!event.exists) throw new functions.https.HttpsError("not-found", "Event not found.");
  const eventData = event.data();
  if (eventData.createdBy !== uid && eventData.creatorId !== uid) {
    throw new functions.https.HttpsError("permission-denied", "Only the event host can issue check-ins.");
  }
  const token = crypto.randomBytes(32).toString("base64url");
  const now = Date.now();
  await db.collection("event_checkin_challenges").doc(stableHash(token)).set({
    eventId,
    creatorUid: uid,
    createdAt: admin.firestore.Timestamp.fromMillis(now),
    expiresAt: admin.firestore.Timestamp.fromMillis(now + 10 * 60 * 1000),
    used: false,
  });
  return { token };
});

exports.completeEventCheckIn = functions.https.onCall(async (data, context) => {
  requireAppCheck(context);
  const uid = requireAuth(context);
  await consumeRateLimit("event-checkin", uid, 60, 60 * 60 * 1000);
  const eventId = data && data.eventId;
  const token = data && data.token;
  if (typeof eventId !== "string" || typeof token !== "string" ||
      !/^[A-Za-z0-9_-]{40,64}$/.test(token)) {
    throw new functions.https.HttpsError("invalid-argument", "Invalid check-in challenge.");
  }
  const challengeRef = db.collection("event_checkin_challenges").doc(stableHash(token));
  const eventRef = db.collection("events").doc(eventId);
  await db.runTransaction(async (transaction) => {
    const challenge = await transaction.get(challengeRef);
    const event = await transaction.get(eventRef);
    if (!challenge.exists || !event.exists) {
      throw new functions.https.HttpsError("not-found", "Check-in challenge not found.");
    }
    const challengeData = challenge.data();
    const expiresAt = challengeData.expiresAt && challengeData.expiresAt.toMillis();
    if (challengeData.eventId !== eventId || challengeData.used === true ||
        !expiresAt || expiresAt < Date.now()) {
      throw new functions.https.HttpsError("failed-precondition", "This check-in has expired.");
    }
    const eventData = event.data();
    const attendees = Array.isArray(eventData.attendees) ? eventData.attendees : [];
    if (!attendees.includes(uid) && eventData.createdBy !== uid && eventData.creatorId !== uid) {
      throw new functions.https.HttpsError("permission-denied", "RSVP before checking in.");
    }
    const confirmed = Array.isArray(eventData.confirmedAttendees) ?
      [...new Set(eventData.confirmedAttendees.filter(validUid))] : [];
    if (confirmed.includes(uid)) {
      throw new functions.https.HttpsError("already-exists", "Already checked in.");
    }
    confirmed.push(uid);
    const now = admin.firestore.FieldValue.serverTimestamp();
    transaction.update(challengeRef, { used: true, usedBy: uid, usedAt: now });
    transaction.update(eventRef, { confirmedAttendees: confirmed });
    transaction.create(db.collection("check_ins").doc(stableHash(`${eventId}:${uid}`)), {
      userId: uid,
      entityId: eventId,
      type: "event",
      verification: "host_single_use_challenge",
      timestamp: now,
    });
    transaction.set(db.collection("trust_data").doc(uid), {
      verifiedCheckInCount: admin.firestore.FieldValue.increment(1),
      lastUpdated: now,
    }, { merge: true });
  });
  return { success: true };
});

exports.onEventDeleted = functions.firestore
  .document("events/{eventId}")
  .onDelete(async (snapshot) => {
    const data = snapshot.data() || {};
    const tasks = [];
    if (data.chatId) {
      tasks.push(db.collection("chats").doc(data.chatId).delete().catch(() => undefined));
    }
    tasks.push(admin.storage().bucket().deleteFiles({
      prefix: `event_images/${snapshot.id}`,
    }).catch(() => undefined));
    await Promise.all(tasks);
    while (true) {
      const histories = await db.collection("event_attendance_history")
          .where("eventId", "==", snapshot.id).limit(400).get();
      if (histories.empty) break;
      const writer = db.bulkWriter();
      for (const history of histories.docs) writer.delete(history.ref);
      await writer.close();
    }
  });

exports.manageChatMembers = functions.https.onCall(async (data, context) => {
  requireAppCheck(context);
  const callerUid = requireAuth(context);
  await consumeRateLimit("chat-membership", callerUid, 120, 60 * 60 * 1000);
  const chatId = data && data.chatId;
  const addUserId = data && data.addUserId;
  const removeUserId = data && data.removeUserId;
  const promoteUserId = data && data.promoteUserId;
  const inviteUserId = data && data.inviteUserId;
  if (typeof chatId !== "string" ||
      [addUserId, removeUserId, promoteUserId, inviteUserId]
        .filter(Boolean).length !== 1) {
    throw new functions.https.HttpsError("invalid-argument", "Specify one membership operation.");
  }
  const targetUid = addUserId || removeUserId || promoteUserId || inviteUserId;
  if (!validUid(targetUid)) {
    throw new functions.https.HttpsError("invalid-argument", "A valid target user is required.");
  }
  if (addUserId) {
    throw new functions.https.HttpsError(
        "failed-precondition",
        "Members must accept an invitation or join a public chat themselves.",
    );
  }
  const ref = db.collection("chats").doc(chatId);
  await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(ref);
    if (!snapshot.exists) throw new functions.https.HttpsError("not-found", "Chat not found.");
    const chat = snapshot.data();
    const admins = Array.isArray(chat.admins) ? [...new Set(chat.admins)] : [];
    if (chat.createdBy !== callerUid && !admins.includes(callerUid)) {
      throw new functions.https.HttpsError("permission-denied", "Chat admin access is required.");
    }
    const participants = Array.isArray(chat.participants) ? [...new Set(chat.participants)] : [];
    if (removeUserId) {
      if (targetUid === chat.createdBy) {
        throw new functions.https.HttpsError("failed-precondition", "The chat creator cannot be removed.");
      }
      const index = participants.indexOf(targetUid);
      if (index >= 0) participants.splice(index, 1);
    }
    if (promoteUserId && !participants.includes(targetUid)) {
      throw new functions.https.HttpsError("failed-precondition", "An admin must be a participant.");
    }
    if (inviteUserId) {
      const targetUser = await transaction.get(db.collection("users").doc(targetUid));
      const blockedByCaller = await transaction.get(
          db.collection("user_blocks").doc(callerUid).collection("blocked").doc(targetUid),
      );
      const blockedByTarget = await transaction.get(
          db.collection("user_blocks").doc(targetUid).collection("blocked").doc(callerUid),
      );
      if (!targetUser.exists) {
        throw new functions.https.HttpsError("not-found", "Invitation recipient not found.");
      }
      if (blockedByCaller.exists || blockedByTarget.exists) {
        throw new functions.https.HttpsError("permission-denied", "This invitation is unavailable.");
      }
      if (participants.includes(targetUid)) return;
      const invitationRef = db.collection("users").doc(targetUid)
          .collection("userChats").doc(chatId);
      transaction.set(invitationRef, {
        chatId,
        invitationOnly: true,
        lastMessage: {
          content: `${String(chat.name || "Group").slice(0, 150)} invitation`,
          timestamp: Date.now(),
          senderId: callerUid,
          type: "group_invitation",
          status: "sent",
        },
        updatedAt: Date.now(),
        unreadCount: admin.firestore.FieldValue.increment(1),
      }, { merge: true });
      return;
    }
    transaction.update(ref, {
      participants,
      admins: promoteUserId ? [...new Set([...admins, targetUid])] :
        admins.filter((uid) => !removeUserId || uid !== targetUid),
      memberCount: participants.length,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  });
  return { success: true };
});

exports.updateChatMetadata = functions.https.onCall(async (data, context) => {
  requireAppCheck(context);
  const callerUid = requireAuth(context);
  await consumeRateLimit("chat-metadata", callerUid, 60, 60 * 60 * 1000);
  const chatId = data && data.chatId;
  if (typeof chatId !== "string" || chatId.length < 1 || chatId.length > 256) {
    throw new functions.https.HttpsError("invalid-argument", "A valid chatId is required.");
  }
  const updates = {};
  if (data.name != null) {
    if (typeof data.name !== "string" || data.name.trim().length < 1 || data.name.length > 200) {
      throw new functions.https.HttpsError("invalid-argument", "Invalid group name.");
    }
    updates.name = data.name.trim();
  }
  if (data.description != null) {
    if (typeof data.description !== "string" || data.description.length > 2000) {
      throw new functions.https.HttpsError("invalid-argument", "Invalid description.");
    }
    updates.description = data.description.trim();
  }
  if (data.photoUrl != null) {
    if (typeof data.photoUrl !== "string" || data.photoUrl.length > 2048 ||
        (data.photoUrl && !data.photoUrl.startsWith("https://"))) {
      throw new functions.https.HttpsError("invalid-argument", "Invalid group image URL.");
    }
    updates.photoUrl = data.photoUrl;
  }
  if (!Object.keys(updates).length) {
    throw new functions.https.HttpsError("invalid-argument", "No metadata changes were supplied.");
  }
  const ref = db.collection("chats").doc(chatId);
  await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(ref);
    if (!snapshot.exists) throw new functions.https.HttpsError("not-found", "Chat not found.");
    const chatData = snapshot.data();
    const admins = Array.isArray(chatData.admins) ? chatData.admins : [];
    if (chatData.createdBy !== callerUid && !admins.includes(callerUid)) {
      throw new functions.https.HttpsError("permission-denied", "Chat admin access is required.");
    }
    transaction.update(ref, {
      ...updates,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  });
  return { success: true };
});

exports.reactToMessage = functions.https.onCall(async (data, context) => {
  requireAppCheck(context);
  const callerUid = requireAuth(context);
  await consumeRateLimit("chat-reaction", callerUid, 240, 60 * 60 * 1000);
  const chatId = data && data.chatId;
  const messageId = data && data.messageId;
  const emoji = data && data.emoji;
  const remove = data && data.remove === true;
  if (typeof chatId !== "string" || typeof messageId !== "string" ||
      (!remove && (typeof emoji !== "string" || emoji.length < 1 || emoji.length > 32))) {
    throw new functions.https.HttpsError("invalid-argument", "Invalid reaction request.");
  }
  const chatRef = db.collection("chats").doc(chatId);
  const messageRef = chatRef.collection("messages").doc(messageId);
  let messageSenderId;
  await db.runTransaction(async (transaction) => {
    const chatSnapshot = await transaction.get(chatRef);
    const messageSnapshot = await transaction.get(messageRef);
    if (!chatSnapshot.exists || !messageSnapshot.exists) {
      throw new functions.https.HttpsError("not-found", "Chat message not found.");
    }
    const participants = Array.isArray(chatSnapshot.data().participants) ?
      chatSnapshot.data().participants : [];
    if (!participants.includes(callerUid)) {
      throw new functions.https.HttpsError("permission-denied", "Chat membership is required.");
    }
    const message = messageSnapshot.data();
    messageSenderId = message.senderId;
    const reactions = Array.isArray(message.reactions) ? message.reactions
      .filter((item) => item && typeof item.emoji === "string" && Array.isArray(item.userIds))
      .slice(0, 50)
      .map((item) => ({
        emoji: item.emoji.slice(0, 32),
        userIds: [...new Set(item.userIds.filter(validUid))].filter((uid) => uid !== callerUid),
      }))
      .filter((item) => item.userIds.length > 0) : [];
    if (!remove) {
      const existing = reactions.find((item) => item.emoji === emoji);
      if (existing) existing.userIds.push(callerUid);
      else reactions.push({ emoji, userIds: [callerUid] });
    }
    transaction.update(messageRef, { reactions });
  });

  if (!remove && validUid(messageSenderId) && messageSenderId !== callerUid) {
    const caller = await db.collection("users").doc(callerUid).get();
    await sendPushToUser(messageSenderId, {
      title: displayReactionSender(caller.exists ? caller.data() : null),
      body: `Reacted ${emoji} to your message`,
      type: "chat_reaction",
      targetUserId: callerUid,
      additionalData: { chatId },
    });
  }
  return { success: true };
});

function displayReactionSender(profile) {
  if (!profile) return "New reaction";
  const name = String(profile.firstName || profile.fullName || "Someone").trim().slice(0, 100);
  return `${name || "Someone"} reacted`;
}


/**
 * ==================================================================
 * 3. CHAT NOTIFICATIONS (Migrated to Firestore)
 * ==================================================================
 */

exports.onDirectMessageCreated = functions.firestore
  .document('chats/{chatId}/messages/{messageId}')
  .onCreate(async (snapshot, context) => {
    const message = snapshot.data();
    const chatId = context.params.chatId;
    const senderId = message.senderId;

    if (!senderId) {
      console.log(`[Chat] Message ${context.params.messageId} has no senderId, skipping`);
      return null;
    }

    // [FIX] Fetch the chat document with retry logic.
    // When a new DM is created, the chat document and first message may be
    // written in separate batch commits. The Cloud Function trigger can fire
    // before the chat document batch is fully propagated.
    let chatDoc = await db.collection('chats').doc(chatId).get();

    if (!chatDoc.exists) {
      console.log(`[Chat] Chat document not found for ${chatId}, retrying in 1.5s...`);
      await new Promise(r => setTimeout(r, 1500));
      chatDoc = await db.collection('chats').doc(chatId).get();
    }

    if (!chatDoc.exists) {
      console.log(`[Chat] Chat document still not found for ${chatId} after retry, skipping`);
      return null;
    }

    let chatData = chatDoc.data();
    let participants = chatData.participants || [];

    // [FIX] Retry if participants are missing (race condition with batch writes)
    if (!Array.isArray(participants) || participants.length === 0) {
      console.log(`[Chat] No participants for ${chatId}, retrying in 1s...`);
      await new Promise(r => setTimeout(r, 1000));
      const retryDoc = await db.collection('chats').doc(chatId).get();
      if (retryDoc.exists) {
        chatData = retryDoc.data();
        participants = chatData.participants || [];
      }
    }

    if (!Array.isArray(participants) || participants.length === 0) {
      console.log(`[Chat] No participants found for chat ${chatId} after retry`);
      return null;
    }

    await deliverMessageIndex(
      chatId,
      context.params.messageId,
      message,
      [...new Set(participants)],
    );

    // Ensure canonical chats/{chatId} also has lastMessage & updatedAt so any
    // client fetching chats/{chatId} immediately sees the latest message.
    const existingLastTs = (chatData.lastMessage && typeof chatData.lastMessage.timestamp === "number")
      ? chatData.lastMessage.timestamp
      : 0;
    const msgTs = typeof message.timestamp === "number" ? message.timestamp : Date.now();
    if (!chatData.lastMessage || msgTs >= existingLastTs) {
      const typeLabels = {
        image: "Photo",
        video: "Video",
        audio: "Voice message",
        audio_file: "Audio",
        document: "Document",
        location: "Location",
        dsp_transfer: "Sent $DIASPORA",
        "money-transfer": "Remittance",
      };
      const preview = String(message.content || typeLabels[message.type] || "Message").slice(0, 2000);
      await db.collection("chats").doc(chatId).set({
        lastMessage: {
          id: context.params.messageId,
          content: preview,
          timestamp: msgTs,
          senderId: message.senderId,
          senderName: String(message.senderName || "").slice(0, 200),
          type: message.type || "text",
          status: message.status || "sent",
        },
        updatedAt: msgTs,
      }, { merge: true }).catch((err) => {
        console.warn(`[Chat] Could not sync lastMessage onto chats/${chatId}: ${err.message}`);
      });
    }

    // STRICT SENDER FILTERING & DEDUPLICATION
    let recipients = participants.filter(uid => String(uid) !== String(senderId));
    recipients = [...new Set(recipients)]; // Deduplicate

    console.log(`[Chat] MsgID: ${context.params.messageId} | Sender: ${senderId} | Recipients: ${recipients.join(', ')}`);

    // Community detection using all chatId patterns (matches Flutter client)
    const isCommunity = chatData.type === 'community' ||
      chatId.startsWith('chat_') ||
      chatId.startsWith('home_') ||
      chatId.startsWith('host_') ||
      chatId.startsWith('past_') ||
      chatId === 'global_community';

    const promises = recipients.map(async (recipientId) => {
      const mentions = Array.isArray(message.mentions) ? message.mentions : [];
      const isMentioned = mentions.includes(recipientId);

      // Check Mute Status from Firestore userChats subcollection
      let isManuallyMuted = false;
      try {
        const muteDoc = await db
          .collection('users')
          .doc(recipientId)
          .collection('userChats')
          .doc(chatId)
          .get();
        if (muteDoc.exists) {
          const muteData = muteDoc.data();
          isManuallyMuted = muteData.muted === true || muteData.isMuted === true;
        }
      } catch (e) {
        console.log(`[Chat] Error checking mute for ${recipientId}: ${e.message}`);
      }

      // Routing Logic
      let shouldNotify = false;

      if (isMentioned) {
        // [OVERRIDE] Mentions always notify
        shouldNotify = true;
      } else if (isManuallyMuted) {
        // [RESPECT] Manual mute takes precedence if not mentioned
        shouldNotify = false;
      } else if (isCommunity) {
        // [DEFAULT] Communities are muted by default
        shouldNotify = false;
      } else {
        // [DEFAULT] Direct messages and Private Groups notify by default
        shouldNotify = true;
      }

      if (!shouldNotify) {
        const reason = isManuallyMuted ? "manually muted" : "community default mute";
        console.log(`[Chat] Skipping notification for ${recipientId} in ${chatId} (${reason})`);
        return null;
      }

      let title = message.senderName || "New Message";
      if (isMentioned) {
        title = `📢 Mentioned by ${message.senderName || "someone"}`;
      }
      let body = message.content;

      if (message.type === 'image') body = "📷 sent a photo";
      if (message.type === 'video') body = "🎥 sent a video";
      if (message.type === 'audio') body = "🎤 sent a voice message";
      if (message.type === 'audio_file') body = "🎵 sent an audio file";
      if (message.type === 'location') body = "📍 sent a location";
      if (message.type === 'document') body = "📄 sent a document";
      if (message.type === 'dsp_transfer') body = message.content ? `🪙 ${message.content}` : "🪙 sent $DIASPORA";
      if (message.type === 'money-transfer') body = message.content ? `💸 ${message.content}` : "💸 sent a remittance";

      // Ensure we don't crash if body is empty
      if (!body) body = "Sent a message";

      await sendPushToUser(recipientId, {
        title: title,
        body: body,
        type: "chat_message",
        targetUserId: senderId, // Open chat with sender
        city: "", // Not relevant for chat
        additionalData: { chatId: chatId }
      });
    });

    await Promise.all(promises);
    return null;
  });
