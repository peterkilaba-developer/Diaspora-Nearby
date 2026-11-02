/**
 * Diaspora Nearby – Multilingual Diaspora AI Agent Engine
 *
 * Replaces the Founder welcome chat with a 24/7 multilingual AI Concierge
 * ("Diaspora AI Agent") capable of answering any platform/diaspora question,
 * searching live flights, hotels, stays, car rentals, jobs, marketplace items,
 * real estate, events, and nearby communities, and preparing/publishing
 * user listings via one-tap in-chat action buttons.
 */

const {
  functions,
  admin,
  db,
} = require("./shared");
const {
  requireAuth,
  requireAppCheck,
  consumeRateLimit,
} = require("./security");
const axios = require("axios");
const {
  fetchRealFlightsFromGoogle,
  fetchRealHotelsFromPlaces,
} = require("./travel");

function validId(value) {
  return typeof value === "string" &&
    value.trim().length > 0 &&
    value.trim().length <= 150 &&
    !value.includes("/");
}

const DIASPORA_AI_AGENT_UID = "diaspora_ai_agent";
const DIASPORA_AI_AGENT_NAME = "Diaspora AI Agent";
const DIASPORA_AI_AGENT_AVATAR = "https://diasporanearby.com/icons/Icon-512.png";

// ── Environment & Firestore Config Fallback for AI Keys ──
let _aiConfigLoaded = false;
async function ensureAiConfigEnv() {
  if (_aiConfigLoaded && process.env.GEMINI_API_KEY) {
    return;
  }
  try {
    const doc = await db.collection("_internalConfig").doc("social").get();
    if (doc.exists) {
      const d = doc.data() || {};
      if (!process.env.GEMINI_API_KEY && d.geminiApiKey) {
        process.env.GEMINI_API_KEY = String(d.geminiApiKey);
      }
      if (!process.env.NVIDIA_API_KEY && d.nvidiaApiKey) {
        process.env.NVIDIA_API_KEY = String(d.nvidiaApiKey);
      }
      _aiConfigLoaded = true;
    }
  } catch (err) {
    console.warn("[AI Agent] Could not load _internalConfig/social fallback:", err.message);
  }
}

// ── Ensure Canonical AI Agent User Profile Exists in Firestore ──
let _agentProfileEnsured = false;
async function ensureAiAgentProfile() {
  if (_agentProfileEnsured) return;
  try {
    const ref = db.collection("users").doc(DIASPORA_AI_AGENT_UID);
    const snap = await ref.get();
    const agentData = {
      uid: DIASPORA_AI_AGENT_UID,
      firstName: "Diaspora",
      lastName: "AI Agent",
      fullName: DIASPORA_AI_AGENT_NAME,
      profileImage: DIASPORA_AI_AGENT_AVATAR,
      photoUrl: DIASPORA_AI_AGENT_AVATAR,
      occupation: "AI Concierge • Multilingual 24/7",
      bio: "Your 24/7 multilingual Diaspora Nearby AI Agent. Ask me anything, search flights, hotels, jobs, car rentals, or post listings right from chat in any language!",
      isAiAgent: true,
      isDiscoverable: false,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };
    if (!snap.exists || snap.data()?.fullName !== DIASPORA_AI_AGENT_NAME) {
      await ref.set(agentData, {merge: true});
    }
    _agentProfileEnsured = true;
  } catch (err) {
    console.warn("[AI Agent] Failed to ensure agent profile:", err.message);
  }
}

// ── Native Greeting Resolver by Home Country ──
function resolveNativeGreeting(profile = {}) {
  const code = String(profile.homeCountryCode || "").trim().toUpperCase();
  const country = String(profile.homeCountry || "").trim().toLowerCase();

  const codeMap = {
    TZ: "Karibu sana",
    KE: "Karibu sana",
    UG: "Karibu / Tukusanyukidde",
    RW: "Murakaza neza",
    BI: "Ikaze",
    CD: "Boyei bolamu / Karibu",
    NG: "Nnọọ • E kaabo • Barka da zuwa",
    GH: "Akwaaba",
    ET: "እንኳን ደህና መጡ (Enkwan dehan metahu)",
    ER: "እንቋዕ ብደሓን መጻእኩም",
    ZA: "Siyakwamukela / Wamkelekile",
    ZW: "Mauya / Siyalemukela",
    ZM: "Mwaiseni",
    MW: "Takulandirani",
    SN: "Dalal ak jàmm • Bienvenue",
    CI: "Akwaba • Bienvenue",
    CM: "Bienvenue / Welcome",
    HT: "Byenvini",
    FR: "Bienvenue",
    BE: "Bienvenue / Welkom",
    CH: "Willkommen / Bienvenue",
    EG: "مرحباً بك (Marhaban)",
    MA: "مرحباً بك (Marhaban)",
    DZ: "مرحباً بك (Marhaban)",
    TN: "مرحباً بك (Marhaban)",
    SD: "مرحباً بك (Marhaban)",
    SA: "مرحباً بك (Marhaban)",
    AE: "مرحباً بك (Marhaban)",
    SO: "Soo dhowoow",
    IN: "नमस्ते (Namaste)",
    PK: "خوش آمدید (Khush Amdeed)",
    BD: "স্বাগতম (Swagotom)",
    CN: "欢迎 (Huānyíng)",
    TW: "歡迎 (Huānyíng)",
    JP: "ようこそ (Yōkoso)",
    KR: "환영합니다 (Hwanyeonghamnida)",
    PH: "Maligayang pagdating",
    VN: "Chào mừng",
    TR: "Hoş geldiniz",
    DE: "Herzlich willkommen",
    IT: "Benvenuto",
    ES: "¡Bienvenido/a",
    MX: "¡Bienvenido/a",
    CO: "¡Bienvenido/a",
    AR: "¡Bienvenido/a",
    PE: "¡Bienvenido/a",
    BR: "Bem-vindo(a)",
    PT: "Bem-vindo(a)",
    AO: "Bem-vindo(a)",
    MZ: "Bem-vindo(a)",
    RU: "Добро пожаловать",
    UA: "Ласкаво просимо",
    PL: "Witamy",
    NL: "Welkom",
    SE: "Välkommen",
    NO: "Velkommen",
    GR: "Καλώς ήρθατε",
    IL: "ברוכים הבאים (Bruchim Haba'im)",
  };

  if (code && codeMap[code]) return codeMap[code];
  if (country.includes("tanzania") || country.includes("kenya")) return "Karibu sana";
  if (country.includes("nigeria")) return "Nnọọ • E kaabo • Barka da zuwa";
  if (country.includes("ghana")) return "Akwaaba";
  if (country.includes("ethiopia")) return "እንኳን ደህና መጡ (Enkwan dehan metahu)";
  if (country.includes("south africa")) return "Siyakwamukela";
  if (country.includes("china")) return "欢迎 (Huānyíng)";
  if (country.includes("india")) return "नमस्ते (Namaste)";
  return "Karibu • Welcome • Bienvenue";
}

function buildAiAgentWelcomeText(profile = {}) {
  const firstName = String(profile.firstName || "").trim();
  const greeting = resolveNativeGreeting(profile);
  const namePart = firstName ? `, ${firstName}` : "";
  const homeCountry = String(profile.homeCountry || "").trim();
  const hostCity = String(profile.hostCity || profile.currentCity || "").trim();
  const corridorNote = homeCountry && hostCity ?
    ` connecting your ${homeCountry} roots with ${hostCity} and the global diaspora` :
    "";

  return `${greeting}${namePart}!\n\n` +
    `I am **Diaspora AI Agent**, your 24/7 personal concierge on Diaspora Nearby${corridorNote}.\n\n` +
    `**Any Language**: Speak to me in English, Kiswahili, Français, العربية, Español, 中文, हिन्दी, Yoruba, Igbo, Hausa, Amharic, or any language you prefer.\n\n` +
    `Here is what I can do for you right here in chat:\n` +
    `• **Flights, Hotels & Car Rentals**: Search live flights, hotels, stays & peer car rentals or list your own car/stay.\n` +
    `• **Jobs & Marketplace**: Find jobs, products, services & real estate — or tell me the details and I'll generate an instant **Publish** button right in chat.\n` +
    `• **Diaspora Utilities**: Ask me anything about Nearby Discovery, Live Homeland Radio, Ubuntu Emergency Fund, DDI Loans, or $DIASPORA.\n\n` +
    `What can I help you find or post today?`;
}

function buildWelcomeAiActions() {
  return [
    {
      id: "welcome_flights",
      type: "navigate",
      label: "Search Flights",
      route: "/dsp/travel/flights",
      icon: "flight",
    },
    {
      id: "welcome_hotels",
      type: "navigate",
      label: "Find Hotels",
      route: "/dsp/travel/hotels",
      icon: "hotel",
    },
    {
      id: "welcome_cars",
      type: "navigate",
      label: "Car Rentals",
      route: "/dsp/travel/car-rental",
      icon: "car",
    },
    {
      id: "welcome_jobs",
      type: "navigate",
      label: "Browse Jobs",
      route: "/marketplace?type=job",
      icon: "briefcase",
    },
    {
      id: "welcome_post_job",
      type: "prompt",
      label: "Post a Job in Chat",
      prompt: "I want to post a job listing.",
      icon: "plus",
    },
    {
      id: "welcome_nearby",
      type: "navigate",
      label: "Explore Nearby",
      route: "/nearby",
      icon: "compass",
    },
  ];
}

// ── Common City / Airport Name to IATA Resolver ──
const CITY_TO_IATA = {
  "dar es salaam": "DAR",
  "dar": "DAR",
  "kilimanjaro": "JRO",
  "arusha": "JRO",
  "zanzibar": "ZNZ",
  "mwanza": "MWZ",
  "dodoma": "DOD",
  "nairobi": "NBO",
  "mombasa": "MBA",
  "entebbe": "EBB",
  "kampala": "EBB",
  "kigali": "KGL",
  "bujumbura": "BJM",
  "addis ababa": "ADD",
  "addis": "ADD",
  "lagos": "LOS",
  "abuja": "ABV",
  "accra": "ACC",
  "johannesburg": "JNB",
  "joburg": "JNB",
  "cape town": "CPT",
  "durban": "DUR",
  "cairo": "CAI",
  "casablanca": "CMN",
  "dakar": "DSS",
  "abidjan": "ABJ",
  "lusaka": "LUN",
  "harare": "HRE",
  "lilongwe": "LLW",
  "kinshasa": "FIH",
  "luanda": "LAD",
  "maputo": "MPM",
  "dubai": "DXB",
  "abu dhabi": "AUH",
  "doha": "DOH",
  "istanbul": "IST",
  "london": "LHR",
  "manchester": "MAN",
  "paris": "CDG",
  "amsterdam": "AMS",
  "frankfurt": "FRA",
  "brussels": "BRU",
  "zurich": "ZRH",
  "rome": "FCO",
  "madrid": "MAD",
  "new york": "JFK",
  "nyc": "JFK",
  "newark": "EWR",
  "washington": "IAD",
  "dc": "IAD",
  "dmv": "IAD",
  "dallas": "DFW",
  "houston": "IAH",
  "atlanta": "ATL",
  "chicago": "ORD",
  "los angeles": "LAX",
  "la": "LAX",
  "san francisco": "SFO",
  "seattle": "SEA",
  "boston": "BOS",
  "miami": "MIA",
  "minneapolis": "MSP",
  "phoenix": "PHX",
  "des moines": "DSM",
  "toronto": "YYZ",
  "montreal": "YUL",
  "vancouver": "YVR",
  "beijing": "PEK",
  "guangzhou": "CAN",
  "shanghai": "PVG",
  "mumbai": "BOM",
  "delhi": "DEL",
  "new delhi": "DEL",
  "tokyo": "HND",
  "sydney": "SYD",
  "melbourne": "MEL",
};

