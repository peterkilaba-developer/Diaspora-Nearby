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
    if (tx.type !== 'earn' && tx.type !== 'transfer_received' && tx.action !== 'token_transfer_received') return null;
    if (tx.points <= 0) return null; // Don't notify for 0 or negative

    let title = "DSP Received!";
    let body = `You received ${tx.points} DSP`;

    if (tx.action === 'token_transfer_received') {
      title = "$DIASPORA Received";
      body = `🪙 You received ${tx.points} $DIASPORA in your wallet.`;
      await sendPushToUser(userId, {
        title: title,
        body: body,
        type: "points_update",
        targetUserId: tx.fromUserId || "",
        city: ""
      });
      return null;
    } else if (tx.action === 'transfer_received') {
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
    let newToken = afterData.fcmToken;

    // [SELF-HEAL] If a client profile save (saveUserProfile / updateProfileData)
    // accidentally serialized `fcmToken: null` into user_private/{userId} while
    // notifications were NOT explicitly disabled (notificationsEnabled !== false),
    // restore the previous valid fcmToken immediately so push notifications keep working.
    // Intentional removals (sign-out, dead-token pruning, token moved to another
    // account) set `fcmTokenRevoked: true` and must NOT be restored.
    if (!newToken && oldToken && afterData.notificationsEnabled !== false &&
        afterData.fcmTokenRevoked !== true) {
      console.log(`[FCM] Restoring accidentally nulled fcmToken for user ${context.params.userId}`);
      await change.after.ref.set({
        fcmToken: oldToken,
        notificationsEnabled: beforeData.notificationsEnabled !== false,
      }, { merge: true });
      newToken = oldToken;
    }

    if (!newToken) return null;

    // [SINGLE OWNER] A device token belongs to whoever is signed in on that
    // device right now. If another account still holds this token (shared
    // device / account switch), detach it there so that account's private
    // pushes (DMs, requests) are never shown to the current user.
    if (newToken !== oldToken) {
      try {
        const holders = await db.collection('user_private')
          .where('fcmToken', '==', newToken)
          .limit(10)
          .get();
        await Promise.all(holders.docs
          .filter((doc) => doc.id !== context.params.userId)
          .map((doc) => {
            console.log(`[FCM] Detaching shared device token from previous account ${doc.id}`);
            return doc.ref.set({
              fcmToken: admin.firestore.FieldValue.delete(),
              fcmTokenRevoked: true,
              fcmTokenRevokedReason: 'claimed_by_other_account',
              fcmTokenUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
            }, { merge: true });
          }));
      } catch (e) {
        console.warn(`[FCM] Shared-token cleanup failed: ${e.message}`);
      }
    }

    // Country check
    const profile = await db.collection('users').doc(context.params.userId).get();
    const newCountry = profile.exists && profile.data().homeCountryCode ?
      String(profile.data().homeCountryCode).toLowerCase() : null;
    const subscribedToken = afterData.fcmServerTopicsToken || null;
    const subscribedCountry = afterData.fcmServerCountryTopic || null;

    // Nothing changed since the last server-side subscription → no API calls.
    if (subscribedToken === newToken && subscribedCountry === newCountry) return null;

    const promises = [];

    // 1. Subscribe to Global (Always) when the token is new to us.
    if (subscribedToken !== newToken) {
      promises.push(admin.messaging().subscribeToTopic(newToken, 'global'));
    }

    // 2. Handle Country Change
    if (subscribedCountry && subscribedCountry !== newCountry && subscribedToken === newToken) {
      promises.push(admin.messaging().unsubscribeFromTopic(newToken, `country_${subscribedCountry}`));
    }
    if (newCountry) {
      promises.push(admin.messaging().subscribeToTopic(newToken, `country_${newCountry}`));
    }

    try {
      await Promise.all(promises);
      // Record what we subscribed so subsequent unrelated writes are no-ops.
      await change.after.ref.set({
        fcmServerTopicsToken: newToken,
        fcmServerCountryTopic: newCountry,
      }, { merge: true });
    } catch (e) {
      console.warn(`[FCM] Topic subscription failed for ${context.params.userId}: ${e.message}`);
    }
    return null;
  });
