#!/usr/bin/env node
/**
 * Diaspora Nearby – Live Interactive Browser Outreach Session Controller
 *
 * Launches a persistent Google Chrome session with remote debugging enabled,
 * opens WhatsApp Web + Facebook Groups, and automatically injects the borderless
 * Diaspora Nearby Outreach Assistant HUD into both tabs via Chrome DevTools Protocol.
 *
 * Features inside the live browser HUD:
 *   - Corridor & Language Selector:
 *       🇹🇿 Tanzanians Abroad (Kiswahili)
 *       🌍 Expats in Tanzania (English, Français, 中文, हिन्दी, العربية, Deutsch)
 *   - 1-Click Extract Group Admins (sorted first) & Group Members on WhatsApp Web & Facebook Groups
 *   - 1-Click Auto-DM Queue (pitches Group Admins first as Founding Chamber Partners, then Members)
 *   - 1-Click Copy Group Roll-Call / Pin Announcement Post
 */

const { spawn } = require("child_process");
const fs = require("fs");
const path = require("path");

const DEBUG_PORT = 9222;
const PROFILE_DIR = path.join(__dirname, "..", ".outreach-profile", "chrome-live");
const STATE_PATH = path.join(__dirname, ".outreach-state.json");
const EXTRACTED_WA_PATH = path.join(__dirname, "outreach-extracted-wa.json");
const CONFIG_PATH = path.join(__dirname, "tz-corridor-groups.json");

const CHROME_PATHS = [
  "C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe",
  "C:\\Program Files (x86)\\Google\\Chrome\\Application\\chrome.exe",
  "C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe",
  "C:\\Program Files\\Microsoft\\Edge\\Application\\msedge.exe",
];

function findBrowserExecutable() {
  for (const p of CHROME_PATHS) {
    if (fs.existsSync(p)) return p;
  }
  throw new Error("Could not find Chrome or Edge executable on this machine.");
}

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

function sleep(ms) {
  return new Promise((r) => setTimeout(r, ms));
}

/**
 * Builds the self-contained client-side script injected into WhatsApp Web & Facebook Groups
 */