function resolveIataCode(input) {
  if (!input) return "";
  const raw = String(input).trim();
  if (/^[A-Za-z]{3}$/.test(raw)) {
    return raw.toUpperCase();
  }
  const lower = raw.toLowerCase();
  if (CITY_TO_IATA[lower]) return CITY_TO_IATA[lower];
  for (const [city, code] of Object.entries(CITY_TO_IATA)) {
    if (lower.includes(city)) return code;
  }
  const match = raw.match(/\b([A-Z]{3})\b/);
  if (match) return match[1];
  return raw.slice(0, 3).toUpperCase();
}

function resolveDefaultFutureDate(daysFromNow = 14) {
  const d = new Date(Date.now() + daysFromNow * 24 * 60 * 60 * 1000);
  return d.toISOString().split("T")[0];
}

// ── Live Tool Executors ──

async function executeSearchFlightsTool(args = {}) {
  const originIata = resolveIataCode(args.origin || args.originIata || "DFW");
  const destinationIata = resolveIataCode(args.destination || args.destinationIata || "DAR");
  let departureDate = String(args.departureDate || "").trim();
  if (!/^\d{4}-\d{2}-\d{2}$/.test(departureDate)) {
    departureDate = resolveDefaultFutureDate(14);
  }
  const returnDate = /^\d{4}-\d{2}-\d{2}$/.test(String(args.returnDate || "").trim()) ?
    String(args.returnDate).trim() :
    undefined;
  const adults = Number(args.adults) > 0 ? Number(args.adults) : 1;
  const currencyCode = String(args.currencyCode || "USD").toUpperCase();

  try {
    const result = await fetchRealFlightsFromGoogle({
      originLocationCode: originIata,
      destinationLocationCode: destinationIata,
      departureDate,
      returnDate,
      adults,
      currencyCode,
      max: 5,
    });
    const offers = Array.isArray(result?.data) ? result.data.slice(0, 4) : [];
    const carriers = result?.dictionaries?.carriers || {};

    const summaryOffers = offers.map((offer) => {
      const price = offer?.price?.grandTotal || offer?.price?.total || "N/A";
      const curr = offer?.price?.currency || currencyCode;
      const firstSeg = offer?.itineraries?.[0]?.segments?.[0] || {};
      const lastSegs = offer?.itineraries?.[0]?.segments || [];
      const lastSeg = lastSegs[lastSegs.length - 1] || firstSeg;
      const carrierCode = firstSeg.carrierCode || (offer.validatingAirlineCodes || [])[0] || "";
      const airlineName = carriers[carrierCode] || carrierCode || "Airline";
      const stops = Math.max(0, lastSegs.length - 1);
      return {
        airline: airlineName,
        price: `${curr} ${price}`,
        departure: firstSeg?.departure?.at || departureDate,
        arrival: lastSeg?.arrival?.at || "",
        stops,
        origin: originIata,
        destination: destinationIata,
      };
    });

    return {
      originIata,
      destinationIata,
      departureDate,
      returnDate: returnDate || null,
      offersCount: summaryOffers.length,
      offers: summaryOffers,
      aiAction: {
        id: `flight_${originIata}_${destinationIata}_${Date.now()}`,
        type: "navigate",
        label: `View Flights (${originIata} to ${destinationIata})`,
        route: "/dsp/travel/flights",
        icon: "flight",
      },
    };
  } catch (err) {
    console.warn("[AI Agent] Flight search fallback:", err.message);
    return {
      originIata,
      destinationIata,
      departureDate,
      offersCount: 0,
      offers: [],
      note: "Live flight feed requires interactive search on the Flights screen.",
      aiAction: {
        id: `flight_${originIata}_${destinationIata}_${Date.now()}`,
        type: "navigate",
        label: `Search Flights (${originIata} to ${destinationIata})`,
        route: "/dsp/travel/flights",
        icon: "flight",
      },
    };
  }
}

async function executeSearchHotelsTool(args = {}) {
  const cityOrQuery = String(args.city || args.locationQuery || "Dar es Salaam").trim();
  const cityCode = resolveIataCode(args.cityCode || cityOrQuery);

  try {
    const hotelsRes = await fetchRealHotelsFromPlaces({
      keyword: cityOrQuery,
      cityCode,
    });
    const hotels = Array.isArray(hotelsRes?.data) ? hotelsRes.data.slice(0, 4) : [];
    const summaryHotels = hotels.map((h) => ({
      name: h.name,
      rating: h.rating || 4.5,
      address: h.address?.lines?.[0] || cityOrQuery,
      amenities: (h.amenities || []).slice(0, 4),
    }));

    return {
      location: cityOrQuery,
      hotelsCount: summaryHotels.length,
      hotels: summaryHotels,
      aiAction: {
        id: `hotel_${Date.now()}`,
        type: "navigate",
        label: `View Hotels in ${cityOrQuery}`,
        route: "/dsp/travel/hotels",
        icon: "hotel",
      },
    };
  } catch (err) {
    console.warn("[AI Agent] Hotel search fallback:", err.message);
    return {
      location: cityOrQuery,
      hotelsCount: 0,
      hotels: [],
      aiAction: {
        id: `hotel_${Date.now()}`,
        type: "navigate",
        label: `Browse Hotels in ${cityOrQuery}`,
        route: "/dsp/travel/hotels",
        icon: "hotel",
      },
    };
  }
}

async function executeSearchCarRentalsAndStaysTool(args = {}) {
  const listingType = String(args.type || "car").toLowerCase(); // "car" | "stay" | "hotel"
  const city = String(args.city || "").trim().toLowerCase();
  const snap = await db.collection("peer_listings")
      .where("type", "==", listingType === "stay" ? "stay" : "car")
      .limit(20)
      .get();

  let docs = snap.docs
      .map((d) => ({id: d.id, ...d.data()}))
      .filter((item) => item.isAvailable !== false);

  if (city) {
    const filtered = docs.filter((item) =>
      String(item.city || "").toLowerCase().includes(city) ||
      String(item.title || "").toLowerCase().includes(city) ||
      String(item.description || "").toLowerCase().includes(city),
    );
    if (filtered.length > 0) docs = filtered;
  }

  const topItems = docs.slice(0, 4).map((item) => ({
    id: item.id,
    title: item.title,
    city: item.city,
    pricePerDay: item.pricePerDay,
    currency: item.currency || "USD",
    details: item.details || {},
  }));

  const route = listingType === "stay" ? "/dsp/travel/stays" : "/dsp/travel/car-rental";
  const label = listingType === "stay" ?
    `View Stays${args.city ? ` in ${args.city}` : ""}` :
    `View Car Rentals${args.city ? ` in ${args.city}` : ""}`;

  return {
    type: listingType,
    count: topItems.length,
    listings: topItems,
    aiAction: {
      id: `peer_${listingType}_${Date.now()}`,
      type: "navigate",
      label,
      route,
      icon: listingType === "stay" ? "hotel" : "car",
    },
  };
}

async function executeSearchJobsAndMarketplaceTool(args = {}) {
  const listingType = String(args.listingType || "job").toLowerCase(); // "job" | "product" | "service"
  const keyword = String(args.keyword || "").trim().toLowerCase();
  const city = String(args.city || "").trim().toLowerCase();

  const snap = await db.collection("marketplace_listings")
      .where("status", "==", "active")
      .limit(30)
      .get();

  let items = snap.docs.map((d) => ({id: d.id, ...d.data()}));
  if (listingType && ["job", "product", "service"].includes(listingType)) {
    const byType = items.filter((i) => String(i.listingType || "product") === listingType);
    if (byType.length > 0 || listingType === "job") {
      items = byType;
    }
  }
  if (city) {
    const byCity = items.filter((i) =>
      String(i.city || "").toLowerCase().includes(city) ||
      String(i.country || "").toLowerCase().includes(city),
    );
    if (byCity.length > 0) items = byCity;
  }
  if (keyword) {
    const byKw = items.filter((i) =>
      String(i.title || "").toLowerCase().includes(keyword) ||
      String(i.description || "").toLowerCase().includes(keyword) ||
      String(i.companyName || "").toLowerCase().includes(keyword) ||
      String(i.category || "").toLowerCase().includes(keyword),
    );
    if (byKw.length > 0) items = byKw;
  }

  const top = items.slice(0, 4).map((i) => ({
    id: i.id,
    title: i.title,
    listingType: i.listingType,
    companyName: i.companyName || i.sellerName || "",
    city: i.city || "",
    country: i.country || "",
    salaryRange: i.salaryRange || (i.priceAmount ? `${i.currency || "USD"} ${i.priceAmount}` : "Negotiable"),
    employmentType: i.employmentType || "",
  }));

  const actions = [];
  if (top.length > 0) {
    actions.push({
      id: `mkt_item_${top[0].id}`,
      type: "navigate",
      label: `View "${top[0].title}"`,
      route: `/marketplace/listing/${top[0].id}`,
      icon: "briefcase",
    });
  }
  actions.push({
    id: `mkt_browse_${Date.now()}`,
    type: "navigate",
    label: listingType === "job" ? "Browse All Jobs" : `Browse Marketplace (${listingType}s)`,
    route: `/marketplace?type=${listingType}`,
    icon: "briefcase",
  });

  return {
    listingType,
    count: top.length,
    listings: top,
    aiActions: actions,
  };
}

async function executeSearchRealEstateTool(args = {}) {
  const category = String(args.category || "house").toLowerCase(); // "plot" | "farm" | "house"
  const city = String(args.city || "").trim().toLowerCase();

  const snap = await db.collection("real_estate_listings")
      .where("status", "==", "active")
      .limit(20)
      .get();

  let items = snap.docs.map((d) => ({id: d.id, ...d.data()}));
  if (["plot", "farm", "house"].includes(category)) {
    const byCat = items.filter((i) => i.category === category);
    if (byCat.length > 0) items = byCat;
  }
  if (city) {
    const byCity = items.filter((i) =>
      String(i.city || "").toLowerCase().includes(city) ||
      String(i.country || "").toLowerCase().includes(city),
    );
    if (byCity.length > 0) items = byCity;
  }

  const top = items.slice(0, 4).map((i) => ({
    id: i.id,
    title: i.title,
    category: i.category,
    price: `${i.currency || "USD"} ${i.price}`,
    sizeSqm: i.sizeSqm,
    city: i.city,
    country: i.country,
    listingType: i.listingType,
  }));

  const validCat = ["plot", "farm", "house"].includes(category) ? category : "house";
  return {
    category: validCat,
    count: top.length,
    listings: top,
    aiAction: {
      id: `re_${validCat}_${Date.now()}`,
      type: "navigate",
      label: `View Real Estate (${validCat.toUpperCase()})`,
      route: `/dsp/real-estate/${validCat}`,
      icon: "home",
    },
  };
}

