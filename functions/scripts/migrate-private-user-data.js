#!/usr/bin/env node
/**
 * One-time migration: move PII and exact locations out of public user docs.
 * Run with GOOGLE_APPLICATION_CREDENTIALS against each environment, inspect
 * with --dry-run first, then rerun with --apply.
 */
const admin = require("firebase-admin");
const { geohashForLocation } = require("geofire-common");

admin.initializeApp();
const db = admin.firestore();
const APPLY = process.argv.includes("--apply");
const PRIVATE_FIELDS = [
  "phone", "dateOfBirth", "currentLocation", "geo", "workLocation",
  "pastLocations", "fcmToken", "fcmTokenUpdatedAt", "fcmTopics",
  "fcmTopicsUpdatedAt", "notificationsEnabled", "blockedUsers",
];

function publicLocation(value) {
  if (!value || typeof value !== "object") return null;
  const city = value.city || null;
  const state = value.state || null;
  const country = value.country || null;
  return {
    formatted_address: [city, state, country].filter(Boolean).join(", "),
    place_id: "",
    city,
    state,
    country,
    country_code: value.country_code || value.countryCode || null,
  };
}

async function main() {
  let cursor = null;
  let scanned = 0;
  let migrated = 0;
  do {
    let query = db.collection("users").orderBy(admin.firestore.FieldPath.documentId()).limit(250);
    if (cursor) query = query.startAfter(cursor);
    const snapshot = await query.get();
    if (snapshot.empty) break;
    const writer = db.bulkWriter();
    for (const document of snapshot.docs) {
      scanned++;
      const data = document.data();
      const privateData = {};
      const publicUpdates = {};
      privateData.securityMigrationVersion = 1;
      for (const field of PRIVATE_FIELDS) {
        if (Object.prototype.hasOwnProperty.call(data, field)) {
          privateData[field] = data[field];
          publicUpdates[field] = admin.firestore.FieldValue.delete();
        }
      }
      for (const field of ["homeLocation", "hostLocation"]) {
        if (data[field] && (data[field].geometry || data[field].place_id)) {
          privateData[field] = data[field];
          publicUpdates[field] = publicLocation(data[field]);
        }
      }
      if (data.businessProfile && data.businessProfile.taxId) {
        privateData.businessProfile = data.businessProfile;
        publicUpdates.businessProfile = {...data.businessProfile};
        delete publicUpdates.businessProfile.taxId;
      }
      if (data.currentLocation && data.showCurrentLocationName === true) {
        const summary = publicLocation(data.currentLocation);
        publicUpdates.currentCity = summary.city;
        publicUpdates.currentState = summary.state;
        publicUpdates.currentCountryCode = summary.country_code;
      }
      const point = data.currentLocation && data.currentLocation.geometry &&
        data.currentLocation.geometry.location;
      if (!privateData.geo && point && Number.isFinite(Number(point.lat)) &&
          Number.isFinite(Number(point.lng))) {
        const latitude = Number(point.lat);
        const longitude = Number(point.lng);
        privateData.geo = {
          geohash: geohashForLocation([latitude, longitude]),
          geopoint: new admin.firestore.GeoPoint(latitude, longitude),
        };
      }
      if (Object.keys(privateData).length > 0) {
        migrated++;
        if (APPLY) {
          writer.set(db.collection("user_private").doc(document.id), privateData, { merge: true });
          if (Object.keys(publicUpdates).length > 0) {
            writer.update(document.ref, publicUpdates);
          }
        }
      }
    }
    await writer.close();
    cursor = snapshot.docs[snapshot.docs.length - 1];
    if (snapshot.size < 250) break;
  } while (true);
  console.log(JSON.stringify({ apply: APPLY, scanned, migrated }));
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
