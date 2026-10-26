/**
 * Diaspora Nearby – Automated Facebook & WhatsApp Outreach Engine
 *
 * Implements the Tanzania Dual-Corridor Go-To-Market (GTM) automation:
 *   1. Cohort A (tz_abroad): Tanzanians living outside Tanzania -> Mostly Kiswahili
 *   2. Cohort B (expat_in_tz): Non-Tanzanians living inside Tanzania (Dar, Arusha, Zanzibar)
 *      -> English or detected/known native language (French, Mandarin, Hindi, Arabic, German, Spanish, Portuguese)
 *
 * Capabilities:
 *   - 2-way WhatsApp Cloud API Interactive Onboarding Concierge (invoked by whatsappWebhook)
 *   - Deterministic Referral & Corridor Attribution (outreach_leads collection)
 *   - Automated 20-hour WhatsApp Follow-Up Nudge inside Meta's free 24h service window
 *   - Facebook Page Comment-to-DM Auto-Responder (metaOutreachWebhook)
 *   - On-demand Campaign Kit & Corridor Post Publisher
 */

const { functions, admin, db } = require("./shared");
const { stableHash } = require("./security");
const { parsePhoneNumberFromString } = require("libphonenumber-js");

const GRAPH_API_BASE = "https://graph.facebook.com/v20.0";

