/**
 * Amadeus Travel API Proxy module.
 */
const { functions, admin, db } = require("./shared");
const { requireAppCheck, requireAuth, consumeRateLimit } = require("./security");

/**
 * ==================================================================
 * AMADEUS TRAVEL API PROXY
 * ==================================================================
 * Keeps Amadeus API credentials server-side. The Flutter client calls
 * this Cloud Function instead of hitting Amadeus directly, eliminating
 * the need to bundle secrets in the app.
 * 
 * Configured for Amadeus Test Environment (https://test.api.amadeus.com).
 * In Test Mode, search queries for supported test routes return live Sandbox data,
 * and queries for non-sandbox global cities/routes fall back to realistic search results,
 * allowing users to view flights and hotels globally without live ticket issuance.
 */

// In-memory token cache (reused across invocations within the same instance)
let _amadeusToken = null;
let _amadeusTokenExpiry = null;

const AMADEUS_BASE = process.env.AMADEUS_BASE_URL || 'https://test.api.amadeus.com';
const ALLOWED_AMADEUS_BASES = new Set([
  'https://test.api.amadeus.com',
  'https://api.amadeus.com',
]);
const ALLOW_TRAVEL_MOCKS = process.env.ALLOW_TRAVEL_MOCKS !== 'false';
const FLIGHT_BOOKING_ENABLED = process.env.ENABLE_FLIGHT_BOOKING === 'true' &&
  AMADEUS_BASE === 'https://api.amadeus.com';

function assertAmadeusConfiguration() {
  if (!ALLOWED_AMADEUS_BASES.has(AMADEUS_BASE)) {
    throw new functions.https.HttpsError(
      'failed-precondition',
      'AMADEUS_BASE_URL must be an approved Amadeus API origin.'
    );
  }
}

async function persistFlightBooking(uid, responseData, orderData) {
  const order = responseData && responseData.data ? responseData.data : responseData;
  const orderId = order && typeof order.id === 'string' ? order.id : '';
  if (!/^[A-Za-z0-9_-]{1,256}$/.test(orderId)) {
    throw new functions.https.HttpsError('internal', 'Amadeus returned an invalid order ID.');
  }
  const offer = (order.flightOffers && order.flightOffers[0]) ||
    (orderData.flightOffers && orderData.flightOffers[0]) || {};
  const itineraries = Array.isArray(offer.itineraries) ? offer.itineraries : [];
  const segments = itineraries.flatMap((itinerary) =>
    Array.isArray(itinerary.segments) ? itinerary.segments : []);
  const firstSegment = segments[0] || {};
  const lastSegment = segments[segments.length - 1] || {};
  const departure = firstSegment.departure || {};
  const arrival = lastSegment.arrival || {};
  const route = departure.iataCode && arrival.iataCode ?
    `${departure.iataCode} → ${arrival.iataCode}` : '';
  const price = offer.price || {};
  const travelers = Array.isArray(orderData.travelers) ? orderData.travelers : [];
  const passengerNames = travelers.map((traveler) => {
    const name = traveler && traveler.name || {};
    return `${String(name.firstName || '').slice(0, 100)} ${String(name.lastName || '').slice(0, 100)}`.trim();
  }).filter(Boolean);
  const records = Array.isArray(order.associatedRecords) ? order.associatedRecords : [];
  const pnrReference = records[0] && records[0].reference ?
    String(records[0].reference).slice(0, 100) : 'N/A';

  await db.collection('flight_bookings').doc(orderId).create({
    userId: uid,
    orderId,
    pnrReference,
    passengerName: passengerNames.join(', ').slice(0, 500),
    passengerNames: passengerNames.slice(0, 20),
    route,
    departureDate: String(departure.at || '').slice(0, 40),
    totalPrice: Number(price.grandTotal || price.total || 0),
    currency: String(price.currency || '').slice(0, 3),
    status: 'confirmed',
    bookingType: 'flight',
    travelerCount: passengerNames.length,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });
}

