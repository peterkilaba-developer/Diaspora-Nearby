#!/usr/bin/env node
/**
 * Diaspora Nearby – Direct WhatsApp Group Admin & Member Outreach Engine
 *
 * Reaches out directly to Admins (first) and Members inside WhatsApp Groups:
 *   - Cohort A (tz_abroad): Tanzanians living outside Tanzania -> Mostly Kiswahili
 *   - Cohort B (expat_in_tz): Non-Tanzanians living in Tanzania -> English or detected native language
 *
 * Usage Examples:
 *   1. Preview all Admin & Member pitches across target groups (Dry Run):
 *      node scripts/wa-group-outreach.cjs --preview
 *
 *   2. Extract Admins & Members from an open WhatsApp Web group & message them (Admins first):
 *      node scripts/wa-group-outreach.cjs --mode=web --corridor=tz_abroad --group="Watanzania USA" --limit=25
 *
 *   3. Generate direct 1-on-1 WhatsApp links / send to specific Admin & Member numbers:
 *      node scripts/wa-group-outreach.cjs --corridor=tz_abroad --group="Watanzania Houston" \
 *        --admins="+17135550111:Juma Admin" --members="+17135550112:Neema,+447700900123:Baraka"
 *
 *   4. Print the browser console extractor snippet for WhatsApp Web:
 *      node scripts/wa-group-outreach.cjs --extract-snippet
 */

const fs = require("fs");
const path = require("path");
const crypto = require("crypto");

const CONFIG_PATH = path.join(__dirname, "tz-corridor-groups.json");
const STATE_PATH = path.join(__dirname, ".outreach-state.json");
const EXTRACTED_PATH = path.join(__dirname, "outreach-extracted-wa.json");

function loadConfig() {
  return JSON.parse(fs.readFileSync(CONFIG_PATH, "utf8"));
}

function loadState() {
  if (!fs.existsSync(STATE_PATH)) {
    return { contactedWhatsApp: {}, contactedFacebook: {} };
  }
  try {
    return JSON.parse(fs.readFileSync(STATE_PATH, "utf8"));
  } catch (_e) {
    return { contactedWhatsApp: {}, contactedFacebook: {} };
  }
}

function saveState(state) {
  fs.writeFileSync(STATE_PATH, JSON.stringify(state, null, 2), "utf8");
}

function buildCode() {
  return "PETER-TZ-CC57";
}

/**
 * Infers native language from phone country code or explicit language tag for Expats in Tanzania
 */
function inferNativeLanguage(phone = "", groupLang = "en", corridor = "tz_abroad") {
  if (corridor === "tz_abroad") return "sw";
  if (groupLang && groupLang !== "en") return groupLang;

  const clean = String(phone).replace(/[^\d+]/g, "");
  if (/^\+(33|32|243|257|221|237|225)/.test(clean)) return "fr"; // France, Belgium, DRC, Burundi, Francophone Africa
  if (/^\+(86|852|886)/.test(clean)) return "zh"; // China, HK, Taiwan
  if (/^\+91/.test(clean)) return "hi"; // India
  if (/^\+(968|971|966|20|961|962)/.test(clean)) return "ar"; // Oman, UAE, Saudi, Egypt, Levant
  if (/^\+(49|43|41)/.test(clean)) return "de"; // Germany, Austria, Switzerland
  return "en";
}

function fillTemplate(template, vars) {
  return String(template || "")
    .replace(/\{\{NAME\}\}/g, vars.name || "Rafiki")
    .replace(/\{\{GROUP_NAME\}\}/g, vars.groupName || "Diaspora Community")
    .replace(/\{\{HOST_REGION\}\}/g, vars.hostRegion || "Tanzania & Global")
    .replace(/\{\{CODE\}\}/g, vars.code || "GENESIS");
}

