/**
 * Platform-managed bilateral Chamber of Commerce group operations.
 */
const {functions, admin, db} = require("./shared");
const {requireAdmin, requireAppCheck, consumeRateLimit} = require("./security");

const MAX_CHAMBER_PARTICIPANTS = 500;

const CHAMBER_CATEGORY = "Business & Entrepreneurship";
const CHAMBER_METADATA = {
  isChamber: true,
  managedBy: "platform",
  avatarType: "splitFlags",
};

function requireAuth(context) {
  if (!context.auth || !context.auth.uid) {
    throw new functions.https.HttpsError(
        "unauthenticated",
        "Authentication is required.",
    );
  }
  return context.auth.uid;
}

function normalizeCountryCode(value, fieldName) {
  const code = String(value || "").trim().toUpperCase();
  if (!/^[A-Z0-9-]{2,12}$/.test(code) || code === "XX") {
    throw new functions.https.HttpsError(
        "failed-precondition",
        `A valid ${fieldName} is required to create a chamber.`,
    );
  }
  return code;
}

function signupCountryCode(value) {
  const code = String(value || "").trim().toUpperCase();
  return /^[A-Z0-9-]{2,12}$/.test(code) && code !== "XX" ? code : null;
}

function chamberDetails(homeCountryCode, hostCountryCode) {
  const corridorId = `${homeCountryCode}_${hostCountryCode}`;
  return {
    chatId: `chamber_${homeCountryCode.toLowerCase()}_${hostCountryCode.toLowerCase()}`,
    corridorId,
    name: `${homeCountryCode} - ${hostCountryCode} Chamber of Commerce`,
    description:
      "First contact for individuals and businesses seeking trade and " +
      `investment connections between ${homeCountryCode} and ` +
      `${hostCountryCode} through the diaspora community.`,
    communityId: `home_country_${homeCountryCode.toLowerCase()}`,
  };
}

function officialFields(details, homeCountryCode, hostCountryCode) {
  return {
    type: "group",
    isPublic: true,
    communityId: details.communityId,
    homeCountryCode,
    hostCountryCode,
    name: details.name,
    category: CHAMBER_CATEGORY,
    admins: [],
    metadata: {
      ...CHAMBER_METADATA,
      corridorId: details.corridorId,
    },
  };
}

