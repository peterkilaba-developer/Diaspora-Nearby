/**
 * Backfill corridor Chamber-of-Commerce organizations for all existing users.
 *
 * Mirrors `OrganizationRepository.ensureCorridorChamber` in the client:
 *   - Deterministic id:   chamber_<host>_<home>   (host first)
 *   - Chat id:            org_chamber_<host>_<home>
 *   - Display name:       "<HOST> ⇄ <HOME> Chamber of Commerce"
 *   - Idempotent          first user creates, subsequent users join
 *   - Skipped when         homeCC === hostCC, or either is empty
 *
 * Each existing user with a valid (home, host) corridor will be added to the
 * appropriate chamber's members/followers and the chamber chat's participants,
 * and the chat will appear in their userChats index.
 *
 * Usage:
 *   node functions/scripts/backfill-corridor-chambers.js          # dry run
 *   node functions/scripts/backfill-corridor-chambers.js --apply  # write changes
 *
 * Requires GOOGLE_APPLICATION_CREDENTIALS or `gcloud auth application-default login`.
 */
const admin = require("firebase-admin");

admin.initializeApp();
const db = admin.firestore();

const DRY_RUN = !process.argv.includes("--apply");

function corridorIds(homeCC, hostCC) {
    const home = homeCC.toUpperCase();
    const host = hostCC.toUpperCase();
    const orgId = `chamber_${host.toLowerCase()}_${home.toLowerCase()}`;
    const chatId = `org_${orgId}`;
    const name = `${host} ⇄ ${home} Chamber of Commerce`;
    return { home, host, orgId, chatId, name };
}

async function ensureChamber({ userId, homeCC, hostCC }) {
    if (!homeCC || !hostCC) return { skipped: "missing-code" };
    if (homeCC === hostCC) return { skipped: "same-country" };
    if (homeCC === "XX" || hostCC === "XX") return { skipped: "placeholder" };

    const { home, host, orgId, chatId, name } = corridorIds(homeCC, hostCC);

    if (DRY_RUN) {
        return { dryRun: true, orgId, chatId, name, userId };
    }

    const orgRef = db.collection("organizations").doc(orgId);
    const chatRef = db.collection("chats").doc(chatId);
    const userChatRef = db
        .collection("users")
        .doc(userId)
        .collection("userChats")
        .doc(chatId);

    const now = Date.now();

    const wasCreated = await db.runTransaction(async (tx) => {
        const snap = await tx.get(orgRef);
        if (!snap.exists) {
            tx.set(orgRef, {
                id: orgId,
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
                members: [userId],
                followers: [userId],
                memberCount: 1,
                isPublic: true,
                country: host,
                homeCountryCode: home,
                hostCountryCode: host,
                communityId: null,
                richData: null,
                chatId,
                status: "active",
                createdAt: admin.firestore.FieldValue.serverTimestamp(),
                updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            });
            tx.set(chatRef, {
                id: chatId,
                type: "organization",
                subtype: "corridor_chamber",
                name,
                participants: [userId],
                admins: [],
                homeCountryCode: home,
                hostCountryCode: host,
                createdAt: now,
                updatedAt: now,
                createdBy: "system",
                lastMessage: {
                    content: "Chamber of Commerce opened",
                    timestamp: now,
                    type: "system",
                    senderId: "system",
                    senderName: "System",
                },
            });
            return true;
        }

        // Existing chamber — only update arrays if user is not already a member
        // (arrayUnion is idempotent, increment is not — guard with a read).
        const data = snap.data() || {};
        const members = Array.isArray(data.members) ? data.members : [];
        const alreadyMember = members.includes(userId);

        tx.update(orgRef, {
            members: admin.firestore.FieldValue.arrayUnion(userId),
            followers: admin.firestore.FieldValue.arrayUnion(userId),
            ...(alreadyMember
                ? {}
                : { memberCount: admin.firestore.FieldValue.increment(1) }),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        tx.update(chatRef, {
            participants: admin.firestore.FieldValue.arrayUnion(userId),
            updatedAt: now,
        });
        return false;
    });

    // userChats index entry (outside transaction — subcollection, idempotent set/merge).
    // Explicitly clear isDeleted in case the user previously soft-deleted
    // the chat — chambers are auto-membership, so an old soft-delete must
    // not keep the chat hidden after backfill restores them.
    await userChatRef.set(
        {
            chatId,
            isDeleted: false,
            updatedAt: now,
            lastRead: now,
        },
        { merge: true }
    );

    return { wasCreated, orgId, chatId, name, userId };
}

async function main() {
    console.log(
        `\n🧭 Corridor Chamber backfill — ${DRY_RUN ? "DRY RUN" : "APPLYING CHANGES"}\n`
    );

    const usersSnap = await db.collection("users").get();
    console.log(`Found ${usersSnap.size} user docs.\n`);

    const stats = {
        processed: 0,
        joined: 0,
        created: 0,
        skippedSame: 0,
        skippedMissing: 0,
        skippedPlaceholder: 0,
        errors: 0,
    };
    const createdChambers = new Set();
    const errors = [];

    for (const doc of usersSnap.docs) {
        const data = doc.data();
        const userId = doc.id;
        const homeCC = (data.homeCountryCode || "").toUpperCase();
        const hostCC = (data.hostCountryCode || "").toUpperCase();

        try {
            const result = await ensureChamber({ userId, homeCC, hostCC });
            stats.processed += 1;

            if (result.skipped === "same-country") {
                stats.skippedSame += 1;
                continue;
            }
            if (result.skipped === "missing-code") {
                stats.skippedMissing += 1;
                continue;
            }
            if (result.skipped === "placeholder") {
                stats.skippedPlaceholder += 1;
                continue;
            }

            if (result.dryRun) {
                console.log(
                    `  [dry] ${userId.slice(0, 8)}… → ${result.orgId} (${result.name})`
                );
                createdChambers.add(result.orgId);
                continue;
            }

            if (result.wasCreated) {
                stats.created += 1;
                createdChambers.add(result.orgId);
                console.log(
                    `  ➕ Created ${result.orgId} (${result.name}) — first member ${userId.slice(0, 8)}…`
                );
            } else {
                stats.joined += 1;
                console.log(
                    `  → Joined ${userId.slice(0, 8)}… into ${result.orgId}`
                );
            }
        } catch (e) {
            stats.errors += 1;
            errors.push({ userId, error: e.message });
            console.error(`  ✗ ${userId}: ${e.message}`);
        }
    }

    console.log("\n📊 Summary");
    console.log("  Users processed:        ", stats.processed);
    console.log("  Chambers created:       ", stats.created);
    console.log("  User joins:             ", stats.joined);
    console.log("  Distinct chambers seen: ", createdChambers.size);
    console.log("  Skipped (same country): ", stats.skippedSame);
    console.log("  Skipped (missing code): ", stats.skippedMissing);
    console.log("  Skipped (XX/placeholder):", stats.skippedPlaceholder);
    console.log("  Errors:                 ", stats.errors);

    if (DRY_RUN) {
        console.log("\n👀 Dry run only. Re-run with --apply to write changes.\n");
    } else {
        console.log("\n✅ Done.\n");
    }

    if (errors.length) {
        console.log("\nFirst 10 errors:");
        errors.slice(0, 10).forEach((e) =>
            console.log(`  ${e.userId}: ${e.error}`)
        );
    }
}

main()
    .then(() => process.exit(0))
    .catch((e) => {
        console.error("Fatal:", e);
        process.exit(1);
    });
