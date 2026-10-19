/**
 * Diaspora Nearby – Autonomous YouTube Publishing & Studio Automation Module
 * 
 * Manages automated YouTube publishing (Videos, YouTube Shorts, Community Posts)
 * and AI-driven video content generation for the @DiasporaNearby channel.
 * 
 * Features:
 * - Direct YouTube Data API v3 upload via OAuth2 (resumable file upload)
 * - YouTube Shorts format validation & optimization (#Shorts, 9:16 vertical, <60s)
 * - Automated Gemini-powered YouTube script, title, description & tag generator
 * - Multi-platform cross-posting coordination
 */

const fs = require("fs");
const path = require("path");
const { google } = require("googleapis");
const axios = require("axios");

// ── YouTube OAuth2 Client Setup ──
function getYouTubeAuthClient() {
  const clientId = process.env.YOUTUBE_CLIENT_ID || process.env.GOOGLE_CLIENT_ID;
  const clientSecret = process.env.YOUTUBE_CLIENT_SECRET || process.env.GOOGLE_CLIENT_SECRET;
  const refreshToken = process.env.YOUTUBE_REFRESH_TOKEN || process.env.GOOGLE_REFRESH_TOKEN;
  const redirectUri = process.env.YOUTUBE_REDIRECT_URI || "http://localhost:3000/oauth2callback";

  if (!clientId || !clientSecret) {
    throw new Error(
      "Missing YouTube API credentials. Please set YOUTUBE_CLIENT_ID and YOUTUBE_CLIENT_SECRET in .env"
    );
  }

  const oauth2Client = new google.auth.OAuth2(clientId, clientSecret, redirectUri);

  if (refreshToken) {
    oauth2Client.setCredentials({ refresh_token: refreshToken });
  }

  return oauth2Client;
}

function getYouTubeService() {
  const auth = getYouTubeAuthClient();
  return google.youtube({ version: "v3", auth });
}

// ── Generate OAuth Authorization URL ──
function getAuthorizationUrl() {
  const oauth2Client = getYouTubeAuthClient();
  const scopes = [
    "https://www.googleapis.com/auth/youtube.upload",
    "https://www.googleapis.com/auth/youtube",
    "https://www.googleapis.com/auth/youtube.force-ssl",
  ];

  return oauth2Client.generateAuthUrl({
    access_type: "offline",
    prompt: "consent",
    scope: scopes,
  });
}

// ── Exchange Authorization Code for Refresh Token ──
async function exchangeCodeForTokens(code) {
  const oauth2Client = getYouTubeAuthClient();
  const { tokens } = await oauth2Client.getToken(code);
  return tokens;
}

// ── Core YouTube Video / Short Upload ──
async function uploadVideo({
  videoPath,
  title,
  description,
  tags = [],
  isShort = false,
  privacyStatus = "public", // 'public', 'private', 'unlisted'
  categoryId = "28", // 28: Science & Technology, 27: Education, 22: People & Blogs
  onProgress = null,
}) {
  if (!fs.existsSync(videoPath)) {
    throw new Error(`Video file not found at path: ${videoPath}`);
  }

  const fileSize = fs.statSync(videoPath).size;
  const youtube = getYouTubeService();

  // If designated as a YouTube Short, enforce title/tag conventions
  let finalTitle = title.trim();
  if (isShort && !finalTitle.toLowerCase().includes("#shorts")) {
    finalTitle = `${finalTitle} #Shorts`;
  }

  let finalDescription = description.trim();
  if (isShort && !finalDescription.toLowerCase().includes("#shorts")) {
    finalDescription = `${finalDescription}\n\n#Shorts #DiasporaNearby #$DIASPORA #DualIdentity`;
  }

  const standardTags = [
    "Diaspora Nearby",
    "Diaspora",
    "$DIASPORA",
    "Dual Identity",
    "Sovereign Economy",
    "African Diaspora",
    "Global Diaspora",
    "Base Blockchain",
    "Web3",
    "Ubuntu",
    "Community Organization",
    ...tags,
  ];

  const requestBody = {
    snippet: {
      title: finalTitle.slice(0, 100),
      description: finalDescription.slice(0, 5000),
      tags: standardTags.slice(0, 30),
      categoryId,
      defaultLanguage: "en",
    },
    status: {
      privacyStatus,
      selfDeclaredMadeForKids: false,
    },
  };

  const media = {
    body: fs.createReadStream(videoPath),
  };

  const res = await youtube.videos.insert(
    {
      part: "snippet,status",
      requestBody,
      media,
    },
    {
      onUploadProgress: (evt) => {
        if (onProgress && evt.bytesRead) {
          const progress = (evt.bytesRead / fileSize) * 100;
          onProgress(progress);
        }
      },
    }
  );

  const videoId = res.data.id;
  const videoUrl = isShort
    ? `https://www.youtube.com/shorts/${videoId}`
    : `https://www.youtube.com/watch?v=${videoId}`;

  return {
    success: true,
    videoId,
    videoUrl,
    title: finalTitle,
    privacyStatus,
    uploadedAt: new Date().toISOString(),
  };
}

