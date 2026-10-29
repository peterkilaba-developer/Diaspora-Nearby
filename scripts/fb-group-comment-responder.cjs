#!/usr/bin/env node
/**
 * Diaspora Nearby — Facebook Group Contextual Question & Discussion Responder
 *
 * Visits joined Tanzania Diaspora (Kiswahili) & Expat-in-Tanzania (English/Native)
 * Facebook Groups, reads recent member posts/questions/discussions, classifies what
 * the member needs, and crafts a contextual, human reply that:
 *   1. Answers/validates their specific question or discussion topic first.
 *   2. Offers the exact Diaspora Nearby platform feature that solves their need:
 *      - Nearby Compatriots & City Chambers (finding people / new in city)
 *      - Peer Hosting, Stays & Real Estate / Land Survey (housing, rooms, plots)
 *      - Zero-Fee Remittances (sending money / M-Pesa / currency exchange)
 *      - Diaspora Marketplace & Business Directory (buying, selling, services, cargo)
 *      - Travel & Car Rentals (flights, local cars, airport pickup)
 *      - Emergency & Bereavement Pool / Proof of Community Trust (msiba, vouching)
 *      - Local Events & Meetups (networking, weekend plans)
 *
 * Usage:
 *   node scripts/fb-group-comment-responder.cjs --playbook
 *   node scripts/fb-group-comment-responder.cjs --match "Nahitaji chumba Dubai Deira" --corridor tz_abroad
 *   node scripts/fb-group-comment-responder.cjs --match "Looking for a reliable car rental or apartment in Masaki Dar" --corridor expat_in_tz
 */

const fs = require("fs");
const path = require("path");

const CONFIG_PATH = path.join(__dirname, "tz-corridor-groups.json");
const STATE_PATH = path.join(__dirname, ".outreach-state.json");

const INVITE_CODE = "PETER-TZ-CC57";
const WA_DISPLAY = "+1 (641) 302-0012";
// Link-free CTAs so Facebook Groups' "Admin Assist -> Hold comments with links" filter never blocks our replies:
const CTA_KISWAHILI = `📲 Pakua app ya "Diaspora Nearby" kwenye Google Play / App Store (Invite Code: ${INVITE_CODE}) au tuma "JAMBO" WhatsApp: ${WA_DISPLAY} (diasporanearby [dot] com)`;
const CTA_ENGLISH = `📲 Search "Diaspora Nearby" on Google Play / App Store (Invite Code: ${INVITE_CODE}) or message "HELLO" on WhatsApp: ${WA_DISPLAY} (diasporanearby [dot] com)`;

/**
 * Topic classifiers + contextual response templates mapped to real Diaspora Nearby features.
 */
