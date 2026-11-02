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
const {
    requireAuth,
    requireAppCheck,
    consumeRateLimit,
    stableHash,
} = require("./security");
const {
    distributeUbuntuMatchingSupply,
    syncProfileMilestoneAndTrust,
} = require("./dsp");
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

// ─── Dwell Proximity & Grassroots Gathering Tunables ─────────────────────────
const DWELL_RADIUS_FEET = 100;                        // 100 ft (~30.48 meters)
const DWELL_QUERY_RADIUS_METERS = 100;                // Geohash query bound buffer
const AUTO_PROXIMITY_REQUIRED_MS = 10 * 60 * 1000;    // >10 minutes within 100 ft
const GRASSROOTS_GATHERING_REQUIRED_MS = 60 * 60 * 1000; // >60 minutes within 100 ft
const REWARD_COOLDOWN_24H_MS = 24 * 60 * 60 * 1000;   // 24-hour rolling window
const DWELL_EVAL_COOLDOWN_MS = 30 * 1000;             // 30s debounce per user
const PEER_LOCATION_FRESHNESS_MS = 24 * 60 * 60 * 1000; // Max age of peer GPS fix
const REWARD_DSP_AMOUNT = 1000;                       // 1,000 DSP each

// In-memory cooldown is a hot-path cache; Firestore is the source of truth.
const _proximityCooldowns = new Map();
const _dwellEvalCooldowns = new Map();

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

function extractCoordinates(privateData, publicData) {
    const candidates = [
        privateData && privateData.currentLocation,
        publicData && publicData.currentLocation,
        privateData && privateData.hostLocation,
        publicData && publicData.hostLocation,
        privateData && privateData.homeLocation,
        publicData && publicData.homeLocation,
    ];
    for (const loc of candidates) {
        if (loc && loc.geometry && loc.geometry.location) {
            const lat = Number(loc.geometry.location.lat);
            const lng = Number(loc.geometry.location.lng);
            if (Number.isFinite(lat) && Number.isFinite(lng) && (lat !== 0 || lng !== 0)) {
                return { lat, lng, loc };
            }
        }
    }
    return null;
}

exports.findNearbyUsers = functions.https.onCall(async (data, context) => {
    requireAppCheck(context);
    const uid = requireAuth(context);
    await consumeRateLimit("nearby-search", uid, 120, 60 * 60 * 1000);
    const limit = Math.min(Math.max(Number(data && data.limit) || 50, 1), 100);
    const isGlobal = Boolean(data && data.global === true);

    const [privateSnapshot, callerProfile] = await Promise.all([
        db.collection("user_private").doc(uid).get(),
        db.collection("users").doc(uid).get(),
    ]);
    const callerPriv = privateSnapshot.exists ? privateSnapshot.data() : {};
    const callerPub = callerProfile.exists ? callerProfile.data() : {};
    const callerCoords = extractCoordinates(callerPriv, callerPub);

    const excluded = new Set([
        uid,
        ...(callerPriv.blockedUsers || []),
        ...(callerPub.blockedUsers || []),
        ...(Array.isArray(data && data.excludeUserIds) ?
            data.excludeUserIds.slice(0, 100).filter(validUid) : []),
    ]);

    const homeCountryCode = callerPub.homeCountryCode || null;
    let queryRef = db.collection("users");
    if (!isGlobal && homeCountryCode) {
        queryRef = queryRef.where("homeCountryCode", "==", homeCountryCode);
    }

    const snapshot = await queryRef.limit(limit * 4).get();
    const candidateDocs = snapshot.docs.filter((doc) => !excluded.has(doc.id));
    if (candidateDocs.length === 0) return { users: [] };

    const privateSnaps = await db.getAll(
        ...candidateDocs.map((doc) => db.collection("user_private").doc(doc.id)),
    );
    const privateById = new Map(
        privateSnaps.filter((s) => s.exists).map((s) => [s.id, s.data()]),
    );

    const results = [];
    for (const doc of candidateDocs) {
        const pub = doc.data() || {};
        const priv = privateById.get(doc.id) || {};
        if (pub.isBanned === true) continue;
        if (!hasUsableName(pub)) continue;
        const blockedByOther = [
            ...(priv.blockedUsers || []),
            ...(pub.blockedUsers || []),
        ];
        if (blockedByOther.includes(uid)) continue;

        const targetCoords = extractCoordinates(priv, pub);
        let distanceKm;
        if (callerCoords && targetCoords) {
            const distanceMiles = calculateDistanceInMiles(
                callerCoords.lat,
                callerCoords.lng,
                targetCoords.lat,
                targetCoords.lng,
            );
            distanceKm = distanceMiles * 1.609344;
        }

        results.push({
            doc,
            priv,
            targetCoords,
            distanceKm,
        });
    }

    results.sort((a, b) => {
        const dA = Number.isFinite(a.distanceKm) ? a.distanceKm : Number.POSITIVE_INFINITY;
        const dB = Number.isFinite(b.distanceKm) ? b.distanceKm : Number.POSITIVE_INFINITY;
        if (dA !== dB) return dA - dB;
        const nameA = String(a.doc.data().firstName || "").toLowerCase();
        const nameB = String(b.doc.data().firstName || "").toLowerCase();
        return nameA.localeCompare(nameB);
    });

    const users = results
        .slice(0, limit)
        .map((item) => publicProfile(item.doc, item.distanceKm, item.priv, item.targetCoords));

    return { users };
});

function validUid(value) {
    return typeof value === "string" && value.length > 0 && value.length <= 128;
}