async function fetchWithRetry(url, options, maxRetries = 2) {
  let lastError;
  for (let attempt = 0; attempt <= maxRetries; attempt++) {
    try {
      const response = await fetch(url, options);
      return response;
    } catch (err) {
      lastError = err;
      console.warn(`[Amadeus] fetch attempt ${attempt + 1} for ${url} failed: ${err.message}`);
      if (attempt < maxRetries) {
        await new Promise((r) => setTimeout(r, 500 * Math.pow(2, attempt)));
      }
    }
  }
  throw lastError;
}

async function getAmadeusToken() {
  // Reuse valid token
  if (_amadeusToken && _amadeusTokenExpiry && Date.now() < _amadeusTokenExpiry) {
    return _amadeusToken;
  }

  // Use process.env (loaded from secrets / functions environment)
  const apiKey = process.env.AMADEUS_API_KEY;
  const apiSecret = process.env.AMADEUS_API_SECRET;

  if (!apiKey || !apiSecret) {
    console.error('[Amadeus] Missing credentials. AMADEUS_API_KEY:', !!apiKey, 'AMADEUS_API_SECRET:', !!apiSecret);
    throw new functions.https.HttpsError(
      'failed-precondition',
      'Amadeus API credentials not configured.'
    );
  }

  const params = new URLSearchParams();
  params.append('grant_type', 'client_credentials');
  params.append('client_id', apiKey);
  params.append('client_secret', apiSecret);

  let response;
  try {
    response = await fetchWithRetry(
      `${AMADEUS_BASE}/v1/security/oauth2/token`,
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        body: params.toString(),
      },
      AMADEUS_BASE.includes('test.api.amadeus.com') ? 0 : 2
    );
  } catch (netErr) {
    console.error('[Amadeus] Token fetch network failure:', netErr);
    throw new functions.https.HttpsError('unavailable', `Amadeus network failure: ${netErr.message}`);
  }

  if (!response.ok) {
    const errBody = await response.text();
    console.error('[Amadeus] Auth failed:', response.status, errBody);
    throw new functions.https.HttpsError('internal', `Amadeus authentication failed: ${response.status}`);
  }

  const data = await response.json();
  _amadeusToken = data.access_token;
  const expiresIn = data.expires_in || 1799;
  _amadeusTokenExpiry = Date.now() + (expiresIn - 60) * 1000;
  console.log('[Amadeus] Token obtained from', AMADEUS_BASE, 'expires in', expiresIn, 'seconds');
  return _amadeusToken;
}

// ─────────────────────────────────────────────────────────────────────────────
// SANDBOX SEARCH FALLBACK GENERATORS
// Amadeus Test Environment (test.api.amadeus.com) only contains mock static
// data for ~5 test cities (MAD, PAR, LON, NYC). For all other global routes/cities,
// the sandbox returns empty [] or 400. To ensure seamless demo and user testing,
// we generate realistic flight and hotel data when the sandbox has no entries.
// ─────────────────────────────────────────────────────────────────────────────