async function executeSearchEventsTool(args = {}) {
  const city = String(args.city || "").trim().toLowerCase();
  const snap = await db.collection("events")
      .where("status", "==", "published")
      .limit(15)
      .get();

  let items = snap.docs.map((d) => ({id: d.id, ...d.data()}));
  if (city) {
    const byCity = items.filter((i) => String(i.location || "").toLowerCase().includes(city));
    if (byCity.length > 0) items = byCity;
  }

  const top = items.slice(0, 4).map((e) => ({
    id: e.id,
    title: e.title,
    location: e.location,
    category: e.category,
    isFree: e.isFree !== false,
  }));

  return {
    count: top.length,
    events: top,
    aiAction: {
      id: `events_${Date.now()}`,
      type: "navigate",
      label: top.length > 0 ? `View "${top[0].title}"` : "Explore Diaspora Events",
      route: top.length > 0 ? `/events/${top[0].id}` : "/events",
      icon: "calendar",
    },
  };
}

// ── Draft Action Builders (Write Flows with In-Chat Confirmation Button) ──

function buildDraftAction({draftType, label, summaryTitle, summaryRows, payload, fallbackRoute}) {
  return {
    id: `draft_${draftType}_${Date.now()}`,
    type: "execute_draft",
    draftType,
    label,
    summaryTitle,
    summaryRows,
    payload,
    fallbackRoute,
    status: "pending",
  };
}

function prepareJobDraftTool(args = {}, userProfile = {}) {
  const title = String(args.title || "").trim();
  const companyName = String(args.companyName || userProfile.company || userProfile.fullName || "Diaspora Employer").trim();
  const city = String(args.city || userProfile.hostCity || userProfile.currentCity || "Dar es Salaam").trim();
  const country = String(args.country || userProfile.hostCountry || userProfile.homeCountry || "Tanzania").trim();
  const employmentType = String(args.employmentType || "Full-time").trim();
  const salaryRange = String(args.salaryRange || "Competitive / Negotiable").trim();
  const description = String(args.description || `${title} role at ${companyName} in ${city}, ${country}.`).trim();
  const category = String(args.category || "job_other").trim();
  const applicationUrl = String(args.applicationUrl || "").trim();

  if (!title) {
    return {
      ready: false,
      missingFields: ["title", "city", "description or salaryRange"],
    };
  }

  const draftAction = buildDraftAction({
    draftType: "post_job",
    label: `Publish Job: ${title}`,
    summaryTitle: `Job Listing: ${title}`,
    summaryRows: [
      {label: "Company", value: companyName},
      {label: "Location", value: `${city}, ${country}`},
      {label: "Type", value: employmentType},
      {label: "Compensation", value: salaryRange},
    ],
    payload: {
      title,
      companyName,
      city,
      country,
      employmentType,
      salaryRange,
      description,
      category,
      applicationUrl,
    },
    fallbackRoute: "/marketplace/create",
  });

  return {
    ready: true,
    draftAction,
  };
}

function prepareCarRentalDraftTool(args = {}, userProfile = {}) {
  const make = String(args.make || "").trim();
  const model = String(args.model || "").trim();
  const year = Number(args.year) || new Date().getFullYear();
  const pricePerDay = Number(args.pricePerDay) || 45;
  const currency = String(args.currency || "USD").toUpperCase();
  const city = String(args.city || userProfile.hostCity || userProfile.currentCity || "Dar es Salaam").trim();
  const transmission = String(args.transmission || "Automatic").trim();
  const fuelType = String(args.fuelType || "Petrol").trim();
  const seats = Number(args.seats) || 5;
  const title = String(args.title || `${year} ${make} ${model}`.trim()).trim();
  const description = String(
      args.description ||
      `Clean, reliable ${title} available for daily rental in ${city}. ${transmission}, ${fuelType}, ${seats} seats.`,
  ).trim();

  if (!make && !args.title) {
    return {
      ready: false,
      missingFields: ["make/model", "pricePerDay", "city"],
    };
  }

  const draftAction = buildDraftAction({
    draftType: "post_car_rental",
    label: `Publish Car Rental: ${title}`,
    summaryTitle: `Car Rental: ${title}`,
    summaryRows: [
      {label: "City", value: city},
      {label: "Rate", value: `${currency} ${pricePerDay} / day`},
      {label: "Specs", value: `${transmission} • ${fuelType} • ${seats} seats`},
    ],
    payload: {
      title,
      make: make || title,
      model,
      year,
      pricePerDay,
      currency,
      city,
      transmission,
      fuelType,
      seats,
      description,
    },
    fallbackRoute: "/dsp/travel/car-rental",
  });

  return {
    ready: true,
    draftAction,
  };
}

function prepareStayOrHotelDraftTool(args = {}, userProfile = {}) {
  const subType = String(args.subType || "stay").toLowerCase() === "hotel" ? "hotel" : "stay";
  const title = String(args.title || "").trim();
  const city = String(args.city || userProfile.hostCity || userProfile.currentCity || "Dar es Salaam").trim();
  const pricePerNight = Number(args.pricePerNight || args.pricePerDay) || 65;
  const currency = String(args.currency || "USD").toUpperCase();
  const propertyType = String(args.propertyType || (subType === "hotel" ? "Boutique Hotel" : "Entire Apartment")).trim();
  const beds = Number(args.beds) || 2;
  const maxGuests = Number(args.maxGuests) || 4;
  const description = String(
      args.description || `${title} in ${city} — ${propertyType}, ${beds} bed(s), up to ${maxGuests} guests.`,
  ).trim();

  if (!title) {
    return {
      ready: false,
      missingFields: ["title", "city", "pricePerNight"],
    };
  }

  const draftAction = buildDraftAction({
    draftType: "post_stay",
    label: `Publish ${subType === "hotel" ? "Hotel" : "Stay"}: ${title}`,
    summaryTitle: `${subType === "hotel" ? "Hotel" : "Stay"}: ${title}`,
    summaryRows: [
      {label: "Location", value: city},
      {label: "Rate", value: `${currency} ${pricePerNight} / night`},
      {label: "Property", value: `${propertyType} • ${beds} beds • ${maxGuests} guests`},
    ],
    payload: {
      subType,
      title,
      city,
      pricePerNight,
      currency,
      propertyType,
      beds,
      maxGuests,
      description,
    },
    fallbackRoute: subType === "hotel" ? "/dsp/travel/hotels" : "/dsp/travel/stays",
  });

  return {
    ready: true,
    draftAction,
  };
}

function prepareMarketplaceDraftTool(args = {}, userProfile = {}) {
  const listingType = String(args.listingType || "product").toLowerCase() === "service" ? "service" : "product";
  const title = String(args.title || "").trim();
  const priceAmount = Number(args.priceAmount || args.price) || 0;
  const currency = String(args.currency || "USD").toUpperCase();
  const city = String(args.city || userProfile.hostCity || userProfile.currentCity || "Dar es Salaam").trim();
  const country = String(args.country || userProfile.hostCountry || userProfile.homeCountry || "Tanzania").trim();
  const category = String(args.category || (listingType === "service" ? "service_consulting" : "other")).trim();
  const description = String(args.description || `${title} available in ${city}, ${country}.`).trim();

  if (!title) {
    return {
      ready: false,
      missingFields: ["title", "priceAmount", "city"],
    };
  }

  const draftAction = buildDraftAction({
    draftType: "post_marketplace",
    label: `Publish ${listingType === "service" ? "Service" : "Listing"}: ${title}`,
    summaryTitle: `Marketplace: ${title}`,
    summaryRows: [
      {label: "Type", value: listingType.toUpperCase()},
      {label: "Price", value: priceAmount > 0 ? `${currency} ${priceAmount}` : "Negotiable"},
      {label: "Location", value: `${city}, ${country}`},
    ],
    payload: {
      listingType,
      title,
      priceAmount,
      currency,
      city,
      country,
      category,
      description,
    },
    fallbackRoute: "/marketplace/create",
  });

  return {
    ready: true,
    draftAction,
  };
}

function prepareRealEstateDraftTool(args = {}, userProfile = {}) {
  const rawCat = String(args.category || "house").toLowerCase();
  const category = ["plot", "farm", "house"].includes(rawCat) ? rawCat : "house";
  const title = String(args.title || "").trim();
  const price = Number(args.price) || 0;
  const currency = String(args.currency || "USD").toUpperCase();
  const sizeSqm = Number(args.sizeSqm) || 500;
  const listingType = String(args.listingType || "sale").toLowerCase() === "rent" ? "rent" : "sale";
  const city = String(args.city || userProfile.homeCity || "Dar es Salaam").trim();
  const country = String(args.country || userProfile.homeCountry || "Tanzania").trim();
  const description = String(args.description || `${title} (${sizeSqm} sqm) for ${listingType} in ${city}, ${country}.`).trim();

  if (!title || price <= 0) {
    return {
      ready: false,
      missingFields: ["title", "price", "city", "sizeSqm"],
    };
  }

  const draftAction = buildDraftAction({
    draftType: "post_real_estate",
    label: `Publish Property: ${title}`,
    summaryTitle: `Property: ${title}`,
    summaryRows: [
      {label: "Category", value: `${category.toUpperCase()} (${listingType.toUpperCase()})`},
      {label: "Price", value: `${currency} ${price.toLocaleString()}`},
      {label: "Size & City", value: `${sizeSqm} sqm • ${city}, ${country}`},
    ],
    payload: {
      category,
      title,
      price,
      currency,
      sizeSqm,
      listingType,
      city,
      country,
      description,
    },
    fallbackRoute: `/dsp/real-estate/${category}`,
  });

  return {
    ready: true,
    draftAction,
  };
}

function prepareEventDraftTool(args = {}, userProfile = {}) {
  const title = String(args.title || "").trim();
  const location = String(args.location || userProfile.hostCity || "Dar es Salaam").trim();
  const startDate = String(args.startDate || resolveDefaultFutureDate(7)).trim();
  const startTime = String(args.startTime || "18:00").trim();
  const category = String(args.category || "Networking").trim();
  const description = String(args.description || `Join us for ${title} at ${location}.`).trim();

  if (!title) {
    return {
      ready: false,
      missingFields: ["title", "startDate", "location"],
    };
  }

  const draftAction = buildDraftAction({
    draftType: "post_event",
    label: `Publish Event: ${title}`,
    summaryTitle: `Event: ${title}`,
    summaryRows: [
      {label: "Date & Time", value: `${startDate} at ${startTime}`},
      {label: "Location", value: location},
      {label: "Category", value: category},
    ],
    payload: {
      title,
      location,
      startDate,
      startTime,
      category,
      description,
    },
    fallbackRoute: "/events/create",
  });

  return {
    ready: true,
    draftAction,
  };
}

