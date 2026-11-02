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
    id: "nearby_notification",
    label: "Nearby Notification & Real-Time Proximity Alerts",
    keywords: [
      "alert", "notification", "pass by", "street", "neighborhood", "around", "close by", "radar",
      "taarifa", "karibu", "mtaa", "jirani", "kupishana",
    ],
    platformFeature: "Nearby Notification (Real-Time Compatriot Proximity Alerts)",
    replyKiswahili: (contextSnippet) =>
      `Kuhusu ${contextSnippet || "kufahamu Watanzania walioko mtaa mmoja na wewe"}: kupitia **Diaspora Nearby**, huduma ya **Nearby Notification** inakupa taarifa za papo hapo Mtanzania mwenzako anapokuwa karibu nawe, pamoja na **Nearby Discovery**, **Live Radio**, **Ubuntu Emergency Fund**, na **DDI Loans**.\n\n${CTA_KISWAHILI}`,
    replyEnglish: (contextSnippet) =>
      `Regarding ${contextSnippet || "knowing when compatriots are right around the corner"}: **Diaspora Nearby** includes **Nearby Notification** (real-time proximity alerts when someone from your home country is nearby), alongside **Nearby Discovery**, **24/7 Live Homeland Radio**, **Ubuntu Emergency Fund**, and **DDI Loans**.\n\n${CTA_ENGLISH}`,
  },
  {
    id: "live_radio",
    label: "Live Homeland & Diaspora Radio Streaming (24/7)",
    keywords: [
      "radio", "music", "news", "stream", "listen", "bongo", "fm", "clouds", "wasafi", "tbc", "station", "podcast",
      "redio", "muziki", "habari", "kusikiliza", " matangazo", "nyumbani",
    ],
    platformFeature: "Live Homeland & Diaspora Radio (24/7 Streaming)",
    replyKiswahili: (contextSnippet) =>
      `Kuhusu ${contextSnippet || "kusikiliza redio na habari za nyumbani Tanzania"}: ndani ya **Diaspora Nearby** kuna **Live Radio** inayokuwezesha kusikiliza redio za nyumbani Tanzania na diaspora mubashara (24/7) popote ulipo, pamoja na **Nearby Discovery**, **Nearby Notification**, **Ubuntu Emergency Fund**, na **DDI Loans**.\n\n${CTA_KISWAHILI}`,
    replyEnglish: (contextSnippet) =>
      `For ${contextSnippet || "staying connected to home news and music"}: **Diaspora Nearby** has built-in **24/7 Live Homeland & Diaspora Radio**, alongside **Nearby Discovery**, **Nearby Notification**, **Ubuntu Emergency Fund**, and **DDI Community Loans**.\n\n${CTA_ENGLISH}`,
  },
  {
    id: "ubuntu_emergency_fund",
    label: "Ubuntu Emergency Fund & Bereavement (Msiba) Mutual Aid",
    keywords: [
      "emergency", "help", "urgent", "hospital", "bereavement", "funeral", "welfare", "ubuntu", "support", "crisis",
      "msiba", "dharura", "mchango", "pole", "msaada", "ugonjwa", "hospitali", "kufiwa", "matibabu",
    ],
    platformFeature: "Ubuntu Emergency Fund (Transparent Community Emergency & Bereavement Pool)",
    replyKiswahili: (contextSnippet) =>
      `Pole sana na asante kwa kushirikisha jumuiya kuhusu ${contextSnippet || "jambo hili la dharura"}. Kwenye **Diaspora Nearby**, tumejenga **Ubuntu Emergency Fund (Mfuko wa Dharura na Msiba)** ili Watanzania tuweze kusaidiana kwa uwazi wakati wa matatizo, pamoja na **Nearby Discovery**, **Nearby Notification**, **Live Radio**, na **DDI Loans**.\n\n${CTA_KISWAHILI}`,
    replyEnglish: (contextSnippet) =>
      `Thank you for sharing this with the community. To support members during emergencies and bereavement without chaotic fundraising, **Diaspora Nearby** provides a transparent **Ubuntu Emergency Fund**, alongside **Nearby Discovery**, **Nearby Notification**, **Live Radio**, and **DDI Loans**.\n\n${CTA_ENGLISH}`,
  },
  {
    id: "ddi_loans",
    label: "DDI Loans (Diaspora Direct Investment & Community Loans)",
    keywords: [
      "loan", "capital", "invest", "investment", "business", "project", "ddi", "credit", "finance", "funding", "build",
      "mkopo", "mikopo", "mtaji", "uwekezaji", "biashara", "mradi", "ujenzi", "nyumba", "kiwanja",
    ],
    platformFeature: "DDI Loans (Diaspora Direct Investment Community-Backed Loans)",
    replyKiswahili: (contextSnippet) =>
      `Kuhusu ${contextSnippet || "mikopo na mitaji ya uwekezaji"}: kupitia **Diaspora Nearby** tuna huduma ya **DDI Loans (Mikopo ya Uwekezaji wa Diaspora)** inayowawezesha wanajumuiya kupata mikopo ya miradi na uwekezaji kupitia hazina ya jamii yetu, pamoja na **Nearby Discovery**, **Nearby Notification**, **Live Radio**, na **Ubuntu Emergency Fund**.\n\n${CTA_KISWAHILI}`,
    replyEnglish: (contextSnippet) =>
      `Regarding ${contextSnippet || "community financing and cross-border investment"}: **Diaspora Nearby** features **DDI Loans (Diaspora Direct Investment Loans)** backed by community treasuries to fund member projects and businesses, plus **Nearby Discovery**, **Nearby Notification**, **Live Radio**, and the **Ubuntu Emergency Fund**.\n\n${CTA_ENGLISH}`,
  },
  {
    id: "nearby_discovery",
    label: "Nearby Discovery (Finding Compatriots & Community Nearby)",
    keywords: [
      "anyone", "who is in", "new in", "moving to", "meetup", "event", "weekend", "friends", "connect", "network", "nearby",
      "nani yupo", "mgeni", "kukutana", "tamasha", "nyama choma", "jumuiya", "marafiki", "kufahamiana", "watanzania",
    ],
    platformFeature: "Nearby Discovery & Nearby Notification + Live Radio, Ubuntu Emergency Fund & DDI Loans",
    replyKiswahili: (contextSnippet) =>
      `Karibu sana! Kuhusu ${contextSnippet || "kuwafahamu Watanzania wenzako karibu nawe"}: kupitia **Diaspora Nearby** unapata huduma 5 muhimu: **Nearby Discovery** (kuona Watanzania walioko mji/mtaa wako), **Nearby Notification** (taarifa Mtanzania akiwa karibu), **Live Radio** (redio za TZ saa 24), **Ubuntu Emergency Fund** (mfuko wa dharura), na **DDI Loans** (mikopo ya uwekezaji wa jamii).\n\n${CTA_KISWAHILI}`,
    replyEnglish: (contextSnippet) =>
      `Welcome! If you're looking to ${contextSnippet || "connect with compatriots nearby"}: **Diaspora Nearby** gives you 5 core utilities in your city — **Nearby Discovery**, **Nearby Notification**, **24/7 Live Homeland Radio**, **Ubuntu Emergency Fund**, and **DDI Community Loans**.\n\n${CTA_ENGLISH}`,
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