function buildContactMessages({
  corridor = "tz_abroad",
  role = "member",
  name = "",
  phone = "",
  groupName = "",
  hostRegion = "",
  groupLang = "",
  adminCode = "",
}) {
  const config = loadConfig();
  const isTzAbroad = corridor === "tz_abroad";
  const lang = inferNativeLanguage(phone, groupLang, corridor);
  const corridorCfg = config.corridors[isTzAbroad ? "tz_abroad" : "expat_in_tz"];
  const templates = corridorCfg.templates[lang] || corridorCfg.templates[corridorCfg.defaultLang];

  const defaultName = isTzAbroad ? "Ndugu" : "Friend";
  const displayName = name && !/^\+?\d+$/.test(name) ? name.split(" ")[0] : defaultName;
  const code =
    role === "admin"
      ? adminCode || buildCode(isTzAbroad ? "ADMTZ" : "ADMEX", phone || groupName)
      : buildCode(isTzAbroad ? "TZ" : "EX", phone || displayName);

  const vars = {
    name: displayName,
    groupName: groupName || (isTzAbroad ? "Watanzania Diaspora" : "Expats in Tanzania"),
    hostRegion: hostRegion || (isTzAbroad ? "Diaspora" : "Dar es Salaam, Arusha & Zanzibar"),
    code,
  };

  if (role === "admin") {
    return {
      role: "admin",
      corridor,
      lang,
      code,
      primaryMessage: fillTemplate(templates.adminPitch, vars),
      pinAnnouncement: fillTemplate(templates.adminPinPost, vars),
    };
  }

  return {
    role: "member",
    corridor,
    lang,
    code,
    primaryMessage: fillTemplate(templates.memberDm, vars),
    pinAnnouncement: null,
  };
}

/**
 * Prints the 1-Click WhatsApp Web Console Snippet to extract Admins & Members from any open group
 */
function printWhatsAppWebExtractorSnippet() {
  const snippet = `
// === PASTE THIS INTO CHROME DEVTOOLS CONSOLE ON web.whatsapp.com ===
// 1. Open the target WhatsApp Group and click the Group Header to open "Group info"
// 2. Scroll down the participants list slightly, then run this snippet:
(function extractWhatsAppGroupMembers() {
  const groupTitleEl = document.querySelector('header span[title]') || document.querySelector('[data-testid="conversation-info-header-chat-title"]');
  const groupName = groupTitleEl ? groupTitleEl.textContent.trim() : 'WhatsApp Group';
  const rows = Array.from(document.querySelectorAll('[role="listitem"], [data-testid="cell-frame-container"]'));
  const contacts = [];
  const seen = new Set();

  for (const row of rows) {
    const text = row.innerText || '';
    const isAdmin = /group admin|admin|msimamizi/i.test(text);
    const phoneMatch = text.match(/\\+\\d[\\d\\s()-]{7,18}\\d/);
    const spans = Array.from(row.querySelectorAll('span[dir="auto"], span[title]'))
      .map(s => (s.getAttribute('title') || s.textContent || '').trim())
      .filter(Boolean);
    const phone = phoneMatch ? phoneMatch[0].replace(/[^\\d+]/g, '') : '';
    const name = spans.find(s => !s.startsWith('+') && !/admin/i.test(s)) || '';
    const key = phone || name;
    if (!key || seen.has(key) || /^you$/i.test(name)) continue;
    seen.add(key);
    contacts.push({
      role: isAdmin ? 'admin' : 'member',
      name: name || phone,
      phone: phone
    });
  }

  // Sort Admins first!
  contacts.sort((a, b) => (a.role === 'admin' ? -1 : 1));
  const payload = { groupName, extractedAt: new Date().toISOString(), total: contacts.length, contacts };
  console.log('✅ Extracted ' + contacts.length + ' contacts (' + contacts.filter(c => c.role === 'admin').length + ' admins first):', payload);
  copy(JSON.stringify(payload, null, 2));
  console.log('📋 Copied JSON to clipboard! Save it to scripts/outreach-extracted-wa.json');
})();
`.trim();

  console.log("\n══════════════════════════════════════════════════════════════════════");
  console.log("  WHATSAPP WEB GROUP ADMIN & MEMBER EXTRACTOR SNIPPET");
  console.log("══════════════════════════════════════════════════════════════════════\n");
  console.log(snippet);
  console.log("\n══════════════════════════════════════════════════════════════════════\n");
}

