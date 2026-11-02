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
      `🌍 *Welcome to Diaspora Nearby — ${cityLabel} Community Hub!*\n\n` +
      `Everything you need to connect and thrive in one app:\n` +
      `1️⃣ *Nearby Discovery*: Instantly see compatriots from your home country around you in ${cityLabel}.\n` +
      `2️⃣ *Nearby Notifications*: Real-time proximity alerts the moment someone from home is nearby.\n` +
      `3️⃣ *Live Homeland Radio*: Stream live radio stations from back home & Tanzania 24/7.\n` +
      `4️⃣ *Ubuntu Emergency Fund*: Transparent, verified community emergency & mutual-aid support.\n` +
      `5️⃣ *DDI Community Loans*: Community-backed Diaspora Direct Investment loans to fund projects & businesses.\n\n` +
      `📲 *1-Tap Download (Android & iOS):*\nhttps://diasporanearby.com/invite?code=${code}\n` +
      `🎁 *Invite Code:* \`${code}\`\n\n` +
      `_Sign in with this WhatsApp number inside the app to join your ${cityLabel} hub immediately!_`,
    forwardCard: (code) =>
      `🌍 *Expats & International Community in Tanzania (Dar · Arusha · Zanzibar)* 🇹🇿\n\n` +
      `Join our community on *Diaspora Nearby* for:\n` +
      `📍 *Nearby Discovery & Instant Proximity Alerts* when compatriots are around you\n` +
      `📻 *Live Homeland Radio* streaming 24/7\n` +
      `🤝 *Ubuntu Emergency Fund* & *DDI Community Loans*\n\n` +
      `Download & check who is near you right now:\n` +
      `👉 https://diasporanearby.com/invite?code=${code}`,
    followUp: (code) =>
      `👋 Quick reminder from *Diaspora Nearby*! People from your corridor are checking in on the Nearby Radar.\n\n` +
      `Tap below to turn on *Nearby Discovery & Notifications*, listen to *Live Radio*, and access the *Ubuntu Emergency Fund & DDI Loans* (\`${code}\`):\n` +
      `👉 https://diasporanearby.com/invite?code=${code}`,
    commentReply: "Welcome! 🌍 We just sent your direct invite link to your DM inbox 📩",
  },
  fr: {
    langName: "Français",
    welcome: (code, cityLabel) =>
      `🌍 *Bienvenue sur Diaspora Nearby — Hub Communautaire (${cityLabel}) !*\n\n` +
      `Retrouvez les 5 outils essentiels de votre communauté :\n` +
      `1️⃣ *Découverte à Proximité (Nearby Discovery)* : Voyez vos compatriotes autour de vous à ${cityLabel}.\n` +
      `2️⃣ *Alertes de Proximité (Nearby Notifications)* : Notification instantanée dès qu'un compatriote est proche.\n` +
      `3️⃣ *Radio en Direct* : Écoutez les radios du pays en direct 24h/24.\n` +
      `4️⃣ *Fonds d'Urgence Ubuntu* : Entraide communautaire transparente en cas d'urgence.\n` +
      `5️⃣ *Prêts Communautaires DDI* : Financement participatif pour vos projets et entreprises.\n\n` +
      `📲 *Téléchargement direct (Android & iOS) :*\nhttps://diasporanearby.com/invite?code=${code}\n` +
      `🎁 *Code :* \`${code}\``,
    forwardCard: (code) =>
      `🌍 *Communauté Francophone & Expatriés en Tanzanie (Dar · Arusha · Zanzibar)* 🇹🇿\n\n` +
      `Rejoignez-nous sur *Diaspora Nearby* : Découverte & Alertes de proximité, Radio du pays en direct, Fonds d'urgence Ubuntu et Prêts DDI :\n` +
      `👉 https://diasporanearby.com/invite?code=${code}`,
    followUp: (code) =>
      `👋 Rappel de *Diaspora Nearby* ! Activez vos alertes de proximité et retrouvez vos compatriotes dès maintenant (\`${code}\`) :\n` +
      `👉 https://diasporanearby.com/invite?code=${code}`,
    commentReply: "Bienvenue ! 🌍 Nous venons de vous envoyer votre lien d'invitation en message privé (DM) 📩",
  },
  zh: {
    langName: "中文 (Mandarin)",
    welcome: (code, cityLabel) =>
      `🌍 *欢迎加入 Diaspora Nearby — 坦桑尼亚与全球侨民社区 (${cityLabel})！*\n\n` +
      `五大核心功能为您服务：\n` +
      `1️⃣ *附近同胞发现 (Nearby Discovery)*：实时查看您身边的华人与同胞。\n` +
      `2️⃣ *附近实时提醒 (Nearby Notification)*：当同胞在附近时立即收到通知。\n` +
      `3️⃣ *家乡在线广播 (Live Radio)*：24小时收听家乡与本地电台。\n` +
      `4️⃣ *Ubuntu 紧急互助基金*：透明可靠的社区紧急与互助保障。\n` +
      `5️⃣ *DDI 社区投资贷款*：社区金库支持的创业与项目贷款。\n\n` +
      `📲 *一键下载应用 (Android & iOS)：*\nhttps://diasporanearby.com/invite?code=${code}\n` +
      `🎁 *邀请码：* \`${code}\``,
    forwardCard: (code) =>
      `🌍 *坦桑尼亚华人与国际侨民社区 (达累斯萨拉姆 · 阿鲁沙 · 桑给巴尔)* 🇹🇿\n\n` +
      `加入 *Diaspora Nearby*：开启附近同胞雷达提醒、收听家乡电台、加入 Ubuntu 互助基金与 DDI 社区贷款：\n` +
      `👉 https://diasporanearby.com/invite?code=${code}`,
    followUp: (code) =>
      `👋 *Diaspora Nearby* 温馨提醒：点击下方链接即可开启附近同胞发现与提醒 (\`${code}\`)：\n` +
      `👉 https://diasporanearby.com/invite?code=${code}`,
    commentReply: "欢迎！🌍 我们已将您的专属邀请链接发送至您的私信 (DM) 📩",
  },
  hi: {
    langName: "हिन्दी (Hindi)",
    welcome: (code, cityLabel) =>
      `🌍 *नमस्ते! Diaspora Nearby में आपका स्वागत है (${cityLabel})!*\n\n` +
      `5 मुख्य सुविधाएँ आपके लिए:\n` +
      `1️⃣ *Nearby Discovery*: अपने आस-पास के देशवासियों को तुरंत खोजें।\n` +
      `2️⃣ *Nearby Notifications*: जब कोई देशवासी पास हो तो तुरंत अलर्ट पाएं।\n` +
      `3️⃣ *Live Radio*: देश और स्थानीय रेडियो स्टेशन 24/7 लाइव सुनें।\n` +
      `4️⃣ *Ubuntu Emergency Fund*: आपातकालीन स्थिति में पारदर्शी सामुदायिक सहायता।\n` +
      `5️⃣ *DDI Loans*: व्यापार और प्रोजेक्ट्स के लिए सामुदायिक ऋण।\n\n` +
      `📲 *ऐप डाउनलोड करें (Android & iOS):*\nhttps://diasporanearby.com/invite?code=${code}\n` +
      `🎁 *कोड:* \`${code}\``,
    forwardCard: (code) =>
      `🌍 *तंजानिया में भारतीय और अंतर्राष्ट्रीय समुदाय (Dar · Arusha · Zanzibar)* 🇹🇿\n\n` +
      `अपने आस-पास के देशवासियों को खोजने, लाइव रेडियो सुनने और Ubuntu Emergency Fund व DDI Loans से जुड़ने के लिए *Diaspora Nearby* डाउनलोड करें:\n` +
      `👉 https://diasporanearby.com/invite?code=${code}`,
    followUp: (code) =>
      `👋 *Diaspora Nearby* रिमाइंडर! अपने आस-पास के देशवासियों से जुड़ने के लिए अभी डाउनलोड करें (\`${code}\`):\n` +
      `👉 https://diasporanearby.com/invite?code=${code}`,
    commentReply: "नमस्ते! 🌍 हमने आपका आमंत्रण लिंक आपके इनबॉक्स (DM) में भेज दिया है 📩",
  },
  ar: {
    langName: "العربية (Arabic)",
    welcome: (code, cityLabel) =>
      `🌍 *مرحباً بك في Diaspora Nearby — ملتقى الجاليات (${cityLabel})!*\n\n` +
      `5 خدمات أساسية في تطبيق واحد:\n` +
      `1️⃣ *اكتشاف القريبين (Nearby Discovery)*: تعرّف على أبناء بلدك بالقرب منك.\n` +
      `2️⃣ *إشعارات القرب الفورية (Nearby Notification)*: تنبيه فوري عند وجود شخص من بلدك بجوارك.\n` +
      `3️⃣ *راديو الوطن مباشر (Live Radio)*: استمع إلى إذاعات الوطن مباشرة على مدار الساعة.\n` +
      `4️⃣ *صندوق طوارئ أوبونتو (Ubuntu Emergency Fund)*: تكافل مجتمعي شفاف في حالات الطوارئ.\n` +
      `5️⃣ *قروض المجتمع (DDI Loans)*: تمويل مجتمعي لدعم المشاريع والأعمال.\n\n` +
      `📲 *تحميل التطبيق (Android & iOS):*\nhttps://diasporanearby.com/invite?code=${code}\n` +
      `🎁 *رمز الدعوة:* \`${code}\``,
    forwardCard: (code) =>
      `🌍 *الجاليات العربية والدولية في تنزانيا (دار السلام · أروشا · زنجبار)* 🇹🇿\n\n` +
      `انضم إلينا على *Diaspora Nearby* لاكتشاف أبناء الجالية بالقرب منك، والاستماع لراديو الوطن، وصندوق الطوارئ وقروض DDI:\n` +
      `👉 https://diasporanearby.com/invite?code=${code}`,
    followUp: (code) =>
      `👋 تذكير من *Diaspora Nearby*! حمّل التطبيق الآن وفعّل تنبيهات القرب (\`${code}\`):\n` +
      `👉 https://diasporanearby.com/invite?code=${code}`,
    commentReply: "أهلاً بك! 🌍 لقد أرسلنا رابط الدعوة الخاص بك إلى رسائلك الخاصة (DM) 📩",
  },
  de: {
    langName: "Deutsch",
    welcome: (code, cityLabel) =>
      `🌍 *Willkommen bei Diaspora Nearby — Community Hub (${cityLabel})!*\n\n` +
      `5 Kernfunktionen für Ihre Community:\n` +
      `1️⃣ *Nearby Discovery*: Landsleute in Ihrer direkten Umgebung entdecken.\n` +
      `2️⃣ *Nearby Notifications*: Echtzeit-Benachrichtigung, sobald Landsleute in der Nähe sind.\n` +
      `3️⃣ *Live Radio*: Heimat- und Lokalradio 24/7 live hören.\n` +
      `4️⃣ *Ubuntu Emergency Fund*: Transparente Notfall- und Gemeinschaftshilfe.\n` +
      `5️⃣ *DDI Loans*: Gemeinschaftsfinanzierte Kredite für Projekte & Unternehmen.\n\n` +
      `📲 *Direkt-Download (Android & iOS):*\nhttps://diasporanearby.com/invite?code=${code}\n` +
      `🎁 *Einladungscode:* \`${code}\``,
    forwardCard: (code) =>
      `🌍 *Deutschsprachige & Internationale Community in Tansania (Dar · Arusha · Sansibar)* 🇹🇿\n\n` +
      `Vernetzt euch auf *Diaspora Nearby*: Nearby Discovery & Alerts, Live Radio, Ubuntu Notfallfonds & DDI Kredite:\n` +
      `👉 https://diasporanearby.com/invite?code=${code}`,
    followUp: (code) =>
      `👋 Kurze Erinnerung von *Diaspora Nearby*! Jetzt App laden und Landsleute in der Nähe entdecken (\`${code}\`):\n` +
      `👉 https://diasporanearby.com/invite?code=${code}`,
    commentReply: "Willkommen! 🌍 Wir haben Ihnen Ihren Einladungslink gerade per DM geschickt 📩",
  },
};