// ── System Knowledge Base for Diaspora AI Agent ──
function buildSystemInstruction(userProfile = {}, dspPoints = 0) {
  const fullName = String(userProfile.fullName || userProfile.firstName || "Diaspora Member").trim();
  const homeCountry = String(userProfile.homeCountry || "their homeland").trim();
  const homeCity = String(userProfile.homeCity || "").trim();
  const hostCountry = String(userProfile.hostCountry || "").trim();
  const hostCity = String(userProfile.hostCity || userProfile.currentCity || "").trim();

  return `You are **Diaspora AI Agent**, the official 24/7 multilingual AI Concierge built into the Diaspora Nearby super-app.
Founder & Origin Story: Diaspora Nearby was founded by Peter Swai, who lived across the diaspora for 25+ years (Tanzania -> San Francisco -> Santa Monica -> Iowa -> Washington DC -> Phoenix -> returning home to Tanzania) to unite the global diaspora with their homelands.

CURRENT USER CONTEXT:
- Name: ${fullName}
- Home Country / Origin: ${homeCity ? `${homeCity}, ` : ""}${homeCountry}
- Current Host Location: ${hostCity ? `${hostCity}, ` : ""}${hostCountry || "Global"}
- $DIASPORA / DSP Points Balance: ${dspPoints}

MULTILINGUAL & FORMATTING RULES (CRITICAL):
- Always reply in the EXACT language the user writes in (English, Kiswahili, French, Arabic, Spanish, Portuguese, Chinese, Hindi, Yoruba, Igbo, Hausa, Amharic, Somali, Zulu, etc.).
- If the user asks you to switch languages, switch immediately and naturally.
- NO EMOJIS: Never use emojis in your responses or labels. Keep all text clean, clear, and professional.

CORE PLATFORM KNOWLEDGE:
1. **Nearby Discovery & Nearby Notifications**: Discover verified compatriots from your home country/town living or traveling near you, with real-time proximity alerts.
2. **Live Homeland Radio**: Stream 24/7 live homeland and diaspora radio stations right inside the app (\`/radio\`).
3. **Ubuntu Emergency Fund**: Transparent, community-governed mutual-aid & bereavement (msiba) emergency fund (\`/dsp/emergency-fund\`).
4. **DDI Loans & Chambers of Commerce**: Community-backed micro and project loans and diaspora investment chambers (\`/economy\`).
5. **Travel Hub**: Live flight search & booking (\`/dsp/travel/flights\`), hotels (\`/dsp/travel/hotels\`), stays (\`/dsp/travel/stays\`), and peer-to-peer car rentals (\`/dsp/travel/car-rental\`).
6. **Jobs, Marketplace & Real Estate**: Post or apply for jobs (\`/marketplace?type=job\`), buy/sell products & services (\`/marketplace\`), and browse verified plots, farms, and houses back home (\`/dsp/real-estate\`).
7. **$DIASPORA on Base Blockchain & Remittances**: Earn DSP points for community contributions, send cross-border remittances (\`/dsp/remittances\`), and use the $DIASPORA wallet (\`/dsp/crypto\`).

CAPABILITIES & ACTION RULES:
- You have tools to search live flights, hotels, car rentals, stays, jobs, marketplace items, real estate, and events.
- You also have tools to PREPARE drafts for posting a job, car rental, stay/hotel, marketplace listing, real estate property, or event.
- IMPORTANT FOR POSTING/CREATING:
  - When a user wants to post a job, car rental, stay/hotel, marketplace item, real estate property, or event:
    1. If they haven't provided the essential details yet (e.g., for a job: Job Title, Company/Organization, City, and Salary/Description; for a car rental: Make/Model, Year, Daily Rate, and City), ask them warmly and concisely for those details.
    2. Once they provide the key details (even if only 2-3 core fields like title, city, and price/salary are given—fill sensible defaults for minor fields), call the corresponding \`prepare_post_*\` tool so the app renders an interactive **Publish** action button right inside your chat bubble!
    3. Tell the user they can tap the **Publish** button below your message to publish it immediately with one tap.`;
}

const GEMINI_TOOLS_DECLARATION = [
  {
    functionDeclarations: [
      {
        name: "search_flights",
        description: "Search live flights between two cities or airport IATA codes.",
        parameters: {
          type: "OBJECT",
          properties: {
            origin: {type: "STRING", description: "Origin city or 3-letter IATA code (e.g. DFW, Houston, London, DAR)"},
            destination: {type: "STRING", description: "Destination city or 3-letter IATA code (e.g. DAR, JRO, NBO, LOS, ACC)"},
            departureDate: {type: "STRING", description: "Departure date in YYYY-MM-DD format if specified"},
            returnDate: {type: "STRING", description: "Return date in YYYY-MM-DD format if round-trip"},
            adults: {type: "INTEGER", description: "Number of adult passengers (default 1)"},
          },
          required: ["origin", "destination"],
        },
      },
      {
        name: "search_hotels",
        description: "Search live hotels in a city or location.",
        parameters: {
          type: "OBJECT",
          properties: {
            city: {type: "STRING", description: "City or area name (e.g. Dar es Salaam, Zanzibar, Arusha, Nairobi, Dubai)"},
          },
          required: ["city"],
        },
      },
      {
        name: "search_car_rentals_and_stays",
        description: "Search peer-to-peer car rentals or short-term stays in the app.",
        parameters: {
          type: "OBJECT",
          properties: {
            type: {type: "STRING", description: "'car' for car rentals or 'stay' for short-term stays/apartments"},
            city: {type: "STRING", description: "Optional city filter"},
          },
          required: ["type"],
        },
      },
      {
        name: "search_jobs_and_marketplace",
        description: "Search jobs, products, or services in the Diaspora Marketplace.",
        parameters: {
          type: "OBJECT",
          properties: {
            listingType: {type: "STRING", description: "'job', 'product', or 'service'"},
            keyword: {type: "STRING", description: "Optional search keyword or role title"},
            city: {type: "STRING", description: "Optional city or country filter"},
          },
          required: ["listingType"],
        },
      },
      {
        name: "search_real_estate",
        description: "Search verified real estate listings (plots, farms, houses).",
        parameters: {
          type: "OBJECT",
          properties: {
            category: {type: "STRING", description: "'plot', 'farm', or 'house'"},
            city: {type: "STRING", description: "Optional city or country"},
          },
          required: ["category"],
        },
      },
      {
        name: "search_events",
        description: "Search upcoming diaspora community events.",
        parameters: {
          type: "OBJECT",
          properties: {
            city: {type: "STRING", description: "Optional city filter"},
          },
        },
      },
      {
        name: "prepare_post_job",
        description: "Prepare a job listing draft and render an in-chat Publish Job button once the user provides at least a job title.",
        parameters: {
          type: "OBJECT",
          properties: {
            title: {type: "STRING", description: "Job title (e.g. Senior Accountant, Driver, Software Engineer)"},
            companyName: {type: "STRING", description: "Company or employer name"},
            city: {type: "STRING", description: "City where the job is located"},
            country: {type: "STRING", description: "Country where the job is located"},
            employmentType: {type: "STRING", description: "Full-time, Part-time, Contract, or Remote"},
            salaryRange: {type: "STRING", description: "Salary or pay range (e.g. '$3,000/mo', 'TZS 1,500,000/mo', 'Competitive')"},
            description: {type: "STRING", description: "Job description and responsibilities"},
          },
          required: ["title"],
        },
      },
      {
        name: "prepare_post_car_rental",
        description: "Prepare a car rental listing draft and render an in-chat Publish Car Rental button once the user provides the vehicle make/model and daily rate.",
        parameters: {
          type: "OBJECT",
          properties: {
            make: {type: "STRING", description: "Vehicle make (e.g. Toyota, Mercedes, Subaru)"},
            model: {type: "STRING", description: "Vehicle model (e.g. Land Cruiser Prado, Harrier, Rav4)"},
            year: {type: "INTEGER", description: "Model year (e.g. 2021)"},
            pricePerDay: {type: "NUMBER", description: "Daily rental price"},
            currency: {type: "STRING", description: "Currency code (USD, TZS, KES, etc.)"},
            city: {type: "STRING", description: "City where the car is available"},
            transmission: {type: "STRING", description: "Automatic or Manual"},
            fuelType: {type: "STRING", description: "Petrol, Diesel, Hybrid, or Electric"},
            seats: {type: "INTEGER", description: "Number of seats"},
            description: {type: "STRING", description: "Additional details about the vehicle"},
          },
          required: ["make", "pricePerDay"],
        },
      },
      {
        name: "prepare_post_stay_or_hotel",
        description: "Prepare a stay/apartment or hotel listing draft and render an in-chat Publish button.",
        parameters: {
          type: "OBJECT",
          properties: {
            subType: {type: "STRING", description: "'stay' or 'hotel'"},
            title: {type: "STRING", description: "Name/title of the property or hotel"},
            city: {type: "STRING", description: "City location"},
            pricePerNight: {type: "NUMBER", description: "Nightly rate"},
            currency: {type: "STRING", description: "Currency code (USD, TZS, etc.)"},
            propertyType: {type: "STRING", description: "e.g. Entire Apartment, Villa, Boutique Hotel"},
            beds: {type: "INTEGER", description: "Number of beds"},
            maxGuests: {type: "INTEGER", description: "Max guests"},
            description: {type: "STRING", description: "Description of the stay"},
          },
          required: ["title", "pricePerNight"],
        },
      },
      {
        name: "prepare_post_marketplace",
        description: "Prepare a product or service marketplace listing and render an in-chat Publish button.",
        parameters: {
          type: "OBJECT",
          properties: {
            listingType: {type: "STRING", description: "'product' or 'service'"},
            title: {type: "STRING", description: "Product or service title"},
            priceAmount: {type: "NUMBER", description: "Price amount"},
            currency: {type: "STRING", description: "Currency code (default USD)"},
            city: {type: "STRING", description: "City location"},
            country: {type: "STRING", description: "Country location"},
            description: {type: "STRING", description: "Item or service description"},
          },
          required: ["title"],
        },
      },
      {
        name: "prepare_post_real_estate",
        description: "Prepare a real estate listing (plot, farm, or house) and render an in-chat Publish button.",
        parameters: {
          type: "OBJECT",
          properties: {
            category: {type: "STRING", description: "'plot', 'farm', or 'house'"},
            title: {type: "STRING", description: "Property title"},
            price: {type: "NUMBER", description: "Price amount"},
            currency: {type: "STRING", description: "Currency code (USD, TZS, etc.)"},
            sizeSqm: {type: "NUMBER", description: "Area in square meters"},
            listingType: {type: "STRING", description: "'sale' or 'rent'"},
            city: {type: "STRING", description: "City location"},
            country: {type: "STRING", description: "Country location"},
            description: {type: "STRING", description: "Property description"},
          },
          required: ["title", "price"],
        },
      },
      {
        name: "prepare_post_event",
        description: "Prepare a community event listing and render an in-chat Publish Event button.",
        parameters: {
          type: "OBJECT",
          properties: {
            title: {type: "STRING", description: "Event title"},
            location: {type: "STRING", description: "Venue / city location"},
            startDate: {type: "STRING", description: "Start date (YYYY-MM-DD)"},
            startTime: {type: "STRING", description: "Start time (HH:MM)"},
            category: {type: "STRING", description: "Category (Networking, Cultural, Business, Music)"},
            description: {type: "STRING", description: "Event description"},
          },
          required: ["title", "location"],
        },
      },
      {
        name: "navigate_app_feature",
        description: "Attach a quick navigation button to open a specific screen in Diaspora Nearby.",
        parameters: {
          type: "OBJECT",
          properties: {
            feature: {
              type: "STRING",
              description: "One of: 'nearby', 'radio', 'emergency_fund', 'remittances', 'crypto', 'points', 'economy', 'communities', 'flights', 'hotels', 'car_rental', 'jobs', 'marketplace', 'real_estate', 'events'",
            },
          },
          required: ["feature"],
        },
      },
    ],
  },
];