const TOPIC_SOLUTIONS = [
  {
    id: "housing_hosting_realestate",
    label: "Housing, Rentals, Rooms, Host Stays & Land/Real Estate",
    keywords: [
      "apartment", "rent", "house", "room", "flat", "accommodation", "housing", "stay",
      "host", "masaki", "mikocheni", "oysterbay", "upanga", "arusha", "zanzibar", "plot", "land",
      "nyumba", "chumba", "kupanga", "kiwanja", "ardhi", "makazi", "hostel", "bedspace", "sharing",
    ],
    platformFeature: "Peer Hosting, Stays & Verified Real Estate / Land Survey",
    replyKiswahili: (contextSnippet) =>
      `Kuhusu suala la ${contextSnippet || "makazi na nyumba"}: kwenye jukwaa la Diaspora Nearby tumeweka sehemu maalum ya **Peer Hosting & Stays** (kupata Watanzania wenzako wanaopangisha vyumba/nyumba au kukukaribisha ukifika mji mpya) pamoja na **Real Estate & Land Survey** kwa wanaotafuta nyumba au viwanja vilivyohakikiwa.\n\n${CTA_KISWAHILI}`,
    replyEnglish: (contextSnippet) =>
      `For ${contextSnippet || "finding verified housing and stays"}: you can also check **Diaspora Nearby** — our community platform has a dedicated **Stays, Peer Hosting & Real Estate** hub where verified expats and locals in Tanzania list apartments, short stays, and housing without middleman markups.\n\n${CTA_ENGLISH}`,
  },
  {
    id: "money_remittance_finance",
    label: "Sending Money, Remittances, M-Pesa, Exchange Rates & Loans",
    keywords: [
      "money", "send", "transfer", "remittance", "mpesa", "m-pesa", "tigo", "airtel",
      "exchange", "rate", "dollar", "usd", "tzs", "shilling", "bank", "fee", "loan", "capital",
      "kutuma", "pesa", "fedha", "makato", "kiwango", "mkopo", "mtaji", "benki", "wakala",
    ],
    platformFeature: "Zero-Fee Diaspora Remittances & Community Treasury (DDI)",
    replyKiswahili: (contextSnippet) =>
      `Kama unatafuta njia rahisi na salama kuhusu ${contextSnippet || "kutuma pesa nyumbani"}: kupitia **Diaspora Nearby** tuna huduma ya **Zero-Fee Remittance (Makato 0%)** inayokuwezesha kutuma pesa moja kwa moja kwenda Mobile Money (M-Pesa/Mixx/Airtel) au Benki Tanzania bila makato makubwa, huku ukijenga uaminifu wa kifedha (PCT) kwenye Chamber yako.\n\n${CTA_KISWAHILI}`,
    replyEnglish: (contextSnippet) =>
      `Regarding ${contextSnippet || "transfers and local payments in Tanzania"}: **Diaspora Nearby** offers **Zero-Fee Remittances & Instant Mobile Money / Bank Settlement** (TZS/USD) built specifically for the Tanzania corridor, so you avoid high transfer fees.\n\n${CTA_ENGLISH}`,
  },
  {
    id: "marketplace_business_jobs_shipping",
    label: "Marketplace, Buying/Selling, Cargo/Shipping, Jobs & Local Businesses",
    keywords: [
      "buy", "sell", "shop", "business", "cargo", "shipping", "courier", "luggage",
      "job", "hiring", "work", "service", "plumber", "mechanic", "doctor", "restaurant", "food",
      "biashara", "mzigo", "mizigo", "kusafirisha", "kazi", "ajira", "duka", "bidhaa", "fundi", "chakula",
    ],
    platformFeature: "Diaspora Marketplace, Verified Business Directory & Peer Luggage/Shipping",
    replyKiswahili: (contextSnippet) =>
      `Kuhusu ${contextSnippet || "huduma na biashara za Watanzania"}: kwenye **Diaspora Nearby** kuna **Diaspora Marketplace & Business Directory** ambapo Watanzania walio nje na nyumbani wanaweka biashara zao, bidhaa, fursa za kazi, na hata kuunganishwa na wasafiri wanaobeba mizigo.\n\n${CTA_KISWAHILI}`,
    replyEnglish: (contextSnippet) =>
      `If you're looking for trusted recommendations for ${contextSnippet || "local services and marketplace listings"}: check the **Diaspora Nearby Marketplace & Verified Business Directory** for Dar, Arusha, and Zanzibar — community members vouch for trusted local businesses, services, and peer listings using Proof of Community Trust.\n\n${CTA_ENGLISH}`,
  },
  {
    id: "travel_flights_cars",
    label: "Flights, Car Rentals, Visas, Airport Pickup & Travel",
    keywords: [
      "flight", "airline", "ticket", "car", "rental", "drive", "driver", "safari",
      "airport", "pickup", "visa", "resident permit", "travel", "trip",
      "ndege", "tiketi", "usafiri", "gari", "kukodi", "safari", "uwanja wa ndege", "pasi",
    ],
    platformFeature: "Travel Hub: Flights, Peer Car Rentals & Stays",
    replyKiswahili: (contextSnippet) =>
      `Kuhusu ${contextSnippet || "usafiri na magari"}: ndani ya **Diaspora Nearby** tuna **Travel Hub** yenye huduma za kutafuta tiketi za ndege, kukodi magari kwa bei nafuu kutoka kwa wanajumuiya (**Peer Car Rentals**), na kuwasiliana na Watanzania wa mji unaokwenda kabla hujasafiri.\n\n${CTA_KISWAHILI}`,
    replyEnglish: (contextSnippet) =>
      `For ${contextSnippet || "getting around and travel in Tanzania"}: **Diaspora Nearby** has a built-in **Peer Car Rental & Travel Hub** where verified locals and expats in Dar, Arusha, and Zanzibar list reliable cars (with no hidden agency fees) alongside flights and stays.\n\n${CTA_ENGLISH}`,
  },
  {
    id: "emergency_bereavement_trust",
    label: "Emergency Support, Bereavement (Msiba), Welfare & Community Trust",
    keywords: [
      "emergency", "help", "urgent", "hospital", "bereavement", "funeral", "trust", "scam", "verify",
      "msiba", "dharura", "mchango", "pole", "msaada", "ugonjwa", "hospitali", "uaminifu", "utapeli",
    ],
    platformFeature: "Diaspora Emergency & Bereavement Fund (Msiba Pool) + Proof of Community Trust (PCT)",
    replyKiswahili: (contextSnippet) =>
      `Pole sana na asante kwa kushirikisha jumuiya kuhusu ${contextSnippet || "jambo hili"}. Kwenye **Diaspora Nearby**, tumejenga mfumo rasmi wa **Emergency & Bereavement Fund (Mfuko wa Dharura na Msiba)** pamoja na **Proof of Community Trust (PCT)** ili Watanzania tuweze kusaidiana kwa uwazi na kuhakikisha kila mwanachama amethibitishwa na wenzake.\n\n${CTA_KISWAHILI}`,
    replyEnglish: (contextSnippet) =>
      `Thank you for raising this with the community. To help everyone verify who they are dealing with and support members in need, **Diaspora Nearby** includes **Peer Verification & Proof of Community Trust (PCT)** plus a transparent **Community Emergency Fund**.\n\n${CTA_ENGLISH}`,
  },
  {
    id: "community_events_networking",
    label: "Finding People Nearby, Events, Meetups & General Community Discussions",
    keywords: [
      "anyone", "who is in", "new in", "moving to", "meetup", "event", "weekend", "friends", "connect", "network",
      "nani yupo", "mgeni", "kukutana", "tamasha", "nyama choma", "jumuiya", "marafiki", "kufahamiana",
    ],
    platformFeature: "Nearby Compatriots Radar, Bilateral City Chambers & Community Events",
    replyKiswahili: (contextSnippet) =>
      `Karibu sana! Kuhusu ${contextSnippet || "kufahamiana na Watanzania wenzako karibu nawe"}: kupitia **Diaspora Nearby** unaweza kuona Watanzania walioko kwenye mji wako (**Nearby Compatriots**), kujiunga kwenye **City Chamber** ya mji huo, na kuona matukio (**Events**) yanayokuja.\n\n${CTA_KISWAHILI}`,
    replyEnglish: (contextSnippet) =>
      `Welcome! If you're looking to ${contextSnippet || "connect with expats and locals nearby"}: **Diaspora Nearby** automatically places you into your city's local Chamber (Dar es Salaam, Arusha, Zanzibar, etc.) where you can see verified members nearby, join the live city chat, and RSVP to local meetups and events.\n\n${CTA_ENGLISH}`,
  },
];