// ── Native Language Localization Packs for Cohort B (Expats Living in Tanzania) ──
const EXPAT_NATIVE_PACKS = {
  en: {
    langName: "English",
    welcome: (code, cityLabel) =>
      `🌍 *Welcome to Diaspora Nearby — Tanzania International & Expat Hub (${cityLabel})!*\n\n` +
      `Living in Tanzania (Dar es Salaam, Arusha, Zanzibar, or beyond) from abroad? Diaspora Nearby connects you with:\n` +
      `1️⃣ *Nearby Compatriots*: Discover verified people from your home country right in your neighborhood.\n` +
      `2️⃣ *High-Trust Network*: Build portable Proof of Community Trust (PCT) on Base Blockchain.\n` +
      `3️⃣ *Nationality & City Chambers*: Organize and lead your country's local community hub in Tanzania.\n` +
      `4️⃣ *1:1 Ubuntu Wealth Match*: Earn *$DIASPORA* on Base Blockchain in Epoch 1 while minting matching treasury reserves for both your host city in Tanzania and your home country.\n\n` +
      `🎁 *Your Genesis Invite Code:* \`${code}\`\n` +
      `📲 *1-Tap Download (Android & iOS):*\nhttps://diasporanearby.com/invite?code=${code}\n\n` +
      `_Sign in using this WhatsApp number inside the app to automatically claim your Epoch 1 Welcome Bonus!_`,
    forwardCard: (code) =>
      `🌍 *Expats & International Community in Tanzania (Dar · Arusha · Zanzibar)* 🇹🇿\n\n` +
      `We are organizing our nationality & city chapters on *Diaspora Nearby* so we can easily discover compatriots from home living nearby in Tanzania, connect safely, and earn *$DIASPORA* on Base Blockchain (with a 1:1 Ubuntu Community Match).\n\n` +
      `Join our Tanzania hub here & claim your Genesis bonus:\n` +
      `👉 https://diasporanearby.com/invite?code=${code}`,
    followUp: (code) =>
      `👋 Quick reminder from *Diaspora Nearby*! Your Founding Member spot and Epoch 1 *$DIASPORA* welcome allocation (\`${code}\`) for the Tanzania International Hub are still reserved.\n\n` +
      `Tap below to install on Android or iOS and verify with this WhatsApp number:\n` +
      `👉 https://diasporanearby.com/invite?code=${code}`,
    commentReply: "Welcome! 🌍 We just sent your Founding Member invite link to your DM inbox 📩",
  },
  fr: {
    langName: "Français",
    welcome: (code, cityLabel) =>
      `🌍 *Bienvenue sur Diaspora Nearby — Hub International en Tanzanie (${cityLabel}) !*\n\n` +
      `Vous vivez en Tanzanie (Dar es Salaam, Arusha, Zanzibar) ? Diaspora Nearby vous permet de :\n` +
      `1️⃣ *Trouver vos compatriotes à proximité* dans votre ville ou quartier.\n` +
      `2️⃣ *Bâtir un réseau de confiance* (Proof of Community Trust sur Base Blockchain).\n` +
      `3️⃣ *Organiser votre communauté* locale et nationale en Tanzanie.\n` +
      `4️⃣ *Créer une richesse collective (1:1 Ubuntu Match)* : Gagnez des jetons *$DIASPORA* sur Base Blockchain tout en abondant la trésorerie de votre communauté à parité 1:1.\n\n` +
      `🎁 *Votre Code d'Invitation Genesis :* \`${code}\`\n` +
      `📲 *Téléchargement direct (Android & iOS) :*\nhttps://diasporanearby.com/invite?code=${code}\n\n` +
      `_Connectez-vous avec ce numéro WhatsApp dans l'application pour activer votre bonus Epoch 1 !_`,
    forwardCard: (code) =>
      `🌍 *Communauté Francophone & Expatriés en Tanzanie (Dar · Arusha · Zanzibar)* 🇹🇿\n\n` +
      `Rejoignez notre communauté sur *Diaspora Nearby* pour retrouver nos compatriotes à proximité en Tanzanie, organiser notre chambre locale et gagner des *$DIASPORA* sur Base Blockchain :\n` +
      `👉 https://diasporanearby.com/invite?code=${code}`,
    followUp: (code) =>
      `👋 Rappel de *Diaspora Nearby* ! Votre code d'invitation Genesis (\`${code}\`) et votre bonus Epoch 1 *$DIASPORA* en Tanzanie vous attendent :\n` +
      `👉 https://diasporanearby.com/invite?code=${code}`,
    commentReply: "Bienvenue ! 🌍 Nous venons de vous envoyer votre lien d'invitation en message privé (DM) 📩",
  },
  zh: {
    langName: "中文 (Mandarin)",
    welcome: (code, cityLabel) =>
      `🌍 *欢迎加入 Diaspora Nearby — 坦桑尼亚华人与国际侨民社区 (${cityLabel})！*\n\n` +
      `无论您在达累斯萨拉姆 (Dar es Salaam)、阿鲁沙 (Arusha) 还是桑给巴尔 (Zanzibar)：\n` +
      `1️⃣ *发现附近的同胞*：实时发现并连接您身边的华人与同胞。\n` +
      `2️⃣ *高信任互助网络*：基于 Base Blockchain 建立社区信任证明 (PCT)。\n` +
      `3️⃣ *组织本地商会与社区*：共建坦桑尼亚本地与祖国双地理身份社区。\n` +
      `4️⃣ *1:1 Ubuntu 财富配捐*：在 Epoch 1 赚取 Base Blockchain 上的 *$DIASPORA* 代币，同时为您的坦桑尼亚本地社区和家乡金库 1:1 铸造储备。\n\n` +
      `🎁 *您的创世邀请码：* \`${code}\`\n` +
      `📲 *一键下载应用 (Android & iOS)：*\nhttps://diasporanearby.com/invite?code=${code}\n\n` +
      `_请使用此 WhatsApp 号码登录应用以自动领取您的 Epoch 1 创世奖励！_`,
    forwardCard: (code) =>
      `🌍 *坦桑尼亚华人与国际侨民社区 (达累斯萨拉姆 · 阿鲁沙 · 桑给巴尔)* 🇹🇿\n\n` +
      `我们正在 *Diaspora Nearby* 组建坦桑尼亚同胞社区！发现身边的同胞、加入本地商会，并在 Base Blockchain 上赚取 *$DIASPORA* 创世代币：\n` +
      `👉 https://diasporanearby.com/invite?code=${code}`,
    followUp: (code) =>
      `👋 *Diaspora Nearby* 温馨提醒：您的坦桑尼亚创世会员邀请码 (\`${code}\`) 与 *$DIASPORA* 奖励已为您保留，点击即可下载加入：\n` +
      `👉 https://diasporanearby.com/invite?code=${code}`,
    commentReply: "欢迎！🌍 我们已将您的专属创世邀请链接发送至您的私信 (DM) 📩",
  },
  hi: {
    langName: "हिन्दी (Hindi)",
    welcome: (code, cityLabel) =>
      `🌍 *नमस्ते! Diaspora Nearby में आपका स्वागत है — तंजानिया प्रवासी और अंतर्राष्ट्रीय समुदाय (${cityLabel})!*\n\n` +
      `क्या आप दार एस सलाम (Dar es Salaam), अरुशा (Arusha), या ज़ांज़ीबार (Zanzibar) में रहते हैं? Diaspora Nearby के माध्यम से:\n` +
      `1️⃣ *आस-पास के देशवासियों से जुड़ें*: अपने शहर में अपने देश के लोगों को तुरंत खोजें।\n` +
      `2️⃣ *विश्वसनीय समुदाय*: Base Blockchain पर Proof of Community Trust (PCT) बनाएं।\n` +
      `3️⃣ *स्थानीय चैंबर और संगठन*: तंजानिया में अपने समुदाय को संगठित करें।\n` +
      `4️⃣ *1:1 Ubuntu वेल्थ मैच*: Epoch 1 में Base Blockchain पर *$DIASPORA* टोकन कमाएं।\n\n` +
      `🎁 *आपका आमंत्रण कोड:* \`${code}\`\n` +
      `📲 *ऐप डाउनलोड करें (Android & iOS):*\nhttps://diasporanearby.com/invite?code=${code}`,
    forwardCard: (code) =>
      `🌍 *तंजानिया में भारतीय और अंतर्राष्ट्रीय समुदाय (Dar · Arusha · Zanzibar)* 🇹🇿\n\n` +
      `अपने आस-पास के देशवासियों से जुड़ने और Base Blockchain पर *$DIASPORA* कमाने के लिए *Diaspora Nearby* से जुड़ें:\n` +
      `👉 https://diasporanearby.com/invite?code=${code}`,
    followUp: (code) =>
      `👋 *Diaspora Nearby* रिमाइंडर! आपका आमंत्रण कोड (\`${code}\`) और Epoch 1 *$DIASPORA* बोनस तैयार है। अभी डाउनलोड करें:\n` +
      `👉 https://diasporanearby.com/invite?code=${code}`,
    commentReply: "नमस्ते! 🌍 हमने आपका आमंत्रण लिंक आपके इनबॉक्स (DM) में भेज दिया है 📩",
  },
  ar: {
    langName: "العربية (Arabic)",
    welcome: (code, cityLabel) =>
      `🌍 *مرحباً بك في Diaspora Nearby — ملتقى الجاليات والمغتربين في تنزانيا (${cityLabel})!*\n\n` +
      `هل تقيم في دار السلام أو أروشا أو زنجبار؟ يتيح لك تطبيق Diaspora Nearby:\n` +
      `1️⃣ *اكتشاف أبناء بلدك بالقرب منك* في مدينتك الحالية.\n` +
      `2️⃣ *بناء شبكة ثقة موثقة* على Base Blockchain.\n` +
      `3️⃣ *تنظيم غرف ومجتمعات الجالية* في تنزانيا.\n` +
      `4️⃣ *مضاعفة الثروة المجتمعية (1:1 Ubuntu Match)* عبر عملة *$DIASPORA* على Base Blockchain.\n\n` +
      `🎁 *رمز الدعوة الخاص بك:* \`${code}\`\n` +
      `📲 *تحميل التطبيق (Android & iOS):*\nhttps://diasporanearby.com/invite?code=${code}`,
    forwardCard: (code) =>
      `🌍 *الجاليات العربية والدولية في تنزانيا (دار السلام · أروشا · زنجبار)* 🇹🇿\n\n` +
      `انضم إلينا على تطبيق *Diaspora Nearby* للتواصل مع أبناء الجالية بالقرب منك وكسب عملات *$DIASPORA* على Base Blockchain:\n` +
      `👉 https://diasporanearby.com/invite?code=${code}`,
    followUp: (code) =>
      `👋 تذكير من *Diaspora Nearby*! رمز الدعوة الخاص بك (\`${code}\`) ومكافأة *$DIASPORA* بانتظارك:\n` +
      `👉 https://diasporanearby.com/invite?code=${code}`,
    commentReply: "أهلاً بك! 🌍 لقد أرسلنا رابط الدعوة الخاص بك إلى رسائلك الخاصة (DM) 📩",
  },
  de: {
    langName: "Deutsch",
    welcome: (code, cityLabel) =>
      `🌍 *Willkommen bei Diaspora Nearby — Expat & Internationale Community in Tansania (${cityLabel})!*\n\n` +
      `Leben Sie in Dar es Salaam, Arusha oder Sansibar? Mit Diaspora Nearby können Sie:\n` +
      `1️⃣ *Landsleute in Ihrer Nähe entdecken* und sich direkt vernetzen.\n` +
      `2️⃣ *Vertrauensnetzwerke aufbauen* (Proof of Community Trust auf der Base Blockchain).\n` +
      `3️⃣ *Lokale Community-Chambers organisieren*.\n` +
      `4️⃣ *1:1 Ubuntu Match*: Verdienen Sie *$DIASPORA* auf der Base Blockchain für Ihre Heimat- und Gast-Community.\n\n` +
      `🎁 *Ihr Genesis-Einladungscode:* \`${code}\`\n` +
      `📲 *Direkt-Download (Android & iOS):*\nhttps://diasporanearby.com/invite?code=${code}`,
    forwardCard: (code) =>
      `🌍 *Deutschsprachige & Internationale Community in Tansania (Dar · Arusha · Sansibar)* 🇹🇿\n\n` +
      `Vernetzt euch mit Landsleuten in der Nähe auf *Diaspora Nearby* und sichert euch euren Genesis *$DIASPORA* Bonus auf der Base Blockchain:\n` +
      `👉 https://diasporanearby.com/invite?code=${code}`,
    followUp: (code) =>
      `👋 Kurze Erinnerung von *Diaspora Nearby*! Ihr Genesis-Einladungscode (\`${code}\`) ist noch für Sie reserviert:\n` +
      `👉 https://diasporanearby.com/invite?code=${code}`,
    commentReply: "Willkommen! 🌍 Wir haben Ihnen Ihren Einladungslink gerade per DM geschickt 📩",
  },
};

