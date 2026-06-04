/**
 * Register system treasury wallets in Firestore governance docs.
 *
 * Run AFTER create-treasury-wallets.js has deployed the wallets on-chain.
 * Stores the wallet addresses so the welcome bonus distribution can look them up.
 *
 * Usage: node scripts/register-treasury-wallets.js
 *        (Run from the functions/ directory with GOOGLE_APPLICATION_CREDENTIALS set)
 */
const admin = require("firebase-admin");
const { ethers } = require("ethers");
const fs = require("fs");
const path = require("path");

// Load .env manually (no dotenv dependency needed)
function loadEnv(envPath) {
    if (!fs.existsSync(envPath)) return;
    const lines = fs.readFileSync(envPath, "utf8").split("\n");
    for (const line of lines) {
        const trimmed = line.trim();
        if (!trimmed || trimmed.startsWith("#")) continue;
        const eqIdx = trimmed.indexOf("=");
        if (eqIdx === -1) continue;
        const key = trimmed.substring(0, eqIdx).trim();
        const value = trimmed.substring(eqIdx + 1).trim();
        if (!process.env[key]) process.env[key] = value;
    }
}

loadEnv(path.join(__dirname, "..", ".env"));

// Initialize Firebase Admin
if (!admin.apps.length) {
    admin.initializeApp();
}
const db = admin.firestore();

const FACTORY_ABI = [
    "function getWallet(bytes32 phoneHash) view returns (address)",
];

async function main() {
    const RPC_URL = process.env.RPC_URL || "https://mainnet.base.org";
    const WALLET_FACTORY_ADDRESS = process.env.WALLET_FACTORY_ADDRESS;

    if (!WALLET_FACTORY_ADDRESS) {
        console.error("WALLET_FACTORY_ADDRESS not set in .env");
        process.exit(1);
    }

    console.log("RPC:", RPC_URL);
    console.log("Factory:", WALLET_FACTORY_ADDRESS);

    const provider = new ethers.JsonRpcProvider(RPC_URL);
    const factory = new ethers.Contract(WALLET_FACTORY_ADDRESS, FACTORY_ABI, provider);

    const treasuries = [
        { id: "founders", label: "Founders & Core Team", salt: "treasury:founders" },
        { id: "investors", label: "Investors & Partners (SAFT)", salt: "treasury:investors" },
    ];

    console.log("\nRegistering system treasury wallets in Firestore...\n");

    for (const t of treasuries) {
        const saltHash = ethers.keccak256(ethers.toUtf8Bytes(t.salt));
        const walletAddress = await factory.getWallet(saltHash);

        if (walletAddress === ethers.ZeroAddress) {
            console.error(`[SKIP] ${t.label}: Wallet not yet deployed on-chain.`);
            continue;
        }

        console.log(`[OK] ${t.label}: ${walletAddress}`);

        // Write governance doc
        await db.collection("governance").doc(t.id).set({
            id: t.id,
            label: t.label,
            type: "system_treasury",
            walletAddress: walletAddress,
            walletType: "smart",
            salt: t.salt,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });

        console.log(`   -> governance/${t.id} updated`);
    }

    console.log("\nDone! Founders and Investors governance docs registered.");
    process.exit(0);
}

main().catch((err) => {
    console.error("Error:", err.message);
    process.exit(1);
});
