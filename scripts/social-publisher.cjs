#!/usr/bin/env node

/**
 * Diaspora Nearby – Autonomous Social Media & Founder Authority CLI
 * 
 * Usage:
 *   node scripts/social-publisher.cjs --test
 *   node scripts/social-publisher.cjs --tweet "text"
 *   node scripts/social-publisher.cjs --thread-file <path>
 *   node scripts/social-publisher.cjs --linkedin "text"
 *   node scripts/social-publisher.cjs --generate [--platform x|linkedin] [--topic "..."]
 *   node scripts/social-publisher.cjs --dry-run
 *   node scripts/social-publisher.cjs --auto-post [--topic "..."]
 *   node scripts/social-publisher.cjs --youtube-script [--topic "..."]
 *   node scripts/social-publisher.cjs --youtube-upload <videoPath> [--title "..."] [--short]
 *   node scripts/social-publisher.cjs --youtube-setup
 */

const path = require("path");
const fs = require("fs");

// Load environment variables from functions/.env
const envPath = path.resolve(__dirname, "../functions/.env");
require(path.resolve(__dirname, "../functions/node_modules/dotenv")).config({ path: envPath });

// Ensure firebase-admin is initialized before requiring functions/lib modules
const admin = require(path.resolve(__dirname, "../functions/node_modules/firebase-admin"));
if (admin.apps.length === 0) {
  const saPath = path.resolve(__dirname, "../tools/admin-scripts/service-account-key.json");
  if (fs.existsSync(saPath)) {
    admin.initializeApp({ credential: admin.credential.cert(require(saPath)) });
  } else {
    admin.initializeApp();
  }
}

const { TwitterApi } = require(path.resolve(__dirname, "../functions/node_modules/twitter-api-v2"));
const axios = require(path.resolve(__dirname, "../functions/node_modules/axios"));
const youtubeAutomation = require(path.resolve(__dirname, "../functions/lib/youtube_automation"));
const unifiedPublisher = require(path.resolve(__dirname, "../functions/lib/unified_social_publisher"));
const contentStudio = require(path.resolve(__dirname, "../functions/lib/content_studio"));
const metaPublisher = require(path.resolve(__dirname, "../functions/lib/meta_publisher"));
const socialMedia = require(path.resolve(__dirname, "../functions/lib/social_media"));
const postToLinkedIn = socialMedia.postToLinkedIn;

function getXClient() {
  const apiKey = process.env.X_API_KEY;
  const apiSecret = process.env.X_API_KEY_SECRET;
  const accessToken = process.env.X_ACCESS_TOKEN;
  const accessSecret = process.env.X_ACCESS_TOKEN_SECRET;

  if (!apiKey || !apiSecret || !accessToken || !accessSecret) {
    throw new Error("Missing X API keys in functions/.env");
  }

  return new TwitterApi({
    appKey: apiKey,
    appSecret: apiSecret,
    accessToken: accessToken,
    accessSecret: accessSecret,
  });
}

