const { ethers } = require("hardhat");

/**
 * Pre-mint the Epoch supply and lock it in the TGEController.
 * Run this AFTER deploy-production.js to lock the epoch's token supply.
 *
 * Epoch Schedule (10x scaling):
 *   Epoch 1:  1,000,000 $DIASPORA
 *   Epoch 2:  10,000,000
 *   Epoch 3:  100,000,000
 *   ...
 *   Epoch 10: 1,000,000,000,000,000 (1 Quadrillion)
 *
 * Usage: npx hardhat run scripts/mint-epoch-supply.js --network base-mainnet
 *
 * Set EPOCH_NUMBER env var to mint for a specific epoch (default: 1).
 * Example: EPOCH_NUMBER=2 npx hardhat run scripts/mint-epoch-supply.js --network base-mainnet
 */

const EPOCH_SUPPLY = {
    1: "1000000",             // 1M
    2: "10000000",            // 10M
    3: "100000000",           // 100M
    4: "1000000000",          // 1B
    5: "10000000000",         // 10B
    6: "100000000000",        // 100B
    7: "1000000000000",       // 1T
    8: "10000000000000",      // 10T
    9: "100000000000000",     // 100T
    10: "1000000000000000",   // 1QD
};

async function main() {
    const [deployer] = await ethers.getSigners();

    // Use env vars or hardcoded addresses (update after deploy-production.js)
    const TOKEN_ADDRESS = process.env.TOKEN_ADDRESS || "REPLACE_AFTER_DEPLOY";
    const TGE_ADDRESS = process.env.TGE_CONTROLLER_ADDRESS || "REPLACE_AFTER_DEPLOY";

    if (TOKEN_ADDRESS === "REPLACE_AFTER_DEPLOY" || TGE_ADDRESS === "REPLACE_AFTER_DEPLOY") {
        console.error("❌ Set TOKEN_ADDRESS and TGE_CONTROLLER_ADDRESS in .env first!");
        console.error("   Run deploy-production.js first, then update .env with the new addresses.");
        process.exit(1);
    }

    const epochNumber = parseInt(process.env.EPOCH_NUMBER || "1");
    const epochSupply = EPOCH_SUPPLY[epochNumber];

    if (!epochSupply) {
        console.error(`❌ Invalid epoch number: ${epochNumber}. Must be 1–10.`);
        process.exit(1);
    }

    const token = await ethers.getContractAt("DiasporaToken", TOKEN_ADDRESS);
    const tge = await ethers.getContractAt("DiasporaTGEController", TGE_ADDRESS);

    console.log("=".repeat(60));
    console.log(`  🔒 $DIASPORA — Mint & Lock Epoch ${epochNumber} Supply`);
    console.log("=".repeat(60));
    console.log("Deployer:", deployer.address);
    console.log("Token:", TOKEN_ADDRESS);
    console.log("TGEController:", TGE_ADDRESS);

    // Verify current state
    const stats = await tge.getStats();
    const currentEpoch = Number(stats[0]);
    console.log(`\nOn-chain Epoch: ${currentEpoch}`);
    console.log(`Requested Epoch: ${epochNumber}`);
    console.log(`Epoch ${epochNumber} Supply: ${Number(epochSupply).toLocaleString()} $DIASPORA`);

    // Check controller's current balance
    const balanceBefore = await token.balanceOf(TGE_ADDRESS);
    console.log(`\nController balance before: ${ethers.formatUnits(balanceBefore, 18)} $DIASPORA`);

    // Mint epoch supply to TGEController
    console.log(`\n🔒 Minting ${Number(epochSupply).toLocaleString()} $DIASPORA to TGEController...`);
    const amount = ethers.parseUnits(epochSupply, 18);
    const tx = await tge.mintEpochSupply(amount);
    const receipt = await tx.wait();

    // Verify
    const balanceAfter = await token.balanceOf(TGE_ADDRESS);
    const totalSupply = await token.totalSupply();
    const statsAfter = await tge.getStats();
    const lockedBalance = await tge.getLockedBalance();

    console.log("\n" + "=".repeat(60));
    console.log(`  ✅ Epoch ${epochNumber} Supply Locked!`);
    console.log("=".repeat(60));
    console.log(`  TX Hash: ${receipt.hash}`);
    console.log(`  Controller balance: ${ethers.formatUnits(balanceAfter, 18)} $DIASPORA`);
    console.log(`  Locked balance: ${ethers.formatUnits(lockedBalance, 18)} $DIASPORA`);
    console.log(`  Total supply: ${ethers.formatUnits(totalSupply, 18)} $DIASPORA`);
    console.log(`  Total minted (lifetime): ${ethers.formatUnits(statsAfter[2], 18)} $DIASPORA`);
    console.log(`\n🔗 Verify on Basescan:`);
    console.log(`  https://basescan.org/tx/${receipt.hash}`);
    console.log(`  https://basescan.org/address/${TGE_ADDRESS}`);
    console.log(`\n📢 Users can verify: TGEController holds exactly ${Number(epochSupply).toLocaleString()} $DIASPORA`);
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