function resolveFeatureNavigationAction(feature = "") {
  const f = String(feature || "").toLowerCase().trim();
  const map = {
    nearby: {label: "Open Nearby Discovery", route: "/nearby", icon: "compass"},
    radio: {label: "Listen to Live Homeland Radio", route: "/radio", icon: "radio"},
    emergency_fund: {label: "Open Ubuntu Emergency Fund", route: "/dsp/emergency-fund", icon: "shield"},
    remittances: {label: "Send Remittance", route: "/dsp/remittances", icon: "send"},
    crypto: {label: "Open $DIASPORA Wallet", route: "/dsp/crypto", icon: "wallet"},
    points: {label: "View My DSP Points", route: "/dsp/points", icon: "sparkles"},
    economy: {label: "Open Chambers & DDI Loans", route: "/economy", icon: "building"},
    communities: {label: "Browse Diaspora Communities", route: "/communities", icon: "users"},
    flights: {label: "Open Flight Search", route: "/dsp/travel/flights", icon: "flight"},
    hotels: {label: "Open Hotel Search", route: "/dsp/travel/hotels", icon: "hotel"},
    car_rental: {label: "Open Car Rentals", route: "/dsp/travel/car-rental", icon: "car"},
    jobs: {label: "Browse Jobs", route: "/marketplace?type=job", icon: "briefcase"},
    marketplace: {label: "Open Marketplace", route: "/marketplace", icon: "shopping"},
    real_estate: {label: "Open Real Estate Hub", route: "/dsp/real-estate", icon: "home"},
    events: {label: "Open Diaspora Events", route: "/events", icon: "calendar"},
  };
  const target = map[f] || map.nearby;
  return {
    id: `nav_${f}_${Date.now()}`,
    type: "navigate",
    label: target.label,
    route: target.route,
    icon: target.icon,
  };
}

async function runToolCall(name, args, userProfile) {
  switch (name) {
    case "search_flights":
      return await executeSearchFlightsTool(args);
    case "search_hotels":
      return await executeSearchHotelsTool(args);
    case "search_car_rentals_and_stays":
      return await executeSearchCarRentalsAndStaysTool(args);
    case "search_jobs_and_marketplace":
      return await executeSearchJobsAndMarketplaceTool(args);
    case "search_real_estate":
      return await executeSearchRealEstateTool(args);
    case "search_events":
      return await executeSearchEventsTool(args);
    case "prepare_post_job":
      return prepareJobDraftTool(args, userProfile);
    case "prepare_post_car_rental":
      return prepareCarRentalDraftTool(args, userProfile);
    case "prepare_post_stay_or_hotel":
      return prepareStayOrHotelDraftTool(args, userProfile);
    case "prepare_post_marketplace":
      return prepareMarketplaceDraftTool(args, userProfile);
    case "prepare_post_real_estate":
      return prepareRealEstateDraftTool(args, userProfile);
    case "prepare_post_event":
      return prepareEventDraftTool(args, userProfile);
    case "navigate_app_feature":
      return {aiAction: resolveFeatureNavigationAction(args?.feature)};
    default:
      return {error: `Unknown tool ${name}`};
  }
}

// ── Emoji Sanitizer (Guarantees Zero Emojis in AI Replies) ──
function stripEmojis(text = "") {
  return String(text || "")
      .replace(/[\u{1F300}-\u{1FAFF}\u{2600}-\u{27BF}\u{FE0F}]/gu, "")
      .replace(/ {2,}/g, " ")
      .trim();
}

function detectStructuredDraftFromUserText(userText = "", userProfile = {}) {
  const text = String(userText || "").trim();
  const lower = text.toLowerCase();
  if (!text) return null;

  // Check if user is providing job details (e.g. contains salary/pay or employment type or follows job prompt)
  const hasMoney = /(\$|tzs|kes|usd|eur|gbp|\b\d{3,}\b)/i.test(text);
  const hasJobSignal = /\b(full-time|part-time|remote|contract|salary|mshahara|ajira|kampuni|company|hiring|developer|accountant|driver|manager|engineer|nurse|teacher|sales)\b/i.test(lower);
  const hasCarSignal = /\b(toyota|prado|harrier|rav4|mercedes|subaru|nissan|honda|bmw|audi|suzuki|ford|car rental|kodisha gari|per day|\/day|kwa siku)\b/i.test(lower);

  if (hasCarSignal && hasMoney) {
    const yearMatch = text.match(/\b(20\d{2}|199\d)\b/);
    const priceMatch = text.match(/(?:\$|usd\s*)?(\d{2,4})(?:\s*\/\s*day|\s*per\s*day|\s*kwa\s*siku)?/i);
    const makeMatch = text.match(/\b(Toyota|Mercedes|Subaru|Nissan|Honda|BMW|Audi|Suzuki|Ford|Land Rover|Range Rover|Lexus|Mazda|Volkswagen)\s*([A-Za-z0-9\s]{1,20})?/i);
    const make = makeMatch ? makeMatch[1].trim() : "Vehicle";
    const model = makeMatch && makeMatch[2] ? makeMatch[2].trim().split(/[,.]/)[0].trim() : "";
    const year = yearMatch ? Number(yearMatch[1]) : new Date().getFullYear();
    const pricePerDay = priceMatch ? Number(priceMatch[1]) : 50;
    const res = prepareCarRentalDraftTool({
      make,
      model,
      year,
      pricePerDay,
      city: userProfile.hostCity || userProfile.homeCity || "Dar es Salaam",
      description: text,
    }, userProfile);
    if (res.ready && res.draftAction) return res.draftAction;
  }

  if (hasJobSignal && (hasMoney || text.split(/[\n,;]/).length >= 2)) {
    const lines = text.split(/[\n,;]+/).map((s) => s.trim()).filter(Boolean);
    const title = (lines[0] || "Open Position").replace(/^(1\.|job title:?|kichwa cha kazi:?)\s*/i, "").slice(0, 80);
    const companyName = (lines[1] || userProfile.company || userProfile.fullName || "Diaspora Employer")
        .replace(/^(2\.|company:?|kampuni:?)\s*/i, "")
        .slice(0, 80);
    const city = (lines[2] || userProfile.hostCity || userProfile.homeCity || "Dar es Salaam")
        .replace(/^(3\.|city:?|mji:?|location:?)\s*/i, "")
        .slice(0, 60);
    const salaryRange = (lines[3] || "Competitive")
        .replace(/^(4\.|salary:?|mshahara:?)\s*/i, "")
        .slice(0, 60);
    const res = prepareJobDraftTool({
      title,
      companyName,
      city,
      salaryRange,
      description: text,
    }, userProfile);
    if (res.ready && res.draftAction) return res.draftAction;
  }

  return null;
}
function isKiswahiliText(text = "") {
  const lower = String(text || "").toLowerCase();
  return /\b(kiswahili|swahili|unaweza|kuongea|kuzungumza|habari|mambo|shikamoo|vipi|naomba|nataka|natafuta|ndege|hoteli|gari|kazi|ajira|nyumba|kiwanja|redio|msiba|dharura|mkopo|mikopo|ndiyo|asante|karibu|msaada|nisaidie)\b/.test(lower);
}

// ── Heuristic Fallback When API Keys Are Unavailable ──
async function buildIntelligentFallbackResponse(userText, userProfile) {
  const lower = String(userText || "").toLowerCase();
  const isSw = isKiswahiliText(userText);
  const actions = [];

  if (
    lower.includes("kiswahili") ||
    lower.includes("swahili") ||
    lower.includes("unaweza kuongea") ||
    lower.includes("unajua kuongea") ||
    lower.includes("speak") ||
    lower.includes("language") ||
    lower.includes("lugha")
  ) {
    return {
      text: isSw ?
        `Ndiyo, ninaweza kuongea Kiswahili fasaha kabisa! Karibu sana.\n\nUnaweza kuniuliza chochote au kuniagiza nikufanyie mambo yote ndani ya Diaspora Nearby kwa Kiswahili, kama vile:\n• **Kutafuta Ndege (Flights)**: Niambie unatoka mji gani kwenda wapi na tarehe.\n• **Kutafuta Hoteli au Kukodisha Gari**: Niambie mji unaohitaji hoteli au maelezo ya gari lako kama unataka kulipost.\n• **Kutafuta au Kupost Kazi (Jobs)**: Niambie kichwa cha kazi (Job Title), kampuni, mji, na mshahara nami nitakuwekea kitufe cha **Publish** hapa hapa kwenye chat.\n• **Huduma za Diaspora**: Nearby Discovery, Redio za Nyumbani Mubashara, Mfuko wa Dharura wa Ubuntu, na Mikopo ya DDI.\n\nJe, ungependa nikusaidie nini leo?` :
        `Yes, I speak fluent Kiswahili and any other language you prefer. Feel free to chat with me in Kiswahili, English, French, Arabic, Spanish, Chinese, or any native language.\n\nHow can I help you today?`,
      aiActions: buildWelcomeAiActions().slice(0, 4),
    };
  }

  if (lower.includes("flight") || lower.includes("fly") || lower.includes("ndege") || lower.includes("ticket") || lower.includes("tiketi")) {
    const res = await executeSearchFlightsTool({
      origin: userProfile.hostCity || "DFW",
      destination: userProfile.homeCity || "DAR",
    });
    if (res.aiAction) actions.push(res.aiAction);
    const offerLines = (res.offers || [])
        .map((o) => `• **${o.airline}**: ${o.price} (${o.stops === 0 ? "Nonstop" : `${o.stops} stop(s)`})`)
        .join("\n");
    return {
      text: offerLines ?
        (isSw ?
          `Hizi hapa ni chaguzi za ndege kutoka **${res.originIata}** kwenda **${res.destinationIata}** (${res.departureDate}):\n\n${offerLines}\n\nBonyeza hapa chini kubadilisha tarehe au kukata tiketi:` :
          `Here are live flight options from **${res.originIata}** to **${res.destinationIata}** (${res.departureDate}):\n\n${offerLines}\n\nTap below to customize dates or book directly:`) :
        (isSw ?
          `Ninaweza kukusaidia kutafuta na kulinganisha bei za ndege kati ya **${res.originIata}** na **${res.destinationIata}** (au uwanja wowote wa ndege duniani). Niambie mji unaotoka, unakokwenda, na tarehe ya safari, au bonyeza hapa chini kufungua Flight Search:` :
          `I can help you search and compare live flights between **${res.originIata}** and **${res.destinationIata}** (or any global airport). Tell me your origin city, destination, and travel date, or tap below to open Flight Search.`),
      aiActions: actions,
    };
  }

  if (lower.includes("hotel") || lower.includes("hoteli") || lower.includes("lodge") || lower.includes("malazi")) {
    const city = userProfile.homeCity || "Dar es Salaam";
    const res = await executeSearchHotelsTool({city});
    if (res.aiAction) actions.push(res.aiAction);
    const hotelLines = (res.hotels || [])
        .map((h) => `• **${h.name}** (${h.rating}/5) — ${h.address}`)
        .join("\n");
    return {
      text: hotelLines ?
        (isSw ?
          `Hizi hapa ni hoteli bora katika mji wa **${res.location}**:\n\n${hotelLines}\n\nBonyeza hapa chini kuona bei na vyumba vilivyopo:` :
          `Here are top-rated hotels in **${res.location}**:\n\n${hotelLines}\n\nTap below to explore rates and availability:`) :
        (isSw ?
          `Niambie unahitaji hoteli katika mji gani, au bonyeza hapa chini kuangalia hoteli zilizopo:` :
          `Tell me which city you need a hotel in, or tap below to browse verified hotels.`),
      aiActions: actions,
    };
  }

  if (lower.includes("car") || lower.includes("rent") || lower.includes("gari") || lower.includes("ukodishaji") || lower.includes("kodisha")) {
    const res = await executeSearchCarRentalsAndStaysTool({type: "car"});
    if (res.aiAction) actions.push(res.aiAction);
    return {
      text: isSw ?
        `Unaweza kukodisha gari kutoka kwa wanajumuia au kuweka gari lako kwa ajili ya kukodishwa kwa siku. Kama unataka **kupost gari la kukodisha**, nijibu kwa kutaja **Aina ya Gari (Make/Model), Mwaka, Mji, na Bei kwa Siku**, nami nitakuandalia kitufe cha **Publish** hapa hapa kwenye chat.` :
        `You can rent a car from verified diaspora & local hosts or list your own vehicle for daily income. If you want to **list a car**, reply with the **Make/Model, Year, City, and Daily Price**, and I will create a one-tap **Publish** button for you right here in chat.`,
      aiActions: actions,
    };
  }

  if (lower.includes("post a job") || lower.includes("post job") || lower.includes("hire") || lower.includes("tangaza kazi") || lower.includes("weka kazi")) {
    return {
      text: isSw ?
        `Nitafurahi kukusaidia kupost tangazo la kazi.\n\nTafadhali nijibu na maelezo haya:\n1. **Kichwa cha Kazi (Job Title)** (mfano: Mhasibu, Dereva, Software Developer)\n2. **Jina la Kampuni au Mwajiri**\n3. **Mji na Nchi**\n4. **Mshahara na Aina ya Ajira** (Full-time, Part-time, Remote)\n\nUkishanitumia maelezo hayo, nitakuwekea kitufe cha **Publish Job** hapa hapa kwenye chat ili uweze kuipost kwa kubonyeza mara moja tu.` :
        `I would be glad to help you post a job.\n\nPlease reply with:\n1. **Job Title** (e.g., Accountant, Driver, Software Developer)\n2. **Company / Employer Name**\n3. **City & Country**\n4. **Salary / Compensation & Employment Type** (Full-time, Part-time, Remote)\n\nAs soon as you share those details, I will generate a **Publish Job Listing** button right here in chat.`,
      aiActions: [
        {
          id: `open_job_form_${Date.now()}`,
          type: "navigate",
          label: "Or Open Full Job Form",
          route: "/marketplace/create",
          icon: "briefcase",
        },
      ],
    };
  }

  if (lower.includes("job") || lower.includes("kazi") || lower.includes("ajira") || lower.includes("work")) {
    const res = await executeSearchJobsAndMarketplaceTool({listingType: "job"});
    return {
      text: isSw ?
        `Unatafuta kazi au unataka kuajiri? Unaweza kuangalia nafasi za kazi zilizopo hapa chini, au niambie **Kichwa cha Kazi, Kampuni, Mji, na Mshahara** ili nikupostie tangazo jipya la kazi moja kwa moja kupitia chat hii.` :
        `Looking for a job or hiring in the diaspora? You can browse active job openings or tell me the **Job Title, Company, Location, and Salary** to post a new job right from this chat.`,
      aiActions: res.aiActions || [],
    };
  }

  if (lower.includes("radio") || lower.includes("redio") || lower.includes("music")) {
    return {
      text: isSw ?
        `Unaweza kusikiliza Redio za Nyumbani na za Diaspora Mubashara saa 24 ndani ya app. Bonyeza hapa chini kuanza kusikiliza:` :
        `You can stream 24/7 Live Homeland & Diaspora Radio stations right inside the app. Tap below to start listening:`,
      aiActions: [resolveFeatureNavigationAction("radio")],
    };
  }

  if (lower.includes("ubuntu") || lower.includes("emergency") || lower.includes("msiba") || lower.includes("dharura")) {
    return {
      text: isSw ?
        `**Mfuko wa Dharura wa Ubuntu (Ubuntu Emergency Fund)** ni mfuko wa uwazi wa kusaidiana wakati wa dharura za kiafya au msiba ili mwanadiaspora yeyote asikose msaada. Bonyeza hapa chini kuona au kujiunga:` :
        `The **Ubuntu Emergency Fund** is our transparent, community-governed mutual-aid fund so no diaspora member faces a medical emergency or bereavement (msiba) alone. Tap below to view or join the fund:`,
      aiActions: [resolveFeatureNavigationAction("emergency_fund")],
    };
  }

  return {
    text: isSw ?
      `Karibu! Nipo hapa saa 24 kukuhudumia kwa Kiswahili au lugha yoyote unayopenda.\n\nUnaweza kuniomba:\n• **Kutafuta ndege** (mfano: *"Natafuta ndege kutoka Houston kwenda Dar es Salaam mwezi ujao"*)\n• **Kutafuta hoteli au kukodisha gari** (mfano: *"Natafuta hoteli Zanzibar"* au *"Post gari langu Toyota Prado 2021 kwa $60/siku Arusha"*)\n• **Kutafuta au kupost kazi** (mfano: *"Tangaza kazi ya Sales Manager Dar es Salaam mshahara $1,200/mwezi"*)\n• **Kufungua huduma yoyote** (Nearby Discovery, Live Radio, Ubuntu Emergency Fund, DDI Loans, au Real Estate).` :
      `I am here 24/7 in any language you prefer.\n\nYou can ask me to:\n• **Search flights** (e.g., *"Find flights from Houston to Dar es Salaam next month"*)\n• **Find hotels or car rentals** (e.g., *"Find hotels in Zanzibar"* or *"List my 2021 Toyota Prado for $60/day in Arusha"*)\n• **Find or post a job** (e.g., *"Post a full-time Sales Manager job in Dar es Salaam paying $1,200/mo"*)\n• **Open any feature** (Nearby Discovery, Live Radio, Ubuntu Emergency Fund, DDI Loans, or Real Estate).`,
    aiActions: buildWelcomeAiActions().slice(0, 4),
  };
}

