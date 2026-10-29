/**
 * Chamber Leadership module.
 *
 * Watches `leadershipRequests/{id}` for `approved: false → true` transitions.
 * When an admin flips the flag (via the CLI, Firebase console, or a future
 * admin UI), this trigger performs the appointment server-side: writes
 * `councilRoles`, `adminTitles`, and `admins` on the chamber org, mirrors
 * moderation rights into the chamber chat, and stamps the request as
 * `status: 'approved'`.
 *
 * Validation (membership, nationality pins, replacing prior seat-holder) is
 * duplicated here from the Dart client method so that a direct console flip
 * stays safe even when the client never ran the pre-flight checks.
 */
const { functions, admin, db, sendPushToUser } = require("./shared");

// Keep this in sync with lib/features/organization/models/chamber_roles.dart
const ROLES = {
    president: { display: "President", homePin: false, hostPin: false },
    vice_president: { display: "Vice President", homePin: false, hostPin: false },
    treasurer: { display: "Treasurer", homePin: false, hostPin: false },
    secretary: { display: "Secretary", homePin: false, hostPin: false },
    home_trade_rep: { display: "Home Trade Rep", homePin: true, hostPin: false },
    host_trade_rep: { display: "Host Trade Rep", homePin: false, hostPin: true },
};

function upper(s) {
    return (s || "").toUpperCase();
}

async function performAppointment({ chamberId, userId, role }) {
    const def = ROLES[role];
    if (!def) throw new Error(`Unknown chamber role "${role}"`);

    const [userSnap, privateUserSnap] = await Promise.all([
        db.collection("users").doc(userId).get(),
        db.collection("user_private").doc(userId).get(),
    ]);
    if (!userSnap.exists) throw new Error(`User ${userId} not found`);
    const user = userSnap.data() || {};
    const privateUser = privateUserSnap.exists ? privateUserSnap.data() : {};
    const userHome = upper(user.homeCountryCode);
    const userHost = upper(user.hostCountryCode);
    const pastCountryCodes = new Set(
        (privateUser.pastLocations || [])
            .map((p) => p && p.location && p.location.countryCode)
            .filter(Boolean)
            .map(upper)
    );

    const orgRef = db.collection("organizations").doc(chamberId);

    return db.runTransaction(async (tx) => {
        const snap = await tx.get(orgRef);
        if (!snap.exists) throw new Error(`Chamber ${chamberId} not found`);
        const data = snap.data();
        if (data.kind !== "corridor_chamber") {
            throw new Error(
                `Not a corridor_chamber org (kind="${data.kind}")`
            );
        }

        const chamberHome = upper(data.homeCountryCode);
        const chamberHost = upper(data.hostCountryCode);

        if (def.homePin && userHome !== chamberHome) {
            throw new Error(
                `Home-pinned role requires home country ${chamberHome}, user has ${userHome}`
            );
        }
        if (def.hostPin) {
            const livesInHost = userHost === chamberHost;
            const livedInHost = pastCountryCodes.has(chamberHost);
            if (!livesInHost && !livedInHost) {
                throw new Error(
                    `Host-pinned role requires lived experience in ${chamberHost}`
                );
            }
        }

        const members = Array.isArray(data.members) ? data.members : [];
        if (!members.includes(userId)) {
            throw new Error(`User ${userId} is not a chamber member`);
        }

        const councilRoles = Object.assign({}, data.councilRoles || {});
        const adminTitles = Object.assign({}, data.adminTitles || {});

        // Replace any prior holder of this single-occupant seat.
        for (const [otherUid, otherRole] of Object.entries(councilRoles)) {
            if (otherUid !== userId && otherRole === role) {
                delete councilRoles[otherUid];
                delete adminTitles[otherUid];
            }
        }

        councilRoles[userId] = role;
        adminTitles[userId] = def.display;

        const admins = Array.isArray(data.admins) ? [...data.admins] : [];
        if (!admins.includes(userId)) admins.push(userId);

        tx.update(orgRef, {
            councilRoles,
            adminTitles,
            admins,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });

        const chatId = data.chatId;
        if (chatId) {
            tx.update(db.collection("chats").doc(chatId), {
                admins: admin.firestore.FieldValue.arrayUnion(userId),
                updatedAt: Date.now(),
            });
        }
    });
}