function buildInjectedHudScript(config, initialState) {
  const serializedConfig = JSON.stringify(config);
  const serializedState = JSON.stringify(initialState);

  return `
(function initDiasporaOutreachHud() {
  if (window.__dnOutreachHudInjected) return;
  window.__dnOutreachHudInjected = true;

  const CONFIG = ${serializedConfig};
  const STATE = ${serializedState};

  function hashCode(prefix, str) {
    let h = 2166136261;
    const s = String(str || 'genesis');
    for (let i = 0; i < s.length; i++) {
      h ^= s.charCodeAt(i);
      h = Math.imul(h, 16777619);
    }
    return prefix + (h >>> 0).toString(16).toUpperCase().padStart(6, '0').slice(0, 6);
  }

  function fillTpl(tpl, vars) {
    return String(tpl || '')
      .replace(/\\{\\{NAME\\}\\}/g, vars.name || 'Rafiki')
      .replace(/\\{\\{GROUP_NAME\\}\\}/g, vars.groupName || 'Diaspora Group')
      .replace(/\\{\\{HOST_REGION\\}\\}/g, vars.hostRegion || 'Diaspora')
      .replace(/\\{\\{CODE\\}\\}/g, vars.code || 'GENESIS');
  }

  function getTemplates(mode) {
    if (mode === 'tz_sw') {
      return { corridor: 'tz_abroad', lang: 'sw', tpl: CONFIG.corridors.tz_abroad.templates.sw };
    }
    const lang = mode.replace('expat_', '') || 'en';
    const tpl = CONFIG.corridors.expat_in_tz.templates[lang] || CONFIG.corridors.expat_in_tz.templates.en;
    return { corridor: 'expat_in_tz', lang, tpl };
  }

  function injectUI() {
    if (!document.body || document.getElementById('dn-outreach-hud')) return;

    const host = document.createElement('div');
    host.id = 'dn-outreach-hud';
    host.style.cssText = [
      'position: fixed',
      'bottom: 16px',
      'right: 16px',
      'width: 360px',
      'max-height: 82vh',
      'overflow-y: auto',
      'z-index: 2147483647',
      'background: rgba(14, 22, 18, 0.94)',
      'backdrop-filter: blur(12px)',
      '-webkit-backdrop-filter: blur(12px)',
      'color: #f3f6f4',
      'border-radius: 20px',
      'padding: 16px',
      'font-family: system-ui, -apple-system, sans-serif',
      'font-size: 13px',
      'box-shadow: 0 18px 42px rgba(0, 0, 0, 0.55)',
      'border: none',
      'outline: none'
    ].join(';');

    const isWhatsApp = location.hostname.includes('whatsapp.com');
    const isFacebook = location.hostname.includes('facebook.com');

    host.innerHTML = \`
      <div style="display:flex;align-items:center;justify-content:space-between;margin-bottom:10px;">
        <div style="font-weight:800;font-size:14px;color:#2ecc71;display:flex;align-items:center;gap:6px;">
          <span>🚀 Diaspora Nearby Outreach</span>
          <span style="font-size:11px;padding:3px 8px;border-radius:999px;background:rgba(46,204,113,0.16);color:#2ecc71;">\${isWhatsApp ? 'WhatsApp' : isFacebook ? 'Facebook' : 'Web'}</span>
        </div>
        <button id="dn-hud-min" type="button" style="background:rgba(255,255,255,0.08);color:#fff;border:none;outline:none;border-radius:10px;padding:4px 9px;cursor:pointer;font-size:12px;">—</button>
      </div>

      <div id="dn-hud-body">
        <div style="margin-bottom:10px;">
          <label style="display:block;font-size:11.5px;color:rgba(255,255,255,0.7);margin-bottom:4px;font-weight:600;">1. Select Target Group Corridor &amp; Language:</label>
          <select id="dn-corridor-select" style="width:100%;padding:9px 10px;border-radius:12px;background:rgba(255,255,255,0.09);color:#fff;border:none;outline:none;font-size:12.5px;font-weight:600;">
            <option value="tz_sw" style="background:#121c16;color:#fff;">🇹🇿 Tanzanians Abroad — Kiswahili</option>
            <option value="expat_en" style="background:#121c16;color:#fff;">🌍 Expats in Tanzania — English</option>
            <option value="expat_fr" style="background:#121c16;color:#fff;">🇫🇷 Expats in Tanzania — Français</option>
            <option value="expat_zh" style="background:#121c16;color:#fff;">🇨🇳 Expats in Tanzania — 中文 (Mandarin)</option>
            <option value="expat_hi" style="background:#121c16;color:#fff;">🇮🇳 Expats in Tanzania — हिन्दी (Hindi)</option>
            <option value="expat_ar" style="background:#121c16;color:#fff;">🇦🇪 Expats in Tanzania — العربية (Arabic)</option>
            <option value="expat_de" style="background:#121c16;color:#fff;">🇩🇪 Expats in Tanzania — Deutsch</option>
          </select>
        </div>

        <div style="display:grid;grid-template-columns:1fr 1fr;gap:8px;margin-bottom:10px;">
          <input id="dn-group-name" type="text" placeholder="Group Name (auto)" style="padding:8px 10px;border-radius:10px;background:rgba(255,255,255,0.08);color:#fff;border:none;outline:none;font-size:12px;" />
          <input id="dn-host-region" type="text" placeholder="City/Region (e.g. USA / Dar)" style="padding:8px 10px;border-radius:10px;background:rgba(255,255,255,0.08);color:#fff;border:none;outline:none;font-size:12px;" />
        </div>

        <div style="display:flex;flex-direction:column;gap:7px;margin-bottom:10px;">
          <button id="dn-btn-extract" type="button" style="width:100%;padding:10px 12px;border-radius:12px;background:#2ecc71;color:#071b0f;font-weight:800;font-size:12.5px;border:none;outline:none;cursor:pointer;text-align:left;">
            🔍 2. Extract Group Admins (First) &amp; Members
          </button>

          \${isFacebook ? \`
          <div style="display:grid;grid-template-columns:1fr 1fr;gap:6px;">
            <button id="dn-btn-fb-admins" type="button" style="padding:8px 10px;border-radius:10px;background:rgba(255,255,255,0.09);color:#fff;font-weight:700;font-size:11.5px;border:none;outline:none;cursor:pointer;">
              👑 Open Group Admins Tab
            </button>
            <button id="dn-btn-fb-search-tz" type="button" style="padding:8px 10px;border-radius:10px;background:rgba(255,255,255,0.09);color:#fff;font-weight:700;font-size:11.5px;border:none;outline:none;cursor:pointer;">
              🔎 Search TZ / Expat Groups
            </button>
          </div>
          \` : ''}

          <button id="dn-btn-copy-pin" type="button" style="width:100%;padding:9px 12px;border-radius:12px;background:rgba(46,204,113,0.14);color:#2ecc71;font-weight:700;font-size:12px;border:none;outline:none;cursor:pointer;text-align:left;">
            📋 Copy Group Announcement / Roll-Call Post
          </button>
        </div>

        <div id="dn-status" style="padding:9px 11px;border-radius:12px;background:rgba(255,255,255,0.06);font-size:11.5px;color:rgba(255,255,255,0.82);line-height:1.45;margin-bottom:8px;">
          \${isWhatsApp
            ? '💡 Open any WhatsApp Group, click the Group Header to open <b>Group Info</b>, then click <b>Extract Group Admins &amp; Members</b>.'
            : '💡 Open any Facebook Group (or search above), click <b>Open Group Admins Tab</b>, then click <b>Extract Group Admins &amp; Members</b>.'}
        </div>

        <div id="dn-contacts-list" style="display:flex;flex-direction:column;gap:6px;max-height:220px;overflow-y:auto;"></div>
      </div>
    \`;

    document.body.appendChild(host);

    const minBtn = document.getElementById('dn-hud-min');
    const bodyEl = document.getElementById('dn-hud-body');
    minBtn.addEventListener('click', () => {
      const hidden = bodyEl.style.display === 'none';
      bodyEl.style.display = hidden ? 'block' : 'none';
      minBtn.textContent = hidden ? '—' : '+';
    });

    const statusEl = document.getElementById('dn-status');
    const listEl = document.getElementById('dn-contacts-list');
    const modeSelect = document.getElementById('dn-corridor-select');
    const groupInput = document.getElementById('dn-group-name');
    const regionInput = document.getElementById('dn-host-region');

    modeSelect.addEventListener('change', () => {
      const isTz = modeSelect.value === 'tz_sw';
      if (!regionInput.value) {
        regionInput.value = isTz ? 'USA, UK, UAE & Diaspora' : 'Dar es Salaam, Arusha & Zanzibar';
      }
    });
    regionInput.value = 'USA, UK, UAE & Diaspora';

    // Copy Pin Announcement / Group Roll-Call
    document.getElementById('dn-btn-copy-pin').addEventListener('click', () => {
      const { tpl } = getTemplates(modeSelect.value);
      const groupName = groupInput.value.trim() || document.title || 'Jumuiya Yetu';
      const hostRegion = regionInput.value.trim() || 'Diaspora';
      const code = hashCode('GRP', groupName);
      const text = fillTpl(tpl.adminPinPost, { name: 'Admin', groupName, hostRegion, code });
      navigator.clipboard.writeText(text).then(() => {
        statusEl.innerHTML = '✅ <b>Copied Group Post to clipboard!</b> Paste it directly into the group chat or feed.';
      });
    });

    if (isFacebook) {
      const fbAdminsBtn = document.getElementById('dn-btn-fb-admins');
      if (fbAdminsBtn) {
        fbAdminsBtn.addEventListener('click', () => {
          const match = location.pathname.match(/\\/groups\\/([^/?#]+)/);
          if (match && match[1] && match[1] !== 'search' && match[1] !== 'joins') {
            location.href = 'https://www.facebook.com/groups/' + match[1] + '/members/admins';
          } else {
            statusEl.innerHTML = '⚠️ Open a specific Facebook Group first, then click <b>Open Group Admins Tab</b>.';
          }
        });
      }
      const fbSearchBtn = document.getElementById('dn-btn-fb-search-tz');
      if (fbSearchBtn) {
        fbSearchBtn.addEventListener('click', () => {
          const isTz = modeSelect.value === 'tz_sw';
          const q = isTz ? 'Tanzanians in USA UK Dubai Diaspora Watanzania' : 'Expats in Dar es Salaam Arusha Zanzibar Tanzania';
          location.href = 'https://www.facebook.com/groups/search/groups/?q=' + encodeURIComponent(q);
        });
      }
    }

    // Extract Admins & Members
    document.getElementById('dn-btn-extract').addEventListener('click', () => {
      listEl.innerHTML = '';
      const { corridor, lang, tpl } = getTemplates(modeSelect.value);
      const contacts = [];
      const seen = new Set();

      if (isWhatsApp) {
        const titleEl = document.querySelector('header span[title]') || document.querySelector('[data-testid="conversation-info-header-chat-title"]');
        if (titleEl && !groupInput.value) groupInput.value = titleEl.textContent.trim();

        const rows = Array.from(document.querySelectorAll('[role="listitem"], [data-testid="cell-frame-container"]'));
        for (const row of rows) {
          const text = row.innerText || '';
          const isAdmin = /group admin|admin|msimamizi/i.test(text);
          const phoneMatch = text.match(/\\+\\d[\\d\\s()-]{7,18}\\d/);
          const spans = Array.from(row.querySelectorAll('span[dir="auto"], span[title]'))
            .map(s => (s.getAttribute('title') || s.textContent || '').trim())
            .filter(Boolean);
          const phone = phoneMatch ? phoneMatch[0].replace(/[^\\d+]/g, '') : '';
          const name = spans.find(s => !s.startsWith('+') && !/admin|you/i.test(s)) || '';
          const key = phone || name;
          if (!key || seen.has(key) || /^you$/i.test(name)) continue;
          seen.add(key);
          contacts.push({
            role: isAdmin ? 'admin' : 'member',
            name: name || phone,
            phone,
            id: phone || name
          });
        }
      } else if (isFacebook) {
        const h1 = document.querySelector('h1');
        if (h1 && !groupInput.value) groupInput.value = h1.innerText.trim();
        const isAdminsPage = location.pathname.includes('/admins');
        const anchors = Array.from(document.querySelectorAll('a[href*="/user/"], a[href*="facebook.com/profile.php"]'));
        for (const a of anchors) {
          const href = a.getAttribute('href') || '';
          const name = (a.innerText || a.getAttribute('aria-label') || '').trim();
          if (!name || name.length < 2 || name.length > 55 || /admin|moderator|learn more/i.test(name)) continue;
          const m = href.match(/\\/user\\/(\\d+)/) || href.match(/id=(\\d+)/);
          const userId = m ? m[1] : href;
          if (seen.has(userId)) continue;
          seen.add(userId);
          const cardText = (a.closest('[role="listitem"], [data-visualcompletion]') || a.parentElement || {}).innerText || '';
          const isAdmin = isAdminsPage || /admin|moderator/i.test(cardText);
          contacts.push({
            role: isAdmin ? 'admin' : 'member',
            name,
            userId,
            id: userId
          });
        }
      }

      // Always sort Group Admins first!
      contacts.sort((a, b) => (a.role === 'admin' ? -1 : 1));
      const groupName = groupInput.value.trim() || 'Diaspora Group';
      const hostRegion = regionInput.value.trim() || (corridor === 'tz_abroad' ? 'Diaspora' : 'Dar, Arusha & Zanzibar');

      if (contacts.length === 0) {
        statusEl.innerHTML = isWhatsApp
          ? '⚠️ No contacts found yet. Click the WhatsApp Group top bar to open <b>Group Info</b> and scroll down the member list, then click Extract again.'
          : '⚠️ No members found on this view. Open a Facebook Group -> <b>Members</b> (or click <b>Open Group Admins Tab</b>), then click Extract again.';
        return;
      }

      const adminCount = contacts.filter(c => c.role === 'admin').length;
      statusEl.innerHTML = \`✅ Extracted <b>\${contacts.length}</b> people (<b>\${adminCount} Admins first</b>). Click <b>Send Direct DM</b> on any Admin or Member below:\`;

      contacts.slice(0, 60).forEach((c) => {
        const firstName = String(c.name || 'Rafiki').split(' ')[0];
        const code = hashCode(c.role === 'admin' ? 'ADM' : (corridor === 'tz_abroad' ? 'TZ' : 'EX'), c.id);
        const msg = fillTpl(c.role === 'admin' ? tpl.adminPitch : tpl.memberDm, {
          name: firstName,
          groupName,
          hostRegion,
          code
        });

        const item = document.createElement('div');
        item.style.cssText = 'display:flex;align-items:center;justify-content:space-between;padding:8px 10px;border-radius:12px;background:rgba(255,255,255,0.07);gap:8px;';
        const badgeColor = c.role === 'admin' ? 'rgba(241,196,15,0.22);color:#f1c40f' : 'rgba(255,255,255,0.12);color:#ccc';

        item.innerHTML = \`
          <div style="overflow:hidden;text-overflow:ellipsis;white-space:nowrap;flex:1;">
            <span style="font-size:10px;font-weight:800;padding:2px 6px;border-radius:6px;background:\${badgeColor};margin-right:5px;">\${c.role.toUpperCase()}</span>
            <span style="font-weight:600;font-size:12px;">\${c.name}</span>
          </div>
          <button type="button" style="padding:6px 10px;border-radius:9px;background:#2ecc71;color:#071b0f;font-weight:800;font-size:11px;border:none;outline:none;cursor:pointer;white-space:nowrap;">
            💬 Send DM
          </button>
        \`;

        const sendBtn = item.querySelector('button');
        sendBtn.addEventListener('click', () => {
          navigator.clipboard.writeText(msg).catch(() => {});
          sendBtn.textContent = '✅ Copied + Opening';
          sendBtn.style.background = 'rgba(46,204,113,0.35)';
          sendBtn.style.color = '#fff';

          if (isWhatsApp && c.phone) {
            const cleanNum = c.phone.replace(/^\\+/, '');
            window.open('https://web.whatsapp.com/send?phone=' + cleanNum + '&text=' + encodeURIComponent(msg), '_blank');
          } else if (isFacebook && c.userId) {
            statusEl.innerHTML = '📋 <b>Personal DM copied to clipboard!</b> Opening Messenger for <b>' + c.name + '</b> — press <b>Ctrl+V</b> and Enter!';
            window.open('https://www.facebook.com/messages/t/' + c.userId, '_blank');
          } else {
            statusEl.innerHTML = '📋 <b>Message copied to clipboard for ' + c.name + '!</b> Paste (Ctrl+V) into their chat.';
          }
        });

        listEl.appendChild(item);
      });
    });
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', injectUI);
  } else {
    injectUI();
  }
  setInterval(injectUI, 2500);
})();
`;
}