// ── Test Connection ──
async function testConnections() {
  await socialMedia.ensureSocialConfigEnv();
  console.log("🔍 Testing Social Media API Credentials...\n");

  // 1. Test X (Personal & Optional Business)
  try {
    const client = getXClient();
    const me = await client.v2.me();
    console.log("✅ [X/Twitter Personal] Connected successfully!");
    console.log(`   Account: ${me.data.name} (@${me.data.username})`);
    console.log(`   User ID: ${me.data.id}`);
  } catch (err) {
    console.error("❌ [X/Twitter Personal] Failed to connect:", err?.data || err.message);
  }

  if (process.env.X_BUSINESS_ACCESS_TOKEN && process.env.X_BUSINESS_ACCESS_TOKEN_SECRET) {
    try {
      const bizClient = new TwitterApi({
        appKey: process.env.X_BUSINESS_API_KEY || process.env.X_API_KEY,
        appSecret: process.env.X_BUSINESS_API_KEY_SECRET || process.env.X_API_KEY_SECRET,
        accessToken: process.env.X_BUSINESS_ACCESS_TOKEN,
        accessSecret: process.env.X_BUSINESS_ACCESS_TOKEN_SECRET,
      });
      const bizMe = await bizClient.v2.me();
      console.log(`✅ [X/Twitter Business] Connected: ${bizMe.data.name} (@${bizMe.data.username})`);
    } catch (err) {
      console.error("❌ [X/Twitter Business] Failed to connect:", err?.data || err.message);
    }
  }

  console.log("\n----------------------------------------\n");

  // 2. Test AI Content Engine (Gemini / NVIDIA)
  const geminiKey = process.env.GEMINI_API_KEY;
  const nvidiaKey = process.env.NVIDIA_API_KEY;
  if (geminiKey) {
    console.log("✅ [AI Engine - Primary] Gemini API Key configured!");
    console.log("   Model: gemini-flash-latest");
  } else if (nvidiaKey) {
    console.log("✅ [AI Engine - Secondary] NVIDIA API Key configured!");
  } else {
    console.log("⚠️ [AI Engine] No AI API Key configured in .env");
  }

  console.log("\n----------------------------------------\n");

  // 3. Test LinkedIn Configuration & Firestore Token
  const clientId = process.env.LINKEDIN_CLIENT_ID;
  const orgId = process.env.LINKEDIN_ORG_ID || "112722655";
  const liDoc = await admin.firestore().collection("_internalConfig").doc("linkedin").get();
  const hasLiToken = (liDoc.exists && !!liDoc.data()?.accessToken) || !!process.env.LINKEDIN_ACCESS_TOKEN;
  console.log("ℹ️ [LinkedIn] Configuration:");
  console.log(`   Client ID: ${clientId ? "Configured (" + clientId.substring(0, 4) + "...)" : "Not configured"}`);
  console.log(`   Company Page (Org ID): ${orgId} (Diaspora Nearby)`);
  if (hasLiToken) {
    const d = liDoc.exists ? liDoc.data() : {};
    console.log(`   ✅ OAuth Token: Connected (${d.memberName || "Peter Swai"}, sub: ${d.memberSub || "env"})`);
  } else {
    console.log("   ⚠️ OAuth Token: Not connected in _internalConfig/linkedin. Run: node scripts/social-publisher.cjs --linkedin-setup");
  }

  console.log("\n----------------------------------------\n");

  // 4. Test Meta (Facebook Page & Instagram Business)
  const metaStatus = await metaPublisher.checkMetaStatus();
  if (metaStatus.valid) {
    console.log("✅ [Meta Business - Facebook & Instagram] Connected!");
    console.log(`   Facebook Page: ${metaStatus.pageName} (ID: ${metaStatus.pageId})`);
    console.log(`   Instagram Business ID: ${metaStatus.instagramAccountId}`);
  } else {
    console.log(`⚠️ [Meta Business] ${metaStatus.error || metaStatus.message}`);
  }
}

// ── Generate AI Content ──
async function generateContent({ platform = "x", topic = "diaspora_sovereign_wealth" } = {}) {
  return await socialMedia.generateDiasporaContent({ platform, topic });
}

// ── Publish Tweet ──
async function postTweet(text, inReplyToId = null, options = {}) {
  const res = await socialMedia.postTweet(text, inReplyToId, options);
  console.log(`🚀 [X/Twitter] Tweet Published!`);
  console.log(`   URL: ${res.tweetUrl}`);
  if (res.businessTweetUrl) {
    console.log(`   Business URL: ${res.businessTweetUrl}`);
  }
  console.log(`   Text: "${res.text}"\n`);
  return res;
}

// ── Publish Thread ──
async function postThread(threadArray) {
  console.log(`🧵 Publishing ${threadArray.length}-tweet thread to X...\n`);
  const res = await socialMedia.postThread(threadArray);
  console.log(`🎉 Thread completed! First tweet: ${res.firstTweetUrl}`);
  return res.thread;
}