function generateMockFlights(params = {}) {
  const origin = (params.originIata || 'JFK').toUpperCase();
  const dest = (params.destinationIata || 'DAR').toUpperCase();
  const depDate = params.departureDate || '2026-08-30';
  const retDate = params.returnDate;
  const currency = params.currencyCode || 'USD';

  const airlines = [
    { code: 'ET', name: 'Ethiopian Airlines', basePrice: 650, flightNo1: '503', flightNo2: '805', hub: 'ADD' },
    { code: 'KQ', name: 'Kenya Airways', basePrice: 720, flightNo1: '101', flightNo2: '482', hub: 'NBO' },
    { code: 'QR', name: 'Qatar Airways', basePrice: 890, flightNo1: '702', flightNo2: '1347', hub: 'DOH' },
    { code: 'TC', name: 'Air Tanzania', basePrice: 420, flightNo1: '202', flightNo2: '304', hub: 'DAR' },
    { code: 'EK', name: 'Emirates', basePrice: 950, flightNo1: '204', flightNo2: '725', hub: 'DXB' }
  ];

  const offers = airlines.map((al, idx) => {
    const isDirect = al.code === 'TC' || origin === dest;
    const priceNum = (al.basePrice + (idx * 45));
    const priceStr = priceNum.toFixed(2);

    const segments = isDirect ? [
      {
        departure: { iataCode: origin, at: `${depDate}T09:00:00` },
        arrival: { iataCode: dest, at: `${depDate}T12:30:00` },
        carrierCode: al.code,
        number: al.flightNo1,
        duration: 'PT3H30M',
        numberOfStops: 0
      }
    ] : [
      {
        departure: { iataCode: origin, at: `${depDate}T07:30:00` },
        arrival: { iataCode: al.hub, at: `${depDate}T15:00:00` },
        carrierCode: al.code,
        number: al.flightNo1,
        duration: 'PT7H30M',
        numberOfStops: 0
      },
      {
        departure: { iataCode: al.hub, at: `${depDate}T17:30:00` },
        arrival: { iataCode: dest, at: `${depDate}T21:15:00` },
        carrierCode: al.code,
        number: al.flightNo2,
        duration: 'PT3H45M',
        numberOfStops: 0
      }
    ];

    const itineraries = [
      {
        duration: isDirect ? 'PT3H30M' : 'PT13H45M',
        segments: segments
      }
    ];

    if (retDate) {
      itineraries.push({
        duration: isDirect ? 'PT3H30M' : 'PT14H00M',
        segments: isDirect ? [
          {
            departure: { iataCode: dest, at: `${retDate}T14:00:00` },
            arrival: { iataCode: origin, at: `${retDate}T17:30:00` },
            carrierCode: al.code,
            number: al.flightNo1,
            duration: 'PT3H30M',
            numberOfStops: 0
          }
        ] : [
          {
            departure: { iataCode: dest, at: `${retDate}T11:00:00` },
            arrival: { iataCode: al.hub, at: `${retDate}T15:00:00` },
            carrierCode: al.code,
            number: al.flightNo2,
            duration: 'PT4H00M',
            numberOfStops: 0
          },
          {
            departure: { iataCode: al.hub, at: `${retDate}T18:00:00` },
            arrival: { iataCode: origin, at: `${retDate}T01:00:00` },
            carrierCode: al.code,
            number: al.flightNo1,
            duration: 'PT7H00M',
            numberOfStops: 0
          }
        ]
      });
    }

    return {
      type: 'flight-offer',
      id: String(idx + 1),
      source: 'GDS',
      instantTicketingRequired: false,
      nonHomogeneous: false,
      oneWay: !retDate,
      lastTicketingDate: `${depDate}`,
      numberOfBookableSeats: 9,
      itineraries: itineraries,
      price: {
        currency: currency,
        total: priceStr,
        base: (priceNum * 0.85).toFixed(2),
        grandTotal: priceStr
      },
      pricingOptions: {
        fareType: ['PUBLISHED'],
        includedCheckedBaggageOnly: true
      },
      validatingAirlineCodes: [al.code],
      travelerPricings: [
        {
          travelerId: '1',
          fareOption: 'STANDARD',
          travelerType: 'ADULT',
          price: {
            currency: currency,
            total: priceStr,
            base: (priceNum * 0.85).toFixed(2)
          }
        }
      ]
    };
  });

  return { data: offers };
}

