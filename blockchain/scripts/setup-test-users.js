/**
 * Setup script: Ensure two test users have full wallet infrastructure.
 * 
 * 1. Creates/updates Firestore user docs with walletAddress + walletType
 * 2. Deploys smart wallets on-chain (via factory.createWallet)
 * 3. Funds smart wallets with $DIASPORA from deployer
 * 4. Ensures user_points docs exist
 * 
 * Usage: npx hardhat run scripts/setup-test-users.js --network base-mainnet
 */
import hre from "hardhat";
import admin from "firebase-admin";
import { createRequire } from "node:module";

// Initialize Firebase Admin
const connection = await hre.network.getOrCreate();
const { ethers } = connection;
const require = createRequire(import.meta.url);
const serviceAccount = require("../../tools/admin-scripts/service-account-key.json");
admin.initializeApp({
    credential: admin.credential.cert(serviceAccount),
});
const db = admin.firestore();

const USERS = [
    { uid: "pQBj6QDbttY6LgdNClcmgZtZdH42", phone: "+16505551230", name: "Peter" },
    { uid: "nDqBgaPLVWcNEqpjCIFZhWb11cI2", phone: "+16505551231", name: "Test User B" },
];

async function main() {
    const [deployer] = await ethers.getSigners();

    const TOKEN = "0x453f81D3a4Bb142AE34C53798BE35e7600D1b25c";
    const FACTORY = "0xe2dC28b9AB63F1fA311AAb1dbfd6252b4577CA8C";

    const token = await ethers.getContractAt("DiasporaToken", TOKEN);
    const factory = await ethers.getContractAt("DiasporaWalletFactory", FACTORY);
    const decimals = await token.decimals();
    const fmt = (v) => ethers.formatUnits(v, decimals);

    console.log("=".repeat(60));
    console.log("  Setup Test Users — Smart Wallets + Funding");
    console.log("=".repeat(60));
    console.log("Deployer:", deployer.address);

    // Ensure deployer has enough tokens
    let deployerBal = await token.balanceOf(deployer.address);
    console.log(`\nDeployer balance: ${fmt(deployerBal)} $DIASPORA`);

    const FUND_AMOUNT = ethers.parseUnits("50", decimals); // 50 $DIASPORA per user
    const totalNeeded = FUND_AMOUNT * BigInt(USERS.length);

    if (deployerBal < totalNeeded) {
        const mintAmount = totalNeeded - deployerBal + ethers.parseUnits("10", decimals); // extra buffer
        console.log(`Minting ${fmt(mintAmount)} $DIASPORA to deployer...`);
        const mintTx = await token.mint(deployer.address, mintAmount);
        await mintTx.wait();
        deployerBal = await token.balanceOf(deployer.address);
        console.log(`Deployer balance after mint: ${fmt(deployerBal)} $DIASPORA`);
    }

    for (const user of USERS) {
        console.log(`\n${"─".repeat(50)}`);
        console.log(`Setting up: ${user.name} (${user.phone})`);
        console.log(`UID: ${user.uid}`);

        // Step 1: Compute wallet address from phone hash
        const phoneHash = ethers.keccak256(ethers.toUtf8Bytes(user.phone));
        const computedAddress = await factory.computeAddress(phoneHash);
        console.log(`  Phone hash:  ${phoneHash}`);
        console.log(`  Wallet addr: ${computedAddress}`);

        // Step 2: Deploy wallet on-chain if not already
        const code = await ethers.provider.getCode(computedAddress);
        if (code === "0x") {
            console.log(`  🏗️  Wallet not deployed — deploying via factory...`);
            const deployTx = await factory.createWallet(phoneHash);
            await deployTx.wait();
            console.log(`  ✅ Wallet deployed on-chain! TX: ${deployTx.hash}`);
        } else {
            console.log(`  ✅ Wallet already deployed on-chain.`);
        }

        // Step 3: Fund wallet with $DIASPORA
        const walletBal = await token.balanceOf(computedAddress);
        console.log(`  Current balance: ${fmt(walletBal)} $DIASPORA`);

        if (walletBal < FUND_AMOUNT) {
            const needed = FUND_AMOUNT - walletBal;
            console.log(`  💰 Funding with ${fmt(needed)} $DIASPORA...`);
            const fundTx = await token.transfer(computedAddress, needed);
            await fundTx.wait();
            const newBal = await token.balanceOf(computedAddress);
            console.log(`  ✅ Funded! New balance: ${fmt(newBal)} $DIASPORA`);
        } else {
            console.log(`  ✅ Already sufficiently funded.`);
        }

        // Step 4: Update Firestore user doc
        const userRef = db.collection("users").doc(user.uid);
        const userDoc = await userRef.get();

        const walletData = {
            walletAddress: computedAddress,
            walletType: "smart",
            phoneNumber: user.phone,
        };

        if (userDoc.exists) {
            await userRef.update(walletData);
            console.log(`  ✅ Updated Firestore user doc with wallet.`);
        } else {
            await userRef.set({
                ...walletData,
                fullName: user.name,
                isAdmin: false,
                createdAt: admin.firestore.FieldValue.serverTimestamp(),
            });
            console.log(`  ✅ Created Firestore user doc with wallet.`);
        }

        // Step 5: Ensure user_points doc exists
        const pointsRef = db.collection("user_points").doc(user.uid);
        const pointsDoc = await pointsRef.get();
        if (!pointsDoc.exists) {
            await pointsRef.set({
                userId: user.uid,
                totalPoints: 0,
                availablePoints: 0,
                walletAddress: computedAddress,
                lastUpdated: admin.firestore.FieldValue.serverTimestamp(),
            });
            console.log(`  ✅ Created user_points doc.`);
        } else {
            await pointsRef.update({ walletAddress: computedAddress });
            console.log(`  ✅ Updated user_points with wallet address.`);
        }
    }

    // Final summary
    console.log(`\n${"=".repeat(60)}`);
    console.log("  ✅ SETUP COMPLETE");
    console.log("=".repeat(60));

    for (const user of USERS) {
        const phoneHash = ethers.keccak256(ethers.toUtf8Bytes(user.phone));
        const addr = await factory.computeAddress(phoneHash);
        const bal = await token.balanceOf(addr);
        console.log(`  ${user.name} (${user.phone}): ${fmt(bal)} $DIASPORA at ${addr}`);
    }

    deployerBal = await token.balanceOf(deployer.address);
    console.log(`  Deployer: ${fmt(deployerBal)} $DIASPORA`);
    console.log(`\n  Now you can test transfers in the app!`);

    process.exit(0);
}

main().catch((error) => {
    console.error(error);
    process.exit(1);
});
