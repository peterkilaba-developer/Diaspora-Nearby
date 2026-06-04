const { ethers } = require("hardhat");

/**
 * Pre-create dedicated smart wallets for system treasuries:
 * - Founders & Core Team
 * - Investors & Partners (SAFT)
 *
 * Uses the same DiasporaWalletFactory with deterministic salts:
 * - treasury:founders  → keccak256 → CREATE2 wallet
 * - treasury:investors → keccak256 → CREATE2 wallet
 *
 * Stores wallet addresses in Firestore governance docs for use in
 * welcome bonus distribution and TGE snapshots.
 *
 * Usage: npx hardhat run scripts/create-treasury-wallets.js --network base-mainnet
 */
async function main() {
    const [deployer] = await ethers.getSigners();
    const balance = await ethers.provider.getBalance(deployer.address);

    const WALLET_FACTORY_ADDRESS = process.env.WALLET_FACTORY_ADDRESS;

    console.log("=".repeat(60));
    console.log("  $DIASPORA — System Treasury Wallet Creation");
    console.log("=".repeat(60));
    console.log("Deployer:", deployer.address);
    console.log("Balance:", ethers.formatEther(balance), "ETH");
    console.log("Factory:", WALLET_FACTORY_ADDRESS);
    console.log("-".repeat(60));

    if (!WALLET_FACTORY_ADDRESS) {
        console.error("❌ WALLET_FACTORY_ADDRESS not set in .env");
        process.exit(1);
    }

    const FACTORY_ABI = [
        "function computeAddress(bytes32 phoneHash) view returns (address)",
        "function createWallet(bytes32 phoneHash) returns (address)",
        "function walletExists(bytes32 phoneHash) view returns (bool)",
        "function getWallet(bytes32 phoneHash) view returns (address)",
    ];

    const factory = new ethers.Contract(WALLET_FACTORY_ADDRESS, FACTORY_ABI, deployer);

    const treasuries = [
        { id: "founders", label: "Founders & Core Team", salt: "treasury:founders" },
        { id: "investors", label: "Investors & Partners (SAFT)", salt: "treasury:investors" },
    ];

    const results = [];

    for (const t of treasuries) {
        console.log(`\n📦 Creating wallet for: ${t.label}`);
        console.log(`   Salt: "${t.salt}"`);

        const saltHash = ethers.keccak256(ethers.toUtf8Bytes(t.salt));
        console.log(`   Hash: ${saltHash}`);

        // Check if already exists
        const existing = await factory.getWallet(saltHash);
        if (existing !== ethers.ZeroAddress) {
            console.log(`   ✅ Already exists: ${existing}`);
            results.push({ ...t, address: existing, status: "existing" });
            continue;
        }

        // Compute predicted address
        const predicted = await factory.computeAddress(saltHash);
        console.log(`   Predicted: ${predicted}`);

        try {
            const tx = await factory.createWallet(saltHash);
            const receipt = await tx.wait();
            console.log(`   ✅ Created: ${predicted} (tx: ${receipt.hash})`);
            results.push({ ...t, address: predicted, status: "created", txHash: receipt.hash });
        } catch (err) {
            console.error(`   ❌ Failed: ${err.message}`);
            // Still store predicted address (CREATE2 is deterministic)
            results.push({ ...t, address: predicted, status: "pending" });
        }
    }

    // Summary
    const finalBalance = await ethers.provider.getBalance(deployer.address);

    console.log("\n" + "=".repeat(60));
    console.log("  ✅ System Treasury Wallets");
    console.log("=".repeat(60));

    for (const r of results) {
        console.log(`\n  ${r.label}:`);
        console.log(`    Address: ${r.address}`);
        console.log(`    Status:  ${r.status}`);
        if (r.txHash) console.log(`    TX:      ${r.txHash}`);
    }

    console.log(`\n⛽ Gas used: ${ethers.formatEther(balance - finalBalance)} ETH`);
    console.log(`💰 Remaining: ${ethers.formatEther(finalBalance)} ETH`);

    console.log("\n📝 Update .env with:");
    for (const r of results) {
        const envKey = r.id.toUpperCase() + "_TREASURY_ADDRESS";
        console.log(`  ${envKey}=${r.address}`);
    }

    console.log("\n📋 Firestore governance docs to update:");
    for (const r of results) {
        console.log(`  governance/${r.id} → walletAddress: "${r.address}"`);
    }
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
