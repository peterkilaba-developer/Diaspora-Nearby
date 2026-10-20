/** Canonical peer stay/car booking lifecycle. */
const {functions, admin, db} = require("./shared");
const {
  requireAuth,
  requireAppCheck,
  consumeRateLimit,
  stableHash,
} = require("./security");

const DAY_MS = 24 * 60 * 60 * 1000;
const MAX_BOOKING_DAYS = 365;

function parseDate(value, fieldName) {
  if (typeof value !== "string" || value.length > 64) {
    throw new functions.https.HttpsError("invalid-argument", `${fieldName} is invalid.`);
  }
  const date = new Date(value);
  if (!Number.isFinite(date.getTime())) {
    throw new functions.https.HttpsError("invalid-argument", `${fieldName} is invalid.`);
  }
  return date;
}

function bookingDays(start, end) {
  const count = Math.floor((end.getTime() - start.getTime()) / DAY_MS);
  if (count < 1 || count > MAX_BOOKING_DAYS) {
    throw new functions.https.HttpsError(
        "invalid-argument",
        `Bookings must be between 1 and ${MAX_BOOKING_DAYS} days.`,
    );
  }
  return count;
}

function dateKeys(start, count) {
  return Array.from({length: count}, (_, index) => {
    const day = new Date(start.getTime() + index * DAY_MS).toISOString().slice(0, 10);
    return day;
  });
}

