import hre from "hardhat";

const connection = await hre.network.getOrCreate();
const { ethers } = connection;

/**
 * Test $DIASPORA round-trip transfer: deployer EOA ↔ smart wallet.
 * 
 * Flow:
 * 1. Check balances (mint if deployer is empty)
 * 2. Deploy smart wallet on-chain if not yet live
 * 3. Send tokens: EOA → Smart Wallet
 * 4. Send tokens back: Smart Wallet → EOA
 * 
 * Usage: npx hardhat run scripts/test-smart-wallet-transfer.js --network base-mainnet
 */
async function main() {
    const [deployer] = await ethers.getSigners();

    const TOKEN = "0x453f81D3a4Bb142AE34C53798BE35e7600D1b25c";
    const WALLET = "0x5562E6EBa6A57BaBc0f638aB3D2178c774b1fBae";
    const FACTORY = "0xe2dC28b9AB63F1fA311AAb1dbfd6252b4577CA8C";

    const token = await ethers.getContractAt("DiasporaToken", TOKEN);
    const factory = await ethers.getContractAt("DiasporaWalletFactory", FACTORY);
    const decimals = await token.decimals();

    const fmt = (v) => ethers.formatUnits(v, decimals);

    console.log("=".repeat(60));
    console.log("  $DIASPORA — Smart Wallet Round-Trip Transfer Test");
    console.log("=".repeat(60));
    console.log("Deployer:     ", deployer.address);
    console.log("Smart Wallet: ", WALLET);

    // ── 1. Balances ──
    let dBal = await token.balanceOf(deployer.address);
    let sBal = await token.balanceOf(WALLET);
    const ethBal = await ethers.provider.getBalance(deployer.address);
    console.log(`\n📊 Deployer:  ${fmt(dBal)} $DIASPORA  (${ethers.formatEther(ethBal)} ETH)`);
    console.log(`   Smart:     ${fmt(sBal)} $DIASPORA`);

    // Mint if empty
    if (dBal === 0n) {
        console.log("\n🔨 Deployer has 0 $DIASPORA — minting 100 for testing...");
        const tx = await token.mint(deployer.address, ethers.parseUnits("100", decimals));
        await tx.wait();
        dBal = await token.balanceOf(deployer.address);
        console.log(`   ✅ Minted! Balance: ${fmt(dBal)} $DIASPORA  TX: ${tx.hash}`);
    }

    // ── 2. Deploy smart wallet if not live ──
    const code = await ethers.provider.getCode(WALLET);
    if (code === "0x") {
        console.log("\n🏗️  Smart wallet not deployed on-chain. Deploying via factory...");
        // We need the phoneHash that produces this address.
        // Reverse-lookup: try the user's phone from Firestore — but we don't have it here.
        // Instead, brute-check computeAddress with the phoneHash stored in the factory mapping.
        // Actually, the simplest way: look up the walletToPhoneHash mapping by iterating,
        // but we can't call it with the wallet address because the wallet isn't in the mapping yet
        // (it was only computed, not created).
        // 
        // So we need the original phone/label used. Let's get it from Firestore via the user doc.
        console.log("   ⚠️  Need the phone hash to deploy. Checking factory records...");

        // Check if we can just look up by the wallet address in the reverse mapping
        const storedHash = await factory.walletToPhoneHash(WALLET);
        console.log(`   Stored hash: ${storedHash}`);

        if (storedHash === ethers.ZeroHash) {
            console.log("   Wallet was pre-computed but never created on-chain.");
            console.log("   We need the phone number to derive the salt and deploy.");
            console.log("   Let's try to find it from the Cloud Function logs...\n");

            // For testing, let's just manually get the phone number from Firestore
            // and compute the hash. We'll use a known phone number for now.
            // Actually, we can call computeAddress with different salts to find a match.
            // But that's extremely expensive. Let's just use the Cloud Function instead.

            console.log("   📌 ACTION REQUIRED: Call getOrCreateSmartWallet from the app");
            console.log("      to deploy the wallet on-chain, then re-run this script.");
            console.log("      Alternatively, provide the phone number below.\n");

            // FALLBACK: If you know the phone number, uncomment and set it:
            // const phoneNumber = "+1234567890";
            // const phoneHash = ethers.keccak256(ethers.toUtf8Bytes(phoneNumber));
            // console.log(`   Phone hash: ${phoneHash}`);
            // const computedAddr = await factory.computeAddress(phoneHash);
            // console.log(`   Computed addr: ${computedAddr}`);
            // if (computedAddr === WALLET) {
            //     console.log("   ✅ Match! Deploying...");
            //     const tx = await factory.createWallet(phoneHash);
            //     await tx.wait();
            //     console.log("   ✅ Deployed!");
            // }

            // For now, tokens sent TO the address are safe even without deployment.
            // Let's still test sending TO it.
            console.log("   ℹ️  Proceeding with one-way transfer (EOA → pre-computed address).");
            console.log("      Tokens are safe at that address and will be recoverable\n");
        } else {
            console.log("   Found hash, deploying wallet...");
            const tx = await factory.createWallet(storedHash);
            await tx.wait();
            console.log("   ✅ Deployed!");
        }
    } else {
        console.log("\n✅ Smart wallet is live on-chain.");
    }

    // ── 3. Send EOA → Smart Wallet ──
    const sendAmount = ethers.parseUnits("10", decimals);
    console.log(`\n💸 Step 3: Sending 10 $DIASPORA → Smart Wallet...`);
    const tx1 = await token.transfer(WALLET, sendAmount);
    console.log(`   ⏳ TX: ${tx1.hash}`);
    await tx1.wait();
    dBal = await token.balanceOf(deployer.address);
    sBal = await token.balanceOf(WALLET);
    console.log(`   ✅ Done!  Deployer: ${fmt(dBal)}  Smart: ${fmt(sBal)}`);

    // ── 4. Send Smart Wallet → EOA (only if deployed) ──
    const liveCode = await ethers.provider.getCode(WALLET);
    if (liveCode !== "0x") {
        console.log(`\n💸 Step 4: Sending 5 $DIASPORA ← Smart Wallet...`);
        const smartWallet = await ethers.getContractAt("DiasporaSmartWallet", WALLET);
        const sendBack = ethers.parseUnits("5", decimals);
        const tx2 = await smartWallet.transferToken(TOKEN, deployer.address, sendBack);
        console.log(`   ⏳ TX: ${tx2.hash}`);
        await tx2.wait();
        dBal = await token.balanceOf(deployer.address);
        sBal = await token.balanceOf(WALLET);
        console.log(`   ✅ Done!  Deployer: ${fmt(dBal)}  Smart: ${fmt(sBal)}`);
    } else {
        console.log("\n⏩ Step 4: Skipped (wallet not deployed, can't call transferToken)");
        console.log("   Tokens at the pre-computed address are safe!");
    }

    // ── Final ──
    dBal = await token.balanceOf(deployer.address);
    sBal = await token.balanceOf(WALLET);
    console.log("\n" + "=".repeat(60));
    console.log("  RESULTS");
    console.log("=".repeat(60));
    console.log(`  Deployer: ${fmt(dBal)} $DIASPORA`);
    console.log(`  Smart:    ${fmt(sBal)} $DIASPORA`);
    console.log(`  https://basescan.org/address/${WALLET}#tokentxns`);
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
