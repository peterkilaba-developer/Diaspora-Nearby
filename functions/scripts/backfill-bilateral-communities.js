/**
 * Backfill bilateral diaspora communities and chats for all existing users.
 *
 * Rules:
 *   - Canonical Community ID: bilateral_country_<first>_<second> (sorted alphabetically)
 *   - Canonical Chat ID:      chat_bilateral_country_<first>_<second>
 *   - Canonical Display Name: "<FIRST> - <SECOND> Community" (viewer-relative in UI)
 *   - Idempotent:             first user creates, subsequent users join
 *   - Skipped when:           homeCC === hostCC (users from and living in the same country),
 *                             or either code is empty / "XX"
 *
 * Each eligible user is added to:
 *   1. `communities/{communityId}` (members, memberCount, totalMembers)
 *   2. `chats/{chatId}` (participants, memberCount)
 *   3. `users/{userId}.communityMemberships`
 *   4. `users/{userId}/userChats/{chatId}`
 *
 * Usage:
 *   node functions/scripts/backfill-bilateral-communities.js          # dry run
 *   node functions/scripts/backfill-bilateral-communities.js --apply  # write changes
 */
const fs = require("fs");
const os = require("os");
const path = require("path");
const {Firestore, FieldValue} = require("@google-cloud/firestore");
const {continentForCountry, CONTINENT_NAMES} = require("../lib/country_continents");

function createFirestoreClient() {
  const projectId = process.env.GCLOUD_PROJECT || process.env.GOOGLE_CLOUD_PROJECT || "diaspora-nearby-a3dac";
  try {
    const cfgPath = path.join(os.homedir(), ".config", "configstore", "firebase-tools.json");
    if (fs.existsSync(cfgPath)) {
      const cfg = JSON.parse(fs.readFileSync(cfgPath, "utf8"));
      if (cfg.tokens && cfg.tokens.access_token) {
        const authClient = {
          getAccessToken: async () => ({
            token: cfg.tokens.access_token,
            res: null,
          }),
          getRequestHeaders: async () => ({
            Authorization: `Bearer ${cfg.tokens.access_token}`,
          }),
        };
        return new Firestore({
          projectId,
          authClient,
          preferRest: true,
        });
      }
    }
  } catch (_) {
    // Fall back to default Firestore initialization
  }
  return new Firestore({projectId});
}

const db = createFirestoreClient();

const DRY_RUN = !process.argv.includes("--apply");
const MAX_COMMUNITY_MEMBERS = 500;

function bilateralIds(homeCC, hostCC) {
  const codeA = String(homeCC || "").trim().toUpperCase();
  const codeB = String(hostCC || "").trim().toUpperCase();
  const [firstCode, secondCode] = [codeA, codeB].sort();
  const communityId = `bilateral_country_${firstCode.toLowerCase()}_${secondCode.toLowerCase()}`;
  const chatId = `chat_${communityId}`;
  const name = `${firstCode} - ${secondCode} Community`;
  const contKey = continentForCountry(firstCode) || continentForCountry(secondCode);
  const continent = (contKey && CONTINENT_NAMES[contKey]) || "Global";
  return {firstCode, secondCode, communityId, chatId, name, continent};
}

function resolveCountryCodes(data) {
  const rawHome = data.homeCountryCode ||
    (data.homeLocation && (data.homeLocation.countryCode || data.homeLocation.country_code)) ||
    "";
  const rawHost = data.hostCountryCode ||
    (data.hostLocation && (data.hostLocation.countryCode || data.hostLocation.country_code)) ||
    (data.currentLocation && (data.currentLocation.countryCode || data.currentLocation.country_code)) ||
    "";
  return {
    homeCC: String(rawHome).trim().toUpperCase(),
    hostCC: String(rawHost).trim().toUpperCase(),
  };
}

