#!/usr/bin/env node
/**
 * Backfills server-enforced block records, direct-chat pair indexes,
 * deterministic pending requests, and unique family slots.
 *
 * Uses Application Default Credentials. Dry-run is the default:
 *   node functions/scripts/migrate-relationship-security.js
 *   node functions/scripts/migrate-relationship-security.js --apply
 */
const crypto = require("crypto");
const admin = require("firebase-admin");

admin.initializeApp();
const db = admin.firestore();
const APPLY = process.argv.includes("--apply");
const PAGE_SIZE = 200;

const metrics = {
  privateProfiles: 0,
  blockEdges: 0,
  blocksCreated: 0,
  directChats: 0,
  directPairsCreated: 0,
  duplicateDirectPairs: 0,
  pendingRequests: 0,
  requestsNormalized: 0,
  requestConflicts: 0,
  relationshipOwners: 0,
  slotsCreated: 0,
  slotConflicts: 0,
  truncatedRelationshipOwners: 0,
};

function stableHash(value) {
  return crypto.createHash("sha256").update(String(value)).digest("hex");
}

function validId(value) {
  return typeof value === "string" && /^[A-Za-z0-9_-]{1,128}$/.test(value);
}

function slotName(type) {
  const normalized = String(type || "").toLowerCase();
  if (["wife", "husband"].includes(normalized)) return "spouse";
  if (["father", "mother"].includes(normalized)) return normalized;
  return null;
}

async function mapLimit(values, concurrency, operation) {
  for (let index = 0; index < values.length; index += concurrency) {
    await Promise.all(values.slice(index, index + concurrency).map(operation));
  }
}

async function pageCollection(queryFactory, operation) {
  let cursor = null;
  while (true) {
    let query = queryFactory()
        .orderBy(admin.firestore.FieldPath.documentId())
        .limit(PAGE_SIZE);
    if (cursor) query = query.startAfter(cursor);
    const page = await query.get();
    if (page.empty) return;
    await operation(page.docs);
    cursor = page.docs[page.docs.length - 1];
    if (page.size < PAGE_SIZE) return;
  }
}

