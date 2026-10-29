/**
 * CORS Proxy modules: Radio Browser, Google Places.
 */
const { functions, admin, db } = require("./shared");
const { requireAppCheck, requireAuth, consumeRateLimit } = require("./security");

function stableAppCheckSubject(decoded) {
  return String(decoded && (decoded.sub || decoded.aud || "unknown")).slice(0, 512);
}

const UPSTREAM_TIMEOUT_MS = 8000;
const MAX_UPSTREAM_BYTES = 1024 * 1024;

async function fetchJson(url) {
  const response = await fetch(url, {
    signal: AbortSignal.timeout(UPSTREAM_TIMEOUT_MS),
    headers: {"Accept": "application/json"},
  });
  if (!response.ok) {
    throw new Error(`Upstream returned ${response.status}`);
  }
  const declaredLength = Number(response.headers.get("content-length") || 0);
  if (declaredLength > MAX_UPSTREAM_BYTES) {
    throw new Error("Upstream response was too large");
  }
  const body = await response.text();
  if (Buffer.byteLength(body, "utf8") > MAX_UPSTREAM_BYTES) {
    throw new Error("Upstream response was too large");
  }
  return JSON.parse(body);
}

function radioEndpoint(rawEndpoint) {
  const raw = String(rawEndpoint || "").trim();
  if (!raw || raw.length > 500 || /\\|\.\.|%2e/i.test(raw)) {
    return null;
  }
  const withoutPrefix = raw.replace(/^\/?(?:stations\/)?/, "");
  let parsed;
  try {
    parsed = new URL(withoutPrefix, "https://radio.invalid/");
  } catch (_) {
    return null;
  }
  if (parsed.origin !== "https://radio.invalid" || parsed.hash) return null;

  const path = parsed.pathname.replace(/^\//, "");
  const keys = [...new Set(parsed.searchParams.keys())];
  if (/^bycountrycodeexact\/[A-Za-z]{2}$/.test(path) && keys.length === 0) {
    const countryCode = path.substring(path.lastIndexOf("/") + 1).toUpperCase();
    return `stations/bycountrycodeexact/${countryCode}?limit=100`;
  }
  if (path === "search" && keys.every((key) => ["name", "limit"].includes(key))) {
    const name = String(parsed.searchParams.get("name") || "").trim();
    const limit = Number(parsed.searchParams.get("limit") || 100);
    if (!name || name.length > 100 || !Number.isInteger(limit) || limit < 1 || limit > 100) {
      return null;
    }
    const params = new URLSearchParams({name, limit: String(limit)});
    return `stations/search?${params.toString()}`;
  }
  const topMatch = path.match(/^topclick\/(\d{1,3})$/);
  if (topMatch && keys.length === 0) {
    const limit = Number(topMatch[1]);
    if (limit >= 1 && limit <= 100) return `stations/topclick/${limit}`;
  }
  return null;
}

/**
 * ==================================================================
 * 2. RADIO PROXY (Restored)
 * ==================================================================
 */

exports.radioProxy = functions.https.onRequest(async (req, res) => {
  res.status(410).json({
    error: 'This legacy endpoint is disabled. Use fetchRadioStations.',
  });
});

/**
 * Records playback reliability without exposing direct client writes to the
 * shared radio_station_health collection.
 */
exports.reportRadioStationHealth = functions.https.onCall(async (data, context) => {
  requireAppCheck(context);
  const uid = requireAuth(context);
  await consumeRateLimit('radio-health', uid, 200, 60 * 60 * 1000);

  const stationUuid = String(data.stationUuid || '').trim();
  const outcome = data.outcome;
  if (!stationUuid || stationUuid.length > 128 || !['success', 'failure'].includes(outcome)) {
    throw new functions.https.HttpsError(
      'invalid-argument',
      'A valid station UUID and outcome are required.',
    );
  }

  const countField = outcome === 'success' ? 'successCount' : 'failureCount';
  await db.collection('radio_station_health').doc(stationUuid).set({
    [countField]: admin.firestore.FieldValue.increment(1),
    lastReported: admin.firestore.FieldValue.serverTimestamp(),
  }, { merge: true });

  return { success: true };
});

/**
 * Authenticated callable proxy for the Radio Browser API. Keeping the upstream
 * host fixed prevents callers from turning this into a general-purpose proxy.
 */
exports.fetchRadioStations = functions.https.onCall(async (data, context) => {
  requireAppCheck(context);
  const uid = requireAuth(context);
  await consumeRateLimit('radio-fetch', uid, 120, 60 * 60 * 1000);

  const finalPath = radioEndpoint(data && data.endpoint);
  if (!finalPath) {
    throw new functions.https.HttpsError(
      'invalid-argument',
      'A valid radio endpoint is required.',
    );
  }

  try {
    const result = await fetchJson(`https://de1.api.radio-browser.info/json/${finalPath}`);
    if (!Array.isArray(result)) throw new Error("Unexpected upstream response");
    return result.slice(0, 100);
  } catch (error) {
    console.error('[FetchRadioStations] Error:', error);
    throw new functions.https.HttpsError(
      'unavailable',
      'Radio stations are temporarily unavailable.',
    );
  }
});


/**
 * ==================================================================
 * 2b. GOOGLE PLACES PROXY (CORS-enabled for web)
 * ==================================================================
 * The Google Places REST API does not include CORS headers, so
 * Flutter web cannot call it directly. This proxy forwards requests
 * and returns results with proper CORS headers.
 */

exports.placesProxy = functions
  .runWith({ secrets: ['GOOGLE_PLACES_API_KEY'] })
  .https.onRequest(async (req, res) => {
  // Handle CORS preflight
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Access-Control-Allow-Methods', 'GET, OPTIONS');
  res.set('Access-Control-Allow-Headers', 'Authorization, Content-Type, X-Firebase-AppCheck');

  if (req.method === 'OPTIONS') {
    res.status(204).send('');
    return;
  }

  const type = req.query.type; // 'autocomplete' or 'details'
  const apiKey = process.env.GOOGLE_PLACES_API_KEY;

  if (!type || !apiKey) {
    res.status(503).json({ error: 'Places service is not configured' });
    return;
  }
  if (req.method !== 'GET') {
    res.set('Allow', 'GET, OPTIONS');
    res.status(405).json({ error: 'Method not allowed' });
    return;
  }

  let uid;
  try {
    const authorization = String(req.header('Authorization') || '');
    const match = authorization.match(/^Bearer ([A-Za-z0-9._-]+)$/);
    if (!match) throw new Error('missing bearer token');
    const token = process.env.FUNCTIONS_EMULATOR !== 'true'
      ? req.header('X-Firebase-AppCheck')
      : null;
    const [decodedAuth, decodedAppCheck] = await Promise.all([
      admin.auth().verifyIdToken(match[1]),
      token ? admin.appCheck().verifyToken(token) : Promise.resolve(null),
    ]);
    uid = decodedAuth.uid;

    if (process.env.FUNCTIONS_EMULATOR !== 'true') {
      if (token) {
        if (!decodedAppCheck.appId && stableAppCheckSubject(decodedAppCheck) === 'unknown') {
          throw new Error('invalid app token');
        }
      } else if (process.env.ENFORCE_APP_CHECK === 'true') {
        throw new Error('missing token');
      } else {
        console.warn('[PlacesProxy] Request missing AppCheck header; allowing because ENFORCE_APP_CHECK is not true.');
      }
    }
  } catch (err) {
    console.warn('[PlacesProxy] Auth/AppCheck error:', err.message);
    res.status(401).json({ error: 'Authentication and app attestation are required' });
    return;
  }
  try {
    await consumeRateLimit('places-proxy', uid, 300, 60 * 60 * 1000);
  } catch (_) {
    res.status(429).json({ error: 'Too many requests' });
    return;
  }

  try {
    let targetUrl;

    if (type === 'autocomplete') {
      const input = String(req.query.input || '').trim();
      const sessiontoken = String(req.query.sessiontoken || '');
      const types = String(req.query.types || '');
      const allowedTypes = new Set([
        '', '(cities)', '(regions)', 'address', 'establishment',
        'geocode', 'school|university',
      ]);

      if (!input || input.length > 256 || sessiontoken.length > 128 || !allowedTypes.has(types)) {
        res.status(400).json({ error: 'Missing input parameter' });
        return;
      }

      const url = new URL('https://maps.googleapis.com/maps/api/place/autocomplete/json');
      url.searchParams.set('input', input);
      url.searchParams.set('key', apiKey);
      if (sessiontoken) url.searchParams.set('sessiontoken', sessiontoken);
      if (types) url.searchParams.set('types', types);
      targetUrl = url;
    } else if (type === 'details') {
      const placeId = String(req.query.place_id || '').trim();
      const fields = String(req.query.fields || '');
      const sessiontoken = String(req.query.sessiontoken || '');
      const allowedFields = new Set([
        'formatted_address', 'geometry', 'name', 'place_id', 'types',
        'address_components', 'website', 'international_phone_number',
        'url', 'rating', 'user_ratings_total', 'opening_hours', 'photos',
        'price_level', 'editorial_summary',
      ]);
      const requestedFields = fields.split(',').filter(Boolean);

      if (!placeId || placeId.length > 512 || fields.length > 512 ||
          sessiontoken.length > 128 || requestedFields.some((field) => !allowedFields.has(field))) {
        res.status(400).json({ error: 'Missing place_id parameter' });
        return;
      }

      const url = new URL('https://maps.googleapis.com/maps/api/place/details/json');
      url.searchParams.set('place_id', placeId);
      url.searchParams.set('key', apiKey);
      if (fields) url.searchParams.set('fields', fields);
      if (sessiontoken) url.searchParams.set('sessiontoken', sessiontoken);
      targetUrl = url;
    } else {
      res.status(400).json({ error: 'Invalid type. Use "autocomplete" or "details".' });
      return;
    }

    console.log(`[PlacesProxy] Proxying ${type} request`);
    const data = await fetchJson(targetUrl);
    res.json(data);
  } catch (error) {
    console.error('[PlacesProxy] Error:', error);
    res.status(502).json({ error: 'Places service is temporarily unavailable' });
  }
});
