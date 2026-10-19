/** Canonical community and community-chat provisioning. */
const {functions, admin, db} = require("./shared");
const {requireAuth, requireAppCheck, consumeRateLimit} = require("./security");
const {continentForCountry, CONTINENT_NAMES, hasStateLevel} = require("./country_continents");

const MAX_COMMUNITY_MEMBERS = 500;
const TYPES = new Set(["global", "continent", "country", "state", "city"]);
const LOCATION_TYPES = new Set(["global", "home", "host", "past"]);

function validUid(value) {
  return typeof value === "string" && value.length > 0 && value.length <= 128;
}

function text(value, maximum = 200) {
  if (typeof value !== "string") return null;
  const normalized = value.trim();
  return normalized && normalized.length <= maximum ? normalized : null;
}

function slug(value) {
  return String(value || "")
      .normalize("NFKD")
      .replace(/[\u0300-\u036f]/g, "")
      .toLowerCase()
      .replace(/[^a-z0-9]+/g, "-")
      .replace(/^-+|-+$/g, "")
      .slice(0, 80);
}

function profileLocation(profile, locationType, explicitLocation) {
  if (explicitLocation && typeof explicitLocation === "object") {
    const countryCode = String(
        explicitLocation.countryCode || explicitLocation.country_code || "",
    ).trim().toUpperCase();
    return {
      city: text(explicitLocation.city),
      state: text(explicitLocation.state),
      country: text(explicitLocation.country),
      countryCode,
      placeId: text(explicitLocation.place_id || explicitLocation.placeId, 256),
    };
  }
  if (locationType === "global") {
    return {
      city: null,
      state: null,
      country: null,
      countryCode: "GLOBAL",
      placeId: null,
    };
  }
  const key = locationType === "home" ? "homeLocation" : "hostLocation";
  const location = profile[key] && typeof profile[key] === "object" ? profile[key] : {};
  const countryCode = String(
      profile[locationType === "home" ? "homeCountryCode" : "hostCountryCode"] ||
      location.country_code || location.countryCode || "",
  ).trim().toUpperCase();
  return {
    city: text(location.city),
    state: text(location.state),
    country: text(location.country),
    countryCode,
    placeId: text(location.place_id || location.placeId, 256),
  };
}

function communityIdentity(type, locationType, location, homeCountryCode) {
  if (type === "global" || locationType === "global") {
    return {
      id: "global_community",
      name: "Global Community",
      continent: "Global",
    };
  }
  const continentKey = continentForCountry(location.countryCode);
  if (!continentKey) {
    throw new functions.https.HttpsError(
        "failed-precondition",
        "The profile country is not supported.",
    );
  }
  const effectiveLocationType = locationType === "past" ? "host" : locationType;
  const suffix = effectiveLocationType === "host" ? `_${homeCountryCode.toLowerCase()}` : "";
  let id;
  let name;
  if (type === "continent") {
    const continentName = CONTINENT_NAMES[continentKey];
    id = `${effectiveLocationType}_continent_${slug(continentName)}${suffix}`;
    name = `${continentName} Community`;
  } else if (type === "country") {
    id = `${effectiveLocationType}_country_${location.countryCode.toLowerCase()}${suffix}`;
    name = `${location.country || location.countryCode} Community`;
  } else if (type === "state") {
    if (!location.state) {
      throw new functions.https.HttpsError("failed-precondition", "The profile has no state.");
    }
    id = `${effectiveLocationType}_state_${location.countryCode.toLowerCase()}_${slug(location.state)}` +
      suffix;
    name = `${location.state} Community`;
  } else {
    if (!location.city) {
      throw new functions.https.HttpsError("failed-precondition", "The profile has no city.");
    }
    id = `${effectiveLocationType}_city_${location.countryCode.toLowerCase()}_` +
      `${location.state ? slug(location.state) : "no-state"}_${slug(location.city)}${suffix}`;
    name = `${location.city} Community`;
  }
  return {id, name, continent: CONTINENT_NAMES[continentKey]};
}