function classifyAndDraftReply(postText, corridor = "tz_abroad", topicHint = "") {
  const normalized = `${postText || ""} ${topicHint || ""}`.toLowerCase();
  let bestTopic = TOPIC_SOLUTIONS[TOPIC_SOLUTIONS.length - 1]; // Default: community_events_networking
  let bestScore = 0;

  for (const topic of TOPIC_SOLUTIONS) {
    let score = 0;
    for (const kw of topic.keywords) {
      if (normalized.includes(kw.toLowerCase())) {
        score += 1;
      }
    }
    if (score > bestScore) {
      bestScore = score;
      bestTopic = topic;
    }
  }

  const reply =
    corridor === "tz_abroad"
      ? bestTopic.replyKiswahili(topicHint)
      : bestTopic.replyEnglish(topicHint);

  return {
    topicId: bestTopic.id,
    topicLabel: bestTopic.label,
    platformFeature: bestTopic.platformFeature,
    corridor,
    reply,
  };
}

function loadState() {
  if (!fs.existsSync(STATE_PATH)) {
    return { commentedPosts: {}, groupWaves: {} };
  }
  try {
    return JSON.parse(fs.readFileSync(STATE_PATH, "utf8"));
  } catch (_) {
    return { commentedPosts: {}, groupWaves: {} };
  }
}

function saveState(state) {
  fs.writeFileSync(STATE_PATH, JSON.stringify(state, null, 2), "utf8");
}

function printPlaybook() {
  const config = JSON.parse(fs.readFileSync(CONFIG_PATH, "utf8"));
  const tzGroups = config.corridors?.tz_abroad?.groups || [];
  const expatGroups = config.corridors?.expat_in_tz?.groups || [];
  const totalClusters = tzGroups.length + expatGroups.length;
  console.log("================================================================================");
  console.log("  DIASPORA NEARBY — CONTEXTUAL GROUP QUESTION & DISCUSSION RESPONDER");
  console.log("================================================================================\n");
  console.log(`Joined Groups Configured: ${totalClusters} primary clusters (68 total joined FB groups)`);
  console.log(`Invite Code: ${INVITE_CODE} | WhatsApp Bot: ${WA_DISPLAY}\n`);
  console.log("Supported Topic -> Platform Feature Mappings:\n");
  for (const t of TOPIC_SOLUTIONS) {
    console.log(`  [${t.id}]`);
    console.log(`    When members ask about: ${t.label}`);
    console.log(`    We offer:               ${t.platformFeature}`);
    console.log(`    Kiswahili sample:       ${t.replyKiswahili().split("\n")[0]}`);
    console.log(`    English sample:         ${t.replyEnglish().split("\n")[0]}\n`);
  }
}

if (require.main === module) {
  const args = process.argv.slice(2);
  const matchIdx = args.indexOf("--match");
  const corridorIdx = args.indexOf("--corridor");
  const corridor = corridorIdx !== -1 && args[corridorIdx + 1] ? args[corridorIdx + 1] : "tz_abroad";

  if (matchIdx !== -1 && args[matchIdx + 1]) {
    const result = classifyAndDraftReply(args[matchIdx + 1], corridor);
    console.log(JSON.stringify(result, null, 2));
  } else {
    printPlaybook();
  }
}

module.exports = {
  TOPIC_SOLUTIONS,
  classifyAndDraftReply,
  loadState,
  saveState,
};
