/**
 * CORS Proxy modules: Radio Browser, Google Places.
 */
const { functions } = require("./shared");

/**
 * ==================================================================
 * 2. RADIO PROXY (Restored)
 * ==================================================================
 */

exports.radioProxy = functions.https.onRequest(async (req, res) => {
  const endpoint = req.query.endpoint;
  if (!endpoint) {
    res.status(400).send('Missing endpoint parameter');
    return;
  }

  // Base URL for Radio Browser API (Primary Mirror)
  const baseUrl = 'https://de1.api.radio-browser.info/json';

  // Construct full URL
  const cleanEndpoint = endpoint.startsWith('/') ? endpoint.substring(1) : endpoint;
  const finalPath = cleanEndpoint.startsWith('stations/') ? cleanEndpoint : `stations/${cleanEndpoint}`;
  const targetUrl = `${baseUrl}/${finalPath}`;

  console.log(`[RadioProxy] Proxying to: ${targetUrl}`);

  try {
    const response = await fetch(targetUrl);
    if (!response.ok) {
      throw new Error(`Upstream returned ${response.status}`);
    }
    const data = await response.json();
    res.set('Access-Control-Allow-Origin', '*'); // Enable CORS
    res.json(data);
  } catch (error) {
    console.error('[RadioProxy] Error:', error);
    res.status(500).send(`Proxy Error: ${error.message}`);
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

exports.placesProxy = functions.https.onRequest(async (req, res) => {
  // Handle CORS preflight
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Access-Control-Allow-Methods', 'GET, OPTIONS');
  res.set('Access-Control-Allow-Headers', 'Content-Type');

  if (req.method === 'OPTIONS') {
    res.status(204).send('');
    return;
  }

  const type = req.query.type; // 'autocomplete' or 'details'
  const apiKey = req.query.key;

  if (!type || !apiKey) {
    res.status(400).json({ error: 'Missing type or key parameter' });
    return;
  }

  try {
    let targetUrl;

    if (type === 'autocomplete') {
      const input = req.query.input;
      const sessiontoken = req.query.sessiontoken || '';
      const types = req.query.types || '';

      if (!input) {
        res.status(400).json({ error: 'Missing input parameter' });
        return;
      }

      targetUrl = `https://maps.googleapis.com/maps/api/place/autocomplete/json?input=${encodeURIComponent(input)}&key=${apiKey}&sessiontoken=${sessiontoken}`;
      if (types) {
        targetUrl += `&types=${encodeURIComponent(types)}`;
      }
    } else if (type === 'details') {
      const placeId = req.query.place_id;
      const fields = req.query.fields || '';
      const sessiontoken = req.query.sessiontoken || '';

      if (!placeId) {
        res.status(400).json({ error: 'Missing place_id parameter' });
        return;
      }

      targetUrl = `https://maps.googleapis.com/maps/api/place/details/json?place_id=${placeId}&key=${apiKey}`;
      if (fields) {
        targetUrl += `&fields=${encodeURIComponent(fields)}`;
      }
      if (sessiontoken) {
        targetUrl += `&sessiontoken=${sessiontoken}`;
      }
    } else {
      res.status(400).json({ error: 'Invalid type. Use "autocomplete" or "details".' });
      return;
    }

    console.log(`[PlacesProxy] Proxying ${type} request`);
    const response = await fetch(targetUrl);
    const data = await response.json();
    res.json(data);
  } catch (error) {
    console.error('[PlacesProxy] Error:', error);
    res.status(500).json({ error: `Proxy Error: ${error.message}` });
  }
});
