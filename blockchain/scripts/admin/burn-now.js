const { ethers } = require("hardhat");

/**
 * Step 2: Burn the 120 $DIASPORA now sitting in deployer's wallet.
 * This reduces totalSupply from 1,000,120 → 1,000,000.
 * 
 * Usage: npx hardhat run scripts/burn-now.js --network base-mainnet
 */
async function main() {
    const [deployer] = await ethers.getSigners();
    const TOKEN_ADDRESS = "0x453f81D3a4Bb142AE34C53798BE35e7600D1b25c";
    const TARGET_SUPPLY = ethers.parseUnits("1000000", 18);

    const token = await ethers.getContractAt("DiasporaToken", TOKEN_ADDRESS);

    const supplyBefore = await token.totalSupply();
    const balBefore = await token.balanceOf(deployer.address);

    console.log("=".repeat(55));
    console.log("  $DIASPORA — BURN 120 EXCESS");
    console.log("=".repeat(55));
    console.log(`Supply before:    ${ethers.formatUnits(supplyBefore, 18)}`);
    console.log(`Deployer balance: ${ethers.formatUnits(balBefore, 18)}`);

    const burnAmount = supplyBefore - TARGET_SUPPLY;
    if (burnAmount <= 0n) {
        console.log("\n✅ Already at target. Nothing to burn.");
        return;
    }

    if (balBefore < burnAmount) {
        console.error(`\n❌ Deployer only has ${ethers.formatUnits(balBefore, 18)} but need to burn ${ethers.formatUnits(burnAmount, 18)}`);
        return;
    }

    console.log(`\n🔥 Burning ${ethers.formatUnits(burnAmount, 18)} $DIASPORA...`);
    const tx = await token.burn(burnAmount);
    const receipt = await tx.wait();

    const supplyAfter = await token.totalSupply();
    const balAfter = await token.balanceOf(deployer.address);

    console.log("\n" + "=".repeat(55));
    console.log("  ✅ BURN COMPLETE!");
    console.log("=".repeat(55));
    console.log(`  TX Hash:          ${receipt.hash}`);
    console.log(`  Supply after:     ${ethers.formatUnits(supplyAfter, 18)} $DIASPORA`);
    console.log(`  Target achieved:  ${supplyAfter === TARGET_SUPPLY ? '✅ YES' : '❌ NO'}`);
    console.log(`  Deployer balance: ${ethers.formatUnits(balAfter, 18)}`);
    console.log(`\n🔗 Verify:`);
    console.log(`  https://basescan.org/tx/${receipt.hash}`);
    console.log(`  https://basescan.org/token/${TOKEN_ADDRESS}`);
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
