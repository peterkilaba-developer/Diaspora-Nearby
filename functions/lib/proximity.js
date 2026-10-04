/**
 * Proximity Alerts module.
 *
 * UX-tuned pipeline:
 *   1. Pre-filter on real movement (>= 0.5 mi) and persistent cooldown.
 *   2. Geo-bounded Firestore query (lat range + in-memory lng range).
 *   3. Per-pair dedup is time-based (14d) AND geo-based (~3 mi) rather than
 *      city-string-based, so suburb drift doesn't re-spam and long-ago meets
 *      eventually re-notify.
 *   4. Block-list + master-notifications-toggle + missing-name + missing-token
 *      filtering happens BEFORE we count matches.
 *   5. Hard cap of TOP_N closest matches per event — landing in a dense
 *      diaspora city no longer fires 80 simultaneous pushes.
 *   6. Quiet hours (22:00–08:00 local, longitude-derived) defer alerts: we
 *      still record the meet so we don't spam at sunrise.
 *   7. Android collapse key + APNs thread-id so the tray groups them.
 */
const { functions, admin, db, sendPushToUser } = require("./shared");
const { requireAuth, requireAppCheck, consumeRateLimit } = require("./security");
const { geohashQueryBounds } = require("geofire-common");

// ─── Tunables ────────────────────────────────────────────────────────────────
const RADIUS_MILES = 25;             // "nearby" = same metro, not same state
const MIN_MOVE_MILES = 0.5;          // ignore GPS drift
const COOLDOWN_MS = 5 * 60 * 1000;   // per-user, persistent
const PAIR_REDEDUP_MS = 14 * 24 * 60 * 60 * 1000; // 14d before same pair re-alerts
const PAIR_REDEDUP_MILES = 3;        // OR moved >3mi from lastMet location
const TOP_N = 3;                     // max pushes fanned out per event
const QUIET_HOUR_START = 22;         // 10pm local
const QUIET_HOUR_END = 8;            // 8am local

// In-memory cooldown is a hot-path cache; Firestore is the source of truth.
const _proximityCooldowns = new Map();

