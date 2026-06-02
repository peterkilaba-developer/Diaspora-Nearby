/**
 * Platform-managed bilateral Chamber of Commerce group operations.
 */
const {functions, admin, db} = require("./shared");

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
  const now = Date.now();

  return db.runTransaction(async (transaction) => {
    const chatSnap = await transaction.get(chatRef);
    const userChatSnap = await transaction.get(userChatRef);
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

    if (!participants.includes(userId)) {
      participants.push(userId);
      enrolled = true;
    }

    const fields = officialFields(details, homeCountryCode, hostCountryCode);
    transaction.set(chatRef, {
      id: details.chatId,
      ...fields,
      description,
      participants,
      memberCount: participants.length,
      createdAt: chatSnap.exists ? chatSnap.data().createdAt || now : now,
      updatedAt: now,
      lastMessage: chatSnap.exists ? chatSnap.data().lastMessage || null : null,
      createdBy: admin.firestore.FieldValue.delete(),
    }, {merge: true});

    transaction.set(discoverableRef, {
      id: details.chatId,
      ...fields,
      description,
      memberCount: participants.length,
      createdAt: chatSnap.exists ? chatSnap.data().createdAt || now : now,
    }, {merge: true});

    if (!userChatSnap.exists) {
      transaction.set(userChatRef, {
        chatId: details.chatId,
        updatedAt: now,
        addedAt: now,
        lastRead: now,
        pinned: false,
        isDeleted: false,
      }, {merge: true});
    }

    return {chatId: details.chatId, created, enrolled};
  });
}

exports.ensureSignupChamber = functions.https.onCall(async (data, context) => {
  const userId = requireAuth(context);
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
  const userId = requireAuth(context);
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

exports.manageChamber = functions.https.onCall(async (data, context) => {
  const adminId = requireAuth(context);
  const adminSnap = await db.collection("users").doc(adminId).get();
  if (!adminSnap.exists || adminSnap.data().isAdmin !== true) {
    throw new functions.https.HttpsError(
        "permission-denied",
        "Platform administrator access is required.",
    );
  }

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
    data.addMemberIds.filter((id) => typeof id === "string" && id.length > 0) :
    [];
  const removeMemberIds = Array.isArray(data.removeMemberIds) ?
    data.removeMemberIds.filter((id) => typeof id === "string" && id.length > 0) :
    [];
  const now = Date.now();
  const chatRef = db.collection("chats").doc(chatId);
  const discoverableRef = db.collection("discoverableChats").doc(chatId);

  await db.runTransaction(async (transaction) => {
    const chatSnap = await transaction.get(chatRef);
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

    addMemberIds.forEach((memberId) => {
      transaction.set(
          db.collection("users").doc(memberId).collection("userChats").doc(chatId),
          {
            chatId,
            updatedAt: now,
            addedAt: now,
            lastRead: now,
            pinned: false,
            isDeleted: false,
          },
          {merge: true},
      );
    });
    removeMemberIds.forEach((memberId) => {
      transaction.delete(
          db.collection("users").doc(memberId).collection("userChats").doc(chatId),
      );
    });
  });

  return {chatId, success: true};
});
