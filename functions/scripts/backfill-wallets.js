/**
 * Backfill wallet addresses on governance docs for all communities
 * and system treasuries (founders, investors, burn).
 * 
 * Usage: node scripts/backfill-wallets.js
 * Requires: GOOGLE_APPLICATION_CREDENTIALS or gcloud auth application-default login
 */
const admin = require("firebase-admin");
const { ethers } = require("ethers");
const fs = require("fs");
const path = require("path");

// Initialize with default credentials
admin.initializeApp();
const db = admin.firestore();

// Load .env manually (no dotenv dependency)
function loadEnv() {
    const envPath = path.resolve(__dirname, "../.env");
    const envContent = fs.readFileSync(envPath, "utf8");
    const envVars = {};
    for (const line of envContent.split("\n")) {
        const trimmed = line.trim();
        if (!trimmed || trimmed.startsWith("#")) continue;
        const eqIdx = trimmed.indexOf("=");
        if (eqIdx === -1) continue;
        const key = trimmed.substring(0, eqIdx).trim();
        const value = trimmed.substring(eqIdx + 1).trim();
        envVars[key] = value;
    }
    return envVars;
}

async function main() {
    const env = loadEnv();
    const RPC_URL = env.RPC_URL || "https://mainnet.base.org";
    const WALLET_FACTORY_ADDRESS = env.WALLET_FACTORY_ADDRESS;

    if (!WALLET_FACTORY_ADDRESS) {
        console.error("WALLET_FACTORY_ADDRESS not found in .env");
        process.exit(1);
    }

    console.log("RPC:", RPC_URL);
    console.log("Factory:", WALLET_FACTORY_ADDRESS);

    const provider = new ethers.JsonRpcProvider(RPC_URL);
    const factoryAbi = [
        "function getWallet(bytes32 salt) external view returns (address)"
    ];
    const factory = new ethers.Contract(WALLET_FACTORY_ADDRESS, factoryAbi, provider);

    // ── 1. System Treasuries ──
    console.log("\n=== System Treasury Wallets ===\n");

    const BURN_ADDRESS = "0x000000000000000000000000000000000000dEaD";

    const systemTreasuries = [
        { label: "Founders", salt: "system:founders_treasury", govId: "founders", name: "Founders & Core Team", walletType: "smart" },
        { label: "Investors", salt: "system:investors_treasury", govId: "investors", name: "Investors & Partners", walletType: "smart" },
        // Burn is the canonical dead address — not a smart wallet. Backfill writes
        // 0x...dEaD directly so the burn slot is irrecoverable by design.
        { label: "Burn", govId: "burn", name: "Deflationary Burn", walletType: "burn", fixedAddress: BURN_ADDRESS },
    ];

    for (const t of systemTreasuries) {
        try {
            let walletAddress;
            if (t.fixedAddress) {
                walletAddress = t.fixedAddress;
            } else {
                const saltHash = ethers.keccak256(ethers.toUtf8Bytes(t.salt));
                walletAddress = await factory.getWallet(saltHash);
            }
            console.log(`${t.label}: ${walletAddress}`);

            await db.collection("governance").doc(t.govId).set({
                id: t.govId,
                name: t.name,
                type: "system",
                walletAddress: walletAddress,
                walletType: t.walletType,
                updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            }, { merge: true });

            console.log(`  → governance/${t.govId} updated`);
        } catch (e) {
            console.error(`  ERR ${t.label}: ${e.message}`);
        }
    }

    // ── 2. Community Wallets ──
    console.log("\n=== Community Treasury Wallets ===\n");

    const commSnap = await db.collection("communities").get();
    console.log(`Found ${commSnap.size} communities\n`);

    let created = 0, existing = 0, errors = 0;

    for (const doc of commSnap.docs) {
        const communityId = doc.id;
        const data = doc.data();

        const govId = communityId === "global_community"
            ? "global_community"
            : (communityId.includes("_") ? communityId.substring(communityId.indexOf("_") + 1) : communityId);

        // If community doc already has walletAddress, ensure governance doc has it too
        if (data.walletAddress) {
            await db.collection("governance").doc(govId).set({
                id: govId,
                communityId: communityId,
                type: "community",
                walletAddress: data.walletAddress,
                walletType: "smart",
                updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            }, { merge: true });

            console.log(`SYNC ${communityId} → governance/${govId}: ${data.walletAddress}`);
            existing++;
            continue;
        }

        // Create new deterministic wallet address
        try {
            const salt = `community:${communityId}`;
            const saltHash = ethers.keccak256(ethers.toUtf8Bytes(salt));
            const walletAddress = await factory.getWallet(saltHash);

            // Update community doc
            await doc.ref.update({
                walletAddress: walletAddress,
                walletGeneratedAt: admin.firestore.FieldValue.serverTimestamp(),
                walletType: "smart",
            });

            // Create/update governance doc
            await db.collection("governance").doc(govId).set({
                id: govId,
                communityId: communityId,
                type: "community",
                walletAddress: walletAddress,
                walletType: "smart",
                updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            }, { merge: true });

            console.log(`NEW  ${communityId} → governance/${govId}: ${walletAddress}`);
            created++;
        } catch (e) {
            console.error(`ERR  ${communityId}: ${e.message}`);
            errors++;
        }
    }

    console.log(`\nCommunities: ${created} new, ${existing} synced, ${errors} errors`);

    // ── 3. Summary ──
    console.log("\n=== Final Governance Docs ===\n");
    const govSnap = await db.collection("governance").get();
    for (const doc of govSnap.docs) {
        const d = doc.data();
        const wallet = d.walletAddress ? d.walletAddress.substring(0, 12) + "..." : "NONE";
        const balance = d.treasuryBalance || 0;
        console.log(`  ${doc.id.padEnd(30)} wallet=${wallet.padEnd(16)} DSP=${balance}`);
    }

    process.exit(0);
}

main().catch(e => {
    console.error("Fatal:", e);
    process.exit(1);
});