// ── Cohort A Pack: Mostly Kiswahili for Tanzanians Outside Tanzania ──
const KISWAHILI_DIASPORA_PACK = {
  welcome: (code, cityLabel) =>
    `🇹🇿 *Karibu Sana Diaspora Nearby — Mtandao wa Watanzania Waishio Nje ya Nchi (${cityLabel})!*\n\n` +
    `Popote ulipo ughaibuni (Marekani, UK, Dubai/UAE, Afrika Kusini, Kenya, Canada, Ulaya au China), *Diaspora Nearby* imejengwa maalum kwa ajili yetu:\n\n` +
    `1️⃣ *Gundua Watanzania Karibu Nawe (Discovery)*: Fahamu na uwasiliane na Watanzania wenzako walio mji mmoja, chuo kimoja au mtaa mmoja na wewe.\n` +
    `2️⃣ *Ungana kwa Uaminifu (Connection)*: Jenga mtandao wa kuaminiana (Proof of Community Trust) uliothibitishwa.\n` +
    `3️⃣ *Jenga Jumuiya na Chemba Imara (Organization)*: Jiunge na chemba ya Watanzania katika mji unaoishi ughaibuni pamoja na mkoa/mji uliotoka nyumbani Tanzania.\n` +
    `4️⃣ *Jenga Utajiri wa Pamoja (1:1 Ubuntu Match)*: Kila unapoungana na kushiriki kwenye Epoch 1 unapata tokeni za *$DIASPORA* kwenye *Base Blockchain*, na hazina ya mji wako wa ughaibuni pamoja na hazina ya nyumbani Tanzania zinapata kiasi sawa (1:1 Match)!\n\n` +
    `🎁 *Kodi Yako ya Mwaliko (Genesis Code):* \`${code}\`\n` +
    `📲 *Bonyeza Hapa Kupakua App (Android & iPhone):*\nhttps://diasporanearby.com/invite?code=${code}\n\n` +
    `_Ukishaingia kwenye app, jisajili kwa namba hii ya WhatsApp ili kupata zawadi yako ya Epoch 1 Welcome Bonus moja kwa moja!_`,

  forwardCard: (code) =>
    `🇹🇿 *Watanzania Wenzangu Waishio Nje ya Tanzania (Diaspora / Ughaibuni)!* 🌍\n\n` +
    `Tunajenga mtandao rasmi wa Watanzania kila mji duniani kupitia *Diaspora Nearby* — programu inayokuwezesha kuwafahamu Watanzania walio karibu nawe mji uliopo, kuimarisha jumuiya zetu, na kujenga hazina ya pamoja kati ya ughaibuni na nyumbani Tanzania kupitia *$DIASPORA* kwenye *Base Blockchain* (1:1 Ubuntu Match).\n\n` +
    `Jiunge na chemba ya mji wako hapa na upate zawadi ya waanzilishi (Epoch 1):\n` +
    `👉 https://diasporanearby.com/invite?code=${code}`,

  followUp: (code) =>
    `🇹🇿 *Habari ndugu yangu!* Huu ni ukumbusho mfupi kutoka *Diaspora Nearby*. Nafasi yako ya Mwanzilishi (Genesis Member) na zawadi yako ya Epoch 1 *$DIASPORA* kwa kutumia kodi \`${code}\` bado imehifadhiwa.\n\n` +
    `Bonyeza link hii kupakua kwenye simu yako (Android au iPhone) na uingie kwa namba hii ya WhatsApp:\n` +
    `👉 https://diasporanearby.com/invite?code=${code}`,

  commentReply:
    "Karibu sana ndugu yetu! 🇹🇿 Tumekutumia link yako ya kujiunga na kodi ya zawadi kwenye inbox yako (DM) sasa hivi 📩",
};

