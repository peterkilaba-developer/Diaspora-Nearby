/**
 * Audit all governance docs — check which ones have walletAddress and which don't.
 */
const https = require("https");
const {getAccessToken} = require("./lib/access-token");

const PROJECT_ID = "diaspora-nearby-a3dac";

async function listDocs(accessToken) {
    const url = `https://firestore.googleapis.com/v1/projects/${PROJECT_ID}/databases/(default)/documents/governance?pageSize=50`;
    return new Promise((resolve, reject) => {
        const u = new URL(url);
        const req = https.request({ hostname: u.hostname, path: u.pathname + u.search, method: "GET", headers: { Authorization: `Bearer ${accessToken}` } }, (res) => {
            let data = ""; res.on("data", (d) => (data += d));
            res.on("end", () => res.statusCode === 200 ? resolve(JSON.parse(data)) : reject(new Error(data)));
        });
        req.on("error", reject); req.end();
    });
}

async function main() {
    const token = await getAccessToken();
    const result = await listDocs(token);
    const docs = result.documents || [];

    // Output as JSON for easy parsing
    const summary = docs.map((doc) => {
        const id = doc.name.split("/").pop();
        const f = doc.fields || {};
        return {
            id,
            walletAddress: f.walletAddress?.stringValue || "MISSING",
            type: f.type?.stringValue || "?",
            balance: f.treasuryBalance?.integerValue || f.treasuryBalance?.doubleValue || "0",
        };
    });

    // Print as table
    for (const s of summary) {
        const status = s.walletAddress === "MISSING" ? "❌" : "✅";
        const addr = s.walletAddress === "MISSING" ? "NO WALLET" : s.walletAddress.substring(0, 10) + "..." + s.walletAddress.slice(-6);
        console.log(`${status} ${s.id.padEnd(42)} ${addr.padEnd(22)} ${s.type.padEnd(12)} bal=${s.balance}`);
    }
}

main().then(() => process.exit(0)).catch((e) => { console.error("Error:", e.message); process.exit(1); });