function calculateDistanceInMiles(lat1, lon1, lat2, lon2) {
    const R = 3958.8;
    const dLat = (lat2 - lat1) * (Math.PI / 180);
    const dLon = (lon2 - lon1) * (Math.PI / 180);
    const a =
        Math.sin(dLat / 2) ** 2 +
        Math.cos(lat1 * (Math.PI / 180)) *
        Math.cos(lat2 * (Math.PI / 180)) *
        Math.sin(dLon / 2) ** 2;
    return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

// Rough UTC offset from longitude (±1h is fine for "don't ping at 3am").
function localHourFromLng(lng, nowMs) {
    const offsetHours = Math.round(lng / 15);
    const local = new Date(nowMs + offsetHours * 3600 * 1000);
    return local.getUTCHours();
}

function isQuietHour(lng, nowMs = Date.now()) {
    const h = localHourFromLng(lng, nowMs);
    return h >= QUIET_HOUR_START || h < QUIET_HOUR_END;
}

exports.findNearbyUsers = functions.https.onCall(async (data, context) => {
    requireAppCheck(context);
    const uid = requireAuth(context);
    await consumeRateLimit("nearby-search", uid, 120, 60 * 60 * 1000);
    const radiusKm = Math.min(Math.max(Number(data && data.radiusKm) || 50, 1), 100);
    const limit = Math.min(Math.max(Number(data && data.limit) || 50, 1), 100);
    const [privateSnapshot, callerProfile] = await Promise.all([
        db.collection("user_private").doc(uid).get(),
        db.collection("users").doc(uid).get(),
    ]);
    const excluded = new Set([
        uid,
        ...(privateSnapshot.exists ? privateSnapshot.data().blockedUsers || [] : []),
        ...(Array.isArray(data && data.excludeUserIds) ?
            data.excludeUserIds.slice(0, 100).filter(validUid) : []),
    ]);
    if (data && data.global === true) {
        const globalSnapshot = await db.collection("users")
            .orderBy("firstName").limit(limit * 3).get();
        const users = globalSnapshot.docs
            .filter((profile) => !excluded.has(profile.id))
            .slice(0, limit)
            .map((profile) => publicProfile(profile));
        return { users };
    }
    const location = privateSnapshot.exists ? privateSnapshot.data().currentLocation : null;
    if (!location || !location.geometry || !location.geometry.location) {
        throw new functions.https.HttpsError(
            "failed-precondition",
            "Location is required for nearby discovery.",
        );
    }
    const latitude = Number(location.geometry.location.lat);
    const longitude = Number(location.geometry.location.lng);
    const bounds = geohashQueryBounds([latitude, longitude], radiusKm * 1000);
    const snapshots = await Promise.all(bounds.map((bound) =>
        db.collection("user_private")
            .orderBy("geo.geohash")
            .startAt(bound[0])
            .endAt(bound[1])
            .limit(150)
            .get()));
    const candidateDocs = new Map();
    for (const snapshot of snapshots) {
        for (const document of snapshot.docs) candidateDocs.set(document.id, document);
    }
    const ranked = [];
    for (const document of candidateDocs.values()) {
        if (excluded.has(document.id)) continue;
        const candidateLocation = document.data().currentLocation;
        if (!candidateLocation || !candidateLocation.geometry) continue;
        const point = candidateLocation.geometry.location;
        const distanceMiles = calculateDistanceInMiles(
            latitude, longitude, Number(point.lat), Number(point.lng),
        );
        const distanceKm = distanceMiles * 1.609344;
        if (distanceKm <= radiusKm) ranked.push({ id: document.id, distanceKm });
    }
    ranked.sort((left, right) => left.distanceKm - right.distanceKm);
    const selected = ranked.slice(0, limit);
    if (selected.length === 0) return { users: [] };
    const profiles = await db.getAll(...selected.map((item) =>
        db.collection("users").doc(item.id)));
    const distances = new Map(selected.map((item) => [item.id, item.distanceKm]));
    const homeCountryCode = callerProfile.exists ?
        callerProfile.data().homeCountryCode : null;
    const users = [];
    for (const profile of profiles) {
        if (!profile.exists || (homeCountryCode &&
            profile.data().homeCountryCode !== homeCountryCode)) continue;
        const otherPrivate = candidateDocs.get(profile.id);
        if (otherPrivate && (otherPrivate.data().blockedUsers || []).includes(uid)) continue;
        users.push(publicProfile(profile, distances.get(profile.id)));
    }
    return { users: users.slice(0, limit) };
});

function validUid(value) {
    return typeof value === "string" && value.length > 0 && value.length <= 128;
}

function publicProfile(document, distance) {
    const data = document.data();
    const allowed = [
        "firstName", "lastName", "profilePhoto", "bio", "interests",
        "occupation", "education", "languages", "socialLinks",
        "homeLocation", "hostLocation", "homeCountry", "hostCountry",
        "homeCountryCode", "hostCountryCode", "profession", "industry",
        "yearsInHostCountry", "servicesOffered", "lookingFor",
        "availability", "meetingPreferences", "showCurrentLocationName",
        "currentCity", "currentState", "currentCountryCode",
    ];
    const result = {uid: document.id};
    for (const field of allowed) {
        if (data[field] !== undefined) result[field] = data[field];
    }
    if (Number.isFinite(distance)) result.distance = distance;
    return result;
}

exports.searchUsers = functions.https.onCall(async (data, context) => {
    requireAppCheck(context);
    const uid = requireAuth(context);
    await consumeRateLimit("profile-search", uid, 120, 60 * 60 * 1000);
    const raw = String(data && data.query || "").trim();
    if (raw.length < 2 || raw.length > 80) {
        throw new functions.https.HttpsError("invalid-argument", "Enter at least two characters.");
    }
    const prefix = raw[0].toUpperCase() + raw.slice(1);
    const [firstNames, lastNames, callerPrivate] = await Promise.all([
        db.collection("users").where("firstName", ">=", prefix)
            .where("firstName", "<", `${prefix}\uf8ff`).limit(25).get(),
        db.collection("users").where("lastName", ">=", prefix)
            .where("lastName", "<", `${prefix}\uf8ff`).limit(25).get(),
        db.collection("user_private").doc(uid).get(),
    ]);
    const blocked = new Set(callerPrivate.exists ?
        callerPrivate.data().blockedUsers || [] : []);
    const matches = new Map();
    for (const profile of [...firstNames.docs, ...lastNames.docs]) {
        if (profile.id !== uid && !blocked.has(profile.id)) matches.set(profile.id, profile);
    }
    const privateMatches = matches.size === 0 ? [] : await db.getAll(
        ...[...matches.keys()].map((id) => db.collection("user_private").doc(id)),
    );
    const blockedCaller = new Set(privateMatches
        .filter((profile) => profile.exists &&
            (profile.data().blockedUsers || []).includes(uid))
        .map((profile) => profile.id));
    return {
        users: [...matches.values()]
            .filter((profile) => !blockedCaller.has(profile.id))
            .slice(0, 25)
            .map((profile) => publicProfile(profile)),
    };
});

function hasUsableName(data) {
    const n = (data && data.firstName) ? String(data.firstName).trim() : "";
    return n.length > 0 && n.toLowerCase() !== "unknown";
}

function locationDisplayName(loc, fallback = "your area") {
    const city = loc && loc.city ? String(loc.city).trim() : "";
    if (city) return city;

    const formatted = loc && (loc.formatted_address || loc.formattedAddress)
        ? String(loc.formatted_address || loc.formattedAddress).trim()
        : "";
    if (!formatted) return fallback;

    const firstPart = formatted.split(",")[0].trim();
    if (!firstPart) return fallback;

    // Avoid showing raw GPS coordinates as a city name.
    if (/^[+-]?\d+(\.\d+)?$/.test(firstPart)) return fallback;

    return firstPart;
}

async function runProximityCheck(userId, userData, oldLoc, isNewUser) {
    const newLoc = userData.currentLocation;
    if (!newLoc || !newLoc.geometry) return null;

    const currentLat = newLoc.geometry.location.lat;
    const currentLng = newLoc.geometry.location.lng;
    if (currentLat === undefined || currentLng === undefined) return null;

    // Gate: only notify users who finished onboarding (have a name).
    if (!hasUsableName(userData)) {
        console.log(`[Proximity] User ${userId}: name not set — skipping.`);
        return null;
    }

    // Same coordinates → silent skip.
    if (!isNewUser && oldLoc && oldLoc.geometry &&
        oldLoc.geometry.location.lat === currentLat &&
        oldLoc.geometry.location.lng === currentLng) {
        return null;
    }

    // Micro-movement (GPS drift).
    if (!isNewUser && oldLoc && oldLoc.geometry) {
        const moved = calculateDistanceInMiles(
            oldLoc.geometry.location.lat, oldLoc.geometry.location.lng,
            currentLat, currentLng
        );
        if (moved < MIN_MOVE_MILES) return null;
    }

    // Warm-instance cooldown (cheap).
    const lastCheckLocal = _proximityCooldowns.get(userId);
    if (lastCheckLocal && (Date.now() - lastCheckLocal) < COOLDOWN_MS) return null;

    // Persistent cooldown (survives cold start / parallel instances).
    const lastCheckAt = userData.lastProximityCheckAt;
    if (lastCheckAt && lastCheckAt.toMillis &&
        (Date.now() - lastCheckAt.toMillis()) < COOLDOWN_MS) {
        console.log(`[Proximity] User ${userId}: persistent cooldown — skipping.`);
        _proximityCooldowns.set(userId, lastCheckAt.toMillis());
        return null;
    }

    const homeCountryCode = userData.homeCountryCode;
    if (!homeCountryCode) return null;

    _proximityCooldowns.set(userId, Date.now());
    await db.collection("user_private").doc(userId).update({
        lastProximityCheckAt: admin.firestore.FieldValue.serverTimestamp(),
    }).catch(e => console.warn(`[Proximity] cooldown write failed: ${e.message}`));

    const currentCity = locationDisplayName(newLoc);
    const firstName = userData.firstName;
    const blockedByMover = new Set(userData.blockedUsers || []);
    const homeCountry = userData.homeCountry || homeCountryCode;

    console.log(`[Proximity] Location changed for ${userId}; scanning nearby users.`);

    const bounds = geohashQueryBounds(
        [Number(currentLat), Number(currentLng)],
        RADIUS_MILES * 1609.344,
    );
    const snapshots = await Promise.all(bounds.map((bound) =>
        db.collection("user_private")
            .orderBy("geo.geohash")
            .startAt(bound[0])
            .endAt(bound[1])
            .limit(150)
            .get()));
    const privateDocuments = new Map();
    for (const snapshot of snapshots) {
        for (const document of snapshot.docs) {
            privateDocuments.set(document.id, document);
        }
    }

    // Build candidate list with distance, then rank.
    const candidates = [];
    const publicSnapshots = privateDocuments.size === 0 ? [] : await db.getAll(
        ...[...privateDocuments.keys()].map((id) => db.collection("users").doc(id)),
    );
    const publicById = new Map(publicSnapshots.map((doc) => [doc.id, doc]));
    for (const doc of privateDocuments.values()) {
        if (doc.id === userId) continue;
        const publicProfile = publicById.get(doc.id);
        if (!publicProfile.exists ||
            publicProfile.data().homeCountryCode !== homeCountryCode) continue;
        const other = {...publicProfile.data(), ...doc.data()};

        // Mutual block check.
        if (blockedByMover.has(doc.id)) continue;
        if ((other.blockedUsers || []).includes(userId)) continue;

        // Honor master notifications toggle + token availability.
        if (other.notificationsEnabled === false) continue;
        if (!other.fcmToken) continue;
        if (!hasUsableName(other)) continue;
        if (other.isBanned === true) continue;

        const oLoc = other.currentLocation;
        if (!oLoc || !oLoc.geometry) continue;
        const oLat = oLoc.geometry.location.lat;
        const oLng = oLoc.geometry.location.lng;
        const distance = calculateDistanceInMiles(currentLat, currentLng, oLat, oLng);
        if (distance > RADIUS_MILES) continue;

        candidates.push({
            id: doc.id,
            data: other,
            distance,
            lat: oLat,
            lng: oLng,
            city: locationDisplayName(oLoc),
        });
    }

    candidates.sort((a, b) => a.distance - b.distance);

    if (candidates.length === 0) {
        console.log(`[Proximity] No nearby matches for ${userId}.`);
        return null;
    }

    const top = candidates.slice(0, TOP_N);
    console.log(`[Proximity] ${candidates.length} candidates; pushing top ${top.length}.`);

    await Promise.all(top.map(c => handleProximityMatch({
        moverId: userId,
        moverName: firstName,
        moverCountry: homeCountry,
        moverLat: currentLat,
        moverLng: currentLng,
        moverCity: currentCity,
        other: c,
        homeCountryCode,
    })));

    return null;
}

exports.checkProximity = functions.firestore
    .document("user_private/{userId}")
    .onUpdate(async (change, context) => {
        const userId = context.params.userId;
        const before = change.before.data();
        const after = change.after.data();

        // Don't loop on our own cooldown writes.
        const beforeStamp = before.lastProximityCheckAt && before.lastProximityCheckAt.toMillis
            ? before.lastProximityCheckAt.toMillis() : 0;
        const afterStamp = after.lastProximityCheckAt && after.lastProximityCheckAt.toMillis
            ? after.lastProximityCheckAt.toMillis() : 0;
        if (afterStamp !== beforeStamp &&
            JSON.stringify(before.currentLocation) === JSON.stringify(after.currentLocation)) {
            return null;
        }

        const profile = await db.collection("users").doc(userId).get();
        if (!profile.exists) return null;
        return runProximityCheck(
            userId,
            {...profile.data(), ...after},
            before.currentLocation,
            false,
        );
    });

exports.checkProximityOnCreate = functions.firestore
    .document("user_private/{userId}")
    .onCreate(async (snap, context) => {
        if (snap.data().securityMigrationVersion === 1) return null;
        const userId = context.params.userId;
        const profile = await db.collection("users").doc(userId).get();
        if (!profile.exists) return null;
        const userData = {...profile.data(), ...snap.data()};
        // Onboarding-incomplete docs are gated inside runProximityCheck.
        return runProximityCheck(userId, userData, null, true);
    });

function formatDistance(distance) {
    if (distance < 0.1) return "right next to you";
    if (distance < 1) return `${(distance * 5280).toFixed(0)} ft away`;
    return `${distance.toFixed(1)} mi away`;
}

async function handleProximityMatch({
    moverId, moverName, moverCountry, moverLat, moverLng, moverCity,
    other, homeCountryCode,
}) {
    const [id1, id2] = [moverId, other.id].sort();
    const historyRef = db.collection("proximity_history").doc(`${id1}_${id2}`);

    const shouldNotify = await db.runTransaction(async (t) => {
        const doc = await t.get(historyRef);
        const now = Date.now();

        if (doc.exists) {
            const d = doc.data();
            const lastTime = d.lastMetTime && d.lastMetTime.toMillis ? d.lastMetTime.toMillis() : 0;
            const lastLat = d.lastMetLat;
            const lastLng = d.lastMetLng;
            const withinWindow = lastTime && (now - lastTime) < PAIR_REDEDUP_MS;
            const closeToLast = (typeof lastLat === "number" && typeof lastLng === "number") &&
                calculateDistanceInMiles(lastLat, lastLng, moverLat, moverLng) < PAIR_REDEDUP_MILES;
            if (withinWindow && closeToLast) {
                console.log(`[Proximity] suppress ${moverId}↔${other.id}: met <14d ago within ${PAIR_REDEDUP_MILES}mi.`);
                return false;
            }
        }

        t.set(historyRef, {
            users: [id1, id2],
            lastMetCity: moverCity,
            lastMetLat: moverLat,
            lastMetLng: moverLng,
            lastMetTime: admin.firestore.FieldValue.serverTimestamp(),
            homeCountryCode,
        }, { merge: true });
        return true;
    }).catch(e => {
        console.error("[Proximity] dedup tx failed", e);
        return false;
    });

    if (!shouldNotify) return;

    // Quiet hours: record the meet (so we don't immediately re-fire later)
    // but skip the actual push. Foreground tab badges / inbox will still
    // reflect it via proximity_history on next app open.
    const moverQuiet = isQuietHour(moverLng);
    const otherQuiet = isQuietHour(other.lng);

    const distStr = formatDistance(other.distance);
    const otherCountry = other.data.homeCountry || homeCountryCode;
    const otherName = other.data.firstName;

    const pushes = [];
    if (!moverQuiet) {
        pushes.push(sendPushToUser(moverId, {
            // Name the OTHER person's city, not the recipient's — when the
            // recipient is travelling, their own city would wrongly imply
            // that's where the match is.
            title: `${otherName} from ${otherCountry} is nearby in ${other.city}`,
            body: `${distStr}. Tap to say hi.`,
            type: "nearby_compatriot",
            targetUserId: other.id,
            city: other.city,
            androidCollapseKey: "nearby_compatriot",
            androidTag: "nearby_compatriot",
            apnsThreadId: "nearby_compatriot",
        }));
    } else {
        console.log(`[Proximity] quiet hours for mover ${moverId} — push skipped.`);
    }

    if (!otherQuiet) {
        pushes.push(sendPushToUser(other.id, {
            title: `${moverName} from ${moverCountry} is nearby in ${moverCity}`,
            body: `${distStr}. Tap to say hi.`,
            type: "nearby_compatriot",
            targetUserId: moverId,
            city: moverCity,
            androidCollapseKey: "nearby_compatriot",
            androidTag: "nearby_compatriot",
            apnsThreadId: "nearby_compatriot",
        }));
    } else {
        console.log(`[Proximity] quiet hours for recipient ${other.id} — push skipped.`);
    }

    await Promise.all(pushes);
}