/**
 * Trigger: a leadership request was created or modified. We only act when
 * `approved` flips from false → true. Everything else is a no-op.
 */
// Lightweight cache to avoid re-fetching the chamber name on every push.
const chamberNameCache = new Map();
async function getChamberName(chamberId) {
    if (chamberNameCache.has(chamberId)) return chamberNameCache.get(chamberId);
    try {
        const snap = await db.collection("organizations").doc(chamberId).get();
        const name = snap.exists ? snap.data().name || chamberId : chamberId;
        chamberNameCache.set(chamberId, name);
        return name;
    } catch (_) {
        return chamberId;
    }
}

exports.onChamberLeadershipRequestApproved = functions.firestore
    .document("leadershipRequests/{requestId}")
    .onUpdate(async (change, context) => {
        const before = change.before.data() || {};
        const after = change.after.data() || {};

        // Detect the two state transitions we care about:
        //   1. approved flipped false → true  → perform appointment + notify
        //   2. status flipped pending → rejected (without approved=true) → notify rejection
        const approveTransition =
            before.approved !== true && after.approved === true;
        const rejectTransition =
            before.status === "pending" && after.status === "rejected";

        if (!approveTransition && !rejectTransition) return null;
        // If both flipped at once (shouldn't happen), favor the approve path.

        const { requestId } = context.params;
        const { chamberId, userId, role } = after;

        if (!chamberId || !userId || !role) {
            console.error(
                `[chamber-leadership] Request ${requestId} missing required fields:`,
                { chamberId, userId, role }
            );
            await change.after.ref.update({
                status: "rejected",
                approved: false,
                decisionNote: "Malformed request: missing fields.",
                decidedAt: admin.firestore.FieldValue.serverTimestamp(),
            });
            return null;
        }

        const roleDisplay = (ROLES[role] && ROLES[role].display) || role;

        if (approveTransition) {
            // Defensive: don't re-process an already-finalized request.
            if (after.status === "approved") return null;
            try {
                await performAppointment({ chamberId, userId, role });
                const [, chamberName] = await Promise.all([
                    change.after.ref.update({
                        status: "approved",
                        decidedAt: admin.firestore.FieldValue.serverTimestamp(),
                    }),
                    getChamberName(chamberId),
                ]);
                console.log(
                    `🏛️ [chamber-leadership] ${requestId}: appointed ${userId} as ${role} of ${chamberId}`
                );

                await sendPushToUser(userId, {
                    title: `You're now ${roleDisplay}`,
                    body: `Your leadership request for ${chamberName} was approved.`,
                    type: "chamber_leadership_approved",
                    additionalData: {
                        chamberId,
                        role,
                        requestId,
                    },
                });
            } catch (e) {
                console.error(
                    `[chamber-leadership] Appointment failed for ${requestId}: ${e.message}`
                );
                const [, chamberName] = await Promise.all([
                    change.after.ref.update({
                        approved: false,
                        status: "rejected",
                        decisionNote: `Appointment failed: ${e.message}`,
                        decidedAt: admin.firestore.FieldValue.serverTimestamp(),
                    }),
                    getChamberName(chamberId),
                ]);

                await sendPushToUser(userId, {
                    title: "Leadership request couldn't be granted",
                    body: `Couldn't appoint you as ${roleDisplay} of ${chamberName}: ${e.message}`,
                    type: "chamber_leadership_failed",
                    additionalData: {
                        chamberId,
                        role,
                        requestId,
                        reason: e.message,
                    },
                });
            }
        } else if (rejectTransition) {
            const chamberName = await getChamberName(chamberId);
            const note = after.decisionNote || "Reviewed by an admin.";
            await sendPushToUser(userId, {
                title: "Leadership request declined",
                body: `${chamberName} — ${roleDisplay}: ${note}`,
                type: "chamber_leadership_rejected",
                additionalData: {
                    chamberId,
                    role,
                    requestId,
                    note,
                },
            });
        }
        return null;
    });

// Exported for the CLI fallback path (when an admin wants to bypass the
// trigger and appoint directly without going through a request doc).
exports._performAppointment = performAppointment;
