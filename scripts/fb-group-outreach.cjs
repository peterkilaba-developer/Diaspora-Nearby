#!/usr/bin/env node
/**
 * Diaspora Nearby – Direct Facebook Group Admin & Member Outreach Automation
 *
 * Reaches out directly to Facebook Group Admins (first) and Active Group Members:
 *   - Cohort A (tz_abroad): Tanzanians living outside Tanzania -> Mostly Kiswahili
 *   - Cohort B (expat_in_tz): Non-Tanzanians living inside Tanzania -> English or group's native language
 *
 * Usage:
 *   1. Generate all Facebook Group Admin & Member outreach links + personalized pitches:
 *      node scripts/fb-group-outreach.cjs --corridor=all
 *
 *   2. Run automated browser outreach on a specific Facebook Group (Admins first, then Members):
 *      node scripts/fb-group-outreach.cjs --automate --corridor=tz_abroad \
 *        --group-url="https://www.facebook.com/groups/YOUR_GROUP_ID" --limit=15
 */

const fs = require("fs");
const path = require("path");
const crypto = require("crypto");

const CONFIG_PATH = path.join(__dirname, "tz-corridor-groups.json");
const STATE_PATH = path.join(__dirname, ".outreach-state.json");
const PROFILE_DIR = path.join(__dirname, "..", ".outreach-profile", "fb");

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

function buildCode(prefix, id) {
  const hash = crypto.createHash("sha256").update(String(id)).digest("hex").slice(0, 6).toUpperCase();
  return `${prefix}${hash}`;
}

