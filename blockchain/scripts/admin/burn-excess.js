const { ethers } = require("hardhat");

/**
 * Burn excess tokens to restore exact 1,000,000 $DIASPORA max supply.
 * 
 * The test-transfer.js script minted 1,000 tokens directly to the deployer
 * on mainnet during testing, pushing totalSupply above the intended 1M.
 * This script burns the excess from the deployer's balance.
 *
 * Usage: npx hardhat run scripts/burn-excess.js --network base-mainnet
 */
async function main() {
    const [deployer] = await ethers.getSigners();

    const TOKEN_ADDRESS = "0x453f81D3a4Bb142AE34C53798BE35e7600D1b25c";
    const TARGET_SUPPLY = ethers.parseUnits("1000000", 18); // Exact 1M

    const token = await ethers.getContractAt("DiasporaToken", TOKEN_ADDRESS);

    console.log("=".repeat(55));
    console.log("  $DIASPORA — Burn Excess Tokens");
    console.log("=".repeat(55));
    console.log("Deployer:", deployer.address);

    const totalSupply = await token.totalSupply();
    const deployerBalance = await token.balanceOf(deployer.address);

    console.log(`\nCurrent total supply: ${ethers.formatUnits(totalSupply, 18)} $DIASPORA`);
    console.log(`Target total supply:  ${ethers.formatUnits(TARGET_SUPPLY, 18)} $DIASPORA`);
    console.log(`Deployer balance:     ${ethers.formatUnits(deployerBalance, 18)} $DIASPORA`);

    if (totalSupply <= TARGET_SUPPLY) {
        console.log("\n✅ Total supply is already at or below target. Nothing to burn.");
        return;
    }

    const excess = totalSupply - TARGET_SUPPLY;
    console.log(`\nExcess to burn: ${ethers.formatUnits(excess, 18)} $DIASPORA`);

    // Verify deployer has enough to burn
    if (deployerBalance < excess) {
        console.error(`\n❌ Deployer balance (${ethers.formatUnits(deployerBalance, 18)}) is less than excess (${ethers.formatUnits(excess, 18)}).`);
        console.error("   Some excess tokens may have been transferred elsewhere.");
        console.error("   Burning deployer's full balance instead...");

        const tx = await token.burn(deployerBalance);
        const receipt = await tx.wait();
        const newSupply = await token.totalSupply();
        console.log(`\n✅ Burned ${ethers.formatUnits(deployerBalance, 18)} $DIASPORA`);
        console.log(`   New total supply: ${ethers.formatUnits(newSupply, 18)} $DIASPORA`);
        console.log(`   Remaining excess: ${ethers.formatUnits(newSupply - TARGET_SUPPLY, 18)} $DIASPORA`);
        console.log(`   TX: ${receipt.hash}`);
        return;
    }

    // Burn the exact excess
    console.log(`\n🔥 Burning ${ethers.formatUnits(excess, 18)} $DIASPORA from deployer...`);
    const tx = await token.burn(excess);
    const receipt = await tx.wait();

    // Verify
    const newSupply = await token.totalSupply();
    const newBalance = await token.balanceOf(deployer.address);

    console.log("\n" + "=".repeat(55));
    console.log("  ✅ Excess Burned Successfully!");
    console.log("=".repeat(55));
    console.log(`  TX Hash: ${receipt.hash}`);
    console.log(`  New total supply:   ${ethers.formatUnits(newSupply, 18)} $DIASPORA`);
    console.log(`  Deployer balance:   ${ethers.formatUnits(newBalance, 18)} $DIASPORA`);
    console.log(`  Target achieved:    ${newSupply === TARGET_SUPPLY ? '✅ YES' : '❌ NO'}`);
    console.log(`\n🔗 Verify on Basescan:`);
    console.log(`  https://basescan.org/tx/${receipt.hash}`);
    console.log(`  https://basescan.org/token/${TOKEN_ADDRESS}`);
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
