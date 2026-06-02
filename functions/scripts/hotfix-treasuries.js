const https = require("https");
const os = require("os");
const path = require("path");
const fs = require("fs");

const PROJECT_ID = "diaspora-nearby-a3dac";

const configCandidates = [
    path.join(os.homedir(), ".config", "configstore", "firebase-tools.json"),
    path.join(process.env.APPDATA || "", "configstore", "firebase-tools.json"),
];
const configPath = configCandidates.find((p) => fs.existsSync(p));

async function getAccessToken() {
    const configData = JSON.parse(fs.readFileSync(configPath, "utf8"));
    const refreshToken = configData?.tokens?.refresh_token;
    const body = new URLSearchParams({
        client_id: "563584335869-fgrhgmd47bqnekij5i8b5pr03ho849e6.apps.googleusercontent.com",
        client_secret: "j9iVZfS8kkCEFUPaAeJV0sAi",
        refresh_token: refreshToken, grant_type: "refresh_token",
    }).toString();
    return new Promise((resolve, reject) => {
        const req = https.request({
            hostname: "oauth2.googleapis.com", path: "/token", method: "POST",
            headers: { "Content-Type": "application/x-www-form-urlencoded", "Content-Length": Buffer.byteLength(body) },
        }, (res) => { let d = ""; res.on("data", (c) => (d += c)); res.on("end", () => { const p = JSON.parse(d); p.access_token ? resolve(p.access_token) : reject(new Error(d)); }); });
        req.on("error", reject); req.write(body); req.end();
    });
}

async function patchDoc(token, docPath, walletAddress) {
    // We append ?updateMask.fieldPaths=walletAddress so we ONLY update walletAddress
    const url = `https://firestore.googleapis.com/v1/projects/${PROJECT_ID}/databases/(default)/documents/${docPath}?updateMask.fieldPaths=walletAddress`;
    
    // Construct the document to patch
    const updatePayload = JSON.stringify({
        fields: {
            walletAddress: { stringValue: walletAddress }
        }
    });

    return new Promise((resolve, reject) => {
        const u = new URL(url);
        const req = https.request({ 
            hostname: u.hostname, 
            path: u.pathname + u.search, 
            method: "PATCH", 
            headers: { 
                Authorization: `Bearer ${token}`,
                "Content-Type": "application/json",
                "Content-Length": Buffer.byteLength(updatePayload)
            } 
        }, (res) => {
            let d = ""; res.on("data", (c) => (d += c));
            res.on("end", () => res.statusCode === 200 ? resolve(JSON.parse(d)) : reject(new Error(`Status ${res.statusCode}: ${d}`)));
        });
        req.on("error", reject);
        req.write(updatePayload);
        req.end();
    });
}

async function main() {
    const token = await getAccessToken();

    console.log("Updating governance/founders ...");
    await patchDoc(token, "governance/founders", "0x721b98484afff3bF4314933a7cB0e324499FbC24");
    console.log("Founders updated ✅");

    console.log("Updating governance/liquidity ...");
    await patchDoc(token, "governance/liquidity", "0x02Bd59A63d6e8Fc31Fda8b117ceb4A4f24265CaD");
    console.log("Liquidity updated ✅");
}

main().then(() => process.exit(0)).catch((e) => { console.error("Error:", e.message); process.exit(1); });
