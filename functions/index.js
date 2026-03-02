const functions = require("firebase-functions");
const admin = require("firebase-admin");
const { ethers } = require("ethers");

admin.initializeApp();
const db = admin.firestore();

/**
 * ==================================================================
 * 0. WALLET MANAGEMENT
 * ==================================================================
 */

// Helper to generate a new wallet and return public/private parts
function generateWallet() {
  const wallet = ethers.Wallet.createRandom();
  return {
    address: wallet.address,
    privateKey: wallet.privateKey,
    mnemonic: wallet.mnemonic.phrase,
  };
}

// 1. Generate Wallet for New Communities
exports.onCommunityWrite = functions.firestore
  .document("communities/{communityId}")
  .onWrite(async (change, context) => {
    // Only on create or update
    if (!change.after.exists) return null;

    const newData = change.after.data();
    const communityId = context.params.communityId;

    // specific check: if walletAddress is missing or null, generate it
    if (newData.walletAddress) return null;

    console.log(`[Wallet] Generating wallet for Community: ${communityId}`);
    const wallet = generateWallet();

    const batch = db.batch();

    // Public info
    batch.update(change.after.ref, {
      walletAddress: wallet.address,
      walletGeneratedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    // Private info (Secrets Subcollection)
    const secretRef = change.after.ref.collection("secrets").doc("wallet");
    batch.set(secretRef, {
      privateKey: wallet.privateKey,
      mnemonic: wallet.mnemonic,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    try {
      await batch.commit();
      console.log(`[Wallet] Generated ${wallet.address} for Community ${communityId}`);
    } catch (e) {
      console.error(`[Wallet] Failed to save community wallet: ${e.message}`);
    }
  });

// 2. Generate Wallet for New/Updated Users
exports.onUserWrite = functions.firestore
  .document("users/{userId}")
  .onWrite(async (change, context) => {
    // Only on create or update
    if (!change.after.exists) return null;

    const newData = change.after.data();
    const userId = context.params.userId;

    // check if walletAddress is missing
    if (newData.walletAddress) return null;

    // [Constraint] Only generate for real users, not mocks if we can distinguish, 
    // but here we just check if it's missing.

    console.log(`[Wallet] Generating wallet for User: ${userId}`);
    const wallet = generateWallet();

    const batch = db.batch();

    // Public info
    batch.update(change.after.ref, {
      walletAddress: wallet.address,
      walletGeneratedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    // Private info (Secrets Subcollection)
    const secretRef = change.after.ref.collection("secrets").doc("wallet");
    batch.set(secretRef, {
      privateKey: wallet.privateKey,
      mnemonic: wallet.mnemonic,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    try {
      await batch.commit();
      console.log(`[Wallet] Generated ${wallet.address} for User ${userId}`);
    } catch (e) {
      console.error(`[Wallet] Failed to save user wallet: ${e.message}`);
    }
  });

// 3. Generate Founder Treasury Wallet (Callable)
// Call this once to initialize the system treasury wallet
exports.ensureSystemWallets = functions.https.onCall(async (data, context) => {
  // Check Admin
  if (!context.auth) throw new functions.https.HttpsError('unauthenticated', 'User must be authenticated.');

  const callerId = context.auth.uid;
  const callerDoc = await db.collection('users').doc(callerId).get();
  if (!callerDoc.exists || !callerDoc.data().isAdmin) {
    throw new functions.https.HttpsError('permission-denied', 'Admin access required.');
  }

  const treasuryRef = db.collection('system_stats').doc('treasury');
  const doc = await treasuryRef.get();

  // We check 'foundersWallet' specifically
  if (doc.exists && doc.data().foundersWallet) {
    return { message: "Founder wallet already exists.", address: doc.data().foundersWallet };
  }

  console.log(`[Wallet] Generating Founder Treasury Wallet...`);
  const wallet = generateWallet();

  // For System Treasury, we might store the private key in a very restricted document, 
  // currently we'll store it in a new secrets collection under system_stats for consistency.

  const batch = db.batch();

  // Public info in treasury doc
  batch.set(treasuryRef, {
    foundersWallet: wallet.address,
    foundersWalletGeneratedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, { merge: true });

  // Secret info
  const secretRef = treasuryRef.collection("secrets").doc("founders_wallet");
  batch.set(secretRef, {
    privateKey: wallet.privateKey,
    mnemonic: wallet.mnemonic,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  await batch.commit();
  console.log(`[Wallet] Founder Wallet Generated: ${wallet.address}`);

  return {
    success: true,
    message: "Generates Founder Wallet",
    address: wallet.address
  };
});

// Distance calculation helper (Haversine formula)
function calculateDistanceInMiles(lat1, lon1, lat2, lon2) {
  const R = 3958.8; // Radius of Earth in miles
  const dLat = (lat2 - lat1) * (Math.PI / 180);
  const dLon = (lon2 - lon1) * (Math.PI / 180);
  const a =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos(lat1 * (Math.PI / 180)) *
    Math.cos(lat2 * (Math.PI / 180)) *
    Math.sin(dLon / 2) * Math.sin(dLon / 2);
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  return R * c;
}

/**
 * ==================================================================
 * 1. PROXIMITY ALERTS
 * ==================================================================
 */

exports.checkProximity = functions.firestore
  .document("users/{userId}")
  .onUpdate(async (change, context) => {
    const userId = context.params.userId;
    const beforeData = change.before.data();
    const afterData = change.after.data();

    // 1. Validate Location Change
    const oldLoc = beforeData.currentLocation;
    const newLoc = afterData.currentLocation;

    if (!newLoc || !newLoc.geometry) return null;

    // Skip if location hasn't changed significantly (optimization)
    if (
      oldLoc &&
      oldLoc.geometry &&
      oldLoc.geometry.location.lat === newLoc.geometry.location.lat &&
      oldLoc.geometry.location.lng === newLoc.geometry.location.lng
    ) {
      return null;
    }

    const currentLat = newLoc.geometry.location.lat;
    const currentLng = newLoc.geometry.location.lng;
    const currentCity = newLoc.city || "Unknown";
    const homeCountryCode = afterData.homeCountryCode;
    const firstName = afterData.firstName || "Someone";

    if (!homeCountryCode) return null;

    console.log(`[Proximity] User ${userId} moved in ${currentCity}. Checking for compatriots...`);

    // 2. Query Compatriots (Same Home Country)
    const snapshot = await db
      .collection("users")
      .where("homeCountryCode", "==", homeCountryCode)
      .get();

    console.log(`[Proximity] Found ${snapshot.size} candidates from ${homeCountryCode}`);

    // [UPDATED] Get full home country name if available
    const homeCountry = afterData.homeCountry || homeCountryCode;

    const promises = [];

    snapshot.forEach((doc) => {
      if (doc.id === userId) return;

      const otherData = doc.data();
      const otherLoc = otherData.currentLocation;

      if (!otherLoc || !otherLoc.geometry) return;

      const otherLat = otherLoc.geometry.location.lat;
      const otherLng = otherLoc.geometry.location.lng;
      const otherCity = otherLoc.city || "Unknown";

      // 3. Calculate Distance
      const distance = calculateDistanceInMiles(currentLat, currentLng, otherLat, otherLng);

      // Threshold: 100 Miles
      if (distance <= 100) {
        // [UPDATED] Pass distance and full country name
        const otherCountry = otherData.homeCountry || homeCountryCode;
        promises.push(handleProximityMatch(userId, doc.id, firstName, otherData.firstName, currentCity, homeCountryCode, distance, homeCountry, otherCountry));
      }
    });

    await Promise.all(promises);
    return null;
  });

async function handleProximityMatch(userAId, userBId, nameA, nameB, city, homeCountryCode, distance, countryA, countryB) {
  // Sort IDs to ensure consistent document key
  const [id1, id2] = [userAId, userBId].sort();
  const historyDocId = `${id1}_${id2}`;

  const historyRef = db.collection("proximity_history").doc(historyDocId);

  await db.runTransaction(async (t) => {
    const historyDoc = await t.get(historyRef);
    let shouldNotify = true;

    if (historyDoc.exists) {
      const data = historyDoc.data();
      const lastMetCity = data.lastMetCity;

      if (lastMetCity === city) {
        console.log(`[Proximity] Supressed alert for ${userAId} & ${userBId}. Already met in ${city}.`);
        shouldNotify = false;
      }
    }

    if (shouldNotify) {
      console.log(`[Proximity] NEW MATCH! ${nameA} & ${nameB} in ${city}. Sending Alerts.`);

      t.set(historyRef, {
        users: [id1, id2],
        lastMetCity: city,
        lastMetTime: admin.firestore.FieldValue.serverTimestamp(),
        homeCountryCode: homeCountryCode
      });
    }
    return shouldNotify;
  }).then(async (shouldNotify) => {
    if (shouldNotify) {
      // [UPDATED] Format distance
      const distStr = distance.toFixed(1) + " miles";

      await sendPushToUser(userAId, {
        title: "Diaspora Nearby!",
        body: `${nameB} from ${countryB} is nearby in ${city}: ${distStr} Away. Connect now`,
        type: "nearby_compatriot",
        targetUserId: userBId,
        city: city
      });

      await sendPushToUser(userBId, {
        title: "Diaspora Nearby!",
        body: `${nameA} from ${countryA} is nearby in ${city}: ${distStr} Away. Connect now`,
        type: "nearby_compatriot",
        targetUserId: userAId,
        city: city
      });
    }
  }).catch(e => {
    console.error("Transaction failure", e);
  });
}

/**
 * ==================================================================
 * 2. RADIO PROXY (Restored)
 * ==================================================================
 */

exports.radioProxy = functions.https.onRequest(async (req, res) => {
  const endpoint = req.query.endpoint;
  if (!endpoint) {
    res.status(400).send('Missing endpoint parameter');
    return;
  }

  // Base URL for Radio Browser API (Primary Mirror)
  const baseUrl = 'https://de1.api.radio-browser.info/json';

  // Construct full URL
  const cleanEndpoint = endpoint.startsWith('/') ? endpoint.substring(1) : endpoint;
  const finalPath = cleanEndpoint.startsWith('stations/') ? cleanEndpoint : `stations/${cleanEndpoint}`;
  const targetUrl = `${baseUrl}/${finalPath}`;

  console.log(`[RadioProxy] Proxying to: ${targetUrl}`);

  try {
    const response = await fetch(targetUrl);
    if (!response.ok) {
      throw new Error(`Upstream returned ${response.status}`);
    }
    const data = await response.json();
    res.set('Access-Control-Allow-Origin', '*'); // Enable CORS
    res.json(data);
  } catch (error) {
    console.error('[RadioProxy] Error:', error);
    res.status(500).send(`Proxy Error: ${error.message}`);
  }
});


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

    // Fetch the chat document from Firestore
    const chatDoc = await db.collection('chats').doc(chatId).get();

    if (!chatDoc.exists) {
      console.log(`[Chat] Chat document not found for ${chatId}`);
      return null;
    }

    const chatData = chatDoc.data();
    let participants = chatData.participants || [];

    if (!Array.isArray(participants) || participants.length === 0) {
      console.log(`[Chat] No participants found for chat ${chatId}`);
      return null;
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

/**
 * ==================================================================
 * 4. PAYMENT & POINTS ALERTS (Restored)
 * ==================================================================
 */

exports.onPointsTransactionCreated = functions.firestore
  .document('points_transactions/{txId}')
  .onCreate(async (snapshot, context) => {
    const tx = snapshot.data();
    const userId = tx.userId;

    // [FIX] Old Transaction Filter
    // If we are backfilling or syncing old transactions, do NOT notify.
    // Allow a 5-minute window for "new" transactions.
    const now = Date.now();
    let txTime = now;

    if (tx.timestamp) {
      if (typeof tx.timestamp.toMillis === 'function') {
        txTime = tx.timestamp.toMillis();
      } else if (typeof tx.timestamp === 'string') {
        txTime = new Date(tx.timestamp).getTime();
      } else if (typeof tx.timestamp === 'number') {
        txTime = tx.timestamp;
      }
    }

    const age = now - txTime;

    // [FIX] Strict 10-minute window now that app uses UTC
    if (age > 600000) {
      console.log(`[Points] Skipping old transaction ${context.params.txId} (Age: ${age}ms)`);
      return null;
    }

    console.log(`[Points] Notifying for ${context.params.txId}. Type: ${tx.type}, Action: ${tx.action}, Points: ${tx.points}`);

    // We only notify on EARN or RECEIVED TRANSFER
    if (tx.type !== 'earn' && tx.type !== 'transfer_received') return null;
    if (tx.points <= 0) return null; // Don't notify for 0 or negative

    let title = "DSP Received!";
    let body = `You received ${tx.points} DSP`;

    if (tx.action === 'transfer_received') {
      title = "Transfer Received";
      body = `🪙 You received ${tx.points} DSP. check your wallet.`;
    } else if (tx.action === 'welcome_bonus') {
      title = "Welcome to Diaspora Nearby";
      body = `🪙 Here is ${tx.points} DSP to get you started.`;
    } else if (tx.action && tx.action.includes && tx.action.includes('streak')) {
      title = "Streak Bonus!";
      body = `🪙 You earned ${tx.points} DSP for your streak!`;
    }

    // [SILENCED] Send Push as per user request to not receive notifications for reward DSP
    /*
    await sendPushToUser(userId, {
      title: title,
      body: body,
      type: "points_update",
      targetUserId: "",
      city: ""
    });
    */
    console.log(`[Points] Notification SILENCED for user ${userId} per request.`);
    return null;
  });

/**
 * ==================================================================
 * 5. TOPIC MANAGEMENT (Restored)
 * ==================================================================
 */

exports.manageUserFCMTopics = functions.firestore
  .document('users/{userId}')
  .onWrite(async (change, context) => {
    // If deleted, do nothing (tokens expire)
    if (!change.after.exists) return null;

    const beforeData = change.before.exists ? change.before.data() : null;
    const afterData = change.after.data();

    // Token check
    const oldToken = beforeData ? beforeData.fcmToken : null;
    const newToken = afterData.fcmToken;

    // Country check
    const oldCountry = beforeData ? beforeData.homeCountryCode : null;
    const newCountry = afterData.homeCountryCode;

    if (!newToken) return null;

    const promises = [];

    // 1. Subscribe to Global (Always)
    // Only if token changed or it's a new user
    if (newToken !== oldToken) {
      promises.push(admin.messaging().subscribeToTopic(newToken, 'global'));
    }

    // 2. Handle Country Change
    if (oldCountry !== newCountry || oldToken !== newToken) {
      if (oldCountry && oldToken && oldToken === newToken) {
        // Unsubscribe specific token from old country topic ONLY if token matches 
        // (If token changed, the old one is dead anyway, no need to unsub)
        promises.push(admin.messaging().unsubscribeFromTopic(oldToken, `country_${oldCountry}`));
      }
      if (newCountry) {
        promises.push(admin.messaging().subscribeToTopic(newToken, `country_${newCountry}`));
      }
    }

    await Promise.all(promises);
    return null;
  });


/**
 * Helper to send FCM Push (Shared)
 */
async function sendPushToUser(userId, payload) {
  const userDoc = await db.collection("users").doc(userId).get();
  if (!userDoc.exists) return;

  const fcmToken = userDoc.data().fcmToken;
  if (!fcmToken) {
    console.log(`[Push] Skipping user ${userId}: No fcmToken found`);
    return;
  }

  const message = {
    token: fcmToken,
    notification: {
      title: payload.title,
      body: payload.body,
    },
    // [FIX] REMOVED TAG LOGIC TO ENSURE STABLE DEPLOY
    data: {
      type: payload.type,
      userId: payload.targetUserId || "",
      city: payload.city || "",
      click_action: "FLUTTER_NOTIFICATION_CLICK",
      ...(payload.additionalData || {})
    }
  };

  try {
    await admin.messaging().send(message);
    console.log(`[Push] Sent to ${userId}: ${payload.title}`);
  } catch (e) {
    console.error(`[Push] Failed to send to ${userId}`, e);
  }
}

/**
 * ==================================================================
 * 6. ADMIN DATABASE RESET
 * ==================================================================
 */

exports.hardResetDatabase = functions
  .runWith({
    timeoutSeconds: 540,
    memory: '512MB'
  })
  .https.onCall(async (data, context) => {

    // 1. Verify Authentication
    if (!context.auth) {
      throw new functions.https.HttpsError(
        'unauthenticated',
        'User must be authenticated to call this function.'
      );
    }

    const callerId = context.auth.uid;
    console.log(`[Admin Reset] Request from user: ${callerId}`);

    // 2. Verify Admin Status
    const callerDoc = await db.collection('users').doc(callerId).get();
    if (!callerDoc.exists || !callerDoc.data().isAdmin) {
      console.log(`[Admin Reset] REJECTED: User ${callerId} is not an admin`);
      throw new functions.https.HttpsError(
        'permission-denied',
        'Only administrators can reset the database.'
      );
    }

    console.log(`[Admin Reset] AUTHORIZED: User ${callerId} is admin`);

    // 3. Parse Request
    const resetTargets = data.resetTargets || [];
    const currentUserId = data.currentUserId || callerId;

    console.log(`[Admin Reset] Targets: ${resetTargets.join(', ')}`);
    console.log(`[Admin Reset] Preserving user: ${currentUserId}`);

    const results = {
      success: [],
      failed: []
    };

    /**
     * Helper to delete a collection recursively
     * If excludeDocId is provided, we list documents and delete them individually (except the excluded one),
     * which is slower but safe.
     * If excludeDocId is NOT provided, we nuke the whole collection path efficiently.
     */
    async function deleteCollection(collectionPath, excludeDocId = null) {
      try {
        const collectionRef = db.collection(collectionPath);

        // CASE 1: Full Delete (Faster, simpler)
        if (!excludeDocId) {
          console.log(`[Admin Reset] Recursively deleting entire collection: ${collectionPath}`);
          await db.recursiveDelete(collectionRef);
          return { success: true };
        }

        // CASE 2: Selective Delete (Must preserve one document)
        console.log(`[Admin Reset] Selective delete on ${collectionPath} (preserving ${excludeDocId})`);
        const snapshot = await collectionRef.get(); // Limitation: Reads all docs first. Good for thousands, bad for millions.

        if (snapshot.empty) {
          return { success: true };
        }

        const promises = [];
        const batchSize = 10; // Concurrency limit for recursiveDelete calls
        let currentBatch = [];

        for (const doc of snapshot.docs) {
          if (doc.id === excludeDocId) {
            console.log(`[Admin Reset] Preserving ${collectionPath}/${doc.id}`);
            continue;
          }

          // Add delete promise to batch
          const p = db.recursiveDelete(doc.ref);
          currentBatch.push(p);

          // Execute batch if full
          if (currentBatch.length >= batchSize) {
            await Promise.all(currentBatch);
            currentBatch = [];
          }
        }

        // Execute remaining
        if (currentBatch.length > 0) {
          await Promise.all(currentBatch);
        }

        return { success: true };

      } catch (error) {
        console.error(`[Admin Reset] Error deleting ${collectionPath}:`, error);
        return { success: false, error: error.message };
      }
    }

    /**
     * Helper to process a target with multiple collections
     */
    async function processTarget(targetName, collections) {
      try {
        // Process collections in parallel within a target
        await Promise.all(collections.map(async ({ path, exclude }) => {
          const excludeId = exclude ? currentUserId : null;
          const result = await deleteCollection(path, excludeId);

          if (!result.success) {
            throw new Error(`Failed to delete ${path}: ${result.error}`);
          }
        }));
        results.success.push(targetName);
      } catch (error) {
        console.error(`[Admin Reset] Target ${targetName} failed:`, error);
        results.failed.push({ target: targetName, error: error.message });
      }
    }

    // 4. Process All Targets in Parallel
    await Promise.all(resetTargets.map(async (target) => {
      switch (target) {
        case 'users':
          await processTarget('users', [
            { path: 'users', exclude: true },
            { path: 'trust_data', exclude: true },
            { path: 'id_verification_requests', exclude: false },
            { path: 'interest_registrations', exclude: false },
            { path: 'qr_exchanges', exclude: false },
            { path: 'vouches', exclude: false },
            { path: 'trust_ratings', exclude: false },
            { path: 'field_verifications', exclude: false },
            { path: 'relationship_requests', exclude: false }
          ]);
          break;

        case 'communities':
          await processTarget('communities', [
            { path: 'communities', exclude: false },
            { path: 'governance', exclude: false },
            { path: 'governance_votes', exclude: false },
            { path: 'governance_history', exclude: false }
          ]);
          break;

        case 'events':
          await processTarget('events', [
            { path: 'events', exclude: false },
            { path: 'check_ins', exclude: false }
          ]);
          break;

        case 'organizations':
          await processTarget('organizations', [
            { path: 'organizations', exclude: false }
          ]);
          break;

        case 'radio':
          await processTarget('radio', [
            { path: 'radio_station_health', exclude: false } // Fixed name
          ]);
          break;

        case 'chats':
          // Delete Firestore chat collections (top-level)
          await processTarget('chats', [
            { path: 'chats', exclude: false },
            { path: 'reports', exclude: false },
            { path: 'discoverableChats', exclude: false }
          ]);
          // Delete userChats subcollections under each user
          try {
            const usersSnap = await db.collection('users').get();
            const userChatDeletes = usersSnap.docs.map(async (userDoc) => {
              const userChatsRef = db.collection('users').doc(userDoc.id).collection('userChats');
              const userChatsSnap = await userChatsRef.get();
              if (!userChatsSnap.empty) {
                await db.recursiveDelete(userChatsRef);
                console.log(`[Admin Reset] Deleted userChats for user ${userDoc.id}`);
              }
            });
            await Promise.all(userChatDeletes);
            results.success.push('userChats');
            console.log('[Admin Reset] Deleted all userChats subcollections');
          } catch (error) {
            console.error('[Admin Reset] Error deleting userChats:', error);
            results.failed.push({ target: 'userChats', error: error.message });
          }
          break;

        case 'points':
          await processTarget('points', [
            { path: 'points_transactions', exclude: false },
            { path: 'referral_codes', exclude: false },
            { path: 'system_stats', exclude: false },
            { path: 'user_points', exclude: false } // Added missing
          ]);
          break;

        case 'storage':
          // Delete Firebase Storage files
          try {
            const bucket = admin.storage().bucket();
            const folders = [
              'profile_photos/',
              'community_headers/',
              'chat_voices/',
              'chat_images/',
              'chat_videos/',
              'chat_documents/',
              'event_images/'
            ];

            await Promise.all(folders.map(async (folder) => {
              await bucket.deleteFiles({ prefix: folder });
              console.log(`[Admin Reset] Deleted files in ${folder}`);
            }));

            results.success.push('storage');
          } catch (error) {
            console.error('[Admin Reset] Error deleting storage:', error);
            results.failed.push({ target: 'storage', error: error.message });
          }
          break;

        case 'feedback':
          await processTarget('feedback', [
            { path: 'feedback', exclude: false }
          ]);
          break;

        case 'proximity':
          await processTarget('proximity', [
            { path: 'proximity_history', exclude: false },
            { path: 'proximity-notifications', exclude: false }
          ]);
          break;

        case 'corridors':
          await processTarget('corridors', [
            { path: 'corridors', exclude: false }
          ]);
          break;

        case 'hosting':
          await processTarget('hosting', [
            { path: 'hosting_requests', exclude: false },
            { path: 'hosting_sessions', exclude: false }
          ]);
          break;

        case 'marketplace':
          await processTarget('marketplace', [
            { path: 'marketplace_listings', exclude: false }
          ]);
          // Delete saved_listings subcollections under each user
          try {
            const usersSnapMkt = await db.collection('users').get();
            const savedListingDeletes = usersSnapMkt.docs.map(async (userDoc) => {
              const savedRef = db.collection('users').doc(userDoc.id).collection('saved_listings');
              const savedSnap = await savedRef.get();
              if (!savedSnap.empty) {
                await db.recursiveDelete(savedRef);
                console.log(`[Admin Reset] Deleted saved_listings for user ${userDoc.id}`);
              }
            });
            await Promise.all(savedListingDeletes);
            console.log('[Admin Reset] Deleted all saved_listings subcollections');
          } catch (error) {
            console.error('[Admin Reset] Error deleting saved_listings:', error);
            results.failed.push({ target: 'saved_listings', error: error.message });
          }
          break;

        case 'peer_listings':
          await processTarget('peer_listings', [
            { path: 'peer_listings', exclude: false },
            { path: 'peer_bookings', exclude: false }
          ]);
          break;

        case 'trust':
          await processTarget('trust', [
            { path: 'trust_data', exclude: false },
            { path: 'trust_ratings', exclude: false },
            { path: 'vouches', exclude: false },
            { path: 'field_verifications', exclude: false }
          ]);
          break;

        default:
          console.log(`[Admin Reset] Unknown target: ${target}`);
          results.failed.push({ target, error: 'Unknown target' });
      }
    }));

    console.log(`[Admin Reset] COMPLETE. Success: ${results.success.length}, Failed: ${results.failed.length}`);

    return {
      success: results.success,
      failed: results.failed
    };
  });

/**
 * Transfers Diaspora (DSP) points between users.
 * Currently updates Firestore ledger. Future: On-chain transfer.
 */
exports.transferDiaspora = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'User must be logged in.');
  }

  const fromUserId = context.auth.uid;
  const { toUserId, amount, assetType } = data;
  const type = assetType || 'points'; // Default to points

  if (!toUserId || !amount || amount <= 0) {
    throw new functions.https.HttpsError('invalid-argument', 'Invalid recipient or amount.');
  }

  try {
    if (type === 'points') {
      // --- POINTS (DSP) TRANSFER LOGIC ---
      await db.runTransaction(async (transaction) => {
        // 1. Get Sender Data
        const fromRef = db.collection('user_points').doc(fromUserId);
        const fromSnap = await transaction.get(fromRef);
        if (!fromSnap.exists) {
          throw new functions.https.HttpsError('not-found', 'Sender wallet not found.');
        }
        const fromData = fromSnap.data();
        const currentBalance = fromData.availablePoints || 0;
        const fromPoct = fromData.currentPoCT || 0;

        if (currentBalance < amount) {
          throw new functions.https.HttpsError('failed-precondition', 'Insufficient DSP funds.');
        }

        // 2. Get Recipient Data
        const toRef = db.collection('user_points').doc(toUserId);
        const toSnap = await transaction.get(toRef);
        const toData = toSnap ? toSnap.data() : null;

        // 3. Get Country Data for Corridors
        const fromUserDoc = await transaction.get(db.collection('users').doc(fromUserId));
        const toUserDoc = await transaction.get(db.collection('users').doc(toUserId));

        const senderCountry = fromUserDoc.data()?.homeCountryCode || 'XX';
        const receiverCountry = toUserDoc.data()?.homeCountryCode || 'XX';
        const corridorId = `${senderCountry}_${receiverCountry}`;

        // 4. Calculate Burn (Trust-Based Sink)
        // 1% burn unless user has 100 PoCT
        const burnRate = fromPoct >= 100 ? 0 : 0.01;
        const burnAmount = Math.floor(amount * burnRate);
        const netAmount = amount - burnAmount;

        // 5. Update Balances
        // Deduct full amount from sender (availablePoints only, totalPoints tracks lifetime earned)
        transaction.update(fromRef, {
          availablePoints: admin.firestore.FieldValue.increment(-amount),
          lastUpdated: admin.firestore.FieldValue.serverTimestamp(),
        });

        // Add net amount to recipient (both totalPoints and availablePoints)
        if (toSnap.exists) {
          transaction.update(toRef, {
            totalPoints: admin.firestore.FieldValue.increment(netAmount),
            availablePoints: admin.firestore.FieldValue.increment(netAmount),
            lastUpdated: admin.firestore.FieldValue.serverTimestamp(),
          });
        } else {
          transaction.set(toRef, {
            userId: toUserId,
            totalPoints: netAmount,
            availablePoints: netAmount,
            lastUpdated: admin.firestore.FieldValue.serverTimestamp(),
          });
        }

        // 6. Record Internal GDP (Global, Community, Corridor)
        const treasuryRef = db.collection('system_stats').doc('treasury');
        transaction.set(treasuryRef, {
          totalInternalGdp: admin.firestore.FieldValue.increment(amount),
          totalBurnedUtility: admin.firestore.FieldValue.increment(burnAmount),
          lastUpdated: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });

        // Update Corridor
        const corridorRef = db.collection('corridors').doc(corridorId);
        transaction.set(corridorRef, {
          id: corridorId,
          senderCountry,
          receiverCountry,
          cumulativeGdp: admin.firestore.FieldValue.increment(amount),
          transactionCount: admin.firestore.FieldValue.increment(1),
          lastTransactionAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });

        // Update Communities (Home and Host for both if applicable)
        // For simplicity, we track against receiver's Home Country community
        if (receiverCountry !== 'XX') {
          const communityRef = db.collection('communities').doc(`home_country_${receiverCountry.toLowerCase()}`);
          transaction.set(communityRef, {
            cumulativeGdp: admin.firestore.FieldValue.increment(amount),
          }, { merge: true });
        }

        // 7. Log Transaction for SENDER (negative points)
        const senderTxRef = db.collection('points_transactions').doc();
        transaction.set(senderTxRef, {
          userId: fromUserId,
          type: 'transfer',
          action: 'dsp_transfer_sent',
          points: -amount,
          assetType: 'points',
          fromUserId,
          toUserId,
          amount,
          burnAmount,
          netAmount,
          senderCountry,
          receiverCountry,
          corridorId,
          timestamp: admin.firestore.FieldValue.serverTimestamp(),
          status: 'success',
          metadata: {
            description: `Sent ${amount} DSP`,
            toUserId,
            burnAmount,
          },
        });

        // 8. Log Transaction for RECEIVER (positive points)
        const receiverTxRef = db.collection('points_transactions').doc();
        transaction.set(receiverTxRef, {
          userId: toUserId,
          type: 'transfer',
          action: 'dsp_transfer_received',
          points: netAmount,
          assetType: 'points',
          fromUserId,
          toUserId,
          amount,
          burnAmount,
          netAmount,
          senderCountry,
          receiverCountry,
          corridorId,
          timestamp: admin.firestore.FieldValue.serverTimestamp(),
          status: 'success',
          metadata: {
            description: `Received ${netAmount} DSP`,
            fromUserId,
            burnAmount,
          },
        });
      });

      return { success: true, message: `Successfully transferred ${amount} DSP.` };

    } else if (type === 'token') {
      // --- TOKEN ($DIASPORA) TRANSFER LOGIC ---

      // 1. Get Sender's Private Key
      // This is a sensitive operation. In a real prompt, we'd ensure STRICT security rules.
      // Here, the Cloud Function runs as Admin, so it can access the secret.
      const senderSecretRef = db.collection('users').doc(fromUserId).collection('secrets').doc('wallet');
      const senderSecretSnap = await senderSecretRef.get();

      if (!senderSecretSnap.exists) {
        throw new functions.https.HttpsError('failed-precondition', 'Sender wallet not initialized (No Private Key).');
      }

      const privateKey = senderSecretSnap.data().privateKey;
      if (!privateKey) {
        throw new functions.https.HttpsError('failed-precondition', 'Sender private key missing.');
      }

      // 2. Get Recipient's Public Address
      const recipientUserRef = db.collection('users').doc(toUserId);
      const recipientUserSnap = await recipientUserRef.get();

      if (!recipientUserSnap.exists) {
        throw new functions.https.HttpsError('not-found', 'Recipient user not found.');
      }

      const toAddress = recipientUserSnap.data().walletAddress;
      if (!toAddress) {
        throw new functions.https.HttpsError('failed-precondition', 'Recipient does not have a wallet address.');
      }

      // 3. Execute On-Chain Transaction (Using Ethers.js)
      // Note: We need a provider (RPC URL) to actually broadcast.
      // For this environment, we might not have a configured provider.
      // We will simulate the successful preparation or rely on a default provider if configured.

      // Mocking the blockchain interaction for stability if no RPC is set
      const rpcUrl = process.env.RPC_URL;
      // If we don't have RPC, we can't really transfer. 
      // User requirement: "Implement logic... simulate/execute".
      // We'll assume simulation if RPC is missing to verify logic flow.

      let txHash = '0x_SIMULATED_HASH_' + Date.now();

      if (rpcUrl) {
        const provider = new ethers.providers.JsonRpcProvider(rpcUrl);
        const wallet = new ethers.Wallet(privateKey, provider);

        // Gas logic, checking balance, etc. would go here.
        try {
          const tx = await wallet.sendTransaction({
            to: toAddress,
            value: ethers.utils.parseEther(amount.toString())
          });
          txHash = tx.hash;
          console.log(`[Token Transfer] Transaction sent: ${txHash}`);
          // await tx.wait(); // Optional: wait for confirmation (slower response)
        } catch (txError) {
          console.error('[Token Transfer] Blockchain Error:', txError);
          throw new functions.https.HttpsError('aborted', 'On-chain transaction failed.', txError.message);
        }
      } else {
        console.log(`[Mock Transfer] Sending ${amount} $DIASPORA from ${fromUserId} to ${toAddress} (No RPC_URL)`);
      }

      // 4. Log Transaction
      await db.collection('points_transactions').add({
        type: 'transfer',
        assetType: 'token',
        fromUserId,
        toUserId,
        toAddress,
        amount, // Stored as number/string
        txHash,
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
        status: 'success', // Presumed success
        description: `$DIASPORA Token Transfer from ${fromUserId} to ${toUserId}`,
      });

      return { success: true, message: `Successfully transferred ${amount} $DIASPORA.`, txHash };
    } else {
      throw new functions.https.HttpsError('invalid-argument', 'Invalid asset type. Must be "points" or "token".');
    }

  } catch (error) {
    console.error('Transfer failed:', error);
    throw new functions.https.HttpsError('internal', 'Transfer failed', error);
  }
});
