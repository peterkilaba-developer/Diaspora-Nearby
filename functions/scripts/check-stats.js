/**
 * Read system_stats/treasury to see what fields are available.
 */
const https = require("https");
const {getAccessToken} = require("./lib/access-token");

const PROJECT_ID = "diaspora-nearby-a3dac";

async function getDoc(token, docPath) {
    const url = `https://firestore.googleapis.com/v1/projects/${PROJECT_ID}/databases/(default)/documents/${docPath}`;
    return new Promise((resolve, reject) => {
        const u = new URL(url);
        const req = https.request({ hostname: u.hostname, path: u.pathname, method: "GET", headers: { Authorization: `Bearer ${token}` } }, (res) => {
            let d = ""; res.on("data", (c) => (d += c));
            res.on("end", () => res.statusCode === 200 ? resolve(JSON.parse(d)) : reject(new Error(d)));
        });
        req.on("error", reject); req.end();
    });
}

function printFields(fields, indent = "") {
    for (const [key, val] of Object.entries(fields)) {
        if (val.integerValue !== undefined) console.log(`${indent}${key}: ${val.integerValue} (int)`);
        else if (val.doubleValue !== undefined) console.log(`${indent}${key}: ${val.doubleValue} (double)`);
        else if (val.stringValue !== undefined) console.log(`${indent}${key}: "${val.stringValue}"`);
        else if (val.booleanValue !== undefined) console.log(`${indent}${key}: ${val.booleanValue} (bool)`);
        else if (val.timestampValue !== undefined) console.log(`${indent}${key}: ${val.timestampValue} (timestamp)`);
        else if (val.mapValue) { console.log(`${indent}${key}: {`); printFields(val.mapValue.fields || {}, indent + "  "); console.log(`${indent}}`); }
        else console.log(`${indent}${key}: ${JSON.stringify(val)}`);
    }
}

async function main() {
    const token = await getAccessToken();

    console.log("=== system_stats/treasury ===");
    const treasury = await getDoc(token, "system_stats/treasury");
    printFields(treasury.fields || {});

    console.log("\n=== governance/founders ===");
    const founders = await getDoc(token, "governance/founders");
    printFields(founders.fields || {});
}

main().then(() => process.exit(0)).catch((e) => { console.error("Error:", e.message); process.exit(1); });
