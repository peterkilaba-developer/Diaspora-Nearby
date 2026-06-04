/**
 * Appoint a trusted user to a leadership seat on a corridor Chamber of Commerce.
 *
 * Mirrors `OrganizationRepository.appointChamberLeader` in the client. Both
 * paths converge on the same Firestore shape so future migrations stay clean.
 *
 * Roles (must match lib/features/organization/models/chamber_roles.dart):
 *   - president          (no nationality pin)
 *   - vice_president     (no nationality pin)
 *   - treasurer          (no nationality pin)
 *   - secretary          (no nationality pin)
 *   - home_trade_rep     (must be home-country national)
 *   - host_trade_rep     (must currently live in or have past location in host country)
 *
 * Usage:
 *   List leaders of a chamber:
 *     node functions/scripts/appoint-chamber-leader.js list chamber_us_tz
 *
 *   Appoint:
 *     node functions/scripts/appoint-chamber-leader.js appoint chamber_us_tz <userId> president
 *
 *   Remove a specific seat:
 *     node functions/scripts/appoint-chamber-leader.js remove chamber_us_tz <userId> [role]
 *
 * Requires GOOGLE_APPLICATION_CREDENTIALS pointing at a service-account key.
 */
const admin = require("firebase-admin");

admin.initializeApp();
const db = admin.firestore();

// --- Role definitions (kept in sync with chamber_roles.dart) ----------------

const ROLES = {
    president: { display: "President", homePin: false, hostPin: false },
    vice_president: { display: "Vice President", homePin: false, hostPin: false },
    treasurer: { display: "Treasurer", homePin: false, hostPin: false },
    secretary: { display: "Secretary", homePin: false, hostPin: false },
    home_trade_rep: { display: "Home Trade Rep", homePin: true, hostPin: false },
    host_trade_rep: { display: "Host Trade Rep", homePin: false, hostPin: true },
};

function fail(msg) {
    console.error("✗ " + msg);
    process.exit(1);
}

// --- Operations -------------------------------------------------------------

async function listLeaders(chamberId) {
    const snap = await db.collection("organizations").doc(chamberId).get();
    if (!snap.exists) fail(`Chamber ${chamberId} not found.`);
    const data = snap.data();
    if (data.kind !== "corridor_chamber") {
        fail(`${chamberId} is not a corridor_chamber (kind="${data.kind}").`);
    }

    console.log(`\n📋 ${data.name}`);
    console.log(`   id: ${chamberId} | members: ${data.memberCount || 0}`);
    console.log(`   home: ${data.homeCountryCode} | host: ${data.hostCountryCode}\n`);

    const councilRoles = data.councilRoles || {};
    const adminTitles = data.adminTitles || {};
    const entries = Object.entries(councilRoles);
    if (entries.length === 0) {
        console.log("   (no leaders appointed yet — system-managed)\n");
        return;
    }
    console.log("   Council:");
    for (const [uid, role] of entries) {
        const def = ROLES[role];
        const display = def ? def.display : role;
        const title = adminTitles[uid] || display;
        console.log(`     - ${title.padEnd(18)} ${uid}`);
    }
    console.log("");
}

