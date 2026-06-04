/**
 * One-off: zero out test-residue treasury balances that would block the next TGE.
 *
 * Context:
 *   TGE 1 (2026-04-19) was triggered against a Firestore populated by a small
 *   group of test users. Those signups accumulated:
 *     - community treasury balances on governance/* docs that never had
 *       `averagePoCT` populated
 *     - a duplicate governance/investors doc with no walletAddress
 *
 *   The hardened performTGE() refuses to fire when any community treasury has
 *   treasuryBalance>0 AND no averagePoCT (silent-skip → 100% burn). Since the
 *   underlying balances are test residue, the correct fix is to zero them
 *   rather than backfill an averagePoCT we don't actually know.
 *
 * What this script does:
 *   For every governance doc with treasuryBalance > 0:
 *     - If it's a community doc (not founders/liquidity/investors/burn) AND
 *       averagePoCT is unset/null → set treasuryBalance = 0.
 *     - If it's the orphan governance/investors doc (no walletAddress) → set
 *       treasuryBalance = 0.
 *   Records the prior balance in `wipedTreasuryBalance` + `wipedAt` so the
 *   action is auditable and reversible if you change your mind.
 *
 * Usage (dry-run by default — shows what would be wiped):
 *   node functions/scripts/wipe-test-treasury-residue.js
 *
 * Execute the wipe:
 *   APPLY=1 node functions/scripts/wipe-test-treasury-residue.js
 */
const https = require("https");
const os = require("os");
const path = require("path");
const fs = require("fs");

const PROJECT_ID = "diaspora-nearby-a3dac";
const SYSTEM_DOC_IDS = new Set(["founders", "liquidity", "investors", "burn"]);
const APPLY = process.env.APPLY === "1";

const configCandidates = [
  path.join(os.homedir(), ".config", "configstore", "firebase-tools.json"),
  path.join(process.env.APPDATA || "", "configstore", "firebase-tools.json"),
];
const configPath = configCandidates.find((p) => fs.existsSync(p));

async function getAccessToken() {
  if (!configPath) throw new Error("Firebase CLI config not found — run `firebase login` first");
  const configData = JSON.parse(fs.readFileSync(configPath, "utf8"));
  const refreshToken = configData?.tokens?.refresh_token;
  if (!refreshToken) throw new Error("No refresh token found");
  const body = new URLSearchParams({
    client_id: "563584335869-fgrhgmd47bqnekij5i8b5pr03ho849e6.apps.googleusercontent.com",
    client_secret: "j9iVZfS8kkCEFUPaAeJV0sAi",
    refresh_token: refreshToken,
    grant_type: "refresh_token",
  }).toString();
  return new Promise((resolve, reject) => {
    const req = https.request({
      hostname: "oauth2.googleapis.com", path: "/token", method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded", "Content-Length": Buffer.byteLength(body) },
    }, (res) => {
      let data = ""; res.on("data", (d) => (data += d));
      res.on("end", () => { const p = JSON.parse(data); p.access_token ? resolve(p.access_token) : reject(new Error(data)); });
    });
    req.on("error", reject); req.write(body); req.end();
  });
}

function firestoreReq(method, pathSuffix, token, body) {
  return new Promise((resolve, reject) => {
    const buf = body ? Buffer.from(JSON.stringify(body)) : null;
    const req = https.request({
      hostname: "firestore.googleapis.com",
      path: `/v1/projects/${PROJECT_ID}/databases/(default)/documents${pathSuffix}`,
      method,
      headers: {
        Authorization: `Bearer ${token}`,
        ...(buf ? { "Content-Type": "application/json", "Content-Length": buf.length } : {}),
      },
    }, (res) => {
      let data = ""; res.on("data", (d) => (data += d));
      res.on("end", () => {
        if (res.statusCode >= 200 && res.statusCode < 300) resolve(data ? JSON.parse(data) : {});
        else reject(new Error(`${res.statusCode}: ${data}`));
      });
    });
    req.on("error", reject);
    if (buf) req.write(buf);
    req.end();
  });
}

async function main() {
  const token = await getAccessToken();
  const list = await firestoreReq("GET", "/governance?pageSize=200", token);
  const docs = list.documents || [];

  const toWipe = [];
  for (const d of docs) {
    const id = d.name.split("/").pop();
    const f = d.fields || {};
    const bal = Number(f.treasuryBalance?.integerValue || f.treasuryBalance?.doubleValue || 0);
    if (bal <= 0) continue;

    const wallet = f.walletAddress?.stringValue;
    const isSystem = SYSTEM_DOC_IDS.has(id);
    const apoctPresent = f.averagePoCT !== undefined;

    let reason = null;
    if (!isSystem && !apoctPresent) {
      reason = "community doc missing averagePoCT (test residue) — would block next TGE";
    } else if (id === "investors" && (!wallet || wallet.length < 10)) {
      reason = "orphan investors doc with no wallet (legacy; superseded by governance/liquidity)";
    }
    if (reason) toWipe.push({ id, bal, wallet: wallet || "MISSING", reason });
  }

  console.log(`\n=== Test-residue treasury wipe ${APPLY ? "(APPLY)" : "(DRY-RUN — pass APPLY=1 to execute)"} ===\n`);
  console.log(`${toWipe.length} doc(s) would be wiped:\n`);
  let totalBalance = 0;
  for (const w of toWipe) {
    console.log(`  governance/${w.id}`);
    console.log(`    balance: ${w.bal} → 0`);
    console.log(`    wallet:  ${w.wallet}`);
    console.log(`    reason:  ${w.reason}`);
    totalBalance += w.bal;
  }
  console.log(`\nTotal DSP residue wiped: ${totalBalance}\n`);

  if (!APPLY) {
    console.log("DRY-RUN complete. Re-run with APPLY=1 to execute.");
    return;
  }

  for (const w of toWipe) {
    const now = new Date().toISOString();
    const body = {
      fields: {
        treasuryBalance: { integerValue: "0" },
        wipedTreasuryBalance: { integerValue: String(w.bal) },
        wipedReason: { stringValue: w.reason },
        wipedAt: { timestampValue: now },
      },
    };
    await firestoreReq(
      "PATCH",
      `/governance/${encodeURIComponent(w.id)}?updateMask.fieldPaths=treasuryBalance&updateMask.fieldPaths=wipedTreasuryBalance&updateMask.fieldPaths=wipedReason&updateMask.fieldPaths=wipedAt`,
      token,
      body
    );
    console.log(`  ✅ wiped governance/${w.id}`);
  }
  console.log(`\nDone. ${toWipe.length} doc(s) wiped.`);
}

main().catch((e) => { console.error("Wipe failed:", e.message); process.exit(1); });