async function ensureBilateralCommunity({userId, homeCC, hostCC}) {
  if (!homeCC || !hostCC) return {skipped: "missing-code"};
  if (homeCC === "XX" || hostCC === "XX") return {skipped: "placeholder"};
  // Explicitly ignore users who are from and live in the same country
  if (homeCC === hostCC) return {skipped: "same-country"};

  const {
    firstCode,
    secondCode,
    communityId,
    chatId,
    name,
    continent,
  } = bilateralIds(homeCC, hostCC);

  if (DRY_RUN) {
    return {dryRun: true, communityId, chatId, name, userId};
  }

  const communityRef = db.collection("communities").doc(communityId);
  const chatRef = db.collection("chats").doc(chatId);
  const userRef = db.collection("users").doc(userId);
  const userChatRef = userRef.collection("userChats").doc(chatId);

  const now = Date.now();
  const initialLastMsg = {
    content: "Bilateral community opened",
    timestamp: now,
    type: "system",
    senderId: "system",
    senderName: "System",
  };

  const {wasCreated, effectiveLastMsg} = await db.runTransaction(async (tx) => {
    const [commSnap, chatSnap] = await Promise.all([
      tx.get(communityRef),
      tx.get(chatRef),
    ]);

    if (!commSnap.exists) {
      tx.set(communityRef, {
        id: communityId,
        name,
        description: "",
        type: "country",
        locationType: "bilateral",
        location: {
          city: null,
          state: null,
          country: null,
          countryCode: firstCode,
          placeId: null,
        },
        homeCountryCode: firstCode,
        hostCountryCode: secondCode,
        continent,
        members: [userId],
        admins: [],
        memberCount: 1,
        totalMembers: 1,
        isPrivate: false,
        chatId,
        profileImage: "",
        flag: "",
        images: [],
        createdAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      });

      tx.set(chatRef, {
        id: chatId,
        communityId,
        type: "community",
        locationType: "bilateral",
        homeCountryCode: firstCode,
        hostCountryCode: secondCode,
        name,
        participants: [userId],
        memberCount: 1,
        admins: [],
        createdBy: "platform",
        isPublic: true,
        createdAt: now,
        updatedAt: now,
        lastMessage: initialLastMsg,
      });

      return {wasCreated: true, effectiveLastMsg: initialLastMsg};
    }

    const commData = commSnap.data() || {};
    const members = Array.isArray(commData.members) ? commData.members : [];
    const alreadyInComm = members.includes(userId);
    const needsCommArrayAdd = !alreadyInComm && members.length < MAX_COMMUNITY_MEMBERS;

    tx.set(communityRef, {
      locationType: "bilateral",
      homeCountryCode: firstCode,
      hostCountryCode: secondCode,
      ...(needsCommArrayAdd ? {members: FieldValue.arrayUnion(userId)} : {}),
      ...(!alreadyInComm ? {
        memberCount: FieldValue.increment(1),
        totalMembers: FieldValue.increment(1),
      } : {}),
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});

    const chatData = chatSnap.exists ? (chatSnap.data() || {}) : {};
    const participants = Array.isArray(chatData.participants) ? chatData.participants : [];
    const alreadyInChat = participants.includes(userId);
    const needsChatArrayAdd = !alreadyInChat && participants.length < MAX_COMMUNITY_MEMBERS;
    const lastMsg = chatData.lastMessage || initialLastMsg;

    if (!chatSnap.exists) {
      tx.set(chatRef, {
        id: chatId,
        communityId,
        type: "community",
        locationType: "bilateral",
        homeCountryCode: firstCode,
        hostCountryCode: secondCode,
        name,
        participants: [userId],
        memberCount: 1,
        admins: [],
        createdBy: "platform",
        isPublic: true,
        createdAt: now,
        updatedAt: now,
        lastMessage: lastMsg,
      });
    } else {
      tx.set(chatRef, {
        communityId,
        type: "community",
        locationType: "bilateral",
        homeCountryCode: firstCode,
        hostCountryCode: secondCode,
        ...(needsChatArrayAdd ? {participants: FieldValue.arrayUnion(userId)} : {}),
        ...(!alreadyInChat ? {memberCount: FieldValue.increment(1)} : {}),
        updatedAt: now,
      }, {merge: true});
    }

    return {wasCreated: false, effectiveLastMsg: lastMsg};
  });

  // Update user's communityMemberships & userChats subcollection
  await Promise.all([
    userRef.set({
      communityMemberships: FieldValue.arrayUnion(communityId),
    }, {merge: true}),
    userChatRef.set({
      chatId,
      name,
      type: "community",
      lastMessage: effectiveLastMsg,
      lastRead: now,
      addedAt: now,
      updatedAt: now,
      isDeleted: false,
    }, {merge: true}),
  ]);

  return {wasCreated, communityId, chatId, name, userId};
}