function buildJoinedSystemMessage(chatRef, chatId, uid, profile, timestamp) {
  const fullName = [profile.firstName, profile.lastName]
    .filter((s) => typeof s === "string" && s.trim().length > 0)
    .join(" ")
    .trim() || "Member";
  const msgRef = chatRef.collection("messages").doc();
  const messageData = {
    id: msgRef.id,
    chatId,
    senderId: uid,
    senderName: fullName,
    content: "joined the community",
    type: "system",
    timestamp,
    status: "read",
  };
  const lastMessageData = {
    id: msgRef.id,
    content: `${fullName} joined the community`,
    timestamp,
    senderId: uid,
    senderName: fullName,
    type: "system",
    status: "read",
  };
  return {msgRef, messageData, lastMessageData};
}

exports.ensureCommunity = functions.https.onCall(async (data, context) => {
  requireAppCheck(context);
  const uid = requireAuth(context);
  await consumeRateLimit("community-ensure", uid, 120, 24 * 60 * 60 * 1000);
  const type = data && data.type;
  const locationType = data && data.locationType;
  if (!TYPES.has(type) || !LOCATION_TYPES.has(locationType)) {
    throw new functions.https.HttpsError("invalid-argument", "Invalid community type.");
  }

  const user = await db.collection("users").doc(uid).get();
  if (!user.exists) {
    throw new functions.https.HttpsError(
        "failed-precondition",
        "Complete your profile before joining communities.",
    );
  }
  const profile = user.data() || {};
  const isGlobal = type === "global" || locationType === "global";
  const explicitLocation = data && data.location;
  const location = profileLocation(profile, locationType, explicitLocation);
  const homeCountryCode = String(
      (data && data.homeCountryCode) || profile.homeCountryCode || "",
  ).trim().toUpperCase();

  if (!isGlobal && (!location.countryCode || !homeCountryCode)) {
    throw new functions.https.HttpsError(
        "failed-precondition",
        "Complete your home and host countries first.",
    );
  }
  const identity = communityIdentity(type, locationType, location, homeCountryCode);
  const communityRef = db.collection("communities").doc(identity.id);
  const chatId = `chat_${identity.id}`;
  const chatRef = db.collection("chats").doc(chatId);

  // Check if community already exists to avoid transaction contention
  const communitySnap = await communityRef.get();
  if (communitySnap.exists) {
    const existing = communitySnap.data() || {};
    const effectiveLocationType = locationType === "past" ? "host" : locationType;
    if (!isGlobal &&
        (existing.type !== type || existing.locationType !== effectiveLocationType ||
          String(existing.homeCountryCode || "").toUpperCase() !== homeCountryCode)) {
      throw new functions.https.HttpsError(
          "already-exists",
          "The canonical community identifier is already in use.",
      );
    }
    const userMemberships = Array.isArray(profile.communityMemberships) ? profile.communityMemberships : [];
    if (userMemberships.includes(identity.id)) {
      return {communityId: identity.id, chatId, name: existing.name || identity.name, created: false};
    }

    const nowMs = Date.now();
    const {msgRef, messageData, lastMessageData} = buildJoinedSystemMessage(
        chatRef, chatId, uid, profile, nowMs,
    );
    const batch = db.batch();
    const rawMembers = Array.isArray(existing.members) ? existing.members : [];
    const needsMemberAdd = rawMembers.length < MAX_COMMUNITY_MEMBERS && !rawMembers.includes(uid);
    batch.set(communityRef, {
      memberCount: admin.firestore.FieldValue.increment(1),
      totalMembers: admin.firestore.FieldValue.increment(1),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      ...(needsMemberAdd ? {members: admin.firestore.FieldValue.arrayUnion(uid)} : {}),
    }, {merge: true});

    const chatSnap = await chatRef.get();
    if (chatSnap.exists) {
      const existingChat = chatSnap.data() || {};
      const rawChatParticipants = Array.isArray(existingChat.participants) ? existingChat.participants : [];
      const needsChatAdd = rawChatParticipants.length < MAX_COMMUNITY_MEMBERS && !rawChatParticipants.includes(uid);
      batch.set(chatRef, {
        memberCount: admin.firestore.FieldValue.increment(1),
        updatedAt: nowMs,
        lastMessage: lastMessageData,
        ...(needsChatAdd ? {participants: admin.firestore.FieldValue.arrayUnion(uid)} : {}),
      }, {merge: true});
    } else {
      batch.set(chatRef, {
        id: chatId,
        communityId: identity.id,
        type: "community",
        name: existing.name || identity.name,
        participants: [uid],
        memberCount: 1,
        admins: [],
        createdBy: "platform",
        isPublic: existing.isPrivate !== true,
        createdAt: nowMs,
        updatedAt: nowMs,
        lastMessage: lastMessageData,
      }, {merge: true});
    }
    batch.set(msgRef, messageData);

    batch.set(user.ref, {
      communityMemberships: admin.firestore.FieldValue.arrayUnion(identity.id),
    }, {merge: true});

    const userChatRef = user.ref.collection("userChats").doc(chatId);
    batch.set(userChatRef, {
      chatId,
      name: existing.name || identity.name,
      type: "community",
      lastMessage: lastMessageData,
      lastRead: nowMs,
      addedAt: nowMs,
      updatedAt: nowMs,
      isDeleted: false,
    }, {merge: true});

    await batch.commit();
    return {communityId: identity.id, chatId, name: existing.name || identity.name, created: false};
  }

  // Community does not exist yet: create atomically via transaction
  let created = false;
  await db.runTransaction(async (transaction) => {
    const community = await transaction.get(communityRef);
    const chat = await transaction.get(chatRef);
    const existing = community.exists ? community.data() : {};
    const effectiveLocationType = locationType === "past" ? "host" : locationType;
    if (community.exists && !isGlobal &&
        (existing.type !== type || existing.locationType !== effectiveLocationType ||
          String(existing.homeCountryCode || "").toUpperCase() !== homeCountryCode)) {
      throw new functions.https.HttpsError(
          "already-exists",
          "The canonical community identifier is already in use.",
      );
    }
    const rawMembers = Array.isArray(existing.members) ?
      [...new Set(existing.members.filter(validUid))] : [];
    const isMemberInArray = rawMembers.includes(uid);
    const members = isMemberInArray ?
      rawMembers :
      (rawMembers.length < MAX_COMMUNITY_MEMBERS ? [...rawMembers, uid] : rawMembers);

    const userMemberships = Array.isArray(profile.communityMemberships) ? profile.communityMemberships : [];
    const isNewMember = !isMemberInArray && !userMemberships.includes(identity.id);
    const currentMemberCount = typeof existing.totalMembers === "number" ?
      existing.totalMembers :
      (typeof existing.memberCount === "number" ? existing.memberCount : rawMembers.length);
    const updatedCount = isNewMember ? currentMemberCount + 1 : currentMemberCount;

    // Geographic namespaces are platform/governance resources. The first
    // member to materialize a missing location must not become its moderator.
    const admins = Array.isArray(existing.admins) ?
      [...new Set(existing.admins.filter(validUid))] : [];
    created = !community.exists;

    transaction.set(communityRef, {
      id: identity.id,
      name: community.exists ? existing.name || identity.name : identity.name,
      description: community.exists ? existing.description || "" : "",
      type: isGlobal ? "global" : type,
      locationType: isGlobal ? "global" : effectiveLocationType,
      location: isGlobal ? {countryCode: "GLOBAL"} : {
        city: location.city,
        state: location.state,
        country: location.country,
        countryCode: location.countryCode,
        placeId: location.placeId,
      },
      homeCountryCode: isGlobal ? null : homeCountryCode,
      hostCountryCode: isGlobal ? null : (effectiveLocationType === "host" ? location.countryCode : null),
      continent: identity.continent,
      members,
      admins,
      memberCount: updatedCount,
      totalMembers: updatedCount,
      isPrivate: community.exists ? existing.isPrivate === true : false,
      chatId,
      profileImage: community.exists ? existing.profileImage || "" : "",
      flag: community.exists ? existing.flag || "" : "",
      images: community.exists && Array.isArray(existing.images) ? existing.images : [],
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      ...(!community.exists && {createdAt: admin.firestore.FieldValue.serverTimestamp()}),
    }, {merge: true});

    const existingChat = chat.exists ? chat.data() : {};
    if (chat.exists && existingChat.communityId !== identity.id) {
      throw new functions.https.HttpsError(
          "already-exists",
          "The canonical community chat identifier is already in use.",
      );
    }
    const rawChatParticipants = Array.isArray(existingChat.participants) ?
      [...new Set(existingChat.participants.filter(validUid))] : [];
    const chatParticipants = rawChatParticipants.includes(uid) ?
      rawChatParticipants :
      (rawChatParticipants.length < MAX_COMMUNITY_MEMBERS ? [...rawChatParticipants, uid] : rawChatParticipants);

    const nowMs = Date.now();
    const {msgRef, messageData, lastMessageData} = buildJoinedSystemMessage(
        chatRef, chatId, uid, profile, nowMs,
    );

    transaction.set(chatRef, {
      id: chatId,
      communityId: identity.id,
      type: "community",
      name: identity.name,
      participants: chatParticipants,
      memberCount: updatedCount,
      admins,
      createdBy: existingChat.createdBy || "platform",
      isPublic: existing.isPrivate !== true,
      createdAt: chat.exists ? existingChat.createdAt || nowMs : nowMs,
      updatedAt: nowMs,
      lastMessage: isNewMember ? lastMessageData : (chat.exists ? existingChat.lastMessage || null : lastMessageData),
    }, {merge: true});
    if (isNewMember) {
      transaction.set(msgRef, messageData);
    }
    transaction.set(user.ref, {
      communityMemberships: admin.firestore.FieldValue.arrayUnion(identity.id),
    }, {merge: true});
    const userChatRef = user.ref.collection("userChats").doc(chatId);
    transaction.set(userChatRef, {
      chatId,
      name: identity.name,
      type: "community",
      ...(isNewMember ? {lastMessage: lastMessageData} : {}),
      lastRead: nowMs,
      addedAt: nowMs,
      updatedAt: nowMs,
      isDeleted: false,
    }, {merge: true});
  });
  return {communityId: identity.id, chatId, name: identity.name, created};
});