// ── Synthesize Natural Non-Robotic Voice Audio via Gemini Neural TTS ──
function pcm16LeToWavBase64(pcmBase64, sampleRate = 24000) {
  const pcmBuffer = Buffer.from(pcmBase64, "base64");
  const numChannels = 1;
  const bitsPerSample = 16;
  const byteRate = (sampleRate * numChannels * bitsPerSample) / 8;
  const blockAlign = (numChannels * bitsPerSample) / 8;
  const dataSize = pcmBuffer.length;
  const header = Buffer.alloc(44);

  header.write("RIFF", 0);
  header.writeUInt32LE(36 + dataSize, 4);
  header.write("WAVE", 8);
  header.write("fmt ", 12);
  header.writeUInt32LE(16, 16); // Subchunk1Size (16 for PCM)
  header.writeUInt16LE(1, 20); // AudioFormat (1 = PCM)
  header.writeUInt16LE(numChannels, 22);
  header.writeUInt32LE(sampleRate, 24);
  header.writeUInt32LE(byteRate, 28);
  header.writeUInt16LE(blockAlign, 32);
  header.writeUInt16LE(bitsPerSample, 34);
  header.write("data", 36);
  header.writeUInt32LE(dataSize, 40);

  return Buffer.concat([header, pcmBuffer]).toString("base64");
}

function cleanTextForSpeech(text) {
  return String(text || "")
      .replace(/\*\*/g, "")
      .replace(/\*/g, "")
      .replace(/`/g, "")
      .replace(/#{1,6}\s*/g, "")
      .replace(/\[([^\]]+)\]\([^)]+\)/g, "$1")
      .replace(/•/g, ",")
      .replace(/\s+/g, " ")
      .trim()
      .slice(0, 650);
}

async function synthesizeGeminiNaturalVoice(textToSpeak, voiceName = "Aoede") {
  await ensureAiConfigEnv();
  const geminiKey = process.env.GEMINI_API_KEY;
  if (!geminiKey) return null;

  const cleanText = cleanTextForSpeech(textToSpeak);
  if (!cleanText) return null;

  const ttsModels = [
    "gemini-2.5-flash-preview-tts",
    "gemini-3.8-flash-lite-tts",
    "gemini-3.8-flash-tts",
  ];

  for (const ttsModel of ttsModels) {
    try {
      const url = `https://generativelanguage.googleapis.com/v1beta/models/${ttsModel}:generateContent?key=${geminiKey}`;
      const res = await axios.post(
          url,
          {
            contents: [
              {
                parts: [
                  {
                    text: cleanText,
                  },
                ],
              },
            ],
            generationConfig: {
              responseModalities: ["AUDIO"],
              speechConfig: {
                voiceConfig: {
                  prebuiltVoiceConfig: {
                    voiceName: voiceName || "Aoede",
                  },
                },
              },
            },
          },
          {timeout: 15000},
      );

      const inline = res.data?.candidates?.[0]?.content?.parts?.[0]?.inlineData;
      if (inline && inline.data) {
        const mimeType = String(inline.mimeType || "audio/wav");
        if (mimeType.includes("L16") || mimeType.includes("pcm")) {
          return {
            audioBase64: pcm16LeToWavBase64(inline.data, 24000),
            mimeType: "audio/wav",
          };
        }
        return {
          audioBase64: inline.data,
          mimeType: "audio/wav",
        };
      }
    } catch (ttsErr) {
      console.warn(`[AI Agent] Gemini TTS (${ttsModel}) failed:`, ttsErr.message);
    }
  }
  return null;
}