async function ensureMembership({
  userId,
  details,
  homeCountryCode,
  hostCountryCode,
  requireCommunity,
}) {
  const chatRef = db.collection("chats").doc(details.chatId);
  const discoverableRef = db.collection("discoverableChats").doc(details.chatId);
  const userChatRef = db
      .collection("users")
      .doc(userId)
      .collection("userChats")
      .doc(details.chatId);
  const communityRef = db.collection("communities").doc(details.communityId);
  const organizationRef = db.collection("organizations").doc(details.chatId);
  const userRef = db.collection("users").doc(userId);
  const now = Date.now();

  return db.runTransaction(async (transaction) => {
    const chatSnap = await transaction.get(chatRef);
    const userChatSnap = await transaction.get(userChatRef);
    const organizationSnap = await transaction.get(organizationRef);
    if (requireCommunity) {
      const communitySnap = await transaction.get(communityRef);
      if (!communitySnap.exists) {
        throw new functions.https.HttpsError(
            "failed-precondition",
            "The home-country community must exist before its chamber.",
        );
      }
    }

    let created = false;
    let enrolled = false;
    let description = details.description;
    let participants = [];

    if (chatSnap.exists) {
      const chatData = chatSnap.data();
      if (!chatData.metadata || chatData.metadata.isChamber !== true) {
        throw new functions.https.HttpsError(
            "already-exists",
            "The chamber identifier is already in use.",
        );
      }
      participants = Array.isArray(chatData.participants) ?
        [...chatData.participants] :
        [];
      description = chatData.description || details.description;
    } else {
      created = true;
    }

    const isAlreadyParticipant = participants.includes(userId);
    if (!isAlreadyParticipant) {
      enrolled = true;
      if (participants.length < MAX_CHAMBER_PARTICIPANTS) {
        participants.push(userId);
      }
    }
    const currentMemberCount = typeof chatSnap.data()?.memberCount === "number" ?
      chatSnap.data().memberCount : participants.length;
    const updatedMemberCount = !isAlreadyParticipant ? currentMemberCount + 1 : currentMemberCount;

    const existingLastMsg = chatSnap.exists ? chatSnap.data().lastMessage || null : null;
    const existingChatUpdatedAt = chatSnap.exists ?
      (typeof chatSnap.data().updatedAt === "number" ?
        chatSnap.data().updatedAt :
        (chatSnap.data().updatedAt && typeof chatSnap.data().updatedAt.toMillis === "function" ?
          chatSnap.data().updatedAt.toMillis() :
          ((existingLastMsg && typeof existingLastMsg.timestamp === "number") ?
            existingLastMsg.timestamp : now))) :
      now;
    const effectiveChatUpdatedAt = (existingLastMsg && typeof existingLastMsg.timestamp === "number") ?
      existingLastMsg.timestamp : existingChatUpdatedAt;

    const fields = officialFields(details, homeCountryCode, hostCountryCode);
    transaction.set(chatRef, {
      id: details.chatId,
      ...fields,
      description,
      participants,
      memberCount: updatedMemberCount,
      createdAt: chatSnap.exists ? chatSnap.data().createdAt || now : now,
      updatedAt: effectiveChatUpdatedAt,
      lastMessage: existingLastMsg,
      createdBy: admin.firestore.FieldValue.delete(),
    }, {merge: true});

    transaction.set(discoverableRef, {
      id: details.chatId,
      ...fields,
      description,
      memberCount: updatedMemberCount,
      createdAt: chatSnap.exists ? chatSnap.data().createdAt || now : now,
    }, {merge: true});

    if (!userChatSnap.exists) {
      transaction.set(userChatRef, {
        chatId: details.chatId,
        accessLevel: "member",
        ...(existingLastMsg ? {lastMessage: existingLastMsg} : {}),
        updatedAt: effectiveChatUpdatedAt,
        addedAt: now,
        lastRead: now,
        pinned: false,
        isDeleted: false,
      }, {merge: true});
    } else {
      transaction.set(userChatRef, {
        accessLevel: "member",
        ...(existingLastMsg ? {lastMessage: existingLastMsg} : {}),
        updatedAt: effectiveChatUpdatedAt,
        isDeleted: false,
      }, {merge: true});
    }

    const existingOrganization = organizationSnap.exists ? organizationSnap.data() : {};
    const rawFollowers = Array.isArray(existingOrganization.followers) ?
      [...new Set(existingOrganization.followers)] : [];
    const followers = rawFollowers.includes(userId) ?
      rawFollowers :
      (rawFollowers.length < MAX_CHAMBER_PARTICIPANTS ? [...rawFollowers, userId] : rawFollowers);

    transaction.set(organizationRef, {
      id: details.chatId,
      kind: "corridor_chamber",
      name: details.name,
      businessName: details.name,
      description,
      type: "Chamber of Commerce",
      chatId: details.chatId,
      homeCountryCode,
      hostCountryCode,
      communityId: details.communityId,
      isPublic: true,
      status: "active",
      members: participants,
      followers,
      memberCount: updatedMemberCount,
      admins: Array.isArray(existingOrganization.admins) ?
        existingOrganization.admins : [],
      pendingAdmins: Array.isArray(existingOrganization.pendingAdmins) ?
        existingOrganization.pendingAdmins : [],
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      ...(!organizationSnap.exists && {
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      }),
    }, {merge: true});
    transaction.set(userRef, {
      organizationMemberships: admin.firestore.FieldValue.arrayUnion(details.chatId),
    }, {merge: true});

    return {chatId: details.chatId, created, enrolled};
  });
}

exports.ensureSignupChamber = functions.https.onCall(async (data, context) => {
  requireAppCheck(context);
  const userId = requireAuth(context);
  await consumeRateLimit("chamber-ensure", userId, 20, 24 * 60 * 60 * 1000);
  const userSnap = await db.collection("users").doc(userId).get();
  if (!userSnap.exists) {
    throw new functions.https.HttpsError(
        "failed-precondition",
        "Complete your profile before creating a chamber.",
    );
  }

  const user = userSnap.data();
  const homeCountryCode = signupCountryCode(user.homeCountryCode);
  const hostCountryCode = signupCountryCode(user.hostCountryCode);
  if (!homeCountryCode || !hostCountryCode) {
    return {skipped: true, reason: "missing-country"};
  }
  if (homeCountryCode === hostCountryCode) {
    return {skipped: true, reason: "same-country"};
  }

  const details = chamberDetails(homeCountryCode, hostCountryCode);
  const result = await ensureMembership({
    userId,
    details,
    homeCountryCode,
    hostCountryCode,
    requireCommunity: true,
  });
  return {...result, skipped: false};
});