exports.createPeerBooking = functions.https.onCall(async (data, context) => {
  requireAppCheck(context);
  const guestId = requireAuth(context);
  await consumeRateLimit("peer-booking-create", guestId, 20, 24 * 60 * 60 * 1000);
  const listingId = data && data.listingId;
  if (typeof listingId !== "string" || !/^[A-Za-z0-9_-]{1,256}$/.test(listingId)) {
    throw new functions.https.HttpsError("invalid-argument", "Invalid listing ID.");
  }
  const start = parseDate(data.startDate, "Start date");
  const end = parseDate(data.endDate, "End date");
  const days = bookingDays(start, end);
  if (start.getTime() < Date.now() - DAY_MS) {
    throw new functions.https.HttpsError("invalid-argument", "The booking cannot start in the past.");
  }
  const guests = data.guests == null ? null : Number(data.guests);
  if (guests != null && (!Number.isSafeInteger(guests) || guests < 1 || guests > 50)) {
    throw new functions.https.HttpsError("invalid-argument", "Invalid guest count.");
  }
  const notes = data.notes == null ? null : String(data.notes).trim();
  if (notes && notes.length > 1000) {
    throw new functions.https.HttpsError("invalid-argument", "Notes are too long.");
  }

  const [listing, guest, privateGuest, trust] = await Promise.all([
    db.collection("peer_listings").doc(listingId).get(),
    db.collection("users").doc(guestId).get(),
    db.collection("user_private").doc(guestId).get(),
    db.collection("trust_data").doc(guestId).get(),
  ]);
  if (!listing.exists || !guest.exists) {
    throw new functions.https.HttpsError("not-found", "Listing or guest profile not found.");
  }
  const listingData = listing.data();
  const hostId = listingData.ownerId;
  if (typeof hostId !== "string" || hostId === guestId || listingData.status !== "active") {
    throw new functions.https.HttpsError("failed-precondition", "This listing cannot be booked.");
  }
  if (listingData.isPeerHosting === true &&
      (!trust.exists || Number(trust.data().trustScore || 0) < 91)) {
    throw new functions.https.HttpsError(
        "failed-precondition",
        "A Trust Score of 91 or higher is required for peer hosting.",
    );
  }
  const maxGuests = Number(listingData.maxGuests || 0);
  if (guests != null && maxGuests > 0 && guests > maxGuests) {
    throw new functions.https.HttpsError("invalid-argument", "Guest count exceeds capacity.");
  }
  const pricePerUnit = Number(listingData.pricePerUnit || 0);
  if (!Number.isFinite(pricePerUnit) || pricePerUnit < 0 || pricePerUnit > 1000000) {
    throw new functions.https.HttpsError("failed-precondition", "Listing price is invalid.");
  }
  const totalPrice = Math.round(pricePerUnit * days * 100) / 100;
  const bookingId = stableHash(
      `${guestId}:${listingId}:${start.toISOString()}:${end.toISOString()}`,
  );
  const bookingRef = db.collection("peer_bookings").doc(bookingId);
  let created = false;
  await db.runTransaction(async (transaction) => {
    const existing = await transaction.get(bookingRef);
    if (existing.exists) return;
    transaction.create(bookingRef, {
      listingId,
      listingType: String(listingData.type || "stay").slice(0, 32),
      listingTitle: String(listingData.title || "Listing").slice(0, 200),
      guestId,
      guestName: String(guest.data().fullName ||
        `${guest.data().firstName || ""} ${guest.data().lastName || ""}`.trim() ||
        "Guest").slice(0, 200),
      guestPhone: String(guest.data().phone || (privateGuest.exists ? privateGuest.data().phone : "") || "").slice(0, 64),
      hostId,
      hostName: String(listingData.ownerName || "Host").slice(0, 200),
      startDate: admin.firestore.Timestamp.fromDate(start),
      endDate: admin.firestore.Timestamp.fromDate(end),
      guests,
      totalPrice,
      currency: String(listingData.currency || "USD").slice(0, 8).toUpperCase(),
      status: "pending",
      notes,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    created = true;
  });
  return {bookingId, created};
});

exports.updatePeerBookingStatus = functions.https.onCall(async (data, context) => {
  requireAppCheck(context);
  const uid = requireAuth(context);
  await consumeRateLimit("peer-booking-status", uid, 60, 24 * 60 * 60 * 1000);
  const bookingId = data && data.bookingId;
  const nextStatus = data && data.status;
  if (typeof bookingId !== "string" || !/^[A-Za-z0-9_-]{1,256}$/.test(bookingId) ||
      !["confirmed", "rejected", "cancelled", "completed"].includes(nextStatus)) {
    throw new functions.https.HttpsError("invalid-argument", "Invalid booking status request.");
  }
  const bookingRef = db.collection("peer_bookings").doc(bookingId);
  await db.runTransaction(async (transaction) => {
    const booking = await transaction.get(bookingRef);
    if (!booking.exists) {
      throw new functions.https.HttpsError("not-found", "Booking not found.");
    }
    const current = booking.data();
    const isGuest = current.guestId === uid;
    const isHost = current.hostId === uid;
    if (!isGuest && !isHost) {
      throw new functions.https.HttpsError("permission-denied", "Booking access denied.");
    }
    const allowed =
      (current.status === "pending" && isHost &&
        ["confirmed", "rejected", "cancelled"].includes(nextStatus)) ||
      (current.status === "pending" && isGuest && nextStatus === "cancelled") ||
      (current.status === "confirmed" && (isGuest || isHost) && nextStatus === "cancelled") ||
      (current.status === "confirmed" && isHost && nextStatus === "completed");
    if (!allowed) {
      throw new functions.https.HttpsError("failed-precondition", "Invalid booking transition.");
    }
    const start = current.startDate.toDate();
    const end = current.endDate.toDate();
    const days = bookingDays(start, end);
    if (nextStatus === "completed" && end.getTime() > Date.now()) {
      throw new functions.https.HttpsError("failed-precondition", "The booking has not ended.");
    }
    const keys = dateKeys(start, days);
    const slotRefs = keys.map((day) =>
      db.collection("peer_booking_slots").doc(stableHash(`${current.listingId}:${day}`)),
    );
    let slots = [];
    if (nextStatus === "confirmed" ||
        (current.status === "confirmed" && nextStatus === "cancelled")) {
      slots = await transaction.getAll(...slotRefs);
    }
    if (nextStatus === "confirmed") {
      if (slots.some((slot) => slot.exists && slot.data().bookingId !== bookingId)) {
        throw new functions.https.HttpsError("already-exists", "These dates are no longer available.");
      }
      slotRefs.forEach((slotRef, index) => transaction.set(slotRef, {
        bookingId,
        listingId: current.listingId,
        guestId: current.guestId,
        hostId: current.hostId,
        day: keys[index],
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      }));
    } else if (current.status === "confirmed" && nextStatus === "cancelled") {
      slots.forEach((slot, index) => {
        if (slot.exists && slot.data().bookingId === bookingId) transaction.delete(slotRefs[index]);
      });
    }
    transaction.update(bookingRef, {
      status: nextStatus,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      [`${nextStatus}At`]: admin.firestore.FieldValue.serverTimestamp(),
    });
  });
  return {bookingId, status: nextStatus};
});
