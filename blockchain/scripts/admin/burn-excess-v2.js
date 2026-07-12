import hre from "hardhat";

const connection = await hre.network.getOrCreate();
const { ethers } = connection;

/**
 * Burn 120 excess $DIASPORA to restore exact 1,000,000 total supply.
 * 
 * Problem: test-transfer.js minted 1,000 extra tokens on mainnet.
 *   After TGE simulation and transfers, totalSupply = 1,000,120.
 *   Deployer balance = 0 (all tokens moved to other addresses).
 *
 * Solution:
 *   1. Use TGEController.distributeWelcomeBonus() to move 120 tokens
 *      from the TGEController's pre-minted balance to the deployer.
 *   2. Call token.burn(120) which uses ERC20Burnable to actually
 *      reduce totalSupply by 120.
 *
 * Usage: npx hardhat run scripts/burn-excess-v2.js --network base-mainnet
 */
async function main() {
    const [deployer] = await ethers.getSigners();

    const TOKEN_ADDRESS = "0x453f81D3a4Bb142AE34C53798BE35e7600D1b25c";
    const TGE_ADDRESS = "0xa3F092357655C0Bc5fb2Ba4B61f25c5422F59FED";
    const TARGET_SUPPLY = ethers.parseUnits("1000000", 18);

    const token = await ethers.getContractAt("DiasporaToken", TOKEN_ADDRESS);
    const tge = await ethers.getContractAt("DiasporaTGEController", TGE_ADDRESS);

    console.log("=".repeat(60));
    console.log("  $DIASPORA — Burn 120 Excess (Restore 1M Supply)");
    console.log("=".repeat(60));
    console.log("Deployer:", deployer.address);

    // ── Pre-flight checks ─────────────────────────────────────
    const totalSupply = await token.totalSupply();
    const deployerBal = await token.balanceOf(deployer.address);
    const tgeBal = await token.balanceOf(TGE_ADDRESS);

    console.log(`\nTotal supply:       ${ethers.formatUnits(totalSupply, 18)} $DIASPORA`);
    console.log(`Target supply:      ${ethers.formatUnits(TARGET_SUPPLY, 18)} $DIASPORA`);
    console.log(`Deployer balance:   ${ethers.formatUnits(deployerBal, 18)} $DIASPORA`);
    console.log(`TGEController bal:  ${ethers.formatUnits(tgeBal, 18)} $DIASPORA`);

    if (totalSupply <= TARGET_SUPPLY) {
        console.log("\n✅ Supply is already at or below target. Nothing to do.");
        return;
    }

    const excess = totalSupply - TARGET_SUPPLY;
    console.log(`\nExcess to burn: ${ethers.formatUnits(excess, 18)} $DIASPORA`);

    // Verify TGE controller has enough
    if (tgeBal < excess) {
        console.error(`\n❌ TGEController balance (${ethers.formatUnits(tgeBal, 18)}) is less than excess.`);
        console.error("   Cannot proceed — not enough tokens in the controller.");
        return;
    }

    // ── Step 1: Move tokens from TGEController to deployer ────
    console.log("\n📤 Step 1: Moving 120 $DIASPORA from TGEController → Deployer");
    console.log("   Using distributeWelcomeBonus() with deployer as recipient...");

    const tx1 = await tge.distributeWelcomeBonus(
        [deployer.address],
        [excess]
    );
    const receipt1 = await tx1.wait();
    console.log(`   ✅ Transferred! TX: ${receipt1.hash}`);

    const balAfter = await token.balanceOf(deployer.address);
    console.log(`   Deployer balance: ${ethers.formatUnits(balAfter, 18)} $DIASPORA`);

    // ── Step 2: Burn from deployer (reduces totalSupply) ──────
    console.log(`\n🔥 Step 2: Burning ${ethers.formatUnits(excess, 18)} $DIASPORA from deployer`);
    console.log("   Using ERC20Burnable.burn() to reduce totalSupply...");

    const tx2 = await token.burn(excess);
    const receipt2 = await tx2.wait();
    console.log(`   ✅ Burned! TX: ${receipt2.hash}`);

    // ── Verify final state ────────────────────────────────────
    const newSupply = await token.totalSupply();
    const newDeployerBal = await token.balanceOf(deployer.address);
    const newTgeBal = await token.balanceOf(TGE_ADDRESS);

    console.log("\n" + "=".repeat(60));
    console.log("  ✅ BURN COMPLETE!");
    console.log("=".repeat(60));
    console.log(`  New total supply:   ${ethers.formatUnits(newSupply, 18)} $DIASPORA`);
    console.log(`  Target achieved:    ${newSupply === TARGET_SUPPLY ? '✅ YES' : '❌ NO'}`);
    console.log(`  Deployer balance:   ${ethers.formatUnits(newDeployerBal, 18)}`);
    console.log(`  TGEController bal:  ${ethers.formatUnits(newTgeBal, 18)}`);
    console.log(`\n🔗 Verify on Basescan:`);
    console.log(`  Burn TX:  https://basescan.org/tx/${receipt2.hash}`);
    console.log(`  Token:    https://basescan.org/token/${TOKEN_ADDRESS}`);
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