function parseArgs(argv) {
  const args = {};
  for (const raw of argv.slice(2)) {
    if (raw.startsWith("--")) {
      const eq = raw.indexOf("=");
      if (eq === -1) {
        args[raw.slice(2)] = true;
      } else {
        args[raw.slice(2, eq)] = raw.slice(eq + 1);
      }
    }
  }
  return args;
}

function parseInlineContacts(rawList = "", role = "member") {
  if (!rawList) return [];
  return String(rawList)
    .split(",")
    .map((item) => item.trim())
    .filter(Boolean)
    .map((entry) => {
      const [phonePart, namePart] = entry.split(":");
      return {
        role,
        phone: phonePart.trim(),
        name: (namePart || "").trim(),
      };
    });
}

async function runPreviewMode() {
  const config = loadConfig();
  console.log("\n══════════════════════════════════════════════════════════════════════");
  console.log("  DIASPORA NEARBY — GROUP ADMIN & MEMBER DIRECT OUTREACH PREVIEW");
  console.log("══════════════════════════════════════════════════════════════════════\n");

  // 1. Sample Cohort A (Tanzanians Abroad — Kiswahili)
  const tzGroup = config.corridors.tz_abroad.groups[0];
  const tzAdmin = buildContactMessages({
    corridor: "tz_abroad",
    role: "admin",
    name: "Juma",
    phone: "+17135550101",
    groupName: tzGroup.name,
    hostRegion: tzGroup.hostRegion,
    adminCode: tzGroup.adminCode,
  });
  const tzMember = buildContactMessages({
    corridor: "tz_abroad",
    role: "member",
    name: "Neema",
    phone: "+17135550102",
    groupName: tzGroup.name,
    hostRegion: tzGroup.hostRegion,
  });

  console.log("🇹🇿 [COHORT A: TANZANIANS ABROAD — MOSTLY KISWAHILI]");
  console.log(`Target Group: ${tzGroup.name}`);
  console.log("\n--- 1A. DIRECT DM TO GROUP ADMIN (KISWAHILI) ---");
  console.log(tzAdmin.primaryMessage);
  console.log("\n--- 1B. READY-TO-PIN GROUP POST FOR ADMIN (KISWAHILI) ---");
  console.log(tzAdmin.pinAnnouncement);
  console.log("\n--- 1C. DIRECT 1-ON-1 DM TO GROUP MEMBER (KISWAHILI) ---");
  console.log(tzMember.primaryMessage);

  // 2. Sample Cohort B (Expats in Tanzania — English + French + Chinese)
  const expatGroupEn = config.corridors.expat_in_tz.groups[0];
  const expatAdminEn = buildContactMessages({
    corridor: "expat_in_tz",
    role: "admin",
    name: "Sarah",
    phone: "+255755100100",
    groupName: expatGroupEn.name,
    hostRegion: expatGroupEn.hostRegion,
    groupLang: "en",
    adminCode: expatGroupEn.adminCode,
  });
  const expatMemberFr = buildContactMessages({
    corridor: "expat_in_tz",
    role: "member",
    name: "Jean-Luc",
    phone: "+243815550199",
    groupName: "Francophones en Tanzanie (Dar & Arusha)",
    hostRegion: "Dar es Salaam & Arusha",
    groupLang: "fr",
  });

  console.log("\n══════════════════════════════════════════════════════════════════════");
  console.log("🌍 [COHORT B: NON-TANZANIANS LIVING IN TANZANIA — ENGLISH & NATIVE LANG]");
  console.log(`Target Group: ${expatGroupEn.name}`);
  console.log("\n--- 2A. DIRECT DM TO GROUP ADMIN (ENGLISH) ---");
  console.log(expatAdminEn.primaryMessage);
  console.log("\n--- 2B. DIRECT 1-ON-1 DM TO FRANCOPHONE GROUP MEMBER IN TZ (FRANÇAIS) ---");
  console.log(expatMemberFr.primaryMessage);
  console.log("══════════════════════════════════════════════════════════════════════\n");
}

