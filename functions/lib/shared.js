/**
 * Shared utilities for Cloud Functions modules.
 * Provides admin SDK, Firestore DB, and shared helpers.
 */
const functions = require("firebase-functions");
const admin = require("firebase-admin");

// Admin SDK is initialized by index.js before any module is loaded.
// This module only provides convenience references.
const db = admin.firestore();

/**
 * Helper to send FCM Push notification to a user.
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
        data: {
            type: payload.type,
            userId: payload.targetUserId || "",
            city: payload.city || "",
            click_action: "FLUTTER_NOTIFICATION_CLICK",
            ...(payload.additionalData || {}),
        },
    };

    try {
        await admin.messaging().send(message);
        console.log(`[Push] Sent to ${userId}: ${payload.title}`);
    } catch (e) {
        console.error(`[Push] Failed to send to ${userId}`, e);
    }
}

module.exports = { functions, admin, db, sendPushToUser };