function computeHierarchyIdentities(homeLocation, hostLocation, homeCountryCode, hostCountryCode) {
  const identities = [];
  // 1. Global
  identities.push({
    identity: {id: "global_community", name: "Global Community", continent: "Global"},
    type: "global",
    locationType: "global",
    location: {countryCode: "GLOBAL"},
    homeCountryCode: null,
    hostCountryCode: null,
  });

  // 2. Home hierarchy
  if (homeCountryCode) {
    const homeContKey = continentForCountry(homeCountryCode);
    if (homeContKey) {
      const homeContName = CONTINENT_NAMES[homeContKey];
      identities.push({
        identity: {id: `home_continent_${slug(homeContName)}`, name: `${homeContName} Community`, continent: homeContName},
        type: "continent",
        locationType: "home",
        location: homeLocation,
        homeCountryCode,
        hostCountryCode: null,
      });
      identities.push({
        identity: {id: `home_country_${homeCountryCode.toLowerCase()}`, name: `${homeLocation.country || homeCountryCode} Community`, continent: homeContName},
        type: "country",
        locationType: "home",
        location: homeLocation,
        homeCountryCode,
        hostCountryCode: null,
      });
      if (homeLocation.state && hasStateLevel(homeCountryCode)) {
        identities.push({
          identity: {id: `home_state_${homeCountryCode.toLowerCase()}_${slug(homeLocation.state)}`, name: `${homeLocation.state} Community`, continent: homeContName},
          type: "state",
          locationType: "home",
          location: homeLocation,
          homeCountryCode,
          hostCountryCode: null,
        });
      }
      if (homeLocation.city) {
        identities.push({
          identity: {
            id: `home_city_${homeCountryCode.toLowerCase()}_${homeLocation.state ? slug(homeLocation.state) : "no-state"}_${slug(homeLocation.city)}`,
            name: `${homeLocation.city} Community`,
            continent: homeContName,
          },
          type: "city",
          locationType: "home",
          location: homeLocation,
          homeCountryCode,
          hostCountryCode: null,
        });
      }
    }
  }

  // 3. Host hierarchy
  const effectiveHostCountry = hostCountryCode || homeCountryCode;
  if (effectiveHostCountry) {
    const hostContKey = continentForCountry(effectiveHostCountry);
    if (hostContKey) {
      const hostContName = CONTINENT_NAMES[hostContKey];
      const suffix = `_${homeCountryCode.toLowerCase()}`;
      identities.push({
        identity: {id: `host_continent_${slug(hostContName)}${suffix}`, name: `${hostContName} Community`, continent: hostContName},
        type: "continent",
        locationType: "host",
        location: hostLocation,
        homeCountryCode,
        hostCountryCode: effectiveHostCountry,
      });
      identities.push({
        identity: {id: `host_country_${effectiveHostCountry.toLowerCase()}${suffix}`, name: `${hostLocation.country || effectiveHostCountry} Community`, continent: hostContName},
        type: "country",
        locationType: "host",
        location: hostLocation,
        homeCountryCode,
        hostCountryCode: effectiveHostCountry,
      });
      if (hostLocation.state && hasStateLevel(effectiveHostCountry)) {
        identities.push({
          identity: {id: `host_state_${effectiveHostCountry.toLowerCase()}_${slug(hostLocation.state)}${suffix}`, name: `${hostLocation.state} Community`, continent: hostContName},
          type: "state",
          locationType: "host",
          location: hostLocation,
          homeCountryCode,
          hostCountryCode: effectiveHostCountry,
        });
      }
      if (hostLocation.city) {
        identities.push({
          identity: {
            id: `host_city_${effectiveHostCountry.toLowerCase()}_${hostLocation.state ? slug(hostLocation.state) : "no-state"}_${slug(hostLocation.city)}${suffix}`,
            name: `${hostLocation.city} Community`,
            continent: hostContName,
          },
          type: "city",
          locationType: "host",
          location: hostLocation,
          homeCountryCode,
          hostCountryCode: effectiveHostCountry,
        });
      }
    }
  }

  return identities;
}