function publicProfile(document, distance, privateData = {}, targetCoords = null) {
    const data = document.data() || {};
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

    // Synthesize a safe city-level currentLocation for ProfileData.fromJson
    // so UserCardView displays the bottom flag, city, and proximity/distance.
    const rawCur = (privateData && privateData.currentLocation) || data.currentLocation;
    const hostLoc = data.hostLocation || (privateData && privateData.hostLocation) || {};
    const city = data.currentCity || (rawCur && rawCur.city) || hostLoc.city || null;
    const state = data.currentState || (rawCur && rawCur.state) || hostLoc.state || null;
    const country = (rawCur && rawCur.country) || data.hostCountry || hostLoc.country || null;
    const countryCode = data.currentCountryCode ||
        (rawCur && (rawCur.country_code || rawCur.countryCode)) ||
        data.hostCountryCode ||
        hostLoc.country_code ||
        hostLoc.countryCode ||
        null;

    const coords = targetCoords || extractCoordinates(privateData, data);
    // Round coordinates to ~1km city grid (2 decimal places) to protect exact street GPS
    const safeLat = coords ? Math.round(coords.lat * 100) / 100 : 0;
    const safeLng = coords ? Math.round(coords.lng * 100) / 100 : 0;

    if (city || countryCode || coords) {
        const summaryParts = [city, state, country].filter((p) => typeof p === "string" && p.trim().length > 0);
        const rawTs = rawCur && rawCur.timestamp;
        const tsMs = typeof rawTs === "number" ? rawTs : Date.now();
        result.currentLocation = {
            formatted_address: summaryParts.join(", "),
            place_id: "",
            city: city,
            state: state,
            country: country,
            country_code: countryCode,
            countryCode: countryCode,
            timestamp: tsMs,
            geometry: {
                location: {
                    lat: safeLat,
                    lng: safeLng,
                },
            },
            lastUpdated: (rawCur && rawCur.lastUpdated) || new Date(tsMs).toISOString(),
        };
    }

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
    const [firstNames, lastNames, callerPrivate, callerPublic] = await Promise.all([
        db.collection("users").where("firstName", ">=", prefix)
            .where("firstName", "<", `${prefix}\uf8ff`).limit(25).get(),
        db.collection("users").where("lastName", ">=", prefix)
            .where("lastName", "<", `${prefix}\uf8ff`).limit(25).get(),
        db.collection("user_private").doc(uid).get(),
        db.collection("users").doc(uid).get(),
    ]);
    const callerPrivData = callerPrivate.exists ? callerPrivate.data() : {};
    const callerPubData = callerPublic.exists ? callerPublic.data() : {};
    const callerCoords = extractCoordinates(callerPrivData, callerPubData);
    const blocked = new Set([
        ...(callerPrivData.blockedUsers || []),
        ...(callerPubData.blockedUsers || []),
    ]);
    const matches = new Map();
    for (const profile of [...firstNames.docs, ...lastNames.docs]) {
        if (profile.id !== uid && !blocked.has(profile.id)) matches.set(profile.id, profile);
    }
    const privateMatches = matches.size === 0 ? [] : await db.getAll(
        ...[...matches.keys()].map((id) => db.collection("user_private").doc(id)),
    );
    const privateById = new Map(
        privateMatches.filter((p) => p.exists).map((p) => [p.id, p.data()]),
    );
    const blockedCaller = new Set(privateMatches
        .filter((profile) => profile.exists &&
            (profile.data().blockedUsers || []).includes(uid))
        .map((profile) => profile.id));
    return {
        users: [...matches.values()]
            .filter((profile) => !blockedCaller.has(profile.id))
            .slice(0, 25)
            .map((profile) => {
                const priv = privateById.get(profile.id) || {};
                const targetCoords = extractCoordinates(priv, profile.data());
                let distanceKm;
                if (callerCoords && targetCoords) {
                    distanceKm = calculateDistanceInMiles(
                        callerCoords.lat, callerCoords.lng,
                        targetCoords.lat, targetCoords.lng,
                    ) * 1.609344;
                }
                return publicProfile(profile, distanceKm, priv, targetCoords);
            }),
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

        // Don't loop on our own cooldown or non-location writes.
        const beforeLoc = before.currentLocation || {};
        const afterLoc = after.currentLocation || {};
        const beforeLat = beforeLoc.geometry && beforeLoc.geometry.location
            ? beforeLoc.geometry.location.lat : null;
        const beforeLng = beforeLoc.geometry && beforeLoc.geometry.location
            ? beforeLoc.geometry.location.lng : null;
        const afterLat = afterLoc.geometry && afterLoc.geometry.location
            ? afterLoc.geometry.location.lat : null;
        const afterLng = afterLoc.geometry && afterLoc.geometry.location
            ? afterLoc.geometry.location.lng : null;
        const locationWriteOccurred =
            beforeLat !== afterLat ||
            beforeLng !== afterLng ||
            beforeLoc.timestamp !== afterLoc.timestamp ||
            beforeLoc.lastUpdated !== afterLoc.lastUpdated;
        if (!locationWriteOccurred) {
            return null;
        }

        const profile = await db.collection("users").doc(userId).get();
        if (!profile.exists) return null;
        const mergedUserData = {...profile.data(), ...after};

        await Promise.all([
            evaluateProximityDwellAndGatherings(userId, mergedUserData).catch((err) => {
                console.error(`[ProximityDwell] Error for ${userId}:`, err);
            }),
            runProximityCheck(
                userId,
                mergedUserData,
                before.currentLocation,
                false,
            ),
        ]);
        return null;
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
        await Promise.all([
            evaluateProximityDwellAndGatherings(userId, userData).catch((err) => {
                console.error(`[ProximityDwell] onCreate error for ${userId}:`, err);
            }),
            runProximityCheck(userId, userData, null, true),
        ]);
        return null;
    });

