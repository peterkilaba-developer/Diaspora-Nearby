/** Canonical community and community-chat provisioning. */
const {functions, admin, db} = require("./shared");
const {requireAuth, requireAppCheck, consumeRateLimit} = require("./security");
const {continentForCountry, CONTINENT_NAMES} = require("./country_continents");

const MAX_COMMUNITY_MEMBERS = 500;
const TYPES = new Set(["continent", "country", "state", "city"]);
const LOCATION_TYPES = new Set(["home", "host"]);

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

function profileLocation(profile, locationType) {
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
  const continentKey = continentForCountry(location.countryCode);
  if (!continentKey) {
    throw new functions.https.HttpsError(
        "failed-precondition",
        "The profile country is not supported.",
    );
  }
  const suffix = locationType === "host" ? `_${homeCountryCode.toLowerCase()}` : "";
  let id;
  let name;
  if (type === "continent") {
    const continentName = CONTINENT_NAMES[continentKey];
    id = `${locationType}_continent_${slug(continentName)}${suffix}`;
    name = `${continentName} Community`;
  } else if (type === "country") {
    id = `${locationType}_country_${location.countryCode.toLowerCase()}${suffix}`;
    name = `${location.country || location.countryCode} Community`;
  } else if (type === "state") {
    if (!location.state) {
      throw new functions.https.HttpsError("failed-precondition", "The profile has no state.");
    }
    id = `${locationType}_state_${location.countryCode.toLowerCase()}_${slug(location.state)}` +
      suffix;
    name = `${location.state} Community`;
  } else {
    if (!location.city) {
      throw new functions.https.HttpsError("failed-precondition", "The profile has no city.");
    }
    id = `${locationType}_city_${location.countryCode.toLowerCase()}_` +
      `${location.state ? slug(location.state) : "no-state"}_${slug(location.city)}${suffix}`;
    name = `${location.city} Community`;
  }
  return {id, name, continent: CONTINENT_NAMES[continentKey]};
}

exports.ensureCommunity = functions.https.onCall(async (data, context) => {
  requireAppCheck(context);
  const uid = requireAuth(context);
  await consumeRateLimit("community-ensure", uid, 30, 24 * 60 * 60 * 1000);
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
  const profile = user.data();
  const location = profileLocation(profile, locationType);
  const homeCountryCode = String(profile.homeCountryCode || "").trim().toUpperCase();
  if (!location.countryCode || !homeCountryCode) {
    throw new functions.https.HttpsError(
        "failed-precondition",
        "Complete your home and host countries first.",
    );
  }
  const identity = communityIdentity(type, locationType, location, homeCountryCode);
  const communityRef = db.collection("communities").doc(identity.id);
  const chatId = `chat_${identity.id}`;
  const chatRef = db.collection("chats").doc(chatId);

  let created = false;
  await db.runTransaction(async (transaction) => {
    const community = await transaction.get(communityRef);
    const chat = await transaction.get(chatRef);
    const existing = community.exists ? community.data() : {};
    if (community.exists &&
        (existing.type !== type || existing.locationType !== locationType ||
          String(existing.homeCountryCode || "").toUpperCase() !== homeCountryCode)) {
      throw new functions.https.HttpsError(
          "already-exists",
          "The canonical community identifier is already in use.",
      );
    }
    const members = Array.isArray(existing.members) ?
      [...new Set(existing.members.filter(validUid))] : [];
    if (!members.includes(uid)) members.push(uid);
    if (members.length > MAX_COMMUNITY_MEMBERS) {
      throw new functions.https.HttpsError(
          "resource-exhausted",
          "This community has reached its current membership limit.",
      );
    }
    // Geographic namespaces are platform/governance resources. The first
    // member to materialize a missing location must not become its moderator.
    const admins = Array.isArray(existing.admins) ?
      [...new Set(existing.admins.filter(validUid))] : [];
    created = !community.exists;

    transaction.set(communityRef, {
      id: identity.id,
      name: community.exists ? existing.name || identity.name : identity.name,
      description: community.exists ? existing.description || "" : "",
      type,
      locationType,
      location: {
        city: location.city,
        state: location.state,
        country: location.country,
        countryCode: location.countryCode,
        placeId: location.placeId,
      },
      homeCountryCode,
      hostCountryCode: locationType === "host" ? location.countryCode : null,
      continent: identity.continent,
      members,
      admins,
      memberCount: members.length,
      totalMembers: members.length,
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
    transaction.set(chatRef, {
      id: chatId,
      communityId: identity.id,
      type: "community",
      name: identity.name,
      participants: members,
      memberCount: members.length,
      admins,
      createdBy: existingChat.createdBy || "platform",
      isPublic: existing.isPrivate !== true,
      createdAt: chat.exists ? existingChat.createdAt || Date.now() : Date.now(),
      updatedAt: Date.now(),
      lastMessage: chat.exists ? existingChat.lastMessage || null : null,
    }, {merge: true});
    transaction.set(user.ref, {
      communityMemberships: admin.firestore.FieldValue.arrayUnion(identity.id),
    }, {merge: true});
  });
  return {communityId: identity.id, chatId, name: identity.name, created};
});