async function appoint(chamberId, userId, role) {
    if (!ROLES[role]) {
        fail(`Unknown role "${role}". Valid: ${Object.keys(ROLES).join(", ")}`);
    }

    // Pre-fetch user profile for nationality / past-location validation.
    const userSnap = await db.collection("users").doc(userId).get();
    if (!userSnap.exists) fail(`User ${userId} does not exist.`);
    const user = userSnap.data() || {};
    const userHome = (user.homeCountryCode || "").toUpperCase();
    const userHost = (user.hostCountryCode || "").toUpperCase();
    const pastCountryCodes = new Set(
        (user.pastLocations || [])
            .map((p) => p && p.location && p.location.countryCode)
            .filter(Boolean)
            .map((c) => c.toUpperCase())
    );

    const orgRef = db.collection("organizations").doc(chamberId);

    await db.runTransaction(async (tx) => {
        const snap = await tx.get(orgRef);
        if (!snap.exists) throw new Error(`Chamber ${chamberId} not found.`);
        const data = snap.data();
        if (data.kind !== "corridor_chamber") {
            throw new Error(
                `Only corridor chambers can be managed here (kind="${data.kind}").`
            );
        }

        const chamberHome = (data.homeCountryCode || "").toUpperCase();
        const chamberHost = (data.hostCountryCode || "").toUpperCase();
        const def = ROLES[role];

        if (def.homePin && userHome !== chamberHome) {
            throw new Error(
                `Home-pinned role "${role}" requires home country ${chamberHome}, user has ${userHome}.`
            );
        }
        if (def.hostPin) {
            const livesInHost = userHost === chamberHost;
            const livedInHost = pastCountryCodes.has(chamberHost);
            if (!livesInHost && !livedInHost) {
                throw new Error(
                    `Host-pinned role "${role}" requires lived experience in ${chamberHost} (current or past). User host=${userHost}.`
                );
            }
        }

        const members = Array.isArray(data.members) ? data.members : [];
        if (!members.includes(userId)) {
            throw new Error(
                `User ${userId} is not a chamber member yet. They must auto-join via signup first.`
            );
        }

        const councilRoles = Object.assign({}, data.councilRoles || {});
        const adminTitles = Object.assign({}, data.adminTitles || {});

        // Replace any prior holder of this single-occupant seat.
        for (const [otherUid, otherRole] of Object.entries(councilRoles)) {
            if (otherUid !== userId && otherRole === role) {
                delete councilRoles[otherUid];
                delete adminTitles[otherUid];
                console.log(`  ↩ replacing prior ${role}: ${otherUid}`);
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

    console.log(`\n✅ Appointed ${userId} as ${ROLES[role].display} of ${chamberId}\n`);
}

async function remove(chamberId, userId, role /* optional */) {
    const orgRef = db.collection("organizations").doc(chamberId);
    let removedRole = null;

    await db.runTransaction(async (tx) => {
        const snap = await tx.get(orgRef);
        if (!snap.exists) throw new Error(`Chamber ${chamberId} not found.`);
        const data = snap.data();
        if (data.kind !== "corridor_chamber") {
            throw new Error("Only corridor chambers are managed here.");
        }
        const councilRoles = Object.assign({}, data.councilRoles || {});
        const adminTitles = Object.assign({}, data.adminTitles || {});

        const currentRole = councilRoles[userId];
        if (!currentRole) {
            throw new Error(`User ${userId} holds no chamber seat.`);
        }
        if (role && currentRole !== role) {
            throw new Error(
                `User ${userId} holds ${currentRole}, not ${role}. Nothing changed.`
            );
        }
        removedRole = currentRole;

        delete councilRoles[userId];
        delete adminTitles[userId];

        const admins = Array.isArray(data.admins) ? [...data.admins] : [];
        const idx = admins.indexOf(userId);
        if (idx >= 0) admins.splice(idx, 1);

        tx.update(orgRef, {
            councilRoles,
            adminTitles,
            admins,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });

        const chatId = data.chatId;
        if (chatId) {
            tx.update(db.collection("chats").doc(chatId), {
                admins: admin.firestore.FieldValue.arrayRemove(userId),
                updatedAt: Date.now(),
            });
        }
    });

    console.log(
        `\n✅ Removed ${userId} from ${removedRole || "(unknown role)"} on ${chamberId}\n`
    );
}

// --- Leadership requests ----------------------------------------------------

async function listRequests(chamberId /* optional */, status /* optional */) {
    let q = db.collection("leadershipRequests");
    if (chamberId) q = q.where("chamberId", "==", chamberId);
    if (status) q = q.where("status", "==", status);
    const snap = await q.get();

    console.log(
        `\n📨 Leadership requests${chamberId ? ` for ${chamberId}` : ""}` +
            `${status ? ` (status=${status})` : ""}\n`
    );
    if (snap.empty) {
        console.log("   (none)\n");
        return;
    }
    for (const doc of snap.docs) {
        const d = doc.data();
        console.log(`   ${doc.id}`);
        console.log(`     chamber:   ${d.chamberId}`);
        console.log(`     user:      ${d.userId}`);
        console.log(`     role:      ${d.role}`);
        console.log(`     status:    ${d.status} | approved=${d.approved}`);
        if (d.message) console.log(`     message:   ${d.message}`);
        if (d.decisionNote) console.log(`     note:      ${d.decisionNote}`);
        console.log("");
    }
}

async function approveRequest(requestId) {
    // We just flip `approved: true`; the Cloud Function trigger handles
    // the appointment and updates `status` server-side. If you ran this
    // without the function deployed, the request stays in pending forever.
    const ref = db.collection("leadershipRequests").doc(requestId);
    const snap = await ref.get();
    if (!snap.exists) fail(`Request ${requestId} not found.`);
    const data = snap.data();
    if (data.status !== "pending") {
        fail(`Request ${requestId} is already ${data.status}.`);
    }

    await ref.update({
        approved: true,
        decidedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    console.log(
        `\n✅ Flipped approved=true on ${requestId}. The trigger function will perform the appointment shortly.\n`
    );
}

async function rejectRequest(requestId, note /* optional */) {
    const ref = db.collection("leadershipRequests").doc(requestId);
    const snap = await ref.get();
    if (!snap.exists) fail(`Request ${requestId} not found.`);
    const data = snap.data();
    if (data.status !== "pending") {
        fail(`Request ${requestId} is already ${data.status}.`);
    }
    await ref.update({
        status: "rejected",
        approved: false,
        decisionNote: note || null,
        decidedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    console.log(`\n✅ Rejected ${requestId}.\n`);
}

// --- CLI dispatch -----------------------------------------------------------

async function main() {
    const [, , cmd, ...rest] = process.argv;

    if (!cmd) {
        console.log(
            "Usage:\n" +
                "  Council inspection / direct appointment:\n" +
                "    node appoint-chamber-leader.js list     <chamberId>\n" +
                "    node appoint-chamber-leader.js appoint  <chamberId> <userId> <role>\n" +
                "    node appoint-chamber-leader.js remove   <chamberId> <userId> [role]\n\n" +
                "  Request workflow (users submit, admin approves):\n" +
                "    node appoint-chamber-leader.js requests [chamberId] [status]\n" +
                "    node appoint-chamber-leader.js approve  <requestId>\n" +
                "    node appoint-chamber-leader.js reject   <requestId> [note]\n\n" +
                `  Valid roles:    ${Object.keys(ROLES).join(", ")}\n` +
                `  Valid statuses: pending, approved, rejected\n`
        );
        process.exit(0);
    }

    switch (cmd) {
        case "list": {
            const [chamberId] = rest;
            if (!chamberId) fail("list requires <chamberId>");
            await listLeaders(chamberId);
            break;
        }
        case "appoint": {
            const [chamberId, userId, role] = rest;
            if (!chamberId || !userId || !role)
                fail("appoint requires <chamberId> <userId> <role>");
            await appoint(chamberId, userId, role);
            await listLeaders(chamberId);
            break;
        }
        case "remove": {
            const [chamberId, userId, role] = rest;
            if (!chamberId || !userId)
                fail("remove requires <chamberId> <userId> [role]");
            await remove(chamberId, userId, role /* may be undefined */);
            await listLeaders(chamberId);
            break;
        }
        case "requests": {
            const [chamberId, status] = rest;
            await listRequests(chamberId, status);
            break;
        }
        case "approve": {
            const [requestId] = rest;
            if (!requestId) fail("approve requires <requestId>");
            await approveRequest(requestId);
            break;
        }
        case "reject": {
            const [requestId, ...noteParts] = rest;
            if (!requestId) fail("reject requires <requestId>");
            await rejectRequest(requestId, noteParts.join(" ") || null);
            break;
        }
        default:
            fail(
                `Unknown command "${cmd}". ` +
                    `Use list / appoint / remove / requests / approve / reject.`
            );
    }
}

main()
    .then(() => process.exit(0))
    .catch((e) => {
        console.error("\n✗ " + e.message + "\n");
        process.exit(1);
    });