function extractLocationMillis(privateData, locObj) {
    if (locObj && typeof locObj.timestamp === "number" && locObj.timestamp > 0) {
        return locObj.timestamp;
    }
    if (locObj && typeof locObj.lastUpdated === "string") {
        const parsed = Date.parse(locObj.lastUpdated);
        if (!Number.isNaN(parsed)) return parsed;
    }
    if (privateData && privateData.locationUpdatedAt &&
        typeof privateData.locationUpdatedAt.toMillis === "function") {
        return privateData.locationUpdatedAt.toMillis();
    }
    return 0;
}

function decodePlusCode(code) {
    if (!code || typeof code !== "string") return null;
    const alphabet = "23456789CFGHJMPQRVWX";
    const clean = code.trim().toUpperCase();
    if (!clean.includes("+")) return null;
    const parts = clean.split("+");
    if (parts.length !== 2) return null;
    const [head, tail] = parts;
    if (!head || head.length > 8 || head.length % 2 !== 0) return null;
    for (let i = 0; i < head.length; i++) {
        if (head[i] !== "0" && !alphabet.includes(head[i])) return null;
    }
    for (let i = 0; i < tail.length; i++) {
        if (!alphabet.includes(tail[i])) return null;
    }
    const fullString = head + tail;
    if (fullString.length < 2) return null;

    let latVal = 0.0;
    let lngVal = 0.0;
    let latResolution = 20.0;
    let lngResolution = 20.0;

    for (let i = 0; i < fullString.length; i += 2) {
        const latChar = fullString[i];
        const lngChar = i + 1 < fullString.length ? fullString[i + 1] : "2";
        const latIdx = Math.max(0, alphabet.indexOf(latChar));
        const lngIdx = Math.max(0, alphabet.indexOf(lngChar));
        latVal += latIdx * latResolution;
        lngVal += lngIdx * lngResolution;
        if (i + 2 < fullString.length) {
            latResolution /= 20.0;
            lngResolution /= 20.0;
        }
    }

    const lat = Math.min(90, Math.max(-90, latVal - 90.0 + latResolution / 2.0));
    const lng = lngVal - 180.0 + lngResolution / 2.0;
    return { lat, lng };
}

/**
 * Evaluates both:
 *   1. Automatic Proximity Detection (100 ft, >10 min in 24h, any member, per unique pair -> 1,000 DSP each + push)
 *   2. Grassroots Gatherings (100 ft of host/venue, >60 min in 24h, RSVP'd/invited event members -> 1,000 DSP each + push + PCT)
 */