async function migrateBlock(blockerId, blockedId) {
  metrics.blockEdges += 1;
  if (!APPLY) return;
  const blockRef = db.collection("user_blocks").doc(blockerId)
      .collection("blocked").doc(blockedId);
  const trustRef = db.collection("trust_data").doc(blockedId);
  const created = await db.runTransaction(async (transaction) => {
    const [block, trust] = await Promise.all([
      transaction.get(blockRef), transaction.get(trustRef),
    ]);
    if (block.exists) return false;
    const count = trust.exists ?
      Math.max(0, Number(trust.data().blockedByCount || 0)) : 0;
    transaction.create(blockRef, {
      blockerId,
      blockedId,
      migratedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    transaction.set(trustRef, {
      blockedByCount: count + 1,
      lastUpdated: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});
    return true;
  });
  if (created) metrics.blocksCreated += 1;
}

async function migrateBlocksAndSlots() {
  await pageCollection(() => db.collection("user_private"), async (documents) => {
    await mapLimit(documents, 10, async (document) => {
      metrics.privateProfiles += 1;
      const blockedUsers = Array.isArray(document.data().blockedUsers) ?
        [...new Set(document.data().blockedUsers.filter((blockedId) =>
          validId(blockedId) && blockedId !== document.id))].slice(0, 1000) : [];
      await mapLimit(blockedUsers, 10, (blockedId) =>
        migrateBlock(document.id, blockedId));
    });
  });

  await pageCollection(() => db.collection("users"), async (users) => {
    await mapLimit(users, 10, async (user) => {
      metrics.relationshipOwners += 1;
      const relationships = await user.ref.collection("relationships").limit(501).get();
      if (relationships.size > 500) metrics.truncatedRelationshipOwners += 1;
      const selectedSlots = new Map();
      for (const relationship of relationships.docs.slice(0, 500)) {
        const slot = slotName(relationship.data().type);
        if (!slot || !validId(relationship.id)) continue;
        if (selectedSlots.has(slot) && selectedSlots.get(slot) !== relationship.id) {
          metrics.slotConflicts += 1;
          continue;
        }
        selectedSlots.set(slot, relationship.id);
      }
      for (const [slot, relatedUserId] of selectedSlots.entries()) {
        if (!APPLY) {
          metrics.slotsCreated += 1;
          continue;
        }
        const slotRef = user.ref.collection("relationship_slots").doc(slot);
        const result = await db.runTransaction(async (transaction) => {
          const existing = await transaction.get(slotRef);
          if (existing.exists && existing.data().relatedUserId !== relatedUserId) {
            return "conflict";
          }
          if (existing.exists) return "exists";
          transaction.create(slotRef, {
            relatedUserId,
            migratedAt: admin.firestore.FieldValue.serverTimestamp(),
          });
          return "created";
        });
        if (result === "created") metrics.slotsCreated += 1;
        if (result === "conflict") metrics.slotConflicts += 1;
      }
    });
  });
}

async function migrateDirectChats() {
  await pageCollection(
      () => db.collection("chats").where("type", "==", "direct"),
      async (documents) => {
        await mapLimit(documents, 20, async (document) => {
          metrics.directChats += 1;
          const participants = document.data().participants;
          if (!Array.isArray(participants) || participants.length !== 2 ||
              !participants.every(validId) || participants[0] === participants[1]) return;
          const users = [...participants].sort();
          const pairRef = db.collection("direct_chat_pairs")
              .doc(stableHash(users.join(":")));
          if (!APPLY) {
            metrics.directPairsCreated += 1;
            return;
          }
          const outcome = await db.runTransaction(async (transaction) => {
            const pair = await transaction.get(pairRef);
            if (pair.exists) {
              return pair.data().chatId === document.id ? "exists" : "duplicate";
            }
            transaction.create(pairRef, {
              chatId: document.id,
              users,
              migratedAt: admin.firestore.FieldValue.serverTimestamp(),
            });
            return "created";
          });
          if (outcome === "created") metrics.directPairsCreated += 1;
          if (outcome === "duplicate") metrics.duplicateDirectPairs += 1;
        });
      },
  );
}

async function migratePendingRequests() {
  await pageCollection(
      () => db.collection("relationship_requests").where("status", "==", "pending"),
      async (documents) => {
        await mapLimit(documents, 20, async (document) => {
          metrics.pendingRequests += 1;
          const request = document.data();
          if (!validId(request.fromUserId) || !validId(request.toUserId) ||
              request.fromUserId === request.toUserId) return;
          const canonicalId = stableHash(`${request.fromUserId}:${request.toUserId}`);
          if (document.id === canonicalId) return;
          if (!APPLY) {
            metrics.requestsNormalized += 1;
            return;
          }
          const canonicalRef = document.ref.parent.doc(canonicalId);
          const outcome = await db.runTransaction(async (transaction) => {
            const canonical = await transaction.get(canonicalRef);
            if (canonical.exists) return "conflict";
            transaction.create(canonicalRef, {
              ...request,
              id: canonicalId,
              migratedAt: admin.firestore.FieldValue.serverTimestamp(),
            });
            transaction.delete(document.ref);
            return "normalized";
          });
          if (outcome === "normalized") metrics.requestsNormalized += 1;
          if (outcome === "conflict") metrics.requestConflicts += 1;
        });
      },
  );
}

async function main() {
  await migrateBlocksAndSlots();
  await migrateDirectChats();
  await migratePendingRequests();
  console.log(JSON.stringify({apply: APPLY, ...metrics}, null, 2));
  if (metrics.slotConflicts || metrics.duplicateDirectPairs ||
      metrics.requestConflicts || metrics.truncatedRelationshipOwners) {
    process.exitCode = 2;
  }
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