// ── Main Conversational Orchestrator ──
async function generateAiAgentResponse({
  userText,
  audioMediaUrl = null,
  audioBase64 = null,
  audioMimeType = "audio/mp4",
  isVoiceMode = false,
  historyMessages = [],
  userProfile = {},
  dspPoints = 0,
}) {
  await ensureAiConfigEnv();
  const geminiKey = process.env.GEMINI_API_KEY;
  const nvidiaKey = process.env.NVIDIA_API_KEY;
  const baseInstruction = buildSystemInstruction(userProfile, dspPoints);
  const systemInstruction = isVoiceMode ?
    `${baseInstruction}\n\nNATURAL VOICE CONVERSATION MODE ACTIVE:\n- You are currently in a live, natural spoken conversation with the user.\n- Keep your response warm, natural, conversational, and concise (1 to 3 sentences) so it sounds like a natural face-to-face conversation when spoken aloud.\n- Do NOT use bullet points, numbered lists, or markdown formatting.\n- Never say you cannot listen to voice; you CAN hear the user's spoken voice directly.` :
    baseInstruction;
  const collectedActions = [];

  let inlineAudioPart = null;
  if (audioBase64 && typeof audioBase64 === "string" && audioBase64.length > 10) {
    inlineAudioPart = {
      inlineData: {
        mimeType: audioMimeType || "audio/mp4",
        data: audioBase64,
      },
    };
  } else if (audioMediaUrl && typeof audioMediaUrl === "string" && audioMediaUrl.startsWith("https://")) {
    try {
      const audioRes = await axios.get(audioMediaUrl, {
        responseType: "arraybuffer",
        timeout: 12000,
      });
      const fetchedBase64 = Buffer.from(audioRes.data).toString("base64");
      if (fetchedBase64 && fetchedBase64.length < 15 * 1024 * 1024) {
        inlineAudioPart = {
          inlineData: {
            mimeType: audioMimeType || "audio/mp4",
            data: fetchedBase64,
          },
        };
      }
    } catch (audioErr) {
      console.warn("[AI Agent] Could not download voice note for multimodal Gemini:", audioErr.message);
    }
  }

  if (geminiKey) {
    const geminiModels = ["gemini-2.5-flash", "gemini-flash-latest"];
    for (const geminiModel of geminiModels) {
      try {
        const url = `https://generativelanguage.googleapis.com/v1beta/models/${geminiModel}:generateContent?key=${geminiKey}`;

        // Build multi-turn contents from recent chat history
        const contents = [];
        for (const msg of historyMessages) {
          const text = String(msg.content || "").trim();
          if (!text) continue;
          const role = msg.senderId === DIASPORA_AI_AGENT_UID ? "model" : "user";
          contents.push({
            role,
            parts: [{text: text.slice(0, 2000)}],
          });
        }

        const latestUserParts = [];
        if (inlineAudioPart) {
          latestUserParts.push(inlineAudioPart);
          latestUserParts.push({
            text: userText && userText !== "Voice message" ?
              `Listen to this voice message and also consider the user note: "${userText}". Reply in the exact language spoken in the voice message.` :
              "Listen carefully to this voice message from the user and respond helpfully in the exact language spoken by the user.",
          });
        } else {
          latestUserParts.push({text: String(userText || "Hello").slice(0, 2000)});
        }

        if (contents.length > 0 && contents[contents.length - 1].role === "user") {
          contents[contents.length - 1].parts = latestUserParts;
        } else {
          contents.push({
            role: "user",
            parts: latestUserParts,
          });
        }

        const firstPayload = {
          systemInstruction: {
            parts: [{text: systemInstruction}],
          },
          contents,
          tools: GEMINI_TOOLS_DECLARATION,
          generationConfig: {
            temperature: 0.5,
            maxOutputTokens: 1024,
          },
        };

        const firstRes = await axios.post(url, firstPayload, {timeout: 20000});
        const candidate = firstRes.data?.candidates?.[0];
        const parts = candidate?.content?.parts || [];
        const functionCalls = parts.filter((p) => p.functionCall).map((p) => p.functionCall);

        if (functionCalls.length > 0) {
          const functionResponseParts = [];
          for (const fc of functionCalls) {
            const toolResult = await runToolCall(fc.name, fc.args || {}, userProfile);
            if (toolResult?.draftAction) {
              collectedActions.push(toolResult.draftAction);
            }
            if (toolResult?.aiAction) {
              collectedActions.push(toolResult.aiAction);
            }
            if (Array.isArray(toolResult?.aiActions)) {
              collectedActions.push(...toolResult.aiActions);
            }
            functionResponseParts.push({
              functionResponse: {
                name: fc.name,
                response: {result: toolResult},
              },
            });
          }

          const secondContents = [
            ...contents,
            candidate.content,
            {
              role: "function",
              parts: functionResponseParts,
            },
          ];

          const secondRes = await axios.post(
              url,
              {
                systemInstruction: {
                  parts: [{text: systemInstruction}],
                },
                contents: secondContents,
                generationConfig: {
                  temperature: 0.5,
                  maxOutputTokens: 1024,
                },
              },
              {timeout: 20000},
          );

          const finalText = secondRes.data?.candidates?.[0]?.content?.parts
              ?.map((p) => p.text || "")
              .join("")
              .trim();

          if (finalText) {
            return {
              text: stripEmojis(finalText),
              aiActions: collectedActions,
            };
          }
        } else {
          const directText = parts.map((p) => p.text || "").join("").trim();
          if (directText) {
            return {
              text: stripEmojis(directText),
              aiActions: collectedActions,
            };
          }
        }
      } catch (gErr) {
        console.warn(`[AI Agent] Gemini (${geminiModel}) call failed, trying next engine:`, gErr.message);
        if (gErr.response?.status === 402 || gErr.response?.status === 403) {
          break;
        }
      }
    }
  }

  if (nvidiaKey) {
    const messages = [{role: "system", content: systemInstruction}];
    for (const msg of historyMessages.slice(-8)) {
      const text = String(msg.content || "").trim();
      if (!text) continue;
      messages.push({
        role: msg.senderId === DIASPORA_AI_AGENT_UID ? "assistant" : "user",
        content: text.slice(0, 1500),
      });
    }
    if (messages[messages.length - 1]?.role !== "user") {
      messages.push({role: "user", content: String(userText || "Hello")});
    }

    const nvidiaModels = [
      "nvidia/nemotron-3.5-bolt-e4b",
      "google/diffusiongemma-26b-a4b-it",
    ];
    for (const modelId of nvidiaModels) {
      try {
        const res = await axios.post(
            "https://integrate.api.nvidia.com/v1/chat/completions",
            {
              model: modelId,
              messages,
              temperature: 0.5,
              max_tokens: 700,
            },
            {
              headers: {
                "Authorization": `Bearer ${nvidiaKey}`,
                "Content-Type": "application/json",
              },
              timeout: 15000,
            },
        );
        const replyText = stripEmojis(res.data?.choices?.[0]?.message?.content || "");
        if (replyText) {
          const structuredDraft = detectStructuredDraftFromUserText(userText, userProfile);
          if (structuredDraft) {
            return {
              text: replyText,
              aiActions: [structuredDraft],
            };
          }
          const fallbackCheck = await buildIntelligentFallbackResponse(userText, userProfile);
          return {
            text: replyText,
            aiActions: fallbackCheck.aiActions || [],
          };
        }
      } catch (nErr) {
        console.warn(`[AI Agent] NVIDIA model ${modelId} failed:`, nErr.message);
      }
    }
  }

  const structuredDraft = detectStructuredDraftFromUserText(userText, userProfile);
  if (structuredDraft) {
    const isSw = isKiswahiliText(userText);
    return {
      text: isSw ?
        `Nimekuandalia rasimu ya tangazo lako hapa chini. Bonyeza kitufe cha **Publish** ili kuipost moja kwa moja kwenye Diaspora Nearby.` :
        `I have prepared your listing draft below. Tap the **Publish** button to publish it live on Diaspora Nearby.`,
      aiActions: [structuredDraft],
    };
  }

  return await buildIntelligentFallbackResponse(userText, userProfile);
}

// ── Handle Incoming Direct Message to Diaspora AI Agent ──
async function handleUserMessageToAiAgent({chatId, messageId, message, userId}) {
  if (!chatId || !userId || userId === DIASPORA_AI_AGENT_UID) return null;

  await ensureAiAgentProfile();

  const typingRef = db.collection("chats").doc(chatId).collection("typing").doc(DIASPORA_AI_AGENT_UID);
  try {
    await typingRef.set({
      isTyping: true,
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
    });

    const [userSnap, pointsSnap, historySnap] = await Promise.all([
      db.collection("users").doc(userId).get(),
      db.collection("user_points").doc(userId).get(),
      db.collection("chats")
          .doc(chatId)
          .collection("messages")
          .orderBy("timestamp", "desc")
          .limit(12)
          .get(),
    ]);

    const userProfile = userSnap.exists ? (userSnap.data() || {}) : {};
    const dspPoints = pointsSnap.exists ? (pointsSnap.data()?.totalPoints || 0) : 0;
    const historyMessages = historySnap.docs
        .map((d) => d.data())
        .reverse();

    const isAudioMessage = message.type === "audio" || message.type === "audio_file";
    const audioMediaUrl = isAudioMessage ?
      (message.documentUrl || message.mediaUrl || message.metadata?.mediaUrl || null) :
      null;
    const rawContent = String(message.content || "").trim();
    const userText = (rawContent && rawContent !== "Voice message" && rawContent !== "Audio") ?
      rawContent :
      (isAudioMessage ?
        "Please listen to my voice message and answer my spoken question directly in the language I spoke." :
        "Hello");
    const aiResult = await generateAiAgentResponse({
      userText,
      audioMediaUrl,
      historyMessages,
      userProfile,
      dspPoints,
    });

    const nowMs = Date.now();
    const replyRef = db.collection("chats").doc(chatId).collection("messages").doc();
    const aiActions = Array.isArray(aiResult.aiActions) && aiResult.aiActions.length > 0 ?
      aiResult.aiActions :
      undefined;

    const replyMessageData = {
      id: replyRef.id,
      chatId,
      senderId: DIASPORA_AI_AGENT_UID,
      senderName: DIASPORA_AI_AGENT_NAME,
      senderImage: DIASPORA_AI_AGENT_AVATAR,
      content: aiResult.text,
      type: "text",
      timestamp: nowMs,
      status: "sent",
      ...(aiActions ? {metadata: {isAiAgent: true, aiActions}} : {metadata: {isAiAgent: true}}),
    };

    await replyRef.set(replyMessageData);
    return replyRef.id;
  } catch (err) {
    console.error(`[AI Agent] Error responding in chat ${chatId}:`, err);
    return null;
  } finally {
    await typingRef.delete().catch(() => {});
  }
}

