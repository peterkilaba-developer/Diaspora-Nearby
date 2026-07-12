import admin from "firebase-admin";
import hre from "hardhat";
import { createRequire } from "node:module";
import "dotenv/config";

// Initialize Firebase Admin
const connection = await hre.network.getOrCreate();
const { ethers } = connection;
const require = createRequire(import.meta.url);
const serviceAccount = require("../../tools/admin-scripts/service-account-key.json");
if (!admin.apps.length) {
    admin.initializeApp({
        credential: admin.credential.cert(serviceAccount)
    });
}
const db = admin.firestore();

async function main() {
    const [oracle] = await ethers.getSigners();
    console.log("Oracle starting with account:", oracle.address);

    // Contract Instances
    const engineAddress = process.env.ENGINE_ADDRESS;
    const tgeAddress = process.env.TGE_ADDRESS;

    if (!engineAddress || !tgeAddress) {
        console.error("Missing ENGINE_ADDRESS or TGE_ADDRESS in .env");
        process.exit(1);
    }

    const ExpansionEngine = await ethers.getContractAt("DiasporaExpansionEngine", engineAddress);
    const TGEController = await ethers.getContractAt("DiasporaTGEController", tgeAddress);

    console.log("--- Starting Sync Loop ---");

    /**
     * 1. REWARD SYNCHRONIZATION
     * Scans Firestore for unsynced 'earn' transactions.
     */
    async function syncRewards() {
        console.log("Checking for unsynced rewards...");
        const snapshot = await db.collection("points_transactions")
            .where("type", "==", "earn")
            .where("synchronized", "==", false)
            .limit(50)
            .get();

        if (snapshot.empty) {
            console.log("No new rewards to sync.");
            return;
        }

        for (const doc of snapshot.docs) {
            const data = doc.data();
            const userAddress = data.metadata?.walletAddress; // Assumes app collects wallet address
            const points = data.points;

            if (!userAddress) {
                console.log(`Skipping txn ${doc.id}: No wallet address.`);
                continue;
            }

            try {
                // Convert points to Wei (DSP has 18 decimals)
                const amountWei = ethers.parseEther(points.toString());

                console.log(`Syncing ${points} DSP to ${userAddress}...`);
                const tx = await ExpansionEngine.recordActivity(userAddress, amountWei);
                await tx.wait();

                // Mark as synced in Firestore
                await doc.ref.update({ synchronized: true, onChainTx: tx.hash });
                console.log(`Successfully synced txn ${doc.id}`);
            } catch (error) {
                console.error(`Failed to sync txn ${doc.id}:`, error.message);
            }
        }
    }

    /**
     * 2. TGE EXECUTION
     * Checks if a milestone has been reached and triggers release/burn.
     */
    async function checkTGE() {
        console.log("Checking TGE milestones...");
        const supplyDoc = await db.collection("system_stats").doc("dsp_supply").get();
        if (!supplyDoc.exists) return;

        const data = supplyDoc.data();
        const totalMinted = data.totalMinted || 0;
        const lastTgeSupply = data.lastTgeSupply || 0;

        // Trigger TGE every 1 Billion DSP expansion (Simulated threshold)
        const threshold = 1000000000;
        if (totalMinted - lastTgeSupply >= threshold) {
            console.log("🔥 TGE Threshold reached! Preparing execution...");

            // In a real scenario, we'd fetch all users/communities with staged balances.
            // For the bridge prototype, we fetch active participants.
            const recipients = [];
            const efficiencies = [];

            // Example: Collect User Efficiencies
            const userPoints = await db.collection("user_points").limit(10).get();
            for (const userDoc of userPoints.docs) {
                const userData = userDoc.data();
                const wallet = userData.walletAddress;
                if (wallet) {
                    recipients.push(wallet);
                    efficiencies.push(Math.floor(userData.trustScore || 0));
                }
            }

            // Example: Collect Community Efficiencies
            const communities = await db.collection("communities").limit(10).get();
            for (const commDoc of communities.docs) {
                const commData = commDoc.data();
                const wallet = commData.treasuryAddress;
                if (wallet) {
                    recipients.push(wallet);
                    efficiencies.push(Math.floor(commData.averagePoCT || 0));
                }
            }

            if (recipients.length > 0) {
                console.log(`Executing TGE for ${recipients.length} recipients...`);
                // Batch size of 50 to avoid gas limits
                const tx = await TGEController.executeTGE(recipients, efficiencies);
                await tx.wait();

                await db.collection("system_stats").doc("dsp_supply").update({
                    lastTgeSupply: totalMinted,
                    lastTgeTimestamp: admin.firestore.FieldValue.serverTimestamp()
                });
                console.log("TGE Execution Complete.");
            }
        }
    }

    // Run once and exit for this demonstration
    // In production, this would be a Cron job or a long-running process
    await syncRewards();
    await checkTGE();
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
