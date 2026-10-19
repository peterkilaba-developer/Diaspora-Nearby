/**
 * Diaspora Nearby – Autonomous Multimedia Content Studio
 * 
 * Generates coordinated, multi-format daily content packs:
 * - Platform-tailored text (X, LinkedIn, Facebook, Instagram, YouTube, TikTok)
 * - Programmatic Branded SVG Graphic Cards (1080x1080 square for IG/FB/LI/X)
 * - YouTube Shorts & TikTok Video Storyboards with Voiceover Narration Scripts
 */

const axios = require("axios");
const fs = require("fs");
const path = require("path");

/**
 * Generate a complete multi-platform multimedia content pack using Gemini
 */
async function generateDailyContentPack({ topic = null } = {}) {
  const geminiApiKey = process.env.GEMINI_API_KEY;
  if (!geminiApiKey) {
    throw new Error("GEMINI_API_KEY is required in functions/.env");
  }

  const prompt = `
You are the Chief Creative Director for Diaspora Nearby (https://diasporanearby.com).
Founder: Peter Swai, Architect of the Global Diaspora Sovereign Economy & Trust-to-Asset Engine.

STRICT MESSAGING SCOPE (4 CORE PILLARS ONLY):
All content MUST focus strictly on these four foundational pillars:
1. DISCOVERY ("Find Your People"): Real-time proximity discovery & notifications alerting verified compatriots when they are nearby in any city, campus, or neighborhood.
2. CONNECTION (High-Trust Peer Network): Connecting diaspora members, turning strangers into family through verified proximity check-ins, peer vouching, and Proof of Community Trust (PCT) on Base Blockchain.
3. ORGANIZATION OF DIASPORA COMMUNITIES: Organizing local town, city, and national diaspora chambers, community hubs, and collective chapters so diaspora communities are structured and united.
4. CREATING WEALTH FOR DIASPORA & THEIR DUAL GEOGRAPHIC IDENTITIES: Seamless Dual Geographic Identity (belonging to both Host and Home locations). Earning sovereign $DIASPORA on Base Blockchain in Epoch 1 (Accumulation Phase) with a 1:1 Ubuntu Community Match that builds treasury reserves for both local/host and homeland communities.

CRITICAL GUARDRAILS & TERMINOLOGY RULES:
1. NO MARKETPLACE PITCHES YET: Do NOT pitch or promote marketplace features, buying/selling goods, vendor directories, or remittance products as a core offering (we need community scale first). Any mention of everyday diaspora exchange may only be brief and anecdotal to illustrate human connection and community organization.
2. OFFICIAL TOKEN HASHTAG: Always include the official token hashtag #$DIASPORA in all social copy.
3. BASE BLOCKCHAIN TERMINOLOGY: Whenever you mention Base, ALWAYS write "Base Blockchain" (never just "Base" or "Base L2") so readers immediately understand what Base means.

Create a synchronized, high-impact DAILY MULTIMEDIA CONTENT PACK${topic ? ` focused on "${topic}"` : " on discovering, connecting, and organizing diaspora communities and creating wealth across their dual geographic identities on Base Blockchain"}.

Return ONLY valid JSON matching this schema:
{
  "theme": "<Theme title>",
  "quoteCard": {
    "headline": "<Punchy headline, 5-8 words max>",
    "bodyQuote": "<Memorable 1-2 sentence core message about discovering, connecting, organizing diaspora communities and creating dual-identity wealth, max 25 words>",
    "subtext": "Peter Swai • Architect of the Global Diaspora Sovereign Economy"
  },
  "textCopy": {
    "x": "<Punchy tweet strictly under 235 chars mentioning Base Blockchain with #DiasporaNearby #FindYourPeople #BaseBlockchain #$DIASPORA>",
    "linkedIn": "<Engaging LinkedIn post, 800-1200 chars mentioning Base Blockchain, #DiasporaNearby #FindYourPeople #BaseBlockchain #$DIASPORA #DualIdentity, with whitespace and CTA to diasporanearby.com>",
    "facebook": "<Community-friendly Facebook post, 400-600 chars mentioning Base Blockchain, #DiasporaNearby #FindYourPeople #BaseBlockchain #$DIASPORA, and CTA to https://diasporanearby.com>",
    "instagramCaption": "<Engaging IG caption mentioning Base Blockchain with bullet points, #DiasporaNearby #FindYourPeople #BaseBlockchain #$DIASPORA #DualIdentity #Ubuntu, and CTA to diasporanearby.com>",
    "tikTokCaption": "<Short viral caption under 100 chars with #DiasporaNearby #FindYourPeople #BaseBlockchain #$DIASPORA>"
  },
  "shortVideoStoryboard": {
    "title": "<Catchy 45-60s video title with #Shorts>",
    "hook": "<0-5s verbal & visual pattern interrupt>",
    "narrationScript": "<110-140 word spoken voiceover text for TTS narrator or Peter Swai>",
    "visualBeats": [
      "<Beat 1: 0-10s visual>",
      "<Beat 2: 10-25s visual>",
      "<Beat 3: 25-45s visual>",
      "<Beat 4: 45-60s visual & CTA>"
    ],
    "soundtrackMood": "Uplifting Afro-Cinematic Ambient / Pulse"
  },
  "hashtags": ["DiasporaNearby", "FindYourPeople", "DualIdentity", "BaseBlockchain", "$DIASPORA", "Ubuntu"]
}
`;

  const url = `https://generativelanguage.googleapis.com/v1beta/models/gemini-flash-latest:generateContent?key=${geminiApiKey}`;
  const response = await axios.post(
    url,
    {
      contents: [{ parts: [{ text: prompt }] }],
      generationConfig: {
        responseMimeType: "application/json",
        temperature: 0.75,
      },
    },
    { headers: { "Content-Type": "application/json" } }
  );

  const rawJson = response.data?.candidates?.[0]?.content?.parts?.[0]?.text;
  if (!rawJson) {
    throw new Error("Failed to receive content pack from Gemini AI.");
  }

  const pack = JSON.parse(rawJson);

  // Enforce "Base Blockchain" phrasing and #$DIASPORA hashtag across all generated text copy
  if (pack.textCopy) {
    for (const key of Object.keys(pack.textCopy)) {
      if (typeof pack.textCopy[key] === "string") {
        pack.textCopy[key] = enforceBaseBlockchainTerminology(pack.textCopy[key]);
      }
    }
  }
  if (pack.quoteCard?.bodyQuote) {
    pack.quoteCard.bodyQuote = enforceBaseBlockchainTerminology(pack.quoteCard.bodyQuote, false);
  }

  // Generate branded SVG Graphic Card
  pack.quoteCard.svg = generateBrandedQuoteCardSvg(pack.quoteCard);

  return pack;
}

