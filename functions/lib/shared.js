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

const crypto = require("crypto");

/** FCM error codes that mean the stored registration token is permanently dead. */
const DEAD_TOKEN_CODES = new Set([
    "messaging/registration-token-not-registered",
    "messaging/invalid-registration-token",
]);

const MAX_TITLE_LENGTH = 120;
const MAX_BODY_LENGTH = 600;

function truncate(value, max) {
    const text = String(value == null ? "" : value);
    return text.length > max ? `${text.slice(0, max - 1)}…` : text;
}

/**
 * FCM requires every `data` value to be a string. Coerce, drop empties, and
 * JSON-encode objects so a stray number/boolean never makes the send throw.
 */
function stringifyData(data) {
    const out = {};
    for (const [key, value] of Object.entries(data || {})) {
        if (value === undefined || value === null) continue;
        out[key] = typeof value === "string" ? value :
            (typeof value === "object" ? JSON.stringify(value) : String(value));
    }
    return out;
}

function safeApnsCollapseId(value) {
    let id = value ? String(value) : "";
    if (id && Buffer.byteLength(id, "utf8") > 64) {
        id = crypto.createHash("sha256").update(id).digest("hex").slice(0, 64);
    }
    return id;
}

/**
 * Builds a fully-specified FCM message. Every push gets:
 *  - the high-importance Android channel + default sound (heads-up display),
 *  - an APNs `sound` so iOS banners are not delivered silently,
 *  - optional per-thread grouping / collapse keys.
 */
function buildMessage(target, payload) {
    const data = stringifyData({
        type: payload.type,
        userId: payload.targetUserId || "",
        city: payload.city || "",
        click_action: "FLUTTER_NOTIFICATION_CLICK",
        ...(payload.additionalData || {}),
    });
    const apnsCollapseId = safeApnsCollapseId(payload.apnsCollapseId);
    return {
        ...target,
        notification: {
            title: truncate(payload.title, MAX_TITLE_LENGTH),
            body: truncate(payload.body, MAX_BODY_LENGTH),
        },
        data,
        android: {
            priority: "high",
            ...(payload.androidCollapseKey ? { collapseKey: String(payload.androidCollapseKey) } : {}),
            notification: {
                channelId: "high_importance_channel",
                sound: "default",
                ...(payload.androidTag ? { tag: String(payload.androidTag) } : {}),
            },
        },
        apns: {
            ...(apnsCollapseId ? { headers: { "apns-collapse-id": apnsCollapseId } } : {}),
            payload: {
                aps: {
                    sound: "default",
                    ...(payload.apnsThreadId ? { "thread-id": String(payload.apnsThreadId) } : {}),
                },
            },
        },
    };
}

/**
 * Clears a dead registration token so we stop paying for failed sends. The
 * `fcmTokenRevoked` marker tells manageUserFCMTopics' self-heal not to restore it.
 * Only clears if the stored token is still the one that failed.
 */
async function clearDeadToken(userId, token) {
    try {
        const ref = db.collection("user_private").doc(userId);
        await db.runTransaction(async (transaction) => {
            const snap = await transaction.get(ref);
            if (!snap.exists || snap.data().fcmToken !== token) return;
            transaction.set(ref, {
                fcmToken: admin.firestore.FieldValue.delete(),
                fcmTokenRevoked: true,
                fcmTokenRevokedReason: "unregistered",
                fcmTokenUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
            }, { merge: true });
        });
        console.log(`[Push] Cleared dead FCM token for ${userId}`);
    } catch (e) {
        console.warn(`[Push] Could not clear dead token for ${userId}: ${e.message}`);
    }
}

function pushTargetFromPrivate(data) {
    if (!data) return null;
    if (data.notificationsEnabled === false) return null;
    const token = typeof data.fcmToken === "string" ? data.fcmToken.trim() : "";
    return token || null;
}

/**
 * Helper to send FCM Push notification to a user.
 * Respects `notificationsEnabled === false` and prunes dead tokens.
 * Resolves to true when FCM accepted the message.
 */
async function sendPushToUser(userId, payload) {
    if (typeof userId !== "string" || !userId) return false;
    const userDoc = await db.collection("user_private").doc(userId).get();
    if (!userDoc.exists) return false;

    const fcmToken = pushTargetFromPrivate(userDoc.data());
    if (!fcmToken) {
        console.log(`[Push] Skipping user ${userId}: no token or notifications disabled`);
        return false;
    }

    try {
        await admin.messaging().send(buildMessage({ token: fcmToken }, payload));
        console.log(`[Push] Sent to ${userId}: ${payload.title}`);
        return true;
    } catch (e) {
        const code = e && (e.code || (e.errorInfo && e.errorInfo.code));
        if (DEAD_TOKEN_CODES.has(code)) {
            await clearDeadToken(userId, fcmToken);
        } else {
            console.error(`[Push] Failed to send to ${userId}`, e);
        }
        return false;
    }
}

