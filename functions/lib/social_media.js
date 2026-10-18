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

// ── Ensure Base Blockchain Terminology ──
function enforceBaseBlockchainTerminology(text) {
  if (!text) return text;
  return text
    .replace(/\bBase\s+L2\b/gi, "Base Blockchain")
    .replace(/\bBase\s+Layer\s*2\b/gi, "Base Blockchain")
    .replace(/\bon\s+Base\b(?!\s+Blockchain)/gi, "on Base Blockchain")
    .replace(/\bvia\s+\$DIASPORA\s+on\s+Base\b(?!\s+Blockchain)/gi, "via $DIASPORA on Base Blockchain")
    .replace(/#BaseL2\b/gi, "#BaseBlockchain")
    .replace(/#Base\b(?!Blockchain)/gi, "#BaseBlockchain");
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
  const topic = options.topic || "diaspora_sovereign_economy";

  const platformInstructions = {
    x: `
- Write a punchy, relatable tweet strictly under 260 characters about "${topic}".
- Highlight how finding your people or earning $DIASPORA on Base Blockchain transforms community connection into co-owned wealth.
- Must be 1 to 2 complete, conversational sentences. Include hashtags: #DiasporaNearby #FindYourPeople #BaseBlockchain #DIASPORA
- Output ONLY the raw tweet text. No introductory remarks, no quotes, no markdown headers.
`,
    linkedin: `
- Write an engaging LinkedIn post (around 1000-1500 characters) on "${topic}".
- Weave together the human experience of finding your people nearby with the transformative power of the $DIASPORA token on Base Blockchain.
- Include short paragraphs, bold insight, whitespace, and a clear call to action to join Epoch 1 at https://diasporanearby.com
- Include hashtags: #DiasporaNearby #FindYourPeople #BaseBlockchain #DIASPORA #DualIdentity
- Output ONLY raw post text.
`,
    facebook: `
- Write an authentic, warm, community-focused Facebook Page post (around 450-800 characters) on "${topic}".
- Start with the relatable human story of diaspora life—moving to a new city, finding compatriots nearby, and representing both home and host countries—then explain how every connection earns $DIASPORA on Base Blockchain with a 1:1 Ubuntu match for your homeland treasury.
- Include a clear call to action to explore https://diasporanearby.com and hashtags: #DiasporaNearby #FindYourPeople #BaseBlockchain #DIASPORA
- Output ONLY raw post text. No introductory remarks, no markdown headers.
`,
    instagram: `
- Write an inspiring Instagram caption (around 400-700 characters) on "${topic}".
- Hook the reader in the first line about finding your people nearby anywhere in the world, followed by 2-3 short bullet points on Dual Identity, Proximity Alerts, and earning $DIASPORA on Base Blockchain.
- End with a call to action to visit diasporanearby.com and hashtags: #DiasporaNearby #FindYourPeople #BaseBlockchain #DIASPORA #DualIdentity #Ubuntu
- Output ONLY raw caption text.
`,
  };

  const systemInstructions = `You are the authentic executive voice of Peter Swai, Founder & CEO of Diaspora Nearby — Architect of the Global Diaspora Sovereign Economy & Trust-to-Asset Engine.
Peter Swai lived across the diaspora for 25+ years (Tanzania -> San Francisco -> Santa Monica -> Iowa -> DC -> Phoenix -> Iowa -> now returning home to Tanzania).
As the Architect of the Global Diaspora Sovereign Economy, your mission is to turn cross-border community trust into sovereign retained wealth.
Use the specific product features (Find Your People, proximity discovery, dual identity, peer hosting, and the $DIASPORA token on Base Blockchain) in your posts to demonstrate how this sovereign architecture works in daily life.

PRIMARY SOCIAL UTILITY (ALWAYS LEAD WITH THIS):
1. "Find Your People" (Nearby Discovery): Real-time proximity discovery that instantly connects verified diaspora members and compatriots wherever they are in the world.
2. Proximity Notifications: When you step into a new city, airport, neighborhood, or campus, you get notified of diaspora peers nearby so you are never alone or isolated.
3. Dual Geographic Identity: Seamlessly represent both your Host country (where you live/work) and Home country (your heritage).
4. High-Trust Peer Hosting & 1:1 Ubuntu Matching: Verified community stays, newcomer welcomes, housing guidance, and mentorship.
5. Proof of Community Trust (PCT): A cross-border reputation score (0-100) on Base Blockchain that travels with you.

BLOCKCHAIN $DIASPORA TOKEN ON BASE BLOCKCHAIN (CRITICAL ECONOMIC LAYER):
- Built on Ethereum Base Blockchain (Coinbase Layer 2) for instant, sub-cent, gas-free mobile transactions.
- Epoch 1 (Accumulation Phase): Earning DSP social points by connecting with peers, verifying identity (PoI), checking in nearby, and peer hosting.
- 1:1 Ubuntu Community Match: When an individual earns $DIASPORA, an equal 1:1 match is minted directly into local town and national homeland community treasuries. Individual growth strengthens collective sovereignty.
- PCT Token Efficiency: Your community trust score directly scales token claim efficiency (91+ PCT unlocks 100% efficiency). Trust is literal capital.
- Web2 vs. Web3 Contrast: Web2 platforms (Meta/WhatsApp) monetize immigrant groups for corporate ad revenue. Diaspora Nearby gives the community true co-ownership through the $DIASPORA token on Base Blockchain.
- Staking for DDI Member Loans: 10% collateral in $DIASPORA unlocks community-backed loans for homeland investments.

CRITICAL POSITIONING & TERMINOLOGY RULES:
1. Do NOT frame Diaspora Nearby primarily as a remittance or money transfer service. The primary emotional hook and daily utility is SOCIAL CONNECTION: finding your people nearby, proximity alerts, and dual identity—backed by the sovereign $DIASPORA token on Base Blockchain.
2. Whenever you refer to Base, ALWAYS write "Base Blockchain" (never standalone "Base" or "Base L2") so readers clearly understand what Base is.

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
    const res = await axios.post(
      "https://integrate.api.nvidia.com/v1/chat/completions",
      {
        model: "meta/llama-3.1-70b-instruct",
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
    return text;
  }

  throw new Error("Content generation failed: no operational AI key.");
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
      const result = await executeDailySocialPublication();
      res.json({ success: true, message: "Diaspora social publication executed!", result });
    } catch (err) {
      console.error("forceDiasporaSocialCron error:", err.message);
      res.status(500).json({ error: err.message });
    }
  });

// Helper that executes the automated publication flow
async function executeDailySocialPublication() {
  await ensureSocialConfigEnv();

  const topics = [
    "Find Your People: How real-time proximity alerts connect diaspora members in any city worldwide",
    "Never landing alone: The power of proximity notifications when moving to a new country",
    "Nearby discovery: Connecting with verified compatriots living in your neighborhood, town, or campus",
    "The $DIASPORA Token on Base Blockchain: How everyday community connection mints on-chain sovereign wealth in Epoch 1",
    "1:1 Ubuntu Token Match: Why every $DIASPORA you earn on Base Blockchain mints equal treasury reserves for your homeland",
    "Web2 vs Web3 Diaspora: Why Meta extracts your community data while Diaspora Nearby gives you co-ownership via $DIASPORA on Base Blockchain",
    "Proof of Community Trust (PCT) and Token Efficiency: Why authentic reputation on Base Blockchain unlocks 100% $DIASPORA claim power",
    "Dual Geographic Identity: Seamlessly belonging to both your home country and host country",
    "From stranger to family: How high-trust peer hosting changes travel for the global diaspora",
    "DDI Member Loans: Staking $DIASPORA on Base Blockchain with 10% collateral to finance cross-border enterprise",
  ];

  const selectedTopic = topics[Math.floor(Math.random() * topics.length)];

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
      return { topic: selectedTopic, type: "unified_broadcast", result: broadcastRes };
    } catch (unifiedErr) {
      console.warn("⚠️ Unified broadcast failed, falling back to direct native publishers:", unifiedErr.message);
    }
  }

  // ── 1. Native Direct Post to X (Twitter) ──
  let xResult = null;
  try {
    const xContent = await generateDiasporaContent({ platform: "x", topic: selectedTopic });
    xResult = await postTweet(xContent);
    console.log(`✅ [Free Native] X post published: ${xResult.tweetUrl}`);
  } catch (xErr) {
    console.error("X publishing error:", xErr.message);
    xResult = { error: xErr.message };
  }

  // ── 2. Native Direct Post to LinkedIn ──
  let linkedInResult = null;
  try {
    const linkedInContent = await generateDiasporaContent({ platform: "linkedin", topic: selectedTopic });
    linkedInResult = await postToLinkedIn(linkedInContent, { postToOrg: true });
    console.log(`✅ [Free Native] LinkedIn post published: ${linkedInResult.postUrl}`);
  } catch (liErr) {
    console.error("LinkedIn publishing error:", liErr.message);
    linkedInResult = { error: liErr.message };
  }

  // ── 3. Native Direct Post to Facebook Page (AI-generated copy) ──
  let facebookResult = null;
  const metaPublisher = require("./meta_publisher");
  if (process.env.META_PAGE_ACCESS_TOKEN) {
    try {
      const fbMessage = await generateDiasporaContent({ platform: "facebook", topic: selectedTopic });
      facebookResult = await metaPublisher.postToFacebookPage({ message: fbMessage });
      console.log(`✅ [Free Native] Facebook Page post published: ${facebookResult.postUrl}`);

      await db.collection("_socialFacebookPosts").add({
        postId: facebookResult.postId,
        postUrl: facebookResult.postUrl,
        text: fbMessage,
        topic: selectedTopic,
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
      const igCaption = await generateDiasporaContent({ platform: "instagram", topic: selectedTopic });
      const igImageUrl = process.env.SOCIAL_SHARE_IMAGE_URL || "https://diasporanearby.com/images/og-share-card.png";
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