async function main() {
  console.log(
      `\n🤝 Bilateral Community backfill — ${DRY_RUN ? "DRY RUN" : "APPLYING CHANGES"}\n`,
  );

  const usersSnap = await db.collection("users").get();
  console.log(`Found ${usersSnap.size} user docs.\n`);

  const stats = {
    processed: 0,
    joined: 0,
    created: 0,
    skippedSame: 0,
    skippedMissing: 0,
    skippedPlaceholder: 0,
    errors: 0,
  };
  const distinctCommunities = new Set();
  const errors = [];

  for (const doc of usersSnap.docs) {
    const data = doc.data() || {};
    const userId = doc.id;
    const {homeCC, hostCC} = resolveCountryCodes(data);

    try {
      const result = await ensureBilateralCommunity({userId, homeCC, hostCC});
      stats.processed += 1;

      if (result.skipped === "same-country") {
        stats.skippedSame += 1;
        continue;
      }
      if (result.skipped === "missing-code") {
        stats.skippedMissing += 1;
        continue;
      }
      if (result.skipped === "placeholder") {
        stats.skippedPlaceholder += 1;
        continue;
      }

      if (result.dryRun) {
        console.log(
            `  [dry] ${userId.slice(0, 8)}… (${homeCC} → ${hostCC}) → ${result.communityId} (${result.name})`,
        );
        distinctCommunities.add(result.communityId);
        continue;
      }

      distinctCommunities.add(result.communityId);
      if (result.wasCreated) {
        stats.created += 1;
        console.log(
            `  ➕ Created ${result.communityId} (${result.name}) — first member ${userId.slice(0, 8)}… (${homeCC} → ${hostCC})`,
        );
      } else {
        stats.joined += 1;
        console.log(
            `  → Joined ${userId.slice(0, 8)}… (${homeCC} → ${hostCC}) into ${result.communityId}`,
        );
      }
    } catch (e) {
      stats.errors += 1;
      errors.push({userId, error: e.message});
      console.error(`  ✗ ${userId}: ${e.message}`);
    }
  }

  console.log("\n📊 Summary");
  console.log("  Users processed:                  ", stats.processed);
  console.log("  Bilateral communities created:    ", stats.created);
  console.log("  User joins:                       ", stats.joined);
  console.log("  Distinct bilateral communities:   ", distinctCommunities.size);
  console.log("  Skipped (same country home==host):", stats.skippedSame);
  console.log("  Skipped (missing code):           ", stats.skippedMissing);
  console.log("  Skipped (XX/placeholder):         ", stats.skippedPlaceholder);
  console.log("  Errors:                           ", stats.errors);

  if (DRY_RUN) {
    console.log("\n👀 Dry run only. Re-run with --apply to write changes.\n");
  } else {
    console.log("\n✅ Done.\n");
  }

  if (errors.length) {
    console.log("\nFirst 10 errors:");
    errors.slice(0, 10).forEach((e) =>
      console.log(`  ${e.userId}: ${e.error}`),
    );
  }
}

main()
    .then(() => process.exit(0))
    .catch((e) => {
      console.error("Fatal:", e);
      process.exit(1);
    });