/**
 * Generates a deterministic 8-character referral/tracking code from phone or user ID
 */
function buildOutreachCode(prefix, identifier) {
  const hash = stableHash(`outreach:${identifier}`).slice(0, 6).toUpperCase();
  return `${prefix}${hash}`;
}

/**
 * Detects corridor ("tz_abroad" | "expat_in_tz" | "unknown"), native language, and city
 * from an incoming WhatsApp message or Facebook comment.
 */
function classifyOutreachIntent(rawText = "", senderPhone = "") {
  const text = String(rawText || "").trim();
  const lower = text.toLowerCase();

  // 1. Explicit button / payload IDs
  if (lower.includes("corridor_tz_abroad") || lower.includes("mtanzania nje")) {
    return { corridor: "tz_abroad", lang: "sw", city: extractCityLabel(text, "tz_abroad") };
  }
  if (lower.includes("corridor_in_tz") || lower.includes("expat living in tz")) {
    const lang = detectExpatLanguage(text);
    return { corridor: "expat_in_tz", lang, city: extractCityLabel(text, "expat_in_tz") };
  }

  // 2. Detect native script / language signals for Expats in Tanzania
  const detectedLang = detectExpatLanguage(text);

  // 3. Keywords for Cohort B (Expats living inside Tanzania)
  const expatInTzKeywords = [
    "live in tanzania",
    "living in tanzania",
    "expat in",
    "expats in",
    "in dar",
    "in arusha",
    "in zanzibar",
    "masaki",
    "oysterbay",
    "mikocheni",
    "upanga",
    "paje",
    "nungwi",
    "stone town",
    "kenyan in",
    "ugandan in",
    "south african in",
    "indian in",
    "chinese in",
    "british in",
    "american in",
    "french in",
    "german in",
    "diplomat",
    "in-tz",
    "corridor=in_tz",
  ];
  if (expatInTzKeywords.some((kw) => lower.includes(kw)) || detectedLang !== "en") {
    return {
      corridor: "expat_in_tz",
      lang: detectedLang,
      city: extractCityLabel(text, "expat_in_tz"),
    };
  }

  // 4. Keywords for Cohort A (Tanzanians living outside Tanzania — Kiswahili)
  const tzAbroadKeywords = [
    "habari",
    "mambo",
    "shikamoo",
    "niaje",
    "safi",
    "karibu",
    "mtanzania",
    "watanzania",
    "ughaibuni",
    "nje ya tanzania",
    "nje ya nchi",
    "tanzanian living abroad",
    "tz diaspora",
    "nipo",
    "naishi",
    "kutoka tanzania",
    "tz",
    "houston",
    "dallas",
    "washington",
    "dmv",
    "london",
    "birmingham",
    "reading",
    "dubai",
    "abu dhabi",
    "oman",
    "muscat",
    "johannesburg",
    "pretoria",
    "nairobi",
    "mombasa",
    "toronto",
    "ottawa",
  ];
  if (tzAbroadKeywords.some((kw) => lower.includes(kw))) {
    return {
      corridor: "tz_abroad",
      lang: "sw",
      city: extractCityLabel(text, "tz_abroad"),
    };
  }

  // 5. Phone country code heuristic when message is a short greeting ("Hi", "Hello", "Start"):
  // If phone is NOT +255 (e.g. +1 US/CA, +44 UK, +971 UAE, +27 SA), check if we should prompt both buttons
  // or default cleanly. Returning "unknown" triggers the 2-button interactive selector on WhatsApp!
  return {
    corridor: "unknown",
    lang: senderPhone.startsWith("+255") ? "en" : "sw",
    city: null,
  };
}

/**
 * Detects native language for non-Tanzanians living in Tanzania
 */