async function evaluateProximityDwellAndGatherings(userId, userData) {
    const newLoc = userData.currentLocation;
    if (!newLoc || !newLoc.geometry || !newLoc.geometry.location) return null;
    if (newLoc.isLiveGps === false) return null;

    const currentLat = Number(newLoc.geometry.location.lat);
    const currentLng = Number(newLoc.geometry.location.lng);
    if (!Number.isFinite(currentLat) || !Number.isFinite(currentLng) ||
        (currentLat === 0 && currentLng === 0)) {
        return null;
    }

    if (!hasUsableName(userData) || userData.isBanned === true) return null;
    if (userData.cityVisibilityForfeited === true || userData.showCurrentLocationName === false) {
        return null;
    }

    const now = Date.now();
    const lastEval = _dwellEvalCooldowns.get(userId);
    if (lastEval && (now - lastEval) < DWELL_EVAL_COOLDOWN_MS) {
        return null;
    }
    _dwellEvalCooldowns.set(userId, now);

    const currentCity = locationDisplayName(newLoc);
    const moverName = String(userData.firstName || "A member").trim();
    const blockedByMover = new Set(userData.blockedUsers || []);

    // 1. Query all users within 100-meter geohash bounds and filter to exact <= 100 ft
    const bounds = geohashQueryBounds(
        [currentLat, currentLng],
        DWELL_QUERY_RADIUS_METERS,
    );
    const [boundSnapshots, activeSessionsSnap] = await Promise.all([
        Promise.all(bounds.map((bound) =>
            db.collection("user_private")
                .orderBy("geo.geohash")
                .startAt(bound[0])
                .endAt(bound[1])
                .limit(100)
                .get())),
        db.collection("proximity_dwell_sessions")
            .where("users", "array-contains", userId)
            .where("status", "==", "active")
            .get(),
    ]);

    const privateDocuments = new Map();
    for (const snapshot of boundSnapshots) {
        for (const doc of snapshot.docs) {
            if (doc.id !== userId) {
                privateDocuments.set(doc.id, doc);
            }
        }
    }

    const publicSnapshots = privateDocuments.size === 0 ? [] : await db.getAll(
        ...[...privateDocuments.keys()].map((id) => db.collection("users").doc(id)),
    );
    const publicById = new Map(publicSnapshots.map((doc) => [doc.id, doc]));

    const nearbyWithin100Ft = new Map();
    for (const privDoc of privateDocuments.values()) {
        const pubDoc = publicById.get(privDoc.id);
        if (!pubDoc || !pubDoc.exists) continue;
        const privData = privDoc.data() || {};
        const pubData = pubDoc.data() || {};
        const other = { ...pubData, ...privData };

        if (other.isBanned === true || !hasUsableName(other)) continue;
        if (blockedByMover.has(privDoc.id)) continue;
        if ((other.blockedUsers || []).includes(userId)) continue;
        if (other.cityVisibilityForfeited === true || other.showCurrentLocationName === false) {
            continue;
        }

        const oLoc = privData.currentLocation || pubData.currentLocation;
        if (!oLoc || !oLoc.geometry || !oLoc.geometry.location) continue;
        if (oLoc.isLiveGps === false) continue;

        const oLat = Number(oLoc.geometry.location.lat);
        const oLng = Number(oLoc.geometry.location.lng);
        if (!Number.isFinite(oLat) || !Number.isFinite(oLng) || (oLat === 0 && oLng === 0)) {
            continue;
        }

        const otherLocMs = extractLocationMillis(privData, oLoc);
        if (otherLocMs > 0 && (now - otherLocMs) > PEER_LOCATION_FRESHNESS_MS) {
            continue;
        }

        const distanceMiles = calculateDistanceInMiles(currentLat, currentLng, oLat, oLng);
        const distanceFeet = distanceMiles * 5280;
        if (distanceFeet <= DWELL_RADIUS_FEET) {
            nearbyWithin100Ft.set(privDoc.id, {
                id: privDoc.id,
                data: other,
                distanceMiles,
                distanceFeet,
                lat: oLat,
                lng: oLng,
                city: locationDisplayName(oLoc, currentCity),
            });
        }
    }

    // 2. Reset any active dwell sessions where the user separated (> 100 ft)
    const separationUpdates = [];
    for (const sessionDoc of activeSessionsSnap.docs) {
        const sData = sessionDoc.data() || {};
        const users = Array.isArray(sData.users) ? sData.users : [];
        const peerId = users.find((u) => u !== userId);
        if (peerId && !nearbyWithin100Ft.has(peerId)) {
            separationUpdates.push(
                sessionDoc.ref.set({
                    status: "separated",
                    sessionStartMs: null,
                    lastSeparatedAtMs: now,
                    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
                }, { merge: true }).catch(() => undefined),
            );
        }
    }
    if (separationUpdates.length > 0) {
        await Promise.all(separationUpdates);
    }

    // 3. Evaluate Automatic Proximity Detection (100 ft, >10 min in 24h, any member, per unique pair)
    if (nearbyWithin100Ft.size > 0) {
        await Promise.all(
            [...nearbyWithin100Ft.values()].map((peer) =>
                processAutomaticProximityPair({
                    moverId: userId,
                    moverName,
                    moverCity: currentCity,
                    moverLat: currentLat,
                    moverLng: currentLng,
                    peer,
                }),
            ),
        );
    }

    // 4. Evaluate Grassroots Gatherings (100 ft of host/venue, >60 min in 24h, RSVP'd/invited event members)
    await evaluateGrassrootsGatheringsForUser({
        userId,
        userData,
        currentLat,
        currentLng,
        currentCity,
        nearbyWithin100Ft,
    });

    return null;
}

