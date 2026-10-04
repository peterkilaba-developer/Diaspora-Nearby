/**
 * Points Transaction Notifications & FCM Topic Management.
 */
const { functions, admin, db, sendPushToUser } = require("./shared");

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
  .document('user_private/{userId}')
  .onWrite(async (change, context) => {
    // If deleted, do nothing (tokens expire)
    if (!change.after.exists) return null;

    const beforeData = change.before.exists ? change.before.data() : null;
    const afterData = change.after.data();

    // Token check
    const oldToken = beforeData ? beforeData.fcmToken : null;
    const newToken = afterData.fcmToken;

    // Country check
    const profile = await db.collection('users').doc(context.params.userId).get();
    const oldCountry = null;
    const newCountry = profile.exists ? profile.data().homeCountryCode : null;

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