function detectExpatLanguage(text = "") {
  const lower = String(text || "").toLowerCase();
  // Script-level checks
  if (/[\u4e00-\u9fff]/.test(text)) return "zh";
  if (/[\u0900-\u097F]/.test(text)) return "hi";
  if (/[\u0600-\u06FF]/.test(text)) return "ar";

  // Keyword / nationality checks
  if (/\b(bonjour|salut|français|francais|france|congo|rdc|kinshasa|burundi|belgique|senegal|cameroun)\b/.test(lower)) {
    return "fr";
  }
  if (/\b(nihao|ni hao|china|chinese|mandarin|beijing|shanghai|guangzhou)\b/.test(lower)) {
    return "zh";
  }
  if (/\b(namaste|hindi|india|indian|mumbai|delhi|gujarat|gujarati|punjab)\b/.test(lower)) {
    return "hi";
  }
  if (/\b(salam|marhaba|habibi|arabic|oman|uae|egypt|cairo|lebanon|syria|yemen)\b/.test(lower)) {
    return "ar";
  }
  if (/\b(hallo|guten tag|deutsch|germany|german|berlin|munich|austria|swiss)\b/.test(lower)) {
    return "de";
  }
  return "en";
}

/**
 * Extracts a human-readable city label if mentioned in the user's message
 */
function extractCityLabel(text = "", corridor = "tz_abroad") {
  const lower = String(text || "").toLowerCase();
  const knownCities = [
    ["dar es salaam", "Dar es Salaam"],
    ["dar", "Dar es Salaam"],
    ["masaki", "Masaki · Dar es Salaam"],
    ["oysterbay", "Oysterbay · Dar es Salaam"],
    ["arusha", "Arusha"],
    ["zanzibar", "Zanzibar"],
    ["paje", "Paje · Zanzibar"],
    ["stone town", "Stone Town · Zanzibar"],
    ["dodoma", "Dodoma"],
    ["mwanza", "Mwanza"],
    ["moshi", "Moshi · Kilimanjaro"],
    ["houston", "Houston, USA"],
    ["dallas", "Dallas, USA"],
    ["washington", "Washington D.C. / DMV"],
    ["dmv", "DMV (DC · MD · VA)"],
    ["london", "London, UK"],
    ["birmingham", "Birmingham, UK"],
    ["reading", "Reading, UK"],
    ["dubai", "Dubai, UAE"],
    ["abu dhabi", "Abu Dhabi, UAE"],
    ["muscat", "Muscat, Oman"],
    ["johannesburg", "Johannesburg, SA"],
    ["cape town", "Cape Town, SA"],
    ["nairobi", "Nairobi, Kenya"],
    ["toronto", "Toronto, Canada"],
  ];
  for (const [needle, label] of knownCities) {
    if (lower.includes(needle)) return label;
  }
  return corridor === "tz_abroad" ? "Diaspora Global" : "Dar · Arusha · Zanzibar";
}

/**
 * Sends a WhatsApp message (text or interactive buttons) via Meta WhatsApp Cloud API
 */
async function sendWhatsAppCloudMessage({
  phoneNumberId,
  accessToken,
  to,
  type = "text",
  textBody = "",
  interactive = null,
}) {
  const cleanRecipient = String(to || "").replace(/^\+/, "");
  const url = `${GRAPH_API_BASE}/${phoneNumberId}/messages`;
  const headers = {
    "Authorization": `Bearer ${accessToken}`,
    "Content-Type": "application/json",
  };

  const payload = {
    messaging_product: "whatsapp",
    recipient_type: "individual",
    to: cleanRecipient,
    type,
  };

  if (type === "interactive" && interactive) {
    payload.interactive = interactive;
  } else {
    payload.type = "text";
    payload.text = {
      preview_url: true,
      body: textBody,
    };
  }

  const response = await fetch(url, {
    method: "POST",
    headers,
    body: JSON.stringify(payload),
  });

  if (!response.ok) {
    const errText = await response.text();
    console.warn(`[OutreachBot] WhatsApp send failed (${response.status}):`, errText);
    return { ok: false, status: response.status, errorText: errText };
  }

  return { ok: true };
}

/**
 * Sends the 2-button bilingual corridor selector when a user sends a generic greeting
 */
async function sendCorridorSelectorPrompt({ phoneNumberId, accessToken, recipientPhone }) {
  const bodyText =
    "🇹🇿 *Karibu Diaspora Nearby!* / *Welcome to Diaspora Nearby!* 🌍\n\n" +
    "Chagua kundi lako hapa chini ili tukutumie link yako maalum ya kujiunga:\n" +
    "_Please select which describes you below to receive your instant invite link:_";

  const interactive = {
    type: "button",
    body: { text: bodyText },
    action: {
      buttons: [
        {
          type: "reply",
          reply: {
            id: "corridor_tz_abroad",
            title: "🇹🇿 Mtanzania Nje ya TZ",
          },
        },
        {
          type: "reply",
          reply: {
            id: "corridor_in_tz",
            title: "🌍 Expat Living in TZ",
          },
        },
      ],
    },
  };

  const res = await sendWhatsAppCloudMessage({
    phoneNumberId,
    accessToken,
    to: recipientPhone,
    type: "interactive",
    interactive,
  });

  // Fallback to plain text if interactive buttons fail
  if (!res.ok) {
    await sendWhatsAppCloudMessage({
      phoneNumberId,
      accessToken,
      to: recipientPhone,
      type: "text",
      textBody:
        `${bodyText}\n\n` +
        `1️⃣ Jibu *TZ* kama wewe ni Mtanzania unayeishi nje ya Tanzania 🇹🇿\n` +
        `2️⃣ Reply *EXPAT* (or your home country) if you are living in Tanzania from abroad 🌍`,
    });
  }
}