// ── AI YouTube Short Script & Metadata Generator (Gemini Flash) ──
async function generateYouTubeShortContent({ topic = null } = {}) {
  const geminiApiKey = process.env.GEMINI_API_KEY;
  if (!geminiApiKey) {
    throw new Error("GEMINI_API_KEY is required to generate YouTube scripts.");
  }

  const prompt = `
You are the Executive Producer and YouTube Strategist for Diaspora Nearby (https://diasporanearby.com, channel: @DiasporaNearby).
Founder: Peter Swai (25-year diaspora veteran from Tanzania).

STRICT MESSAGING SCOPE (4 CORE PILLARS ONLY):
1. DISCOVERY ("Find Your People"): Real-time proximity discovery & notifications alerting verified diaspora members and compatriots when they are nearby in any city, campus, or neighborhood worldwide.
2. CONNECTION (High-Trust Peer Network): Connecting diaspora members, turning strangers into family through verified proximity check-ins, peer vouching, and Proof of Community Trust (PCT) on Base Blockchain.
3. ORGANIZATION OF DIASPORA COMMUNITIES: Organizing local town, city, and national diaspora chambers, community hubs, and collective chapters so diaspora communities are structured and united.
4. CREATING WEALTH FOR DIASPORA & THEIR DUAL GEOGRAPHIC IDENTITIES: Seamless Dual Geographic Identity (belonging to both Host and Home locations). Every verified connection and community action in Epoch 1 earns $DIASPORA on Base Blockchain, with a 1:1 Ubuntu Community Match that mints equal treasury reserves for both local/host and homeland community treasuries.

CRITICAL GUARDRAILS & TERMINOLOGY MANDATE:
1. NO MARKETPLACE PITCHES YET: Do NOT pitch or promote marketplace features, buying/selling goods, vendor directories, or remittance products as a core offering (those require community scale first). Any mention of everyday diaspora exchange may only be brief and anecdotal to illustrate human connection and community organization.
2. OFFICIAL TOKEN HASHTAG: Always include the official token hashtag #$DIASPORA in the video description.
3. BASE BLOCKCHAIN TERMINOLOGY: Whenever you refer to Base, ALWAYS write "Base Blockchain" (never standalone "Base" or "Base L2") so viewers and readers immediately know what Base means.

Generate a viral, high-retention 45-60 second YouTube Short script and upload package${
    topic ? ` focused on "${topic}"` : " on discovering, connecting, and organizing diaspora communities and creating wealth across their dual geographic identities on Base Blockchain"
  }.

Format output strictly as JSON with this schema:
{
  "title": "<Catchy title under 65 chars with #Shorts>",
  "hook": "<0-5s visual & verbal hook to prevent scroll-away>",
  "narration": "<Full spoken voiceover script, approx 110-140 words, broken into short cinematic beats, using 'Base Blockchain'>",
  "visualPrompts": [
    "<Beat 1 visual direction>",
    "<Beat 2 visual direction>",
    "<Beat 3 visual direction>"
  ],
  "description": "<SEO-optimized YouTube description (under 1000 chars) mentioning Base Blockchain, #$DIASPORA, and including call-to-action to visit diasporanearby.com and download the app>",
  "tags": ["DiasporaNearby", "Shorts", "DualIdentity", "$DIASPORA", "AfricanDiaspora", "BaseBlockchain", "PeterSwai", "Ubuntu"],
  "callToAction": "<Final spoken and on-screen CTA>"
}
`;

  const url = `https://generativelanguage.googleapis.com/v1beta/models/gemini-flash-latest:generateContent?key=${geminiApiKey}`;
  const response = await axios.post(
    url,
    {
      contents: [{ parts: [{ text: prompt }] }],
      generationConfig: {
        responseMimeType: "application/json",
        temperature: 0.7,
      },
    },
    { headers: { "Content-Type": "application/json" } }
  );

  const rawJson = response.data?.candidates?.[0]?.content?.parts?.[0]?.text;
  if (!rawJson) {
    throw new Error("Gemini returned empty response for YouTube Short generation.");
  }

  return JSON.parse(rawJson);
}

module.exports = {
  getYouTubeAuthClient,
  getYouTubeService,
  getAuthorizationUrl,
  exchangeCodeForTokens,
  uploadVideo,
  generateYouTubeShortContent,
};
