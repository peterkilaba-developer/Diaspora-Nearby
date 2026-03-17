/**
 * Proximity Alerts module.
 */
const { functions, admin, db, sendPushToUser } = require("./shared");

// Distance calculation helper (Haversine formula)
function calculateDistanceInMiles(lat1, lon1, lat2, lon2) {
  const R = 3958.8; // Radius of Earth in miles
  const dLat = (lat2 - lat1) * (Math.PI / 180);
  const dLon = (lon2 - lon1) * (Math.PI / 180);
  const a =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos(lat1 * (Math.PI / 180)) *
    Math.cos(lat2 * (Math.PI / 180)) *
    Math.sin(dLon / 2) * Math.sin(dLon / 2);
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  return R * c;
}

/**
 * ==================================================================
 * 1. PROXIMITY ALERTS
 * ==================================================================
 * [SCALABILITY FIX] Uses lat/lng bounding box to pre-filter the Firestore
 * query instead of downloading ALL users from the same country.
 * At 1M users this reduces reads from 400K+ to ~50-200 per invocation.
 *
 * Also adds:
 * - Minimum 0.5-mile movement threshold (avoids re-checks on GPS drift)
 * - 5-minute cooldown per user (avoids rapid-fire invocations)
 *
 * [FIX] Added separate onCreate handler for new user profiles to ensure
 * proximity checks run when a user first signs up.
 */

// In-memory cooldown tracker for proximity checks (persists within warm instances)
const _proximityCooldowns = new Map();
const PROXIMITY_COOLDOWN_MS = 5 * 60 * 1000; // 5 minutes

/**
 * Core proximity check logic — shared between onCreate and onUpdate triggers.
 * @param {string} userId - The user who moved / was created
 * @param {object} userData - The user's Firestore document data
 * @param {object|null} oldLoc - Previous currentLocation (null for new users)
 * @param {boolean} isNewUser - Whether this is a brand-new user (onCreate)
 */
async function runProximityCheck(userId, userData, oldLoc, isNewUser) {
  const newLoc = userData.currentLocation;

  // 1. Validate Location exists
  if (!newLoc || !newLoc.geometry) {
    console.log(`[Proximity] User ${userId}: No currentLocation.geometry — skipping.`);
    return null;
  }

  const currentLat = newLoc.geometry.location.lat;
  const currentLng = newLoc.geometry.location.lng;

  if (currentLat === undefined || currentLng === undefined) {
    console.log(`[Proximity] User ${userId}: Missing lat/lng — skipping.`);
    return null;
  }

  // 2. Skip if location hasn't changed (only for updates, not new users)
  if (!isNewUser && oldLoc && oldLoc.geometry &&
    oldLoc.geometry.location.lat === currentLat &&
    oldLoc.geometry.location.lng === currentLng) {
    // Silent skip — this fires on every non-location user doc update
    return null;
  }

  // 3. Skip micro-movements (only for updates with a previous location)
  if (!isNewUser && oldLoc && oldLoc.geometry) {
    const movedDistance = calculateDistanceInMiles(
      oldLoc.geometry.location.lat, oldLoc.geometry.location.lng,
      currentLat, currentLng
    );
    if (movedDistance < 0.5) {
      return null; // GPS drift, not a real move
    }
  }

  // 4. Cooldown: skip if this user was checked recently (within same warm instance)
  const lastCheck = _proximityCooldowns.get(userId);
  if (lastCheck && (Date.now() - lastCheck) < PROXIMITY_COOLDOWN_MS) {
    console.log(`[Proximity] User ${userId}: Cooldown active — skipping.`);
    return null;
  }
  _proximityCooldowns.set(userId, Date.now());

  const currentCity = newLoc.city || "Unknown";
  const homeCountryCode = userData.homeCountryCode;
  const firstName = userData.firstName || "Someone";

  if (!homeCountryCode) {
    console.log(`[Proximity] User ${userId}: No homeCountryCode — skipping.`);
    return null;
  }

  console.log(`[Proximity] User ${userId} (${firstName}) ${isNewUser ? "JOINED" : "moved"} in ${currentCity}. Checking for nearby compatriots...`);

  // 5. Geo-bounded query instead of full-country scan
  const DEGREE_BOUND = 1.5;
  const latMin = currentLat - DEGREE_BOUND;
  const latMax = currentLat + DEGREE_BOUND;
  const lngMin = currentLng - DEGREE_BOUND;
  const lngMax = currentLng + DEGREE_BOUND;

  const snapshot = await db
    .collection("users")
    .where("homeCountryCode", "==", homeCountryCode)
    .where("currentLocation.geometry.location.lat", ">=", latMin)
    .where("currentLocation.geometry.location.lat", "<=", latMax)
    .limit(500)
    .get();

  console.log(`[Proximity] Found ${snapshot.size} nearby candidates from ${homeCountryCode} (geo-bounded)`);

  const homeCountry = userData.homeCountry || homeCountryCode;
  const promises = [];

  snapshot.forEach((doc) => {
    if (doc.id === userId) return;

    const otherData = doc.data();
    const otherLoc = otherData.currentLocation;

    if (!otherLoc || !otherLoc.geometry) return;

    const otherLat = otherLoc.geometry.location.lat;
    const otherLng = otherLoc.geometry.location.lng;

    // In-memory longitude filter (Firestore can't do range on 2 fields)
    if (otherLng < lngMin || otherLng > lngMax) return;

    const otherCity = otherLoc.city || "Unknown";

    // Calculate Distance (precise Haversine)
    const distance = calculateDistanceInMiles(currentLat, currentLng, otherLat, otherLng);

    // Threshold: 100 Miles
    if (distance <= 100) {
      const otherCountry = otherData.homeCountry || homeCountryCode;
      promises.push(handleProximityMatch(userId, doc.id, firstName, otherData.firstName, currentCity, homeCountryCode, distance, homeCountry, otherCountry));
    }
  });

  if (promises.length === 0) {
    console.log(`[Proximity] No matches within 100 miles for ${firstName} in ${currentCity}.`);
  }

  await Promise.all(promises);
  return null;
}

