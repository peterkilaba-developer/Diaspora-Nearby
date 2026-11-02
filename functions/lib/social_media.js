/**
 * Diaspora Nearby – Autonomous Social Media & Founder Authority Module
 * 
 * Manages automated and on-demand publishing across X (Twitter) and LinkedIn
 * on behalf of Peter Swai and the Diaspora Nearby ecosystem.
 * 
 * Features:
 * - Direct X API v2 posting (OAuth 1.0a User Context)
 * - X Thread chaining (multi-part sequential tweets)
 * - LinkedIn Personal and Organization (Company Page 112722655) publishing
 * - AI Content Generation Engine powered by Gemini & NVIDIA tuned for Diaspora Nearby
 * - Daily scheduled cron publishing & audit logging
 */

const { functions, admin, db } = require("./shared");
const { TwitterApi } = require("twitter-api-v2");
const axios = require("axios");

// ── Environment & Firestore Config Fallback ──
let _socialConfigLoaded = false;
async function ensureSocialConfigEnv() {
  if (_socialConfigLoaded && process.env.X_API_KEY && process.env.GEMINI_API_KEY) {
    return;
  }
  try {
    const doc = await db.collection("_internalConfig").doc("social").get();
    if (doc.exists) {
      const d = doc.data() || {};
      const map = {
        X_API_KEY: d.xApiKey,
        X_API_KEY_SECRET: d.xApiSecret,
        X_ACCESS_TOKEN: d.xAccessToken,
        X_ACCESS_TOKEN_SECRET: d.xAccessSecret,
        X_BUSINESS_API_KEY: d.xBusinessApiKey,
        X_BUSINESS_API_KEY_SECRET: d.xBusinessApiSecret,
        X_BUSINESS_ACCESS_TOKEN: d.xBusinessAccessToken,
        X_BUSINESS_ACCESS_TOKEN_SECRET: d.xBusinessAccessSecret,
        GEMINI_API_KEY: d.geminiApiKey,
        NVIDIA_API_KEY: d.nvidiaApiKey,
        META_APP_ID: d.metaAppId,
        META_PAGE_ID: d.metaPageId,
        META_IG_ACCOUNT_ID: d.metaIgAccountId,
        META_PAGE_ACCESS_TOKEN: d.metaPageAccessToken,
        LINKEDIN_CLIENT_ID: d.linkedInClientId,
        LINKEDIN_CLIENT_SECRET: d.linkedInClientSecret,
        LINKEDIN_ORG_CLIENT_ID: d.linkedInOrgClientId,
        LINKEDIN_ORG_CLIENT_SECRET: d.linkedInOrgClientSecret,
        LINKEDIN_ORG_ID: d.linkedInOrgId,
        LINKEDIN_ACCESS_TOKEN: d.linkedInAccessToken,
        LINKEDIN_ORG_ACCESS_TOKEN: d.linkedInOrgAccessToken,
        LINKEDIN_MEMBER_SUB: d.linkedInMemberSub,
      };
      for (const [envKey, val] of Object.entries(map)) {
        if (!process.env[envKey] && val) {
          process.env[envKey] = String(val);
        }
      }
      _socialConfigLoaded = true;
    }
  } catch (err) {
    console.warn("Could not load _internalConfig/social fallback:", err.message);
  }
}

function getXClient(accountType = "personal") {
  const isBusiness = accountType === "business";
  const apiKey = isBusiness
    ? process.env.X_BUSINESS_API_KEY || process.env.X_API_KEY
    : process.env.X_API_KEY;
  const apiSecret = isBusiness
    ? process.env.X_BUSINESS_API_KEY_SECRET || process.env.X_API_KEY_SECRET
    : process.env.X_API_KEY_SECRET;
  const accessToken = isBusiness
    ? process.env.X_BUSINESS_ACCESS_TOKEN
    : process.env.X_ACCESS_TOKEN;
  const accessSecret = isBusiness
    ? process.env.X_BUSINESS_ACCESS_TOKEN_SECRET
    : process.env.X_ACCESS_TOKEN_SECRET;

  if (!apiKey || !apiSecret || !accessToken || !accessSecret) {
    throw new Error(
      `X API credentials (${accountType}) missing in environment (.env or _internalConfig/social)`
    );
  }

  return new TwitterApi({
    appKey: apiKey,
    appSecret: apiSecret,
    accessToken: accessToken,
    accessSecret: accessSecret,
  });
}

// ── Rate Limit Check ──
async function checkXRateLimit(maxPerDay = 50) {
  const today = new Date();
  today.setHours(0, 0, 0, 0);

  const snapshot = await db.collection("_socialXPosts")
    .where("postedAt", ">=", today)
    .get();

  if (snapshot.size >= maxPerDay) {
    throw new Error(`Daily X rate limit reached (${snapshot.size}/${maxPerDay} posts today).`);
  }
  return snapshot.size;
}

// ── Core Post to X (Personal + Optional Business Account) ──
async function postTweet(text, inReplyToId = null, options = {}) {
  await ensureSocialConfigEnv();

  if (!text || text.trim().length === 0) {
    throw new Error("Tweet text cannot be empty.");
  }

  const cleanText = text.trim();
  if (cleanText.length > 280) {
    throw new Error(`Tweet exceeds 280 characters (${cleanText.length}/280).`);
  }

  await checkXRateLimit(50);

  const accountType = options.accountType || "personal";
  const client = getXClient(accountType);
  const payload = { text: cleanText };
  if (inReplyToId) {
    payload.reply = { in_reply_to_tweet_id: inReplyToId };
  }

  const result = await client.v2.tweet(payload);
  const tweetId = result.data.id;
  const tweetUrl = `https://x.com/i/status/${tweetId}`;

  // Also cross-post to Business X account if configured and not already in business mode
  let businessTweetUrl = null;
  let businessTweetId = null;
  if (
    accountType === "personal" &&
    options.postToBusiness !== false &&
    process.env.X_BUSINESS_ACCESS_TOKEN &&
    process.env.X_BUSINESS_ACCESS_TOKEN_SECRET &&
    process.env.X_BUSINESS_ACCESS_TOKEN !== process.env.X_ACCESS_TOKEN
  ) {
    try {
      const bizClient = getXClient("business");
      const bizRes = await bizClient.v2.tweet({ text: cleanText });
      businessTweetId = bizRes.data.id;
      businessTweetUrl = `https://x.com/i/status/${businessTweetId}`;
    } catch (bizErr) {
      console.warn("X Business cross-post warning:", bizErr.message);
    }
  }

  // Log to Firestore
  await db.collection("_socialXPosts").add({
    tweetId,
    tweetUrl,
    businessTweetId,
    businessTweetUrl,
    text: cleanText,
    inReplyToId: inReplyToId || null,
    accountType,
    postedAt: admin.firestore.FieldValue.serverTimestamp(),
    author: accountType === "business" ? "Diaspora Nearby" : "Peter Swai | Diaspora Nearby",
  });

  return {
    success: true,
    tweetId,
    tweetUrl,
    businessTweetId,
    businessTweetUrl,
    text: cleanText,
  };
}