async function attachHudToTargets(hudScript) {
  try {
    const res = await fetch(`http://127.0.0.1:${DEBUG_PORT}/json`);
    const targets = await res.json();
    const pages = targets.filter(
      (t) =>
        t.type === "page" &&
        t.webSocketDebuggerUrl &&
        (t.url.includes("whatsapp.com") || t.url.includes("facebook.com"))
    );

    for (const target of pages) {
      await evaluateInTarget(target.webSocketDebuggerUrl, hudScript);
    }
  } catch (_e) {
    // Browser still starting up
  }
}

function evaluateInTarget(wsUrl, expression) {
  return new Promise((resolve) => {
    try {
      const ws = new WebSocket(wsUrl);
      const timeout = setTimeout(() => {
        try {
          ws.close();
        } catch (_e) {}
        resolve();
      }, 3000);

      ws.addEventListener("open", () => {
        ws.send(
          JSON.stringify({
            id: 1,
            method: "Page.addScriptToEvaluateOnNewDocument",
            params: { source: expression },
          })
        );
        ws.send(
          JSON.stringify({
            id: 2,
            method: "Runtime.evaluate",
            params: { expression },
          })
        );
        setTimeout(() => {
          clearTimeout(timeout);
          try {
            ws.close();
          } catch (_e) {}
          resolve();
        }, 400);
      });

      ws.addEventListener("error", () => {
        clearTimeout(timeout);
        resolve();
      });
    } catch (_err) {
      resolve();
    }
  });
}

