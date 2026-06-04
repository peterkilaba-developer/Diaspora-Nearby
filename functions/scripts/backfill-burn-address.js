/**
 * One-shot script: backfill walletAddress into governance/burn doc.
 * Uses Firebase CLI's cached credential token directly via Firestore REST API.
 */
const https = require("https");
const os = require("os");
const path = require("path");
const fs = require("fs");

const PROJECT_ID = "diaspora-nearby-a3dac";
const BURN_ADDRESS = "0x000000000000000000000000000000000000dEaD";

// Firebase CLI stores config - try multiple locations
const configCandidates = [
    path.join(os.homedir(), ".config", "configstore", "firebase-tools.json"),
    path.join(process.env.APPDATA || "", "configstore", "firebase-tools.json"),
];
const configPath = configCandidates.find((p) => fs.existsSync(p));

async function getAccessToken() {
    if (!configPath) throw new Error("Firebase CLI config not found");
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
        const req = https.request(
            {
                hostname: "oauth2.googleapis.com",
                path: "/token",
                method: "POST",
                headers: {
                    "Content-Type": "application/x-www-form-urlencoded",
                    "Content-Length": Buffer.byteLength(body),
                },
            },
            (res) => {
                let data = "";
                res.on("data", (d) => (data += d));
                res.on("end", () => {
                    const parsed = JSON.parse(data);
                    if (parsed.access_token) resolve(parsed.access_token);
                    else reject(new Error(JSON.stringify(parsed)));
                });
            }
        );
        req.on("error", reject);
        req.write(body);
        req.end();
    });
}

async function patchDocument(accessToken) {
    const docPath = `projects/${PROJECT_ID}/databases/(default)/documents/governance/burn`;
    const url = `https://firestore.googleapis.com/v1/${docPath}?updateMask.fieldPaths=walletAddress&updateMask.fieldPaths=walletType`;

    const body = JSON.stringify({
        fields: {
            walletAddress: { stringValue: BURN_ADDRESS },
            walletType: { stringValue: "burn" },
        },
    });

    return new Promise((resolve, reject) => {
        const parsedUrl = new URL(url);
        const req = https.request(
            {
                hostname: parsedUrl.hostname,
                path: parsedUrl.pathname + parsedUrl.search,
                method: "PATCH",
                headers: {
                    Authorization: `Bearer ${accessToken}`,
                    "Content-Type": "application/json",
                    "Content-Length": Buffer.byteLength(body),
                },
            },
            (res) => {
                let data = "";
                res.on("data", (d) => (data += d));
                res.on("end", () => {
                    if (res.statusCode === 200) {
                        console.log("✅ governance/burn updated with walletAddress!");
                        resolve();
                    } else {
                        console.error(`❌ HTTP ${res.statusCode}:`, data);
                        reject(new Error(`HTTP ${res.statusCode}`));
                    }
                });
            }
        );
        req.on("error", reject);
        req.write(body);
        req.end();
    });
}

async function main() {
    console.log("Getting Firebase CLI access token...");
    const token = await getAccessToken();
    console.log("Token acquired. Patching governance/burn...");
    await patchDocument(token);
}

main().then(() => process.exit(0)).catch((e) => {
    console.error("Error:", e.message);
    process.exit(1);
});