// ── CLI Dispatcher ──
async function main() {
  const args = process.argv.slice(2);

  if (args.length === 0 || args.includes("--help") || args.includes("-h")) {
    console.log(`
Diaspora Nearby Social Media Publisher CLI

Commands:
  --test                    Test API credentials (X, AI, LinkedIn, Meta)
  --tweet "<text>"          Publish a single tweet to X
  --thread-file <path>      Publish a thread from a JSON or Markdown file
  --generate                Generate AI content (--platform x|linkedin|facebook|instagram --topic "...")
  --dry-run                 Generate and display posts without publishing
  --broadcast               Generate and immediately broadcast to X, LinkedIn, Facebook & Instagram
  --linkedin-setup          Generate LinkedIn OAuth 2.0 URL or save token to Firestore

Examples:
  node scripts/social-publisher.cjs --test
  node scripts/social-publisher.cjs --tweet "Turning $900B remittances into sovereign community wealth on Base Blockchain. #DiasporaNearby #BaseBlockchain"
  node scripts/social-publisher.cjs --dry-run
  node scripts/social-publisher.cjs --broadcast
    `);
    process.exit(0);
  }

  try {
    if (args.includes("--test")) {
      await testConnections();
      process.exit(0);
    }

    if (args.includes("--tweet")) {
      const idx = args.indexOf("--tweet");
      const text = args[idx + 1];
      if (!text) {
        console.error("❌ Please provide text for --tweet");
        process.exit(1);
      }
      await postTweet(text);
      process.exit(0);
    }

    if (args.includes("--thread-file")) {
      const idx = args.indexOf("--thread-file");
      const filePath = args[idx + 1];
      if (!filePath || !fs.existsSync(filePath)) {
        console.error(`❌ Thread file not found: ${filePath}`);
        process.exit(1);
      }

      const raw = fs.readFileSync(filePath, "utf8");
      let tweets = [];
      if (filePath.endsWith(".json")) {
        tweets = JSON.parse(raw);
      } else {
        // Markdown: Split by '---'
        tweets = raw.split(/^---+$/m).map((s) => s.trim()).filter((s) => s.length > 0);
      }

      await postThread(tweets);
      process.exit(0);
    }

    if (args.includes("--dry-run")) {
      console.log("🧪 DRY RUN MODE (No posts will be published)\n");
      console.log("Generating sample X post via AI...");
      const xText = await generateContent({ platform: "x", topic: "Find Your People: How real-time proximity alerts end diaspora isolation" });
      console.log("------------------------------------------");
      console.log(`[X Tweet Preview] (${xText.length}/280 chars):`);
      console.log(xText);
      console.log("------------------------------------------\n");

      console.log("Generating sample LinkedIn post via AI...");
      const liText = await generateContent({ platform: "linkedin", topic: "Never Moving Alone: Proximity Discovery & Dual Geographic Identity" });
      console.log("------------------------------------------");
      console.log(`[LinkedIn Post Preview] (${liText.length}/3000 chars):`);
      console.log(liText);
      console.log("------------------------------------------");
      process.exit(0);
    }

    if (args.includes("--generate")) {
      const platform = args.includes("--platform") ? args[args.indexOf("--platform") + 1] : "x";
      const topic = args.includes("--topic") ? args[args.indexOf("--topic") + 1] : "Diaspora Sovereign Economy";
      const text = await generateContent({ platform, topic });
      console.log(`\nGenerated ${platform.toUpperCase()} Post:\n`);
      console.log(text);
      process.exit(0);
    }

    if (args.includes("--youtube-script")) {
      const topic = args.includes("--topic") ? args[args.indexOf("--topic") + 1] : null;
      console.log(`🎬 Generating YouTube Short Script${topic ? ` on: "${topic}"` : ""} via Gemini AI...\n`);
      const script = await youtubeAutomation.generateYouTubeShortContent({ topic });
      console.log("==================================================");
      console.log(`🎥 TITLE: ${script.title}`);
      console.log("==================================================");
      console.log(`\n🎣 HOOK:\n${script.hook}\n`);
      console.log(`🎙️ NARRATION (Voiceover):\n${script.narration}\n`);
      console.log("🎞️ VISUAL DIRECTIONS:");
      script.visualPrompts.forEach((v, i) => console.log(`   [Beat ${i + 1}] ${v}`));
      console.log(`\n📢 CALL TO ACTION:\n${script.callToAction}\n`);
      console.log("--------------------------------------------------");
      console.log(`📝 DESCRIPTION:\n${script.description}\n`);
      console.log(`🏷️ TAGS:\n${script.tags.join(", ")}`);
      console.log("==================================================");
      process.exit(0);
    }

    if (args.includes("--youtube-upload")) {
      const idx = args.indexOf("--youtube-upload");
      const videoPath = args[idx + 1];
      if (!videoPath || !fs.existsSync(videoPath)) {
        console.error(`❌ Video file not found: ${videoPath}`);
        process.exit(1);
      }

      const isShort = args.includes("--short") || videoPath.toLowerCase().includes("short");
      const title = args.includes("--title")
        ? args[args.indexOf("--title") + 1]
        : path.basename(videoPath, path.extname(videoPath));
      const description = args.includes("--description")
        ? args[args.indexOf("--description") + 1]
        : "Discover the sovereign diaspora economy at https://diasporanearby.com\n\n#DiasporaNearby #DualIdentity";

      console.log(`📤 Uploading to YouTube (@DiasporaNearby)...`);
      console.log(`   File: ${videoPath}`);
      console.log(`   Title: ${title}`);
      console.log(`   Format: ${isShort ? "YouTube Short" : "Standard Video"}`);

      const res = await youtubeAutomation.uploadVideo({
        videoPath,
        title,
        description,
        isShort,
        onProgress: (p) => {
          process.stdout.write(`\r   Progress: ${p.toFixed(1)}%`);
        },
      });

      console.log(`\n\n🎉 YouTube Upload Complete!`);
      console.log(`   URL: ${res.videoUrl}`);
      console.log(`   Video ID: ${res.videoId}`);
      process.exit(0);
    }

    if (args.includes("--youtube-setup")) {
      console.log("📺 YouTube Data API v3 Setup Guide for @DiasporaNearby:\n");
      const hasId = !!process.env.YOUTUBE_CLIENT_ID;
      const hasSecret = !!process.env.YOUTUBE_CLIENT_SECRET;
      const hasRefresh = !!process.env.YOUTUBE_REFRESH_TOKEN;

      console.log(`   YOUTUBE_CLIENT_ID:     ${hasId ? "✅ Configured" : "❌ Missing"}`);
      console.log(`   YOUTUBE_CLIENT_SECRET: ${hasSecret ? "✅ Configured" : "❌ Missing"}`);
      console.log(`   YOUTUBE_REFRESH_TOKEN: ${hasRefresh ? "✅ Configured" : "❌ Missing"}`);

      if (!hasId || !hasSecret) {
        console.log("\n1. Go to Google Cloud Console (https://console.cloud.google.com).");
        console.log("2. Enable 'YouTube Data API v3'.");
        console.log("3. Create an OAuth 2.0 Client ID (Web Application or Desktop).");
        console.log("4. Add credentials to functions/.env:\n   YOUTUBE_CLIENT_ID=your_client_id\n   YOUTUBE_CLIENT_SECRET=your_client_secret");
      } else if (!hasRefresh) {
        try {
          const authUrl = youtubeAutomation.getAuthorizationUrl();
          console.log("\nTo authorize the Diaspora Nearby channel, open this URL in your browser:\n");
          console.log(authUrl);
          console.log("\nAfter logging in and authorizing, paste the returned code into:");
          console.log("node scripts/social-publisher.cjs --youtube-auth-code <code>");
        } catch (e) {
          console.error("Auth URL generation error:", e.message);
        }
      } else {
        console.log("\n✅ YouTube Data API is fully configured for automated uploading!");
      }
      process.exit(0);
    }

    if (args.includes("--multimedia-pack")) {
      const topic = args.includes("--topic") ? args[args.indexOf("--topic") + 1] : null;
      console.log(`🎨 Generating Full Daily Multimedia Content Pack${topic ? ` on: "${topic}"` : ""}...\n`);
      const pack = await contentStudio.generateDailyContentPack({ topic });

      // Save SVG quote card to disk
      const outDir = path.resolve(__dirname, "../assets/social_generated");
      if (!fs.existsSync(outDir)) fs.mkdirSync(outDir, { recursive: true });
      const svgPath = path.join(outDir, `quote_card_${Date.now()}.svg`);
      fs.writeFileSync(svgPath, pack.quoteCard.svg, "utf8");

      console.log("==================================================");
      console.log(`🌟 THEME: ${pack.theme}`);
      console.log("==================================================");
      console.log(`\n🖼️ BRANDED QUOTE CARD (Saved: ${svgPath}):`);
      console.log(`   Headline: "${pack.quoteCard.headline}"`);
      console.log(`   Body:     "${pack.quoteCard.bodyQuote}"`);
      console.log(`   By:       ${pack.quoteCard.subtext}`);
      console.log("\n--------------------------------------------------");
      console.log("📱 MULTI-PLATFORM COPY:");
      console.log(`[X (Twitter)]:\n${pack.textCopy.x}\n`);
      console.log(`[LinkedIn]:\n${pack.textCopy.linkedIn}\n`);
      console.log(`[Facebook]:\n${pack.textCopy.facebook}\n`);
      console.log(`[Instagram Caption]:\n${pack.textCopy.instagramCaption}\n`);
      console.log(`[TikTok Caption]:\n${pack.textCopy.tikTokCaption}\n`);
      console.log("--------------------------------------------------");
      console.log("🎬 SHORT VIDEO / REEL STORYBOARD:");
      console.log(`   Title: ${pack.shortVideoStoryboard.title}`);
      console.log(`   Hook:  ${pack.shortVideoStoryboard.hook}`);
      console.log(`   Narration:\n   "${pack.shortVideoStoryboard.narrationScript}"`);
      console.log("   Visual Beats:");
      pack.shortVideoStoryboard.visualBeats.forEach((b) => console.log(`   • ${b}`));
      console.log("==================================================");
      process.exit(0);
    }

    if (args.includes("--facebook") || args.includes("--fb")) {
      const idx = args.includes("--facebook") ? args.indexOf("--facebook") : args.indexOf("--fb");
      const message = args[idx + 1];
      const imageUrl = args.includes("--image") ? args[args.indexOf("--image") + 1] : null;
      if (!message) {
        console.error("❌ Please provide message text: --facebook 'Your message' [--image <url>]");
        process.exit(1);
      }
      console.log("👥 Posting to Facebook Page (Diaspora Nearby)...");
      const res = imageUrl
        ? await metaPublisher.postPhotoToFacebookPage({ imageUrl, caption: message })
        : await metaPublisher.postToFacebookPage({ message });
      console.log(`✅ [Facebook Page] Post Published!`);
      console.log(`   URL: ${res.postUrl}`);
      process.exit(0);
    }

    if (args.includes("--instagram") || args.includes("--ig")) {
      const idx = args.includes("--instagram") ? args.indexOf("--instagram") : args.indexOf("--ig");
      const argVal = args[idx + 1] || "";
      const isUrl = argVal.startsWith("http://") || argVal.startsWith("https://");
      const caption = args.includes("--caption")
        ? args[args.indexOf("--caption") + 1]
        : (isUrl ? "" : argVal);
      const imageUrl = args.includes("--image")
        ? args[args.indexOf("--image") + 1]
        : (isUrl ? argVal : metaPublisher.getRotatingVisualCardUrl(caption));

      console.log(`📸 Publishing to Instagram (@diasporanearby)...`);
      console.log(`   Visual Card: ${imageUrl}`);
      const res = await metaPublisher.postPhotoToInstagram({ imageUrl, caption });
      console.log(`✅ [Instagram] Post Published!`);
      console.log(`   URL: ${res.postUrl}`);
      process.exit(0);
    }

    if (args.includes("--meta-status")) {
      console.log("👥 Free Meta Developer API Status (Facebook & Instagram):\n");
      const status = await metaPublisher.checkMetaStatus();
      if (!status.configured) {
        console.log("❌ META_PAGE_ACCESS_TOKEN is not configured in functions/.env");
        console.log("\nTo enable 100% FREE posting to Facebook Page & Instagram (No credit card ever):");
        console.log("1. Go to https://developers.facebook.com/tools/explorer/");
        console.log("2. Under 'User or Page', select 'Diaspora Nearby' Page.");
        console.log("3. Add permissions: pages_manage_posts, pages_read_engagement, instagram_basic, instagram_content_publish.");
        console.log("4. Click 'Generate Access Token'.");
        console.log("5. Paste into functions/.env:");
        console.log("   META_PAGE_ACCESS_TOKEN=your_token_here");
        console.log("   META_PAGE_ID=455143491012634\n");
      } else if (!status.valid) {
        console.log(`⚠️ Meta Token configured, but returned error: ${status.error}`);
      } else {
        console.log("✅ Meta API Token is ACTIVE and VALID!");
        console.log(`   Page Name:    ${status.pageName}`);
        console.log(`   Page ID:      ${status.pageId}`);
        console.log(`   Instagram ID: ${status.instagramAccountId || "Auto-detecting from page"}`);
      }
      process.exit(0);
    }

    if (args.includes("--broadcast")) {
      const topic = args.includes("--topic") ? args[args.indexOf("--topic") + 1] : null;
      console.log(`🚀 Generating & Broadcasting Free Native Multi-Platform Post${topic ? ` on: "${topic}"` : ""}...\n`);
      const pack = await contentStudio.generateDailyContentPack({ topic });

      console.log(`🌟 Daily Theme: "${pack.theme}"\n`);

      // 1. Post to X (Twitter)
      try {
        console.log("1️⃣ Publishing to X (Twitter)...");
        const xRes = await postTweet(pack.textCopy.x);
        console.log(`   ✅ X: ${xRes.tweetUrl}`);
      } catch (xErr) {
        console.error(`   ❌ X error: ${xErr.message}`);
      }

      // 2. Post to LinkedIn (Personal & Company)
      try {
        console.log("\n2️⃣ Publishing to LinkedIn...");
        const liRes = await postToLinkedIn(pack.textCopy.linkedIn, { postToOrg: true });
        console.log(`   ✅ LinkedIn: ${liRes.postUrl}`);
      } catch (liErr) {
        console.error(`   ❌ LinkedIn error: ${liRes.message}`);
      }

      // 3. Post to Facebook Page & Instagram (if Meta token configured)
      if (process.env.META_PAGE_ACCESS_TOKEN) {
        const rotatingCardUrl = metaPublisher.getRotatingVisualCardUrl(topic || pack.theme);
        try {
          console.log(`\n3️⃣ Publishing to Facebook Page with Visual Card (${rotatingCardUrl})...`);
          const fbRes = await metaPublisher.postPhotoToFacebookPage({
            imageUrl: rotatingCardUrl,
            caption: pack.textCopy.facebook,
          });
          console.log(`   ✅ Facebook: ${fbRes.postUrl}`);
        } catch (fbErr) {
          console.error(`   ❌ Facebook error: ${fbErr.message}`);
        }

        // 4. Post to Instagram Professional Account
        try {
          console.log(`\n4️⃣ Publishing to Instagram (@diasporanearby) with Visual Card (${rotatingCardUrl})...`);
          const igRes = await metaPublisher.postPhotoToInstagram({
            imageUrl: rotatingCardUrl,
            caption: pack.textCopy.instagramCaption,
          });
          console.log(`   ✅ Instagram: ${igRes.postUrl}`);
        } catch (igErr) {
          console.error(`   ❌ Instagram error: ${igErr.response?.data?.error?.message || igErr.message}`);
        }
      } else {
        console.log("\n3️⃣ Facebook & Instagram: Skipped (Add META_PAGE_ACCESS_TOKEN to functions/.env to activate)");
      }

      console.log("\n🎉 Native Multi-Platform Execution Complete (100% Free)!");
      process.exit(0);
    }

    if (args.includes("--linkedin-setup")) {
      const clientId = process.env.LINKEDIN_CLIENT_ID;
      const redirectUri =
        process.env.LINKEDIN_REDIRECT_URI ||
        "https://us-central1-diaspora-nearby-a3dac.cloudfunctions.net/postToLinkedIn";
      const personalScope = "openid profile email w_member_social";
      const orgScope = "openid profile email w_member_social w_organization_social";
      const state = Math.random().toString(36).substring(2, 15);
      const personalAuthUrl = `https://www.linkedin.com/oauth/v2/authorization?response_type=code&client_id=${clientId}&redirect_uri=${encodeURIComponent(
        redirectUri
      )}&scope=${encodeURIComponent(personalScope)}&state=${state}`;
      const orgAuthUrl = `https://www.linkedin.com/oauth/v2/authorization?response_type=code&client_id=${clientId}&redirect_uri=${encodeURIComponent(
        redirectUri
      )}&scope=${encodeURIComponent(orgScope)}&state=${state}`;

      console.log("🔗 LinkedIn OAuth 2.0 Setup for Diaspora Nearby:\n");
      console.log(`   Client ID:    ${clientId || "Missing"}`);
      console.log(`   Redirect URI: ${redirectUri}`);
      console.log("\n1. Ensure the Redirect URI above is added in your LinkedIn Developer App (Auth tab).");
      console.log("2A. Open this URL for Personal Profile (Sign In with LinkedIn + Share on LinkedIn):\n");
      console.log(personalAuthUrl);
      console.log("\n2B. Or open this URL if 'Community Management API' is enabled on your LinkedIn App (Personal + Company Page 112722655):\n");
      console.log(orgAuthUrl);
      console.log("\nOr if you already have a LinkedIn Access Token, save it directly via:");
      console.log("   node scripts/social-publisher.cjs --linkedin-token <ACCESS_TOKEN>\n");
      process.exit(0);
    }

    if (args.includes("--linkedin-token")) {
      const idx = args.indexOf("--linkedin-token");
      const token = args[idx + 1];
      if (!token) {
        console.error("❌ Please provide an access token: --linkedin-token <ACCESS_TOKEN>");
        process.exit(1);
      }
      let memberSub = null;
      let memberName = "Peter Swai";
      try {
        const profileRes = await axios.get("https://api.linkedin.com/v2/userinfo", {
          headers: { Authorization: `Bearer ${token}` },
        });
        memberSub = profileRes.data?.sub;
        memberName = profileRes.data?.name || memberName;
      } catch (_e) {
        const meRes = await axios.get("https://api.linkedin.com/v2/me", {
          headers: { Authorization: `Bearer ${token}` },
        });
        memberSub = meRes.data?.id;
        memberName =
          [meRes.data?.localizedFirstName, meRes.data?.localizedLastName].filter(Boolean).join(" ") ||
          memberName;
      }
      const { admin, db } = require(path.resolve(__dirname, "../functions/lib/shared"));
      const expiresAt = new Date(Date.now() + 60 * 24 * 60 * 60 * 1000);
      await db.collection("_internalConfig").doc("linkedin").set(
        {
          accessToken: token,
          expiresAt,
          memberSub,
          memberName,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true }
      );
      console.log(`✅ LinkedIn token saved to Firestore _internalConfig/linkedin for ${memberName} (${memberSub})!`);
      process.exit(0);
    }

    console.log("Unknown command. Run with --help for instructions.");
  } catch (err) {
    console.error("❌ Execution Error:", err.message);
    process.exit(1);
  }
}

main();