async function processAutomaticProximityPair({
    moverId,
    moverName,
    moverCity,
    moverLat,
    moverLng,
    peer,
}) {
    const [id1, id2] = [moverId, peer.id].sort();
    const sessionRef = db.collection("proximity_dwell_sessions").doc(`${id1}_${id2}`);
    const now = Date.now();

    const txResult = await db.runTransaction(async (t) => {
        const doc = await t.get(sessionRef);
        const d = doc.exists ? (doc.data() || {}) : {};

        const lastRewardedAtMs = Number(d.lastRewardedAtMs || 0);
        if (lastRewardedAtMs > 0 && (now - lastRewardedAtMs) < REWARD_COOLDOWN_24H_MS) {
            t.set(sessionRef, {
                lastSeenMs: now,
                lastDistanceFeet: Math.round(peer.distanceFeet * 10) / 10,
                updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            }, { merge: true });
            return { shouldAward: false };
        }

        const sessionStartMs = Number(d.sessionStartMs || 0);
        const isSessionActive =
            d.status === "active" &&
            sessionStartMs > 0 &&
            (now - sessionStartMs) <= REWARD_COOLDOWN_24H_MS;

        if (!isSessionActive) {
            t.set(sessionRef, {
                users: [id1, id2],
                status: "active",
                sessionStartMs: now,
                lastSeenMs: now,
                dwellDurationMs: 0,
                lastDistanceFeet: Math.round(peer.distanceFeet * 10) / 10,
                startLat: moverLat,
                startLng: moverLng,
                city: moverCity,
                updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            }, { merge: true });
            return { shouldAward: false };
        }

        const dwellMs = now - sessionStartMs;
        if (dwellMs < AUTO_PROXIMITY_REQUIRED_MS) {
            t.set(sessionRef, {
                lastSeenMs: now,
                dwellDurationMs: dwellMs,
                lastDistanceFeet: Math.round(peer.distanceFeet * 10) / 10,
                updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            }, { merge: true });
            return { shouldAward: false };
        }

        // >= 10 minutes within 100 feet during a 24-hour window -> Award both!
        const serverNow = admin.firestore.FieldValue.serverTimestamp();
        t.set(sessionRef, {
            users: [id1, id2],
            status: "rewarded",
            sessionStartMs: null,
            lastSeenMs: now,
            lastRewardedAtMs: now,
            lastDwellDurationMs: dwellMs,
            lastDistanceFeet: Math.round(peer.distanceFeet * 10) / 10,
            rewardCount: admin.firestore.FieldValue.increment(1),
            city: moverCity,
            updatedAt: serverNow,
        }, { merge: true });

        for (const col of ["trust_data", "trust_scores"]) {
            for (const uid of [id1, id2]) {
                t.set(db.collection(col).doc(uid), {
                    proximityConnectionsCount: admin.firestore.FieldValue.increment(1),
                    lastUpdated: serverNow,
                }, { merge: true });
            }
        }
        return { shouldAward: true, dwellMs };
    }).catch((err) => {
        console.error(`[ProximityDwell] Transaction failed for ${id1}_${id2}:`, err);
        return { shouldAward: false };
    });

    if (!txResult || !txResult.shouldAward) return;

    const peerName = String(peer.data.firstName || "a member").trim();
    const dwellMinutes = Math.max(10, Math.round((txResult.dwellMs || AUTO_PROXIMITY_REQUIRED_MS) / 60000));
    console.log(
        `🎉 [ProximityDwell] Awarding ${REWARD_DSP_AMOUNT} DSP each to ${moverId} & ${peer.id} (${dwellMinutes}m within ${peer.distanceFeet.toFixed(1)}ft)`,
    );

    try {
        const rewardBatch = db.batch();
        const serverNow = admin.firestore.FieldValue.serverTimestamp();
        const pairs = [
            [moverId, peer.id, peerName],
            [peer.id, moverId, moverName],
        ];

        await Promise.all(
            pairs.map(async ([uid, otherUid, otherDisplayName]) => {
                rewardBatch.set(
                    db.collection("user_points").doc(uid),
                    {
                        userId: uid,
                        totalPoints: admin.firestore.FieldValue.increment(REWARD_DSP_AMOUNT),
                        availablePoints: admin.firestore.FieldValue.increment(REWARD_DSP_AMOUNT),
                        lastUpdated: serverNow,
                        lifetimeEarnings: {
                            proximity_dwell_reward: admin.firestore.FieldValue.increment(REWARD_DSP_AMOUNT),
                        },
                    },
                    { merge: true },
                );

                rewardBatch.set(db.collection("points_transactions").doc(), {
                    userId: uid,
                    type: "earn",
                    action: "proximity_dwell_reward",
                    points: REWARD_DSP_AMOUNT,
                    amount: REWARD_DSP_AMOUNT,
                    timestamp: serverNow,
                    metadata: {
                        peerUid: otherUid,
                        peerName: otherDisplayName,
                        city: moverCity,
                        distanceFeet: Math.round(peer.distanceFeet),
                        dwellMinutes,
                        description: `Proximity Connection with ${otherDisplayName} (10+ mins)`,
                    },
                });

                await distributeUbuntuMatchingSupply(
                    rewardBatch,
                    uid,
                    REWARD_DSP_AMOUNT,
                    serverNow,
                    "proximity_dwell_reward_match",
                );
            }),
        );

        await Promise.all([
            rewardBatch.commit(),
            syncProfileMilestoneAndTrust(moverId).catch((err) => {
                console.warn(`[ProximityDwell] syncProfileMilestoneAndTrust mover warning: ${err.message}`);
            }),
            syncProfileMilestoneAndTrust(peer.id).catch((err) => {
                console.warn(`[ProximityDwell] syncProfileMilestoneAndTrust peer warning: ${err.message}`);
            }),
        ]);
    } catch (rewardErr) {
        console.error(`[ProximityDwell] Failed to commit DSP reward for ${id1}_${id2}:`, rewardErr);
        return;
    }

    // Send push notifications to BOTH users after points are awarded
    await Promise.all([
        sendPushToUser(moverId, {
            title: "🎉 +1,000 DSP Earned!",
            body: `You and ${peerName} connected in person for ${dwellMinutes}+ minutes in ${moverCity}. 1,000 DSP has been added to your wallet!`,
            type: "proximity_reward",
            targetUserId: peer.id,
            city: moverCity,
            androidCollapseKey: `proximity_reward_${peer.id}`,
            androidTag: `proximity_reward_${peer.id}`,
            apnsThreadId: "proximity_reward",
        }),
        sendPushToUser(peer.id, {
            title: "🎉 +1,000 DSP Earned!",
            body: `You and ${moverName} connected in person for ${dwellMinutes}+ minutes in ${moverCity}. 1,000 DSP has been added to your wallet!`,
            type: "proximity_reward",
            targetUserId: moverId,
            city: moverCity,
            androidCollapseKey: `proximity_reward_${moverId}`,
            androidTag: `proximity_reward_${moverId}`,
            apnsThreadId: "proximity_reward",
        }),
    ]);
}

function parseEventWindow(eventData, nowMs) {
    const startDateStr = String(eventData.startDate || "").trim();
    const startTimeStr = String(eventData.startTime || "00:00").trim();
    const endDateStr = String(eventData.endDate || startDateStr).trim();
    const endTimeStr = String(eventData.endTime || "23:59").trim();

    let startMs = Number.NaN;
    if (startDateStr) {
        startMs = Date.parse(`${startDateStr}T${startTimeStr}:00Z`);
        if (Number.isNaN(startMs)) startMs = Date.parse(startDateStr);
    }
    let endMs = Number.NaN;
    if (endDateStr) {
        endMs = Date.parse(`${endDateStr}T${endTimeStr}:00Z`);
        if (Number.isNaN(endMs)) endMs = Date.parse(endDateStr);
    }

    if (Number.isNaN(startMs)) startMs = nowMs;
    if (Number.isNaN(endMs) || endMs <= startMs) endMs = startMs + 24 * 60 * 60 * 1000;

    // Allow a generous 24h buffer around start/end to handle local timezones
    const windowStartMs = startMs - 24 * 60 * 60 * 1000;
    const windowEndMs = endMs + 24 * 60 * 60 * 1000;
    return { isActiveWindow: nowMs >= windowStartMs && nowMs <= windowEndMs };
}