// ── Cohort A Pack: Kiswahili for Tanzanians (Abroad & Homeland Corridors) ──
const KISWAHILI_DIASPORA_PACK = {
  welcome: (code, cityLabel) =>
    `🇹🇿 *Karibu Sana Diaspora Nearby — Jumuiya ya Watanzania (${cityLabel})!* 🌍\n\n` +
    `Huduma 5 muhimu ndani ya app moja kwa kila Mtanzania (ughaibuni na nyumbani):\n\n` +
    `1️⃣ *Nearby Discovery (Watanzania Karibu Nawe)*: Ona na ufahamiane na Watanzania wenzako walio mji, chuo, au mtaa mmoja na wewe.\n` +
    `2️⃣ *Nearby Notification (Taarifa za Papo Hapo)*: Pata ujumbe (alert) kwenye simu yako punde tu Mtanzania mwenzako anapokuwa karibu nawe.\n` +
    `3️⃣ *Redio za Nyumbani Live (Radio)*: Sikiliza redio za Tanzania live saa 24 popote ulipo duniani.\n` +
    `4️⃣ *Ubuntu Emergency Fund (Mfuko wa Dharura na Msiba)*: Kusaidiana kwenye dharura na msiba kwa uwazi na uaminifu.\n` +
    `5️⃣ *DDI Loans (Mikopo ya Uwekezaji ya Jumuiya)*: Mikopo inayotokana na hazina ya jumuiya yetu kukuza biashara na miradi nyumbani na ughaibuni.\n\n` +
    `📲 *Bonyeza Hapa Kupakua App (Android & iPhone):*\nhttps://diasporanearby.com/invite?code=${code}\n` +
    `🎁 *Kodi ya Mwaliko:* \`${code}\`\n\n` +
    `_Jisajili ndani ya app kwa namba hii ya WhatsApp ili uunganishwe moja kwa moja na Watanzania wa ${cityLabel}!_`,

  forwardCard: (code) =>
    `🇹🇿 *Watanzania Wenzangu — Tupo Wangapi Kwenye Mji Huu?* 🌍\n\n` +
    `Pakua app ya *Diaspora Nearby* upate huduma hizi 5:\n` +
    `📍 *Nearby Discovery*: Ona Watanzania walio karibu nawe mji uliopo\n` +
    `🔔 *Nearby Notification*: Pata taarifa papo hapo Mtanzania anapokuwa jirani\n` +
    `📻 *Live Radio*: Sikiliza redio zote za nyumbani Tanzania live\n` +
    `🤝 *Ubuntu Emergency Fund*: Mfuko rasmi wa kusaidiana kwenye dharura na msiba\n` +
    `🏦 *DDI Loans*: Mikopo ya jumuiya kwa ajili ya biashara na uwekezaji\n\n` +
    `Bonyeza hapa kuangalia Watanzania walio karibu nawe sasa hivi:\n` +
    `👉 https://diasporanearby.com/invite?code=${code}`,

  followUp: (code) =>
    `🇹🇿 *Habari ndugu yangu!* Watanzania wenzako wanaendelea kujiunga kwenye *Diaspora Nearby*.\n\n` +
    `Bonyeza link hii kupakua app (Android au iPhone) ili uwashe *Nearby Discovery & Notification*, usikilize *Redio za Nyumbani Live*, na ujiunge na *Ubuntu Emergency Fund & DDI Loans* (Kodi: \`${code}\`):\n` +
    `👉 https://diasporanearby.com/invite?code=${code}`,

  commentReply:
    "Karibu sana ndugu yetu! 🇹🇿 Tumekutumia link ya kupakua app kwenye inbox yako (DM) sasa hivi 📩",
};

