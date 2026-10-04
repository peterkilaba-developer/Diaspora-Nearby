/**
 * One-shot script: backfill walletAddress into governance/burn doc.
 * Uses Firebase CLI's cached credential token directly via Firestore REST API.
 */
const https = require("https");
const {getAccessToken} = require("./lib/access-token");

const PROJECT_ID = "diaspora-nearby-a3dac";
const BURN_ADDRESS = "0x000000000000000000000000000000000000dEaD";

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