exports.joinChamber = functions.https.onCall(async (data, context) => {
  requireAppCheck(context);
  const userId = requireAuth(context);
  await consumeRateLimit("chamber-join", userId, 30, 24 * 60 * 60 * 1000);
  const chatId = typeof data.chatId === "string" ? data.chatId : "";
  if (!chatId.startsWith("chamber_")) {
    throw new functions.https.HttpsError(
        "invalid-argument",
        "A chamber chat ID is required.",
    );
  }

  const chatSnap = await db.collection("chats").doc(chatId).get();
  const chat = chatSnap.exists ? chatSnap.data() : null;
  if (!chat || chat.isPublic !== true || chat.metadata?.isChamber !== true) {
    throw new functions.https.HttpsError("not-found", "Chamber not found.");
  }

  const homeCountryCode = normalizeCountryCode(
      chat.homeCountryCode,
      "home country",
  );
  const hostCountryCode = normalizeCountryCode(
      chat.hostCountryCode,
      "host country",
  );
  const details = chamberDetails(homeCountryCode, hostCountryCode);
  if (details.chatId !== chatId) {
    throw new functions.https.HttpsError(
        "failed-precondition",
        "Chamber identity is invalid.",
    );
  }

  return ensureMembership({
    userId,
    details,
    homeCountryCode,
    hostCountryCode,
    requireCommunity: false,
  });
});

exports.setChamberFollow = functions.https.onCall(async (data, context) => {
  requireAppCheck(context);
  const userId = requireAuth(context);
  await consumeRateLimit("chamber-follow", userId, 60, 24 * 60 * 60 * 1000);
  const chatId = typeof data.chatId === "string" ? data.chatId : "";
  const following = data.following;
  if (!chatId.startsWith("chamber_") || typeof following !== "boolean") {
    throw new functions.https.HttpsError("invalid-argument", "Invalid chamber follow request.");
  }

  const chatRef = db.collection("chats").doc(chatId);
  const organizationRef = db.collection("organizations").doc(chatId);
  const userChatRef = db.collection("users").doc(userId)
      .collection("userChats").doc(chatId);
  await db.runTransaction(async (transaction) => {
    const chatSnapshot = await transaction.get(chatRef);
    const organizationSnapshot = await transaction.get(organizationRef);
    if (!chatSnapshot.exists || chatSnapshot.data().metadata?.isChamber !== true) {
      throw new functions.https.HttpsError("not-found", "Chamber not found.");
    }
    const organization = organizationSnapshot.exists ? organizationSnapshot.data() : {};
    const members = Array.isArray(organization.members) ? organization.members : [];
    if (!following && members.includes(userId)) {
      throw new functions.https.HttpsError(
          "failed-precondition",
          "Leave chamber membership before unfollowing.",
      );
    }
    const followers = Array.isArray(organization.followers) ?
      [...new Set(organization.followers)] : [];
    const followerIndex = followers.indexOf(userId);
    if (following && followerIndex < 0) followers.push(userId);
    if (!following && followerIndex >= 0) followers.splice(followerIndex, 1);

    const participants = Array.isArray(chatSnapshot.data().participants) ?
      [...new Set(chatSnapshot.data().participants)] : [];
    const participantIndex = participants.indexOf(userId);
    if (following && participantIndex < 0) participants.push(userId);
    if (!following && participantIndex >= 0) participants.splice(participantIndex, 1);
    if (participants.length > MAX_CHAMBER_PARTICIPANTS) {
      throw new functions.https.HttpsError("resource-exhausted", "This chamber is full.");
    }

    transaction.set(organizationRef, {
      id: chatId,
      kind: "corridor_chamber",
      chatId,
      followers,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});
    transaction.update(chatRef, {
      participants,
      memberCount: participants.length,
      updatedAt: Date.now(),
    });
    if (following) {
      transaction.set(userChatRef, {
        chatId,
        accessLevel: "follower",
        isDeleted: false,
        updatedAt: Date.now(),
        lastRead: Date.now(),
      }, {merge: true});
    } else {
      transaction.delete(userChatRef);
    }
  });
  return {chatId, following};
});