/**
 * Ensures any standalone "on Base" / "Base L2" / "#Base" is normalized to "Base Blockchain" / "#BaseBlockchain"
 * and ensures the official #$DIASPORA hashtag is present on social copy.
 */
function enforceBaseBlockchainTerminology(text, requireTokenHashtag = true) {
  if (!text) return text;
  let updated = text
    .replace(/\bBase\s+L2\b/gi, "Base Blockchain")
    .replace(/\bBase\s+Layer\s*2\b/gi, "Base Blockchain")
    .replace(/\bon\s+Base\b(?!\s+Blockchain)/gi, "on Base Blockchain")
    .replace(/\bvia\s+\$DIASPORA\s+on\s+Base\b(?!\s+Blockchain)/gi, "via $DIASPORA on Base Blockchain")
    .replace(/#BaseL2\b/gi, "#BaseBlockchain")
    .replace(/#Base\b(?!Blockchain)/gi, "#BaseBlockchain")
    .replace(/(^|\s)#DIASPORA\b/g, "$1#$DIASPORA");

  if (requireTokenHashtag && !updated.includes("#$DIASPORA")) {
    updated = `${updated.trim()} #$DIASPORA`;
  }
  return updated;
}

/**
 * Generate a production-ready 1080x1080 SVG graphic quote card
 * Uses pure SVG <text>/<tspan> elements (no <foreignObject>) so it renders cleanly in all rasterizers.
 */
function generateBrandedQuoteCardSvg({ headline, bodyQuote, subtext }) {
  const escapeXml = (str) =>
    (str || "")
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;")
      .replace(/'/g, "&apos;");

  const cleanHeadline = escapeXml((headline || "FIND YOUR PEOPLE").toUpperCase());
  const cleanSubtext = escapeXml(subtext || "Peter Swai • Architect of the Global Diaspora Sovereign Economy");

  // Wrap bodyQuote into lines of ~36 chars for clean SVG <tspan> rendering
  const words = (bodyQuote || "").split(/\s+/).filter(Boolean);
  const lines = [];
  let currentLine = "";
  for (const word of words) {
    if ((currentLine + " " + word).trim().length > 36 && currentLine.length > 0) {
      lines.push(currentLine.trim());
      currentLine = word;
    } else {
      currentLine = (currentLine + " " + word).trim();
    }
  }
  if (currentLine.trim().length > 0) {
    lines.push(currentLine.trim());
  }

  const tspans = lines
    .slice(0, 6)
    .map((line, idx) => `<tspan x="100" dy="${idx === 0 ? 0 : 54}">${escapeXml(line)}</tspan>`)
    .join("\n      ");

  return `<svg width="1080" height="1080" viewBox="0 0 1080 1080" xmlns="http://www.w3.org/2000/svg">
  <defs>
    <!-- Background Gradient -->
    <linearGradient id="bgGrad" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="#0a0518" />
      <stop offset="40%" stop-color="#140a2b" />
      <stop offset="100%" stop-color="#05020c" />
    </linearGradient>

    <!-- Gold Accent Gradient -->
    <linearGradient id="goldGrad" x1="0%" y1="0%" x2="100%" y2="0%">
      <stop offset="0%" stop-color="#F59E0B" />
      <stop offset="100%" stop-color="#FBBF24" />
    </linearGradient>

    <!-- Purple Glow Filter -->
    <filter id="glow" x="-20%" y="-20%" width="140%" height="140%">
      <feGaussianBlur stdDeviation="60" result="blur" />
      <feComposite in="SourceGraphic" in2="blur" operator="over" />
    </filter>
  </defs>

  <!-- Canvas Background -->
  <rect width="1080" height="1080" fill="url(#bgGrad)" />

  <!-- Ambient Glow Elements -->
  <circle cx="900" cy="150" r="220" fill="#7C3AED" opacity="0.25" filter="url(#glow)" />
  <circle cx="150" cy="950" r="280" fill="#D97706" opacity="0.18" filter="url(#glow)" />

  <!-- Outer Border Frame -->
  <rect x="40" y="40" width="1000" height="1000" rx="32" fill="none" stroke="#2D1B4E" stroke-width="2" opacity="0.6" />

  <!-- Top Header Badge -->
  <g transform="translate(100, 110)">
    <rect width="260" height="48" rx="24" fill="#1E1035" stroke="#7C3AED" stroke-width="1.5" />
    <circle cx="28" cy="24" r="8" fill="#F59E0B" />
    <text x="50" y="31" font-family="Arial, Helvetica, sans-serif" font-size="16" font-weight="700" fill="#E2E8F0" letter-spacing="2">DIASPORA NEARBY</text>
  </g>

  <!-- Network Pill: Built on Base Blockchain -->
  <g transform="translate(720, 110)">
    <rect width="260" height="48" rx="24" fill="#0052FF" opacity="0.15" stroke="#0052FF" stroke-width="1.5" />
    <circle cx="28" cy="24" r="8" fill="#0052FF" />
    <text x="48" y="30" font-family="Arial, Helvetica, sans-serif" font-size="14" font-weight="700" fill="#60A5FA" letter-spacing="1">ON BASE BLOCKCHAIN</text>
  </g>

  <!-- Main Headline -->
  <text x="100" y="290" font-family="Arial, Helvetica, sans-serif" font-size="40" font-weight="900" fill="url(#goldGrad)" letter-spacing="1">
    ${cleanHeadline}
  </text>

  <!-- Quote Mark Icon -->
  <text x="100" y="410" font-family="Georgia, serif" font-size="110" fill="#7C3AED" opacity="0.5">“</text>

  <!-- Body Quote (Multi-line pure SVG text) -->
  <text x="100" y="470" font-family="Arial, Helvetica, sans-serif" font-size="36" font-weight="500" fill="#F8FAFC">
      ${tspans}
  </text>

  <!-- Bottom Divider Line -->
  <line x1="100" y1="840" x2="980" y2="840" stroke="#2D1B4E" stroke-width="2" />

  <!-- Author Signature & Title -->
  <g transform="translate(100, 890)">
    <circle cx="36" cy="36" r="36" fill="#F59E0B" opacity="0.2" />
    <text x="36" y="44" font-family="Arial, Helvetica, sans-serif" font-size="24" font-weight="800" fill="#F59E0B" text-anchor="middle">PS</text>
    <text x="96" y="32" font-family="Arial, Helvetica, sans-serif" font-size="24" font-weight="700" fill="#FFFFFF">Peter Swai</text>
    <text x="96" y="58" font-family="Arial, Helvetica, sans-serif" font-size="16" font-weight="500" fill="#94A3B8">${cleanSubtext}</text>
  </g>

  <!-- Web & App Callout Bottom Right -->
  <g transform="translate(730, 905)">
    <text x="250" y="24" font-family="Arial, Helvetica, sans-serif" font-size="18" font-weight="700" fill="#F59E0B" text-anchor="end">diasporanearby.com</text>
    <text x="250" y="48" font-family="Arial, Helvetica, sans-serif" font-size="14" font-weight="500" fill="#64748B" text-anchor="end">iOS • Android • Base Blockchain</text>
  </g>
</svg>`;
}

module.exports = {
  generateDailyContentPack,
  generateBrandedQuoteCardSvg,
  enforceBaseBlockchainTerminology,
};