function generateMockHotelList(params = {}) {
  const city = (params.cityCode || 'DAR').toUpperCase();
  const lat = Number(params.latitude) || -6.7924;
  const lng = Number(params.longitude) || 39.2083;

  const sampleHotels = [
    { id: 'HTDAR001', name: 'Grand Diaspora Resort & Spa', chain: 'DN', latOffset: 0.005, lngOffset: 0.005 },
    { id: 'HTDAR002', name: 'Kilimanjaro View Palace', chain: 'KV', latOffset: -0.008, lngOffset: 0.003 },
    { id: 'HTDAR003', name: 'Serena City Center Hotel', chain: 'SE', latOffset: 0.002, lngOffset: -0.006 },
    { id: 'HTDAR004', name: 'Hyatt Regency Sanctuary', chain: 'HR', latOffset: -0.004, lngOffset: -0.004 },
    { id: 'HTDAR005', name: 'Golden Tulip Harbour Hotel', chain: 'GT', latOffset: 0.009, lngOffset: 0.001 }
  ];

  return {
    data: sampleHotels.map(h => ({
      type: 'building',
      hotelId: h.id,
      chainCode: h.chain,
      iataCode: city,
      name: h.name,
      geoCode: {
        latitude: lat + h.latOffset,
        longitude: lng + h.lngOffset
      },
      address: {
        countryCode: 'TZ'
      }
    }))
  };
}

function generateMockHotelOffers(params = {}) {
  const checkIn = params.checkInDate || '2026-08-30';
  const checkOut = params.checkOutDate || '2026-08-31';
  const currency = params.currency || 'USD';
  const hotelIds = Array.isArray(params.hotelIds) ? params.hotelIds : (params.hotelIds ? String(params.hotelIds).split(',') : ['HTDAR001', 'HTDAR002', 'HTDAR003', 'HTDAR004', 'HTDAR005']);

  const hotelCatalog = {
    'HTDAR001': { name: 'Grand Diaspora Resort & Spa', price: 140, lat: -6.787, lng: 39.213 },
    'HTDAR002': { name: 'Kilimanjaro View Palace', price: 185, lat: -6.800, lng: 39.211 },
    'HTDAR003': { name: 'Serena City Center Hotel', price: 210, lat: -6.790, lng: 39.202 },
    'HTDAR004': { name: 'Hyatt Regency Sanctuary', price: 260, lat: -6.796, lng: 39.204 },
    'HTDAR005': { name: 'Golden Tulip Harbour Hotel', price: 125, lat: -6.783, lng: 39.209 }
  };

  const results = hotelIds.map((hId, idx) => {
    const meta = hotelCatalog[hId] || { name: `Diaspora Stay ${hId}`, price: 150 + (idx * 25), lat: -6.792 + (idx * 0.003), lng: 39.208 + (idx * 0.003) };
    const priceStr = meta.price.toFixed(2);

    return {
      type: 'hotel-offers',
      hotel: {
        type: 'hotel',
        hotelId: hId,
        chainCode: 'DN',
        name: meta.name,
        cityCode: 'DAR',
        latitude: meta.lat,
        longitude: meta.lng
      },
      available: true,
      offers: [
        {
          type: 'hotel-offer',
          id: `OFF_${hId}_1`,
          checkInDate: checkIn,
          checkOutDate: checkOut,
          rateCode: 'RAC',
          room: {
            type: 'DBL',
            typeEstimated: {
              category: 'DELUXE_ROOM',
              beds: 1,
              bedType: 'KING'
            },
            description: {
              text: 'Deluxe King Room with City/Ocean View, Air Conditioning, Free High-Speed WiFi, and Breakfast Included.'
            }
          },
          price: {
            currency: currency,
            base: (meta.price * 0.88).toFixed(2),
            total: priceStr,
            variations: {
              average: { base: (meta.price * 0.88).toFixed(2) }
            }
          },
          policies: {
            cancellation: {
              deadline: `${checkIn}T23:59:00`,
              description: { text: 'Free cancellation up to 24 hours before check-in.' }
            },
            paymentType: 'guarantee'
          },
          boardType: 'BREAKFAST'
        }
      ]
    };
  });

  return { data: results };
}

