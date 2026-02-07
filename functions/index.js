const functions = require("firebase-functions");
const admin = require("firebase-admin");

admin.initializeApp();
const db = admin.firestore();

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
 * 3. CHAT NOTIFICATIONS (Restored)
 * ==================================================================
 */

exports.onDirectMessageCreated = functions.database
  .ref('/chats/{chatId}/messages/{messageId}')
  .onCreate(async (snapshot, context) => {
    const message = snapshot.val();
    const chatId = context.params.chatId;
    const senderId = message.senderId;

    // We need to find who to notify.
    // In many schemas, 'participants' is stored at /chats/{chatId}/participants
    const chatRef = admin.database().ref(`/chats/${chatId}`);
    const chatSnapshot = await chatRef.once('value');
    const chatData = chatSnapshot.val();

    if (!chatData || !chatData.participants) {
      console.log(`[Chat] No participants found for chat ${chatId}`);
      return null;
    }

    let participants = [];
    if (Array.isArray(chatData.participants)) {
      participants = chatData.participants; // List of IDs
    } else if (typeof chatData.participants === 'object') {
      participants = Object.keys(chatData.participants); // Map of IDs
    }

    // [FIX] STRICT SENDER FILTERING & DEDUPLICATION
    let recipients = participants.filter(uid => String(uid) !== String(senderId));
    recipients = [...new Set(recipients)]; // Deduplicate to ensure 1 notification per user

    // [REMOVED] Skip DSP Transfer (Now handled here to ensure recipient gets notified if points are silenced)
    // This previously caused SILENCE for recipient because Points notifications were muted in app.

    console.log(`[Chat] MsgID: ${context.params.messageId} | Sender: ${senderId} | Recipients: ${recipients.join(', ')}`);

    const promises = recipients.map(async (recipientId) => {
      // 1. Identify context
      const isCommunity = chatData.type === 'community' || chatId.startsWith('chat_');
      const isDirect = chatData.type === 'direct';
      const mentions = Array.isArray(message.mentions) ? message.mentions : [];
      const isMentioned = mentions.includes(recipientId);

      // 2. Check Mute Status
      const muteSnapshot = await admin.database()
        .ref(`/userChats/${recipientId}/${chatId}/muted`)
        .once('value');
      const isManuallyMuted = muteSnapshot.val() === true;

      // 3. Routing Logic
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
      // dsp_transfer skipped above

      // [FIX] Ensure we don't crash if body is empty
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

exports.hardResetDatabase = functions.https.onCall(async (data, context) => {
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
      for (const { path, exclude } of collections) {
        const excludeId = exclude ? currentUserId : null;
        const result = await deleteCollection(path, excludeId);

        if (!result.success) {
          throw new Error(`Failed to delete ${path}: ${result.error}`);
        }
      }
      results.success.push(targetName);
    } catch (error) {
      console.error(`[Admin Reset] Target ${targetName} failed:`, error);
      results.failed.push({ target: targetName, error: error.message });
    }
  }

  // 4. Process Each Target
  for (const target of resetTargets) {
    switch (target) {
      case 'users':
        await processTarget('users', [
          { path: 'users', exclude: true },
          { path: 'trust_data', exclude: true },
          { path: 'id_verification_requests', exclude: false }, // Added missing
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
          { path: 'radio_stations', exclude: false }
        ]);
        break;

      case 'chats':
        // Delete Firestore collections
        await processTarget('chats', [
          { path: 'chats', exclude: false },
          { path: 'reports', exclude: false }
        ]);
        // Delete RTDB paths
        try {
          await admin.database().ref('chats').remove();
          await admin.database().ref('userChats').remove();
          console.log('[Admin Reset] Deleted RTDB paths: chats, userChats');
        } catch (error) {
          console.error('[Admin Reset] Error deleting RTDB paths:', error);
          throw error;
        }
        break;

      case 'points':
        await processTarget('points', [
          { path: 'points_transactions', exclude: false },
          { path: 'referral_codes', exclude: false },
          { path: 'system_stats', exclude: false }
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
            'event_images/'
          ];

          for (const folder of folders) {
            // Delete files in folder with prefix
            // Note: bucket.deleteFiles() handles prefixes
            await bucket.deleteFiles({ prefix: folder });
            console.log(`[Admin Reset] Deleted files in ${folder}`);
          }

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

      default:
        console.log(`[Admin Reset] Unknown target: ${target}`);
        results.failed.push({ target, error: 'Unknown target' });
    }
  }

  console.log(`[Admin Reset] COMPLETE. Success: ${results.success.length}, Failed: ${results.failed.length}`);

  return {
    success: results.success,
    failed: results.failed
  };
});
