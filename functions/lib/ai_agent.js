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
const crypto = require("crypto");
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
    const existing = snap.exists ? (snap.data() || {}) : {};
    const defaultLoc = {
      formatted_address: "Global Diaspora",
      place_id: "global_diaspora",
      city: "Global",
      country: "Diaspora",
      country_code: "UN",
      geometry: {
        location: {
          lat: 0,
          lng: 0,
        },
      },
    };
    const agentData = {
      uid: DIASPORA_AI_AGENT_UID,
      firstName: "Diaspora",
      lastName: "AI Agent",
      fullName: DIASPORA_AI_AGENT_NAME,
      phone: existing.phone || "+10000000000",
      profilePhoto: DIASPORA_AI_AGENT_AVATAR,
      profileImage: DIASPORA_AI_AGENT_AVATAR,
      photoUrl: DIASPORA_AI_AGENT_AVATAR,
      homeLocation: existing.homeLocation && typeof existing.homeLocation === "object" ?
        existing.homeLocation :
        defaultLoc,
      hostLocation: existing.hostLocation && typeof existing.hostLocation === "object" ?
        existing.hostLocation :
        defaultLoc,
      occupation: "AI Concierge • Multilingual 24/7",
      bio: "Your 24/7 multilingual Diaspora Nearby AI Agent. Ask me anything, search flights, hotels, jobs, car rentals, or post listings right from chat in any language!",
      isAiAgent: true,
      isDiscoverable: false,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };
    const needsUpdate =
      !snap.exists ||
      existing.fullName !== DIASPORA_AI_AGENT_NAME ||
      existing.profilePhoto !== DIASPORA_AI_AGENT_AVATAR ||
      existing.profileImage !== DIASPORA_AI_AGENT_AVATAR ||
      typeof existing.phone !== "string" ||
      !existing.homeLocation ||
      !existing.hostLocation;
    if (needsUpdate) {
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
    `I am **Diaspora AI Agent**, your 24/7 personal concierge on Diaspora Nearby${corridorNote}. Speak or write to me in **any language** — I have full access to platform information and can complete tasks directly for you right here in chat.\n\n` +
    `**Your Proof of Humanity (PoH) & $DIASPORA Rewards**:\n` +
    `• **Proof of Humanity (PoH)**: Earn up to **70,000 $DIASPORA** across 7 PoH pillars, where your earned DSP converts immediately at **100% 1:1 efficiency** into on-chain **$DIASPORA** tokens in your smart wallet.\n` +
    `• **Fill Your 12 Profile Fields (+10,000 DSP -> 10,000 $DIASPORA Immediately)**: Completing your **12 profile fields** earns **1,000 DSP per field** — your first **10,000 DSP is immediately converted 1:1 into 10,000 $DIASPORA tokens** right away (plus +2,000 DSP bonus on fields 11 and 12). **Want me to help fill out all 12 fields for you right here in chat?** Just reply or tap the button below and we will complete them together in minutes!\n` +
    `• **QR EXCHANGE to Unlock Your Tokens (Crucial)**: Complete **10 in-person QR Exchanges** with fellow diaspora members to earn another **+10,000 $DIASPORA** (+1,000 per scan) **AND unlock all your minted $DIASPORA tokens** in your wallet for peer transfers and Token Distribution Events.\n\n` +
    `**Everything Else I Can Do For You**:\n` +
    `• Search live **Flights, Hotels, Stays & Car Rentals**, find or publish **Jobs, Marketplace & Real Estate** listings, connect with **Nearby Compatriots**, stream **Live Homeland Radio**, or access the **Ubuntu Emergency Fund & DDI Loans**.\n\n` +
    `Would you like me to help fill out your 12 profile fields now to claim your **10,000 $DIASPORA**, or what task can I complete for you today?`;
}