/**
 * Trigger: User document UPDATED (location change, etc.)
 */
exports.checkProximity = functions.firestore
  .document("users/{userId}")
  .onUpdate(async (change, context) => {
    const userId = context.params.userId;
    const beforeData = change.before.data();
    const afterData = change.after.data();
    const oldLoc = beforeData.currentLocation;

    return runProximityCheck(userId, afterData, oldLoc, false);
  });

/**
 * Trigger: User document CREATED (new user signup)
 * This ensures proximity notifications fire for brand-new users who
 * haven't triggered an onUpdate yet.
 */
exports.checkProximityOnCreate = functions.firestore
  .document("users/{userId}")
  .onCreate(async (snap, context) => {
    const userId = context.params.userId;
    const userData = snap.data();

    console.log(`[Proximity] New user created: ${userId} (${userData.firstName || "Unknown"})`);

    return runProximityCheck(userId, userData, null, true);
  });

async function handleProximityMatch(userAId, userBId, nameA, nameB, city, homeCountryCode, distance, countryA, countryB) {
  // Sort IDs to ensure consistent document key
  const [id1, id2] = [userAId, userBId].sort();
  const historyDocId = `${id1}_${id2}`;

  const historyRef = db.collection("proximity_history").doc(historyDocId);

  await db.runTransaction(async (t) => {
    const historyDoc = await t.get(historyRef);
    let shouldNotify = true;

    if (historyDoc.exists) {
      const data = historyDoc.data();
      const lastMetCity = data.lastMetCity;

      if (lastMetCity === city) {
        console.log(`[Proximity] Suppressed alert for ${userAId} & ${userBId}. Already met in ${city}.`);
        shouldNotify = false;
      }
    }

    if (shouldNotify) {
      console.log(`[Proximity] NEW MATCH! ${nameA} & ${nameB} in ${city}. Sending Alerts.`);

      t.set(historyRef, {
        users: [id1, id2],
        lastMetCity: city,
        lastMetTime: admin.firestore.FieldValue.serverTimestamp(),
        homeCountryCode: homeCountryCode
      });
    }
    return shouldNotify;
  }).then(async (shouldNotify) => {
    if (shouldNotify) {
      // Format distance
      const distStr = distance.toFixed(1) + " miles";

      await sendPushToUser(userAId, {
        title: "Diaspora Nearby!",
        body: `${nameB} from ${countryB} is nearby in ${city}: ${distStr} Away. Connect now`,
        type: "nearby_compatriot",
        targetUserId: userBId,
        city: city
      });

      await sendPushToUser(userBId, {
        title: "Diaspora Nearby!",
        body: `${nameA} from ${countryA} is nearby in ${city}: ${distStr} Away. Connect now`,
        type: "nearby_compatriot",
        targetUserId: userAId,
        city: city
      });
    }
  }).catch(e => {
    console.error("Transaction failure", e);
  });
}