/**
 * Processes incoming WhatsApp messages from Meta Cloud API webhook (invoked by auth.whatsappWebhook)
 */
async function handleIncomingWhatsAppMessages(webhookValue) {
  const accessToken = process.env.WHATSAPP_ACCESS_TOKEN;
  const phoneNumberId =
    (webhookValue.metadata && webhookValue.metadata.phone_number_id) ||
    process.env.WHATSAPP_PHONE_NUMBER_ID;

  if (!accessToken || !phoneNumberId) {
    console.warn("[OutreachBot] Missing WHATSAPP_ACCESS_TOKEN or WHATSAPP_PHONE_NUMBER_ID.");
    return;
  }

  const messages = Array.isArray(webhookValue.messages) ? webhookValue.messages : [];
  const contacts = Array.isArray(webhookValue.contacts) ? webhookValue.contacts : [];
  const profileName = contacts[0]?.profile?.name || "";

  for (const msg of messages) {
    const rawFrom = String(msg.from || "").trim();
    if (!rawFrom) continue;

    const e164Phone = rawFrom.startsWith("+") ? rawFrom : `+${rawFrom}`;
    const parsed = parsePhoneNumberFromString(e164Phone);
    const normalizedPhone = parsed && parsed.isValid() ? parsed.number : e164Phone;

    // Extract text from regular message or interactive button reply
    let incomingText = "";
    if (msg.type === "text" && msg.text?.body) {
      incomingText = msg.text.body;
    } else if (msg.type === "interactive") {
      incomingText =
        msg.interactive?.button_reply?.id ||
        msg.interactive?.button_reply?.title ||
        msg.interactive?.list_reply?.id ||
        msg.interactive?.list_reply?.title ||
        "";
    } else if (msg.type === "button" && msg.button?.text) {
      incomingText = msg.button.text;
    }

    if (!incomingText) continue;

    const intent = classifyOutreachIntent(incomingText, normalizedPhone);
    const leadId = stableHash(`lead:${normalizedPhone}`);
    const leadRef = db.collection("outreach_leads").doc(leadId);

    if (intent.corridor === "unknown") {
      await leadRef.set(
        {
          phoneNumber: normalizedPhone,
          profileName,
          corridor: "pending_selection",
          lastMessage: incomingText.slice(0, 280),
          lastInboundAt: admin.firestore.FieldValue.serverTimestamp(),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true }
      );

      await sendCorridorSelectorPrompt({
        phoneNumberId,
        accessToken,
        recipientPhone: normalizedPhone,
      });
      continue;
    }

    const prefix = intent.corridor === "tz_abroad" ? "TZ" : "EX";
    const referralCode = buildOutreachCode(prefix, normalizedPhone);

    // Record lead in Firestore for conversion attribution & 20h follow-up cron
    await leadRef.set(
      {
        phoneNumber: normalizedPhone,
        profileName,
        corridor: intent.corridor,
        lang: intent.lang,
        city: intent.city,
        referralCode,
        status: "link_sent",
        followUpSent: false,
        lastMessage: incomingText.slice(0, 280),
        lastInboundAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );

    if (intent.corridor === "tz_abroad") {
      // Send Kiswahili welcome + personal link
      await sendWhatsAppCloudMessage({
        phoneNumberId,
        accessToken,
        to: normalizedPhone,
        type: "text",
        textBody: KISWAHILI_DIASPORA_PACK.welcome(referralCode, intent.city),
      });

      // Send forwardable Kiswahili WhatsApp Group invite card
      await sendWhatsAppCloudMessage({
        phoneNumberId,
        accessToken,
        to: normalizedPhone,
        type: "text",
        textBody: KISWAHILI_DIASPORA_PACK.forwardCard(referralCode),
      });
    } else {
      // Cohort B: Expats in Tanzania — English or detected native language
      const pack = EXPAT_NATIVE_PACKS[intent.lang] || EXPAT_NATIVE_PACKS.en;
      await sendWhatsAppCloudMessage({
        phoneNumberId,
        accessToken,
        to: normalizedPhone,
        type: "text",
        textBody: pack.welcome(referralCode, intent.city),
      });

      await sendWhatsAppCloudMessage({
        phoneNumberId,
        accessToken,
        to: normalizedPhone,
        type: "text",
        textBody: pack.forwardCard(referralCode),
      });
    }
  }
}

/**
 * Scheduled Cron: Runs every 2 hours to send a single reminder inside Meta's free 24h
 * customer-initiated window (between 18h and 23h after inbound contact) if the user
 * hasn't completed Firebase Auth registration yet.
 */
exports.outreachFollowUpCron = functions
  .runWith({
    timeoutSeconds: 180,
    memory: "256MB",
    secrets: ["WHATSAPP_ACCESS_TOKEN", "WHATSAPP_PHONE_NUMBER_ID"],
  })
  .pubsub.schedule("every 2 hours")
  .onRun(async () => {
    const accessToken = process.env.WHATSAPP_ACCESS_TOKEN;
    const phoneNumberId = process.env.WHATSAPP_PHONE_NUMBER_ID;
    if (!accessToken || !phoneNumberId) {
      return null;
    }

    const now = Date.now();
    const minAgeMs = 18 * 60 * 60 * 1000; // 18 hours ago
    const maxAgeMs = 23.5 * 60 * 60 * 1000; // 23.5 hours ago (inside 24h free window)
    const minTimestamp = admin.firestore.Timestamp.fromMillis(now - maxAgeMs);
    const maxTimestamp = admin.firestore.Timestamp.fromMillis(now - minAgeMs);

    const snapshot = await db
      .collection("outreach_leads")
      .where("status", "==", "link_sent")
      .where("followUpSent", "==", false)
      .where("lastInboundAt", ">=", minTimestamp)
      .where("lastInboundAt", "<=", maxTimestamp)
      .limit(50)
      .get();

    for (const doc of snapshot.docs) {
      const lead = doc.data() || {};
      const phoneNumber = lead.phoneNumber;
      if (!phoneNumber) continue;

      // Check if user already registered in Firebase Auth
      let isRegistered = false;
      try {
        await admin.auth().getUserByPhoneNumber(phoneNumber);
        isRegistered = true;
      } catch (_err) {
        isRegistered = false;
      }

      if (isRegistered) {
        await doc.ref.set(
          {
            status: "converted",
            convertedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          { merge: true }
        );
        continue;
      }

      const code = lead.referralCode || buildOutreachCode("TZ", phoneNumber);
      const reminderText =
        lead.corridor === "tz_abroad"
          ? KISWAHILI_DIASPORA_PACK.followUp(code)
          : (EXPAT_NATIVE_PACKS[lead.lang] || EXPAT_NATIVE_PACKS.en).followUp(code);

      const res = await sendWhatsAppCloudMessage({
        phoneNumberId,
        accessToken,
        to: phoneNumber,
        type: "text",
        textBody: reminderText,
      });

      await doc.ref.set(
        {
          followUpSent: true,
          followUpSentAt: admin.firestore.FieldValue.serverTimestamp(),
          followUpResult: res.ok ? "sent" : "failed",
        },
        { merge: true }
      );
    }

    return null;
  });

/**
 * Facebook Page & Instagram Comment-to-DM Webhook
 * - GET: Responds to Meta hub.challenge verification
 * - POST: Listens for comments on Diaspora Nearby Facebook Page posts and automatically:
 *   1) Replies publicly to the comment (Kiswahili for TZ Diaspora / English or native lang for Expats in TZ)
 *   2) Sends a Private Reply DM with their direct corridor onboarding link & WhatsApp link
 */
exports.metaOutreachWebhook = functions.https.onRequest(async (req, res) => {
  if (req.method === "GET") {
    const mode = req.query["hub.mode"];
    const token = req.query["hub.verify_token"];
    const challenge = req.query["hub.challenge"];
    const expectedToken =
      process.env.META_WEBHOOK_VERIFY_TOKEN ||
      process.env.WHATSAPP_WEBHOOK_VERIFY_TOKEN ||
      "diaspora_webhook_2026";

    if (mode === "subscribe" && token === expectedToken) {
      return res.status(200).send(challenge);
    }
    return res.status(403).send("Forbidden");
  }

  if (req.method !== "POST") {
    return res.status(405).send("Method Not Allowed");
  }

  try {
    const socialMedia = require("./social_media");
    await socialMedia.ensureSocialConfigEnv();

    const pageAccessToken =
      process.env.META_PAGE_ACCESS_TOKEN || process.env.FACEBOOK_PAGE_ACCESS_TOKEN;
    const pageId = process.env.META_PAGE_ID || "455143491012634";
    const body = req.body || {};

    if (pageAccessToken && Array.isArray(body.entry)) {
      for (const entry of body.entry) {
        const changes = Array.isArray(entry.changes) ? entry.changes : [];
        for (const change of changes) {
          const val = change.value || {};
          // Handle new comments on the Facebook Page feed
          if (
            change.field === "feed" &&
            val.item === "comment" &&
            val.verb === "add" &&
            val.comment_id &&
            String(val.from?.id || "") !== String(pageId)
          ) {
            const commentId = val.comment_id;
            const messageText = String(val.message || "").trim();
            const commenterId = String(val.from?.id || commentId);

            // Prevent duplicate auto-replies to the same comment
            const logRef = db.collection("_socialMetaCommentReplies").doc(stableHash(commentId));
            const existing = await logRef.get();
            if (existing.exists) continue;

            const intent = classifyOutreachIntent(messageText, "");
            const isExpat = intent.corridor === "expat_in_tz";
            const code = buildOutreachCode(isExpat ? "EX" : "TZ", commenterId);
            const pack = isExpat
              ? EXPAT_NATIVE_PACKS[intent.lang] || EXPAT_NATIVE_PACKS.en
              : KISWAHILI_DIASPORA_PACK;

            const dmText = isExpat
              ? pack.welcome(code, intent.city || "Dar · Arusha · Zanzibar")
              : KISWAHILI_DIASPORA_PACK.welcome(code, intent.city || "Diaspora Global");

            const publicReplyText = isExpat
              ? pack.commentReply
              : KISWAHILI_DIASPORA_PACK.commentReply;

            // 1. Send Private Reply DM to the commenter
            let dmOk = false;
            try {
              const dmRes = await fetch(`${GRAPH_API_BASE}/${commentId}/private_replies`, {
                method: "POST",
                headers: { "Content-Type": "application/json" },
                body: JSON.stringify({
                  message: dmText,
                  access_token: pageAccessToken,
                }),
              });
              dmOk = dmRes.ok;
            } catch (dmErr) {
              console.warn("[MetaOutreach] Private reply warning:", dmErr.message);
            }

            // 2. Reply publicly to the comment to boost organic post ranking
            let commentReplyOk = false;
            try {
              const replyRes = await fetch(`${GRAPH_API_BASE}/${commentId}/comments`, {
                method: "POST",
                headers: { "Content-Type": "application/json" },
                body: JSON.stringify({
                  message: publicReplyText,
                  access_token: pageAccessToken,
                }),
              });
              commentReplyOk = replyRes.ok;
            } catch (repErr) {
              console.warn("[MetaOutreach] Public comment reply warning:", repErr.message);
            }

            await logRef.set({
              commentId,
              commenterId,
              messageText: messageText.slice(0, 280),
              corridor: isExpat ? "expat_in_tz" : "tz_abroad",
              lang: intent.lang || "sw",
              referralCode: code,
              dmOk,
              commentReplyOk,
              repliedAt: admin.firestore.FieldValue.serverTimestamp(),
            });
          }
        }
      }
    }

    return res.status(200).send("EVENT_RECEIVED");
  } catch (err) {
    console.error("[MetaOutreach] Webhook error:", err.message);
    return res.status(200).send("EVENT_RECEIVED");
  }
});

/**
 * HTTPS: Direct WhatsApp Group Admin & Member Batch Dispatcher
 * POST /dispatchGroupOutreachBatch
 * Prioritizes Group Admins first, sends tailored Kiswahili (tz_abroad) or
 * English/Native-Language (expat_in_tz) outreach messages, and logs leads in Firestore.
 */
exports.dispatchGroupOutreachBatch = functions
  .runWith({
    timeoutSeconds: 300,
    memory: "256MB",
    secrets: ["WHATSAPP_ACCESS_TOKEN", "WHATSAPP_PHONE_NUMBER_ID"],
  })
  .https.onRequest(async (req, res) => {
    if (req.method !== "POST") {
      return res.status(405).json({ error: "Method Not Allowed. Use POST." });
    }

    const accessToken = process.env.WHATSAPP_ACCESS_TOKEN;
    const phoneNumberId = process.env.WHATSAPP_PHONE_NUMBER_ID;
    if (!accessToken || !phoneNumberId) {
      return res.status(500).json({ error: "WhatsApp Cloud API credentials not configured." });
    }

    try {
      const {
        corridor = "tz_abroad",
        groupName = "Diaspora Group",
        hostRegion = "Tanzania & Global",
        contacts = [],
      } = req.body || {};

      if (!Array.isArray(contacts) || contacts.length === 0) {
        return res.status(400).json({ error: "Provide a non-empty contacts array." });
      }

      // Sort Admins first
      const sorted = [...contacts].sort((a, b) => (a.role === "admin" ? -1 : 1)).slice(0, 50);
      const results = [];

      for (const item of sorted) {
        const parsed = parsePhoneNumberFromString(String(item.phone || ""));
        const normalizedPhone = parsed && parsed.isValid() ? parsed.number : String(item.phone || "").trim();
        if (!normalizedPhone) continue;

        const role = item.role === "admin" ? "admin" : "member";
        const code = item.code || buildOutreachCode(role === "admin" ? "ADM" : "TZ", normalizedPhone);
        const lang = item.lang || (corridor === "tz_abroad" ? "sw" : detectExpatLanguage(item.name || ""));
        const messageBody =
          item.message ||
          (corridor === "tz_abroad"
            ? KISWAHILI_DIASPORA_PACK.welcome(code, hostRegion)
            : (EXPAT_NATIVE_PACKS[lang] || EXPAT_NATIVE_PACKS.en).welcome(code, hostRegion));

        const delivery = await sendWhatsAppCloudMessage({
          phoneNumberId,
          accessToken,
          to: normalizedPhone,
          type: "text",
          textBody: messageBody,
        });

        await db
          .collection("outreach_leads")
          .doc(stableHash(`lead:${normalizedPhone}`))
          .set(
            {
              phoneNumber: normalizedPhone,
              profileName: item.name || "",
              role,
              groupName,
              hostRegion,
              corridor,
              lang,
              referralCode: code,
              status: delivery.ok ? "link_sent" : "wa_link_generated",
              followUpSent: false,
              updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            },
            { merge: true }
          );

        results.push({
          phone: normalizedPhone,
          name: item.name || "",
          role,
          lang,
          code,
          cloudDeliveryOk: delivery.ok,
          waDirectLink: `https://wa.me/${normalizedPhone.replace(/^\+/, "")}?text=${encodeURIComponent(messageBody)}`,
        });

        await new Promise((r) => setTimeout(r, 800));
      }

      return res.status(200).json({
        success: true,
        groupName,
        corridor,
        totalProcessed: results.length,
        adminsCount: results.filter((r) => r.role === "admin").length,
        membersCount: results.filter((r) => r.role === "member").length,
        results,
      });
    } catch (err) {
      console.error("[dispatchGroupOutreachBatch] Error:", err.message);
      return res.status(500).json({ error: err.message });
    }
  });

module.exports = {
  EXPAT_NATIVE_PACKS,
  KISWAHILI_DIASPORA_PACK,
  classifyOutreachIntent,
  detectExpatLanguage,
  handleIncomingWhatsAppMessages,
  outreachFollowUpCron: exports.outreachFollowUpCron,
  metaOutreachWebhook: exports.metaOutreachWebhook,
  dispatchGroupOutreachBatch: exports.dispatchGroupOutreachBatch,
};
