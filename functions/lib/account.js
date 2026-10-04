/** Privacy-preserving, server-side account erasure workflow. */
const { functions, admin, db } = require("./shared");
const { requireAuth, requireAppCheck, stableHash } = require("./security");

async function deleteQuery(query) {
  let count = 0;
  while (true) {
    const snapshot = await query.limit(400).get();
    if (snapshot.empty) return count;
    const writer = db.bulkWriter();
    for (const document of snapshot.docs) writer.delete(document.ref);
    await writer.close();
    count += snapshot.size;
  }
}

async function anonymizeQuery(query, fields, tombstone) {
  let count = 0;
  while (true) {
    const snapshot = await query.limit(400).get();
    if (snapshot.empty) return count;
    const writer = db.bulkWriter();
    for (const document of snapshot.docs) {
      const updates = {
        anonymizedAt: admin.firestore.FieldValue.serverTimestamp(),
      };
      for (const field of fields) updates[field] = tombstone;
      writer.update(document.ref, updates);
    }
    await writer.close();
    count += snapshot.size;
  }
}

async function anonymizeMessages(uid, tombstone) {
  let count = 0;
  const storagePaths = new Set();
  while (true) {
    const snapshot = await db.collectionGroup("messages")
        .where("senderId", "==", uid).limit(400).get();
    if (snapshot.empty) return {count, storagePaths: [...storagePaths]};
    const writer = db.bulkWriter();
    for (const document of snapshot.docs) {
      const data = document.data();
      if (typeof data.storagePath === "string") storagePaths.add(data.storagePath);
      for (const field of ["imageUrl", "documentUrl"]) {
        const value = data[field];
        if (typeof value !== "string") continue;
        const match = value.match(/\/o\/([^?]+)/);
        if (match) storagePaths.add(decodeURIComponent(match[1]));
      }
      writer.update(document.ref, {
        senderId: tombstone,
        senderName: "Deleted user",
        senderImage: admin.firestore.FieldValue.delete(),
        senderHostCountryCode: admin.firestore.FieldValue.delete(),
        senderHomeCountryCode: admin.firestore.FieldValue.delete(),
        adminId: admin.firestore.FieldValue.delete(),
        adminImage: admin.firestore.FieldValue.delete(),
        imageUrl: admin.firestore.FieldValue.delete(),
        documentUrl: admin.firestore.FieldValue.delete(),
        storagePath: admin.firestore.FieldValue.delete(),
        anonymizedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }
    await writer.close();
    count += snapshot.size;
  }
}

async function removeFromArrays(collection, uid, fields) {
  let count = 0;
  while (true) {
    const snapshots = await Promise.all(fields.map((field) =>
      db.collection(collection).where(field, "array-contains", uid).limit(400).get()));
    const documents = new Map();
    for (const snapshot of snapshots) {
      for (const document of snapshot.docs) documents.set(document.ref.path, document);
    }
    if (documents.size === 0) return count;
    const writer = db.bulkWriter();
    for (const document of documents.values()) {
      const updates = { updatedAt: admin.firestore.FieldValue.serverTimestamp() };
      for (const field of fields) {
        const values = document.data()[field];
        if (Array.isArray(values) && values.includes(uid)) {
          updates[field] = admin.firestore.FieldValue.arrayRemove(uid);
        }
      }
      writer.update(document.ref, updates);
    }
    await writer.close();
    count += documents.size;
  }
}

exports.deleteMyAccount = functions
  .runWith({
    timeoutSeconds: 540,
    memory: "1GB",
    secrets: ["STRIPE_SECRET_KEY"],
  })
  .https.onCall(async (data, context) => {
    requireAppCheck(context);
    const uid = requireAuth(context);
    const authTimeSeconds = Number(context.auth.token.auth_time || 0);
    if (Date.now() / 1000 - authTimeSeconds > 5 * 60) {
      throw new functions.https.HttpsError(
          "unauthenticated",
          "Please sign in again before deleting your account.",
      );
    }
    if (!data || data.confirm !== true) {
      throw new functions.https.HttpsError(
          "failed-precondition",
          "Explicit deletion confirmation is required.",
      );
    }

    const tombstone = `deleted-${stableHash(uid).slice(0, 24)}`;
    const stripeRef = db.collection("stripe_customers").doc(uid);
    const stripeSnapshot = await stripeRef.get();
    if (stripeSnapshot.exists && stripeSnapshot.data().customerId &&
        process.env.STRIPE_SECRET_KEY) {
      try {
        const stripe = require("stripe")(process.env.STRIPE_SECRET_KEY);
        await stripe.customers.del(stripeSnapshot.data().customerId);
      } catch (error) {
        console.error("Stripe customer deletion failed", error);
        throw new functions.https.HttpsError(
            "unavailable",
            "Account deletion could not be completed. Please retry.",
        );
      }
    }

    const messages = await anonymizeMessages(uid, tombstone);
    await Promise.all([
      deleteQuery(db.collection("event_attendance_history").where("userId", "==", uid)),
      deleteQuery(db.collectionGroup("views").where("userId", "==", uid)),
      deleteQuery(db.collectionGroup("saved_by").where("userId", "==", uid)),
      deleteQuery(db.collectionGroup("relationships").where("id", "==", uid)),
      deleteQuery(db.collectionGroup("blocked").where("blockedId", "==", uid)),
      deleteQuery(db.collection("direct_chat_pairs").where("users", "array-contains", uid)),
    ]);
    await Promise.all([
      anonymizeQuery(
          db.collection("points_transactions").where("userId", "==", uid),
          ["userId"],
          tombstone,
      ),
      anonymizeQuery(
          db.collection("gdp_transactions").where("actorUid", "==", uid),
          ["actorUid"],
          tombstone,
      ),
      anonymizeQuery(
          db.collection("stripe_webhook_events").where("userId", "==", uid),
          ["userId"],
          tombstone,
      ),
    ]);
    await Promise.all([
      removeFromArrays("chats", uid, ["participants", "admins"]),
      removeFromArrays("communities", uid, ["members", "memberIds", "admins"]),
      removeFromArrays("organizations", uid, ["members", "followers", "admins"]),
      removeFromArrays("hosting_requests", uid, ["interestedHostIds"]),
      removeFromArrays("user_private", uid, ["blockedUsers"]),
    ]);

    const ownedQueries = [
      ["relationship_requests", "fromUserId"],
      ["relationship_requests", "toUserId"],
      ["trust_ratings", "fromUserId"],
      ["trust_ratings", "toUserId"],
      ["vouches", "fromUserId"],
      ["vouches", "toUserId"],
      ["qr_exchanges", "fromUid"],
      ["qr_exchanges", "toUid"],
      ["reports", "reporterId"],
      ["hosting_requests", "travelerId"],
      ["hosting_sessions", "travelerId"],
      ["hosting_sessions", "hostId"],
      ["hosting_checkin_challenges", "hostId"],
      ["peer_bookings", "guestId"],
      ["peer_bookings", "hostId"],
      ["peer_booking_slots", "guestId"],
      ["peer_booking_slots", "hostId"],
      ["flight_bookings", "userId"],
      ["leadershipRequests", "userId"],
    ];
    for (const [collection, field] of ownedQueries) {
      await deleteQuery(db.collection(collection).where(field, "==", uid));
    }

    const directDocuments = [
      "user_private", "user_points", "trust_data", "trust_scores", "stripe_customers",
      "bereavement_memberships", "emergency_fund_memberships",
      "emergency_fund_stakers", "emergency_fund_interest",
    ];
    await Promise.all(directDocuments.map((collection) =>
      db.collection(collection).doc(uid).delete()));

    const userRef = db.collection("users").doc(uid);
    await db.recursiveDelete(db.collection("user_blocks").doc(uid));
    await db.recursiveDelete(userRef);
    await Promise.all(messages.storagePaths.map((path) =>
      admin.storage().bucket().file(path).delete({ignoreNotFound: true})));
    await admin.storage().bucket().deleteFiles({
      prefix: `profile_photos/${uid}/`,
    });
    await admin.auth().deleteUser(uid);
    return { success: true };
  });
