/**
 * Create the missing governance/burn doc.
 * 
 * This script uses firebase-admin with the Firebase CLI's auth context.
 * Run: firebase functions:shell < scripts/create-burn-gov.js
 * Or: node -e "..." in functions dir with correct GOOGLE_APPLICATION_CREDENTIALS
 */

// Use firebase functions shell approach - get admin from the already-initialized context
const functions = require("firebase-functions");
const admin = require("firebase-admin");

// When running as a Node script (not in firebase shell), initialize ourselves
if (!admin.apps.length) {
    admin.initializeApp({
        projectId: "diaspora-nearby-a3dac",
    });
}

const db = admin.firestore();

async function createBurnDoc() {
    console.log("Creating governance/burn document...");

    await db.collection("governance").doc("burn").set({
        id: "burn",
        name: "Deflationary Burn",
        type: "system",
        treasuryBalance: 0,
        title: "Burn Treasury",
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });

    console.log("SUCCESS: governance/burn document created!");
}

createBurnDoc()
    .then(() => process.exit(0))
    .catch((err) => {
        console.error("ERROR:", err.message);
        process.exit(1);
    });