exports.provisionSignupCommunities = functions.https.onCall(async (data, context) => {
  requireAppCheck(context);
  const uid = requireAuth(context);
  await consumeRateLimit("signup-provision", uid, 20, 24 * 60 * 60 * 1000);

  const userRef = db.collection("users").doc(uid);
  const userSnap = await userRef.get();
  if (!userSnap.exists) {
    throw new functions.https.HttpsError(
        "failed-precondition",
        "Complete your profile before joining communities.",
    );
  }
  const profile = userSnap.data() || {};
  const existingMemberships = new Set(
      Array.isArray(profile.communityMemberships) ? profile.communityMemberships : [],
  );
  const homeCountryCode = String(
      data?.homeCountryCode || profile.homeCountryCode || "",
  ).trim().toUpperCase();
  const hostCountryCode = String(
      data?.hostCountryCode || profile.hostCountryCode || homeCountryCode || "",
  ).trim().toUpperCase();

  const homeLocation = profileLocation(profile, "home", data?.homeLocation);
  const hostLocation = profileLocation(profile, "host", data?.hostLocation);

  const items = computeHierarchyIdentities(homeLocation, hostLocation, homeCountryCode, hostCountryCode);
  if (items.length === 0) {
    throw new functions.https.HttpsError("invalid-argument", "Valid home and host locations required.");
  }

  const communityRefs = items.map((item) => db.collection("communities").doc(item.identity.id));
  const chatRefs = items.map((item) => db.collection("chats").doc(`chat_${item.identity.id}`));

  const [commSnaps, chatSnaps] = await Promise.all([
    db.getAll(...communityRefs),
    db.getAll(...chatRefs),
  ]);

  const batch = db.batch();
  const now = admin.firestore.FieldValue.serverTimestamp();
  const nowMs = Date.now();
  const communityIds = [];
  const chatIds = [];

  for (let i = 0; i < items.length; i++) {
    const item = items[i];
    const commSnap = commSnaps[i];
    const chatSnap = chatSnaps[i];
    const commId = item.identity.id;
    const chatId = `chat_${commId}`;
    communityIds.push(commId);
    chatIds.push(chatId);

    const existingComm = commSnap.exists ? (commSnap.data() || {}) : {};
    const rawMembers = Array.isArray(existingComm.members) ? existingComm.members : [];
    const existingChat = chatSnap.exists ? (chatSnap.data() || {}) : {};
    const rawParticipants = Array.isArray(existingChat.participants) ? existingChat.participants : [];
    const isAlreadyJoined = existingMemberships.has(commId) ||
        rawMembers.includes(uid) ||
        rawParticipants.includes(uid);

    const {msgRef, messageData, lastMessageData} = buildJoinedSystemMessage(
        chatSnap.ref, chatId, uid, profile, nowMs + i,
    );

    if (commSnap.exists) {
      const needsMemberAdd = rawMembers.length < MAX_COMMUNITY_MEMBERS && !rawMembers.includes(uid);
      batch.set(commSnap.ref, {
        ...(!isAlreadyJoined ? {
          memberCount: admin.firestore.FieldValue.increment(1),
          totalMembers: admin.firestore.FieldValue.increment(1),
        } : {}),
        updatedAt: now,
        ...(needsMemberAdd ? {members: admin.firestore.FieldValue.arrayUnion(uid)} : {}),
      }, {merge: true});
    } else {
      batch.set(commSnap.ref, {
        id: commId,
        name: item.identity.name,
        description: "",
        type: item.type,
        locationType: item.locationType,
        location: item.location,
        homeCountryCode: item.homeCountryCode,
        hostCountryCode: item.hostCountryCode,
        continent: item.identity.continent,
        members: [uid],
        admins: [],
        memberCount: 1,
        totalMembers: 1,
        isPrivate: false,
        chatId,
        profileImage: "",
        flag: "",
        images: [],
        createdAt: now,
        updatedAt: now,
      });
    }

    if (chatSnap.exists) {
      const needsParticipantAdd = rawParticipants.length < MAX_COMMUNITY_MEMBERS && !rawParticipants.includes(uid);
      batch.set(chatSnap.ref, {
        ...(!isAlreadyJoined ? {
          memberCount: admin.firestore.FieldValue.increment(1),
          lastMessage: lastMessageData,
        } : {}),
        updatedAt: nowMs + i,
        ...(needsParticipantAdd ? {participants: admin.firestore.FieldValue.arrayUnion(uid)} : {}),
      }, {merge: true});
    } else {
      batch.set(chatSnap.ref, {
        id: chatId,
        communityId: commId,
        type: "community",
        name: item.identity.name,
        participants: [uid],
        memberCount: 1,
        admins: [],
        createdBy: "platform",
        isPublic: true,
        createdAt: nowMs + i,
        updatedAt: nowMs + i,
        lastMessage: lastMessageData,
      });
    }

    if (!isAlreadyJoined) {
      batch.set(msgRef, messageData);
    }

    const userChatRef = userRef.collection("userChats").doc(chatId);
    batch.set(userChatRef, {
      chatId,
      name: item.identity.name,
      type: "community",
      ...(!isAlreadyJoined ? {lastMessage: lastMessageData} : {}),
      lastRead: nowMs + i,
      addedAt: nowMs + i,
      updatedAt: nowMs + i,
      isDeleted: false,
    }, {merge: true});
  }

  batch.set(userRef, {
    communityMemberships: admin.firestore.FieldValue.arrayUnion(...communityIds),
  }, {merge: true});

  await batch.commit();

  return {communityIds, chatIds, success: true};
});