const FOUNDER_INVITE_CODE = "PETER-TZ-CC57";

/**
 * Returns the single invitation code created at signup for Founder Peter Swai
 */
function buildOutreachCode() {
  return FOUNDER_INVITE_CODE;
}

/**
 * Detects corridor ("tz_abroad" | "expat_in_tz" | "unknown"), native language, and city
 * from an incoming WhatsApp message or Facebook comment.
 */
function classifyOutreachIntent(rawText = "", senderPhone = "") {
  const text = String(rawText || "").trim();
  const lower = text.toLowerCase();

  // 1. Explicit button / payload IDs
  if (
    lower.includes("corridor_tz_abroad") ||
    lower.includes("corridor_tz_home") ||
    lower.includes("nje ya tanzania") ||
    lower.includes("nipo tanzania") ||
    lower.includes("mtanzania nje")
  ) {
    return { corridor: "tz_abroad", lang: "sw", city: extractCityLabel(text, "tz_abroad") };
  }
  if (lower.includes("corridor_in_tz") || lower.includes("expat in tz") || lower.includes("expat living in tz")) {
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
    "expat",
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

  // 4. Keywords for Cohort A & Homeland TZ (Kiswahili + all 31 TZ regions, towns & global cities)
  const tzAbroadKeywords = [
    "habari",
    "mambo",
    "jambo",
    "hujambo",
    "shikamoo",
    "niaje",
    "safi",
    "salama",
    "karibu",
    "asante",
    "ahsante",
    "ndio",
    "ndiyo",
    "mtanzania",
    "watanzania",
    "tanzania",
    "ughaibuni",
    "nje ya tanzania",
    "nje ya nchi",
    "tanzanian living abroad",
    "tz diaspora",
    "nipo",
    "naishi",
    "natoka",
    "kutoka",
    "nyumbani",
    "kijiji",
    "wilaya",
    "mkoa",
    "mtaa",
    "tz",
    // All Tanzania regions & major towns
    "dar es salaam",
    "dar",
    "arusha",
    "zanzibar",
    "unguja",
    "pemba",
    "mwanza",
    "dodoma",
    "moshi",
    "kilimanjaro",
    "iringa",
    "ilula",
    "mbeya",
    "tanga",
    "morogoro",
    "bukoba",
    "kagera",
    "songea",
    "ruvuma",
    "mtwara",
    "lindi",
    "tabora",
    "kigoma",
    "shinyanga",
    "geita",
    "simiyu",
    "bariadi",
    "mara",
    "musoma",
    "singida",
    "njombe",
    "rukwa",
    "sumbawanga",
    "katavi",
    "mpanda",
    "manyara",
    "babati",
    "pwani",
    "kibaha",
    "bagamoyo",
    "songwe",
    "vwawa",
    "tunduma",
    "makambako",
    "ifakara",
    "kahama",
    "korogwe",
    "lushoto",
    // Global diaspora hubs
    "houston",
    "dallas",
    "washington",
    "dmv",
    "atlanta",
    "new york",
    "phoenix",
    "columbus",
    "chicago",
    "seattle",
    "california",
    "london",
    "birmingham",
    "reading",
    "manchester",
    "slough",
    "dubai",
    "abu dhabi",
    "sharjah",
    "oman",
    "muscat",
    "doha",
    "qatar",
    "johannesburg",
    "pretoria",
    "cape town",
    "durban",
    "nairobi",
    "mombasa",
    "kampala",
    "kigali",
    "lubumbashi",
    "lusaka",
    "toronto",
    "ottawa",
    "montreal",
    "calgary",
    "berlin",
    "frankfurt",
    "stockholm",
    "istanbul",
    "guangzhou",
    "beijing",
    "wuhan",
    "mumbai",
    "delhi",
    "bangalore",
  ];
  if (tzAbroadKeywords.some((kw) => lower.includes(kw))) {
    return {
      corridor: "tz_abroad",
      lang: "sw",
      city: extractCityLabel(text, "tz_abroad"),
    };
  }

  // 5. If sender has a +255 Tanzanian phone number and sends a greeting or media, default to Kiswahili pack!
  if (String(senderPhone || "").startsWith("+255")) {
    return {
      corridor: "tz_abroad",
      lang: "sw",
      city: extractCityLabel(text, "tz_abroad"),
    };
  }

  // 6. Otherwise return "unknown" so the interactive 3-button selector is sent (with the direct link included!)
  return {
    corridor: "unknown",
    lang: "sw",
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
    ["masaki", "Masaki · Dar es Salaam"],
    ["oysterbay", "Oysterbay · Dar es Salaam"],
    ["mikocheni", "Mikocheni · Dar es Salaam"],
    ["upanga", "Upanga · Dar es Salaam"],
    ["dar", "Dar es Salaam"],
    ["arusha", "Arusha"],
    ["zanzibar", "Zanzibar"],
    ["paje", "Paje · Zanzibar"],
    ["stone town", "Stone Town · Zanzibar"],
    ["dodoma", "Dodoma"],
    ["mwanza", "Mwanza"],
    ["moshi", "Moshi · Kilimanjaro"],
    ["kilimanjaro", "Kilimanjaro"],
    ["iringa", "Iringa"],
    ["ilula", "Ilula · Iringa"],
    ["mbeya", "Mbeya"],
    ["tanga", "Tanga"],
    ["morogoro", "Morogoro"],
    ["bukoba", "Bukoba · Kagera"],
    ["kagera", "Kagera"],
    ["songea", "Songea · Ruvuma"],
    ["ruvuma", "Ruvuma"],
    ["mtwara", "Mtwara"],
    ["lindi", "Lindi"],
    ["tabora", "Tabora"],
    ["kigoma", "Kigoma"],
    ["shinyanga", "Shinyanga"],
    ["geita", "Geita"],
    ["simiyu", "Simiyu"],
    ["mara", "Mara"],
    ["musoma", "Musoma · Mara"],
    ["singida", "Singida"],
    ["njombe", "Njombe"],
    ["sumbawanga", "Sumbawanga · Rukwa"],
    ["rukwa", "Rukwa"],
    ["katavi", "Katavi"],
    ["mpanda", "Mpanda · Katavi"],
    ["manyara", "Manyara"],
    ["babati", "Babati · Manyara"],
    ["pwani", "Pwani"],
    ["kibaha", "Kibaha · Pwani"],
    ["bagamoyo", "Bagamoyo · Pwani"],
    ["songwe", "Songwe"],
    ["houston", "Houston, USA"],
    ["dallas", "Dallas, USA"],
    ["washington", "Washington D.C. / DMV"],
    ["dmv", "DMV (DC · MD · VA)"],
    ["atlanta", "Atlanta, USA"],
    ["new york", "New York, USA"],
    ["phoenix", "Phoenix, USA"],
    ["columbus", "Columbus, USA"],
    ["chicago", "Chicago, USA"],
    ["seattle", "Seattle, USA"],
    ["london", "London, UK"],
    ["birmingham", "Birmingham, UK"],
    ["reading", "Reading, UK"],
    ["manchester", "Manchester, UK"],
    ["slough", "Slough, UK"],
    ["dubai", "Dubai, UAE"],
    ["abu dhabi", "Abu Dhabi, UAE"],
    ["muscat", "Muscat, Oman"],
    ["johannesburg", "Johannesburg, SA"],
    ["pretoria", "Pretoria, SA"],
    ["cape town", "Cape Town, SA"],
    ["nairobi", "Nairobi, Kenya"],
    ["mombasa", "Mombasa, Kenya"],
    ["kampala", "Kampala, Uganda"],
    ["kigali", "Kigali, Rwanda"],
    ["toronto", "Toronto, Canada"],
    ["ottawa", "Ottawa, Canada"],
    ["berlin", "Berlin, Germany"],
    ["guangzhou", "Guangzhou, China"],
    ["beijing", "Beijing, China"],
  ];
  for (const [needle, label] of knownCities) {
    if (lower.includes(needle)) return label;
  }
  return corridor === "tz_abroad" ? "Tanzania & Diaspora" : "Dar · Arusha · Zanzibar";
}

/**
 * Extracts both Home City/Country and Host City/Country from a Facebook comment
 * e.g. "Arusha -> Houston", "From Dar living in London", "Kutoka Mwanza nipo Dubai",
 * "Home: Moshi, Host: Washington DC", or "Dar es Salaam / Dallas".
 */
function parseHomeAndHostFromComment(rawText = "") {
  const clean = String(rawText || "").replace(/\s+/g, " ").trim();
  if (!clean) return { homeCity: null, hostCity: null };

  // 1. Explicit labeled pattern: "Home: X, Host: Y" or "Kutoka X nipo/naishi Y" or "From X in/living in Y"
  const labeledMatch =
    clean.match(/(?:home|kutoka|from|born in|nyumbani)\s*[:=-]?\s*([^,;|\->/]+?)\s*(?:[,;|/]|->|to|living in|live in|currently in|in|nipo|naishi|niko|host)\s*[:=-]?\s*([^.!?\n]+)/i) ||
    clean.match(/([^,;|\->/]+?)\s*(?:->|→|=>| to | \/ | \| | - )\s*([^.!?\n]+)/i);

  if (labeledMatch) {
    const rawHome = labeledMatch[1].replace(/^(?:i am|i'm|mimi ni|naitwa)\s+/i, "").trim();
    const rawHost = labeledMatch[2].replace(/^(?:host|now in|living in|nipo|naishi)\s*[:=-]?\s*/i, "").trim();
    if (rawHome.length >= 2 && rawHost.length >= 2 && rawHome.length <= 45 && rawHost.length <= 45) {
      return { homeCity: rawHome, hostCity: rawHost };
    }
  }

  // 2. Check if two known cities appear in the comment
  const tzHomeCities = [
    ["dar es salaam", "Dar es Salaam"],
    ["arusha", "Arusha"],
    ["zanzibar", "Zanzibar"],
    ["mwanza", "Mwanza"],
    ["dodoma", "Dodoma"],
    ["moshi", "Moshi"],
    ["kilimanjaro", "Kilimanjaro"],
    ["mbeya", "Mbeya"],
    ["tanga", "Tanga"],
    ["morogoro", "Morogoro"],
    ["bukoba", "Bukoba"],
    ["iringa", "Iringa"],
    ["ilula", "Ilula, Iringa"],
    ["songea", "Songea"],
    ["mtwara", "Mtwara"],
    ["lindi", "Lindi"],
    ["tabora", "Tabora"],
    ["kigoma", "Kigoma"],
    ["shinyanga", "Shinyanga"],
    ["geita", "Geita"],
    ["musoma", "Musoma"],
    ["singida", "Singida"],
    ["njombe", "Njombe"],
    ["sumbawanga", "Sumbawanga"],
  ];
  const globalCities = [
    ["houston", "Houston, USA"],
    ["dallas", "Dallas, USA"],
    ["washington", "Washington D.C."],
    ["dmv", "DMV, USA"],
    ["atlanta", "Atlanta, USA"],
    ["new york", "New York, USA"],
    ["seattle", "Seattle, USA"],
    ["chicago", "Chicago, USA"],
    ["columbus", "Columbus, USA"],
    ["phoenix", "Phoenix, USA"],
    ["london", "London, UK"],
    ["birmingham", "Birmingham, UK"],
    ["reading", "Reading, UK"],
    ["manchester", "Manchester, UK"],
    ["dubai", "Dubai, UAE"],
    ["abu dhabi", "Abu Dhabi, UAE"],
    ["muscat", "Muscat, Oman"],
    ["johannesburg", "Johannesburg, SA"],
    ["cape town", "Cape Town, SA"],
    ["nairobi", "Nairobi, Kenya"],
    ["mombasa", "Mombasa, Kenya"],
    ["toronto", "Toronto, Canada"],
    ["ottawa", "Ottawa, Canada"],
    ["berlin", "Berlin, Germany"],
    ["guangzhou", "Guangzhou, China"],
    ["beijing", "Beijing, China"],
  ];

  const lower = clean.toLowerCase();
  const matchedTz = tzHomeCities.find(([needle]) => lower.includes(needle));
  const matchedGlobal = globalCities.find(([needle]) => lower.includes(needle));

  if (matchedTz && matchedGlobal) {
    const tzIdx = lower.indexOf(matchedTz[0]);
    const glIdx = lower.indexOf(matchedGlobal[0]);
    if (tzIdx <= glIdx) {
      return { homeCity: matchedTz[1], hostCity: matchedGlobal[1] };
    }
    return { homeCity: matchedGlobal[1], hostCity: matchedTz[1] };
  }

  if (matchedGlobal) {
    return { homeCity: "Tanzania", hostCity: matchedGlobal[1] };
  }
  if (matchedTz) {
    return { homeCity: matchedTz[1], hostCity: null };
  }

  return { homeCity: null, hostCity: null };
}

/**
 * Builds the personalized public comment reply and Private Reply DM for a Facebook commenter
 */
function buildFacebookCommentOnboarding({
  commentText = "",
  commenterName = "",
  commenterId = "",
}) {
  const intent = classifyOutreachIntent(commentText, "");
  const { homeCity, hostCity } = parseHomeAndHostFromComment(commentText);
  const isExpat = intent.corridor === "expat_in_tz";
  const code = buildOutreachCode(isExpat ? "EX" : "TZ", commenterId || commenterName || commentText);
  const firstName = String(commenterName || "").trim().split(/\s+/)[0] || "";
  const inviteUrl = `https://diasporanearby.com/invite?code=${code}`;

  const effectiveHome = homeCity || (isExpat ? "your home country" : "Tanzania");
  const effectiveHost = hostCity || intent.city || (isExpat ? "Tanzania" : "mji wako");

  let publicReplyText;
  if (!isExpat) {
    const nameGreet = firstName ? ` ${firstName}` : "";
    const corridorPhrase = homeCity && hostCity
      ? `kutoka *${effectiveHome}* ukiwa *${effectiveHost}*`
      : hostCity
        ? `ukiwa *${effectiveHost}*`
        : `kutoka *${effectiveHome}*`;
    publicReplyText =
      `Karibu sana${nameGreet}! 🇹🇿🌍 Ungana na Watanzania wenzako ${corridorPhrase} ndani ya *Diaspora Nearby* ` +
      `(Nearby Discovery & Notification, Redio za Nyumbani Live, Ubuntu Emergency Fund, na DDI Loans).\n` +
      `📲 Pakua "Diaspora Nearby" kwenye Google Play / App Store (Kodi: ${code}) au tuma ujumbe WhatsApp: +1 641-302-0012 (diasporanearby [dot] com)`;
  } else {
    const nameGreet = firstName ? `, ${firstName}` : "";
    const corridorPhrase = homeCity && hostCity
      ? `from *${effectiveHome}* living in *${effectiveHost}*`
      : `in *${effectiveHost}*`;
    publicReplyText =
      `Welcome${nameGreet}! 🌍 Connect with fellow compatriots ${corridorPhrase} on *Diaspora Nearby* ` +
      `(Nearby Discovery & Notifications, Live Homeland Radio, Ubuntu Emergency Fund, and DDI Loans).\n` +
      `📲 Search "Diaspora Nearby" on Google Play / App Store (Invite Code: ${code}) or WhatsApp: +1 641-302-0012 (diasporanearby [dot] com)`;
  }

  const pack = isExpat
    ? EXPAT_NATIVE_PACKS[intent.lang] || EXPAT_NATIVE_PACKS.en
    : KISWAHILI_DIASPORA_PACK;
  const dmCityLabel = homeCity && hostCity ? `${effectiveHome} → ${effectiveHost}` : effectiveHost;
  const dmText = isExpat
    ? pack.welcome(code, dmCityLabel)
    : KISWAHILI_DIASPORA_PACK.welcome(code, dmCityLabel);

  return {
    code,
    inviteUrl,
    corridor: isExpat ? "expat_in_tz" : "tz_abroad",
    lang: intent.lang || "sw",
    homeCity: homeCity || null,
    hostCity: hostCity || intent.city || null,
    publicReplyText,
    dmText,
  };
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
 * Sends the 3-button bilingual corridor selector when a user sends a generic greeting.
 * IMPORTANT:
 *   1. All button titles MUST be <= 20 characters (Meta Cloud API hard limit #131009).
 *   2. ALWAYS includes the direct invite link right inside the body so the user never
 *      leaves without a clickable download link!
 */
async function sendCorridorSelectorPrompt({ phoneNumberId, accessToken, recipientPhone }) {
  const code = FOUNDER_INVITE_CODE;
  const inviteUrl = `https://diasporanearby.com/invite?code=${code}`;
  const bodyText =
    `🇹🇿 *Karibu Diaspora Nearby!* / *Welcome!* 🌍\n\n` +
    `Huduma 5 ndani ya app moja:\n` +
    `📍 *Nearby Discovery* (Wenzako Karibu Nawe)\n` +
    `🔔 *Nearby Notification* (Taarifa za Papo Hapo)\n` +
    `📻 *Live Radio* (Redio za Nyumbani Live)\n` +
    `🤝 *Ubuntu Emergency Fund* (Mfuko wa Dharura)\n` +
    `🏦 *DDI Loans* (Mikopo ya Jumuiya)\n\n` +
    `📲 *Pakua App Sasa (Android & iPhone):*\n${inviteUrl}\n` +
    `🎁 *Kodi:* \`${code}\`\n\n` +
    `Chagua kundi lako hapa chini / _Select your group below:_`;

  const interactive = {
    type: "button",
    body: { text: bodyText },
    action: {
      buttons: [
        {
          type: "reply",
          reply: {
            id: "corridor_tz_abroad",
            title: "🇹🇿 Nje ya Tanzania", // 18 chars (<= 20 limit)
          },
        },
        {
          type: "reply",
          reply: {
            id: "corridor_tz_home",
            title: "🇹🇿 Nipo Tanzania", // 16 chars (<= 20 limit)
          },
        },
        {
          type: "reply",
          reply: {
            id: "corridor_in_tz",
            title: "🌍 Expat in TZ", // 14 chars (<= 20 limit)
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
        `1️⃣ Jibu *TZ* kama wewe ni Mtanzania (nje au ndani ya Tanzania) 🇹🇿\n` +
        `2️⃣ Reply *EXPAT* if you are living in Tanzania from abroad 🌍`,
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

    // Extract text from regular message, media caption, or interactive button reply
    let incomingText = "";
    let isMediaWithoutCaption = false;
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
    } else if (msg.image?.caption || msg.video?.caption || msg.document?.caption) {
      incomingText = msg.image?.caption || msg.video?.caption || msg.document?.caption || "";
    } else if (["image", "video", "audio", "document", "sticker", "location"].includes(msg.type)) {
      isMediaWithoutCaption = true;
      incomingText = `[${msg.type}]`;
    }

    if (!incomingText) continue;

    const leadId = stableHash(`lead:${normalizedPhone}`);
    const leadRef = db.collection("outreach_leads").doc(leadId);

    // If user sent media without caption (e.g. a multi-photo album), debounce so we only greet once
    if (isMediaWithoutCaption) {
      const existingSnap = await leadRef.get();
      if (existingSnap.exists) {
        const existingData = existingSnap.data() || {};
        const lastInboundMs =
          existingData.lastInboundAt && typeof existingData.lastInboundAt.toMillis === "function"
            ? existingData.lastInboundAt.toMillis()
            : 0;
        if (
          existingData.status === "link_sent" ||
          existingData.status === "converted" ||
          Date.now() - lastInboundMs < 5 * 60 * 1000
        ) {
          continue;
        }
      }
    }

    const lowerIncoming = incomingText.toLowerCase();
    const isFounder1on1 =
      lowerIncoming.includes("peter") ||
      lowerIncoming.includes("1-on-1") ||
      lowerIncoming.includes("1-kwa-1") ||
      lowerIncoming.includes("1-à-1") ||
      lowerIncoming.includes("1-zu-1") ||
      incomingText.includes("一对一") ||
      incomingText.includes("1-ऑन-1") ||
      incomingText.includes("1-إلى-1");

    const intent = classifyOutreachIntent(incomingText, normalizedPhone);

    if (isFounder1on1) {
      const isSwahili =
        intent.corridor === "tz_abroad" ||
        lowerIncoming.includes("habari") ||
        lowerIncoming.includes("1-kwa-1") ||
        lowerIncoming.includes("nimejiunga");
      const isCallRequest =
        lowerIncoming.includes("call") ||
        lowerIncoming.includes("simu") ||
        lowerIncoming.includes("appel") ||
        lowerIncoming.includes("anruf") ||
        incomingText.includes("通话") ||
        incomingText.includes("कॉल") ||
        incomingText.includes("مكالمة");

      await Promise.all([
        leadRef.set(
          {
            phoneNumber: normalizedPhone,
            profileName,
            status: "founder_1on1_requested",
            founderHelpRequested: true,
            founderHelpType: isCallRequest ? "call" : "text",
            lastMessage: incomingText.slice(0, 500),
            lastInboundAt: admin.firestore.FieldValue.serverTimestamp(),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          { merge: true }
        ),
        db.collection("founder_concierge_requests").add({
          phoneNumber: normalizedPhone,
          profileName,
          requestType: isCallRequest ? "call" : "text",
          lang: isSwahili ? "sw" : intent.lang || "en",
          message: incomingText.slice(0, 500),
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        }),
      ]);

      const founderReply = isSwahili
        ? "🇹🇿 *Ahsante sana kwa kuwasiliana nami!* Mimi ni *Peter Swai*, Mwanzilishi wa Diaspora Nearby.\n\n" +
          "Nimepokea ujumbe wako wa msaada wa 1-kwa-1. Unaweza kunipigia simu ya WhatsApp moja kwa moja hapa sasa hivi (bonyeza kitufe cha Simu / Call juu kulia), au nitakupigia na kukujibu punde tu!\n\n" +
          `📲 Pakua app hapa: https://diasporanearby.com/invite?code=${FOUNDER_INVITE_CODE}\n` +
          "Karibu sana nyumbani kwenye Diaspora Nearby 🙏"
        : "🌍 *Thank you for reaching out!* This is *Peter Swai*, Founder of Diaspora Nearby.\n\n" +
          "I just received your 1-on-1 request. Feel free to tap the WhatsApp Call icon at the top right to call me right now, or I will call/message you right back shortly!\n\n" +
          `📲 Download the app here: https://diasporanearby.com/invite?code=${FOUNDER_INVITE_CODE}\n` +
          "Welcome to Diaspora Nearby 🙏";

      await sendWhatsAppCloudMessage({
        phoneNumberId,
        accessToken,
        to: normalizedPhone,
        type: "text",
        textBody: founderReply,
      });
      continue;
    }

    if (intent.corridor === "unknown") {
      await leadRef.set(
        {
          phoneNumber: normalizedPhone,
          profileName,
          corridor: "tz_abroad",
          lang: "sw",
          referralCode: FOUNDER_INVITE_CODE,
          status: "link_sent",
          followUpSent: false,
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
    const minMs = now - maxAgeMs;
    const maxMs = now - minAgeMs;

    const snapshot = await db
      .collection("outreach_leads")
      .where("status", "==", "link_sent")
      .limit(100)
      .get();

    for (const doc of snapshot.docs) {
      const lead = doc.data() || {};
      if (lead.followUpSent === true) continue;
      const inboundMillis = lead.lastInboundAt && typeof lead.lastInboundAt.toMillis === "function"
        ? lead.lastInboundAt.toMillis()
        : 0;
      if (inboundMillis < minMs || inboundMillis > maxMs) continue;

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

    // Also poll Facebook Page posts for any new Home/Host city comments
    try {
      await pollFacebookPageComments();
    } catch (fbErr) {
      console.warn("[outreachFollowUpCron] Facebook comment poll warning:", fbErr.message);
    }

    return null;
  });

/**
 * Processes a single Facebook comment: parses Home & Host cities, sends Private Reply DM
 * and Public Comment Reply with direct onboarding link, and logs in Firestore.
 */
async function processFacebookComment({
  commentId,
  messageText = "",
  commenterId = "",
  commenterName = "",
  postId = "",
  pageAccessToken = "",
}) {
  if (!commentId || !messageText.trim()) return { skipped: true, reason: "empty" };

  const logRef = db.collection("_socialMetaCommentReplies").doc(stableHash(commentId));
  const existing = await logRef.get();
  if (existing.exists) {
    return { skipped: true, reason: "already_replied", data: existing.data() };
  }

  const onboarding = buildFacebookCommentOnboarding({
    commentText: messageText,
    commenterName,
    commenterId: commenterId || commentId,
  });

  let dmOk = false;
  let commentReplyOk = false;

  if (pageAccessToken) {
    // 1. Send Private Reply DM to the commenter
    try {
      const dmRes = await fetch(`${GRAPH_API_BASE}/${commentId}/private_replies`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          message: onboarding.dmText,
          access_token: pageAccessToken,
        }),
      });
      dmOk = dmRes.ok;
    } catch (dmErr) {
      console.warn("[MetaOutreach] Private reply warning:", dmErr.message);
    }

    // 2. Reply publicly to the comment with personalized Home -> Host onboarding link
    try {
      const replyRes = await fetch(`${GRAPH_API_BASE}/${commentId}/comments`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          message: onboarding.publicReplyText,
          access_token: pageAccessToken,
        }),
      });
      commentReplyOk = replyRes.ok;
    } catch (repErr) {
      console.warn("[MetaOutreach] Public comment reply warning:", repErr.message);
    }
  }

  const record = {
    commentId,
    postId: postId || null,
    commenterId: commenterId || commentId,
    commenterName: commenterName || null,
    messageText: messageText.slice(0, 280),
    homeCity: onboarding.homeCity,
    hostCity: onboarding.hostCity,
    corridor: onboarding.corridor,
    lang: onboarding.lang,
    referralCode: onboarding.code,
    inviteUrl: onboarding.inviteUrl,
    publicReplyText: onboarding.publicReplyText,
    dmOk,
    commentReplyOk,
    repliedAt: admin.firestore.FieldValue.serverTimestamp(),
  };

  await logRef.set(record);
  return { skipped: false, ...record };
}

/**
 * Polls recent posts on the Diaspora Nearby Facebook Page for unreplied comments
 * and replies with their personalized Home -> Host city onboarding link.
 */
async function pollFacebookPageComments({ limitPosts = 15 } = {}) {
  const socialMedia = require("./social_media");
  await socialMedia.ensureSocialConfigEnv();

  const pageAccessToken =
    process.env.META_PAGE_ACCESS_TOKEN || process.env.FACEBOOK_PAGE_ACCESS_TOKEN;
  const pageId = process.env.META_PAGE_ID || "455143491012634";
  if (!pageAccessToken) {
    return { ok: false, error: "Missing META_PAGE_ACCESS_TOKEN" };
  }

  const feedUrl =
    `${GRAPH_API_BASE}/${pageId}/feed?fields=id,message,created_time,comments.limit(50){id,from,message,created_time}` +
    `&limit=${limitPosts}&access_token=${encodeURIComponent(pageAccessToken)}`;

  const res = await fetch(feedUrl);
  if (!res.ok) {
    const errText = await res.text();
    return { ok: false, status: res.status, error: errText };
  }

  const data = await res.json();
  const posts = Array.isArray(data.data) ? data.data : [];
  const processed = [];

  for (const post of posts) {
    const comments = Array.isArray(post.comments?.data) ? post.comments.data : [];
    for (const c of comments) {
      const fromId = String(c.from?.id || "");
      if (fromId === String(pageId)) continue;
      const fromName = String(c.from?.name || "");
      const text = String(c.message || "").trim();
      if (!text) continue;

      const out = await processFacebookComment({
        commentId: c.id,
        messageText: text,
        commenterId: fromId || c.id,
        commenterName: fromName,
        postId: post.id,
        pageAccessToken,
      });
      if (!out.skipped) {
        processed.push(out);
      }
    }
  }

  return { ok: true, postsScanned: posts.length, commentsProcessed: processed.length, processed };
}

/**
 * Facebook Page & Instagram Comment-to-DM Webhook
 * - GET: Responds to Meta hub.challenge verification
 * - POST: Listens for comments on Diaspora Nearby Facebook Page posts and automatically:
 *   1) Extracts Home & Host cities from the comment
 *   2) Replies publicly with a personalized Home -> Host onboarding link
 *   3) Sends a Private Reply DM with their direct corridor onboarding link
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
            await processFacebookComment({
              commentId: val.comment_id,
              messageText: String(val.message || "").trim(),
              commenterId: String(val.from?.id || val.comment_id),
              commenterName: String(val.from?.name || ""),
              postId: String(val.post_id || ""),
              pageAccessToken,
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

/**
 * Helper to normalize user-entered phone numbers from the web Roll-Call check-in
 */
function normalizeWebPhone(rawPhone = "", homeLocation = "", hostLocation = "") {
  const cleaned = String(rawPhone || "").replace(/[^\d+]/g, "").trim();
  if (!cleaned || cleaned.length < 7) return null;

  let candidate = cleaned;
  const combinedLoc = `${homeLocation} ${hostLocation}`.toLowerCase();
  if (!candidate.startsWith("+")) {
    if (candidate.startsWith("0") && candidate.length === 10) {
      // Local 07xx / 06xx format (default to +255 Tanzania or +254 Kenya if mentioned)
      const cc = combinedLoc.includes("kenya") || combinedLoc.includes("nairobi") ? "+254" : "+255";
      candidate = cc + candidate.slice(1);
    } else if (candidate.length === 10 && (combinedLoc.includes("usa") || combinedLoc.includes("houston") || combinedLoc.includes("dallas") || combinedLoc.includes("canada") || combinedLoc.includes("dmv"))) {
      candidate = "+1" + candidate;
    } else {
      candidate = "+" + candidate;
    }
  }

  const parsed = parsePhoneNumberFromString(candidate);
  if (parsed && parsed.isValid()) return parsed.number;
  return /^\+\d{8,15}$/.test(candidate) ? candidate : null;
}

/**
 * HTTPS: Web Roll-Call Check-In & Instant WhatsApp Pass Dispatcher
 * GET  /submitWebRollCallLead -> Returns live roll-call social proof stats
 * POST /submitWebRollCallLead -> Records home/host check-in, sends instant WhatsApp app link & forward card
 */
exports.submitWebRollCallLead = functions
  .runWith({
    timeoutSeconds: 60,
    memory: "256MB",
    secrets: ["WHATSAPP_ACCESS_TOKEN", "WHATSAPP_PHONE_NUMBER_ID"],
  })
  .https.onRequest(async (req, res) => {
    res.set("Access-Control-Allow-Origin", "*");
    res.set("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
    res.set("Access-Control-Allow-Headers", "Content-Type, Authorization");

    if (req.method === "OPTIONS") {
      return res.status(204).send("");
    }

    if (req.method === "GET") {
      try {
        const [usersSnap, leadsSnap] = await Promise.all([
          db.collection("users").limit(200).get(),
          db.collection("outreach_leads").limit(200).get(),
        ]);
        return res.status(200).json({
          success: true,
          activeMembers: Math.max(31, usersSnap.size + leadsSnap.size),
          activeChambers: 64,
        });
      } catch (_e) {
        return res.status(200).json({
          success: true,
          activeMembers: 42,
          activeChambers: 64,
        });
      }
    }

    if (req.method !== "POST") {
      return res.status(405).json({ error: "Method Not Allowed." });
    }

    try {
      const body = req.body || {};
      const homeLocation = String(body.homeLocation || "Tanzania").trim().slice(0, 60);
      const hostLocation = String(body.hostLocation || "Diaspora").trim().slice(0, 60);
      const profileName = String(body.name || "").trim().slice(0, 60);
      const rawPhone = String(body.phone || "").trim();
      const code = String(body.code || FOUNDER_INVITE_CODE).trim().slice(0, 32) || FOUNDER_INVITE_CODE;

      const normalizedPhone = normalizeWebPhone(rawPhone, homeLocation, hostLocation);
      const intent = classifyOutreachIntent(`${homeLocation} -> ${hostLocation}`, normalizedPhone || "");
      const isExpat =
        body.corridor === "expat_in_tz" ||
        (intent.corridor === "expat_in_tz" && !homeLocation.toLowerCase().includes("tanzania"));
      const corridor = isExpat ? "expat_in_tz" : "tz_abroad";
      const lang = body.lang || (corridor === "tz_abroad" ? "sw" : intent.lang || "en");
      const corridorLabel = `${homeLocation} ✈️ ${hostLocation}`;

      const docKey = normalizedPhone
        ? stableHash(`lead:${normalizedPhone}`)
        : stableHash(`web:${homeLocation}:${hostLocation}:${Date.now()}`);

      let whatsappDelivered = false;
      const accessToken = process.env.WHATSAPP_ACCESS_TOKEN;
      const phoneNumberId = process.env.WHATSAPP_PHONE_NUMBER_ID;

      if (normalizedPhone && accessToken && phoneNumberId) {
        const welcomeText =
          corridor === "tz_abroad"
            ? KISWAHILI_DIASPORA_PACK.welcome(code, corridorLabel)
            : (EXPAT_NATIVE_PACKS[lang] || EXPAT_NATIVE_PACKS.en).welcome(code, corridorLabel);

        const delivery = await sendWhatsAppCloudMessage({
          phoneNumberId,
          accessToken,
          to: normalizedPhone,
          type: "text",
          textBody: welcomeText,
        });
        whatsappDelivered = !!delivery.ok;

        if (whatsappDelivered) {
          const forwardText =
            corridor === "tz_abroad"
              ? KISWAHILI_DIASPORA_PACK.forwardCard(code)
              : (EXPAT_NATIVE_PACKS[lang] || EXPAT_NATIVE_PACKS.en).forwardCard(code);
          await sendWhatsAppCloudMessage({
            phoneNumberId,
            accessToken,
            to: normalizedPhone,
            type: "text",
            textBody: forwardText,
          }).catch(() => undefined);
        }
      }

      await db
        .collection("outreach_leads")
        .doc(docKey)
        .set(
          {
            ...(normalizedPhone ? { phoneNumber: normalizedPhone } : {}),
            ...(profileName ? { profileName } : {}),
            homeCity: homeLocation,
            hostCity: hostLocation,
            city: corridorLabel,
            corridor,
            lang,
            referralCode: code,
            source: "web_rollcall",
            status: whatsappDelivered ? "link_sent" : "web_checked_in",
            followUpSent: false,
            lastInboundAt: admin.firestore.FieldValue.serverTimestamp(),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          { merge: true }
        );

      const inviteUrl = `https://diasporanearby.com/invite?code=${encodeURIComponent(code)}`;
      const shareText =
        corridor === "tz_abroad"
          ? `🇹🇿 Nimejiunga kwenye Roll-Call ya *${homeLocation} ✈️ ${hostLocation}* ndani ya *Diaspora Nearby*!\n\n` +
            `Washia *Nearby Discovery & Notification* uone Watanzania walio karibu nawe mji huu, sikiliza *Redio za Nyumbani Live*, na ujiunge na *Ubuntu Emergency Fund & DDI Loans*:\n` +
            `👉 ${inviteUrl}`
          : `🌍 Just checked into the *${homeLocation} ✈️ ${hostLocation}* corridor on *Diaspora Nearby*!\n\n` +
            `Turn on *Nearby Discovery & Notifications* to see compatriots around you, stream *Live Homeland Radio*, and access the *Ubuntu Emergency Fund & DDI Loans*:\n` +
            `👉 ${inviteUrl}`;

      return res.status(200).json({
        success: true,
        corridor,
        lang,
        corridorLabel,
        whatsappDelivered,
        referralCode: code,
        inviteUrl,
        shareText,
      });
    } catch (err) {
      console.error("[submitWebRollCallLead] Error:", err.message);
      return res.status(500).json({ error: err.message });
    }
  });

module.exports = {
  EXPAT_NATIVE_PACKS,
  KISWAHILI_DIASPORA_PACK,
  classifyOutreachIntent,
  detectExpatLanguage,
  parseHomeAndHostFromComment,
  buildFacebookCommentOnboarding,
  processFacebookComment,
  pollFacebookPageComments,
  handleIncomingWhatsAppMessages,
  outreachFollowUpCron: exports.outreachFollowUpCron,
  metaOutreachWebhook: exports.metaOutreachWebhook,
  dispatchGroupOutreachBatch: exports.dispatchGroupOutreachBatch,
  submitWebRollCallLead: exports.submitWebRollCallLead,
};