function buildWelcomeAiActions() {
  return [
    {
      id: "welcome_fill_12_fields",
      type: "prompt",
      label: "Fill My 12 Profile Fields (+10,000 $DIASPORA)",
      prompt: "Help me fill out my 12 profile fields right here in chat so I can earn my 10,000 DSP immediately converted to $DIASPORA tokens.",
      icon: "sparkles",
    },
    {
      id: "welcome_qr_exchange",
      type: "navigate",
      label: "Open QR Exchange (Unlock $DIASPORA)",
      route: "/profile?showQr=true",
      icon: "check",
    },
    {
      id: "welcome_poh_hub",
      type: "navigate",
      label: "PoH & $DIASPORA Hub",
      route: "/dsp/points",
      icon: "wallet",
    },
    {
      id: "welcome_nearby",
      type: "navigate",
      label: "Explore Nearby",
      route: "/nearby",
      icon: "compass",
    },
    {
      id: "welcome_flights",
      type: "navigate",
      label: "Flights & Hotels",
      route: "/dsp/travel/flights",
      icon: "flight",
    },
    {
      id: "welcome_jobs",
      type: "navigate",
      label: "Jobs & Marketplace",
      route: "/marketplace",
      icon: "briefcase",
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

// ── Country & Location Normalization Helpers ──
const COUNTRY_NAME_TO_ISO = {
  "tanzania": "TZ",
  "united republic of tanzania": "TZ",
  "kenya": "KE",
  "uganda": "UG",
  "rwanda": "RW",
  "burundi": "BI",
  "drc": "CD",
  "congo": "CD",
  "democratic republic of the congo": "CD",
  "nigeria": "NG",
  "ghana": "GH",
  "ethiopia": "ET",
  "eritrea": "ER",
  "somalia": "SO",
  "south africa": "ZA",
  "zimbabwe": "ZW",
  "zambia": "ZM",
  "malawi": "MW",
  "mozambique": "MZ",
  "angola": "AO",
  "botswana": "BW",
  "namibia": "NA",
  "senegal": "SN",
  "ivory coast": "CI",
  "cote d'ivoire": "CI",
  "cameroon": "CM",
  "egypt": "EG",
  "morocco": "MA",
  "algeria": "DZ",
  "tunisia": "TN",
  "sudan": "SD",
  "united states": "US",
  "usa": "US",
  "u.s.a.": "US",
  "united states of america": "US",
  "canada": "CA",
  "united kingdom": "GB",
  "uk": "GB",
  "england": "GB",
  "germany": "DE",
  "france": "FR",
  "italy": "IT",
  "spain": "ES",
  "netherlands": "NL",
  "belgium": "BE",
  "switzerland": "CH",
  "sweden": "SE",
  "norway": "NO",
  "denmark": "DK",
  "finland": "FI",
  "united arab emirates": "AE",
  "uae": "AE",
  "dubai": "AE",
  "saudi arabia": "SA",
  "qatar": "QA",
  "turkey": "TR",
  "india": "IN",
  "china": "CN",
  "japan": "JP",
  "south korea": "KR",
  "australia": "AU",
  "brazil": "BR",
  "mexico": "MX",
};

const CITY_TO_COUNTRY = {
  "dar es salaam": {country: "Tanzania", countryCode: "TZ"},
  "arusha": {country: "Tanzania", countryCode: "TZ"},
  "zanzibar": {country: "Tanzania", countryCode: "TZ"},
  "dodoma": {country: "Tanzania", countryCode: "TZ"},
  "mwanza": {country: "Tanzania", countryCode: "TZ"},
  "mbeya": {country: "Tanzania", countryCode: "TZ"},
  "moshi": {country: "Tanzania", countryCode: "TZ"},
  "morogoro": {country: "Tanzania", countryCode: "TZ"},
  "tanga": {country: "Tanzania", countryCode: "TZ"},
  "nairobi": {country: "Kenya", countryCode: "KE"},
  "mombasa": {country: "Kenya", countryCode: "KE"},
  "kisumu": {country: "Kenya", countryCode: "KE"},
  "kampala": {country: "Uganda", countryCode: "UG"},
  "entebbe": {country: "Uganda", countryCode: "UG"},
  "kigali": {country: "Rwanda", countryCode: "RW"},
  "bujumbura": {country: "Burundi", countryCode: "BI"},
  "addis ababa": {country: "Ethiopia", countryCode: "ET"},
  "lagos": {country: "Nigeria", countryCode: "NG"},
  "abuja": {country: "Nigeria", countryCode: "NG"},
  "accra": {country: "Ghana", countryCode: "GH"},
  "kumasi": {country: "Ghana", countryCode: "GH"},
  "johannesburg": {country: "South Africa", countryCode: "ZA"},
  "cape town": {country: "South Africa", countryCode: "ZA"},
  "durban": {country: "South Africa", countryCode: "ZA"},
  "pretoria": {country: "South Africa", countryCode: "ZA"},
  "lusaka": {country: "Zambia", countryCode: "ZM"},
  "harare": {country: "Zimbabwe", countryCode: "ZW"},
  "lilongwe": {country: "Malawi", countryCode: "MW"},
  "dubai": {country: "United Arab Emirates", countryCode: "AE"},
  "abu dhabi": {country: "United Arab Emirates", countryCode: "AE"},
  "doha": {country: "Qatar", countryCode: "QA"},
  "london": {country: "United Kingdom", countryCode: "GB"},
  "manchester": {country: "United Kingdom", countryCode: "GB"},
  "birmingham": {country: "United Kingdom", countryCode: "GB"},
  "paris": {country: "France", countryCode: "FR"},
  "berlin": {country: "Germany", countryCode: "DE"},
  "frankfurt": {country: "Germany", countryCode: "DE"},
  "amsterdam": {country: "Netherlands", countryCode: "NL"},
  "toronto": {country: "Canada", countryCode: "CA"},
  "vancouver": {country: "Canada", countryCode: "CA"},
  "montreal": {country: "Canada", countryCode: "CA"},
  "new york": {country: "United States", countryCode: "US"},
  "washington": {country: "United States", countryCode: "US"},
  "houston": {country: "United States", countryCode: "US"},
  "dallas": {country: "United States", countryCode: "US"},
  "atlanta": {country: "United States", countryCode: "US"},
  "chicago": {country: "United States", countryCode: "US"},
  "los angeles": {country: "United States", countryCode: "US"},
  "san francisco": {country: "United States", countryCode: "US"},
  "seattle": {country: "United States", countryCode: "US"},
  "boston": {country: "United States", countryCode: "US"},
  "miami": {country: "United States", countryCode: "US"},
  "minneapolis": {country: "United States", countryCode: "US"},
  "phoenix": {country: "United States", countryCode: "US"},
  "des moines": {country: "United States", countryCode: "US"},
};

function resolveLocationDetails({city = "", country = "", countryCode = "", userProfile = {}} = {}) {
  const ctx = extractUserProfileContext(userProfile);
  let resolvedCity = String(city || "").trim();
  let resolvedCountry = String(country || "").trim();
  let resolvedCode = String(countryCode || "").trim().toUpperCase();

  if (resolvedCity.includes(",")) {
    const parts = resolvedCity.split(",").map((p) => p.trim()).filter(Boolean);
    if (parts.length >= 2) {
      resolvedCity = parts[0];
      if (!resolvedCountry) resolvedCountry = parts[parts.length - 1];
    }
  }

  if (!resolvedCity) {
    resolvedCity = ctx.hostCity || ctx.currentCity || ctx.homeCity || "Dar es Salaam";
  }

  const cityLookup = CITY_TO_COUNTRY[resolvedCity.toLowerCase()];
  if (cityLookup) {
    if (!resolvedCountry) resolvedCountry = cityLookup.country;
    if (!resolvedCode) resolvedCode = cityLookup.countryCode;
  }

  if (!resolvedCountry) {
    resolvedCountry = ctx.hostCountry || ctx.homeCountry || "Tanzania";
  }

  if (!resolvedCode || resolvedCode.length !== 2) {
    const mapped = COUNTRY_NAME_TO_ISO[resolvedCountry.toLowerCase()];
    if (mapped) {
      resolvedCode = mapped;
    } else if (resolvedCountry.toLowerCase() === (ctx.homeCountry || "").toLowerCase() && ctx.homeCountryCode) {
      resolvedCode = ctx.homeCountryCode.toUpperCase();
    } else if (resolvedCountry.toLowerCase() === (ctx.hostCountry || "").toLowerCase() && ctx.hostCountryCode) {
      resolvedCode = ctx.hostCountryCode.toUpperCase();
    } else {
      resolvedCode = (ctx.hostCountryCode || ctx.homeCountryCode || "TZ").toUpperCase();
    }
  }

  const formattedAddress = [resolvedCity, resolvedCountry].filter(Boolean).join(", ");
  return {
    city: resolvedCity,
    country: resolvedCountry,
    countryCode: resolvedCode,
    formattedAddress,
    locationMap: {
      city: resolvedCity,
      country: resolvedCountry,
      countryCode: resolvedCode,
      formattedAddress,
      formatted_address: formattedAddress,
    },
  };
}

function normalizeEmploymentType(raw = "") {
  const s = String(raw || "").trim().toLowerCase();
  if (s.includes("part")) return "part_time";
  if (s.includes("contract") || s.includes("freelance")) return "contract";
  if (s.includes("intern")) return "internship";
  if (s.includes("temp")) return "temporary";
  return "full_time";
}

function normalizeWorkMode(raw = "", employmentTypeRaw = "") {
  const s = `${raw || ""} ${employmentTypeRaw || ""}`.toLowerCase();
  if (s.includes("remote")) return "remote";
  if (s.includes("hybrid")) return "hybrid";
  return "onsite";
}

function normalizeJobCategory(raw = "", title = "") {
  const valid = [
    "job_technology",
    "job_healthcare",
    "job_finance",
    "job_education",
    "job_construction",
    "job_hospitality",
    "job_sales",
    "job_transport_logistics",
    "job_admin_hr",
    "job_creative_media",
    "job_domestic",
    "job_other",
  ];
  const s = String(raw || "").trim().toLowerCase();
  if (valid.includes(s)) return s;
  if (s === "job_tech") return "job_technology";
  if (s === "job_logistics") return "job_transport_logistics";
  if (s === "job_legal") return "job_admin_hr";
  if (s === "job_creative") return "job_creative_media";
  const combined = `${s} ${String(title || "").toLowerCase()}`;
  if (/\b(software|developer|engineer|blockchain|ai|data|it|cyber|web|mobile|devops|tech|cloud)\b/.test(combined)) return "job_technology";
  if (/\b(nurse|doctor|medical|health|clinic|pharmacist|caregiver)\b/.test(combined)) return "job_healthcare";
  if (/\b(accountant|finance|bank|audit|tax|bookkeeper|analyst)\b/.test(combined)) return "job_finance";
  if (/\b(teacher|tutor|professor|school|education|trainer)\b/.test(combined)) return "job_education";
  if (/\b(construction|plumber|electrician|architect|civil|carpenter|builder)\b/.test(combined)) return "job_construction";
  if (/\b(hotel|chef|cook|waiter|restaurant|hospitality|tourism|guide)\b/.test(combined)) return "job_hospitality";
  if (/\b(sales|marketing|business development|account manager|retail)\b/.test(combined)) return "job_sales";
  if (/\b(driver|logistics|supply chain|delivery|transport|warehouse|fleet)\b/.test(combined)) return "job_transport_logistics";
  if (/\b(lawyer|legal|attorney|paralegal|compliance|admin|hr|secretary|assistant)\b/.test(combined)) return "job_admin_hr";
  if (/\b(designer|video|media|writer|content|creative|photographer)\b/.test(combined)) return "job_creative_media";
  if (/\b(nanny|housekeeper|cleaner|guard|security|gardener|domestic)\b/.test(combined)) return "job_domestic";
  return "job_other";
}

function normalizeMarketplaceCategory(raw = "", listingType = "product", title = "") {
  const s = String(raw || "").trim().toLowerCase();
  const combined = `${s} ${String(title || "").toLowerCase()}`;
  if (listingType === "service") {
    const validServices = [
      "professional",
      "home_services",
      "wellness",
      "education",
      "events_catering",
      "transport",
      "financial",
      "tech_digital",
      "other_services",
    ];
    if (validServices.includes(s)) return s;
    if (/\b(ship|cargo|freight|courier|clearing|transport|moving)\b/.test(combined)) return "transport";
    if (/\b(law|legal|immigration|visa|notary|consult)\b/.test(combined)) return "professional";
    if (/\b(tax|accounting|finance|loan|insurance|remittance)\b/.test(combined)) return "financial";
    if (/\b(web|software|app|it|tech|design|developer|digital)\b/.test(combined)) return "tech_digital";
    if (/\b(cater|food|chef|baking|event|photo|videograph|camera|dj)\b/.test(combined)) return "events_catering";
    if (/\b(hair|braid|salon|barber|beauty|makeup|wellness|massage)\b/.test(combined)) return "wellness";
    if (/\b(tutor|teach|language|lesson|class|coach)\b/.test(combined)) return "education";
    if (/\b(plumb|repair|electric|clean|handyman|home)\b/.test(combined)) return "home_services";
    return "other_services";
  }
  const validProducts = [
    "electronics",
    "vehicles",
    "fashion",
    "home_garden",
    "food_grocery",
    "books_media",
    "baby_kids",
    "sports_outdoors",
    "health",
    "other_products",
  ];
  if (validProducts.includes(s)) return s;
  if (/\b(phone|iphone|samsung|laptop|macbook|tv|camera|computer|electronics)\b/.test(combined)) return "electronics";
  if (/\b(car|truck|suv|toyota|motorcycle|vehicle|tire)\b/.test(combined)) return "vehicles";
  if (/\b(dress|shirt|shoes|kitenge|ankara|clothes|fashion|bag|watch)\b/.test(combined)) return "fashion";
  if (/\b(sofa|bed|table|chair|furniture|fridge|home)\b/.test(combined)) return "home_garden";
  if (/\b(spice|coffee|tea|flour|food|grocery|honey)\b/.test(combined)) return "food_grocery";
  if (/\b(book|novel|textbook|media|game)\b/.test(combined)) return "books_media";
  if (/\b(baby|stroller|toy|kids)\b/.test(combined)) return "baby_kids";
  if (/\b(gym|fitness|sport|bike|bicycle|football)\b/.test(combined)) return "sports_outdoors";
  if (/\b(skin|lotion|vitamin|health|beauty|cosmetic)\b/.test(combined)) return "health";
  return "other_products";
}

function computeListingChatId(listingId) {
  const hex = crypto.createHash("sha256").update(String(listingId || "")).digest("hex");
  return `listing_${hex.slice(0, 40)}`;
}

function computeLegacyListingChatId(listingId) {
  let hash = 0;
  const str = String(listingId || "");
  for (let i = 0; i < str.length; i++) {
    hash = ((hash << 5) - hash) + str.charCodeAt(i);
    hash |= 0;
  }
  return `listing_${Math.abs(hash)}`;
}

// ── Self-Healing for Any Existing AI-Created Docs in Firestore ──
let _lastLegacyHealMs = 0;
async function healLegacyAiAgentDocs(force = false) {
  const now = Date.now();
  if (!force && now - _lastLegacyHealMs < 60 * 1000) return;
  _lastLegacyHealMs = now;

  try {
    // 1. Heal marketplace_listings (jobs, products, services)
    const mktSnap = await db.collection("marketplace_listings")
        .where("createdViaAiAgent", "==", true)
        .limit(50)
        .get();

    for (const doc of mktSnap.docs) {
      const data = doc.data() || {};
      const updates = {};
      const listingType = String(data.listingType || "product").toLowerCase();
      const locInfo = resolveLocationDetails({
        city: data.city || (typeof data.location === "object" ? data.location?.city : ""),
        country: data.country || (typeof data.location === "object" ? data.location?.country : ""),
        countryCode: data.sellerCountryCode || data.sellerCountry || (typeof data.location === "object" ? data.location?.countryCode : ""),
      });

      if (!data.location || typeof data.location === "string" || !data.location.city || !data.location.countryCode) {
        updates.location = locInfo.locationMap;
      }
      if (!data.sellerPhoto && data.sellerAvatar) {
        updates.sellerPhoto = data.sellerAvatar;
      }
      if (!data.sellerCountryCode) {
        updates.sellerCountryCode = locInfo.countryCode;
      }
      if (!data.sellerCity) {
        updates.sellerCity = locInfo.city;
      }
      if (!data.titleLower && data.title) {
        updates.titleLower = String(data.title).toLowerCase();
      }
      if (!data.scope) {
        updates.scope = "global";
      }
      if (!data.contactMethod) {
        updates.contactMethod = "in_app";
      }
      if (!Array.isArray(data.communityIds) || data.communityIds.length === 0) {
        updates.communityIds = ["global_community", "global"];
      }
      if (listingType === "job") {
        if (!data.jobDetails || typeof data.jobDetails !== "object") {
          updates.jobDetails = {
            companyName: data.companyName || data.sellerName || "Diaspora Employer",
            employmentType: normalizeEmploymentType(data.employmentType || "Full-time"),
            salaryRange: data.salaryRange || "Competitive / Negotiable",
            experienceLevel: data.experienceLevel || "mid",
            workMode: normalizeWorkMode(data.workMode, data.employmentType),
            applicationDeadline: data.applicationDeadline || null,
            applicationUrl: data.applicationUrl || null,
          };
        }
        const normCat = normalizeJobCategory(data.category, data.title);
        if (data.category !== normCat) {
          updates.category = normCat;
        }
      } else if (listingType === "service") {
        if (!data.serviceDetails || typeof data.serviceDetails !== "object") {
          updates.serviceDetails = {
            pricingModel: data.pricingModel || "fixed",
            serviceArea: data.serviceArea || locInfo.city,
          };
        }
        const normCat = normalizeMarketplaceCategory(data.category, "service", data.title);
        if (data.category !== normCat) {
          updates.category = normCat;
        }
      } else {
        if (data.condition === "New" || data.condition === "Good") {
          updates.condition = data.condition === "New" ? "new" : "used_good";
        }
        const normCat = normalizeMarketplaceCategory(data.category, "product", data.title);
        if (data.category !== normCat) {
          updates.category = normCat;
        }
      }

      if (Object.keys(updates).length > 0) {
        updates.updatedAt = admin.firestore.FieldValue.serverTimestamp();
        await doc.ref.set(updates, {merge: true});
      }

      // Also heal the associated listing discussion chat(s) for this marketplace listing
      const sellerRole = listingType === "job" ?
        "Employer" :
        (listingType === "service" ? "Provider" : "Seller");
      const createdSystemText = listingType === "job" ?
        "Job posted" :
        (listingType === "service" ? "Service posted" : "Shop created");
      const canonicalChatId = computeListingChatId(doc.id);
      const legacyChatId = computeLegacyListingChatId(doc.id);
      const chatIdsToCheck = Array.from(new Set([canonicalChatId, legacyChatId]));

      for (const cid of chatIdsToCheck) {
        const chatSnap = await db.collection("chats").doc(cid).get();
        if (!chatSnap.exists) continue;
        const cData = chatSnap.data() || {};
        const chatUpdates = {};
        if (cData.type !== "group") {
          chatUpdates.type = "group";
        }
        if (cData.isPublic !== true) {
          chatUpdates.isPublic = true;
        }
        if (!cData.createdBy && data.sellerId) {
          chatUpdates.createdBy = data.sellerId;
        }
        const existingMeta = (cData.metadata && typeof cData.metadata === "object") ? cData.metadata : {};
        if (existingMeta.isListingChat !== true ||
            existingMeta.listingType !== listingType ||
            existingMeta.sellerRole !== sellerRole ||
            existingMeta.listingId !== doc.id) {
          chatUpdates.metadata = {
            ...existingMeta,
            isListingChat: true,
            listingId: doc.id,
            listingType,
            sellerRole,
          };
        }
        const existingLastMsg = (cData.lastMessage && typeof cData.lastMessage === "object") ? cData.lastMessage : null;
        if (!existingLastMsg ||
            (existingLastMsg.senderId === "system" &&
             existingLastMsg.content === "Shop created" &&
             createdSystemText !== "Shop created")) {
          chatUpdates.lastMessage = {
            id: existingLastMsg?.id || "",
            senderId: "system",
            senderName: "System",
            content: createdSystemText,
            type: "system",
            timestamp: existingLastMsg?.timestamp || Date.now(),
            status: "sent",
          };
        }
        if (Object.keys(chatUpdates).length > 0) {
          await chatSnap.ref.set(chatUpdates, {merge: true});
        }
      }
    }

    // 2. Heal peer_listings (cars, stays, hotels)
    const peerSnap = await db.collection("peer_listings")
        .where("createdViaAiAgent", "==", true)
        .limit(50)
        .get();

    for (const doc of peerSnap.docs) {
      const data = doc.data() || {};
      const updates = {};
      const details = (data.details && typeof data.details === "object") ? data.details : {};
      const locInfo = resolveLocationDetails({
        city: data.city || data.locality || "",
        country: data.country || "",
        countryCode: data.countryCode || "",
      });

      if (data.pricePerUnit == null) {
        updates.pricePerUnit = Number(data.pricePerDay || data.pricePerNight || 45);
      }
      if (!data.priceUnit) {
        updates.priceUnit = data.type === "car" ? "day" : "night";
      }
      if (!data.status) {
        updates.status = data.isAvailable === false ? "paused" : "active";
      }
      if (!data.ownerPhoto && data.ownerPhotoUrl) {
        updates.ownerPhoto = data.ownerPhotoUrl;
      }
      if (!Array.isArray(data.photos)) {
        updates.photos = Array.isArray(data.photoUrls) ? data.photoUrls : [];
      }
      if (!data.localityLower) {
        updates.localityLower = locInfo.city.toLowerCase();
      }
      if (!data.country) updates.country = locInfo.country;
      if (!data.countryCode) updates.countryCode = locInfo.countryCode;
      if (data.type === "car") {
        if (!data.make && details.make) updates.make = details.make;
        if (!data.model && details.model) updates.model = details.model;
        if (!data.year && details.year) updates.year = Number(details.year);
        if (!data.transmission && details.transmission) updates.transmission = String(details.transmission).toLowerCase();
        if (!data.fuelType && details.fuelType) updates.fuelType = String(details.fuelType).toLowerCase();
        if (!data.seats && details.seats) updates.seats = Number(details.seats);
      } else {
        if (!data.propertyType && details.propertyType) updates.propertyType = details.propertyType;
        if (!data.beds && details.beds) updates.beds = Number(details.beds);
        if (!data.baths && (details.baths || details.bathrooms)) updates.baths = Number(details.baths || details.bathrooms || 1);
        if (!data.maxGuests && details.maxGuests) updates.maxGuests = Number(details.maxGuests);
        if (!Array.isArray(data.amenities) && Array.isArray(details.amenities)) updates.amenities = details.amenities;
      }

      if (Object.keys(updates).length > 0) {
        await doc.ref.set(updates, {merge: true});
      }
    }

    // 3. Heal real_estate_listings
    const reSnap = await db.collection("real_estate_listings")
        .where("createdViaAiAgent", "==", true)
        .limit(50)
        .get();

    for (const doc of reSnap.docs) {
      const data = doc.data() || {};
      const updates = {};
      const locInfo = resolveLocationDetails({
        city: data.city || data.locality || "",
        country: data.country || "",
        countryCode: data.countryCode || "",
      });

      if (data.size == null && data.sizeSqm != null) {
        updates.size = Number(data.sizeSqm);
      }
      if (data.sizeUnit === "sqm" || !data.sizeUnit) {
        updates.sizeUnit = "m²";
      }
      if (data.hasTitle == null) {
        updates.hasTitle = data.hasTitleDeed !== false;
      }
      if (!data.ownerPhoto && data.ownerPhotoUrl) {
        updates.ownerPhoto = data.ownerPhotoUrl;
      }
      if (!Array.isArray(data.photos)) {
        updates.photos = Array.isArray(data.photoUrls) ? data.photoUrls : [];
      }
      if (!data.localityLower) {
        updates.localityLower = locInfo.city.toLowerCase();
      }
      if (!data.countryCode) {
        updates.countryCode = locInfo.countryCode;
      }

      if (Object.keys(updates).length > 0) {
        await doc.ref.set(updates, {merge: true});
      }
    }

    // 4. Heal events
    const evSnap = await db.collection("events")
        .where("createdViaAiAgent", "==", true)
        .limit(50)
        .get();

    for (const doc of evSnap.docs) {
      const data = doc.data() || {};
      const updates = {};
      if (!data.creatorId && data.organizerId) updates.creatorId = data.organizerId;
      if (!data.creatorName && data.organizerName) updates.creatorName = data.organizerName;
      if (!data.creatorPhoto && data.organizerAvatar) updates.creatorPhoto = data.organizerAvatar;
      if (!data.attendingPermission) updates.attendingPermission = "global_community";
      if (!data.startTime) updates.startTime = "18:00";
      if (!data.endTime) updates.endTime = "21:00";
      if (data.startDate && typeof data.startDate.toDate === "function") {
        const d = data.startDate.toDate();
        updates.startDate = d.toISOString().split("T")[0];
      }
      if (data.endDate && typeof data.endDate.toDate === "function") {
        const d = data.endDate.toDate();
        updates.endDate = d.toISOString().split("T")[0];
      }

      if (Object.keys(updates).length > 0) {
        await doc.ref.set(updates, {merge: true});
      }
    }
  } catch (err) {
    console.warn("[AI Agent] Legacy doc self-healing warning:", err.message);
  }
}

// ── Canonical Firestore Creation Helpers (100% Matching App Models & Chats) ──

async function createCanonicalMarketplaceListing({uid, userProfile = {}, payload = {}}) {
  const ctx = extractUserProfileContext(userProfile);
  const userFullName = ctx.fullName || "Diaspora Member";
  const userAvatar = userProfile.profileImage || userProfile.profilePhoto || userProfile.photoUrl || null;
  const rawType = String(payload.listingType || "job").toLowerCase();
  const listingType = ["job", "product", "service"].includes(rawType) ? rawType : "product";

  const locInfo = resolveLocationDetails({
    city: payload.city,
    country: payload.country,
    countryCode: payload.countryCode,
    userProfile,
  });

  const userComms = Array.isArray(userProfile.communityMemberships) ?
    userProfile.communityMemberships.filter(Boolean) :
    [];
  const communityIds = Array.from(new Set(["global_community", "global", ...userComms]));

  const docRef = db.collection("marketplace_listings").doc();
  const title = String(payload.title || (listingType === "job" ? "Open Position" : "Marketplace Listing")).trim();
  const companyName = String(payload.companyName || userProfile.company || userFullName).trim();
  const employmentTypeNorm = normalizeEmploymentType(payload.employmentType || "Full-time");
  const workModeNorm = normalizeWorkMode(payload.workMode, payload.employmentType);
  const salaryRange = String(payload.salaryRange || "Competitive / Negotiable").trim();
  const experienceLevel = String(payload.experienceLevel || "mid").toLowerCase();
  const priceAmount = listingType === "job" ? 0 : (Number(payload.priceAmount || payload.price) || 0);
  const currency = String(payload.currency || "USD").toUpperCase();
  const description = String(
      payload.description ||
      (listingType === "job" ?
        `${title} role at ${companyName} in ${locInfo.formattedAddress}. Compensation: ${salaryRange}.` :
        `${title} available in ${locInfo.formattedAddress}.`),
  ).trim();

  const category = listingType === "job" ?
    normalizeJobCategory(payload.category, title) :
    normalizeMarketplaceCategory(payload.category, listingType, title);

  const jobDetails = listingType === "job" ? {
    companyName,
    employmentType: employmentTypeNorm,
    salaryRange,
    experienceLevel: ["entry", "mid", "senior", "executive"].includes(experienceLevel) ? experienceLevel : "mid",
    workMode: workModeNorm,
    applicationDeadline: payload.applicationDeadline || null,
    applicationUrl: payload.applicationUrl || null,
  } : null;

  const serviceDetails = listingType === "service" ? {
    pricingModel: String(payload.pricingModel || (priceAmount > 0 ? "fixed" : "quote")).toLowerCase(),
    serviceArea: String(payload.serviceArea || locInfo.city),
  } : null;

  const listingDoc = {
    id: docRef.id,
    listingType,
    sellerId: uid,
    sellerName: userFullName,
    sellerPhoto: userAvatar,
    sellerAvatar: userAvatar,
    sellerVerified: userProfile.isVerified === true,
    sellerCountryCode: locInfo.countryCode,
    sellerCountry: locInfo.countryCode,
    sellerCity: locInfo.city,
    title,
    titleLower: title.toLowerCase(),
    description,
    price: priceAmount,
    priceAmount,
    currency,
    isNegotiable: payload.isNegotiable !== false,
    category,
    condition: listingType === "product" ? (payload.condition || "used_good") : null,
    images: Array.isArray(payload.images) ? payload.images : [],
    location: locInfo.locationMap,
    city: locInfo.city,
    country: locInfo.country,
    countryCode: locInfo.countryCode,
    scope: "global",
    communityIds,
    status: "active",
    isSold: false,
    viewCount: 0,
    saveCount: 0,
    inquiryCount: 0,
    savedBy: [],
    tags: [
      listingType,
      category,
      locInfo.city.toLowerCase(),
      locInfo.country.toLowerCase(),
    ].filter(Boolean),
    contactMethod: "in_app",
    contactPhone: userProfile.phone || null,
    contactEmail: userProfile.email || null,
    contactWhatsapp: userProfile.phone || null,
    jobDetails,
    serviceDetails,
    companyName: listingType === "job" ? companyName : null,
    employmentType: listingType === "job" ? employmentTypeNorm : null,
    salaryRange: listingType === "job" ? salaryRange : null,
    applicationUrl: payload.applicationUrl || null,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    expiresAt: admin.firestore.Timestamp.fromDate(new Date(Date.now() + 60 * 86400000)),
    createdViaAiAgent: true,
  };

  await docRef.set(listingDoc);

  // Also create the dedicated listing discussion chat so "Listing Discussion" works out of the box
  const listingChatId = computeListingChatId(docRef.id);
  const priceDisplay = listingType === "job" ?
    salaryRange :
    (priceAmount > 0 ? `${currency} ${priceAmount}` : "Negotiable");
  const sellerRole = listingType === "job" ?
    "Employer" :
    (listingType === "service" ? "Provider" : "Seller");
  const createdSystemText = listingType === "job" ?
    "Job posted" :
    (listingType === "service" ? "Service posted" : "Shop created");
  const nowMs = Date.now();
  const images = Array.isArray(payload.images) ? payload.images : [];
  const canonicalPhoto = (typeof images[0] === "string" && images[0].startsWith("https://")) ? images[0] : null;

  await db.collection("chats").doc(listingChatId).set({
    id: listingChatId,
    name: title,
    description: `${title} - ${priceDisplay}`,
    photoUrl: canonicalPhoto,
    type: "group",
    subtype: null,
    participants: [uid],
    admins: [uid],
    createdBy: uid,
    creatorId: uid,
    memberCount: 1,
    isPublic: true,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    unreadCount: {[uid]: 0},
    lastMessage: {
      id: "",
      senderId: "system",
      senderName: "System",
      content: createdSystemText,
      type: "system",
      timestamp: nowMs,
      status: "sent",
    },
    metadata: {
      isListingChat: true,
      listingId: docRef.id,
      listingType,
      sellerRole,
    },
    listingId: docRef.id,
    listingData: {
      title,
      price: priceDisplay,
      image: canonicalPhoto,
      category,
      sellerId: uid,
      sellerName: userFullName,
      location: locInfo.formattedAddress,
    },
  }, {merge: true});

  return {
    id: docRef.id,
    title,
    listingType,
    city: locInfo.city,
    country: locInfo.country,
    route: `/marketplace/listing/${docRef.id}`,
    browseRoute: `/marketplace?type=${listingType}`,
    entityLabel: listingType === "job" ?
      `Job "${title}"` :
      (listingType === "service" ? `Service "${title}"` : `Product "${title}"`),
  };
}

async function createCanonicalPeerListing({uid, userProfile = {}, payload = {}}) {
  const ctx = extractUserProfileContext(userProfile);
  const userFullName = ctx.fullName || "Diaspora Member";
  const userAvatar = userProfile.profileImage || userProfile.profilePhoto || userProfile.photoUrl || null;
  const rawType = String(payload.type || payload.subType || "car").toLowerCase();
  const type = ["car", "stay", "hotel"].includes(rawType) ? rawType : "car";

  const locInfo = resolveLocationDetails({
    city: payload.city || payload.locality,
    country: payload.country,
    countryCode: payload.countryCode,
    userProfile,
  });

  const docRef = db.collection("peer_listings").doc();
  const make = String(payload.make || "").trim();
  const model = String(payload.model || "").trim();
  const year = Number(payload.year) || new Date().getFullYear();
  const title = String(
      payload.title ||
      (type === "car" ? `${year} ${make || "Vehicle"} ${model}`.trim() : "Diaspora Stay"),
  ).trim();
  const pricePerUnit = Number(payload.pricePerUnit || payload.pricePerDay || payload.pricePerNight) || (type === "car" ? 45 : 65);
  const currency = String(payload.currency || "USD").toUpperCase();
  const transmission = String(payload.transmission || "automatic").toLowerCase();
  const fuelType = String(payload.fuelType || "petrol").toLowerCase();
  const seats = Number(payload.seats) || 5;
  const propertyType = String(payload.propertyType || (type === "hotel" ? "Boutique Hotel" : "Entire Apartment")).trim();
  const beds = Number(payload.beds) || 2;
  const baths = Number(payload.baths || payload.bathrooms) || 1;
  const maxGuests = Number(payload.maxGuests) || 4;
  const amenities = Array.isArray(payload.amenities) && payload.amenities.length > 0 ?
    payload.amenities :
    (type === "car" ? ["Air Conditioning", "Bluetooth", "GPS"] : ["Wi-Fi", "Air Conditioning", "Kitchen", "Parking"]);
  const description = String(
      payload.description ||
      (type === "car" ?
        `Clean, reliable ${title} available for rental in ${locInfo.formattedAddress}.` :
        `${title} in ${locInfo.formattedAddress} — ${propertyType}, ${beds} bed(s), up to ${maxGuests} guests.`),
  ).trim();

  await docRef.set({
    id: docRef.id,
    type,
    ownerId: uid,
    ownerName: userFullName,
    ownerPhoto: userAvatar,
    ownerPhotoUrl: userAvatar,
    ownerPhone: userProfile.phone || null,
    title,
    description,
    country: locInfo.country,
    countryCode: locInfo.countryCode,
    city: locInfo.city,
    locality: locInfo.city,
    localityLower: locInfo.city.toLowerCase(),
    address: locInfo.formattedAddress,
    pricePerUnit,
    pricePerDay: pricePerUnit,
    pricePerNight: pricePerUnit,
    currency,
    priceUnit: type === "car" ? "day" : "night",
    photos: [],
    photoUrls: [],
    status: "active",
    isAvailable: true,
    verified: userProfile.isVerified === true,
    rating: 5.0,
    reviewCount: 0,
    ...(type === "car" ? {
      make: make || title,
      model,
      year,
      transmission,
      seats,
      fuelType,
      selfDrive: payload.selfDrive !== false,
      withDriver: Boolean(payload.withDriver),
    } : {
      propertyType,
      beds,
      baths,
      maxGuests,
      amenities,
      starRating: type === "hotel" ? (Number(payload.starRating) || 4) : null,
      roomTypes: type === "hotel" ? ["Standard Room", "Deluxe Suite"] : [],
      breakfastIncluded: Boolean(payload.breakfastIncluded),
    }),
    details: type === "car" ? {
      make: make || title,
      model,
      year,
      transmission,
      fuelType,
      seats,
    } : {
      propertyType,
      beds,
      bathrooms: baths,
      maxGuests,
      amenities,
    },
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    createdViaAiAgent: true,
  });

  const browseRoute = type === "car" ?
    "/dsp/travel/car-rental" :
    (type === "hotel" ? "/dsp/travel/hotels" : "/dsp/travel/stays");

  return {
    id: docRef.id,
    title,
    type,
    city: locInfo.city,
    country: locInfo.country,
    route: `/dsp/travel/listing/${docRef.id}`,
    browseRoute,
    entityLabel: `${type === "car" ? "Car Rental" : (type === "hotel" ? "Hotel" : "Stay")} "${title}"`,
  };
}

async function createCanonicalRealEstateListing({uid, userProfile = {}, payload = {}}) {
  const ctx = extractUserProfileContext(userProfile);
  const userFullName = ctx.fullName || "Diaspora Member";
  const userAvatar = userProfile.profileImage || userProfile.profilePhoto || userProfile.photoUrl || null;
  const rawCat = String(payload.category || "house").toLowerCase();
  const category = ["plot", "farm", "house"].includes(rawCat) ? rawCat : "house";
  const listingType = String(payload.listingType || "sale").toLowerCase() === "rent" ? "rent" : "sale";

  const locInfo = resolveLocationDetails({
    city: payload.city || payload.locality,
    country: payload.country,
    countryCode: payload.countryCode,
    userProfile,
  });

  const docRef = db.collection("real_estate_listings").doc();
  const title = String(payload.title || "Property Listing").trim();
  const price = Number(payload.price) || 25000;
  const currency = String(payload.currency || "USD").toUpperCase();
  const size = Number(payload.size || payload.sizeSqm) || 500;
  const sizeUnit = String(payload.sizeUnit || "m²") === "sqm" ? "m²" : String(payload.sizeUnit || "m²");
  const description = String(
      payload.description ||
      `${title} (${size} ${sizeUnit}) for ${listingType} in ${locInfo.formattedAddress}.`,
  ).trim();

  await docRef.set({
    id: docRef.id,
    category,
    listingType,
    ownerId: uid,
    ownerName: userFullName,
    ownerPhoto: userAvatar,
    ownerPhotoUrl: userAvatar,
    ownerPhone: userProfile.phone || null,
    ownerRole: payload.ownerRole || "owner",
    title,
    description,
    country: locInfo.country,
    countryCode: locInfo.countryCode,
    city: locInfo.city,
    locality: locInfo.city,
    localityLower: locInfo.city.toLowerCase(),
    address: locInfo.formattedAddress,
    price,
    currency,
    priceNegotiable: payload.priceNegotiable !== false,
    installmentAvailable: Boolean(payload.installmentAvailable),
    size,
    sizeSqm: size,
    sizeUnit,
    hasTitle: payload.hasTitle !== false,
    hasTitleDeed: payload.hasTitle !== false,
    titleType: payload.titleType || "Certificate of Occupancy",
    surveyed: payload.surveyed !== false,
    photos: [],
    photoUrls: [],
    status: "active",
    verified: userProfile.isVerified === true,
    isVerified: userProfile.isVerified === true,
    locationVerified: false,
    escrowEligible: true,
    bedrooms: category === "house" ? (Number(payload.bedrooms) || 3) : null,
    bathrooms: category === "house" ? (Number(payload.bathrooms) || 2) : null,
    furnished: Boolean(payload.furnished),
    yearBuilt: category === "house" ? (Number(payload.yearBuilt) || new Date().getFullYear() - 2) : null,
    zoning: category === "plot" ? (payload.zoning || "residential") : null,
    roadAccess: true,
    waterAvailable: true,
    electricityAvailable: true,
    amenities: [],
    specs: {},
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    createdViaAiAgent: true,
  });

  return {
    id: docRef.id,
    title,
    category,
    city: locInfo.city,
    country: locInfo.country,
    route: `/dsp/real-estate/listing/${docRef.id}`,
    browseRoute: `/dsp/real-estate/${category}`,
    entityLabel: `Property "${title}"`,
  };
}

async function createCanonicalEvent({uid, userProfile = {}, payload = {}}) {
  const ctx = extractUserProfileContext(userProfile);
  const userFullName = ctx.fullName || "Diaspora Member";
  const userAvatar = userProfile.profileImage || userProfile.profilePhoto || userProfile.photoUrl || null;
  const docRef = db.collection("events").doc();
  const title = String(payload.title || "Community Event").trim();
  const location = String(payload.location || ctx.hostCity || ctx.homeCity || "Dar es Salaam").trim();
  const startDate = /^\d{4}-\d{2}-\d{2}$/.test(String(payload.startDate || "").trim()) ?
    String(payload.startDate).trim() :
    resolveDefaultFutureDate(7);
  const startTime = /^\d{2}:\d{2}$/.test(String(payload.startTime || "").trim()) ?
    String(payload.startTime).trim() :
    "18:00";
  const endDate = /^\d{4}-\d{2}-\d{2}$/.test(String(payload.endDate || "").trim()) ?
    String(payload.endDate).trim() :
    startDate;
  const endTime = /^\d{2}:\d{2}$/.test(String(payload.endTime || "").trim()) ?
    String(payload.endTime).trim() :
    "21:00";
  const category = String(payload.category || "Networking").trim();
  const description = String(payload.description || `Join us for ${title} at ${location}.`).trim();
  const eventChatId = `event_${docRef.id}`;

  await docRef.set({
    id: docRef.id,
    title,
    description,
    category,
    startDate,
    startTime,
    endDate,
    endTime,
    location,
    isVirtual: Boolean(payload.isVirtual),
    virtualLink: payload.virtualLink || null,
    creatorId: uid,
    creatorName: userFullName,
    creatorPhoto: userAvatar,
    organizerId: uid,
    organizerName: userFullName,
    organizerAvatar: userAvatar,
    attendingPermission: "global_community",
    communityId: "global_community",
    attendees: [uid],
    interested: [],
    attendeeCount: 1,
    status: "published",
    type: "EventType.community",
    visibility: "EventVisibility.public",
    isFree: payload.isFree !== false,
    ticketPrice: Number(payload.ticketPrice) || null,
    currency: String(payload.currency || "USD").toUpperCase(),
    chatId: eventChatId,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    createdViaAiAgent: true,
  });

  await db.collection("chats").doc(eventChatId).set({
    id: eventChatId,
    name: title,
    description: description || `Discussion for ${title}`,
    image: null,
    type: "ChatType.event",
    participants: [uid],
    admins: [uid],
    creatorId: uid,
    visibleTo: [],
    visibility: "public",
    eventId: docRef.id,
    eventData: {
      title,
      date: startDate,
      time: startTime,
      location,
      category,
      image: null,
      organizerId: uid,
      organizerName: userFullName,
    },
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    unreadCount: {[uid]: 0},
  }, {merge: true});

  return {
    id: docRef.id,
    title,
    location,
    startDate,
    startTime,
    route: `/events/${docRef.id}`,
    browseRoute: "/events",
    entityLabel: `Event "${title}"`,
  };
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
  await healLegacyAiAgentDocs();
  const listingType = String(args.type || "car").toLowerCase(); // "car" | "stay" | "hotel"
  const city = String(args.city || "").trim().toLowerCase();
  const snap = await db.collection("peer_listings")
      .where("type", "==", listingType === "stay" ? "stay" : (listingType === "hotel" ? "hotel" : "car"))
      .limit(20)
      .get();

  let docs = snap.docs
      .map((d) => ({id: d.id, ...d.data()}))
      .filter((item) => item.isAvailable !== false && item.status !== "paused");

  if (city) {
    const filtered = docs.filter((item) =>
      String(item.city || item.locality || "").toLowerCase().includes(city) ||
      String(item.title || "").toLowerCase().includes(city) ||
      String(item.description || "").toLowerCase().includes(city),
    );
    if (filtered.length > 0) docs = filtered;
  }

  const topItems = docs.slice(0, 4).map((item) => ({
    id: item.id,
    title: item.title,
    city: item.city || item.locality,
    pricePerDay: item.pricePerUnit || item.pricePerDay || item.pricePerNight,
    currency: item.currency || "USD",
    details: item.details || {},
  }));

  const route = listingType === "stay" ?
    "/dsp/travel/stays" :
    (listingType === "hotel" ? "/dsp/travel/hotels" : "/dsp/travel/car-rental");
  const label = listingType === "stay" ?
    `View Stays${args.city ? ` in ${args.city}` : ""}` :
    `View Car Rentals${args.city ? ` in ${args.city}` : ""}`;

  const actions = [];
  if (topItems.length > 0) {
    actions.push({
      id: `peer_item_${topItems[0].id}`,
      type: "navigate",
      label: `View "${topItems[0].title}"`,
      route: `/dsp/travel/listing/${topItems[0].id}`,
      icon: listingType === "stay" ? "hotel" : "car",
    });
  }
  actions.push({
    id: `peer_${listingType}_${Date.now()}`,
    type: "navigate",
    label,
    route,
    icon: listingType === "stay" ? "hotel" : "car",
  });

  return {
    type: listingType,
    count: topItems.length,
    listings: topItems,
    aiActions: actions,
  };
}

async function executeSearchJobsAndMarketplaceTool(args = {}) {
  await healLegacyAiAgentDocs();
  const listingType = String(args.listingType || "job").toLowerCase(); // "job" | "product" | "service"
  const keyword = String(args.keyword || "").trim().toLowerCase();
  const city = String(args.city || "").trim().toLowerCase();

  const snap = await db.collection("marketplace_listings")
      .where("status", "==", "active")
      .limit(40)
      .get();

  let items = snap.docs.map((d) => ({id: d.id, ...d.data()}));
  if (listingType && ["job", "product", "service"].includes(listingType)) {
    const byType = items.filter((i) => String(i.listingType || "product") === listingType);
    if (byType.length > 0 || listingType === "job") {
      items = byType;
    }
  }
  if (city) {
    const byCity = items.filter((i) => {
      const locCity = typeof i.location === "object" ? (i.location?.city || "") : String(i.location || "");
      const locCountry = typeof i.location === "object" ? (i.location?.country || "") : "";
      return String(i.city || locCity).toLowerCase().includes(city) ||
        String(i.country || locCountry).toLowerCase().includes(city);
    });
    if (byCity.length > 0) items = byCity;
  }
  if (keyword) {
    const byKw = items.filter((i) =>
      String(i.title || "").toLowerCase().includes(keyword) ||
      String(i.description || "").toLowerCase().includes(keyword) ||
      String(i.companyName || i.jobDetails?.companyName || "").toLowerCase().includes(keyword) ||
      String(i.category || "").toLowerCase().includes(keyword),
    );
    if (byKw.length > 0) items = byKw;
  }

  const top = items.slice(0, 4).map((i) => {
    const locCity = typeof i.location === "object" ? (i.location?.city || i.city || "") : (i.city || "");
    const locCountry = typeof i.location === "object" ? (i.location?.country || i.country || "") : (i.country || "");
    return {
      id: i.id,
      title: i.title,
      listingType: i.listingType,
      companyName: i.jobDetails?.companyName || i.companyName || i.sellerName || "",
      city: locCity,
      country: locCountry,
      salaryRange: i.jobDetails?.salaryRange || i.salaryRange || (i.priceAmount ? `${i.currency || "USD"} ${i.priceAmount}` : "Negotiable"),
      employmentType: i.jobDetails?.employmentType || i.employmentType || "",
    };
  });

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
    label: listingType === "job" ?
      "Browse All Jobs" :
      (listingType === "service" ? "Browse Services" : "Browse Products"),
    route: `/marketplace?type=${listingType}`,
    icon: listingType === "job" ? "briefcase" : "shopping",
  });

  return {
    listingType,
    count: top.length,
    listings: top,
    aiActions: actions,
  };
}

async function executeSearchRealEstateTool(args = {}) {
  await healLegacyAiAgentDocs();
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
      String(i.city || i.locality || "").toLowerCase().includes(city) ||
      String(i.country || "").toLowerCase().includes(city),
    );
    if (byCity.length > 0) items = byCity;
  }

  const top = items.slice(0, 4).map((i) => ({
    id: i.id,
    title: i.title,
    category: i.category,
    price: `${i.currency || "USD"} ${i.price}`,
    sizeSqm: i.size || i.sizeSqm,
    city: i.city || i.locality,
    country: i.country,
    listingType: i.listingType,
  }));

  const validCat = ["plot", "farm", "house"].includes(category) ? category : "house";
  const catPluralLabel = validCat === "plot" ? "Plots" : (validCat === "farm" ? "Farms" : "Houses");
  const actions = [];
  if (top.length > 0) {
    actions.push({
      id: `re_item_${top[0].id}`,
      type: "navigate",
      label: `View "${top[0].title}"`,
      route: `/dsp/real-estate/listing/${top[0].id}`,
      icon: "home",
    });
  }
  actions.push({
    id: `re_${validCat}_${Date.now()}`,
    type: "navigate",
    label: `Browse ${catPluralLabel}`,
    route: `/dsp/real-estate/${validCat}`,
    icon: "home",
  });

  return {
    category: validCat,
    count: top.length,
    listings: top,
    aiActions: actions,
  };
}