/** Sends one push to an FCM topic (e.g. `city_lagos`). */
async function sendPushToTopic(topic, payload) {
    const safeTopic = String(topic || "").replace(/[^a-zA-Z0-9-_.~%]/g, "");
    if (!safeTopic) return false;
    try {
        await admin.messaging().send(buildMessage({ topic: safeTopic }, payload));
        console.log(`[Push] Sent to topic ${safeTopic}: ${payload.title}`);
        return true;
    } catch (e) {
        console.error(`[Push] Failed to send to topic ${safeTopic}`, e);
        return false;
    }
}

function notificationDocId(dedupKey) {
    return crypto.createHash("sha256").update(String(dedupKey)).digest("hex").slice(0, 40);
}

function buildInAppDoc(payload) {
    const inApp = payload.inApp || {};
    const route = payload.route || inApp.route || "";
    return {
        type: inApp.type || "system",
        title: truncate(payload.title, MAX_TITLE_LENGTH),
        body: truncate(payload.body, MAX_BODY_LENGTH),
        payload: {
            ...stringifyData(inApp.payload || payload.additionalData || {}),
            ...(route ? { route } : {}),
            ...(payload.dedupKey ? { dedupKey: String(payload.dedupKey) } : {}),
        },
        isRead: false,
        actionRequired: inApp.actionRequired === true,
        actionCompleted: false,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
    };
}

/**
 * Engagement notification: persists an entry in the in-app Notifications hub
 * (`users/{uid}/notifications`) AND sends a push. Idempotent per `dedupKey`, so
 * a retried Cloud Function trigger never double-notifies.
 *
 * payload: { title, body, type, targetUserId?, additionalData?, route?,
 *            dedupKey?, inApp?: { type, actionRequired?, payload? } | false,
 *            ...push grouping options }
 */
async function notifyUser(userId, payload) {
    if (typeof userId !== "string" || !userId || userId === "system") return false;
    const additionalData = {
        ...(payload.additionalData || {}),
        ...(payload.route ? { route: payload.route } : {}),
        ...(payload.dedupKey ? { id: String(payload.dedupKey) } : {}),
    };

    if (payload.dedupKey) {
        // Claim the dedup slot first; if it already exists this event was handled.
        const ref = db.collection("users").doc(userId)
            .collection("notifications").doc(notificationDocId(payload.dedupKey));
        try {
            if (payload.inApp === false) {
                await db.collection("notification_dedup").doc(
                    notificationDocId(`${userId}:${payload.dedupKey}`),
                ).create({ userId, dedupKey: String(payload.dedupKey),
                    createdAt: admin.firestore.FieldValue.serverTimestamp() });
            } else {
                await ref.create(buildInAppDoc(payload));
            }
        } catch (e) {
            if (e && (e.code === 6 || e.code === "already-exists")) {
                console.log(`[Notify] Duplicate ${payload.dedupKey} for ${userId}, skipped`);
                return false;
            }
            console.warn(`[Notify] In-app persist failed for ${userId}: ${e.message}`);
        }
    } else if (payload.inApp !== false) {
        await db.collection("users").doc(userId).collection("notifications")
            .add(buildInAppDoc(payload))
            .catch((e) => console.warn(`[Notify] In-app persist failed for ${userId}: ${e.message}`));
    }

    return sendPushToUser(userId, { ...payload, additionalData });
}

/**
 * Fan-out of the same notification to many users (community broadcasts).
 * `buildPayload(userId)` may return null to skip a recipient.
 */
async function notifyUsers(userIds, buildPayload, { max = 500, concurrency = 25 } = {}) {
    const unique = [...new Set((userIds || []).filter((id) => typeof id === "string" && id))]
        .slice(0, max);
    let sent = 0;
    for (let i = 0; i < unique.length; i += concurrency) {
        const chunk = unique.slice(i, i + concurrency);
        const results = await Promise.all(chunk.map(async (uid) => {
            const payload = typeof buildPayload === "function" ? buildPayload(uid) : buildPayload;
            if (!payload) return false;
            try {
                return await notifyUser(uid, payload);
            } catch (e) {
                console.warn(`[Notify] Fan-out failed for ${uid}: ${e.message}`);
                return false;
            }
        }));
        sent += results.filter(Boolean).length;
    }
    return sent;
}

module.exports = {
    functions,
    admin,
    db,
    sendPushToUser,
    sendPushToTopic,
    notifyUser,
    notifyUsers,
    buildMessage,
    stringifyData,
};