async function main() {
  const browserExe = findBrowserExecutable();
  const config = loadConfig();
  const state = loadState();
  const hudScript = buildInjectedHudScript(config, state);

  fs.mkdirSync(PROFILE_DIR, { recursive: true });

  const startUrls = [
    "https://web.whatsapp.com/",
    "https://www.facebook.com/groups/search/groups/?q=Tanzanians%20in%20USA%20UK%20Dubai%20Diaspora",
    "https://www.facebook.com/groups/search/groups/?q=Expats%20in%20Dar%20es%20Salaam%20Arusha%20Zanzibar",
  ];

  console.log("🚀 Launching Live Outreach Browser Session...");
  console.log(`   Browser: ${browserExe}`);
  console.log(`   Profile: ${PROFILE_DIR}`);

  const child = spawn(
    browserExe,
    [
      `--remote-debugging-port=${DEBUG_PORT}`,
      `--user-data-dir=${PROFILE_DIR}`,
      "--no-first-run",
      "--no-default-browser-check",
      ...startUrls,
    ],
    {
      detached: true,
      stdio: "ignore",
    }
  );
  child.unref();

  console.log("⏳ Attaching Outreach HUD to WhatsApp Web & Facebook tabs on port 9222...");
  let consecutiveFailures = 0;
  while (consecutiveFailures < 15) {
    await sleep(2500);
    try {
      const res = await fetch(`http://127.0.0.1:${DEBUG_PORT}/json`);
      if (res.ok) {
        consecutiveFailures = 0;
        await attachHudToTargets(hudScript);
      } else {
        consecutiveFailures += 1;
      }
    } catch (_e) {
      consecutiveFailures += 1;
    }
  }
}

main().catch((err) => {
  console.error("Failed to launch outreach browser session:", err.message);
  process.exit(1);
});
