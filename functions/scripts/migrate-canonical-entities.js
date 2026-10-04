#!/usr/bin/env node
/**
 * Audits and, with --apply, backfills canonical parent/chat links and booking
 * availability slots introduced by the enterprise hardening release.
 *
 * Uses Application Default Credentials. Dry-run is the default:
 *   node functions/scripts/migrate-canonical-entities.js
 *   node functions/scripts/migrate-canonical-entities.js --apply
 *
 * The script is deliberately conservative: it never replaces an existing
 * parent chat, never truncates participant lists, and reports booking overlap
 * conflicts instead of selecting a winner.
 */
const crypto = require("crypto");
const admin = require("firebase-admin");

admin.initializeApp();
const db = admin.firestore();
const APPLY = process.argv.includes("--apply");
const PAGE_SIZE = 200;
const MAX_PARTICIPANTS = 500;

const metrics = {
  parentsScanned: 0,
  missingParentOwners: 0,
  invalidParentChatIds: 0,
  missingChats: 0,
  chatsCreated: 0,
  parentLinksBackfilled: 0,
  participantConflicts: 0,
  chamberChatsScanned: 0,
  chamberOrganizationMismatches: 0,
  confirmedBookingsScanned: 0,
  invalidBookings: 0,
  bookingSlotsNeeded: 0,
  bookingSlotsCreated: 0,
  bookingSlotConflicts: 0,
};

function stableHash(value) {
  return crypto.createHash("sha256").update(String(value)).digest("hex");
}

function validId(value) {
  return typeof value === "string" && /^[A-Za-z0-9_-]{1,256}$/.test(value);
}

function boundedText(value, fallback) {
  const normalized = String(value || "").trim();
  return (normalized || fallback).slice(0, 200);
}

function uniqueIds(values) {
  return [...new Set(values.filter(validId))];
}

function timestampDate(value) {
  if (value && typeof value.toDate === "function") return value.toDate();
  if (value instanceof Date) return value;
  if (typeof value === "string" || typeof value === "number") {
    const parsed = new Date(value);
    if (Number.isFinite(parsed.getTime())) return parsed;
  }
  return null;
}