/**
 * Evaluates Grassroots Gatherings & Event Geofencing:
 *   - Dynamic geofence around the event host's location (or static venue/Plus Code)
 *   - RSVP'd (`attendees`) or invited (`invitedUserIds`) members within 100 ft for >60 min in 24h
 *   - Automatically confirms attendance, awards 1,000 DSP to both host and guest,
 *     increments verifiedGatheringVisitsCount (+1 PCT per 10 for host) and verifiedCheckInCount (+10 PCT at 10 for guest),
 *     and sends push notifications to both host and guest.
 */
async function evaluateGrassrootsGatheringsForUser({
    userId,
    userData,
    currentLat,
    currentLng,
    currentCity,
    nearbyWithin100Ft,
}) {
    const now = Date.now();
    const [attendingSnap, invitedSnap, hostedSnap] = await Promise.all([
        db.collection("events")
            .where("attendees", "array-contains", userId)
            .where("status", "==", "published")
            .limit(50)
            .get(),
        db.collection("events")
            .where("invitedUserIds", "array-contains", userId)
            .where("status", "==", "published")
            .limit(50)
            .get(),
        db.collection("events")
            .where("creatorId", "==", userId)
            .where("status", "==", "published")
            .limit(50)
            .get(),
    ]);

    const eventsById = new Map();
    for (const snap of [attendingSnap, invitedSnap, hostedSnap]) {
        for (const doc of snap.docs) {
            eventsById.set(doc.id, doc);
        }
    }
    if (eventsById.size === 0) return;

    for (const eventDoc of eventsById.values()) {
        const eventData = eventDoc.data() || {};
        const eventId = eventDoc.id;
        const { isActiveWindow } = parseEventWindow(eventData, now);
        if (!isActiveWindow) continue;

        const hostUid = String(eventData.creatorId || eventData.createdBy || "").trim();
        if (!validUid(hostUid)) continue;

        const attendees = Array.isArray(eventData.attendees) ? eventData.attendees : [];
        const invited = Array.isArray(eventData.invitedUserIds) ? eventData.invitedUserIds : [];
        const allGuests = [...new Set([...attendees, ...invited].filter((u) => validUid(u) && u !== hostUid))];
        if (allGuests.length === 0) continue;

        // Resolve venue coordinates (if provided via lat/lng or Plus Code)
        let venueLat = typeof eventData.latitude === "number" ? eventData.latitude : null;
        let venueLng = typeof eventData.longitude === "number" ? eventData.longitude : null;
        if ((venueLat === null || venueLng === null) && eventData.plusCode) {
            const decoded = decodePlusCode(eventData.plusCode);
            if (decoded) {
                venueLat = decoded.lat;
                venueLng = decoded.lng;
            }
        }

        // Resolve host dynamic coordinates
        let hostLat = null;
        let hostLng = null;
        let hostName = String(eventData.creatorName || "Host").trim();
        if (userId === hostUid) {
            hostLat = currentLat;
            hostLng = currentLng;
            hostName = String(userData.firstName || hostName).trim();
        } else if (nearbyWithin100Ft.has(hostUid)) {
            const hostPeer = nearbyWithin100Ft.get(hostUid);
            hostLat = hostPeer.lat;
            hostLng = hostPeer.lng;
            hostName = String(hostPeer.data.firstName || hostName).trim();
        } else {
            const [hostPrivSnap, hostPubSnap] = await Promise.all([
                db.collection("user_private").doc(hostUid).get(),
                db.collection("users").doc(hostUid).get(),
            ]);
            if (hostPubSnap.exists && hostPubSnap.data().firstName) {
                hostName = String(hostPubSnap.data().firstName).trim();
            }
            if (hostPrivSnap.exists) {
                const hLoc = hostPrivSnap.data().currentLocation;
                if (hLoc && hLoc.geometry && hLoc.geometry.location && hLoc.isLiveGps !== false) {
                    const hLat = Number(hLoc.geometry.location.lat);
                    const hLng = Number(hLoc.geometry.location.lng);
                    const hMs = extractLocationMillis(hostPrivSnap.data(), hLoc);
                    if (Number.isFinite(hLat) && Number.isFinite(hLng) &&
                        (hMs === 0 || (now - hMs) <= PEER_LOCATION_FRESHNESS_MS)) {
                        hostLat = hLat;
                        hostLng = hLng;
                    }
                }
            }
        }

        const candidateGuests = userId === hostUid
            ? allGuests
            : (allGuests.includes(userId) ? [userId] : []);

        for (const guestUid of candidateGuests) {
            let guestLat = null;
            let guestLng = null;
            let guestName = "Guest";

            if (guestUid === userId) {
                guestLat = currentLat;
                guestLng = currentLng;
                guestName = String(userData.firstName || "Guest").trim();
            } else if (nearbyWithin100Ft.has(guestUid)) {
                const gPeer = nearbyWithin100Ft.get(guestUid);
                guestLat = gPeer.lat;
                guestLng = gPeer.lng;
                guestName = String(gPeer.data.firstName || "Guest").trim();
            } else {
                const [gPrivSnap, gPubSnap] = await Promise.all([
                    db.collection("user_private").doc(guestUid).get(),
                    db.collection("users").doc(guestUid).get(),
                ]);
                if (gPubSnap.exists && gPubSnap.data().firstName) {
                    guestName = String(gPubSnap.data().firstName).trim();
                }
                if (gPrivSnap.exists) {
                    const gLoc = gPrivSnap.data().currentLocation;
                    if (gLoc && gLoc.geometry && gLoc.geometry.location && gLoc.isLiveGps !== false) {
                        const gLat = Number(gLoc.geometry.location.lat);
                        const gLng = Number(gLoc.geometry.location.lng);
                        const gMs = extractLocationMillis(gPrivSnap.data(), gLoc);
                        if (Number.isFinite(gLat) && Number.isFinite(gLng) &&
                            (gMs === 0 || (now - gMs) <= PEER_LOCATION_FRESHNESS_MS)) {
                            guestLat = gLat;
                            guestLng = gLng;
                        }
                    }
                }
            }

            if (guestLat === null || guestLng === null) continue;

            // Compute distance to dynamic host location and/or static venue location
            let distToHostFeet = Number.POSITIVE_INFINITY;
            if (hostLat !== null && hostLng !== null) {
                distToHostFeet = calculateDistanceInMiles(guestLat, guestLng, hostLat, hostLng) * 5280;
            }
            let distToVenueFeet = Number.POSITIVE_INFINITY;
            if (venueLat !== null && venueLng !== null) {
                distToVenueFeet = calculateDistanceInMiles(guestLat, guestLng, venueLat, venueLng) * 5280;
            }
            const effectiveDistanceFeet = Math.min(distToHostFeet, distToVenueFeet);

            await processGrassrootsGatheringGuest({
                eventId,
                eventTitle: String(eventData.title || "Grassroots Gathering").trim(),
                hostUid,
                hostName,
                guestUid,
                guestName,
                effectiveDistanceFeet,
                city: currentCity,
                now,
            });
        }
    }
}