// ── Post Sequential X Thread ──
async function postThread(tweetsArray) {
  await ensureSocialConfigEnv();

  if (!Array.isArray(tweetsArray) || tweetsArray.length === 0) {
    throw new Error("Thread must contain an array of tweet texts.");
  }

  const posted = [];
  let previousTweetId = null;

  for (let i = 0; i < tweetsArray.length; i++) {
    const text = tweetsArray[i].trim();
    const res = await postTweet(text, previousTweetId, { postToBusiness: i === 0 });
    posted.push(res);
    previousTweetId = res.tweetId;
    // Small delay to ensure order and avoid momentary burst limits
    await new Promise((r) => setTimeout(r, 1200));
  }

  return {
    success: true,
    totalTweets: posted.length,
    firstTweetUrl: posted[0].tweetUrl,
    thread: posted,
  };
}

// ── Core Post to LinkedIn (Personal Profile + Company Page) ──
async function postToLinkedIn(text, options = {}) {
  await ensureSocialConfigEnv();

  if (!text || text.trim().length === 0) {
    throw new Error("LinkedIn post text cannot be empty.");
  }

  const cleanText = text.trim();
  if (cleanText.length > 3000) {
    throw new Error(`LinkedIn post exceeds 3000 characters (${cleanText.length}/3000).`);
  }

  // 1. Fetch OAuth token from Firestore config (or fallback to env vars)
  let accessToken = process.env.LINKEDIN_ACCESS_TOKEN || null;
  let orgAccessToken = process.env.LINKEDIN_ORG_ACCESS_TOKEN || null;
  let memberSub = process.env.LINKEDIN_MEMBER_SUB || null;

  const configDoc = await db.collection("_internalConfig").doc("linkedin").get();
  if (configDoc.exists) {
    const data = configDoc.data();
    accessToken = data.accessToken || accessToken;
    orgAccessToken = data.orgAccessToken || orgAccessToken;
    memberSub = data.memberSub || memberSub;
    const expiresAt = data.expiresAt;
    const expiry = expiresAt?.toDate ? expiresAt.toDate() : (expiresAt ? new Date(expiresAt) : null);

    // Attempt silent auto-refresh if expired and refreshToken is present
    if (expiry && expiry < new Date()) {
      const refreshToken = data.refreshToken || process.env.LINKEDIN_REFRESH_TOKEN;
      const clientId = process.env.LINKEDIN_CLIENT_ID;
      const clientSecret = process.env.LINKEDIN_CLIENT_SECRET;

      if (refreshToken && clientId && clientSecret) {
        console.log("🔄 LinkedIn access token expired — attempting silent refresh...");
        try {
          const refreshRes = await axios.post(
            "https://www.linkedin.com/oauth/v2/accessToken",
            null,
            {
              params: {
                grant_type: "refresh_token",
                refresh_token: refreshToken,
                client_id: clientId,
                client_secret: clientSecret,
              },
              headers: { "Content-Type": "application/x-www-form-urlencoded" },
            }
          );

          const {
            access_token: newAccessToken,
            expires_in: expiresIn,
            refresh_token: newRefreshToken,
          } = refreshRes.data;
          const newExpiry = new Date(Date.now() + (expiresIn || 5184000) * 1000);
          accessToken = newAccessToken;

          await db.collection("_internalConfig").doc("linkedin").set(
            {
              accessToken: newAccessToken,
              expiresAt: newExpiry,
              ...(newRefreshToken ? { refreshToken: newRefreshToken } : {}),
              lastRefreshedAt: admin.firestore.FieldValue.serverTimestamp(),
            },
            { merge: true }
          );
          console.log(`✅ LinkedIn token refreshed silently. New expiry: ${newExpiry.toISOString()}`);
        } catch (refreshErr) {
          throw new Error(
            `LinkedIn access token expired and refresh failed: ${
              refreshErr.response?.data?.error_description || refreshErr.message
            }`
          );
        }
      } else {
        throw new Error("LinkedIn access token expired. Re-authentication required.");
      }
    }
  }

  if (!accessToken) {
    throw new Error(
      "LinkedIn account not connected in Firestore _internalConfig/linkedin (or LINKEDIN_ACCESS_TOKEN in .env)."
    );
  }

  // Resolve memberSub via /v2/userinfo or /v2/me if we have an accessToken but no memberSub yet
  if (!memberSub) {
    try {
      const profileRes = await axios.get("https://api.linkedin.com/v2/userinfo", {
        headers: { Authorization: `Bearer ${accessToken}` },
      });
      memberSub = profileRes.data?.sub;
      if (memberSub) {
        await db.collection("_internalConfig").doc("linkedin").set(
          {
            accessToken,
            memberSub,
            memberName: profileRes.data?.name || "Peter Swai",
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          { merge: true }
        );
      }
    } catch (_uErr) {
      try {
        const meRes = await axios.get("https://api.linkedin.com/v2/me", {
          headers: { Authorization: `Bearer ${accessToken}` },
        });
        memberSub = meRes.data?.id;
        if (memberSub) {
          const name = [meRes.data?.localizedFirstName, meRes.data?.localizedLastName]
            .filter(Boolean)
            .join(" ") || "Peter Swai";
          await db.collection("_internalConfig").doc("linkedin").set(
            {
              accessToken,
              memberSub,
              memberName: name,
              updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            },
            { merge: true }
          );
        }
      } catch (meErr) {
        console.warn("Could not auto-resolve LinkedIn memberSub:", meErr.response?.data || meErr.message);
      }
    }
  }

  // 2. Post to Personal Profile (if memberSub is available)
  let postId = "unknown";
  let postUrl = null;
  const baseShareContent = {
    "com.linkedin.ugc.ShareContent": {
      shareCommentary: { text: cleanText },
      shareMediaCategory: "NONE",
    },
  };

  if (memberSub) {
    const postPayload = {
      author: `urn:li:person:${memberSub}`,
      lifecycleState: "PUBLISHED",
      specificContent: baseShareContent,
      visibility: { "com.linkedin.ugc.MemberNetworkVisibility": "PUBLIC" },
    };

    const personalRes = await axios.post("https://api.linkedin.com/v2/ugcPosts", postPayload, {
      headers: {
        Authorization: `Bearer ${accessToken}`,
        "Content-Type": "application/json",
        "X-Restli-Protocol-Version": "2.0.0",
      },
    });

    postId = personalRes.headers["x-restli-id"] || personalRes.data?.id || "unknown";
    postUrl = `https://www.linkedin.com/feed/update/${postId}`;
  }

  // 3. Cross-post to Organization (Diaspora Nearby Company Page) if configured
  const orgId = process.env.LINKEDIN_ORG_ID || "112722655";
  const effectiveOrgToken = orgAccessToken || accessToken;
  let orgPostUrl = null;
  if (options.postToOrg !== false && orgId && effectiveOrgToken) {
    try {
      const orgPayload = {
        author: `urn:li:organization:${orgId}`,
        lifecycleState: "PUBLISHED",
        specificContent: baseShareContent,
        visibility: { "com.linkedin.ugc.MemberNetworkVisibility": "PUBLIC" },
      };
      const orgRes = await axios.post("https://api.linkedin.com/v2/ugcPosts", orgPayload, {
        headers: {
          Authorization: `Bearer ${effectiveOrgToken}`,
          "Content-Type": "application/json",
          "X-Restli-Protocol-Version": "2.0.0",
        },
      });
      const orgPostId = orgRes.headers["x-restli-id"] || orgRes.data?.id || "unknown";
      orgPostUrl = `https://www.linkedin.com/feed/update/${orgPostId}`;
      if (!postUrl) {
        postId = orgPostId;
        postUrl = orgPostUrl;
      }
    } catch (orgErr) {
      console.warn("LinkedIn organization cross-post error:", orgErr.response?.data?.message || orgErr.message);
      if (!postUrl) {
        throw orgErr;
      }
    }
  }

  // Log to Firestore
  await db.collection("_socialLinkedInPosts").add({
    postId,
    postUrl,
    orgPostUrl,
    text: cleanText,
    postedAt: admin.firestore.FieldValue.serverTimestamp(),
    author: memberSub || `organization:${orgId}`,
  });

  return { success: true, postId, postUrl, orgPostUrl };
}

// ── Ensure Base Blockchain Terminology & Official #$DIASPORA Hashtag ──
function enforceBaseBlockchainTerminology(text) {
  if (!text) return text;
  let updated = text
    .replace(/\bBase\s+L2\b/gi, "Base Blockchain")
    .replace(/\bBase\s+Layer\s*2\b/gi, "Base Blockchain")
    .replace(/\bon\s+Base\b(?!\s+Blockchain)/gi, "on Base Blockchain")
    .replace(/\bvia\s+\$DIASPORA\s+on\s+Base\b(?!\s+Blockchain)/gi, "via $DIASPORA on Base Blockchain")
    .replace(/#BaseL2\b/gi, "#BaseBlockchain")
    .replace(/#Base\b(?!Blockchain)/gi, "#BaseBlockchain")
    .replace(/(^|\s)#DIASPORA\b/g, "$1#$DIASPORA");

  if (!updated.includes("#$DIASPORA")) {
    updated = `${updated.trim()} #$DIASPORA`;
  }
  return updated;
}

// ── Diaspora Nearby AI Content Generator ──
async function generateDiasporaContent(options = {}) {
  await ensureSocialConfigEnv();

  const geminiKey = process.env.GEMINI_API_KEY;
  const nvidiaKey = process.env.NVIDIA_API_KEY;

  if (!geminiKey && !nvidiaKey) {
    throw new Error("Neither GEMINI_API_KEY nor NVIDIA_API_KEY is configured in .env");
  }

  const platform = (options.platform || "x").toLowerCase(); // "x", "linkedin", "facebook", "instagram"
  const topic = options.topic || "diaspora_discovery_connection_and_dual_identity_wealth";
  const corridor = options.corridor || (topic.includes("[TZ_ABROAD]") ? "tz_abroad" : topic.includes("[EXPAT_IN_TZ]") ? "expat_in_tz" : "global");
  const lang = options.lang || (corridor === "tz_abroad" ? "sw" : "en");

  const corridorGuidance =
    corridor === "tz_abroad"
      ? `
TARGET AUDIENCE & LANGUAGE REQUIREMENT (COHORT A — TANZANIANS LIVING OUTSIDE TANZANIA):
- Write MOSTLY IN KISWAHILI (warm, authentic Tanzanian Kiswahili addressing "Watanzania waishio nje ya Tanzania / Ughaibuni / Diaspora" in the US, UK, UAE/Dubai, South Africa, Kenya, Canada, Europe, and China).
- Highlight the 5 everyday utilities built for Watanzania:
  1. Nearby Discovery: Gundua Watanzania walio karibu nawe katika mji au mtaa unaoishi.
  2. Nearby Notification: Pata taarifa za papo hapo Mtanzania mwenzako anapokuwa karibu nawe.
  3. Live Radio: Sikiliza redio za nyumbani Tanzania na diaspora mubashara (24/7) ndani ya app.
  4. Ubuntu Emergency Fund: Mfuko wa dharura na msiba wa kusaidiana kwa uwazi wakati wa matatizo.
  5. DDI Loans (Mikopo ya DDI): Mikopo ya kuwezesha miradi na uwekezaji kupitia hazina ya jamii yetu.
- On Facebook and Instagram, end with a Kiswahili Comment-to-DM Roll-Call hook: "Andika mkoa uliotoka TZ + mji ulipo sasa kwenye comment (mfano: IRINGA -> HOUSTON, ARUSHA -> LONDON, DAR -> DUBAI) tukutumie link ya kujiunga moja kwa moja kwenye DM! 👉 https://diasporanearby.com/invite"
`
      : corridor === "expat_in_tz"
      ? `
TARGET AUDIENCE & LANGUAGE REQUIREMENT (COHORT B — NON-TANZANIANS / EXPATS LIVING INSIDE TANZANIA):
- Target international expats, diplomats, professionals, regional diaspora, and digital nomads who are NOT from Tanzania but live inside Tanzania (Dar es Salaam — Masaki/Oysterbay/Upanga/Mikocheni, Arusha — UN/EAC/NGOs, and Zanzibar — Stone Town/Paje/Nungwi).
- Language: ${
          lang && lang !== "en"
            ? `Write in ${lang.toUpperCase()} paired with clear English so speakers of that native language in Tanzania feel immediately at home.`
            : "Write in warm, inclusive International English (and optionally weave in multicultural greetings like Bienvenue / 欢迎 / नमस्ते / مرحباً / Willkommen / Karibu)."
        }
- Emphasize the 5 core utilities in Tanzania:
  1. Nearby Discovery: Instantly find compatriots from your home country nearby in Dar, Arusha, or Zanzibar.
  2. Nearby Notification: Real-time proximity alerts when someone from home is in your neighborhood.
  3. Live Radio: Stream 24/7 radio stations from your home country and local diaspora hubs.
  4. Ubuntu Emergency Fund: Transparent community mutual-aid & emergency support fund.
  5. DDI Loans: Community-backed Diaspora Direct Investment loans to grow cross-border ventures.
- On Facebook and Instagram, end with a Comment-to-DM Roll-Call hook: "Living in Dar es Salaam, Arusha, or Zanzibar? Comment your Home Country + City below and we'll DM your Founding Member invite link! 👉 https://diasporanearby.com/invite"
`
      : "";

  const platformInstructions = {
    x: `
- Write a punchy, relatable tweet strictly under 245 characters about "${topic}".
- Focus strictly on the 5 core utilities of Diaspora Nearby: Nearby Discovery, Nearby Notification, Live Radio, Ubuntu Emergency Fund, and DDI Loans.
- Must be 1 to 2 complete, conversational sentences. Include #DiasporaNearby #FindYourPeople #$DIASPORA
- Output ONLY the raw tweet text. No introductory remarks, no quotes, no markdown headers.
`,
    linkedin: `
- Write an engaging LinkedIn post (around 900-1400 characters) on "${topic}".
- Focus clearly on the 5 core utilities of Diaspora Nearby:
  1. Nearby Discovery (finding compatriots nearby in your city)
  2. Nearby Notification (real-time proximity alerts when a fellow compatriot is nearby)
  3. Live Radio (streaming homeland & diaspora radio 24/7)
  4. Ubuntu Emergency Fund (transparent community emergency & bereavement mutual-aid fund)
  5. DDI Loans (Diaspora Direct Investment community-backed loans)
- Include short paragraphs, clear structure, and a call to action to join at https://diasporanearby.com/invite
- Include #DiasporaNearby #FindYourPeople #$DIASPORA #Ubuntu
- Output ONLY raw post text.
`,
    facebook: `
- Write an authentic, warm, community-focused Facebook Page post (around 450-800 characters) on "${topic}".
- Start with a relatable human roll-call hook ("Who from your home town is right down the street from you right now?"), then highlight the 5 core utilities: Nearby Discovery, Nearby Notification, Live Homeland Radio, Ubuntu Emergency Fund, and DDI Loans.
- Include a clear call to action to comment their Home + Host City and explore https://diasporanearby.com/invite along with #DiasporaNearby #FindYourPeople #$DIASPORA
- Output ONLY raw post text. No introductory remarks, no markdown headers.
`,
    instagram: `
- Write an inspiring Instagram caption (around 400-700 characters) on "${topic}".
- Hook the reader in the first line about finding your people nearby, followed by the 5 core utilities:
  📍 Nearby Discovery
  🔔 Nearby Notification
  📻 Live Homeland Radio
  🤝 Ubuntu Emergency Fund
  🏦 DDI Community Loans
- End with a call to action to comment their Home + Host City and visit diasporanearby.com/invite along with #DiasporaNearby #FindYourPeople #$DIASPORA #Ubuntu
- Output ONLY raw caption text.
`,
  };

  const systemInstructions = `You are the authentic executive voice of Peter Swai, Founder & CEO of Diaspora Nearby.
Peter Swai lived across the diaspora for 25+ years (Tanzania -> San Francisco -> Santa Monica -> Iowa -> DC -> Phoenix -> Iowa -> now returning home to Tanzania).

STRICT MESSAGING SCOPE (5 CORE UTILITIES ONLY):
All posts MUST focus strictly on these 5 immediate everyday utilities:
1. NEARBY DISCOVERY: Discover verified compatriots from your home country or region who live or work right near you in your city or neighborhood.
2. NEARBY NOTIFICATION: Real-time proximity notifications that alert you when someone from your home country/town is nearby so you never pass a brother or sister on the street without knowing.
3. LIVE RADIO: Stream live homeland and diaspora radio stations 24/7 right inside the app to stay connected to home wherever you are in the world.
4. UBUNTU EMERGENCY FUND: A transparent, community-governed emergency & bereavement (msiba) mutual-aid fund so no diaspora member faces a crisis alone (replacing chaotic WhatsApp hat-passing with instant collective support).
5. DDI LOANS (Diaspora Direct Investment Loans): Community-backed micro and project loans powered by community treasuries to help members build businesses, homes, and cross-border investments.

CRITICAL GUARDRAILS:
1. Keep language warm, human, and immediately understandable to everyday diaspora members—avoid heavy crypto/blockchain jargon so anyone on WhatsApp or Facebook immediately understands the 5 practical utilities.
2. Always include the official hashtag #$DIASPORA in the hashtag block.

${corridorGuidance}
${platformInstructions[platform] || platformInstructions.linkedin}`;

  // 1. Try Gemini
  if (geminiKey) {
    try {
      const url = `https://generativelanguage.googleapis.com/v1beta/models/gemini-flash-latest:generateContent?key=${geminiKey}`;
      const userPrompt = `Write a ${platform} post on: "${topic}". Always refer to Base as "Base Blockchain". Start directly:`;

      const payload = {
        contents: [
          {
            parts: [
              {
                text: `${systemInstructions}\n\n${userPrompt}`,
              },
            ],
          },
        ],
        generationConfig: {
          temperature: 0.75,
        },
      };

      const res = await axios.post(url, payload);
      let text = res.data?.candidates?.[0]?.content?.parts?.[0]?.text?.trim() || "";
      text = text.replace(/^(here\s+is|here's)[^\n:]*[:\n]\s*/i, "");
      text = text.replace(/^["']/, "").replace(/["']$/, "").trim();
      text = enforceBaseBlockchainTerminology(text);
      if (platform === "x" && text.length > 280) {
        text = text.substring(0, 275) + "...";
      }
      return text;
    } catch (gErr) {
      console.warn("⚠️ Gemini generation failed, trying secondary engine:", gErr.message);
    }
  }

  // 2. Fallback to NVIDIA API if configured
  if (nvidiaKey) {
    try {
      const res = await axios.post(
        "https://integrate.api.nvidia.com/v1/chat/completions",
        {
          model: "meta/llama-3.3-70b-instruct",
          messages: [
            { role: "system", content: systemInstructions },
            { role: "user", content: `Write a ${platform} post on: "${topic}". Always use "Base Blockchain". Start directly:` },
          ],
          temperature: 0.7,
          max_tokens: 800,
        },
        {
          headers: {
            Authorization: `Bearer ${nvidiaKey}`,
            "Content-Type": "application/json",
          },
        }
      );
      let text = res.data?.choices?.[0]?.message?.content?.trim() || "";
      text = text.replace(/^(here\s+is|here's)[^\n:]*[:\n]\s*/i, "");
      text = text.replace(/^["']/, "").replace(/["']$/, "").trim();
      text = enforceBaseBlockchainTerminology(text);
      if (platform === "x" && text.length > 280) {
        text = text.substring(0, 275) + "...";
      }
      if (text) return text;
    } catch (nErr) {
      console.warn("⚠️ NVIDIA generation fallback warning, using curated corridor copy bank:", nErr.message);
    }
  }

  // 3. Zero-Failure Curated Corridor Copy Bank (Kiswahili TZ Abroad / Expat in TZ / Global)
  return buildCuratedCorridorCopy({ platform, corridor, lang });
}

function buildCuratedCorridorCopy({ platform = "facebook", corridor = "global", lang = "en" }) {
  const idx = Math.floor(Date.now() / (1000 * 60 * 10)) % 3;

  if (corridor === "tz_abroad") {
    const xPool = [
      "🇹🇿 Watanzania waishio nje ya TZ! Gundua Watanzania walio karibu nawe, sikiliza Redio za TZ live, na jiunge na Mfuko wa Dharura wa Ubuntu & Mikopo ya DDI 👉 https://diasporanearby.com/invite #DiasporaNearby #$DIASPORA",
      "🇹🇿 Popote ulipo ughaibuni (US, UK, Dubai, SA, Kenya, Canada) — pata taarifa Mtanzania akiwa karibu nawe, sikiliza redio za nyumbani & shiriki Mikopo ya DDI! 👉 https://diasporanearby.com/invite #DiasporaNearby #$DIASPORA",
      "🇹🇿 Kutoka Dar, Arusha, Iringa, Moshi na Mwanza hadi Houston, London na Dubai: Nearby Discovery, Live Radio, Ubuntu Emergency Fund & DDI Loans kwenye Diaspora Nearby! 👉 https://diasporanearby.com/invite #$DIASPORA",
    ];
    const longSw = [
      "🇹🇿 Habari Watanzania wenzangu waishio nje ya Tanzania na mikoani! 🌍\n\nPopote ulipo — Marekani (Houston, DC/DMV, Dallas), Uingereza (London, Reading), Dubai/UAE, Afrika Kusini, Kenya, Canada au Tanzania — Diaspora Nearby inakupa huduma 5 muhimu kila siku:\n\n1️⃣ Nearby Discovery: Gundua Watanzania walio karibu nawe mji au mtaa unaoishi.\n2️⃣ Nearby Notification: Pata taarifa za papo hapo Mtanzania mwenzako anapokuwa karibu nawe.\n3️⃣ Live Radio: Sikiliza redio za nyumbani Tanzania na diaspora mubashara (24/7) ndani ya app.\n4️⃣ Ubuntu Emergency Fund: Mfuko wa dharura na msiba wa kusaidiana kwa uwazi wakati wa matatizo.\n5️⃣ DDI Loans (Mikopo ya DDI): Mikopo ya kuwezesha miradi na uwekezaji kupitia hazina ya jamii yetu.\n\n💬 Andika mkoa uliotoka TZ + mji ulipo sasa kwenye comment (mfano: IRINGA -> HOUSTON, ARUSHA -> LONDON, DAR -> DUBAI) tukutumie link kwenye DM!\n👉 https://diasporanearby.com/invite\n\n#DiasporaNearby #WatanzaniaUghaibuni #FindYourPeople #Ubuntu #$DIASPORA",
      "🇹🇿 Nyumbani ni nyumbani hata ukiwa ughaibuni! 🌍\n\nJe, unajua kuna Watanzania wangapi mtaa au mji unaoishi sasa hivi? Kupitia Diaspora Nearby unapata:\n• 📍 Nearby Discovery & 🔔 Nearby Notification (fahamu Mtanzania mwenzako akiwa karibu)\n• 📻 Live Homeland Radio (sikiliza redio za nyumbani TZ saa 24)\n• 🤝 Ubuntu Emergency Fund (mfuko wa dharura na msiba wa kusaidiana kama ndugu)\n• 🏦 DDI Loans (mikopo ya jamii kwa ajili ya uwekezaji na miradi)\n\n💬 Comment mkoa wako wa TZ + mji ulipo sasa hapa chini tukutumie link ya kujiunga kwenye DM!\n👉 https://diasporanearby.com/invite\n\n#DiasporaNearby #TanzaniaDiaspora #FindYourPeople #Ubuntu #$DIASPORA",
      "🇹🇿 Roll Call ya Watanzania! Umetoka mkoa gani Tanzania na sasa upo mji gani?\n\nUngana na Watanzania wenzako kwenye Diaspora Nearby ufurahie:\n📍 Nearby Discovery & 🔔 Nearby Notification\n📻 Redio za Tanzania Mubashara (Live Radio)\n🤝 Mfuko wa Dharura wa Ubuntu (Ubuntu Emergency Fund)\n🏦 Mikopo ya Uwekezaji wa Jamii (DDI Loans)\n\n💬 Andika mkoa wako + mji ulipo kwenye comment tukutumie link kwenye DM!\n👉 https://diasporanearby.com/invite\n\n#DiasporaNearby #FindYourPeople #Ubuntu #$DIASPORA",
    ];
    return platform === "x" ? xPool[idx] : longSw[idx];
  }

  if (corridor === "expat_in_tz") {
    if (lang === "fr") {
      return platform === "x"
        ? "🇫🇷🌍 Vous vivez en Tanzanie (Dar, Arusha, Zanzibar) ? Découverte à proximité, alertes en temps réel, radio en direct, Fonds d'urgence Ubuntu & prêts DDI 👉 https://diasporanearby.com/invite #DiasporaNearby #$DIASPORA"
        : "🇫🇷🌍 Appel à la communauté francophone et aux expatriés vivant en Tanzanie (Dar es Salaam, Arusha, Zanzibar) !\n\nAvec Diaspora Nearby, profitez de 5 services essentiels :\n1️⃣ Nearby Discovery : Découvrez vos compatriotes vivant à proximité.\n2️⃣ Nearby Notification : Alertes instantanées lorsqu'un compatriote est près de vous.\n3️⃣ Live Radio : Écoutez les radios de votre pays d'origine en direct 24h/24.\n4️⃣ Ubuntu Emergency Fund : Fonds d'entraide et d'urgence communautaire transparent.\n5️⃣ DDI Loans : Prêts communautaires d'investissement direct de la diaspora.\n\n💬 Commentez votre pays d'origine + votre ville (ex: DAR, ARUSHA, ZANZIBAR) et nous vous enverrons votre lien d'invitation en DM !\n👉 https://diasporanearby.com/invite\n\n#DiasporaNearby #ExpatsInTanzania #Ubuntu #$DIASPORA";
    }
    const xExpat = [
      "🌍 Living in Dar es Salaam, Arusha, or Zanzibar? Get Nearby Discovery, Nearby Notifications, Live Homeland Radio, Ubuntu Emergency Fund & DDI Loans on Diaspora Nearby 👉 https://diasporanearby.com/invite #DiasporaNearby #$DIASPORA",
      "🌍➡️🇹🇿 Expats & diaspora in Tanzania! Find compatriots nearby in Dar, Arusha & Zanzibar, stream home radio live, and access the Ubuntu Emergency Fund & DDI Loans 👉 https://diasporanearby.com/invite #DiasporaNearby #$DIASPORA",
      "🌍 Never land alone in Tanzania. Nearby Discovery, Real-Time Proximity Alerts, 24/7 Home Radio, Ubuntu Emergency Fund & DDI Community Loans 👉 https://diasporanearby.com/invite #DiasporaNearby #$DIASPORA",
    ];
    const longExpat = [
      "🌍➡️🇹🇿 Living in Dar es Salaam, Arusha, or Zanzibar from abroad?\n\nWhether you are from Kenya, South Africa, DRC, Uganda, the UK, US, India, China, or Europe — Diaspora Nearby gives you 5 everyday community utilities in Tanzania:\n\n1️⃣ Nearby Discovery: Instantly find compatriots from your home country in Masaki, Oysterbay, Upanga, Arusha, or Zanzibar.\n2️⃣ Nearby Notification: Real-time proximity alerts when someone from home is nearby.\n3️⃣ Live Radio: Stream 24/7 radio stations from your home country and diaspora hubs.\n4️⃣ Ubuntu Emergency Fund: Transparent community mutual-aid & emergency support fund.\n5️⃣ DDI Loans: Community-backed Diaspora Direct Investment loans for your projects.\n\n💬 Comment your Home Country + City below (e.g., 'KENYA -> DAR' or 'UK -> ARUSHA') and we'll DM your invite link!\n👉 https://diasporanearby.com/invite\n\n#DiasporaNearby #ExpatsInTanzania #DarEsSalaam #Arusha #Zanzibar #$DIASPORA",
      "🌍 Quick Roll Call for the International & Expat Community in Tanzania (Dar · Arusha · Zanzibar)! 🇹🇿\n\nBienvenue · 欢迎 · नमस्ते · مرحباً · Willkommen · Karibu!\n\nConnect with people from your home country right in your neighborhood on Diaspora Nearby:\n📍 Nearby Discovery & 🔔 Nearby Notification\n📻 Live Homeland Radio (24/7)\n🤝 Ubuntu Emergency Fund\n🏦 DDI Community Loans\n\n💬 Drop your Home Country + City in the comments to receive your Founding Member invite in your DM!\n👉 https://diasporanearby.com/invite\n\n#DiasporaNearby #FindYourPeople #Ubuntu #$DIASPORA",
      "🌍➡️🇹🇿 Never land alone in Tanzania.\n\nDiscover compatriots from home right in your neighborhood, get real-time nearby notifications, stream live homeland radio, and back each other through the Ubuntu Emergency Fund and DDI Loans.\n\n💬 Comment 'DAR', 'ARUSHA', or 'ZANZIBAR' below and we'll DM your direct invite link!\n👉 https://diasporanearby.com/invite\n\n#DiasporaNearby #ExpatsInDar #Arusha #Zanzibar #$DIASPORA",
    ];
    return platform === "x" ? xExpat[idx] : longExpat[idx];
  }

  const xGlobal = [
    "🌍 5 everyday utilities for every diaspora community: Nearby Discovery, Nearby Notification, Live Homeland Radio, Ubuntu Emergency Fund & DDI Loans 👉 https://diasporanearby.com/invite #DiasporaNearby #FindYourPeople #$DIASPORA",
    "🌍 Never pass a compatriot on the street without knowing. Get Nearby Discovery, Proximity Alerts, 24/7 Homeland Radio, Ubuntu Emergency Fund & DDI Loans 👉 https://diasporanearby.com/invite #DiasporaNearby #$DIASPORA",
    "🌍 From finding compatriots down the street to backing each other with the Ubuntu Emergency Fund & DDI Loans — join Diaspora Nearby today 👉 https://diasporanearby.com/invite #DiasporaNearby #Ubuntu #$DIASPORA",
  ];
  const longGlobal = [
    "🌍 Who from your home town is right down the street from you right now?\n\nDiaspora Nearby brings 5 essential utilities to every diaspora community worldwide:\n📍 Nearby Discovery — Find compatriots from your home country in your city or neighborhood\n🔔 Nearby Notification — Real-time alerts when someone from home is nearby\n📻 Live Radio — Stream homeland & diaspora radio 24/7 inside the app\n🤝 Ubuntu Emergency Fund — Transparent community emergency & bereavement mutual-aid fund\n🏦 DDI Loans — Community-backed Diaspora Direct Investment loans\n\n👉 Join your city roll-call today: https://diasporanearby.com/invite\n\n#DiasporaNearby #FindYourPeople #Ubuntu #$DIASPORA",
    "🌍 Replacing scattered WhatsApp groups with 5 real diaspora utilities:\n\n1️⃣ Nearby Discovery\n2️⃣ Nearby Notification\n3️⃣ Live Homeland Radio (24/7)\n4️⃣ Ubuntu Emergency Fund\n5️⃣ DDI Community Loans\n\n👉 Check who from home is near you: https://diasporanearby.com/invite\n\n#DiasporaNearby #FindYourPeople #Ubuntu #$DIASPORA",
    "🌍 Never land alone in a new city.\n\nDiscover compatriots nearby, get real-time proximity notifications, listen to live radio from home, and support one another through the Ubuntu Emergency Fund and DDI Loans.\n\n👉 https://diasporanearby.com/invite\n\n#DiasporaNearby #FindYourPeople #$DIASPORA",
  ];
  return platform === "x" ? xGlobal[idx] : longGlobal[idx];
}

// ── Cloud Functions (HTTPS & Scheduled) ──

/**
 * HTTPS: Publish to X (Single tweet or thread)
 * POST /xMarketingPublish
 * Body: { text?: string, thread?: string[], inReplyToId?: string, accountType?: "personal"|"business" }
 */
exports.xMarketingPublish = functions.https.onRequest(async (req, res) => {
  if (req.method !== "POST") {
    res.status(405).json({ error: "Method not allowed. Use POST." });
    return;
  }

  try {
    await ensureSocialConfigEnv();
    const { text, thread, inReplyToId, accountType } = req.body;

    if (Array.isArray(thread) && thread.length > 0) {
      const result = await postThread(thread);
      res.json(result);
      return;
    }

    if (!text) {
      res.status(400).json({ error: "Missing 'text' or 'thread' in request body." });
      return;
    }

    const result = await postTweet(text, inReplyToId, { accountType });
    res.json(result);
  } catch (err) {
    console.error("xMarketingPublish error:", err.message);
    res.status(500).json({ error: err.message });
  }
});

/**
 * HTTPS: Publish to LinkedIn (or configure LinkedIn OAuth credentials)
 * POST /postToLinkedIn
 * Body:
 *   - To post: { text: string, postToOrg?: boolean }
 *   - To save/connect OAuth token: { configureToken: { accessToken, refreshToken?, expiresIn?, memberSub? } }
 *   - To exchange OAuth code: { exchangeCode: { code, redirectUri } }
 */
exports.postToLinkedIn = functions.https.onRequest(async (req, res) => {
  await ensureSocialConfigEnv();

  if (req.method === "GET") {
    // Support OAuth 2.0 callback or auth URL generation
    const { code, action, state: queryState } = req.query;
    const isOrgOAuth = req.query.org === "true" || (typeof queryState === "string" && queryState.startsWith("org_"));
    const clientId = isOrgOAuth
      ? process.env.LINKEDIN_ORG_CLIENT_ID || process.env.LINKEDIN_CLIENT_ID
      : process.env.LINKEDIN_CLIENT_ID;
    const clientSecret = isOrgOAuth
      ? process.env.LINKEDIN_ORG_CLIENT_SECRET || process.env.LINKEDIN_CLIENT_SECRET
      : process.env.LINKEDIN_CLIENT_SECRET;
    const redirectUri =
      req.query.redirectUri ||
      process.env.LINKEDIN_REDIRECT_URI ||
      `https://us-central1-${process.env.GCLOUD_PROJECT || "diaspora-nearby-a3dac"}.cloudfunctions.net/postToLinkedIn`;

    if (action === "authUrl") {
      if (!clientId) {
        res.status(400).json({ error: "LINKEDIN_CLIENT_ID is not set." });
        return;
      }
      const scope = isOrgOAuth
        ? "w_organization_social r_organization_social"
        : "openid profile email w_member_social";
      const statePrefix = isOrgOAuth ? "org_" : "personal_";
      const state = statePrefix + Math.random().toString(36).substring(2, 15);
      const authUrl = `https://www.linkedin.com/oauth/v2/authorization?response_type=code&client_id=${clientId}&redirect_uri=${encodeURIComponent(
        redirectUri
      )}&scope=${encodeURIComponent(scope)}&state=${state}`;
      res.json({ authUrl, redirectUri, scope, isOrgOAuth, clientId });
      return;
    }

    if (code) {
      try {
        const tokenRes = await axios.post("https://www.linkedin.com/oauth/v2/accessToken", null, {
          params: {
            grant_type: "authorization_code",
            code,
            redirect_uri: redirectUri,
            client_id: clientId,
            client_secret: clientSecret,
          },
          headers: { "Content-Type": "application/x-www-form-urlencoded" },
        });

        const { access_token: accessToken, expires_in: expiresIn, refresh_token: refreshToken } = tokenRes.data;
        const expiresAt = new Date(Date.now() + (expiresIn || 5184000) * 1000);

        if (isOrgOAuth) {
          await db.collection("_internalConfig").doc("linkedin").set(
            {
              orgAccessToken: accessToken,
              orgExpiresAt: expiresAt,
              ...(refreshToken ? { orgRefreshToken: refreshToken } : {}),
              orgClientId: clientId,
              orgUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
            },
            { merge: true }
          );
          res.json({
            success: true,
            message: `LinkedIn Business Page (org: ${process.env.LINKEDIN_ORG_ID || "112722655"}) token connected!`,
            orgExpiresAt: expiresAt.toISOString(),
          });
          return;
        }

        let memberSub = null;
        let memberName = "Peter Swai";
        try {
          const profileRes = await axios.get("https://api.linkedin.com/v2/userinfo", {
            headers: { Authorization: `Bearer ${accessToken}` },
          });
          memberSub = profileRes.data?.sub;
          memberName = profileRes.data?.name || memberName;
        } catch (_e) {
          const meRes = await axios.get("https://api.linkedin.com/v2/me", {
            headers: { Authorization: `Bearer ${accessToken}` },
          });
          memberSub = meRes.data?.id;
          memberName =
            [meRes.data?.localizedFirstName, meRes.data?.localizedLastName].filter(Boolean).join(" ") ||
            memberName;
        }

        await db.collection("_internalConfig").doc("linkedin").set(
          {
            accessToken,
            expiresAt,
            ...(refreshToken ? { refreshToken } : {}),
            memberSub,
            memberName,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          { merge: true }
        );

        res.json({
          success: true,
          message: `LinkedIn connected for ${memberName} (${memberSub})`,
          expiresAt: expiresAt.toISOString(),
        });
        return;
      } catch (err) {
        console.error("LinkedIn OAuth callback error:", err.response?.data || err.message);
        res.status(500).json({ error: err.response?.data || err.message });
        return;
      }
    }

    res.status(400).json({ error: "Use ?action=authUrl to get LinkedIn OAuth URL, or POST to publish." });
    return;
  }

  if (req.method !== "POST") {
    res.status(405).json({ error: "Method not allowed. Use POST or GET." });
    return;
  }

  try {
    const { text, postToOrg, configureToken } = req.body;

    if (configureToken && configureToken.accessToken) {
      let memberSub = configureToken.memberSub || null;
      let memberName = configureToken.memberName || "Peter Swai";
      if (!memberSub) {
        try {
          const profileRes = await axios.get("https://api.linkedin.com/v2/userinfo", {
            headers: { Authorization: `Bearer ${configureToken.accessToken}` },
          });
          memberSub = profileRes.data?.sub;
          memberName = profileRes.data?.name || memberName;
        } catch (_e) {
          const meRes = await axios.get("https://api.linkedin.com/v2/me", {
            headers: { Authorization: `Bearer ${configureToken.accessToken}` },
          });
          memberSub = meRes.data?.id;
          memberName =
            [meRes.data?.localizedFirstName, meRes.data?.localizedLastName].filter(Boolean).join(" ") ||
            memberName;
        }
      }
      const expiresIn = configureToken.expiresIn || 5184000; // default 60 days
      const expiresAt = new Date(Date.now() + expiresIn * 1000);
      await db.collection("_internalConfig").doc("linkedin").set(
        {
          accessToken: configureToken.accessToken,
          expiresAt,
          ...(configureToken.refreshToken ? { refreshToken: configureToken.refreshToken } : {}),
          memberSub,
          memberName,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true }
      );
      res.json({ success: true, memberSub, memberName, expiresAt: expiresAt.toISOString() });
      return;
    }

    if (!text) {
      res.status(400).json({ error: "Missing 'text' in request body." });
      return;
    }

    const result = await postToLinkedIn(text, { postToOrg: postToOrg !== false });
    res.json(result);
  } catch (err) {
    console.error("postToLinkedIn error:", err.message);
    res.status(500).json({ error: err.message });
  }
});

/**
 * Scheduled Cron: Daily Diaspora Nearby Social Authority Publication
 * Runs daily at 9:00 AM Central Time.
 */
exports.diasporaSocialCron = functions
  .runWith({ timeoutSeconds: 300, memory: "512MB" })
  .pubsub
  .schedule("every day 09:00")
  .timeZone("America/Chicago")
  .onRun(async (_context) => {
    console.log("⏰ Running Diaspora Nearby Daily Social Cron...");
    return await executeDailySocialPublication();
  });

/**
 * HTTPS: Force Daily Social Cron (Admin on-demand trigger)
 */
exports.forceDiasporaSocialCron = functions
  .runWith({ timeoutSeconds: 300, memory: "512MB" })
  .https.onRequest(async (req, res) => {
    try {
      const overrides = {
        corridor: req.body?.corridor || req.query?.corridor || null,
        lang: req.body?.lang || req.query?.lang || null,
        topic: req.body?.topic || req.query?.topic || null,
      };
      const result = await executeDailySocialPublication(overrides);
      res.json({ success: true, message: "Diaspora social publication executed!", result });
    } catch (err) {
      console.error("forceDiasporaSocialCron error:", err.message);
      res.status(500).json({ error: err.message });
    }
  });

// Helper that executes the automated publication flow
async function executeDailySocialPublication(overrides = {}) {
  await ensureSocialConfigEnv();

  const topics = [
    "[TZ_ABROAD] Watanzania waishio nje ya Tanzania (Marekani, UK, Dubai, Afrika Kusini, Kenya, Canada): Gundua Watanzania walio karibu nawe (Nearby Discovery & Notification), sikiliza Redio za TZ live, na jiunge na Mfuko wa Dharura wa Ubuntu na Mikopo ya DDI",
    "[TZ_ABROAD] Kutoka Dar, Arusha, Iringa, Moshi na Mwanza hadi Houston, London na Dubai: Jinsi Diaspora Nearby inavyowaunganisha Watanzania kupitia Nearby Discovery, Nearby Notification, Live Radio, Ubuntu Emergency Fund, na DDI Loans",
    "[EXPAT_IN_TZ] Living in Dar es Salaam, Arusha, or Zanzibar from abroad? Get Nearby Discovery, Real-Time Proximity Notifications, 24/7 Live Homeland Radio, Ubuntu Emergency Fund, and DDI Community Loans",
    "[EXPAT_IN_TZ] From Masaki & Oysterbay in Dar to Arusha & Zanzibar: How international expats and diaspora in Tanzania find compatriots nearby, stream homeland radio, and access the Ubuntu Emergency Fund & DDI Loans",
    "Nearby Discovery & Nearby Notification: How real-time proximity alerts help diaspora members discover compatriots right down the street in any city worldwide",
    "Live Homeland Radio 24/7: Staying connected to the sounds, news, and music of home from anywhere in the diaspora while connecting with peers nearby",
    "Ubuntu Emergency Fund: Replacing chaotic WhatsApp bereavement and emergency hat-passing with a transparent, community-governed mutual-aid fund",
    "DDI Loans (Diaspora Direct Investment Loans): How community-backed loans empower diaspora members to build businesses, homes, and cross-border projects",
  ];

  const selectedTopic =
    overrides.topic ||
    (overrides.corridor === "tz_abroad"
      ? topics[0]
      : overrides.corridor === "expat_in_tz"
      ? topics[2]
      : topics[Math.floor(Math.random() * topics.length)]);
  const corridor =
    overrides.corridor ||
    (selectedTopic.includes("[TZ_ABROAD]")
      ? "tz_abroad"
      : selectedTopic.includes("[EXPAT_IN_TZ]")
      ? "expat_in_tz"
      : "global");
  const lang = overrides.lang || (corridor === "tz_abroad" ? "sw" : "en");

  // Check if Unified API (Ayrshare) is available for 6-platform broadcast
  if (process.env.AYRSHARE_API_KEY) {
    try {
      const contentStudio = require("./content_studio");
      const unifiedPublisher = require("./unified_social_publisher");
      console.log(`📡 AYRSHARE_API_KEY detected. Generating multimedia content pack on: "${selectedTopic}"...`);
      const pack = await contentStudio.generateDailyContentPack({ topic: selectedTopic });
      const broadcastRes = await unifiedPublisher.broadcastUnifiedPost({
        post: pack.textCopy.x + "\n\n" + pack.textCopy.linkedIn.slice(0, 300) + "...\n\n👉 Join: https://diasporanearby.com",
        videoTitle: pack.shortVideoStoryboard.title,
      });
      return { topic: selectedTopic, corridor, lang, type: "unified_broadcast", result: broadcastRes };
    } catch (unifiedErr) {
      console.warn("⚠️ Unified broadcast failed, falling back to direct native publishers:", unifiedErr.message);
    }
  }

  // ── 1. Native Direct Post to X (Twitter) ──
  let xResult = null;
  try {
    const xContent = await generateDiasporaContent({ platform: "x", topic: selectedTopic, corridor, lang });
    xResult = await postTweet(xContent);
    console.log(`✅ [Free Native] X post published: ${xResult.tweetUrl}`);
  } catch (xErr) {
    console.error("X publishing error:", xErr.message);
    xResult = { error: xErr.message };
  }

  // ── 2. Native Direct Post to LinkedIn ──
  let linkedInResult = null;
  try {
    const linkedInContent = await generateDiasporaContent({ platform: "linkedin", topic: selectedTopic, corridor, lang });
    linkedInResult = await postToLinkedIn(linkedInContent, { postToOrg: true });
    console.log(`✅ [Free Native] LinkedIn post published: ${linkedInResult.postUrl}`);
  } catch (liErr) {
    console.error("LinkedIn publishing error:", liErr.message);
    linkedInResult = { error: liErr.message };
  }

  // ── 3. Native Direct Post to Facebook Page (AI-generated copy) ──
  let facebookResult = null;
  const metaPublisher = require("./meta_publisher");
  const rotatingCardUrl = metaPublisher.getRotatingVisualCardUrl(selectedTopic);
  if (process.env.META_PAGE_ACCESS_TOKEN) {
    try {
      const fbMessage = await generateDiasporaContent({ platform: "facebook", topic: selectedTopic, corridor, lang });
      facebookResult = await metaPublisher.postPhotoToFacebookPage({
        imageUrl: rotatingCardUrl,
        caption: fbMessage,
      });
      console.log(`✅ [Free Native] Facebook Page photo post published: ${facebookResult.postUrl}`);

      await db.collection("_socialFacebookPosts").add({
        postId: facebookResult.photoId || facebookResult.postId,
        postUrl: facebookResult.postUrl,
        imageUrl: rotatingCardUrl,
        text: fbMessage,
        topic: selectedTopic,
        corridor,
        lang,
        postedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    } catch (fbErr) {
      console.error("Facebook publishing error:", fbErr.message);
      facebookResult = { error: fbErr.message };
    }
  } else {
    facebookResult = { status: "skipped", reason: "META_PAGE_ACCESS_TOKEN not yet added to .env" };
  }

  // ── 4. Native Direct Post to Instagram Professional Account ──
  let instagramResult = null;
  if (process.env.META_PAGE_ACCESS_TOKEN) {
    try {
      const igCaption = await generateDiasporaContent({ platform: "instagram", topic: selectedTopic, corridor, lang });
      const igImageUrl = rotatingCardUrl;
      instagramResult = await metaPublisher.postPhotoToInstagram({
        imageUrl: igImageUrl,
        caption: igCaption,
      });
      console.log(`✅ [Free Native] Instagram post published: ${instagramResult.postUrl}`);

      await db.collection("_socialInstagramPosts").add({
        mediaId: instagramResult.mediaId,
        postUrl: instagramResult.postUrl,
        imageUrl: igImageUrl,
        caption: igCaption,
        topic: selectedTopic,
        postedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    } catch (igErr) {
      console.error("Instagram publishing error:", igErr.response?.data?.error?.message || igErr.message);
      instagramResult = { error: igErr.response?.data?.error?.message || igErr.message };
    }
  } else {
    instagramResult = { status: "skipped", reason: "META_PAGE_ACCESS_TOKEN not yet added to .env" };
  }

  return {
    topic: selectedTopic,
    publishedAt: new Date().toISOString(),
    platforms: {
      x: xResult,
      linkedIn: linkedInResult,
      facebook: facebookResult,
      instagram: instagramResult,
    },
  };
}

// Export module functions for CLI and internal use
module.exports = {
  ensureSocialConfigEnv,
  postTweet,
  postThread,
  postToLinkedIn,
  generateDiasporaContent,
  enforceBaseBlockchainTerminology,
  executeDailySocialPublication,
  xMarketingPublish: exports.xMarketingPublish,
  postToLinkedInFunc: exports.postToLinkedIn,
  diasporaSocialCron: exports.diasporaSocialCron,
  forceDiasporaSocialCron: exports.forceDiasporaSocialCron,
};