function utcDays(start, end) {
  const cursor = new Date(Date.UTC(
      start.getUTCFullYear(), start.getUTCMonth(), start.getUTCDate()));
  const finalDay = new Date(Date.UTC(
      end.getUTCFullYear(), end.getUTCMonth(), end.getUTCDate()));
  const result = [];
  while (cursor < finalDay && result.length <= 365) {
    result.push(cursor.toISOString().slice(0, 10));
    cursor.setUTCDate(cursor.getUTCDate() + 1);
  }
  return result;
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

function parentSpec(collection, document) {
  const data = document.data();
  if (collection === "events") {
    return {
      ownerId: data.creatorId,
      deterministicChatId: `event_${document.id}`,
      chatType: "event",
      groupType: "event",
      entityField: "eventId",
      name: boundedText(data.title || data.name, "Event chat"),
      photoUrl: data.imageUrl || data.coverImage || "",
      admins: uniqueIds([data.creatorId]),
      participants: uniqueIds([
        data.creatorId,
        ...(Array.isArray(data.attendees) ? data.attendees : []),
      ]),
      isPublic: data.isPrivate !== true,
    };
  }
  if (collection === "organizations") {
    const admins = uniqueIds([
      ...(Array.isArray(data.admins) ? data.admins : []),
      data.createdBy,
      data.creatorId,
      data.ownerId,
    ]);
    return {
      ownerId: admins[0],
      deterministicChatId: `org_${document.id}`,
      chatType: data.type === "chamber" ? "group" : "organization",
      groupType: data.type === "chamber" ? "chamber" : "organization",
      entityField: "organizationId",
      name: boundedText(data.name, "Organization chat"),
      photoUrl: data.logoUrl || data.imageUrl || "",
      admins,
      participants: uniqueIds([
        ...admins,
        ...(Array.isArray(data.members) ? data.members : []),
        ...(Array.isArray(data.followers) ? data.followers : []),
      ]),
      isPublic: data.isPrivate !== true,
    };
  }
  const admins = uniqueIds(Array.isArray(data.admins) ? data.admins : []);
  const members = uniqueIds([
    ...(Array.isArray(data.members) ? data.members : []),
    ...(Array.isArray(data.memberIds) ? data.memberIds : []),
  ]);
  return {
    ownerId: admins[0] || members[0],
    deterministicChatId: `chat_${document.id}`,
    chatType: "community",
    groupType: "community",
    entityField: "communityId",
    name: boundedText(data.name, "Community chat"),
    photoUrl: data.profileImage || data.imageUrl || "",
    admins,
    participants: uniqueIds([
      ...admins,
      ...members,
    ]),
    isPublic: data.isPrivate !== true,
  };
}

async function auditParent(collection, document) {
  metrics.parentsScanned += 1;
  const data = document.data();
  const spec = parentSpec(collection, document);
  if (!validId(spec.ownerId)) {
    metrics.missingParentOwners += 1;
    return;
  }
  if (spec.participants.length > MAX_PARTICIPANTS) {
    metrics.participantConflicts += 1;
    return;
  }

  const storedChatId = data.chatId;
  if (storedChatId != null && !validId(storedChatId)) {
    metrics.invalidParentChatIds += 1;
    return;
  }
  const chatId = validId(storedChatId) ? storedChatId : spec.deterministicChatId;
  const chatRef = db.collection("chats").doc(chatId);
  const chat = await chatRef.get();
  if (!chat.exists) metrics.missingChats += 1;
  if (!validId(storedChatId)) metrics.parentLinksBackfilled += 1;
  if (!APPLY) return;

  await db.runTransaction(async (transaction) => {
    const [latestParent, latestChat] = await Promise.all([
      transaction.get(document.ref), transaction.get(chatRef),
    ]);
    if (!latestParent.exists) return;
    const latestChatId = latestParent.data().chatId;
    if (validId(latestChatId) && latestChatId !== chatId) {
      metrics.participantConflicts += 1;
      return;
    }
    if (!latestChat.exists) {
      transaction.create(chatRef, {
        chatId,
        type: spec.chatType,
        groupType: spec.groupType,
        name: spec.name,
        groupName: spec.name,
        groupPhoto: typeof spec.photoUrl === "string" ? spec.photoUrl : "",
        creatorId: spec.ownerId,
        admins: spec.admins.length ? spec.admins : [spec.ownerId],
        participants: spec.participants.length ? spec.participants : [spec.ownerId],
        isPublic: spec.isPublic,
        [spec.entityField]: document.id,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        securityMigrationVersion: 1,
      });
      metrics.chatsCreated += 1;
    } else {
      transaction.set(chatRef, {
        [spec.entityField]: document.id,
        securityMigrationVersion: 1,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, {merge: true});
    }
    if (!validId(latestChatId)) {
      transaction.set(document.ref, {
        chatId,
        securityMigrationVersion: 1,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, {merge: true});
    }
  });
}

async function migrateParents() {
  for (const collection of ["events", "organizations", "communities"]) {
    await pageCollection(() => db.collection(collection), async (documents) => {
      await mapLimit(documents, 10, (document) => auditParent(collection, document));
    });
  }
}

async function auditChamberIdentity() {
  await pageCollection(
      () => db.collection("chats").where("groupType", "==", "chamber"),
      async (documents) => {
        await mapLimit(documents, 20, async (document) => {
          metrics.chamberChatsScanned += 1;
          const organizationId = document.data().organizationId;
          if (organizationId !== document.id) {
            metrics.chamberOrganizationMismatches += 1;
          }
        });
      });
}

async function auditConfirmedBooking(document) {
  metrics.confirmedBookingsScanned += 1;
  const booking = document.data();
  const start = timestampDate(booking.startDate);
  const end = timestampDate(booking.endDate);
  if (!validId(booking.listingId) || !validId(booking.guestId) ||
      !validId(booking.hostId) || !start || !end || end <= start) {
    metrics.invalidBookings += 1;
    return;
  }
  const days = utcDays(start, end);
  if (days.length < 1 || days.length > 365) {
    metrics.invalidBookings += 1;
    return;
  }
  metrics.bookingSlotsNeeded += days.length;

  await mapLimit(days, 20, async (day) => {
    const slotRef = db.collection("peer_booking_slots")
        .doc(stableHash(`${booking.listingId}:${day}`));
    if (!APPLY) {
      const existing = await slotRef.get();
      if (existing.exists && existing.data().bookingId !== document.id) {
        metrics.bookingSlotConflicts += 1;
      }
      return;
    }
    const result = await db.runTransaction(async (transaction) => {
      const existing = await transaction.get(slotRef);
      if (existing.exists) {
        return existing.data().bookingId === document.id ? "exists" : "conflict";
      }
      transaction.create(slotRef, {
        bookingId: document.id,
        listingId: booking.listingId,
        guestId: booking.guestId,
        hostId: booking.hostId,
        day,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        securityMigrationVersion: 1,
      });
      return "created";
    });
    if (result === "created") metrics.bookingSlotsCreated += 1;
    if (result === "conflict") metrics.bookingSlotConflicts += 1;
  });
}

async function migrateBookingSlots() {
  await pageCollection(
      () => db.collection("peer_bookings").where("status", "==", "confirmed"),
      async (documents) => {
        await mapLimit(documents, 5, auditConfirmedBooking);
      });
}

async function main() {
  await migrateParents();
  await auditChamberIdentity();
  await migrateBookingSlots();
  console.log(JSON.stringify({apply: APPLY, ...metrics}, null, 2));
  if (metrics.invalidParentChatIds || metrics.participantConflicts ||
      metrics.chamberOrganizationMismatches || metrics.invalidBookings ||
      metrics.bookingSlotConflicts) {
    process.exitCode = 2;
  }
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