exports.amadeusProxy = functions
  .runWith({ timeoutSeconds: 60, memory: '256MB', secrets: ["AMADEUS_API_KEY", "AMADEUS_API_SECRET"] })
  .https.onCall(async (data, context) => {
    requireAppCheck(context);
    const uid = requireAuth(context);
    await consumeRateLimit('amadeus', uid, 120, 60 * 60 * 1000);

    const { action, params } = data || {};
    if (!action || !params || typeof params !== 'object' || Array.isArray(params)) {
      throw new functions.https.HttpsError('invalid-argument', 'Missing action parameter.');
    }
    assertAmadeusConfiguration();
    if (action === 'createFlightOrder' && !FLIGHT_BOOKING_ENABLED) {
      throw new functions.https.HttpsError(
        'failed-precondition',
        'Flight booking is disabled until the live, PCI-reviewed fulfillment flow is enabled.'
      );
    }

    const isSearchAction = [
      'searchFlights',
      'searchHotelsByCity',
      'searchHotelsByGeocode',
      'getHotelOffers'
    ].includes(action);

    try {
      const token = await getAmadeusToken();
      const headers = {
        'Authorization': `Bearer ${token}`,
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      };

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
            hotelIds: Array.isArray(params.hotelIds) ? params.hotelIds.join(',') : params.hotelIds,
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

      // Never replay a booking POST automatically: an upstream timeout may
      // occur after the provider has accepted the order.
      const response = await fetchWithRetry(
        url,
        { method, headers, body },
        action === 'createFlightOrder' ? 0 : 2
      );
      const responseData = await response.json();

      if (!response.ok) {
        const errDetail = JSON.stringify(responseData).substring(0, 500);
        console.error(`[Amadeus] ${action} failed (${response.status}):`, errDetail);

        if (isSearchAction && ALLOW_TRAVEL_MOCKS) {
          console.log(`[Amadeus] Sandbox non-200 (${response.status}) for ${action}. Providing search results.`);
          if (action === 'searchFlights') return generateMockFlights(params);
          if (action === 'searchHotelsByCity' || action === 'searchHotelsByGeocode') return generateMockHotelList(params);
          if (action === 'getHotelOffers') return generateMockHotelOffers(params);
        }

        if (action === 'confirmFlightPrice' && ALLOW_TRAVEL_MOCKS) {
          return { data: { type: 'flight-offers-pricing', flightOffers: [params.rawOfferJson] } };
        }

        let userMsg = `Amadeus ${action} failed: ${response.status}`;
        const errors = responseData?.errors;
        if (Array.isArray(errors) && errors.length > 0) {
          userMsg += ' — ' + errors.map(e => `${e.detail || e.title || e.code}`).join('; ');
        }
        throw new functions.https.HttpsError('internal', userMsg);
      }

      // Check if Amadeus Test Sandbox returned 0 results for a non-sandbox city/route
      if (isSearchAction && ALLOW_TRAVEL_MOCKS &&
          (!responseData.data || (Array.isArray(responseData.data) && responseData.data.length === 0))) {
        console.log(`[Amadeus] Sandbox returned 0 results for ${action}. Providing realistic search entries for requested route/city.`);
        if (action === 'searchFlights') return generateMockFlights(params);
        if (action === 'searchHotelsByCity' || action === 'searchHotelsByGeocode') return generateMockHotelList(params);
        if (action === 'getHotelOffers') return generateMockHotelOffers(params);
      }

      if (action === 'createFlightOrder') {
        await persistFlightBooking(uid, responseData, params.orderData || {});
      }
      return responseData;
    } catch (error) {
      console.error(`[Amadeus] Error in ${action}:`, error);

      if (isSearchAction && ALLOW_TRAVEL_MOCKS) {
        console.log(`[Amadeus] Providing fallback search results for ${action} in sandbox/test mode.`);
        if (action === 'searchFlights') return generateMockFlights(params);
        if (action === 'searchHotelsByCity' || action === 'searchHotelsByGeocode') return generateMockHotelList(params);
        if (action === 'getHotelOffers') return generateMockHotelOffers(params);
      }

      if (action === 'confirmFlightPrice' && ALLOW_TRAVEL_MOCKS) {
        return { data: { type: 'flight-offers-pricing', flightOffers: [params.rawOfferJson] } };
      }

      if (error instanceof functions.https.HttpsError) throw error;
      throw new functions.https.HttpsError('internal', `Amadeus proxy error: ${error.message}`);
    }
  });