async function processGrassrootsGatheringGuest({
    eventId,
    eventTitle,
    hostUid,
    hostName,
    guestUid,
    guestName,
    effectiveDistanceFeet,
    city,
    now,
}) {
    const gatheringSessionRef = db.collection("grassroots_gathering_sessions")
        .doc(`${eventId}_${guestUid}`);
    const pairVisitRef = db.collection("peer_visits").doc(`${hostUid}_${guestUid}`);
    const reversePairVisitRef = db.collection("peer_visits").doc(`${guestUid}_${hostUid}`);

    if (effectiveDistanceFeet > DWELL_RADIUS_FEET) {
        const snap = await gatheringSessionRef.get();
        if (snap.exists && snap.data().status === "active") {
            await gatheringSessionRef.set({
                status: "separated",
                sessionStartMs: null,
                lastSeparatedAtMs: now,
                updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            }, { merge: true });
        }
        return;
    }

    const txResult = await db.runTransaction(async (t) => {
        const [sessionDoc, visitDoc, reverseVisitDoc, eventDoc] = await Promise.all([
            t.get(gatheringSessionRef),
            t.get(pairVisitRef),
            t.get(reversePairVisitRef),
            t.get(db.collection("events").doc(eventId)),
        ]);

        if (!eventDoc.exists) return { shouldAward: false };
        const sData = sessionDoc.exists ? (sessionDoc.data() || {}) : {};
        if (sData.status === "rewarded") {
            return { shouldAward: false };
        }

        // Check 24-hour pair cooldown in peer_visits
        for (const vSnap of [visitDoc, reverseVisitDoc]) {
            if (vSnap.exists && vSnap.data()) {
                const lastVisitMs = Number(vSnap.data().lastVisitTimestampMs || 0);
                if (lastVisitMs > 0 && (now - lastVisitMs) < REWARD_COOLDOWN_24H_MS) {
                    return { shouldAward: false };
                }
            }
        }

        const sessionStartMs = Number(sData.sessionStartMs || 0);
        const isSessionActive =
            sData.status === "active" &&
            sessionStartMs > 0 &&
            (now - sessionStartMs) <= REWARD_COOLDOWN_24H_MS;

        if (!isSessionActive) {
            t.set(gatheringSessionRef, {
                eventId,
                hostUid,
                guestUid,
                status: "active",
                sessionStartMs: now,
                lastSeenMs: now,
                dwellDurationMs: 0,
                lastDistanceFeet: Math.round(effectiveDistanceFeet * 10) / 10,
                city,
                updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            }, { merge: true });
            return { shouldAward: false };
        }

        const dwellMs = now - sessionStartMs;
        if (dwellMs < GRASSROOTS_GATHERING_REQUIRED_MS) {
            t.set(gatheringSessionRef, {
                lastSeenMs: now,
                dwellDurationMs: dwellMs,
                lastDistanceFeet: Math.round(effectiveDistanceFeet * 10) / 10,
                updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            }, { merge: true });
            return { shouldAward: false };
        }

        // >= 60 minutes within 100 feet -> Confirm Grassroots Gathering!
        const serverNow = admin.firestore.FieldValue.serverTimestamp();
        t.set(gatheringSessionRef, {
            eventId,
            hostUid,
            guestUid,
            status: "rewarded",
            sessionStartMs: null,
            lastSeenMs: now,
            rewardedAtMs: now,
            dwellDurationMs: dwellMs,
            lastDistanceFeet: Math.round(effectiveDistanceFeet * 10) / 10,
            city,
            updatedAt: serverNow,
        }, { merge: true });

        t.update(db.collection("events").doc(eventId), {
            confirmedAttendees: admin.firestore.FieldValue.arrayUnion(guestUid),
            updatedAt: serverNow,
        });

        t.set(db.collection("check_ins").doc(stableHash(`${eventId}:${guestUid}`)), {
            userId: guestUid,
            entityId: eventId,
            hostUserId: hostUid,
            type: "event",
            verification: "grassroots_geofence_60m",
            timestamp: serverNow,
        }, { merge: true });

        t.set(pairVisitRef, {
            hostUserId: hostUid,
            visitorUserId: guestUid,
            eventId,
            locationAddress: city,
            lastVisitTimestamp: new Date(now).toISOString(),
            lastVisitTimestampMs: now,
            visitCount: admin.firestore.FieldValue.increment(1),
            updatedAt: serverNow,
        }, { merge: true });

        // Increment guest and host Grassroots Gathering counters (+1 PCT per 10 gatherings)
        for (const col of ["trust_data", "trust_scores"]) {
            t.set(db.collection(col).doc(guestUid), {
                grassrootsGatheringsCount: admin.firestore.FieldValue.increment(1),
                verifiedGatheringVisitsCount: admin.firestore.FieldValue.increment(1),
                attendedEventsCount: admin.firestore.FieldValue.increment(1),
                lastUpdated: serverNow,
            }, { merge: true });
            t.set(db.collection(col).doc(hostUid), {
                grassrootsGatheringsCount: admin.firestore.FieldValue.increment(1),
                verifiedGatheringVisitsCount: admin.firestore.FieldValue.increment(1),
                lastUpdated: serverNow,
            }, { merge: true });
        }

        return { shouldAward: true, dwellMs };
    }).catch((err) => {
        console.error(`[GrassrootsGathering] Transaction failed for ${eventId}_${guestUid}:`, err);
        return { shouldAward: false };
    });

    if (!txResult || !txResult.shouldAward) return;

    const dwellMinutes = Math.max(60, Math.round((txResult.dwellMs || GRASSROOTS_GATHERING_REQUIRED_MS) / 60000));
    console.log(
        `🏠 [GrassrootsGathering] Confirmed 60+ min gathering for event ${eventId}: Host=${hostUid}, Guest=${guestUid} (${dwellMinutes}m)`,
    );

    try {
        const rewardBatch = db.batch();
        const serverNow = admin.firestore.FieldValue.serverTimestamp();
        const targets = [
            [guestUid, "peer_visit_visitor_reward", `Grassroots Gathering: ${eventTitle}`],
            [hostUid, "peer_visit_host_reward", `Hosted Grassroots Gathering: ${eventTitle} (${guestName})`],
        ];

        await Promise.all(
            targets.map(async ([targetUid, primaryAction, description]) => {
                rewardBatch.set(
                    db.collection("user_points").doc(targetUid),
                    {
                        userId: targetUid,
                        totalPoints: admin.firestore.FieldValue.increment(REWARD_DSP_AMOUNT),
                        availablePoints: admin.firestore.FieldValue.increment(REWARD_DSP_AMOUNT),
                        lastUpdated: serverNow,
                        lifetimeEarnings: {
                            [primaryAction]: admin.firestore.FieldValue.increment(REWARD_DSP_AMOUNT),
                        },
                    },
                    { merge: true },
                );

                rewardBatch.set(db.collection("points_transactions").doc(), {
                    userId: targetUid,
                    type: "earn",
                    action: primaryAction,
                    points: REWARD_DSP_AMOUNT,
                    amount: REWARD_DSP_AMOUNT,
                    timestamp: serverNow,
                    metadata: {
                        eventId,
                        eventName: eventTitle,
                        hostUid,
                        guestUid,
                        city,
                        dwellMinutes,
                        description,
                    },
                });

                await distributeUbuntuMatchingSupply(
                    rewardBatch,
                    targetUid,
                    REWARD_DSP_AMOUNT,
                    serverNow,
                    `${primaryAction}_match`,
                );
            }),
        );

        await Promise.all([
            rewardBatch.commit(),
            syncProfileMilestoneAndTrust(guestUid).catch((err) => {
                console.warn(`[GrassrootsGathering] syncProfileMilestoneAndTrust guest warning: ${err.message}`);
            }),
            syncProfileMilestoneAndTrust(hostUid).catch((err) => {
                console.warn(`[GrassrootsGathering] syncProfileMilestoneAndTrust host warning: ${err.message}`);
            }),
        ]);
    } catch (rewardErr) {
        console.error(`[GrassrootsGathering] Reward error for ${eventId}_${guestUid}:`, rewardErr);
        return;
    }

    await Promise.all([
        sendPushToUser(guestUid, {
            title: "🎉 +1,000 DSP Grassroots Gathering!",
            body: `Your ${dwellMinutes}+ minute gathering with ${hostName} at "${eventTitle}" was verified! 1,000 DSP added to your wallet.`,
            type: "grassroots_gathering_reward",
            targetUserId: hostUid,
            city,
            additionalData: { eventId },
            androidCollapseKey: `gathering_reward_${eventId}`,
            androidTag: `gathering_reward_${eventId}`,
            apnsThreadId: "grassroots_gathering_reward",
        }),
        sendPushToUser(hostUid, {
            title: "🎉 +1,000 DSP Host Reward!",
            body: `${guestName} attended "${eventTitle}" with you for ${dwellMinutes}+ minutes! 1,000 DSP added to your wallet.`,
            type: "grassroots_gathering_reward",
            targetUserId: guestUid,
            city,
            additionalData: { eventId },
            androidCollapseKey: `gathering_host_${eventId}_${guestUid}`,
            androidTag: `gathering_host_${eventId}_${guestUid}`,
            apnsThreadId: "grassroots_gathering_reward",
        }),
    ]);
}

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