function fillTemplate(template, vars) {
  return String(template || "")
    .replace(/\{\{NAME\}\}/g, vars.name || "Rafiki")
    .replace(/\{\{GROUP_NAME\}\}/g, vars.groupName || "Diaspora Community")
    .replace(/\{\{HOST_REGION\}\}/g, vars.hostRegion || "Tanzania & Global")
    .replace(/\{\{CODE\}\}/g, vars.code || "GENESIS");
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

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function printDirectoryOutreachPlaybook(corridorFilter = "all") {
  const config = loadConfig();
  const corridorsToRun =
    corridorFilter === "all"
      ? ["tz_abroad", "expat_in_tz"]
      : [corridorFilter === "expat_in_tz" ? "expat_in_tz" : "tz_abroad"];

  console.log("\n══════════════════════════════════════════════════════════════════════");
  console.log("  FACEBOOK GROUP ADMIN & MEMBER DIRECT OUTREACH PLAYBOOK");
  console.log("══════════════════════════════════════════════════════════════════════");

  for (const key of corridorsToRun) {
    const corr = config.corridors[key];
    console.log(`\n▶ ${corr.label.toUpperCase()}`);
    console.log("──────────────────────────────────────────────────────────────────────");

    for (const grp of corr.groups) {
      const tpl = corr.templates[grp.lang] || corr.templates[corr.defaultLang];
      const adminMsg = fillTemplate(tpl.adminPitch, {
        name: "Admin",
        groupName: grp.name,
        hostRegion: grp.hostRegion,
        code: grp.adminCode,
      });

      console.log(`\n📌 GROUP: ${grp.name}`);
      console.log(`   Region: ${grp.hostRegion} | Language: ${grp.lang.toUpperCase()} | Admin Code: ${grp.adminCode}`);
      console.log(`   🔍 Find Group & Admins on FB: ${grp.fbGroupUrls[0]}`);
      console.log(`   💬 Direct Admin Pitch Preview (First Line):`);
      console.log(`      "${adminMsg.split("\n")[0]}"`);
      console.log(`   🔗 Admin Referral Link: https://diasporanearby.com/invite?code=${grp.adminCode}`);
    }
  }
  console.log("\n══════════════════════════════════════════════════════════════════════\n");
}

/**
 * Automated Browser Mode: Uses Playwright persistent context to extract Admins first,
 * then Active Members from a Facebook Group and send human-paced Messenger DMs.
 */
async function runBrowserAutomation(args) {
  let playwright;
  try {
    playwright = require("playwright");
  } catch (_e) {
    console.error(
      "Playwright is required for --automate mode. Run: npx playwright install chromium"
    );
    process.exit(1);
  }

  const groupUrl = String(args["group-url"] || "").replace(/\/+$/, "");
  if (!groupUrl || !groupUrl.includes("facebook.com/groups/")) {
    console.error("Please provide a valid --group-url=\"https://www.facebook.com/groups/...\"");
    process.exit(1);
  }

  const corridor = args.corridor || "tz_abroad";
  const isTzAbroad = corridor === "tz_abroad";
  const lang = args.lang || (isTzAbroad ? "sw" : "en");
  const groupName = args.group || (isTzAbroad ? "Watanzania Diaspora" : "Expats in Tanzania");
  const hostRegion = args.region || (isTzAbroad ? "Diaspora" : "Dar es Salaam, Arusha & Zanzibar");
  const limit = Number(args.limit || 15);

  const config = loadConfig();
  const corrCfg = config.corridors[isTzAbroad ? "tz_abroad" : "expat_in_tz"];
  const tpl = corrCfg.templates[lang] || corrCfg.templates[corrCfg.defaultLang];
  const state = loadState();

  fs.mkdirSync(PROFILE_DIR, { recursive: true });
  console.log(`🌐 Launching persistent Chrome session (${PROFILE_DIR})...`);
  const context = await playwright.chromium.launchPersistentContext(PROFILE_DIR, {
    headless: false,
    viewport: { width: 1280, height: 840 },
  });

  const page = await context.newPage();

  // Step 1: Visit Group Admins Page FIRST
  const adminsUrl = `${groupUrl}/members/admins`;
  console.log(`👑 Step 1: Navigating to Group Admins & Moderators (${adminsUrl})...`);
  await page.goto(adminsUrl, { waitUntil: "domcontentloaded" });
  await sleep(5000);

  const extractMembersFromPage = async (roleLabel) => {
    return await page.evaluate((role) => {
      const anchors = Array.from(
        document.querySelectorAll('a[href*="/user/"], a[href*="facebook.com/profile.php"]')
      );
      const found = [];
      const seen = new Set();
      for (const a of anchors) {
        const href = a.getAttribute("href") || "";
        const name = (a.innerText || a.getAttribute("aria-label") || "").trim();
        if (!name || name.length < 2 || name.length > 60) continue;
        const userMatch = href.match(/\/user\/(\d+)/) || href.match(/id=(\d+)/);
        const userId = userMatch ? userMatch[1] : href;
        if (seen.has(userId)) continue;
        seen.add(userId);
        found.push({ userId, name, role, href });
      }
      return found;
    }, roleLabel);
  };

  const admins = await extractMembersFromPage("admin");
  console.log(`✅ Found ${admins.length} Group Admins/Moderators.`);

  // Step 2: Visit Group Members Page
  const membersUrl = `${groupUrl}/members`;
  console.log(`👥 Step 2: Navigating to Active Group Members (${membersUrl})...`);
  await page.goto(membersUrl, { waitUntil: "domcontentloaded" });
  await sleep(5000);
  const members = await extractMembersFromPage("member");
  console.log(`✅ Found ${members.length} visible Group Members.`);

  const combinedQueue = [...admins, ...members];
  let sentCount = 0;

  for (const person of combinedQueue) {
    if (sentCount >= limit) break;
    if (state.contactedFacebook[person.userId] && !args.force) continue;

    const firstName = person.name.split(" ")[0];
    const code = buildCode(
      person.role === "admin" ? (isTzAbroad ? "ADMTZ" : "ADMEX") : isTzAbroad ? "TZ" : "EX",
      person.userId
    );
    const messageText = fillTemplate(
      person.role === "admin" ? tpl.adminPitch : tpl.memberDm,
      {
        name: firstName,
        groupName,
        hostRegion,
        code,
      }
    );

    console.log(
      `\n📨 [${sentCount + 1}/${limit}] Sending [${person.role.toUpperCase()}] DM to ${person.name} (${person.userId})...`
    );

    if (args["dry-run"]) {
      console.log(messageText);
      sentCount += 1;
      continue;
    }

    try {
      const dmUrl = `https://www.facebook.com/messages/t/${person.userId}`;
      await page.goto(dmUrl, { waitUntil: "domcontentloaded" });
      await sleep(4500);

      const box = page.locator('[role="textbox"][contenteditable="true"]').first();
      await box.click({ timeout: 8000 });
      await box.fill(messageText);
      await sleep(1200);
      await page.keyboard.press("Enter");
      await sleep(2500);

      state.contactedFacebook[person.userId] = {
        name: person.name,
        role: person.role,
        corridor,
        lang,
        groupName,
        code,
        sentAt: new Date().toISOString(),
      };
      saveState(state);
      sentCount += 1;

      // Human-safe randomized pause (45s - 75s) between Messenger DMs
      const pauseMs = 45000 + Math.floor(Math.random() * 30000);
      console.log(`⏳ Waiting ${Math.round(pauseMs / 1000)}s before next DM (human-safe pacing)...`);
      await sleep(pauseMs);
    } catch (dmErr) {
      console.warn(`⚠️ Could not DM ${person.name}: ${dmErr.message}`);
    }
  }

  console.log(`\n🎉 Session complete! Sent ${sentCount} direct outreach DMs.`);
  await context.close();
}

async function main() {
  const args = parseArgs(process.argv);
  if (args.automate) {
    await runBrowserAutomation(args);
    return;
  }
  printDirectoryOutreachPlaybook(args.corridor || "all");
}

main().catch((err) => {
  console.error("Facebook Group Outreach error:", err.message);
  process.exit(1);
});
