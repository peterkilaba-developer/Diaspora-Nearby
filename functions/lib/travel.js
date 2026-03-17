/**
 * Amadeus Travel API Proxy module.
 */
const { functions } = require("./shared");

/**
 * ==================================================================
 * AMADEUS TRAVEL API PROXY
 * ==================================================================
 * Keeps Amadeus API credentials server-side. The Flutter client calls
 * this Cloud Function instead of hitting Amadeus directly, eliminating
 * the need to bundle secrets in the app.
 */

// In-memory token cache (reused across invocations within the same instance)
let _amadeusToken = null;
let _amadeusTokenExpiry = null;

const AMADEUS_BASE = 'https://test.api.amadeus.com';

async function getAmadeusToken() {
  // Reuse valid token
  if (_amadeusToken && _amadeusTokenExpiry && Date.now() < _amadeusTokenExpiry) {
    return _amadeusToken;
  }

  // Use process.env (loaded from functions/.env by Firebase Functions v4+)
  const apiKey = process.env.AMADEUS_API_KEY;
  const apiSecret = process.env.AMADEUS_API_SECRET;

  if (!apiKey || !apiSecret) {
    console.error('[Amadeus] Missing credentials. AMADEUS_API_KEY:', !!apiKey, 'AMADEUS_API_SECRET:', !!apiSecret);
    throw new functions.https.HttpsError(
      'failed-precondition',
      'Amadeus API credentials not configured. Add AMADEUS_API_KEY and AMADEUS_API_SECRET to functions/.env'
    );
  }

  const params = new URLSearchParams();
  params.append('grant_type', 'client_credentials');
  params.append('client_id', apiKey);
  params.append('client_secret', apiSecret);

  const response = await fetch(`${AMADEUS_BASE}/v1/security/oauth2/token`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: params.toString(),
  });

  if (!response.ok) {
    const errBody = await response.text();
    console.error('[Amadeus] Auth failed:', response.status, errBody);
    throw new functions.https.HttpsError('internal', `Amadeus authentication failed: ${response.status}`);
  }

  const data = await response.json();
  _amadeusToken = data.access_token;
  const expiresIn = data.expires_in || 1799;
  _amadeusTokenExpiry = Date.now() + (expiresIn - 60) * 1000;
  console.log('[Amadeus] Token obtained, expires in', expiresIn, 'seconds');
  return _amadeusToken;
}

exports.amadeusProxy = functions
  .runWith({ timeoutSeconds: 60, memory: '256MB' })
  .https.onCall(async (data, context) => {
    // Require authentication
    if (!context.auth) {
      throw new functions.https.HttpsError('unauthenticated', 'Must be signed in.');
    }

    const { action, params } = data;
    if (!action) {
      throw new functions.https.HttpsError('invalid-argument', 'Missing action parameter.');
    }

    const token = await getAmadeusToken();
    const headers = {
      'Authorization': `Bearer ${token}`,
      'Accept': 'application/json',
      'Content-Type': 'application/json',
    };

    try {
      let url;
      let method = 'GET';
      let body = null;

      switch (action) {
        // ── FLIGHT SEARCH ──────────────────────────────────────────
        case 'searchFlights': {
          const qp = new URLSearchParams({
            originLocationCode: params.originIata,
            destinationLocationCode: params.destinationIata,
            departureDate: params.departureDate,
            adults: String(params.adults || 1),
            max: String(params.maxResults || 10),
            currencyCode: params.currencyCode || 'USD',
          });
          if (params.returnDate) qp.set('returnDate', params.returnDate);
          url = `${AMADEUS_BASE}/v2/shopping/flight-offers?${qp}`;
          break;
        }

        // ── FLIGHT PRICING ─────────────────────────────────────────
        case 'confirmFlightPrice': {
          url = `${AMADEUS_BASE}/v1/shopping/flight-offers/pricing`;
          method = 'POST';
          body = JSON.stringify({
            data: {
              type: 'flight-offers-pricing',
              flightOffers: [params.rawOfferJson],
            },
          });
          break;
        }

        // ── FLIGHT BOOKING ─────────────────────────────────────────
        case 'createFlightOrder': {
          url = `${AMADEUS_BASE}/v1/booking/flight-orders`;
          method = 'POST';
          body = JSON.stringify({ data: params.orderData });
          break;
        }

        // ── HOTEL LIST BY CITY ─────────────────────────────────────
        case 'searchHotelsByCity': {
          const qp = new URLSearchParams({
            cityCode: params.cityCode,
            radius: String(params.radius || 5),
            radiusUnit: 'KM',
            hotelSource: 'ALL',
          });
          url = `${AMADEUS_BASE}/v1/reference-data/locations/hotels/by-city?${qp}`;
          break;
        }

        // ── HOTEL LIST BY GEO ──────────────────────────────────────
        case 'searchHotelsByGeocode': {
          const qp = new URLSearchParams({
            latitude: String(params.latitude),
            longitude: String(params.longitude),
            radius: String(params.radius || 5),
            radiusUnit: 'KM',
            hotelSource: 'ALL',
          });
          url = `${AMADEUS_BASE}/v1/reference-data/locations/hotels/by-geocode?${qp}`;
          break;
        }

        // ── HOTEL OFFERS ───────────────────────────────────────────
        case 'getHotelOffers': {
          const qp = new URLSearchParams({
            hotelIds: params.hotelIds.join(','),
            checkInDate: params.checkInDate,
            checkOutDate: params.checkOutDate,
            adults: String(params.adults || 1),
            roomQuantity: String(params.rooms || 1),
            currency: params.currencyCode || 'USD',
            bestRateOnly: 'true',
          });
          url = `${AMADEUS_BASE}/v3/shopping/hotel-offers?${qp}`;
          break;
        }

        default:
          throw new functions.https.HttpsError('invalid-argument', `Unknown action: ${action}`);
      }

      console.log(`[Amadeus] ${method} ${action} for user ${context.auth.uid}`);

      const response = await fetch(url, { method, headers, body });
      const responseData = await response.json();

      if (!response.ok) {
        const errDetail = JSON.stringify(responseData).substring(0, 500);
        console.error(`[Amadeus] ${action} failed:`, response.status, errDetail);
        // Extract a useful error message from Amadeus response
        let userMsg = `Amadeus ${action} failed: ${response.status}`;
        const errors = responseData?.errors;
        if (Array.isArray(errors) && errors.length > 0) {
          userMsg += ' — ' + errors.map(e => `${e.detail || e.title || e.code}`).join('; ');
        }
        throw new functions.https.HttpsError('internal', userMsg);
      }

      return responseData;
    } catch (error) {
      if (error instanceof functions.https.HttpsError) throw error;
      console.error(`[Amadeus] Unexpected error in ${action}:`, error);
      throw new functions.https.HttpsError('internal', `Amadeus proxy error: ${error.message}`);
    }
  });