async function main() {
  const args = parseArgs(process.argv);

  if (args["extract-snippet"]) {
    printWhatsAppWebExtractorSnippet();
    return;
  }

  if (args.preview || Object.keys(args).length === 0) {
    await runPreviewMode();
    return;
  }

  const corridor = args.corridor || "tz_abroad";
  const groupName = args.group || (corridor === "tz_abroad" ? "Watanzania Diaspora" : "Expats in Tanzania");
  const hostRegion = args.region || (corridor === "tz_abroad" ? "USA, UK, UAE & Diaspora" : "Dar es Salaam, Arusha & Zanzibar");
  const groupLang = args.lang || (corridor === "tz_abroad" ? "sw" : "en");
  const limit = Number(args.limit || 25);

  let contacts = [];
  if (args.file && fs.existsSync(args.file)) {
    const fileData = JSON.parse(fs.readFileSync(args.file, "utf8"));
    contacts = Array.isArray(fileData.contacts) ? fileData.contacts : fileData;
  } else if (fs.existsSync(EXTRACTED_PATH) && !args.admins && !args.members) {
    const fileData = JSON.parse(fs.readFileSync(EXTRACTED_PATH, "utf8"));
    contacts = Array.isArray(fileData.contacts) ? fileData.contacts : [];
  } else {
    contacts = [
      ...parseInlineContacts(args.admins, "admin"),
      ...parseInlineContacts(args.members, "member"),
    ];
  }

  // Always sort Admins first so Group Admins are pitched before members
  contacts.sort((a, b) => (a.role === "admin" ? -1 : 1));

  const state = loadState();
  const queue = [];

  for (const contact of contacts) {
    if (queue.length >= limit) break;
    const cleanPhone = String(contact.phone || "").replace(/[^\d+]/g, "");
    if (!cleanPhone) continue;
    if (state.contactedWhatsApp[cleanPhone] && !args.force) {
      continue;
    }

    const built = buildContactMessages({
      corridor,
      role: contact.role || "member",
      name: contact.name || "",
      phone: cleanPhone,
      groupName,
      hostRegion,
      groupLang,
    });

    const waNumber = cleanPhone.replace(/^\+/, "");
    const waDeepLink = `https://wa.me/${waNumber}?text=${encodeURIComponent(built.primaryMessage)}`;

    queue.push({
      phone: cleanPhone,
      name: contact.name || cleanPhone,
      role: built.role,
      corridor: built.corridor,
      lang: built.lang,
      code: built.code,
      waDeepLink,
      primaryMessage: built.primaryMessage,
      pinAnnouncement: built.pinAnnouncement,
    });
  }

  console.log(`\n✅ Prepared ${queue.length} direct WhatsApp outreach messages (${queue.filter((q) => q.role === "admin").length} Group Admins first, ${queue.filter((q) => q.role === "member").length} Group Members):\n`);

  for (let i = 0; i < queue.length; i++) {
    const item = queue[i];
    console.log(`[#${i + 1}] [${item.role.toUpperCase()}] ${item.name} (${item.phone}) — Lang: ${item.lang.toUpperCase()} | Code: ${item.code}`);
    console.log(`   👉 1-Click Direct WhatsApp DM: ${item.waDeepLink}\n`);
  }

  // If --send-cloud is passed, also dispatch via deployed Cloud Function
  if (args["send-cloud"]) {
    const endpoint =
      args.endpoint ||
      "https://us-central1-diaspora-nearby-a3dac.cloudfunctions.net/dispatchGroupOutreachBatch";
    console.log(`📡 Dispatching ${queue.length} contacts via Cloud Function (${endpoint})...`);
    const res = await fetch(endpoint, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        corridor,
        groupName,
        hostRegion,
        contacts: queue.map((q) => ({
          phone: q.phone,
          name: q.name,
          role: q.role,
          lang: q.lang,
          code: q.code,
          message: q.primaryMessage,
          pinAnnouncement: q.pinAnnouncement,
        })),
      }),
    });
    const result = await res.json();
    console.log("Cloud Dispatch Result:", JSON.stringify(result, null, 2));

    for (const item of queue) {
      state.contactedWhatsApp[item.phone] = {
        role: item.role,
        corridor: item.corridor,
        groupName,
        sentAt: new Date().toISOString(),
      };
    }
    saveState(state);
  }
}

main().catch((err) => {
  console.error("Outreach error:", err.message);
  process.exit(1);
});