exports.leaveChamber = functions.https.onCall(async (data, context) => {
  requireAppCheck(context);
  const userId = requireAuth(context);
  await consumeRateLimit("chamber-leave", userId, 30, 24 * 60 * 60 * 1000);
  const rawId = typeof data.chatId === "string" ? data.chatId.trim() : "";
  if (!rawId.startsWith("chamber_") && !rawId.startsWith("org_chamber_")) {
    throw new functions.https.HttpsError("invalid-argument", "A chamber chat ID is required.");
  }
  const chamberOrgId = rawId.startsWith("org_") ? rawId.substring(4) : rawId;
  const chamberChatId = rawId.startsWith("org_") ? rawId : `org_${rawId}`;

  const chatRef = db.collection("chats").doc(chamberChatId);
  const altChatRef = db.collection("chats").doc(chamberOrgId);
  const organizationRef = db.collection("organizations").doc(chamberOrgId);
  const altOrgRef = db.collection("organizations").doc(chamberChatId);
  const userChatRef = db.collection("users").doc(userId)
      .collection("userChats").doc(chamberChatId);
  const altUserChatRef = db.collection("users").doc(userId)
      .collection("userChats").doc(chamberOrgId);
  const userRef = db.collection("users").doc(userId);

  await db.runTransaction(async (transaction) => {
    let chat = await transaction.get(chatRef);
    if (!chat.exists) chat = await transaction.get(altChatRef);

    let organization = await transaction.get(organizationRef);
    let targetOrgRef = organizationRef;
    if (!organization.exists) {
      organization = await transaction.get(altOrgRef);
      targetOrgRef = altOrgRef;
    }

    if (!organization.exists) {
      throw new functions.https.HttpsError("not-found", "Chamber not found.");
    }
    const orgData = organization.data() || {};
    const members = Array.isArray(orgData.members) ?
      [...new Set(orgData.members)] : [];
    const index = members.indexOf(userId);
    if (index >= 0) members.splice(index, 1);

    transaction.update(targetOrgRef, {
      members,
      memberCount: members.length,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    transaction.set(userChatRef, {
      accessLevel: "follower",
      updatedAt: Date.now(),
    }, {merge: true});
    transaction.set(altUserChatRef, {
      accessLevel: "follower",
      updatedAt: Date.now(),
    }, {merge: true});
    transaction.set(userRef, {
      organizationMemberships: admin.firestore.FieldValue.arrayRemove(chamberOrgId, chamberChatId),
    }, {merge: true});
  });
  return {chatId: rawId, member: false};
});

exports.manageChamber = functions.https.onCall(async (data, context) => {
  requireAppCheck(context);
  const adminId = requireAdmin(context);
  await consumeRateLimit("chamber-manage", adminId, 60, 60 * 60 * 1000);

  const chatId = typeof data.chatId === "string" ? data.chatId : "";
  if (!chatId.startsWith("chamber_")) {
    throw new functions.https.HttpsError(
        "invalid-argument",
        "A chamber chat ID is required.",
    );
  }

  const description = data.description == null ? null :
    String(data.description).trim();
  if (description != null && description.length > 200) {
    throw new functions.https.HttpsError(
        "invalid-argument",
        "Description must be 200 characters or fewer.",
    );
  }
  const addMemberIds = Array.isArray(data.addMemberIds) ?
    [...new Set(data.addMemberIds.filter((id) =>
      typeof id === "string" && id.length > 0 && id.length <= 128))].slice(0, 100) :
    [];
  const removeMemberIds = Array.isArray(data.removeMemberIds) ?
    [...new Set(data.removeMemberIds.filter((id) =>
      typeof id === "string" && id.length > 0 && id.length <= 128))].slice(0, 100) :
    [];
  const now = Date.now();
  const chatRef = db.collection("chats").doc(chatId);
  const discoverableRef = db.collection("discoverableChats").doc(chatId);
  const organizationRef = db.collection("organizations").doc(chatId);

  await db.runTransaction(async (transaction) => {
    const chatSnap = await transaction.get(chatRef);
    await transaction.get(organizationRef);
    const chat = chatSnap.exists ? chatSnap.data() : null;
    if (!chat || chat.metadata?.isChamber !== true) {
      throw new functions.https.HttpsError("not-found", "Chamber not found.");
    }

    const members = new Set(
        Array.isArray(chat.participants) ? chat.participants : [],
    );
    addMemberIds.forEach((id) => members.add(id));
    removeMemberIds.forEach((id) => members.delete(id));
    const participants = [...members];
    if (participants.length > MAX_CHAMBER_PARTICIPANTS) {
      throw new functions.https.HttpsError("resource-exhausted", "This chamber is full.");
    }
    const updates = {
      participants,
      memberCount: participants.length,
      updatedAt: now,
    };
    if (description != null) updates.description = description;
    transaction.update(chatRef, updates);
    transaction.set(discoverableRef, {
      memberCount: participants.length,
      ...(description != null ? {description} : {}),
    }, {merge: true});
    transaction.set(organizationRef, {
      members: participants,
      memberCount: participants.length,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      ...(description != null ? {description} : {}),
    }, {merge: true});

    addMemberIds.forEach((memberId) => {
      transaction.set(
          db.collection("users").doc(memberId).collection("userChats").doc(chatId),
          {
            chatId,
            accessLevel: "member",
            updatedAt: now,
            addedAt: now,
            lastRead: now,
            pinned: false,
            isDeleted: false,
          },
          {merge: true},
      );
      transaction.set(db.collection("users").doc(memberId), {
        organizationMemberships: admin.firestore.FieldValue.arrayUnion(chatId),
      }, {merge: true});
    });
    removeMemberIds.forEach((memberId) => {
      transaction.delete(
          db.collection("users").doc(memberId).collection("userChats").doc(chatId),
      );
      transaction.set(db.collection("users").doc(memberId), {
        organizationMemberships: admin.firestore.FieldValue.arrayRemove(chatId),
      }, {merge: true});
    });
  });

  return {chatId, success: true};
});
