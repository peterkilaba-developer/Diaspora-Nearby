/**
 * Shared utilities for Cloud Functions modules.
 * Provides admin SDK, Firestore DB, and shared helpers.
 */
// v1 API pinned explicitly: since firebase-functions v6 the bare
// "firebase-functions" entry point serves the v2 API. All functions in
// this codebase are 1st-gen; /v1 keeps their API and deployed identity
// unchanged.
const functions = require("firebase-functions/v1");
const admin = require("firebase-admin");

// Admin SDK is initialized by index.js before any module is loaded.
// This module only provides convenience references.
const db = admin.firestore();

/**
 * Helper to send FCM Push notification to a user.
 */
async function sendPushToUser(userId, payload) {
    const userDoc = await db.collection("user_private").doc(userId).get();
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

    // Optional Android grouping/collapse so repeated alerts of the same type
    // stack in the tray instead of flooding it.
    if (payload.androidCollapseKey || payload.androidTag) {
        message.android = {
            collapseKey: payload.androidCollapseKey,
            notification: {
                channelId: "high_importance_channel",
                ...(payload.androidTag ? { tag: payload.androidTag } : {}),
            },
        };
    }
    if (payload.apnsThreadId || payload.apnsCollapseId) {
        let safeCollapseId = payload.apnsCollapseId ? String(payload.apnsCollapseId) : "";
        if (safeCollapseId && Buffer.byteLength(safeCollapseId, "utf8") > 64) {
            const crypto = require("crypto");
            safeCollapseId = crypto.createHash("sha256").update(safeCollapseId).digest("hex").slice(0, 64);
        }
        message.apns = {
            ...(safeCollapseId ? {
                headers: { "apns-collapse-id": safeCollapseId },
            } : {}),
            payload: {
                aps: {
                    ...(payload.apnsThreadId ? { "thread-id": payload.apnsThreadId } : {}),
                },
            },
        };
    }

    try {
        await admin.messaging().send(message);
        console.log(`[Push] Sent to ${userId}: ${payload.title}`);
    } catch (e) {
        console.error(`[Push] Failed to send to ${userId}`, e);
    }
}

module.exports = { functions, admin, db, sendPushToUser };