// ── Execute Confirmed In-Chat AI Draft Action (Publish Job, Car Rental, Stay, Marketplace, Real Estate, Event) ──
exports.executeAiAgentAction = functions.https.onCall(async (data, context) => {
  requireAppCheck(context);
  const uid = requireAuth(context);
  await consumeRateLimit("ai-agent-action", uid, 60, 60 * 60 * 1000);

  const chatId = String(data?.chatId || "").trim();
  const messageId = String(data?.messageId || "").trim();
  const actionId = String(data?.actionId || "").trim();
  const draftType = String(data?.draftType || "").trim();
  const payload = (data?.payload && typeof data.payload === "object") ? data.payload : {};

  if (!draftType) {
    throw new functions.https.HttpsError("invalid-argument", "Missing draftType.");
  }

  const userSnap = await db.collection("users").doc(uid).get();
  const userProfile = userSnap.exists ? (userSnap.data() || {}) : {};
  const userFullName = String(
      userProfile.fullName ||
      `${userProfile.firstName || ""} ${userProfile.lastName || ""}`.trim() ||
      "Diaspora Member",
  ).trim();
  const userAvatar = userProfile.profileImage || userProfile.photoUrl || null;
  const userCountryCode = userProfile.homeCountryCode || userProfile.hostCountryCode || "TZ";
  const communityIds = Array.isArray(userProfile.communityMemberships) && userProfile.communityMemberships.length > 0 ?
    userProfile.communityMemberships :
    ["global"];

  let createdEntityId = null;
  let createdRoute = "/marketplace";
  let entityLabel = "Listing";

  if (draftType === "post_job") {
    const docRef = db.collection("marketplace_listings").doc();
    const title = String(payload.title || "Open Role").trim();
    const companyName = String(payload.companyName || userFullName).trim();
    const city = String(payload.city || userProfile.hostCity || "Dar es Salaam").trim();
    const country = String(payload.country || userProfile.hostCountry || "Tanzania").trim();
    const salaryRange = String(payload.salaryRange || "Competitive").trim();
    const employmentType = String(payload.employmentType || "Full-time").trim();
    const description = String(payload.description || `${title} at ${companyName}`).trim();
    const category = String(payload.category || "job_other").trim();

    await docRef.set({
      id: docRef.id,
      sellerId: uid,
      sellerName: userFullName,
      sellerAvatar: userAvatar,
      sellerCountry: userCountryCode,
      title,
      description,
      price: 0,
      priceAmount: 0,
      currency: "USD",
      category,
      condition: "New",
      images: [],
      communityIds,
      location: `${city}, ${country}`,
      city,
      country,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      isSold: false,
      status: "active",
      listingType: "job",
      companyName,
      employmentType,
      salaryRange,
      applicationUrl: payload.applicationUrl || null,
      createdViaAiAgent: true,
    });
    createdEntityId = docRef.id;
    createdRoute = `/marketplace/listing/${docRef.id}`;
    entityLabel = `Job "${title}"`;
  } else if (draftType === "post_car_rental") {
    const docRef = db.collection("peer_listings").doc();
    const title = String(payload.title || `${payload.year || ""} ${payload.make || "Car"} ${payload.model || ""}`).trim();
    const city = String(payload.city || userProfile.hostCity || "Dar es Salaam").trim();
    const pricePerDay = Number(payload.pricePerDay) || 45;
    const currency = String(payload.currency || "USD").toUpperCase();

    await docRef.set({
      id: docRef.id,
      ownerId: uid,
      ownerName: userFullName,
      ownerPhotoUrl: userAvatar,
      type: "car",
      title,
      description: String(payload.description || `${title} available for rental in ${city}.`),
      city,
      pricePerDay,
      currency,
      photoUrls: [],
      isAvailable: true,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      details: {
        make: payload.make || title,
        model: payload.model || "",
        year: Number(payload.year) || new Date().getFullYear(),
        transmission: payload.transmission || "Automatic",
        fuelType: payload.fuelType || "Petrol",
        seats: Number(payload.seats) || 5,
      },
      createdViaAiAgent: true,
    });
    createdEntityId = docRef.id;
    createdRoute = "/dsp/travel/car-rental";
    entityLabel = `Car Rental "${title}"`;
  } else if (draftType === "post_stay") {
    const docRef = db.collection("peer_listings").doc();
    const subType = payload.subType === "hotel" ? "hotel" : "stay";
    const title = String(payload.title || "Diaspora Stay").trim();
    const city = String(payload.city || userProfile.hostCity || "Dar es Salaam").trim();
    const pricePerNight = Number(payload.pricePerNight) || 65;
    const currency = String(payload.currency || "USD").toUpperCase();

    await docRef.set({
      id: docRef.id,
      ownerId: uid,
      ownerName: userFullName,
      ownerPhotoUrl: userAvatar,
      type: subType,
      title,
      description: String(payload.description || `${title} in ${city}.`),
      city,
      pricePerDay: pricePerNight,
      currency,
      photoUrls: [],
      isAvailable: true,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      details: {
        propertyType: payload.propertyType || "Entire Apartment",
        beds: Number(payload.beds) || 2,
        bathrooms: 1,
        maxGuests: Number(payload.maxGuests) || 4,
        amenities: ["Wi-Fi", "Air Conditioning", "Parking"],
      },
      createdViaAiAgent: true,
    });
    createdEntityId = docRef.id;
    createdRoute = subType === "hotel" ? "/dsp/travel/hotels" : "/dsp/travel/stays";
    entityLabel = `${subType === "hotel" ? "Hotel" : "Stay"} "${title}"`;
  } else if (draftType === "post_marketplace") {
    const docRef = db.collection("marketplace_listings").doc();
    const listingType = payload.listingType === "service" ? "service" : "product";
    const title = String(payload.title || "Marketplace Listing").trim();
    const priceAmount = Number(payload.priceAmount) || 0;
    const currency = String(payload.currency || "USD").toUpperCase();
    const city = String(payload.city || userProfile.hostCity || "Dar es Salaam").trim();
    const country = String(payload.country || userProfile.hostCountry || "Tanzania").trim();

    await docRef.set({
      id: docRef.id,
      sellerId: uid,
      sellerName: userFullName,
      sellerAvatar: userAvatar,
      sellerCountry: userCountryCode,
      title,
      description: String(payload.description || title),
      price: priceAmount,
      priceAmount,
      currency,
      category: payload.category || (listingType === "service" ? "service_other" : "other"),
      condition: "Good",
      images: [],
      communityIds,
      location: `${city}, ${country}`,
      city,
      country,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      isSold: false,
      status: "active",
      listingType,
      createdViaAiAgent: true,
    });
    createdEntityId = docRef.id;
    createdRoute = `/marketplace/listing/${docRef.id}`;
    entityLabel = `Listing "${title}"`;
  } else if (draftType === "post_real_estate") {
    const docRef = db.collection("real_estate_listings").doc();
    const category = ["plot", "farm", "house"].includes(payload.category) ? payload.category : "house";
    const title = String(payload.title || "Property Listing").trim();
    const price = Number(payload.price) || 10000;
    const currency = String(payload.currency || "USD").toUpperCase();
    const sizeSqm = Number(payload.sizeSqm) || 500;
    const city = String(payload.city || "Dar es Salaam").trim();
    const country = String(payload.country || "Tanzania").trim();

    await docRef.set({
      id: docRef.id,
      ownerId: uid,
      ownerName: userFullName,
      ownerPhotoUrl: userAvatar,
      category,
      title,
      description: String(payload.description || `${title} in ${city}, ${country}`),
      country,
      city,
      price,
      currency,
      sizeSqm,
      sizeUnit: "sqm",
      listingType: payload.listingType === "rent" ? "rent" : "sale",
      photoUrls: [],
      isVerified: false,
      hasTitleDeed: true,
      amenities: [],
      specs: {},
      status: "active",
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      createdViaAiAgent: true,
    });
    createdEntityId = docRef.id;
    createdRoute = `/dsp/real-estate/${category}`;
    entityLabel = `Property "${title}"`;
  } else if (draftType === "post_event") {
    const docRef = db.collection("events").doc();
    const title = String(payload.title || "Community Event").trim();
    const location = String(payload.location || "Dar es Salaam").trim();
    const startDateStr = `${payload.startDate || resolveDefaultFutureDate(7)}T${payload.startTime || "18:00"}:00Z`;
    const parsedStart = new Date(startDateStr);
    const startTs = isNaN(parsedStart.getTime()) ?
      new Date(Date.now() + 7 * 86400000) :
      parsedStart;
    const endTs = new Date(startTs.getTime() + 3 * 3600000);

    await docRef.set({
      id: docRef.id,
      title,
      description: String(payload.description || title),
      startDate: admin.firestore.Timestamp.fromDate(startTs),
      endDate: admin.firestore.Timestamp.fromDate(endTs),
      location,
      isVirtual: false,
      organizerId: uid,
      organizerName: userFullName,
      organizerAvatar: userAvatar,
      communityId: communityIds[0] || "global",
      attendees: [uid],
      attendeeCount: 1,
      category: payload.category || "Networking",
      status: "published",
      type: "EventType.community",
      visibility: "EventVisibility.public",
      isFree: true,
      currency: "USD",
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      createdViaAiAgent: true,
    });
    createdEntityId = docRef.id;
    createdRoute = `/events/${docRef.id}`;
    entityLabel = `Event "${title}"`;
  } else {
    throw new functions.https.HttpsError("invalid-argument", `Unsupported draftType: ${draftType}`);
  }

  // Update the chat message metadata so the button immediately shows "Published ✓"
  if (validId(chatId) && validId(messageId)) {
    const msgRef = db.collection("chats").doc(chatId).collection("messages").doc(messageId);
    const msgSnap = await msgRef.get();
    if (msgSnap.exists) {
      const msgData = msgSnap.data() || {};
      const metadata = Object.assign({}, msgData.metadata || {});
      if (Array.isArray(metadata.aiActions)) {
        metadata.aiActions = metadata.aiActions.map((act) => {
          if (act.id === actionId || act.draftType === draftType) {
            return Object.assign({}, act, {
              status: "completed",
              createdEntityId,
              createdRoute,
            });
          }
          return act;
        });
      }
      await msgRef.set({metadata}, {merge: true});
    }

    // Also post a follow-up confirmation message from Diaspora AI Agent with a View button
    const confirmRef = db.collection("chats").doc(chatId).collection("messages").doc();
    const nowMs = Date.now();
    await confirmRef.set({
      id: confirmRef.id,
      chatId,
      senderId: DIASPORA_AI_AGENT_UID,
      senderName: DIASPORA_AI_AGENT_NAME,
      senderImage: DIASPORA_AI_AGENT_AVATAR,
      content: `Your ${entityLabel} has been published live on Diaspora Nearby. Tap below to view or manage it anytime.`,
      type: "text",
      timestamp: nowMs,
      status: "sent",
      metadata: {
        isAiAgent: true,
        aiActions: [
          {
            id: `view_created_${createdEntityId}`,
            type: "navigate",
            label: `View ${entityLabel}`,
            route: createdRoute,
            icon: "check",
          },
        ],
      },
    });
  }

  return {
    success: true,
    createdEntityId,
    createdRoute,
  };
});

// ── Interactive Real-Time Natural Voice Turn with Diaspora AI Agent ──
exports.converseAiAgentVoice = functions.https.onCall(async (data, context) => {
  requireAppCheck(context);
  const uid = requireAuth(context);
  await consumeRateLimit("ai-agent-voice", uid, 120, 60 * 60 * 1000);

  const chatId = String(data?.chatId || `ai_agent_${uid}`).trim();
  const audioBase64 = String(data?.audioBase64 || "").trim();
  const mimeType = String(data?.mimeType || "audio/mp4").trim();
  const voiceName = String(data?.voiceName || "Aoede").trim();
  const saveToChat = data?.saveToChat === true;

  if (!audioBase64) {
    throw new functions.https.HttpsError("invalid-argument", "Missing audioBase64.");
  }

  await ensureAiAgentProfile();

  const [userSnap, pointsSnap, historySnap] = await Promise.all([
    db.collection("users").doc(uid).get(),
    db.collection("user_points").doc(uid).get(),
    validId(chatId) ?
      db.collection("chats")
          .doc(chatId)
          .collection("messages")
          .orderBy("timestamp", "desc")
          .limit(10)
          .get() :
      Promise.resolve({docs: []}),
  ]);

  const userProfile = userSnap.exists ? (userSnap.data() || {}) : {};
  const dspPoints = pointsSnap.exists ? (pointsSnap.data()?.totalPoints || 0) : 0;
  const historyMessages = (historySnap.docs || []).map((d) => d.data()).reverse();

  const aiResult = await generateAiAgentResponse({
    userText: "Listen carefully to what I just said in this voice turn and answer me naturally in the exact language I spoke.",
    audioBase64,
    audioMimeType: mimeType,
    isVoiceMode: true,
    historyMessages,
    userProfile,
    dspPoints,
  });

  const replyText = String(aiResult.text || "").trim();
  const ttsResult = await synthesizeGeminiNaturalVoice(replyText, voiceName);

  // If the AI prepared any action buttons or drafts (e.g. flight results or job post button),
  // or if saveToChat is requested, post the assistant's reply + buttons into the chat so the user can tap them!
  const hasActions = Array.isArray(aiResult.aiActions) && aiResult.aiActions.length > 0;
  if ((hasActions || saveToChat) && validId(chatId)) {
    const nowMs = Date.now();
    const replyRef = db.collection("chats").doc(chatId).collection("messages").doc();
    const replyMessageData = {
      id: replyRef.id,
      chatId,
      senderId: DIASPORA_AI_AGENT_UID,
      senderName: DIASPORA_AI_AGENT_NAME,
      senderImage: DIASPORA_AI_AGENT_AVATAR,
      content: replyText,
      type: "text",
      timestamp: nowMs,
      status: "sent",
      metadata: {
        isAiAgent: true,
        fromVoiceSession: true,
        ...(hasActions ? {aiActions: aiResult.aiActions} : {}),
      },
    };
    await replyRef.set(replyMessageData).catch((e) => {
      console.warn("[AI Agent Voice] Could not save voice reply to chat:", e.message);
    });
  }

  return {
    replyText,
    audioBase64: ttsResult?.audioBase64 || null,
    audioMimeType: ttsResult?.mimeType || "audio/wav",
    aiActions: aiResult.aiActions || [],
  };
});

exports.DIASPORA_AI_AGENT_UID = DIASPORA_AI_AGENT_UID;
exports.DIASPORA_AI_AGENT_NAME = DIASPORA_AI_AGENT_NAME;
exports.DIASPORA_AI_AGENT_AVATAR = DIASPORA_AI_AGENT_AVATAR;
exports.ensureAiAgentProfile = ensureAiAgentProfile;
exports.buildAiAgentWelcomeText = buildAiAgentWelcomeText;
exports.buildWelcomeAiActions = buildWelcomeAiActions;
exports.handleUserMessageToAiAgent = handleUserMessageToAiAgent;