async function executeSearchEventsTool(args = {}) {
  await healLegacyAiAgentDocs();
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
    startDate: e.startDate,
    startTime: e.startTime,
    category: e.category,
    isFree: e.isFree !== false,
  }));

  const actions = [];
  if (top.length > 0) {
    actions.push({
      id: `event_item_${top[0].id}`,
      type: "navigate",
      label: `View "${top[0].title}"`,
      route: `/events/${top[0].id}`,
      icon: "calendar",
    });
  }
  actions.push({
    id: `events_${Date.now()}`,
    type: "navigate",
    label: "Explore Diaspora Events",
    route: "/events",
    icon: "calendar",
  });

  return {
    count: top.length,
    events: top,
    aiActions: actions,
  };
}

// ── Draft & Direct Publishing Tools (Publishes Immediately in Firestore When User Requests) ──

function buildDraftAction({draftType, label, summaryTitle, summaryRows, payload, fallbackRoute, status = "pending", createdEntityId = null, createdRoute = null}) {
  return {
    id: `draft_${draftType}_${Date.now()}`,
    type: "execute_draft",
    draftType,
    label,
    summaryTitle,
    summaryRows,
    payload,
    fallbackRoute,
    status,
    ...(createdEntityId ? {createdEntityId} : {}),
    ...(createdRoute ? {createdRoute} : {}),
  };
}

async function prepareJobDraftTool(args = {}, userProfile = {}) {
  const ctx = extractUserProfileContext(userProfile);
  const uid = String(userProfile.uid || "").trim();
  const title = String(args.title || "").trim();
  const companyName = String(args.companyName || userProfile.company || ctx.fullName || "Diaspora Employer").trim();
  const locInfo = resolveLocationDetails({
    city: args.city,
    country: args.country,
    userProfile,
  });
  const employmentType = String(args.employmentType || "Full-time").trim();
  const salaryRange = String(args.salaryRange || "Competitive / Negotiable").trim();
  const description = String(args.description || `${title} role at ${companyName} in ${locInfo.formattedAddress}.`).trim();
  const category = normalizeJobCategory(args.category, title);
  const applicationUrl = String(args.applicationUrl || "").trim();

  if (!title) {
    return {
      ready: false,
      missingFields: ["title", "city", "description or salaryRange"],
    };
  }

  const payload = {
    listingType: "job",
    title,
    companyName,
    city: locInfo.city,
    country: locInfo.country,
    countryCode: locInfo.countryCode,
    employmentType,
    salaryRange,
    description,
    category,
    applicationUrl,
  };

  if (uid && args.draftOnly !== true) {
    const created = await createCanonicalMarketplaceListing({uid, userProfile, payload});
    return {
      ready: true,
      published: true,
      listingId: created.id,
      title: created.title,
      city: created.city,
      country: created.country,
      route: created.route,
      aiActions: [
        {
          id: `view_job_${created.id}`,
          type: "navigate",
          label: `View "${created.title}"`,
          route: created.route,
          icon: "briefcase",
        },
        {
          id: `browse_jobs_${Date.now()}`,
          type: "navigate",
          label: "Browse All Jobs",
          route: "/marketplace?type=job",
          icon: "briefcase",
        },
      ],
    };
  }

  const draftAction = buildDraftAction({
    draftType: "post_job",
    label: `Publish Job: ${title}`,
    summaryTitle: `Job Listing: ${title}`,
    summaryRows: [
      {label: "Company", value: companyName},
      {label: "Location", value: locInfo.formattedAddress},
      {label: "Type", value: employmentType},
      {label: "Compensation", value: salaryRange},
    ],
    payload,
    fallbackRoute: "/marketplace/create",
  });

  return {
    ready: true,
    draftAction,
  };
}

async function prepareCarRentalDraftTool(args = {}, userProfile = {}) {
  const uid = String(userProfile.uid || "").trim();
  const make = String(args.make || "").trim();
  const model = String(args.model || "").trim();
  const year = Number(args.year) || new Date().getFullYear();
  const pricePerDay = Number(args.pricePerDay) || 45;
  const currency = String(args.currency || "USD").toUpperCase();
  const locInfo = resolveLocationDetails({
    city: args.city,
    country: args.country,
    userProfile,
  });
  const transmission = String(args.transmission || "Automatic").trim();
  const fuelType = String(args.fuelType || "Petrol").trim();
  const seats = Number(args.seats) || 5;
  const title = String(args.title || `${year} ${make} ${model}`.trim()).trim();
  const description = String(
      args.description ||
      `Clean, reliable ${title} available for daily rental in ${locInfo.formattedAddress}. ${transmission}, ${fuelType}, ${seats} seats.`,
  ).trim();

  if (!make && !args.title) {
    return {
      ready: false,
      missingFields: ["make/model", "pricePerDay", "city"],
    };
  }

  const payload = {
    type: "car",
    title,
    make: make || title,
    model,
    year,
    pricePerDay,
    pricePerUnit: pricePerDay,
    currency,
    city: locInfo.city,
    country: locInfo.country,
    countryCode: locInfo.countryCode,
    transmission,
    fuelType,
    seats,
    description,
  };

  if (uid && args.draftOnly !== true) {
    const created = await createCanonicalPeerListing({uid, userProfile, payload});
    return {
      ready: true,
      published: true,
      listingId: created.id,
      title: created.title,
      route: created.route,
      aiActions: [
        {
          id: `view_car_${created.id}`,
          type: "navigate",
          label: `View "${created.title}"`,
          route: created.route,
          icon: "car",
        },
        {
          id: `browse_cars_${Date.now()}`,
          type: "navigate",
          label: "Browse Car Rentals",
          route: "/dsp/travel/car-rental",
          icon: "car",
        },
      ],
    };
  }

  const draftAction = buildDraftAction({
    draftType: "post_car_rental",
    label: `Publish Car Rental: ${title}`,
    summaryTitle: `Car Rental: ${title}`,
    summaryRows: [
      {label: "City", value: locInfo.formattedAddress},
      {label: "Rate", value: `${currency} ${pricePerDay} / day`},
      {label: "Specs", value: `${transmission} • ${fuelType} • ${seats} seats`},
    ],
    payload,
    fallbackRoute: "/dsp/travel/car-rental",
  });

  return {
    ready: true,
    draftAction,
  };
}

async function prepareStayOrHotelDraftTool(args = {}, userProfile = {}) {
  const uid = String(userProfile.uid || "").trim();
  const subType = String(args.subType || "stay").toLowerCase() === "hotel" ? "hotel" : "stay";
  const title = String(args.title || "").trim();
  const locInfo = resolveLocationDetails({
    city: args.city,
    country: args.country,
    userProfile,
  });
  const pricePerNight = Number(args.pricePerNight || args.pricePerDay) || 65;
  const currency = String(args.currency || "USD").toUpperCase();
  const propertyType = String(args.propertyType || (subType === "hotel" ? "Boutique Hotel" : "Entire Apartment")).trim();
  const beds = Number(args.beds) || 2;
  const maxGuests = Number(args.maxGuests) || 4;
  const description = String(
      args.description || `${title} in ${locInfo.formattedAddress} — ${propertyType}, ${beds} bed(s), up to ${maxGuests} guests.`,
  ).trim();

  if (!title) {
    return {
      ready: false,
      missingFields: ["title", "city", "pricePerNight"],
    };
  }

  const payload = {
    type: subType,
    subType,
    title,
    city: locInfo.city,
    country: locInfo.country,
    countryCode: locInfo.countryCode,
    pricePerNight,
    pricePerUnit: pricePerNight,
    currency,
    propertyType,
    beds,
    maxGuests,
    description,
  };

  if (uid && args.draftOnly !== true) {
    const created = await createCanonicalPeerListing({uid, userProfile, payload});
    return {
      ready: true,
      published: true,
      listingId: created.id,
      title: created.title,
      route: created.route,
      aiActions: [
        {
          id: `view_stay_${created.id}`,
          type: "navigate",
          label: `View "${created.title}"`,
          route: created.route,
          icon: "hotel",
        },
        {
          id: `browse_stays_${Date.now()}`,
          type: "navigate",
          label: subType === "hotel" ? "Browse Hotels" : "Browse Stays",
          route: created.browseRoute,
          icon: "hotel",
        },
      ],
    };
  }

  const draftAction = buildDraftAction({
    draftType: "post_stay",
    label: `Publish ${subType === "hotel" ? "Hotel" : "Stay"}: ${title}`,
    summaryTitle: `${subType === "hotel" ? "Hotel" : "Stay"}: ${title}`,
    summaryRows: [
      {label: "Location", value: locInfo.formattedAddress},
      {label: "Rate", value: `${currency} ${pricePerNight} / night`},
      {label: "Property", value: `${propertyType} • ${beds} beds • ${maxGuests} guests`},
    ],
    payload,
    fallbackRoute: subType === "hotel" ? "/dsp/travel/hotels" : "/dsp/travel/stays",
  });

  return {
    ready: true,
    draftAction,
  };
}

async function prepareMarketplaceDraftTool(args = {}, userProfile = {}) {
  const uid = String(userProfile.uid || "").trim();
  const listingType = String(args.listingType || "product").toLowerCase() === "service" ? "service" : "product";
  const title = String(args.title || "").trim();
  const priceAmount = Number(args.priceAmount || args.price) || 0;
  const currency = String(args.currency || "USD").toUpperCase();
  const locInfo = resolveLocationDetails({
    city: args.city,
    country: args.country,
    userProfile,
  });
  const category = normalizeMarketplaceCategory(args.category, listingType, title);
  const description = String(args.description || `${title} available in ${locInfo.formattedAddress}.`).trim();

  if (!title) {
    return {
      ready: false,
      missingFields: ["title", "priceAmount", "city"],
    };
  }

  const payload = {
    listingType,
    title,
    priceAmount,
    currency,
    city: locInfo.city,
    country: locInfo.country,
    countryCode: locInfo.countryCode,
    category,
    description,
  };

  if (uid && args.draftOnly !== true) {
    const created = await createCanonicalMarketplaceListing({uid, userProfile, payload});
    return {
      ready: true,
      published: true,
      listingId: created.id,
      title: created.title,
      route: created.route,
      aiActions: [
        {
          id: `view_mkt_${created.id}`,
          type: "navigate",
          label: `View "${created.title}"`,
          route: created.route,
          icon: "shopping",
        },
        {
          id: `browse_mkt_${Date.now()}`,
          type: "navigate",
          label: listingType === "service" ? "Browse Services" : "Browse Products",
          route: created.browseRoute,
          icon: "shopping",
        },
      ],
    };
  }

  const draftAction = buildDraftAction({
    draftType: "post_marketplace",
    label: `Publish ${listingType === "service" ? "Service" : "Product"}: ${title}`,
    summaryTitle: `${listingType === "service" ? "Service" : "Product"}: ${title}`,
    summaryRows: [
      {label: "Type", value: listingType === "service" ? "Service" : "Product"},
      {label: listingType === "service" ? "Rate" : "Price", value: priceAmount > 0 ? `${currency} ${priceAmount}` : "Negotiable"},
      {label: "Location", value: locInfo.formattedAddress},
    ],
    payload,
    fallbackRoute: "/marketplace/create",
  });

  return {
    ready: true,
    draftAction,
  };
}

async function prepareRealEstateDraftTool(args = {}, userProfile = {}) {
  const uid = String(userProfile.uid || "").trim();
  const rawCat = String(args.category || "house").toLowerCase();
  const category = ["plot", "farm", "house"].includes(rawCat) ? rawCat : "house";
  const catSingular = category === "plot" ? "Plot" : (category === "farm" ? "Farm" : "House");
  const catPlural = category === "plot" ? "Plots" : (category === "farm" ? "Farms" : "Houses");
  const title = String(args.title || "").trim();
  const price = Number(args.price) || 0;
  const currency = String(args.currency || "USD").toUpperCase();
  const sizeSqm = Number(args.sizeSqm || args.size) || 500;
  const listingType = String(args.listingType || "sale").toLowerCase() === "rent" ? "rent" : "sale";
  const locInfo = resolveLocationDetails({
    city: args.city,
    country: args.country,
    userProfile,
  });
  const description = String(args.description || `${title} (${sizeSqm} m²) for ${listingType} in ${locInfo.formattedAddress}.`).trim();

  if (!title || price <= 0) {
    return {
      ready: false,
      missingFields: ["title", "price", "city", "sizeSqm"],
    };
  }

  const payload = {
    category,
    title,
    price,
    currency,
    size: sizeSqm,
    sizeSqm,
    listingType,
    city: locInfo.city,
    country: locInfo.country,
    countryCode: locInfo.countryCode,
    description,
  };

  if (uid && args.draftOnly !== true) {
    const created = await createCanonicalRealEstateListing({uid, userProfile, payload});
    return {
      ready: true,
      published: true,
      listingId: created.id,
      title: created.title,
      route: created.route,
      aiActions: [
        {
          id: `view_re_${created.id}`,
          type: "navigate",
          label: `View "${created.title}"`,
          route: created.route,
          icon: "home",
        },
        {
          id: `browse_re_${Date.now()}`,
          type: "navigate",
          label: `Browse ${catPlural}`,
          route: created.browseRoute,
          icon: "home",
        },
      ],
    };
  }

  const draftAction = buildDraftAction({
    draftType: "post_real_estate",
    label: `Publish ${catSingular}: ${title}`,
    summaryTitle: `${catSingular}: ${title}`,
    summaryRows: [
      {label: "Category", value: `${catSingular} (For ${listingType === "rent" ? "Rent" : "Sale"})`},
      {label: "Price", value: `${currency} ${price.toLocaleString()}`},
      {label: "Size & City", value: `${sizeSqm} m² • ${locInfo.formattedAddress}`},
    ],
    payload,
    fallbackRoute: `/dsp/real-estate/${category}`,
  });

  return {
    ready: true,
    draftAction,
  };
}

async function prepareEventDraftTool(args = {}, userProfile = {}) {
  const ctx = extractUserProfileContext(userProfile);
  const uid = String(userProfile.uid || "").trim();
  const title = String(args.title || "").trim();
  const location = String(args.location || ctx.hostCity || ctx.currentCity || ctx.homeCity || "Dar es Salaam").trim();
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

  const payload = {
    title,
    location,
    startDate,
    startTime,
    category,
    description,
  };

  if (uid && args.draftOnly !== true) {
    const created = await createCanonicalEvent({uid, userProfile, payload});
    return {
      ready: true,
      published: true,
      eventId: created.id,
      title: created.title,
      route: created.route,
      aiActions: [
        {
          id: `view_event_${created.id}`,
          type: "navigate",
          label: `View "${created.title}"`,
          route: created.route,
          icon: "calendar",
        },
        {
          id: `browse_events_${Date.now()}`,
          type: "navigate",
          label: "Browse All Events",
          route: "/events",
          icon: "calendar",
        },
      ],
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
    payload,
    fallbackRoute: "/events/create",
  });

  return {
    ready: true,
    draftAction,
  };
}

// ── Full User Task Execution Tools (Manage Listings, Book, RSVP, Hosting, Members, Chats, Profile, Check-In, Ubuntu Fund, DDI, Feedback) ──

async function executeManageMyListingsTool(args = {}, userProfile = {}) {
  const uid = String(userProfile.uid || "").trim();
  if (!uid) return {error: "User authentication required."};

  const action = String(args.action || "list").toLowerCase(); // "list" | "update" | "pause" | "activate" | "mark_sold" | "delete"
  const targetId = String(args.listingId || "").trim();
  const targetTitle = String(args.titleKeyword || "").trim().toLowerCase();

  const [mktSnap, peerSnap, reSnap, evSnap] = await Promise.all([
    db.collection("marketplace_listings").where("sellerId", "==", uid).limit(25).get(),
    db.collection("peer_listings").where("ownerId", "==", uid).limit(25).get(),
    db.collection("real_estate_listings").where("ownerId", "==", uid).limit(25).get(),
    db.collection("events").where("creatorId", "==", uid).limit(25).get(),
  ]);

  const allListings = [
    ...mktSnap.docs.map((d) => ({
      id: d.id,
      collection: "marketplace_listings",
      kind: d.data().listingType || "product",
      title: d.data().title,
      status: d.data().status || "active",
      route: `/marketplace/listing/${d.id}`,
      ref: d.ref,
      data: d.data(),
    })),
    ...peerSnap.docs.map((d) => ({
      id: d.id,
      collection: "peer_listings",
      kind: d.data().type || "car",
      title: d.data().title,
      status: d.data().status || "active",
      route: `/dsp/travel/listing/${d.id}`,
      ref: d.ref,
      data: d.data(),
    })),
    ...reSnap.docs.map((d) => ({
      id: d.id,
      collection: "real_estate_listings",
      kind: `real_estate_${d.data().category || "house"}`,
      title: d.data().title,
      status: d.data().status || "active",
      route: `/dsp/real-estate/listing/${d.id}`,
      ref: d.ref,
      data: d.data(),
    })),
    ...evSnap.docs.map((d) => ({
      id: d.id,
      collection: "events",
      kind: "event",
      title: d.data().title,
      status: d.data().status || "published",
      route: `/events/${d.id}`,
      ref: d.ref,
      data: d.data(),
    })),
  ];

  if (action === "list") {
    const actions = allListings.slice(0, 3).map((item) => ({
      id: `my_item_${item.id}`,
      type: "navigate",
      label: `View "${item.title}"`,
      route: item.route,
      icon: "briefcase",
    }));
    actions.push({
      id: `my_listings_screen_${Date.now()}`,
      type: "navigate",
      label: "Manage My Listings",
      route: "/marketplace/my-listings",
      icon: "briefcase",
    });
    return {
      count: allListings.length,
      listings: allListings.map((i) => ({
        id: i.id,
        kind: i.kind,
        title: i.title,
        status: i.status,
        route: i.route,
      })),
      aiActions: actions,
    };
  }

  const matched = allListings.find((item) =>
    (targetId && item.id === targetId) ||
    (targetTitle && String(item.title || "").toLowerCase().includes(targetTitle)),
  ) || allListings[0];

  if (!matched) {
    return {
      success: false,
      message: "No matching listing found under your account.",
    };
  }

  if (action === "delete") {
    await matched.ref.delete();
    return {
      success: true,
      action: "deleted",
      deletedId: matched.id,
      title: matched.title,
      aiActions: [
        {
          id: `my_listings_after_del_${Date.now()}`,
          type: "navigate",
          label: "Open My Listings",
          route: "/marketplace/my-listings",
          icon: "briefcase",
        },
      ],
    };
  }

  const updates = {
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };
  if (action === "pause") {
    updates.status = "paused";
    if (matched.collection === "peer_listings") updates.isAvailable = false;
  } else if (action === "activate") {
    updates.status = matched.collection === "events" ? "published" : "active";
    if (matched.collection === "peer_listings") updates.isAvailable = true;
  } else if (action === "mark_sold") {
    updates.status = "sold";
    updates.isSold = true;
  } else if (action === "update") {
    if (args.newTitle) {
      updates.title = String(args.newTitle).trim();
      updates.titleLower = updates.title.toLowerCase();
    }
    if (args.newDescription) {
      updates.description = String(args.newDescription).trim();
    }
    if (args.newPrice != null) {
      const p = Number(args.newPrice) || 0;
      if (matched.collection === "marketplace_listings") {
        updates.price = p;
        updates.priceAmount = p;
      } else if (matched.collection === "peer_listings") {
        updates.pricePerUnit = p;
        updates.pricePerDay = p;
      } else if (matched.collection === "real_estate_listings") {
        updates.price = p;
      }
    }
    if (args.newSalaryRange && matched.collection === "marketplace_listings") {
      updates.salaryRange = String(args.newSalaryRange).trim();
      updates["jobDetails.salaryRange"] = updates.salaryRange;
    }
  }

  await matched.ref.update(updates);
  return {
    success: true,
    action,
    listingId: matched.id,
    title: updates.title || matched.title,
    route: matched.route,
    aiActions: [
      {
        id: `view_updated_${matched.id}`,
        type: "navigate",
        label: `View "${updates.title || matched.title}"`,
        route: matched.route,
        icon: "check",
      },
    ],
  };
}

async function executeSaveOrUnsaveListingTool(args = {}, userProfile = {}) {
  const uid = String(userProfile.uid || "").trim();
  if (!uid) return {error: "User authentication required."};
  const listingId = String(args.listingId || "").trim();
  const keyword = String(args.keyword || "").trim().toLowerCase();
  const unsave = args.unsave === true;

  let targetDoc = null;
  if (listingId && validId(listingId)) {
    const snap = await db.collection("marketplace_listings").doc(listingId).get();
    if (snap.exists) targetDoc = snap;
  }
  if (!targetDoc && keyword) {
    const snap = await db.collection("marketplace_listings").where("status", "==", "active").limit(30).get();
    targetDoc = snap.docs.find((d) => String(d.data().title || "").toLowerCase().includes(keyword)) || null;
  }
  if (!targetDoc) {
    return {success: false, message: "Could not find the specified listing to save."};
  }

  await targetDoc.ref.update({
    savedBy: unsave ?
      admin.firestore.FieldValue.arrayRemove(uid) :
      admin.firestore.FieldValue.arrayUnion(uid),
    saveCount: admin.firestore.FieldValue.increment(unsave ? -1 : 1),
  });

  const title = targetDoc.data().title || "Listing";
  return {
    success: true,
    saved: !unsave,
    listingId: targetDoc.id,
    title,
    aiActions: [
      {
        id: `view_saved_${targetDoc.id}`,
        type: "navigate",
        label: `View "${title}"`,
        route: `/marketplace/listing/${targetDoc.id}`,
        icon: "briefcase",
      },
      {
        id: `view_all_saved_${Date.now()}`,
        type: "navigate",
        label: "Open Saved Listings",
        route: "/marketplace/saved",
        icon: "briefcase",
      },
    ],
  };
}

