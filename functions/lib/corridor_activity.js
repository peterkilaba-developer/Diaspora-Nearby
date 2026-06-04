/**
 * Corridor Activity module — the unified write path for any economic
 * activity that crosses a diaspora corridor.
 *
 * Every commerce-touching feature (DSP transfers, marketplace sales,
 * hosting payments, flight bookings, B2B fiat, etc.) calls into
 * `recordCorridorActivity` so the chamber doc for that (home, host)
 * pair becomes the single source of truth for bilateral GDP.
 *
 * Chambers are organizations of kind `corridor_chamber` with id
 *   chamber_<host>_<home>   (host first, see organization_repository.dart)
 *
 * This module intentionally has no Firestore-trigger exports — it is a
 * library called by other Cloud Functions inside the admin SDK process.
 */
const { admin, db } = require("./shared");

/**
 * Records one economic event against the chamber for the (home, host)
 * country pair. Idempotently ensures the chamber doc exists.
 *
 * @param {object} args
 * @param {string} args.homeCountryCode    ISO code of the diaspora's home country
 * @param {string} args.hostCountryCode    ISO code of the country the activity happens in
 * @param {number} args.amountUsd          USD value of the economic activity
 * @param {string} args.activityType       'dsp_transfer' | 'marketplace' | 'hosting'
 *                                          | 'booking' | 'fiat_b2b' | etc.
 * @param {string} [args.direction]        'hostToHome' | 'homeToHost' | 'hostInternal'.
 *                                          When omitted, no direction split is recorded
 *                                          (still counts toward gdpTotal).
 * @param {string} [args.actorUid]         For audit trail.
 * @param {object} [args.metadata]         Free-form context (txId, listingId, etc.)
 * @returns {Promise<{chamberId: string|null, recorded: boolean}>}
 *
 * Returns `{ recorded: false, chamberId: null }` when the activity has no
 * meaningful corridor (missing codes, same-country, or invalid amount).
 * Callers should treat that as a no-op, not an error.
 */
const VALID_DIRECTIONS = new Set([
    "hostToHome",  // host → home (classic remittance: TZ-in-US sending DSP to TZ)
    "homeToHost",  // home → host (origin economy paying diaspora abroad)
    "hostInternal", // both parties in host country (diaspora-to-diaspora)
]);

async function recordCorridorActivity({
    homeCountryCode,
    hostCountryCode,
    amountUsd,
    activityType,
    direction = null,
    actorUid = null,
    metadata = {},
}) {
    if (!homeCountryCode || !hostCountryCode) {
        return { chamberId: null, recorded: false };
    }
    const home = String(homeCountryCode).toUpperCase();
    const host = String(hostCountryCode).toUpperCase();
    if (home === host) return { chamberId: null, recorded: false };
    if (typeof amountUsd !== "number" || amountUsd <= 0) {
        return { chamberId: null, recorded: false };
    }
    if (!activityType || typeof activityType !== "string") {
        return { chamberId: null, recorded: false };
    }
    const dir = direction && VALID_DIRECTIONS.has(direction) ? direction : null;

    const chamberId = `chamber_${host.toLowerCase()}_${home.toLowerCase()}`;
    const chatId = `org_${chamberId}`;
    const chamberRef = db.collection("organizations").doc(chamberId);

    // Atomic: if the chamber doesn't exist yet (no member has signed up
    // in this corridor), bootstrap a minimal-but-complete doc so the
    // increments below have a target. The full opt-in setup will fill in
    // any missing fields the next time `ensureCorridorChamber` is called
    // from a client signup.
    await db.runTransaction(async (tx) => {
        const snap = await tx.get(chamberRef);
        const now = admin.firestore.FieldValue.serverTimestamp();

        if (!snap.exists) {
            const name = `${host} ⇄ ${home} Chamber of Commerce`;
            const nowMillis = Date.now();
            tx.set(chamberRef, {
                id: chamberId,
                kind: "corridor_chamber",
                name,
                businessName: name,
                description: `Official public corridor chamber — ${host} (host) ↔ ${home} (home) diaspora.`,
                type: "Chamber of Commerce",
                phone: "",
                website: "",
                profileImage: null,
                superAdminId: null,
                admins: [],
                pendingAdmins: [],
                adminTitles: {},
                members: [],
                followers: [],
                memberCount: 0,
                linkedBusinesses: [],
                memberBusinessCount: 0,
                isPublic: true,
                country: host,
                homeCountryCode: home,
                hostCountryCode: host,
                communityId: null,
                richData: null,
                chatId,
                status: "active",
                gdpTotal: amountUsd,
                gdpByActivityType: { [activityType]: amountUsd },
                gdpByDirection: dir
                    ? { [dir]: amountUsd }
                    : {},
                transactionCount: 1,
                lastTransactionAt: now,
                createdAt: now,
                updatedAt: now,
            });
            tx.set(db.collection("chats").doc(chatId), {
                id: chatId,
                type: "organization",
                subtype: "corridor_chamber",
                name,
                participants: [],
                admins: [],
                homeCountryCode: home,
                hostCountryCode: host,
                createdAt: nowMillis,
                updatedAt: nowMillis,
                createdBy: "system",
                lastMessage: {
                    content: "Chamber of Commerce opened",
                    timestamp: nowMillis,
                    type: "system",
                    senderId: "system",
                    senderName: "System",
                },
            });
        } else {
            const update = {
                gdpTotal: admin.firestore.FieldValue.increment(amountUsd),
                [`gdpByActivityType.${activityType}`]:
                    admin.firestore.FieldValue.increment(amountUsd),
                transactionCount:
                    admin.firestore.FieldValue.increment(1),
                lastTransactionAt: now,
                updatedAt: now,
            };
            if (dir) {
                update[`gdpByDirection.${dir}`] =
                    admin.firestore.FieldValue.increment(amountUsd);
            }
            tx.update(chamberRef, update);
        }
    });

    // Audit trail row. Reuses the existing `gdp_transactions` collection
    // so the platform-wide GDP audit log stays in one place. Adding
    // `chamberOrgId` lets us query "show me every event that touched this
    // chamber" trivially.
    try {
        await db.collection("gdp_transactions").add({
            chamberOrgId: chamberId,
            homeCountryCode: home,
            hostCountryCode: host,
            amountUsd,
            activityType,
            direction: dir,
            actorUid,
            metadata: metadata || {},
            timestamp: admin.firestore.FieldValue.serverTimestamp(),
        });
    } catch (e) {
        // Audit log failure must not break the primary write.
        console.error(
            `[corridor-activity] audit write failed for ${chamberId}: ${e.message}`
        );
    }

    return { chamberId, recorded: true };
}

module.exports = { recordCorridorActivity };
