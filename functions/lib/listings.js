/** Server-authoritative listing engagement counters. */
const { functions, admin, db } = require("./shared");
const {
  requireAuth,
  requireAppCheck,
  consumeRateLimit,
} = require("./security");

const LISTING_TYPES = Object.freeze({
  marketplace: { collection: "marketplace_listings", ownerField: "sellerId" },
  peer: { collection: "peer_listings", ownerField: "ownerId" },
  real_estate: { collection: "real_estate_listings", ownerField: "ownerId" },
});

function listingSpec(data) {
  const type = data && data.listingType;
  const listingId = data && data.listingId;
  const spec = LISTING_TYPES[type];
  if (!spec || typeof listingId !== "string" ||
      !/^[A-Za-z0-9_-]{1,256}$/.test(listingId)) {
    throw new functions.https.HttpsError(
        "invalid-argument",
        "A valid listing type and listingId are required.",
    );
  }
  return { ...spec, type, listingId };
}

exports.recordListingView = functions.https.onCall(async (data, context) => {
  requireAppCheck(context);
  const uid = requireAuth(context);
  const spec = listingSpec(data);
  await consumeRateLimit("listing-view", uid, 300, 60 * 60 * 1000);

  const listingRef = db.collection(spec.collection).doc(spec.listingId);
  const viewRef = listingRef.collection("views").doc(uid);
  const counted = await db.runTransaction(async (transaction) => {
    const [listing, existingView] = await Promise.all([
      transaction.get(listingRef),
      transaction.get(viewRef),
    ]);
    if (!listing.exists) {
      throw new functions.https.HttpsError("not-found", "Listing not found.");
    }
    // Owners may preview their listing, but previews are not engagement.
    if (listing.data()[spec.ownerField] === uid || existingView.exists) return false;
    const country = typeof data.country === "string" ? data.country.trim().slice(0, 100) : null;
    const countryCode = typeof data.countryCode === "string" ?
      data.countryCode.trim().toUpperCase().slice(0, 3) : null;
    transaction.create(viewRef, {
      userId: uid,
      ...(country && { country }),
      ...(countryCode && { countryCode }),
      viewedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    transaction.update(listingRef, {
      viewCount: admin.firestore.FieldValue.increment(1),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return true;
  });
  return { success: true, counted };
});

exports.setListingSaved = functions.https.onCall(async (data, context) => {
  requireAppCheck(context);
  const uid = requireAuth(context);
  const spec = listingSpec(data);
  if (typeof data.saved !== "boolean") {
    throw new functions.https.HttpsError("invalid-argument", "saved must be boolean.");
  }
  await consumeRateLimit("listing-save", uid, 120, 60 * 60 * 1000);

  const listingRef = db.collection(spec.collection).doc(spec.listingId);
  const savedRef = listingRef.collection("saved_by").doc(uid);
  const changed = await db.runTransaction(async (transaction) => {
    const [listing, existingSave] = await Promise.all([
      transaction.get(listingRef),
      transaction.get(savedRef),
    ]);
    if (!listing.exists) {
      throw new functions.https.HttpsError("not-found", "Listing not found.");
    }
    if (data.saved === existingSave.exists) return false;
    if (data.saved) {
      transaction.create(savedRef, {
        userId: uid,
        savedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    } else {
      transaction.delete(savedRef);
    }
    const current = Number(listing.data().savedCount || 0);
    transaction.update(listingRef, {
      savedCount: Math.max(0, current + (data.saved ? 1 : -1)),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return true;
  });
  return { success: true, changed };
});