async function executeBookCarOrStayTool(args = {}, userProfile = {}) {
  const uid = String(userProfile.uid || "").trim();
  if (!uid) return {error: "User authentication required."};
  const ctx = extractUserProfileContext(userProfile);

  const listingId = String(args.listingId || "").trim();
  const keyword = String(args.keyword || "").trim().toLowerCase();
  let listingSnap = null;
  if (listingId && validId(listingId)) {
    const s = await db.collection("peer_listings").doc(listingId).get();
    if (s.exists) listingSnap = s;
  }
  if (!listingSnap) {
    const s = await db.collection("peer_listings").limit(25).get();
    listingSnap = s.docs.find((d) =>
      !keyword ||
      String(d.data().title || "").toLowerCase().includes(keyword) ||
      String(d.data().city || "").toLowerCase().includes(keyword),
    ) || null;
  }
  if (!listingSnap) {
    return {success: false, message: "No matching car rental or stay found to book."};
  }

  const listing = listingSnap.data() || {};
  const startDate = /^\d{4}-\d{2}-\d{2}$/.test(String(args.startDate || "").trim()) ?
    String(args.startDate).trim() :
    resolveDefaultFutureDate(3);
  const days = Math.max(1, Number(args.days || args.nights) || 3);
  const startMs = new Date(`${startDate}T00:00:00Z`).getTime();
  const endDate = new Date(startMs + days * 86400000).toISOString().split("T")[0];
  const unitPrice = Number(listing.pricePerUnit || listing.pricePerDay || 50);
  const totalPrice = Number((unitPrice * days).toFixed(2));

  const bookingRef = db.collection("peer_bookings").doc();
  await bookingRef.set({
    id: bookingRef.id,
    listingId: listingSnap.id,
    listingType: listing.type || "car",
    listingTitle: listing.title || "Listing",
    ownerId: listing.ownerId || "",
    renterId: uid,
    renterName: ctx.fullName,
    renterPhone: userProfile.phone || null,
    startDate: admin.firestore.Timestamp.fromDate(new Date(`${startDate}T00:00:00Z`)),
    endDate: admin.firestore.Timestamp.fromDate(new Date(`${endDate}T00:00:00Z`)),
    days,
    guests: Math.max(1, Number(args.guests) || 1),
    unitPrice,
    totalPrice,
    currency: listing.currency || "USD",
    notes: String(args.notes || "Booked via Diaspora AI Agent"),
    status: "pending",
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  return {
    success: true,
    bookingId: bookingRef.id,
    listingTitle: listing.title,
    startDate,
    endDate,
    days,
    totalPrice: `${listing.currency || "USD"} ${totalPrice}`,
    aiActions: [
      {
        id: `view_booked_${listingSnap.id}`,
        type: "navigate",
        label: `View "${listing.title}"`,
        route: `/dsp/travel/listing/${listingSnap.id}`,
        icon: listing.type === "car" ? "car" : "hotel",
      },
    ],
  };
}

async function executeRsvpOrInterestEventTool(args = {}, userProfile = {}) {
  const uid = String(userProfile.uid || "").trim();
  if (!uid) return {error: "User authentication required."};

  const eventId = String(args.eventId || "").trim();
  const keyword = String(args.keyword || "").trim().toLowerCase();
  const mode = String(args.mode || "rsvp").toLowerCase(); // "rsvp" | "interested" | "cancel"

  let eventDoc = null;
  if (eventId && validId(eventId)) {
    const s = await db.collection("events").doc(eventId).get();
    if (s.exists) eventDoc = s;
  }
  if (!eventDoc) {
    const s = await db.collection("events").where("status", "==", "published").limit(20).get();
    eventDoc = s.docs.find((d) =>
      !keyword ||
      String(d.data().title || "").toLowerCase().includes(keyword) ||
      String(d.data().location || "").toLowerCase().includes(keyword),
    ) || null;
  }
  if (!eventDoc) {
    return {success: false, message: "Could not find a matching event."};
  }

  const evData = eventDoc.data() || {};
  if (mode === "cancel") {
    await eventDoc.ref.update({
      attendees: admin.firestore.FieldValue.arrayRemove(uid),
      interested: admin.firestore.FieldValue.arrayRemove(uid),
    });
  } else if (mode === "interested") {
    await eventDoc.ref.update({
      interested: admin.firestore.FieldValue.arrayUnion(uid),
    });
  } else {
    await eventDoc.ref.update({
      attendees: admin.firestore.FieldValue.arrayUnion(uid),
      interested: admin.firestore.FieldValue.arrayRemove(uid),
    });
    const chatId = evData.chatId || `event_${eventDoc.id}`;
    await db.collection("chats").doc(chatId).set({
      participants: admin.firestore.FieldValue.arrayUnion(uid),
      [`unreadCount.${uid}`]: 0,
    }, {merge: true});
  }

  return {
    success: true,
    mode,
    eventId: eventDoc.id,
    title: evData.title,
    location: evData.location,
    aiActions: [
      {
        id: `view_rsvp_event_${eventDoc.id}`,
        type: "navigate",
        label: `View "${evData.title}"`,
        route: `/events/${eventDoc.id}`,
        icon: "calendar",
      },
    ],
  };
}

async function executeHostingRequestTool(args = {}, userProfile = {}) {
  const uid = String(userProfile.uid || "").trim();
  if (!uid) return {error: "User authentication required."};
  const ctx = extractUserProfileContext(userProfile);

  const action = String(args.action || "create").toLowerCase(); // "create" | "list" | "cancel"
  if (action === "list") {
    const snap = await db.collection("hosting_requests")
        .where("status", "==", "open")
        .limit(10)
        .get();
    const requests = snap.docs.map((d) => ({
      id: d.id,
      userName: d.data().userName,
      location: d.data().location,
      reason: d.data().reason,
      durationDays: d.data().durationDays,
    }));
    return {
      count: requests.length,
      requests,
      aiAction: {
        id: `open_hosting_${Date.now()}`,
        type: "navigate",
        label: "Open Community Hosting",
        route: "/hosting",
        icon: "home",
      },
    };
  }

  if (action === "cancel") {
    const mySnap = await db.collection("hosting_requests")
        .where("userId", "==", uid)
        .where("status", "==", "open")
        .limit(5)
        .get();
    for (const d of mySnap.docs) {
      await d.ref.update({status: "cancelled"});
    }
    return {
      success: true,
      cancelledCount: mySnap.size,
      aiAction: {
        id: `open_hosting_cancel_${Date.now()}`,
        type: "navigate",
        label: "Open Community Hosting",
        route: "/hosting",
        icon: "home",
      },
    };
  }

  const location = String(args.location || ctx.homeCity || ctx.hostCity || "Dar es Salaam").trim();
  const reason = String(args.reason || `Visiting ${location} and looking for diaspora community hosting.`).trim();
  const durationDays = Math.min(Math.max(Number(args.durationDays) || 5, 1), 90);
  const startDate = args.startDate ? new Date(args.startDate) : new Date(Date.now() + 7 * 86400000);
  const validStart = isNaN(startDate.getTime()) ? new Date(Date.now() + 7 * 86400000) : startDate;

  const docRef = db.collection("hosting_requests").doc();
  await docRef.set({
    id: docRef.id,
    userId: uid,
    userName: ctx.fullName,
    userPhoto: userProfile.profileImage || userProfile.profilePhoto || null,
    homeCountry: ctx.homeCountry || "Global",
    homeCountryCode: ctx.homeCountryCode || "UN",
    reason,
    durationDays,
    startDate: admin.firestore.Timestamp.fromDate(validStart),
    location,
    visibility: "everyone",
    status: "open",
    interestedHostIds: [],
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  return {
    success: true,
    requestId: docRef.id,
    location,
    durationDays,
    aiAction: {
      id: `view_hosting_${docRef.id}`,
      type: "navigate",
      label: "View Hosting Requests",
      route: "/hosting",
      icon: "home",
    },
  };
}

function _extractLatLng(profileObj = {}) {
  const curr = profileObj?.currentLocation?.geometry?.location;
  if (curr && Number.isFinite(Number(curr.lat)) && Number.isFinite(Number(curr.lng))) {
    return {lat: Number(curr.lat), lng: Number(curr.lng)};
  }
  const host = profileObj?.hostLocation?.geometry?.location;
  if (host && Number.isFinite(Number(host.lat)) && Number.isFinite(Number(host.lng))) {
    return {lat: Number(host.lat), lng: Number(host.lng)};
  }
  return null;
}

function _haversineKm(a, b) {
  if (!a || !b) return null;
  const toRad = (deg) => (deg * Math.PI) / 180;
  const R = 6371;
  const dLat = toRad(b.lat - a.lat);
  const dLng = toRad(b.lng - a.lng);
  const sinLat = Math.sin(dLat / 2);
  const sinLng = Math.sin(dLng / 2);
  const h = sinLat * sinLat + Math.cos(toRad(a.lat)) * Math.cos(toRad(b.lat)) * sinLng * sinLng;
  return Math.round(R * 2 * Math.atan2(Math.sqrt(h), Math.sqrt(1 - h)) * 10) / 10;
}

async function executeSearchCompatriotsAndMembersTool(args = {}, userProfile = {}) {
  const uid = String(userProfile.uid || "").trim();
  const queryText = String(args.query || args.name || args.profession || "").trim().toLowerCase();
  const cityFilter = String(args.city || "").trim().toLowerCase();
  const countryFilter = String(args.homeCountry || "").trim().toLowerCase();
  const callerCoords = _extractLatLng(userProfile);

  const snap = await db.collection("users").limit(200).get();
  let members = snap.docs
      .map((d) => ({uid: d.id, ...d.data()}))
      .filter((u) => u.uid !== uid && u.uid !== DIASPORA_AI_AGENT_UID && !u.isAiAgent && u.isDiscoverable !== false && !u.isBanned);

  if (countryFilter) {
    const byCountry = members.filter((u) =>
      String(u.homeCountry || u.homeLocation?.country || "").toLowerCase().includes(countryFilter),
    );
    if (byCountry.length > 0) members = byCountry;
  }
  if (cityFilter) {
    const byCity = members.filter((u) => {
      const visibleCurrentCity = u.showCurrentLocationName !== false ?
        (u.currentCity || u.currentLocation?.city || "") :
        "";
      return String(u.hostCity || visibleCurrentCity || u.homeCity || u.hostLocation?.city || "")
          .toLowerCase()
          .includes(cityFilter);
    });
    if (byCity.length > 0) members = byCity;
  }
  if (queryText) {
    const byQuery = members.filter((u) => {
      const hay = [
        u.fullName,
        u.firstName,
        u.lastName,
        u.occupation,
        u.bio,
        ...(Array.isArray(u.profession) ? u.profession : []),
        ...(Array.isArray(u.industry) ? u.industry : []),
        ...(Array.isArray(u.servicesOffered) ? u.servicesOffered : []),
        ...(Array.isArray(u.interests) ? u.interests : []),
      ].filter(Boolean).join(" ").toLowerCase();
      return hay.includes(queryText);
    });
    if (byQuery.length > 0) members = byQuery;
  }

  const enriched = members.map((u) => {
    const memberCoords = u.showCurrentLocationName !== false ? _extractLatLng(u) : null;
    const distanceKm = (callerCoords && memberCoords) ? _haversineKm(callerCoords, memberCoords) : null;
    const visibleCity = u.showCurrentLocationName !== false ?
      (u.currentCity || u.currentLocation?.city || u.hostCity || u.hostLocation?.city || "") :
      (u.hostCity || u.hostLocation?.city || "");
    return {
      uid: u.uid,
      fullName: u.fullName || `${u.firstName || ""} ${u.lastName || ""}`.trim() || "Diaspora Member",
      occupation: u.occupation || (Array.isArray(u.profession) ? u.profession[0] : "") || "",
      homeCountry: u.homeCountry || u.homeLocation?.country || "",
      currentCity: visibleCity,
      ...(distanceKm !== null ? {distanceKm} : {}),
    };
  });

  if (callerCoords) {
    enriched.sort((a, b) => {
      const da = typeof a.distanceKm === "number" ? a.distanceKm : Number.POSITIVE_INFINITY;
      const dbDist = typeof b.distanceKm === "number" ? b.distanceKm : Number.POSITIVE_INFINITY;
      return da - dbDist;
    });
  }

  const top = enriched.slice(0, 6);

  const actions = [];
  if (top.length > 0) {
    actions.push({
      id: `profile_${top[0].uid}`,
      type: "navigate",
      label: `View ${top[0].fullName}`,
      route: `/profile/${top[0].uid}`,
      icon: "users",
    });
    actions.push({
      id: `chat_${top[0].uid}`,
      type: "navigate",
      label: `Message ${top[0].fullName}`,
      route: `/chat/direct/${top[0].uid}`,
      icon: "users",
    });
  }
  actions.push({
    id: `open_nearby_${Date.now()}`,
    type: "navigate",
    label: "Explore Nearby Compatriots",
    route: "/nearby",
    icon: "compass",
  });

  return {
    count: top.length,
    members: top,
    aiActions: actions,
  };
}

async function executeConnectOrMessageMemberTool(args = {}, userProfile = {}) {
  const uid = String(userProfile.uid || "").trim();
  if (!uid) return {error: "User authentication required."};
  const ctx = extractUserProfileContext(userProfile);

  const targetUserId = String(args.targetUserId || "").trim();
  const targetName = String(args.targetName || "").trim().toLowerCase();
  const messageText = String(args.messageText || "").trim();
  const relationshipType = String(args.relationshipType || "").trim(); // e.g. "Friend", "Brother", "Sister", "Colleague"

  let targetUser = null;
  if (targetUserId && validId(targetUserId)) {
    const s = await db.collection("users").doc(targetUserId).get();
    if (s.exists) targetUser = {uid: s.id, ...s.data()};
  }
  if (!targetUser && targetName) {
    const s = await db.collection("users").limit(80).get();
    const found = s.docs.find((d) =>
      d.id !== uid &&
      String(d.data().fullName || `${d.data().firstName || ""} ${d.data().lastName || ""}`).toLowerCase().includes(targetName),
    );
    if (found) targetUser = {uid: found.id, ...found.data()};
  }
  if (!targetUser) {
    return {success: false, message: "Could not find a member matching that name."};
  }

  const otherId = targetUser.uid;
  const otherName = targetUser.fullName || `${targetUser.firstName || ""} ${targetUser.lastName || ""}`.trim() || "Member";

  if (relationshipType) {
    const reqRef = db.collection("relationship_requests").doc();
    await reqRef.set({
      id: reqRef.id,
      senderId: uid,
      senderName: ctx.fullName,
      senderImage: userProfile.profileImage || userProfile.profilePhoto || null,
      receiverId: otherId,
      receiverName: otherName,
      receiverImage: targetUser.profileImage || targetUser.profilePhoto || null,
      category: String(args.category || "Friends"),
      type: relationshipType,
      status: "pending",
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  }

  const sortedIds = [uid, otherId].sort();
  const directChatId = `${sortedIds[0]}_${sortedIds[1]}`;
  const chatRef = db.collection("chats").doc(directChatId);
  await chatRef.set({
    id: directChatId,
    name: otherName,
    type: "ChatType.direct",
    participants: sortedIds,
    visibleTo: sortedIds,
    participantDetails: {
      [uid]: {
        name: ctx.fullName,
        image: userProfile.profileImage || userProfile.profilePhoto || null,
      },
      [otherId]: {
        name: otherName,
        image: targetUser.profileImage || targetUser.profilePhoto || null,
      },
    },
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, {merge: true});

  if (messageText) {
    const msgRef = chatRef.collection("messages").doc();
    await msgRef.set({
      id: msgRef.id,
      chatId: directChatId,
      senderId: uid,
      senderName: ctx.fullName,
      senderImage: userProfile.profileImage || userProfile.profilePhoto || null,
      content: messageText,
      type: "text",
      timestamp: Date.now(),
      status: "sent",
    });
  }

  return {
    success: true,
    otherUserId: otherId,
    otherName,
    chatId: directChatId,
    sentMessage: Boolean(messageText),
    sentRelationshipRequest: Boolean(relationshipType),
    aiActions: [
      {
        id: `open_dm_${otherId}`,
        type: "navigate",
        label: `Open Chat with ${otherName}`,
        route: `/chat/direct/${otherId}?name=${encodeURIComponent(otherName)}`,
        icon: "users",
      },
      {
        id: `open_prof_${otherId}`,
        type: "navigate",
        label: `View ${otherName}'s Profile`,
        route: `/profile/${otherId}`,
        icon: "users",
      },
    ],
  };
}

async function executeJoinOrCreateGroupOrChamberTool(args = {}, userProfile = {}) {
  const uid = String(userProfile.uid || "").trim();
  if (!uid) return {error: "User authentication required."};
  const ctx = extractUserProfileContext(userProfile);

  const mode = String(args.mode || "join_chamber").toLowerCase(); // "join_chamber" | "create_group" | "join_community"
  if (mode === "create_group") {
    const groupName = String(args.name || `${ctx.homeCountry || "Diaspora"} Connect Group`).trim();
    const description = String(args.description || `Community group created by ${ctx.fullName}`).trim();
    const chatRef = db.collection("chats").doc();
    await chatRef.set({
      id: chatRef.id,
      name: groupName,
      description,
      type: "ChatType.group",
      participants: [uid],
      admins: [uid],
      creatorId: uid,
      visibleTo: [uid],
      visibility: args.isPrivate ? "private" : "public",
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      unreadCount: {[uid]: 0},
    });
    return {
      success: true,
      mode,
      chatId: chatRef.id,
      name: groupName,
      aiAction: {
        id: `open_group_${chatRef.id}`,
        type: "navigate",
        label: `Open "${groupName}"`,
        route: `/chat/group/${chatRef.id}?name=${encodeURIComponent(groupName)}`,
        icon: "users",
      },
    };
  }

  // Default: join/ensure bilateral Chamber of Commerce
  const homeCode = (ctx.homeCountryCode || "TZ").toUpperCase();
  const hostCode = (ctx.hostCountryCode || "US").toUpperCase();
  const chamberId = `chamber_${homeCode}_${hostCode}`;
  const chamberName = `${ctx.homeCountry || homeCode} in ${ctx.hostCountry || hostCode} Chamber of Commerce`;

  await db.collection("chambers").doc(chamberId).set({
    id: chamberId,
    name: chamberName,
    homeCountry: ctx.homeCountry || homeCode,
    homeCountryCode: homeCode,
    hostCountry: ctx.hostCountry || hostCode,
    hostCountryCode: hostCode,
    memberIds: admin.firestore.FieldValue.arrayUnion(uid),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, {merge: true});

  await db.collection("users").doc(uid).set({
    chamberIds: admin.firestore.FieldValue.arrayUnion(chamberId),
  }, {merge: true});

  return {
    success: true,
    chamberId,
    chamberName,
    aiAction: {
      id: `open_chamber_${Date.now()}`,
      type: "navigate",
      label: "Open Chambers & DDI Economy",
      route: "/economy",
      icon: "building",
    },
  };
}

const AI_PROFILE_MILESTONE_FIELDS = [
  {key: "bio", label: "Bio"},
  {key: "occupation", label: "Occupation"},
  {key: "yearsInHostCountry", label: "Years in Host Country"},
  {key: "industry", label: "Industry"},
  {key: "profession", label: "Profession"},
  {key: "languages", label: "Languages"},
  {key: "meetingPreferences", label: "Meeting Preferences"},
  {key: "availability", label: "Availability"},
  {key: "interests", label: "Interests"},
  {key: "servicesOffered", label: "Services Offered"},
  {key: "lookingFor", label: "Looking For"},
  {key: "education", label: "Education"},
];

function inspectProfileMilestones(userData = {}) {
  const completedFields = [];
  const missingFields = [];
  for (const field of AI_PROFILE_MILESTONE_FIELDS) {
    const val = userData ? userData[field.key] : undefined;
    let isFilled = false;
    if (Array.isArray(val)) {
      isFilled = val.length > 0;
    } else if (typeof val === "string") {
      isFilled = val.trim().length > 0;
    } else if (val != null) {
      isFilled = true;
    }
    if (isFilled) {
      completedFields.push(field.label);
    } else {
      missingFields.push(field.label);
    }
  }
  return {
    completedCount: completedFields.length,
    totalCount: AI_PROFILE_MILESTONE_FIELDS.length,
    completedFields,
    missingFields,
  };
}

function _normalizeStringListArg(val) {
  if (Array.isArray(val)) {
    return val.map((s) => String(s || "").trim()).filter(Boolean);
  }
  if (typeof val === "string" && val.trim().length > 0) {
    return val.split(/[,;/|]+/).map((s) => s.trim()).filter(Boolean);
  }
  return [];
}

function _normalizeEducationArg(val) {
  if (!val) return [];
  const items = Array.isArray(val) ? val : [val];
  const normalized = [];
  for (const item of items) {
    if (item && typeof item === "object" && !Array.isArray(item)) {
      const institution = String(item.institution || item.school || item.university || "").trim();
      const degree = String(item.degree || item.program || item.qualification || "Degree / Diploma").trim();
      const graduationYear = String(item.graduationYear || item.year || "Completed").trim();
      if (institution) {
        normalized.push({institution, degree, graduationYear});
      }
    } else if (typeof item === "string" && item.trim().length > 0) {
      const raw = item.trim();
      const yearMatch = raw.match(/\b(19\d{2}|20\d{2})\b/);
      const graduationYear = yearMatch ? yearMatch[1] : "Completed";
      const parts = raw.replace(/\(\s*(19\d{2}|20\d{2})\s*\)/, "").split(/\s*[-–—|@]\s*/).filter(Boolean);
      const institution = (parts[0] || raw).trim();
      const degree = (parts[1] || "Degree / Studies").trim();
      normalized.push({institution, degree, graduationYear});
    }
  }
  return normalized;
}

async function executeUpdateMyProfileTool(args = {}, userProfile = {}) {
  const uid = String(userProfile.uid || "").trim();
  if (!uid) return {error: "User authentication required."};

  const prevInspection = inspectProfileMilestones(userProfile);
  const updates = {};

  if (typeof args.bio === "string" && args.bio.trim()) {
    updates.bio = args.bio.trim().slice(0, 600);
  }
  if (typeof args.occupation === "string" && args.occupation.trim()) {
    updates.occupation = args.occupation.trim().slice(0, 120);
  }
  if (args.yearsInHostCountry != null && String(args.yearsInHostCountry).trim()) {
    updates.yearsInHostCountry = String(args.yearsInHostCountry).trim().slice(0, 60);
  }

  const listFieldKeys = [
    "industry",
    "profession",
    "languages",
    "meetingPreferences",
    "availability",
    "interests",
    "servicesOffered",
    "lookingFor",
  ];
  for (const key of listFieldKeys) {
    const arr = _normalizeStringListArg(args[key]);
    if (arr.length > 0) {
      updates[key] = arr;
    }
  }

  const eduList = _normalizeEducationArg(args.education);
  if (eduList.length > 0) {
    updates.education = eduList;
  }

  if (args.socialLinks && typeof args.socialLinks === "object") {
    const existingSocial = (userProfile.socialLinks && typeof userProfile.socialLinks === "object") ?
      userProfile.socialLinks :
      {};
    const nextSocial = {...existingSocial};
    for (const k of ["linkedin", "instagram", "twitter", "facebook"]) {
      if (typeof args.socialLinks[k] === "string" && args.socialLinks[k].trim()) {
        nextSocial[k] = args.socialLinks[k].trim();
      }
    }
    if (Object.keys(nextSocial).length > 0) {
      updates.socialLinks = nextSocial;
    }
  }

  if (Object.keys(updates).length === 0) {
    return {
      success: false,
      completedFields: prevInspection.completedCount,
      totalFields: prevInspection.totalCount,
      missingFields: prevInspection.missingFields,
      message:
        "Provide at least one profile field to update (any of the 12 milestone fields: bio, occupation, yearsInHostCountry, industry, profession, languages, meetingPreferences, availability, interests, servicesOffered, lookingFor, education).",
    };
  }

  const updatedFieldKeys = Object.keys(updates);
  updates.updatedAt = admin.firestore.FieldValue.serverTimestamp();
  await db.collection("users").doc(uid).set(updates, {merge: true});

  // Update in-memory userProfile so chained tool calls in the same turn see the latest values
  for (const k of updatedFieldKeys) {
    userProfile[k] = updates[k];
  }

  // If BACKEND_SIGNER_PRIVATE_KEY is mounted in this runtime, evaluate & mint synchronously;
  // otherwise onUserWrite (which always mounts BACKEND_SIGNER_PRIVATE_KEY) triggers immediately
  // in the background to mint $DIASPORA on-chain and post the conversion card!
  if (process.env.BACKEND_SIGNER_PRIVATE_KEY) {
    try {
      const {syncProfileMilestoneAndTrust} = require("./dsp");
      await syncProfileMilestoneAndTrust(uid);
    } catch (syncErr) {
      console.warn(`[AI Agent] syncProfileMilestoneAndTrust warning after profile update for ${uid}:`, syncErr.message);
    }
  }

  const nextInspection = inspectProfileMilestones(userProfile);
  const newlyCompletedCount = Math.max(0, nextInspection.completedCount - prevInspection.completedCount);
  const newlyAwardedDsp = newlyCompletedCount * 1000;
  const newlyConvertedDiaspora = Math.max(
      0,
      Math.min(10, nextInspection.completedCount) - Math.min(10, prevInspection.completedCount),
  ) * 1000;
  const fieldsLeftFor10k = Math.max(0, 10 - nextInspection.completedCount);

  return {
    success: true,
    updatedFields: updatedFieldKeys,
    completedFields: nextInspection.completedCount,
    totalFields: nextInspection.totalCount,
    completedFieldNames: nextInspection.completedFields,
    missingFieldNames: nextInspection.missingFields,
    newlyAwardedDsp,
    newlyConvertedDiaspora,
    remainingImmediateDiasporaFromProfile: fieldsLeftFor10k * 1000,
    qrExchangeUnlockReminder:
      "Remind the user that completing 10 in-person QR Exchanges unlocks all minted $DIASPORA in their smart wallet and earns another +10,000 $DIASPORA.",
    aiActions: [
      {
        id: `view_my_profile_${Date.now()}`,
        type: "navigate",
        label: `View My Profile (${nextInspection.completedCount}/12)`,
        route: "/profile",
        icon: "users",
      },
      {
        id: `open_qr_after_profile_${Date.now()}`,
        type: "navigate",
        label: "Open QR Exchange (Unlock $DIASPORA)",
        route: "/profile?showQr=true",
        icon: "check",
      },
      {
        id: `open_wallet_after_profile_${Date.now()}`,
        type: "navigate",
        label: "Open $DIASPORA Wallet",
        route: "/dsp/crypto",
        icon: "wallet",
      },
    ],
  };
}

async function executeClaimDailyCheckInAndPointsTool(args = {}, userProfile = {}) {
  const uid = String(userProfile.uid || "").trim();
  if (!uid) return {error: "User authentication required."};

  const now = new Date();
  const nowIso = now.toISOString();
  const nowTimestamp = admin.firestore.FieldValue.serverTimestamp();
  const pointsRef = db.collection("user_points").doc(uid);

  let alreadyCheckedInToday = false;
  let pointsAwarded = 0;
  let streak = 1;
  let totalPoints = 0;
  let availablePoints = 0;

  await db.runTransaction(async (transaction) => {
    const snap = await transaction.get(pointsRef);
    const data = snap.exists ? (snap.data() || {}) : {};
    const lastRaw = data.lastCheckInDate;
    let lastDate = null;
    if (lastRaw) {
      if (typeof lastRaw.toDate === "function") {
        lastDate = lastRaw.toDate();
      } else {
        const parsed = new Date(String(lastRaw));
        if (!Number.isNaN(parsed.getTime())) lastDate = parsed;
      }
    }

    const isSameDay = Boolean(
        lastDate &&
        lastDate.getUTCFullYear() === now.getUTCFullYear() &&
        lastDate.getUTCMonth() === now.getUTCMonth() &&
        lastDate.getUTCDate() === now.getUTCDate(),
    );

    if (isSameDay) {
      alreadyCheckedInToday = true;
      streak = data.currentStreak || 1;
      totalPoints = data.totalPoints || 0;
      availablePoints = data.availablePoints || 0;
      return;
    }

    const diffHours = lastDate ? (now.getTime() - lastDate.getTime()) / (1000 * 60 * 60) : Infinity;
    const isConsecutive = diffHours <= 48;
    streak = isConsecutive ? (data.currentStreak || 0) + 1 : 1;

    pointsAwarded = 10;
    if (streak === 10) pointsAwarded += 1000;
    if (streak === 100) pointsAwarded += 10000;

    totalPoints = (data.totalPoints || 0) + pointsAwarded;
    availablePoints = (data.availablePoints || 0) + pointsAwarded;

    transaction.set(pointsRef, {
      userId: uid,
      currentStreak: streak,
      longestStreak: Math.max(streak, data.longestStreak || 0),
      lastCheckInDate: nowIso,
      totalPoints,
      availablePoints,
      lastUpdated: nowTimestamp,
    }, {merge: true});

    const txRef = db.collection("points_transactions").doc();
    transaction.set(txRef, {
      userId: uid,
      type: "earn",
      action: "daily_check_in",
      points: pointsAwarded,
      streak,
      timestamp: nowTimestamp,
      metadata: {
        description: `Daily Check-In via Diaspora AI Agent (Day ${streak})`,
        streak,
      },
    });
  });

  return {
    success: true,
    alreadyCheckedInToday,
    pointsAwarded,
    totalPoints,
    availablePoints,
    currentStreak: streak,
    aiActions: [
      {
        id: `open_points_${Date.now()}`,
        type: "navigate",
        label: "View My DSP Points",
        route: "/dsp/points",
        icon: "sparkles",
      },
      {
        id: `open_wallet_${Date.now()}`,
        type: "navigate",
        label: "Open $DIASPORA Wallet",
        route: "/dsp/crypto",
        icon: "wallet",
      },
    ],
  };
}

async function loadComprehensiveUserAiContext(uid, existingUserProfile = null) {
  if (!uid || uid === DIASPORA_AI_AGENT_UID) {
    return {
      userProfile: existingUserProfile || {},
      dspPoints: 0,
      availablePoints: 0,
      pohConvertedDsp: 0,
      currentStreak: 0,
      trustScore: 0,
      trustLevel: "lowTrust",
      uniqueQrCount: 0,
      uniqueFamilyCount: 0,
      uniqueFriendCount: 0,
      uniqueVerificationCount: 0,
      hasLocationTransparency: false,
      cityVisibilityForfeited: false,
      hasEmergencyFund: false,
      walletAddress: null,
      pohTokensTarget: 0,
      pohTokensMintedOnChain: 0,
      pohTokensPending: 0,
      tokensUnlocked: false,
      profileInspection: inspectProfileMilestones(existingUserProfile || {}),
    };
  }

  const [userSnap, pointsSnap, trustSnap] = await Promise.all([
    existingUserProfile ? Promise.resolve(null) : db.collection("users").doc(uid).get(),
    db.collection("user_points").doc(uid).get(),
    db.collection("trust_data").doc(uid).get(),
  ]);

  const userProfile = existingUserProfile ?
    existingUserProfile :
    (userSnap && userSnap.exists ? (userSnap.data() || {}) : {});
  userProfile.uid = uid;

  const pointsData = pointsSnap.exists ? (pointsSnap.data() || {}) : {};
  const trustData = trustSnap.exists ? (trustSnap.data() || {}) : {};
  const milestones = Array.isArray(trustData.milestones) ? trustData.milestones : [];
  const profileInspection = inspectProfileMilestones(userProfile);

  const uniqueQrCount = Number(trustData.uniqueQrCount || 0);
  const uniqueFamilyCount = Number(trustData.uniqueFamilyCount || 0);
  const uniqueFriendCount = Number(trustData.uniqueFriendCount || 0);
  const uniqueVerificationCount = Number(trustData.uniqueVerificationCount || 0);
  const cityVisibilityForfeited = Boolean(userProfile.cityVisibilityForfeited || trustData.cityVisibilityForfeited);
  const hasLocationTransparency = !cityVisibilityForfeited && (
    milestones.includes("City") ||
    (Boolean(userProfile.currentLocation) && userProfile.showCurrentLocationName !== false)
  );
  const hasEmergencyFund = Boolean(trustData.hasEmergencyFund || milestones.includes("EmergencyFund"));
  const tokensUnlocked = Boolean(userProfile.pohTokensUnlocked || uniqueQrCount >= 10 || milestones.includes("QR"));
  const pohTokensTarget = Number(userProfile.pohTokensTarget || pointsData.pohConvertedDsp || 0);
  const pohTokensMintedOnChain = Number(userProfile.pohTokensMintedOnChain || 0);
  const pohTokensPending = Number(userProfile.pohTokensPending || Math.max(0, pohTokensTarget - pohTokensMintedOnChain));

  return {
    userProfile,
    dspPoints: Number(pointsData.totalPoints || 0),
    availablePoints: Number(pointsData.availablePoints || 0),
    pohConvertedDsp: Number(pointsData.pohConvertedDsp || pohTokensTarget || 0),
    currentStreak: Number(pointsData.currentStreak || 0),
    trustScore: Number(trustData.trustScore || pointsData.trustScore || 0),
    trustLevel: String(trustData.trustLevel || "lowTrust"),
    uniqueQrCount,
    uniqueFamilyCount,
    uniqueFriendCount,
    uniqueVerificationCount,
    hasLocationTransparency,
    cityVisibilityForfeited,
    hasEmergencyFund,
    walletAddress: userProfile.walletAddress || null,
    pohTokensTarget,
    pohTokensMintedOnChain,
    pohTokensPending,
    tokensUnlocked,
    referralCode: userProfile.referralCode || null,
    profileInspection,
  };
}

async function executeGetMyPohWalletAndAccountStatusTool(args = {}, userProfile = {}) {
  const uid = String(userProfile.uid || "").trim();
  if (!uid) return {error: "User authentication required."};

  const [richCtx, txSnap] = await Promise.all([
    loadComprehensiveUserAiContext(uid),
    db.collection("points_transactions")
        .where("userId", "==", uid)
        .limit(8)
        .get()
        .catch(() => ({docs: []})),
  ]);

  const recentTransactions = (txSnap.docs || []).map((d) => {
    const t = d.data() || {};
    return {
      action: t.action || t.type || "activity",
      points: t.points || 0,
      tokensMinted: t.tokensMinted || 0,
      description: t.metadata?.description || t.action || "",
    };
  });

  const qrRemainingToUnlock = Math.max(0, 10 - richCtx.uniqueQrCount);
  const profileRewardRemaining = Math.max(0, 10 - richCtx.profileInspection.completedCount) * 1000;

  return {
    walletAddress: richCtx.walletAddress || "Provisioning Smart Wallet",
    diasporaTokenSummary: {
      totalConvertedFromPoh: richCtx.pohTokensTarget,
      mintedOnChain: richCtx.pohTokensMintedOnChain,
      pendingOnChainMint: richCtx.pohTokensPending,
      maxPohGenesisPool: 70000,
      remainingPohGenesisPool: Math.max(0, 70000 - richCtx.pohTokensTarget),
      isWalletUnlockedForTransfers: richCtx.tokensUnlocked,
      qrExchangesCompleted: richCtx.uniqueQrCount,
      qrExchangesRequiredToUnlock: 10,
      qrExchangesRemainingToUnlock: qrRemainingToUnlock,
    },
    dspPointsSummary: {
      lifetimeTotalDsp: richCtx.dspPoints,
      availableUnconvertedDspForTde: richCtx.availablePoints,
      alreadyConvertedPohDsp: richCtx.pohConvertedDsp,
      currentCheckInStreakDays: richCtx.currentStreak,
      pctTrustScorePercent: richCtx.trustScore,
    },
    pohSevenPillars: {
      pillar1_locationTransparency: {
        active: richCtx.hasLocationTransparency,
        forfeited: richCtx.cityVisibilityForfeited,
        reward: "10,000 DSP -> 10,000 $DIASPORA immediately",
      },
      pillar2_twelveProfileFields: {
        completedCount: richCtx.profileInspection.completedCount,
        totalFields: 12,
        completedFields: richCtx.profileInspection.completedFields,
        missingFields: richCtx.profileInspection.missingFields,
        immediateDiasporaRemaining: profileRewardRemaining,
        rule: "1,000 DSP per field; first 10 fields (10,000 DSP) convert 1:1 immediately to 10,000 $DIASPORA; fields 11-12 (+2,000 DSP) convert at TDEs.",
      },
      pillar3_inPersonQrExchanges: {
        completed: richCtx.uniqueQrCount,
        target: 10,
        rule: "1,000 DSP -> 1,000 $DIASPORA per unique scan (up to 10,000 $DIASPORA) AND 10 QR scans unlock all minted $DIASPORA in wallet!",
      },
      pillar4_familyCircle: {completed: richCtx.uniqueFamilyCount, target: 10, maxDiaspora: 10000},
      pillar5_friendCircle: {completed: richCtx.uniqueFriendCount, target: 10, maxDiaspora: 10000},
      pillar6_peerProfileVerifications: {completed: richCtx.uniqueVerificationCount, target: 10, maxDiaspora: 10000},
      pillar7_ubuntuEmergencyFund: {completed: richCtx.hasEmergencyFund, maxDiaspora: 10000},
    },
    referralInviteLink: richCtx.referralCode ? `https://diasporanearby.com/invite?code=${richCtx.referralCode}` : null,
    recentTransactions,
    aiActions: [
      ...(richCtx.profileInspection.missingFields.length > 0 ? [{
        id: `fill_missing_fields_${Date.now()}`,
        type: "prompt",
        label: `Fill Missing Profile Fields (${richCtx.profileInspection.completedCount}/12)`,
        prompt: "Help me fill out my remaining missing profile fields right here in chat.",
        icon: "sparkles",
      }] : []),
      {
        id: `open_qr_status_${Date.now()}`,
        type: "navigate",
        label: `Open QR Exchange (${richCtx.uniqueQrCount}/10)`,
        route: "/profile?showQr=true",
        icon: "check",
      },
      {
        id: `open_wallet_status_${Date.now()}`,
        type: "navigate",
        label: "Open $DIASPORA Wallet",
        route: "/dsp/crypto",
        icon: "wallet",
      },
      {
        id: `open_poh_hub_${Date.now()}`,
        type: "navigate",
        label: "PoH & DSP Hub",
        route: "/dsp/points",
        icon: "compass",
      },
    ],
  };
}

async function executeQueryCommunitiesRadioAndAppDataTool(args = {}, userProfile = {}) {
  const uid = String(userProfile.uid || "").trim();
  const domain = String(args.domain || "all_summary").toLowerCase().trim();
  const keyword = String(args.keyword || "").toLowerCase().trim();
  const result = {domain};
  const aiActions = [];

  if (domain === "communities" || domain === "all_summary") {
    const joinedIds = Array.isArray(userProfile.communityMemberships) ? userProfile.communityMemberships : [];
    const commSnap = await db.collection("communities").limit(50).get().catch(() => ({docs: []}));
    let comms = commSnap.docs.map((d) => ({id: d.id, ...d.data()}));
    if (keyword) {
      const filtered = comms.filter((c) =>
        String(c.name || c.country || c.city || "").toLowerCase().includes(keyword),
      );
      if (filtered.length > 0) comms = filtered;
    }
    result.joinedCommunityIds = joinedIds;
    result.communities = comms.slice(0, 10).map((c) => ({
      id: c.id,
      name: c.name || c.id,
      type: c.type || "community",
      memberCount: c.memberCount || 0,
      isJoined: joinedIds.includes(c.id),
    }));
    aiActions.push(resolveFeatureNavigationAction("communities"));
  }

  if (domain === "chambers" || domain === "ddi_and_ubuntu" || domain === "all_summary") {
    const [orgSnap, loanSnap, claimSnap] = await Promise.all([
      db.collection("organizations").limit(20).get().catch(() => ({docs: []})),
      db.collection("ddi_loan_applications").limit(10).get().catch(() => ({docs: []})),
      db.collection("emergency_fund_claims").limit(10).get().catch(() => ({docs: []})),
    ]);
    result.chambersAndOrganizations = orgSnap.docs.slice(0, 8).map((d) => {
      const o = d.data() || {};
      return {id: d.id, name: o.name || d.id, type: o.type || "chamber", memberCount: o.memberCount || 0};
    });
    result.ddiLoanProposals = loanSnap.docs.slice(0, 6).map((d) => {
      const l = d.data() || {};
      return {
        id: d.id,
        projectTitle: l.projectTitle || "Project",
        amountRequested: l.amountRequested || 0,
        status: l.status || "open",
        yesVotes: l.yesVotes || 0,
      };
    });
    result.emergencyFundClaimsCount = claimSnap.docs.length;
    aiActions.push(resolveFeatureNavigationAction("economy"));
  }

  if (domain === "radio" || domain === "all_summary") {
    const radioSnap = await db.collection("radio_stations").limit(40).get().catch(() => ({docs: []}));
    let stations = radioSnap.docs.map((d) => ({id: d.id, ...d.data()}));
    if (keyword) {
      const filtered = stations.filter((s) =>
        String(s.name || s.country || s.genre || s.city || "").toLowerCase().includes(keyword),
      );
      if (filtered.length > 0) stations = filtered;
    }
    result.radioStations = stations.slice(0, 10).map((s) => ({
      id: s.id,
      name: s.name || s.title || "Homeland Radio",
      country: s.country || "",
      genre: s.genre || s.category || "Live Stream",
    }));
    aiActions.push(resolveFeatureNavigationAction("radio"));
  }

  if (uid && (domain === "my_bookings_and_rsvps" || domain === "all_summary")) {
    const [carBookSnap, stayBookSnap, eventRsvpSnap] = await Promise.all([
      db.collection("car_rental_bookings").where("renterId", "==", uid).limit(10).get().catch(() => ({docs: []})),
      db.collection("stay_bookings").where("guestId", "==", uid).limit(10).get().catch(() => ({docs: []})),
      db.collection("events").where("attendees", "array-contains", uid).limit(10).get().catch(() => ({docs: []})),
    ]);
    result.myCarBookings = carBookSnap.docs.map((d) => ({id: d.id, ...(d.data() || {})})).slice(0, 5);
    result.myStayBookings = stayBookSnap.docs.map((d) => ({id: d.id, ...(d.data() || {})})).slice(0, 5);
    result.myEventRsvps = eventRsvpSnap.docs.map((d) => {
      const ev = d.data() || {};
      return {id: d.id, title: ev.title || "Event", location: ev.location || "", startDate: ev.startDate || ""};
    });
  }

  if (uid && (domain === "my_relationships" || domain === "all_summary")) {
    const relSnap = await db.collection("users").doc(uid).collection("relationships").limit(30).get().catch(() => ({docs: []}));
    result.myCircleOfTrustRelationships = relSnap.docs.map((d) => {
      const r = d.data() || {};
      return {
        otherUserId: d.id,
        name: r.otherUserName || r.name || "Member",
        type: r.type || r.relationshipType || "Connection",
        status: r.status || "active",
      };
    });
  }

  result.aiActions = aiActions.slice(0, 3);
  return result;
}

async function executeUbuntuFundOrDdiActionTool(args = {}, userProfile = {}) {
  const uid = String(userProfile.uid || "").trim();
  if (!uid) return {error: "User authentication required."};
  const ctx = extractUserProfileContext(userProfile);

  const action = String(args.action || "join_emergency_fund").toLowerCase(); // "join_emergency_fund" | "submit_emergency_claim" | "apply_ddi_loan"
  if (action === "submit_emergency_claim") {
    const claimRef = db.collection("emergency_fund_claims").doc();
    await claimRef.set({
      id: claimRef.id,
      userId: uid,
      applicantName: ctx.fullName,
      claimType: String(args.claimType || "medical"),
      amountRequested: Number(args.amountRequested) || 500,
      currency: "USD",
      description: String(args.description || "Emergency assistance requested via Diaspora AI Agent"),
      status: "under_review",
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return {
      success: true,
      claimId: claimRef.id,
      aiAction: resolveFeatureNavigationAction("emergency_fund"),
    };
  }

  if (action === "apply_ddi_loan") {
    const loanRef = db.collection("ddi_loan_applications").doc();
    const projectTitle = String(args.projectTitle || `${ctx.fullName} Diaspora Project`).trim();
    const amount = Number(args.amountRequested) || 2500;
    await loanRef.set({
      id: loanRef.id,
      applicantId: uid,
      applicantName: ctx.fullName,
      projectTitle,
      amountRequested: amount,
      currency: "USD",
      category: String(args.category || "Business"),
      description: String(args.description || projectTitle),
      status: "open_for_voting",
      yesVotes: 0,
      noVotes: 0,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return {
      success: true,
      loanId: loanRef.id,
      projectTitle,
      amountRequested: amount,
      aiAction: resolveFeatureNavigationAction("economy"),
    };
  }

  await db.collection("emergency_fund_interest").doc(uid).set({
    uid,
    fullName: ctx.fullName,
    country: ctx.hostCountry || ctx.homeCountry || "Global",
    tier: String(args.tier || "standard"),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, {merge: true});

  return {
    success: true,
    enrolledInUbuntuFund: true,
    aiAction: resolveFeatureNavigationAction("emergency_fund"),
  };
}

async function executeSubmitFeedbackOrRequestTool(args = {}, userProfile = {}) {
  const uid = String(userProfile.uid || "").trim();
  const ctx = extractUserProfileContext(userProfile);
  const message = String(args.message || "").trim();
  const category = String(args.category || "general").trim();
  if (!message) return {success: false, message: "Please provide feedback details."};

  const ref = db.collection("feedback").doc();
  await ref.set({
    id: ref.id,
    userId: uid || null,
    userName: ctx.fullName,
    category,
    message,
    source: "diaspora_ai_agent",
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });
  return {
    success: true,
    feedbackId: ref.id,
  };
}

// ── Extract Rich User Profile Context (Nested & Top-Level Fields) ──
function extractUserProfileContext(userProfile = {}) {
  const homeLoc = (userProfile.homeLocation && typeof userProfile.homeLocation === "object") ?
    userProfile.homeLocation :
    {};
  const hostLoc = (userProfile.hostLocation && typeof userProfile.hostLocation === "object") ?
    userProfile.hostLocation :
    {};
  const currLoc = (userProfile.currentLocation && typeof userProfile.currentLocation === "object") ?
    userProfile.currentLocation :
    {};

  const firstName = String(userProfile.firstName || "").trim();
  const lastName = String(userProfile.lastName || "").trim();
  const fullName = String(
      userProfile.fullName ||
      `${firstName} ${lastName}`.trim() ||
      "Diaspora Member",
  ).trim();

  const homeCity = String(userProfile.homeCity || homeLoc.city || "").trim();
  const homeState = String(userProfile.homeState || homeLoc.state || "").trim();
  const homeCountry = String(userProfile.homeCountry || homeLoc.country || "").trim();
  const homeCountryCode = String(
      userProfile.homeCountryCode ||
      homeLoc.country_code ||
      homeLoc.countryCode ||
      "",
  ).trim();
  const homeAddress = String(
      homeLoc.formatted_address ||
      homeLoc.formattedAddress ||
      [homeCity, homeState, homeCountry].filter(Boolean).join(", ") ||
      "Not specified",
  ).trim();

  const hostCity = String(userProfile.hostCity || hostLoc.city || userProfile.currentCity || currLoc.city || "").trim();
  const hostState = String(userProfile.hostState || hostLoc.state || userProfile.currentState || currLoc.state || "").trim();
  const hostCountry = String(userProfile.hostCountry || hostLoc.country || "").trim();
  const hostCountryCode = String(
      userProfile.hostCountryCode ||
      hostLoc.country_code ||
      hostLoc.countryCode ||
      "",
  ).trim();
  const hostAddress = String(
      hostLoc.formatted_address ||
      hostLoc.formattedAddress ||
      [hostCity, hostState, hostCountry].filter(Boolean).join(", ") ||
      "Not specified",
  ).trim();

  const currentCity = String(userProfile.currentCity || currLoc.city || hostCity || "").trim();
  const currentState = String(userProfile.currentState || currLoc.state || hostState || "").trim();
  const currentCountryCode = String(
      userProfile.currentCountryCode ||
      currLoc.country_code ||
      currLoc.countryCode ||
      hostCountryCode ||
      "",
  ).trim();
  const currentAddress = String(
      currLoc.formatted_address ||
      currLoc.formattedAddress ||
      [currentCity, currentState, currentCountryCode].filter(Boolean).join(", ") ||
      hostAddress,
  ).trim();

  const occupation = String(userProfile.occupation || "").trim();
  const bio = String(userProfile.bio || "").trim();
  const yearsInHostCountry = String(userProfile.yearsInHostCountry || "").trim();
  const profession = Array.isArray(userProfile.profession) ? userProfile.profession.filter(Boolean).join(", ") : "";
  const industry = Array.isArray(userProfile.industry) ? userProfile.industry.filter(Boolean).join(", ") : "";
  const languages = Array.isArray(userProfile.languages) ? userProfile.languages.filter(Boolean).join(", ") : "";
  const interests = Array.isArray(userProfile.interests) ? userProfile.interests.filter(Boolean).join(", ") : "";
  const servicesOffered = Array.isArray(userProfile.servicesOffered) ? userProfile.servicesOffered.filter(Boolean).join(", ") : "";
  const lookingFor = Array.isArray(userProfile.lookingFor) ? userProfile.lookingFor.filter(Boolean).join(", ") : "";
  const pastLocations = Array.isArray(userProfile.pastLocations) ?
    userProfile.pastLocations
        .map((p) => {
          const loc = p?.location || {};
          const addr = loc.formatted_address || [loc.city, loc.state, loc.country].filter(Boolean).join(", ");
          return addr ? (p.until ? `${addr} (until ${p.until})` : addr) : "";
        })
        .filter(Boolean)
        .join("; ") :
    "";

  const meetingPreferences = Array.isArray(userProfile.meetingPreferences) ? userProfile.meetingPreferences.filter(Boolean).join(", ") : "";
  const availability = Array.isArray(userProfile.availability) ? userProfile.availability.filter(Boolean).join(", ") : "";
  const education = Array.isArray(userProfile.education) ?
    userProfile.education
        .map((e) => {
          if (typeof e === "string") return e;
          const inst = e?.institution || "";
          const deg = e?.degree || "";
          const yr = e?.graduationYear || "";
          return [inst, deg, yr ? `(${yr})` : ""].filter(Boolean).join(" ");
        })
        .filter(Boolean)
        .join("; ") :
    "";

  return {
    firstName,
    lastName,
    fullName,
    homeCity,
    homeState,
    homeCountry,
    homeCountryCode,
    homeAddress,
    hostCity,
    hostState,
    hostCountry,
    hostCountryCode,
    hostAddress,
    currentCity,
    currentState,
    currentCountryCode,
    currentAddress,
    occupation,
    bio,
    yearsInHostCountry,
    profession,
    industry,
    languages,
    meetingPreferences,
    availability,
    interests,
    servicesOffered,
    lookingFor,
    education,
    pastLocations,
  };
}

// ── System Knowledge Base for Diaspora AI Agent ──
function buildSystemInstruction(userProfile = {}, dspPoints = 0, richContext = null) {
  const ctx = extractUserProfileContext(userProfile);
  const inspection = richContext?.profileInspection || inspectProfileMilestones(userProfile);
  const availableDsp = Number((richContext && richContext.availablePoints != null) ? richContext.availablePoints : (dspPoints || 0));
  const totalDsp = Number((richContext && richContext.dspPoints != null) ? richContext.dspPoints : (dspPoints || 0));
  const pohTargetTokens = Number((richContext && richContext.pohTokensTarget != null) ? richContext.pohTokensTarget : (userProfile.pohTokensTarget || 0));
  const pohMintedTokens = Number((richContext && richContext.pohTokensMintedOnChain != null) ? richContext.pohTokensMintedOnChain : (userProfile.pohTokensMintedOnChain || 0));
  const qrCount = Number((richContext && richContext.uniqueQrCount != null) ? richContext.uniqueQrCount : 0);
  const familyCount = Number((richContext && richContext.uniqueFamilyCount != null) ? richContext.uniqueFamilyCount : 0);
  const friendCount = Number((richContext && richContext.uniqueFriendCount != null) ? richContext.uniqueFriendCount : 0);
  const verifCount = Number((richContext && richContext.uniqueVerificationCount != null) ? richContext.uniqueVerificationCount : 0);
  const trustScore = Number((richContext && richContext.trustScore != null) ? richContext.trustScore : 0);
  const tokensUnlocked = (richContext && richContext.tokensUnlocked != null)
    ? Boolean(richContext.tokensUnlocked)
    : Boolean(userProfile.pohTokensUnlocked || qrCount >= 10);
  const hasLocation = (richContext && richContext.hasLocationTransparency != null)
    ? Boolean(richContext.hasLocationTransparency)
    : Boolean(userProfile.currentLocation && userProfile.showCurrentLocationName !== false);
  const hasEmergencyFund = Boolean(richContext && richContext.hasEmergencyFund);

  return `You are **Diaspora AI Agent**, the official 24/7 multilingual AI Concierge built into the Diaspora Nearby super-app.
Founder & Origin Story: Diaspora Nearby was founded by Peter Swai, who lived across the diaspora for 25+ years (Tanzania -> San Francisco -> Santa Monica -> Iowa -> Washington DC -> Phoenix -> returning home to Tanzania) to unite the global diaspora with their homelands.

CURRENT USER PROFILE, WALLET & PROOF OF HUMANITY (PoH) LIVE CONTEXT:
- Full Name: ${ctx.fullName}${ctx.firstName ? ` (First Name: ${ctx.firstName})` : ""}
- Home Location (Homeland / Origin): ${ctx.homeAddress}${ctx.homeCity ? ` [City: ${ctx.homeCity}]` : ""}${ctx.homeCountry ? ` [Country: ${ctx.homeCountry} (${ctx.homeCountryCode})]` : ""}
- Host Location (Diaspora Residence): ${ctx.hostAddress}${ctx.hostCity ? ` [City: ${ctx.hostCity}]` : ""}${ctx.hostCountry ? ` [Country: ${ctx.hostCountry} (${ctx.hostCountryCode})]` : ""}
- Current Live Location: ${ctx.currentAddress} (Location Transparency Active: ${hasLocation ? "Yes" : "No"})
- Occupation / Bio: ${[ctx.occupation, ctx.profession, ctx.industry].filter(Boolean).join(" • ") || "Not specified"}${ctx.bio ? ` — "${ctx.bio}"` : ""}
- Years in Host Country: ${ctx.yearsInHostCountry || "Not specified"}
- Languages Spoken: ${ctx.languages || "Not specified"}
- Meeting Preferences & Availability: ${[ctx.meetingPreferences, ctx.availability].filter(Boolean).join(" | ") || "Not specified"}
- Interests & Services: ${[ctx.interests, ctx.servicesOffered, ctx.lookingFor].filter(Boolean).join(" | ") || "Not specified"}
- Education: ${ctx.education || "Not specified"}
${ctx.pastLocations ? `- Past Diaspora Locations: ${ctx.pastLocations}\n` : ""}- Smart Wallet Address: ${userProfile.walletAddress || "Auto-provisioning"}
- $DIASPORA Token Balance (PoH Converted): ${pohTargetTokens.toLocaleString()} $DIASPORA (${pohMintedTokens.toLocaleString()} minted on Base; Remaining in 70,000 PoH Genesis Pool: ${Math.max(0, 70000 - pohTargetTokens).toLocaleString()} $DIASPORA)
- $DIASPORA Wallet Unlock Status: ${tokensUnlocked ? "UNLOCKED (10+ QR Exchanges complete)" : `LOCKED until 10 In-Person QR Exchanges (${qrCount}/10 completed)`}
- DSP Points: ${availableDsp.toLocaleString()} Available DSP (for TDEs) • ${totalDsp.toLocaleString()} Lifetime DSP Earned • PCT Trust Score: ${trustScore}%
- 12 Profile Milestone Fields Progress: ${inspection.completedCount}/12 completed
  - Completed Fields (${inspection.completedFields.length}): ${inspection.completedFields.join(", ") || "None yet"}
  - Missing Fields (${inspection.missingFields.length}): ${inspection.missingFields.join(", ") || "All 12 completed!"}
- Other PoH Pillars: QR Exchanges ${qrCount}/10 • Family Circle ${familyCount}/10 • Friend Circle ${friendCount}/10 • Peer Verifications ${verifCount}/10 • Ubuntu Emergency Fund: ${hasEmergencyFund ? "Completed" : "Not yet"}

PROOF OF HUMANITY (PoH), 12 PROFILE FIELDS & QR EXCHANGE TOKENOMICS (AUTHORITATIVE):
1. **70,000 $DIASPORA Immediate 1:1 PoH Genesis Pool (7 Pillars, 10,000 $DIASPORA each)**:
   - Pillar 1 — **Location Transparency**: Keeping live city visibility enabled awards **10,000 DSP** immediately converted 1:1 into **10,000 $DIASPORA** (+10 PCT). Warning: turning off city visibility permanently burns/forfeits that 10,000 reward!
   - Pillar 2 — **12 Profile Milestone Fields**: The 12 fields are Bio, Occupation, Years in Host Country, Industry, Profession, Languages, Meeting Preferences, Availability, Interests, Services Offered, Looking For, and Education. Each field awards **1,000 DSP**. The **first 10 completed fields (10,000 DSP) immediately convert 1:1 into 10,000 $DIASPORA** (+10 PCT), and fields 11 and 12 award **+2,000 DSP** toward upcoming Token Distribution Events (TDEs) while completing 100% of the profile.
   - Pillar 3 — **10 In-Person QR Exchanges (CRITICAL UNLOCK GATE)**: Each unique in-person QR handshake with a diaspora member earns **1,000 DSP -> 1,000 $DIASPORA** immediately (up to **10,000 $DIASPORA**), **AND reaching 10 QR Exchanges unlocks all minted $DIASPORA tokens** in the user's smart wallet for peer-to-peer transfers and TDE macro conversions! Always emphasize QR Exchange so users unlock their tokens.
   - Pillars 4, 5, 6 — **Family Circle (10)**, **Friend Circle (10)**, **Peer Profile Verifications (10)**: Each earns **1,000 DSP -> 1,000 $DIASPORA** per verified connection/verification (up to **10,000 $DIASPORA** per pillar).
   - Pillar 7 — **Ubuntu Emergency Fund**: Active paid contribution awards **10,000 DSP -> 10,000 $DIASPORA** immediately (+10 PCT).
2. **Proactive Conversational Profile Filling (All 12 Fields)**:
   - Whenever the user asks to fill out their profile, earn $DIASPORA, or responds with personal details, check their **Missing Fields** above!
   - Guide them warmly and concisely (ask 2-4 missing fields at a time, OR extract as many fields as they share in a single message or voice note) and immediately call \`update_my_profile\` to save their answers! Every newly filled field (up to 10) immediately converts 1,000 DSP into 1,000 $DIASPORA in their wallet.

PERSONALIZED CONTEXT RULES:
- When the user asks about their home location, hometown, home country, host location, host city, current location, occupation, PoH progress, missing profile fields, QR count, or $DIASPORA / DSP balance, answer directly and accurately using the LIVE CONTEXT above (or call \`get_my_poh_wallet_and_account_status\` / \`query_communities_radio_and_app_data\` when deeper live database records are needed).
- When searching flights, if the user says "flights home" or doesn't specify origin/destination, default origin to their Host Location (${ctx.hostCity || ctx.hostCountry || "DFW"}) and destination to their Home Location (${ctx.homeCity || ctx.homeCountry || "DAR"}), or vice versa.
- When searching hotels, car rentals, jobs, or real estate without a city specified, use their Home City (${ctx.homeCity || "Dar es Salaam"}) or Host City (${ctx.hostCity || "their city"}) contextually.

MULTILINGUAL & FORMATTING RULES (CRITICAL):
- Always reply in the EXACT language the user speaks or writes in (English, Kiswahili, French, Arabic, Spanish, Portuguese, Chinese, Hindi, Yoruba, Igbo, Hausa, Amharic, Somali, Zulu, etc.).
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
- You are an autonomous full-featured concierge capable of accessing ANY platform/account information and completing EVERY task a user asks for in Diaspora Nearby.
- You have tools to:
  1. **Inspect Account, Wallet, PoH & Live Platform Data**: Check live $DIASPORA/DSP balances, wallet unlock status, 12-field completion, transactions, and referral link (\`get_my_poh_wallet_and_account_status\`), and query communities, Chambers of Commerce, live homeland radio stations, DDI loans, Ubuntu claims, bookings, RSVPs, and relationships (\`query_communities_radio_and_app_data\`).
  2. **Search**: Live flights, hotels, car rentals, stays, jobs, marketplace products/services, real estate (plots, farms, houses), events, and nearby diaspora compatriots/members.
  3. **Create & Publish Live**: Immediately publish jobs (\`prepare_post_job\`), car rentals (\`prepare_post_car_rental\`), stays/hotels (\`prepare_post_stay_or_hotel\`), marketplace products/services (\`prepare_post_marketplace\`), real estate properties (\`prepare_post_real_estate\`), and events (\`prepare_post_event\`).
  4. **Manage Listings & Bookmarks**: List, update price/salary/title/description, pause, activate, mark sold, or delete any of the user's listings (\`manage_my_listings\`), and save/unsave any listing (\`save_or_unsave_listing\`).
  5. **Book & RSVP**: Book a car rental or stay (\`book_car_or_stay\`), RSVP or mark interested in an event (\`rsvp_or_interest_event\`), and create/list/cancel community hosting requests (\`create_or_manage_hosting_request\`).
  6. **Connect & Community**: Search compatriots (\`search_compatriots_and_members\`), start a direct chat or send a friend/family relationship request (\`connect_or_message_member\`), and join the user's bilateral Chamber of Commerce or create a group chat (\`join_or_create_group_or_chamber\`).
  7. **Complete All 12 Profile Fields, Check-In, Ubuntu Fund & DDI**: Update any or all of the user's 12 profile milestone fields (\`update_my_profile\`), claim daily DSP check-in (\`claim_daily_checkin_and_points\`), join or claim from the Ubuntu Emergency Fund or apply for a DDI project loan (\`ubuntu_fund_or_ddi_action\`), open any screen including QR Exchange (\`navigate_app_feature\`), and submit feedback (\`submit_feedback_or_request\`).
- IMPORTANT FOR POSTING/CREATING:
  - When a user wants to post a job, car rental, stay/hotel, marketplace item, real estate property, or event:
    1. If they haven't provided at least a title/item name yet, ask them warmly and concisely for the essential details.
    2. Once they provide the key details (even if only a title, city, or price/salary are given—fill sensible defaults for minor fields), call the corresponding \`prepare_post_*\` tool! When called for an authenticated user, it publishes the listing live in Firestore and attaches direct **View "<Title>"** and **Browse** buttons to your reply.`;
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
        description: "Publish a job listing live on Diaspora Nearby once the user provides at least a job title, and attach View & Browse buttons.",
        parameters: {
          type: "OBJECT",
          properties: {
            title: {type: "STRING", description: "Job title (e.g. Senior Accountant, Blockchain Developer, Driver, Software Engineer)"},
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
        description: "Publish a car rental listing live on Diaspora Nearby once the user provides the vehicle make/model and daily rate.",
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
        description: "Publish a stay/apartment or hotel listing live on Diaspora Nearby.",
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
        description: "Publish a product or service marketplace listing live on Diaspora Nearby.",
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
        description: "Publish a real estate listing (plot, farm, or house) live on Diaspora Nearby.",
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
        description: "Publish a community event listing live on Diaspora Nearby.",
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
        name: "manage_my_listings",
        description: "List, update (title, price, salary, description), pause, activate, mark sold, or delete the user's own listings across jobs, marketplace, car rentals, stays, real estate, and events.",
        parameters: {
          type: "OBJECT",
          properties: {
            action: {type: "STRING", description: "'list', 'update', 'pause', 'activate', 'mark_sold', or 'delete'"},
            listingId: {type: "STRING", description: "Optional listing ID"},
            titleKeyword: {type: "STRING", description: "Keyword matching the listing title to manage"},
            newTitle: {type: "STRING", description: "New title when action is 'update'"},
            newDescription: {type: "STRING", description: "New description when action is 'update'"},
            newPrice: {type: "NUMBER", description: "New price when action is 'update'"},
            newSalaryRange: {type: "STRING", description: "New salary range when updating a job"},
          },
          required: ["action"],
        },
      },
      {
        name: "save_or_unsave_listing",
        description: "Save (bookmark) or unsave a marketplace or job listing for the user.",
        parameters: {
          type: "OBJECT",
          properties: {
            listingId: {type: "STRING", description: "Listing ID if known"},
            keyword: {type: "STRING", description: "Listing title keyword to match"},
            unsave: {type: "BOOLEAN", description: "True to remove from saved, false to save"},
          },
        },
      },
      {
        name: "book_car_or_stay",
        description: "Book a peer car rental, stay, or hotel for specified dates.",
        parameters: {
          type: "OBJECT",
          properties: {
            listingId: {type: "STRING", description: "Optional peer listing ID"},
            keyword: {type: "STRING", description: "Vehicle or property keyword or city"},
            startDate: {type: "STRING", description: "Start date YYYY-MM-DD"},
            days: {type: "INTEGER", description: "Number of days or nights"},
            guests: {type: "INTEGER", description: "Number of guests"},
            notes: {type: "STRING", description: "Booking notes"},
          },
        },
      },
      {
        name: "rsvp_or_interest_event",
        description: "RSVP as attending, mark interested, or cancel attendance for a community event.",
        parameters: {
          type: "OBJECT",
          properties: {
            eventId: {type: "STRING", description: "Optional event ID"},
            keyword: {type: "STRING", description: "Event title or city keyword"},
            mode: {type: "STRING", description: "'rsvp', 'interested', or 'cancel'"},
          },
        },
      },
      {
        name: "create_or_manage_hosting_request",
        description: "Create a community hosting request when traveling, list open hosting requests, or cancel the user's open hosting request.",
        parameters: {
          type: "OBJECT",
          properties: {
            action: {type: "STRING", description: "'create', 'list', or 'cancel'"},
            location: {type: "STRING", description: "Destination city/country for hosting"},
            reason: {type: "STRING", description: "Reason for visit / hosting request"},
            durationDays: {type: "INTEGER", description: "Number of days"},
            startDate: {type: "STRING", description: "Start date YYYY-MM-DD"},
          },
          required: ["action"],
        },
      },
      {
        name: "search_compatriots_and_members",
        description: "Search diaspora compatriots and members by name, profession, skill, home country, or city.",
        parameters: {
          type: "OBJECT",
          properties: {
            query: {type: "STRING", description: "Name, profession, skill, or service keyword"},
            city: {type: "STRING", description: "Optional city filter"},
            homeCountry: {type: "STRING", description: "Optional home country filter"},
          },
        },
      },
      {
        name: "connect_or_message_member",
        description: "Start a direct chat with a member, send them a message, or send a Friend/Family/Community relationship request.",
        parameters: {
          type: "OBJECT",
          properties: {
            targetUserId: {type: "STRING", description: "Optional target user UID"},
            targetName: {type: "STRING", description: "Name of the member to connect with or message"},
            messageText: {type: "STRING", description: "Optional message text to send"},
            relationshipType: {type: "STRING", description: "Optional relationship type (e.g. Friend, Brother, Sister, Cousin, Colleague)"},
            category: {type: "STRING", description: "'Friends', 'Family', or 'Community'"},
          },
        },
      },
      {
        name: "join_or_create_group_or_chamber",
        description: "Join the user's bilateral Diaspora Chamber of Commerce or create a new community group chat.",
        parameters: {
          type: "OBJECT",
          properties: {
            mode: {type: "STRING", description: "'join_chamber' or 'create_group'"},
            name: {type: "STRING", description: "Group name when creating a group"},
            description: {type: "STRING", description: "Group description"},
            isPrivate: {type: "BOOLEAN", description: "Whether the group is private"},
          },
          required: ["mode"],
        },
      },
      {
        name: "update_my_profile",
        description: "Update any or all of the user's 12 Proof of Humanity profile milestone fields (bio, occupation, yearsInHostCountry, industry, profession, languages, meetingPreferences, availability, interests, servicesOffered, lookingFor, education) and optional socialLinks. Each newly completed field (up to 10) earns 1,000 DSP immediately converted 1:1 into 1,000 $DIASPORA tokens!",
        parameters: {
          type: "OBJECT",
          properties: {
            bio: {type: "STRING", description: "Updated short bio or personal introduction"},
            occupation: {type: "STRING", description: "Current job title or occupation"},
            yearsInHostCountry: {type: "STRING", description: "Years living in host country (e.g. '5 years', '10+ years', 'Born here')"},
            industry: {type: "ARRAY", items: {type: "STRING"}, description: "Industries (e.g. ['Technology', 'Healthcare', 'Finance'])"},
            profession: {type: "ARRAY", items: {type: "STRING"}, description: "Professions or specialties (e.g. ['Software Engineer', 'Entrepreneur'])"},
            languages: {type: "ARRAY", items: {type: "STRING"}, description: "Languages spoken (e.g. ['English', 'Kiswahili'])"},
            meetingPreferences: {type: "ARRAY", items: {type: "STRING"}, description: "Preferred ways to meet (e.g. ['Coffee', 'Networking Events', 'Video Call', 'In-Person'])"},
            availability: {type: "ARRAY", items: {type: "STRING"}, description: "When or what the user is available for (e.g. ['Weekends', 'Evenings', 'Mentorship', 'Business Collaboration'])"},
            interests: {type: "ARRAY", items: {type: "STRING"}, description: "Personal or community interests"},
            servicesOffered: {type: "ARRAY", items: {type: "STRING"}, description: "Skills or services the user offers to the community"},
            lookingFor: {type: "ARRAY", items: {type: "STRING"}, description: "Opportunities or connections the user is looking for"},
            education: {
              type: "ARRAY",
              description: "Education history entries (institution, degree, graduationYear)",
              items: {
                type: "OBJECT",
                properties: {
                  institution: {type: "STRING", description: "University, college, or school name"},
                  degree: {type: "STRING", description: "Degree, major, or qualification"},
                  graduationYear: {type: "STRING", description: "Graduation year (e.g. '2018' or 'Completed')"},
                },
              },
            },
            socialLinks: {
              type: "OBJECT",
              description: "Optional social profile links",
              properties: {
                linkedin: {type: "STRING"},
                instagram: {type: "STRING"},
                twitter: {type: "STRING"},
                facebook: {type: "STRING"},
              },
            },
          },
        },
      },
      {
        name: "get_my_poh_wallet_and_account_status",
        description: "Get the user's live Proof of Humanity (PoH) 7-pillar progress, $DIASPORA wallet balance, QR Exchange unlock status (X/10), DSP points, exact completed/missing profile fields out of 12, referral link, and recent reward transactions.",
        parameters: {
          type: "OBJECT",
          properties: {},
        },
      },
      {
        name: "query_communities_radio_and_app_data",
        description: "Query live platform and user information across communities, Chambers of Commerce, live homeland radio stations, DDI loan proposals, Ubuntu Emergency Fund claims, the user's active car/stay bookings and event RSVPs, or their Family/Friend Circle relationships.",
        parameters: {
          type: "OBJECT",
          properties: {
            domain: {
              type: "STRING",
              description: "One of: 'communities', 'chambers', 'radio', 'ddi_and_ubuntu', 'my_bookings_and_rsvps', 'my_relationships', or 'all_summary'",
            },
            keyword: {
              type: "STRING",
              description: "Optional filter keyword (country, city, station name, community name)",
            },
          },
        },
      },
      {
        name: "claim_daily_checkin_and_points",
        description: "Claim the user's daily DSP points check-in and view their updated points balance and streak.",
        parameters: {
          type: "OBJECT",
          properties: {},
        },
      },
      {
        name: "ubuntu_fund_or_ddi_action",
        description: "Enroll in the Ubuntu Emergency Fund, submit an emergency support claim, or submit a DDI community project loan application.",
        parameters: {
          type: "OBJECT",
          properties: {
            action: {type: "STRING", description: "'join_emergency_fund', 'submit_emergency_claim', or 'apply_ddi_loan'"},
            claimType: {type: "STRING", description: "'medical' or 'bereavement'"},
            projectTitle: {type: "STRING", description: "DDI loan project title"},
            amountRequested: {type: "NUMBER", description: "Amount in USD"},
            category: {type: "STRING", description: "Category for DDI loan"},
            description: {type: "STRING", description: "Reason or project description"},
          },
          required: ["action"],
        },
      },
      {
        name: "submit_feedback_or_request",
        description: "Submit user feedback, bug report, or feature request to the Diaspora Nearby team.",
        parameters: {
          type: "OBJECT",
          properties: {
            category: {type: "STRING", description: "'bug', 'feature_request', or 'general'"},
            message: {type: "STRING", description: "Feedback or request message"},
          },
          required: ["message"],
        },
      },
      {
        name: "navigate_app_feature",
        description: "Attach a quick navigation button to open a specific screen in Diaspora Nearby (including QR Exchange or Edit Profile).",
        parameters: {
          type: "OBJECT",
          properties: {
            feature: {
              type: "STRING",
              description: "One of: 'qr_exchange', 'edit_profile', 'profile', 'nearby', 'radio', 'emergency_fund', 'remittances', 'crypto', 'points', 'economy', 'communities', 'flights', 'hotels', 'car_rental', 'jobs', 'marketplace', 'real_estate', 'events', 'hosting', 'saved', 'my_listings'",
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
    qr_exchange: {label: "Open QR Exchange (Unlock $DIASPORA)", route: "/profile?showQr=true", icon: "check"},
    edit_profile: {label: "Edit My 12 Profile Fields", route: "/profile?edit=true", icon: "users"},
    profile: {label: "Open My Profile", route: "/profile", icon: "users"},
    nearby: {label: "Open Nearby Discovery", route: "/nearby", icon: "compass"},
    radio: {label: "Listen to Live Homeland Radio", route: "/radio", icon: "radio"},
    emergency_fund: {label: "Open Ubuntu Emergency Fund", route: "/dsp/emergency-fund", icon: "shield"},
    remittances: {label: "Send Remittance", route: "/dsp/remittances", icon: "send"},
    crypto: {label: "Open $DIASPORA Wallet", route: "/dsp/crypto", icon: "wallet"},
    points: {label: "View My DSP Points & PoH", route: "/dsp/points", icon: "sparkles"},
    economy: {label: "Open Chambers & DDI Loans", route: "/economy", icon: "building"},
    communities: {label: "Browse Diaspora Communities", route: "/communities", icon: "users"},
    flights: {label: "Open Flight Search", route: "/dsp/travel/flights", icon: "flight"},
    hotels: {label: "Open Hotel Search", route: "/dsp/travel/hotels", icon: "hotel"},
    car_rental: {label: "Open Car Rentals", route: "/dsp/travel/car-rental", icon: "car"},
    jobs: {label: "Browse Jobs", route: "/marketplace?type=job", icon: "briefcase"},
    marketplace: {label: "Open Marketplace", route: "/marketplace", icon: "shopping"},
    real_estate: {label: "Open Real Estate Hub", route: "/dsp/real-estate", icon: "home"},
    events: {label: "Open Diaspora Events", route: "/events", icon: "calendar"},
    hosting: {label: "Open Community Hosting", route: "/hosting", icon: "home"},
    saved: {label: "Open Saved Listings", route: "/marketplace/saved", icon: "briefcase"},
    my_listings: {label: "Manage My Listings", route: "/marketplace/my-listings", icon: "briefcase"},
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
      return await prepareJobDraftTool(args, userProfile);
    case "prepare_post_car_rental":
      return await prepareCarRentalDraftTool(args, userProfile);
    case "prepare_post_stay_or_hotel":
      return await prepareStayOrHotelDraftTool(args, userProfile);
    case "prepare_post_marketplace":
      return await prepareMarketplaceDraftTool(args, userProfile);
    case "prepare_post_real_estate":
      return await prepareRealEstateDraftTool(args, userProfile);
    case "prepare_post_event":
      return await prepareEventDraftTool(args, userProfile);
    case "manage_my_listings":
      return await executeManageMyListingsTool(args, userProfile);
    case "save_or_unsave_listing":
      return await executeSaveOrUnsaveListingTool(args, userProfile);
    case "book_car_or_stay":
      return await executeBookCarOrStayTool(args, userProfile);
    case "rsvp_or_interest_event":
      return await executeRsvpOrInterestEventTool(args, userProfile);
    case "create_or_manage_hosting_request":
      return await executeHostingRequestTool(args, userProfile);
    case "search_compatriots_and_members":
      return await executeSearchCompatriotsAndMembersTool(args, userProfile);
    case "connect_or_message_member":
      return await executeConnectOrMessageMemberTool(args, userProfile);
    case "join_or_create_group_or_chamber":
      return await executeJoinOrCreateGroupOrChamberTool(args, userProfile);
    case "update_my_profile":
      return await executeUpdateMyProfileTool(args, userProfile);
    case "get_my_poh_wallet_and_account_status":
      return await executeGetMyPohWalletAndAccountStatusTool(args, userProfile);
    case "query_communities_radio_and_app_data":
      return await executeQueryCommunitiesRadioAndAppDataTool(args, userProfile);
    case "claim_daily_checkin_and_points":
      return await executeClaimDailyCheckInAndPointsTool(args, userProfile);
    case "ubuntu_fund_or_ddi_action":
      return await executeUbuntuFundOrDdiActionTool(args, userProfile);
    case "submit_feedback_or_request":
      return await executeSubmitFeedbackOrRequestTool(args, userProfile);
    case "navigate_app_feature":
      return {aiAction: resolveFeatureNavigationAction(args?.feature)};
    default:
      return {error: `Unknown tool ${name}`};
  }
}

// ── Emoji Sanitizer (Guarantees Zero Emojis in AI Replies) ──
function stripEmojis(text = "") {
  return String(text || "")
      .replace(/[\u{1F300}-\u{1FAFF}\u{2600}-\u{27BF}]|\u{FE0F}/gu, "")
      .replace(/ {2,}/g, " ")
      .trim();
}

async function detectStructuredDraftFromUserText(userText = "", userProfile = {}) {
  const text = String(userText || "").trim();
  const lower = text.toLowerCase();
  if (!text) return null;

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
    const res = await prepareCarRentalDraftTool({
      make,
      model,
      year,
      pricePerDay,
      city: userProfile.hostCity || userProfile.homeCity || "Dar es Salaam",
      description: text,
      draftOnly: true,
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
    const res = await prepareJobDraftTool({
      title,
      companyName,
      city,
      salaryRange,
      description: text,
      draftOnly: true,
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
  const ctx = extractUserProfileContext(userProfile);
  const lower = String(userText || "").toLowerCase();
  const isSw = isKiswahiliText(userText);
  const actions = [];

  if (
    lower.includes("where am i from") ||
    lower.includes("my home") ||
    lower.includes("my host") ||
    lower.includes("where do i live") ||
    lower.includes("who am i") ||
    lower.includes("my location") ||
    lower.includes("natoka wapi") ||
    lower.includes("naishi wapi")
  ) {
    return {
      text: isSw ?
        `Jina lako ni **${ctx.fullName}**. Nyumbani kwako (Home Location) ni **${ctx.homeAddress}**, na makazi yako ya sasa (Host Location) ni **${ctx.hostAddress}**.` :
        `You are **${ctx.fullName}**. Your home location is **${ctx.homeAddress}**, and your host location is **${ctx.hostAddress}**.`,
      aiActions: [resolveFeatureNavigationAction("nearby")],
    };
  }

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
      origin: ctx.hostCity || ctx.hostCountry || "DFW",
      destination: ctx.homeCity || ctx.homeCountry || "DAR",
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
    const city = ctx.homeCity || ctx.hostCity || "Dar es Salaam";
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

  if (
    lower.includes("poh") ||
    lower.includes("proof of humanity") ||
    lower.includes("12 profile") ||
    lower.includes("12 fields") ||
    lower.includes("profile fields") ||
    lower.includes("fill out my") ||
    lower.includes("missing profile") ||
    lower.includes("qr exchange") ||
    lower.includes("unlock") ||
    lower.includes("diaspora") ||
    lower.includes("dsp")
  ) {
    const inspection = inspectProfileMilestones(userProfile);
    const missingList = inspection.missingFields.length > 0 ?
      inspection.missingFields.join(", ") :
      "None — all 12 fields completed!";
    const immediateLeft = Math.max(0, 10 - inspection.completedCount) * 1000;
    return {
      text: isSw ?
        `Kupitia **Proof of Humanity (PoH)** unaweza kupata hadi **70,000 $DIASPORA** kwa ubadilishaji wa papo hapo wa 1:1 kutoka DSP:\n\n• **Sehemu 12 za Wasifu (${inspection.completedCount}/12 zimejazwa)**: Kila sehemu inakupa **1,000 DSP**, na sehemu 10 za kwanza (**10,000 DSP**) hubadilishwa papo hapo kuwa **10,000 $DIASPORA** kwenye pochi yako (${immediateLeft.toLocaleString()} $DIASPORA bado inapatikana papo hapo). Sehemu zilizobaki: **${missingList}**. Nijibu hapa hapa kwenye chat ukitaja kazi yako, lugha, elimu, au maelezo yako nami nitakujazia mara moja!\n• **QR EXCHANGE Kufungua Tokeni Zako**: Hakikisha unafanya **QR Exchanges 10 za ana kwa ana** na wanadiaspora wenzako ili kupata **+10,000 $DIASPORA** zaidi na **kufungua (unlock) tokeni zako zote za $DIASPORA** kwenye pochi yako!` :
        `With **Proof of Humanity (PoH)**, you can earn up to **70,000 $DIASPORA** converted immediately 1:1 from DSP:\n\n• **12 Profile Fields (${inspection.completedCount}/12 completed)**: Each field earns **1,000 DSP**, and your first **10,000 DSP is immediately converted 1:1 into 10,000 $DIASPORA tokens** (${immediateLeft.toLocaleString()} $DIASPORA still available immediately). Missing fields: **${missingList}**. Reply right here with your bio, occupation, years in host country, industry, profession, languages, meeting preferences, availability, interests, services, what you are looking for, or education — and I will update them for you right now!\n• **QR EXCHANGE to Unlock Your Tokens**: Complete **10 in-person QR Exchanges** with fellow diaspora members to earn another **+10,000 $DIASPORA** AND **unlock all your minted $DIASPORA tokens** in your smart wallet!`,
      aiActions: [
        resolveFeatureNavigationAction("qr_exchange"),
        resolveFeatureNavigationAction("edit_profile"),
        resolveFeatureNavigationAction("crypto"),
      ],
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
      `Karibu! Nipo hapa saa 24 kukuhudumia kwa Kiswahili au lugha yoyote unayopenda.\n\nUnaweza kuniomba:\n• **Kukujazia Sehemu 12 za Wasifu wako** ili upate **10,000 DSP -> 10,000 $DIASPORA** papo hapo (na kufanya **QR Exchange 10** kufungua tokeni zako)\n• **Kutafuta ndege, hoteli, au kukodisha gari**\n• **Kutafuta au kupost kazi, bidhaa, au nyumba/viwanja**\n• **Kufungua huduma yoyote** (Nearby Discovery, Live Radio, Ubuntu Emergency Fund, DDI Loans, au QR Exchange).` :
      `I am here 24/7 in any language you prefer.\n\nYou can ask me to:\n• **Help fill out your 12 profile fields right in chat** to earn **10,000 DSP -> 10,000 $DIASPORA** immediately (and open **QR Exchange** to complete your 10 scans and unlock your tokens)\n• **Search flights, hotels, stays, or car rentals**\n• **Find or publish jobs, marketplace listings, events, or real estate**\n• **Access any information or feature** (Nearby Discovery, Communities, Chambers, Live Radio, Ubuntu Emergency Fund, or DDI Loans).`,
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

// ── Multimodal MIME Type Helpers ──
function inferAudioMimeType(urlOrHint, headerContentType) {
  const header = String(headerContentType || "").split(";")[0].trim().toLowerCase();
  if (header.startsWith("audio/")) return header;
  const clean = String(urlOrHint || "").split("?")[0].toLowerCase();
  if (clean.endsWith(".mp3")) return "audio/mpeg";
  if (clean.endsWith(".wav")) return "audio/wav";
  if (clean.endsWith(".aac")) return "audio/aac";
  if (clean.endsWith(".ogg") || clean.endsWith(".opus")) return "audio/ogg";
  if (clean.endsWith(".webm")) return "audio/webm";
  return "audio/mp4";
}

function inferImageMimeType(urlOrHint, headerContentType) {
  const header = String(headerContentType || "").split(";")[0].trim().toLowerCase();
  if (header.startsWith("image/") && header !== "image/svg+xml") return header;
  const clean = String(urlOrHint || "").split("?")[0].toLowerCase();
  if (clean.endsWith(".png")) return "image/png";
  if (clean.endsWith(".webp")) return "image/webp";
  if (clean.endsWith(".gif")) return "image/gif";
  if (clean.endsWith(".heic") || clean.endsWith(".heif")) return "image/heic";
  return "image/jpeg";
}

// ── Main Conversational Orchestrator ──
async function generateAiAgentResponse({
  userText,
  audioMediaUrl = null,
  audioBase64 = null,
  audioMimeType = "audio/mp4",
  imageMediaUrl = null,
  isVoiceMode = false,
  historyMessages = [],
  userProfile = {},
  dspPoints = 0,
  richContext = null,
}) {
  await ensureAiConfigEnv();
  const geminiKey = process.env.GEMINI_API_KEY;
  const nvidiaKey = process.env.NVIDIA_API_KEY;
  const baseInstruction = buildSystemInstruction(userProfile, dspPoints, richContext);
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
        const detectedAudioMime = inferAudioMimeType(
            audioMediaUrl,
            audioRes.headers?.["content-type"],
        );
        inlineAudioPart = {
          inlineData: {
            mimeType: detectedAudioMime,
            data: fetchedBase64,
          },
        };
      }
    } catch (audioErr) {
      console.warn("[AI Agent] Could not download voice note for multimodal Gemini:", audioErr.message);
    }
  }

  let inlineImagePart = null;
  if (imageMediaUrl && typeof imageMediaUrl === "string" && imageMediaUrl.startsWith("https://")) {
    try {
      const imgRes = await axios.get(imageMediaUrl, {
        responseType: "arraybuffer",
        timeout: 12000,
      });
      const fetchedImgBase64 = Buffer.from(imgRes.data).toString("base64");
      if (fetchedImgBase64 && fetchedImgBase64.length < 15 * 1024 * 1024) {
        const detectedImageMime = inferImageMimeType(
            imageMediaUrl,
            imgRes.headers?.["content-type"],
        );
        inlineImagePart = {
          inlineData: {
            mimeType: detectedImageMime,
            data: fetchedImgBase64,
          },
        };
      }
    } catch (imgErr) {
      console.warn("[AI Agent] Could not download image for multimodal Gemini:", imgErr.message);
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
        } else if (inlineImagePart) {
          latestUserParts.push(inlineImagePart);
          latestUserParts.push({
            text: userText && userText !== "Photo" ?
              `Examine this image and respond helpfully to the user's message: "${userText}".` :
              "Examine this image sent by the user and describe or assist with what is shown helpfully.",
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

        const generationConfig = {
          temperature: 0.4,
          maxOutputTokens: isVoiceMode ? 280 : 1024,
          ...(isVoiceMode && geminiModel.startsWith("gemini-2.5") ? {
            thinkingConfig: {thinkingBudget: 0},
          } : {}),
        };

        const MAX_TOOL_ROUNDS = 3;
        let roundContents = [...contents];
        let finalReplyText = "";

        for (let round = 0; round <= MAX_TOOL_ROUNDS; round++) {
          const allowMoreTools = round < MAX_TOOL_ROUNDS;
          const payload = {
            systemInstruction: {
              parts: [{text: systemInstruction}],
            },
            contents: roundContents,
            ...(allowMoreTools ? {tools: GEMINI_TOOLS_DECLARATION} : {}),
            generationConfig,
          };

          const roundRes = await axios.post(url, payload, {timeout: 20000});
          const candidate = roundRes.data?.candidates?.[0];
          const parts = candidate?.content?.parts || [];
          const functionCalls = parts.filter((p) => p.functionCall).map((p) => p.functionCall);

          if (functionCalls.length > 0 && allowMoreTools) {
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

            roundContents = [
              ...roundContents,
              candidate.content,
              {
                role: "function",
                parts: functionResponseParts,
              },
            ];
            continue;
          }

          finalReplyText = parts.map((p) => p.text || "").join("").trim();
          break;
        }

        if (finalReplyText) {
          const seenIds = new Set();
          const dedupedActions = collectedActions.filter((a) => {
            const key = `${a.type || ""}:${a.route || a.prompt || a.id || ""}`;
            if (seenIds.has(key)) return false;
            seenIds.add(key);
            return true;
          });
          return {
            text: stripEmojis(finalReplyText),
            aiActions: dedupedActions,
          };
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
          const structuredDraft = await detectStructuredDraftFromUserText(userText, userProfile);
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

  const structuredDraft = await detectStructuredDraftFromUserText(userText, userProfile);
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

  await Promise.all([
    ensureAiAgentProfile(),
    healLegacyAiAgentDocs(),
  ]);

  const typingRef = db.collection("chats").doc(chatId).collection("typing").doc(DIASPORA_AI_AGENT_UID);
  try {
    await typingRef.set({
      isTyping: true,
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
    });

    const [richContext, historySnap] = await Promise.all([
      loadComprehensiveUserAiContext(userId),
      db.collection("chats")
          .doc(chatId)
          .collection("messages")
          .orderBy("timestamp", "desc")
          .limit(12)
          .get(),
    ]);

    const userProfile = richContext.userProfile;
    const dspPoints = richContext.dspPoints;
    const historyMessages = historySnap.docs
        .map((d) => d.data())
        .reverse();

    const isAudioMessage = message.type === "audio" || message.type === "audio_file";
    const isImageMessage = message.type === "image";
    const audioMediaUrl = isAudioMessage ?
      (message.documentUrl || message.mediaUrl || message.metadata?.mediaUrl || null) :
      null;
    const imageMediaUrl = isImageMessage ?
      (message.imageUrl || message.documentUrl || message.mediaUrl || null) :
      null;
    const rawContent = String(message.content || "").trim();
    const userText = (rawContent &&
        rawContent !== "Voice message" &&
        rawContent !== "Audio" &&
        rawContent !== "Photo") ?
      rawContent :
      (isAudioMessage ?
        "Please listen to my voice message and answer my spoken question directly in the language I spoke." :
        isImageMessage ?
        "Please inspect the image I shared and help me with what is shown." :
        "Hello");
    const aiResult = await generateAiAgentResponse({
      userText,
      audioMediaUrl,
      imageMediaUrl,
      historyMessages,
      userProfile,
      dspPoints,
      richContext,
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
  await healLegacyAiAgentDocs(true);

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
  userProfile.uid = uid;

  let createdEntityId = null;
  let createdRoute = "/marketplace";
  let browseRoute = "/marketplace";
  let entityLabel = "Listing";

  if (draftType === "post_job") {
    const created = await createCanonicalMarketplaceListing({
      uid,
      userProfile,
      payload: {...payload, listingType: "job"},
    });
    createdEntityId = created.id;
    createdRoute = created.route;
    browseRoute = created.browseRoute;
    entityLabel = created.entityLabel;
  } else if (draftType === "post_car_rental") {
    const created = await createCanonicalPeerListing({
      uid,
      userProfile,
      payload: {...payload, type: "car"},
    });
    createdEntityId = created.id;
    createdRoute = created.route;
    browseRoute = created.browseRoute;
    entityLabel = created.entityLabel;
  } else if (draftType === "post_stay") {
    const subType = payload.subType === "hotel" ? "hotel" : "stay";
    const created = await createCanonicalPeerListing({
      uid,
      userProfile,
      payload: {...payload, type: subType},
    });
    createdEntityId = created.id;
    createdRoute = created.route;
    browseRoute = created.browseRoute;
    entityLabel = created.entityLabel;
  } else if (draftType === "post_marketplace") {
    const listingType = payload.listingType === "service" ? "service" : "product";
    const created = await createCanonicalMarketplaceListing({
      uid,
      userProfile,
      payload: {...payload, listingType},
    });
    createdEntityId = created.id;
    createdRoute = created.route;
    browseRoute = created.browseRoute;
    entityLabel = created.entityLabel;
  } else if (draftType === "post_real_estate") {
    const created = await createCanonicalRealEstateListing({
      uid,
      userProfile,
      payload,
    });
    createdEntityId = created.id;
    createdRoute = created.route;
    browseRoute = created.browseRoute;
    entityLabel = created.entityLabel;
  } else if (draftType === "post_event") {
    const created = await createCanonicalEvent({
      uid,
      userProfile,
      payload,
    });
    createdEntityId = created.id;
    createdRoute = created.route;
    browseRoute = created.browseRoute;
    entityLabel = created.entityLabel;
  } else {
    throw new functions.https.HttpsError("invalid-argument", `Unsupported draftType: ${draftType}`);
  }

  // Update the chat message metadata so the button immediately shows "Published"
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
          {
            id: `browse_created_${createdEntityId}`,
            type: "navigate",
            label: draftType === "post_job" ?
              "Browse All Jobs" :
              (draftType === "post_car_rental" ?
                "Browse Car Rentals" :
                (draftType === "post_stay" ?
                  (payload.subType === "hotel" ? "Browse Hotels" : "Browse Stays") :
                  (draftType === "post_marketplace" ?
                    (payload.listingType === "service" ? "Browse Services" : "Browse Products") :
                    (draftType === "post_real_estate" ?
                      `Browse ${payload.category === "plot" ? "Plots" : (payload.category === "farm" ? "Farms" : "Houses")}` :
                      (draftType === "post_event" ? "Browse All Events" : "Browse All Listings"))))),
            route: browseRoute,
            icon: "briefcase",
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

  const rawChatId = String(data?.chatId || `ai_agent_${uid}`).trim();
  const audioBase64 = String(data?.audioBase64 || "").trim();
  const mimeType = String(data?.mimeType || "audio/mp4").trim();
  const voiceName = String(data?.voiceName || "Aoede").trim();
  const saveToChat = data?.saveToChat === true;

  if (!audioBase64) {
    throw new functions.https.HttpsError("invalid-argument", "Missing audioBase64.");
  }

  await Promise.all([
    ensureAiAgentProfile(),
    healLegacyAiAgentDocs(),
  ]);

  const richContext = await loadComprehensiveUserAiContext(uid);
  const userProfile = richContext.userProfile;
  const dspPoints = richContext.dspPoints;

  let chatId = rawChatId;
  if (!chatId || chatId.startsWith("ai_agent_")) {
    const ensuredChatId = await resolveOrEnsureAiAgentChatForUser(uid, userProfile);
    if (ensuredChatId) {
      chatId = ensuredChatId;
    }
  }

  const historySnap = validId(chatId) ?
    await db.collection("chats")
        .doc(chatId)
        .collection("messages")
        .orderBy("timestamp", "desc")
        .limit(10)
        .get() :
    {docs: []};
  const historyMessages = (historySnap.docs || []).map((d) => d.data()).reverse();

  const aiResult = await generateAiAgentResponse({
    userText: "Listen carefully to what I just said in this voice turn and answer me naturally in the exact language I spoke.",
    audioBase64,
    audioMimeType: mimeType,
    isVoiceMode: true,
    historyMessages,
    userProfile,
    dspPoints,
    richContext,
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

// ── Ensure User <-> Diaspora AI Agent Direct Chat & Post Token Conversion Message ──
function _pairHash(firstUserId, secondUserId) {
  const users = [firstUserId, secondUserId].sort();
  return crypto.createHash("sha256").update(users.join(":")).digest("hex").slice(0, 32);
}

async function resolveOrEnsureAiAgentChatForUser(userId, userProfile = {}) {
  if (!validId(userId) || userId === DIASPORA_AI_AGENT_UID) return null;
  await ensureAiAgentProfile();

  const agentUid = DIASPORA_AI_AGENT_UID;
  const pairId = _pairHash(userId, agentUid);
  const pairRef = db.collection("direct_chat_pairs").doc(pairId);
  const detRef = db.collection("chats").doc(`direct_${pairId}`);

  const [pairSnap, detSnap] = await db.getAll(pairRef, detRef);
  let chatRef = detRef;
  if (pairSnap.exists && validId(pairSnap.data()?.chatId)) {
    chatRef = db.collection("chats").doc(pairSnap.data().chatId);
  } else if (!detSnap.exists) {
    const legacy = await db.collection("chats")
        .where("participants", "array-contains", userId)
        .where("type", "==", "direct")
        .limit(100)
        .get();
    const match = legacy.docs.find((s) => {
      const p = s.data()?.participants;
      return Array.isArray(p) && p.length === 2 && p.includes(userId) && p.includes(agentUid);
    });
    if (match) chatRef = match.ref;
  }

  const users = [userId, agentUid].sort();
  const userChatRef = db.collection("users").doc(userId).collection("userChats").doc(chatRef.id);
  const [chatSnap, userChatSnap] = await db.getAll(chatRef, userChatRef);
  if (!chatSnap.exists) {
    const existingUserChatData = userChatSnap.exists ? (userChatSnap.data() || {}) : {};
    const shouldDefaultPin = !userChatSnap.exists || (
      typeof existingUserChatData.pinned !== "boolean" &&
      typeof existingUserChatData.isPinned !== "boolean"
    );
    const now = admin.firestore.FieldValue.serverTimestamp();
    const nowMs = Date.now();
    const welcomeContent = buildAiAgentWelcomeText(userProfile);
    const welcomeActions = buildWelcomeAiActions();
    const welcomeMsgRef = chatRef.collection("messages").doc("welcome_from_ai_agent");
    const lastMessageData = {
      id: "welcome_from_ai_agent",
      content: welcomeContent,
      timestamp: nowMs,
      senderId: agentUid,
      senderName: DIASPORA_AI_AGENT_NAME,
      type: "text",
      status: "sent",
      metadata: {
        isAiAgent: true,
        aiActions: welcomeActions,
      },
    };
    const batch = db.batch();
    batch.set(pairRef, {
      chatId: chatRef.id,
      users,
      updatedAt: now,
    }, {merge: true});
    batch.set(chatRef, {
      id: chatRef.id,
      type: "direct",
      name: DIASPORA_AI_AGENT_NAME,
      photoUrl: DIASPORA_AI_AGENT_AVATAR,
      participants: users,
      memberCount: 2,
      createdBy: agentUid,
      adminId: agentUid,
      createdAt: now,
      updatedAt: nowMs,
      lastMessage: lastMessageData,
      metadata: {isAiAgent: true},
    }, {merge: true});
    batch.set(welcomeMsgRef, {
      id: "welcome_from_ai_agent",
      chatId: chatRef.id,
      senderId: agentUid,
      senderName: DIASPORA_AI_AGENT_NAME,
      senderImage: DIASPORA_AI_AGENT_AVATAR,
      content: welcomeContent,
      type: "text",
      timestamp: nowMs,
      status: "sent",
      metadata: {
        isAiAgent: true,
        aiActions: welcomeActions,
      },
    });
    batch.set(
        userChatRef,
        {
          chatId: chatRef.id,
          type: "direct",
          name: DIASPORA_AI_AGENT_NAME,
          photoUrl: DIASPORA_AI_AGENT_AVATAR,
          subtype: "ai_agent",
          lastMessage: lastMessageData,
          lastDeliveredMessageId: "welcome_from_ai_agent",
          updatedAt: nowMs,
          unreadCount: 1,
          unreadNotificationLines: [welcomeContent.slice(0, 500)],
          isDeleted: false,
          ...(shouldDefaultPin ? {pinned: true, pinnedBottom: false} : {}),
        },
        {merge: true},
    );
    batch.set(
        db.collection("users").doc(agentUid).collection("userChats").doc(chatRef.id),
        {
          chatId: chatRef.id,
          type: "direct",
          subtype: "ai_agent",
          lastMessage: lastMessageData,
          lastDeliveredMessageId: "welcome_from_ai_agent",
          updatedAt: nowMs,
          unreadCount: 0,
          unreadNotificationLines: [],
          lastRead: nowMs,
          isDeleted: false,
        },
        {merge: true},
    );
    await batch.commit();
  }

  return chatRef.id;
}

function buildNextPohTaskRecommendation({
  completedFields = 0,
  totalFields = 12,
  uniqueQrCount = 0,
  uniqueFamilyCount = 0,
  uniqueFriendCount = 0,
  uniqueVerificationCount = 0,
  hasLocation = false,
  hasEmergencyFund = false,
  pohTargetDsp = 0,
  trustScore = 0,
}) {
  const remainingPool = Math.max(0, 70000 - Number(pohTargetDsp || 0));

  if (!hasLocation) {
    return {
      nextTaskTitle: "Next PoH Task: Enable Location Transparency (+10,000 $DIASPORA)",
      nextTaskBody:
        `Turn on your live city visibility so nearby compatriots can connect with you and immediately convert **+10,000 DSP -> 10,000 $DIASPORA** at 100% efficiency (${remainingPool.toLocaleString()} $DIASPORA still available in your 70,000 PoH Genesis pool).`,
      aiActions: [
        {
          id: "poh_next_location",
          type: "navigate",
          label: "Enable Location (+10,000 $DIASPORA)",
          route: "/profile?enforceLocation=true",
          icon: "compass",
        },
        {
          id: "poh_open_qr",
          type: "navigate",
          label: `Open QR Exchange (${uniqueQrCount}/10)`,
          route: "/profile?showQr=true",
          icon: "check",
        },
      ],
    };
  }

  if (completedFields < 10) {
    const fieldsLeftFor10k = Math.max(1, 10 - completedFields);
    const rewardLeft = fieldsLeftFor10k * 1000;
    return {
      nextTaskTitle: `Next PoH Task: Fill Your 12 Profile Fields (+${rewardLeft.toLocaleString()} $DIASPORA) & QR Exchange`,
      nextTaskBody:
        `You have completed **${completedFields}/${totalFields}** profile fields. Complete **${fieldsLeftFor10k} more field${fieldsLeftFor10k === 1 ? "" : "s"}** to earn **+1,000 DSP per field** immediately converted 1:1 into **+${rewardLeft.toLocaleString()} $DIASPORA** (I can fill all 12 fields for you right here in chat!). Remember: complete **10 in-person QR Exchanges** (**${uniqueQrCount}/10**) to **unlock your minted $DIASPORA tokens**!`,
      aiActions: [
        {
          id: "poh_fill_profile_ai",
          type: "prompt",
          label: `Fill My 12 Fields with AI (+${rewardLeft.toLocaleString()} $DIASPORA)`,
          prompt: "Help me fill out my 12 profile fields right here in chat so I can earn my 10,000 DSP immediately converted to $DIASPORA tokens.",
          icon: "sparkles",
        },
        {
          id: "poh_open_qr",
          type: "navigate",
          label: `Open QR Exchange (${uniqueQrCount}/10 to Unlock)`,
          route: "/profile?showQr=true",
          icon: "check",
        },
        {
          id: "poh_next_profile",
          type: "navigate",
          label: "Edit Profile Manually",
          route: "/profile?edit=true",
          icon: "users",
        },
      ],
    };
  }

  if (uniqueQrCount < 10) {
    const qrLeft = Math.max(1, 10 - uniqueQrCount);
    const qrRewardLeft = qrLeft * 1000;
    return {
      nextTaskTitle: `Unlock Your Tokens: ${qrLeft} More In-Person QR Exchange${qrLeft === 1 ? "" : "s"} (+${qrRewardLeft.toLocaleString()} $DIASPORA)`,
      nextTaskBody:
        `You have **${uniqueQrCount}/10** in-person QR Exchanges. Every QR Exchange with a diaspora member converts **+1,000 DSP -> 1,000 $DIASPORA** immediately, and reaching **10 QR Exchanges unlocks all your minted $DIASPORA tokens** in your wallet for peer transfers and TDE macro distributions!`,
      aiActions: [
        {
          id: "poh_open_profile_qr",
          type: "navigate",
          label: `Open QR Exchange (${uniqueQrCount}/10 to Unlock)`,
          route: "/profile?showQr=true",
          icon: "check",
        },
        {
          id: "poh_next_qr",
          type: "navigate",
          label: "Find Nearby Compatriots",
          route: "/nearby",
          icon: "compass",
        },
      ],
    };
  }

  if (uniqueFamilyCount < 10) {
    const famLeft = Math.max(1, 10 - uniqueFamilyCount);
    const famRewardLeft = famLeft * 1000;
    return {
      nextTaskTitle: `Next PoH Task: Link Family Circle (+${famRewardLeft.toLocaleString()} $DIASPORA left)`,
      nextTaskBody:
        `You have **${uniqueFamilyCount}/10** Family Circle connections. Add family members on Diaspora Nearby to earn **+1,000 $DIASPORA** per verified family connection (up to **+${famRewardLeft.toLocaleString()} $DIASPORA** at 100% efficiency).`,
      aiActions: [
        {
          id: "poh_next_family",
          type: "navigate",
          label: `Add Family (+${famRewardLeft.toLocaleString()} $DIASPORA)`,
          route: "/nearby",
          icon: "compass",
        },
        {
          id: "poh_view_wallet",
          type: "navigate",
          label: "View $DIASPORA Wallet",
          route: "/dsp/points",
          icon: "check",
        },
      ],
    };
  }

  if (uniqueFriendCount < 10) {
    const friendLeft = Math.max(1, 10 - uniqueFriendCount);
    const friendRewardLeft = friendLeft * 1000;
    return {
      nextTaskTitle: `Next PoH Task: Link Friend Circle (+${friendRewardLeft.toLocaleString()} $DIASPORA left)`,
      nextTaskBody:
        `You have **${uniqueFriendCount}/10** Friend Circle connections. Connect with friends in your diaspora community to earn **+1,000 $DIASPORA** per connection (up to **+${friendRewardLeft.toLocaleString()} $DIASPORA** at 100% efficiency).`,
      aiActions: [
        {
          id: "poh_next_friend",
          type: "navigate",
          label: `Add Friends (+${friendRewardLeft.toLocaleString()} $DIASPORA)`,
          route: "/nearby",
          icon: "compass",
        },
        {
          id: "poh_view_wallet",
          type: "navigate",
          label: "View $DIASPORA Wallet",
          route: "/dsp/points",
          icon: "check",
        },
      ],
    };
  }

  if (uniqueVerificationCount < 10) {
    const verLeft = Math.max(1, 10 - uniqueVerificationCount);
    const verRewardLeft = verLeft * 1000;
    return {
      nextTaskTitle: `Next PoH Task: Peer Profile Verifications (+${verRewardLeft.toLocaleString()} $DIASPORA left)`,
      nextTaskBody:
        `You have **${uniqueVerificationCount}/10** Peer Profile Verifications. Have compatriots outside your Circle of Trust verify your profile fields to earn **+1,000 $DIASPORA** per peer verification (up to **+${verRewardLeft.toLocaleString()} $DIASPORA**).`,
      aiActions: [
        {
          id: "poh_next_verify",
          type: "navigate",
          label: `Explore Compatriots (${uniqueVerificationCount}/10 Verified)`,
          route: "/communities",
          icon: "compass",
        },
        {
          id: "poh_view_wallet",
          type: "navigate",
          label: "View $DIASPORA Wallet",
          route: "/dsp/points",
          icon: "check",
        },
      ],
    };
  }

  if (!hasEmergencyFund) {
    return {
      nextTaskTitle: "Final PoH Pillar: Ubuntu Emergency Fund (+10,000 $DIASPORA)",
      nextTaskBody:
        "Complete your 7th Proof of Humanity pillar by contributing to the **Ubuntu Emergency Fund** to immediately convert **+10,000 DSP -> 10,000 $DIASPORA** at 100% efficiency and reach the full **70,000 $DIASPORA** PoH Genesis target!",
      aiActions: [
        {
          id: "poh_next_emergency_fund",
          type: "navigate",
          label: "Ubuntu Emergency Fund (+10,000 $DIASPORA)",
          route: "/dsp/emergency-fund",
          icon: "check",
        },
        {
          id: "poh_view_wallet",
          type: "navigate",
          label: "View $DIASPORA Wallet",
          route: "/dsp/points",
          icon: "compass",
        },
      ],
    };
  }

  return {
    nextTaskTitle: `All 7 PoH Pillars Complete (PCT Score: ${trustScore}%)!`,
    nextTaskBody:
      "You have unlocked all **70,000 $DIASPORA** from the 7 Proof of Humanity pillars! Keep earning DSP from daily check-ins, events, hosting, and marketplace activity so your balance converts into even more **$DIASPORA** at upcoming Token Distribution Events (TDEs).",
    aiActions: [
      {
        id: "poh_view_wallet",
        type: "navigate",
        label: "View $DIASPORA Wallet & TDEs",
        route: "/dsp/points",
        icon: "check",
      },
      {
        id: "poh_explore_nearby",
        type: "navigate",
        label: "Explore Nearby",
        route: "/nearby",
        icon: "compass",
      },
    ],
  };
}

function buildLocationTransparencyDistributionPayload({
  userProfile = {},
  amount = 10000,
  reasonStr = "enabling Location Transparency (+10,000 DSP)",
  txHash = null,
  pohState = {},
}) {
  const firstName = String(userProfile.firstName || "").trim();
  const greetingName = firstName ? `, ${firstName}` : "";
  const completedFields = Number(pohState.completedFields ?? inspectProfileMilestones(userProfile).completedCount);
  const totalFields = Number(pohState.totalFields || 12);
  const fieldsLeftFor10k = Math.max(0, 10 - completedFields);
  const profileRewardLeft = fieldsLeftFor10k > 0 ? fieldsLeftFor10k * 1000 : 10000;
  const qrCount = Number(pohState.uniqueQrCount || 0);
  const isUnlocked = Boolean(pohState.tokensUnlocked || qrCount >= 10);
  const totalConvertedSoFar = Number(pohState.pohTargetDsp || amount);

  const headerLabel = "Location Transparency • DSP Converted to $DIASPORA";
  const footerLabel = txHash ?
    (isUnlocked ? "100% PoH On-Chain Mint • Unlocked" : `On-Chain in Wallet • Unlocks at 10 QR (${qrCount}/10)`) :
    (isUnlocked ? "100% PoH Conversion Confirmed" : `100% PoH Conversion • Unlocks at 10 QR (${qrCount}/10)`);

  const profileOfferText = completedFields < 12 ?
    `• **Fill Your 12 Profile Fields (+10,000 DSP -> 10,000 $DIASPORA Immediately)**: Complete your **${totalFields} profile fields** (**${completedFields}/${totalFields}** completed so far) to earn **10,000 DSP** that is **immediately converted 1:1 into 10,000 $DIASPORA tokens** right away (plus +2,000 DSP bonus on fields 11 and 12). **I can help fill out all 12 fields for you right here in chat** — just reply with your details or tap **Fill My 12 Fields with AI** below!` :
    `• **12 Profile Fields Completed**: You have already completed all **12/12** profile fields and earned your **10,000 $DIASPORA** profile reward!`;

  const qrUnlockText = isUnlocked ?
    `• **QR EXCHANGE Unlocked**: You have completed **${qrCount}/10** in-person QR Exchanges — your **$DIASPORA** tokens are unlocked in your wallet!` :
    `• **QR EXCHANGE to Unlock Your Tokens (Important)**: Your minted **$DIASPORA** (${totalConvertedSoFar.toLocaleString()} / 70,000 PoH $DIASPORA converted so far) is held safely in your smart wallet and **unlocks once you complete 10 in-person QR Exchanges** (**${qrCount}/10 completed**). Every QR Exchange with a fellow diaspora member also converts **+1,000 DSP -> 1,000 $DIASPORA** immediately (+10,000 $DIASPORA total)!`;

  const explanationText =
    `Congratulations${greetingName}! You just received **+${amount.toLocaleString()} $DIASPORA** from **${reasonStr}** — your earned DSP was immediately converted at **100% efficiency** into **$DIASPORA** tokens!\n\n` +
    `**Welcome to Proof of Humanity (PoH)**:\n` +
    `PoH rewards verified diaspora members with up to **70,000 $DIASPORA** converted immediately 1:1 from DSP across 7 community pillars (keep live city visibility enabled so this Location Transparency reward is never forfeited).\n\n` +
    `${profileOfferText}\n\n` +
    `${qrUnlockText}`;

  const nextTaskTitle = completedFields < 10 ?
    `Earn +${profileRewardLeft.toLocaleString()} $DIASPORA (12 Profile Fields) & Unlock via QR Exchange` :
    `Unlock Your $DIASPORA via In-Person QR Exchange (${qrCount}/10)`;

  const nextTaskBody = completedFields < 10 ?
    `Tap **Fill My 12 Fields with AI** below so I can help complete your 12 profile fields right here in chat for **+10,000 DSP -> 10,000 $DIASPORA**, and scan **10 in-person QR codes** (**${qrCount}/10**) via **QR Exchange** to **unlock all your tokens**!` :
    `Meet fellow diaspora members in person and scan **10 QR codes** (**${qrCount}/10**) via **QR Exchange** to earn **+1,000 $DIASPORA per scan** and **unlock all your minted $DIASPORA tokens**!`;

  const aiActions = [
    ...(completedFields < 12 ? [{
      id: "loc_dist_fill_12_fields_ai",
      type: "prompt",
      label: `Fill My 12 Fields with AI (+${profileRewardLeft.toLocaleString()} $DIASPORA)`,
      prompt: "Help me fill out my 12 profile fields right here in chat so I can earn my 10,000 DSP immediately converted to $DIASPORA tokens.",
      icon: "sparkles",
    }] : []),
    {
      id: "loc_dist_open_qr_exchange",
      type: "navigate",
      label: `Open QR Exchange (${qrCount}/10 to Unlock)`,
      route: "/profile?showQr=true",
      icon: "check",
    },
    ...(completedFields < 12 ? [{
      id: "loc_dist_edit_profile",
      type: "navigate",
      label: "Edit Profile Manually",
      route: "/profile?edit=true",
      icon: "users",
    }] : []),
    {
      id: "loc_dist_open_wallet",
      type: "navigate",
      label: "View $DIASPORA Wallet",
      route: "/dsp/crypto",
      icon: "wallet",
    },
  ];

  const pushSummaryText =
    `+${amount.toLocaleString()} $DIASPORA from Location Transparency! Fill your 12 profile fields with AI (+10,000 $DIASPORA) & complete 10 QR Exchanges to unlock your tokens.`;

  return {
    headerLabel,
    footerLabel,
    explanationText,
    pushSummaryText,
    nextTaskTitle,
    nextTaskBody,
    aiActions,
  };
}

async function sendAiAgentTokenConversionMessage({
  userId,
  userProfile = {},
  convertedAmount = 0,
  conversionKind = "poh_conversion",
  reasonsList = [],
  txHash = null,
  pohState = {},
  tdeDetails = null,
}) {
  const amount = Math.floor(Number(convertedAmount || 0));
  if (!validId(userId) || userId === DIASPORA_AI_AGENT_UID || amount <= 0) {
    return null;
  }

  try {
    const chatId = await resolveOrEnsureAiAgentChatForUser(userId, userProfile);
    if (!chatId) return null;

    const firstName = String(userProfile.firstName || "").trim();
    const greetingName = firstName ? `, ${firstName}` : "";

    let headerLabel = "DSP Converted to $DIASPORA";
    let footerLabel = "100% PoH Conversion Confirmed";
    let explanationText = "";
    let pushSummaryText = "";
    let nextTask = buildNextPohTaskRecommendation(pohState);

    if (conversionKind === "tde_conversion" && tdeDetails) {
      const epochNum = Number(tdeDetails.epoch || 1);
      const tdeNum = Number(tdeDetails.tdeNumber || 1);
      const eff = Number(tdeDetails.efficiency || 100);
      headerLabel = `TDE #${tdeNum} • DSP Converted to $DIASPORA`;
      footerLabel = `${eff}% PCT Conversion Confirmed`;
      explanationText =
        `Congratulations${greetingName}! You just received **+${amount.toLocaleString()} $DIASPORA** in your wallet from **Epoch ${epochNum} • TDE #${tdeNum}** (converted from your earned DSP at **${eff}% Proof of Community Trust efficiency**).`;
      pushSummaryText =
        `+${amount.toLocaleString()} $DIASPORA minted from your DSP in Epoch ${epochNum} TDE #${tdeNum}! Tap to view your reward & next PoH task.`;
    } else {
      const cleanReasons = Array.isArray(reasonsList)
        ? reasonsList.filter((r) => typeof r === "string" && r.trim().length > 0)
        : [];
      const reasonStr = cleanReasons.length > 0
        ? cleanReasons.join(", ")
        : "completing a Proof of Humanity (PoH) milestone";
      const isLocationTransparencyDist = cleanReasons.some((r) => /location transparency/i.test(r));

      if (isLocationTransparencyDist) {
        const locPayload = buildLocationTransparencyDistributionPayload({
          userProfile,
          amount,
          reasonStr,
          txHash,
          pohState,
        });
        headerLabel = locPayload.headerLabel;
        footerLabel = locPayload.footerLabel;
        explanationText = locPayload.explanationText;
        pushSummaryText = locPayload.pushSummaryText;
        nextTask = {
          nextTaskTitle: locPayload.nextTaskTitle,
          nextTaskBody: locPayload.nextTaskBody,
          aiActions: locPayload.aiActions,
        };
      } else {
        const totalConvertedSoFar = Number(pohState.pohTargetDsp || amount);
        const isUnlocked = Boolean(pohState.tokensUnlocked);
        const qrCount = Number(pohState.uniqueQrCount || 0);
        const lockNote = isUnlocked
          ? "Your $DIASPORA wallet is unlocked and active on-chain!"
          : `Your minted **$DIASPORA** is held safely in your smart wallet (**${totalConvertedSoFar.toLocaleString()} / 70,000** PoH $DIASPORA converted so far) and **unlocks via QR Exchange** once you complete **10 in-person QR Exchanges** (**${qrCount}/10 completed**).`;

        headerLabel = "DSP Converted to $DIASPORA";
        footerLabel = txHash ? "100% PoH On-Chain Mint Confirmed" : "100% PoH Conversion Confirmed";
        explanationText =
          `Congratulations${greetingName}! You just received **+${amount.toLocaleString()} $DIASPORA** because your earned DSP from **${reasonStr}** automatically converted at **100% efficiency** into **$DIASPORA** tokens.\n\n${lockNote}`;
        pushSummaryText =
          `+${amount.toLocaleString()} $DIASPORA converted from DSP (${reasonStr})! Tap to see how to earn more.`;
      }
    }

    const nowMs = Date.now() + 2500;
    const msgRef = db.collection("chats").doc(chatId).collection("messages").doc();

    await msgRef.set({
      id: msgRef.id,
      chatId,
      senderId: DIASPORA_AI_AGENT_UID,
      senderName: DIASPORA_AI_AGENT_NAME,
      senderImage: DIASPORA_AI_AGENT_AVATAR,
      content: pushSummaryText,
      type: "dsp_transfer",
      timestamp: nowMs,
      status: "sent",
      metadata: {
        isAiAgent: true,
        isConversion: true,
        conversionKind,
        amount,
        currency: "DIASPORA",
        assetType: "token",
        headerLabel,
        footerLabel,
        explanationText,
        nextTaskTitle: nextTask.nextTaskTitle,
        nextTaskBody: nextTask.nextTaskBody,
        aiActions: nextTask.aiActions,
        ...(txHash ? {txHash} : {}),
      },
    });

    return {chatId, messageId: msgRef.id};
  } catch (err) {
    console.warn(`[AI Agent] Failed to send token conversion message to ${userId}:`, err.message);
    return null;
  }
}

exports.DIASPORA_AI_AGENT_UID = DIASPORA_AI_AGENT_UID;
exports.DIASPORA_AI_AGENT_NAME = DIASPORA_AI_AGENT_NAME;
exports.DIASPORA_AI_AGENT_AVATAR = DIASPORA_AI_AGENT_AVATAR;
exports.AI_PROFILE_MILESTONE_FIELDS = AI_PROFILE_MILESTONE_FIELDS;
exports.inspectProfileMilestones = inspectProfileMilestones;
exports.ensureAiAgentProfile = ensureAiAgentProfile;
exports.buildAiAgentWelcomeText = buildAiAgentWelcomeText;
exports.buildWelcomeAiActions = buildWelcomeAiActions;
exports.buildLocationTransparencyDistributionPayload = buildLocationTransparencyDistributionPayload;
exports.buildNextPohTaskRecommendation = buildNextPohTaskRecommendation;
exports.buildSystemInstruction = buildSystemInstruction;
exports.executeUpdateMyProfileTool = executeUpdateMyProfileTool;
exports.handleUserMessageToAiAgent = handleUserMessageToAiAgent;
exports.sendAiAgentTokenConversionMessage = sendAiAgentTokenConversionMessage;
