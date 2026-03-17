const { ethers, upgrades } = require("hardhat");

/**
 * Upgrade TGEController to V2 — adds distributeWelcomeBonus() function.
 *
 * This is a UUPS proxy upgrade. The proxy address stays the same,
 * only the implementation contract is replaced. All existing state is preserved.
 *
 * New features in V2:
 * - distributeWelcomeBonus(address[], uint256[]) — instant DSP→token conversion on signup
 * - totalWelcomeBonuses state variable — tracks welcome bonus distributions
 * - WelcomeBonusDistributed event — emitted on each welcome bonus distribution
 * - getStats() returns 7 values instead of 6 (added welcomeBonuses)
 *
 * Usage: npx hardhat run scripts/upgrade-tge-v2.js --network base-mainnet
 */
async function main() {
    const [deployer] = await ethers.getSigners();
    const balance = await ethers.provider.getBalance(deployer.address);

    // Production TGE Controller proxy address
    const TGE_PROXY_ADDRESS = "0xa3F092357655C0Bc5fb2Ba4B61f25c5422F59FED";

    console.log("=".repeat(60));
    console.log("  $DIASPORA — TGEController V2 Upgrade");
    console.log("=".repeat(60));
    console.log("Deployer:", deployer.address);
    console.log("Balance:", ethers.formatEther(balance), "ETH");
    console.log("Proxy:", TGE_PROXY_ADDRESS);
    console.log("-".repeat(60));

    // Verify we have the right proxy
    const oldTge = await ethers.getContractAt("DiasporaTGEController", TGE_PROXY_ADDRESS);

    // Read pre-upgrade stats
    let stats;
    try {
        stats = await oldTge.getStats();
        console.log("\n📊 Pre-upgrade state:");
        console.log("  Epoch:", stats[0].toString());
        console.log("  TGE Event:", stats[1].toString());
        console.log("  Total Minted:", ethers.formatUnits(stats[2], 18), "$DIASPORA");
        console.log("  Total Distributed:", ethers.formatUnits(stats[3], 18), "$DIASPORA");
        console.log("  Total Burned:", ethers.formatUnits(stats[4], 18), "$DIASPORA");
        console.log("  TGE Count:", stats[5].toString());
    } catch (e) {
        console.log("  ⚠️ Could not read pre-upgrade stats:", e.message);
    }

    // Check deployer has UPGRADER_ROLE
    const UPGRADER_ROLE = await oldTge.UPGRADER_ROLE();
    const hasRole = await oldTge.hasRole(UPGRADER_ROLE, deployer.address);
    if (!hasRole) {
        console.error("\n❌ Deployer does not have UPGRADER_ROLE. Cannot upgrade.");
        process.exit(1);
    }
    console.log("\n✅ Deployer has UPGRADER_ROLE");

    // Perform the upgrade
    console.log("\n🔄 Upgrading TGEController to V2...");
    const DiasporaTGEControllerV2 = await ethers.getContractFactory("DiasporaTGEController");

    const upgraded = await upgrades.upgradeProxy(
        TGE_PROXY_ADDRESS,
        DiasporaTGEControllerV2,
        { kind: "uups" }
    );
    await upgraded.waitForDeployment();

    console.log("✅ Upgrade complete! Proxy still at:", TGE_PROXY_ADDRESS);

    // Verify post-upgrade state
    const newTge = await ethers.getContractAt("DiasporaTGEController", TGE_PROXY_ADDRESS);

    try {
        const newStats = await newTge.getStats();
        console.log("\n📊 Post-upgrade state:");
        console.log("  Epoch:", newStats[0].toString());
        console.log("  TGE Event:", newStats[1].toString());
        console.log("  Total Minted:", ethers.formatUnits(newStats[2], 18), "$DIASPORA");
        console.log("  Total Distributed:", ethers.formatUnits(newStats[3], 18), "$DIASPORA");
        console.log("  Total Burned:", ethers.formatUnits(newStats[4], 18), "$DIASPORA");
        console.log("  TGE Count:", newStats[5].toString());
        console.log("  Welcome Bonuses:", ethers.formatUnits(newStats[6], 18), "$DIASPORA (new!)");
    } catch (e) {
        console.log("  ⚠️ Could not read post-upgrade stats:", e.message);
    }

    // Verify new function exists
    try {
        const wb = await newTge.totalWelcomeBonuses();
        console.log("\n✅ New totalWelcomeBonuses variable accessible:", ethers.formatUnits(wb, 18));
    } catch (e) {
        console.error("\n❌ New function not found:", e.message);
    }

    // Verify state was preserved
    if (stats) {
        const postStats = await newTge.getStats();
        const preserved =
            postStats[0] === stats[0] &&
            postStats[2] === stats[2] &&
            postStats[3] === stats[3];
        console.log("\n" + (preserved ? "✅" : "❌"), "State preserved:", preserved);
    }

    const finalBalance = await ethers.provider.getBalance(deployer.address);
    console.log("\n⛽ Gas used:", ethers.formatEther(balance - finalBalance), "ETH");
    console.log("💰 Remaining:", ethers.formatEther(finalBalance), "ETH");

    console.log("\n" + "=".repeat(60));
    console.log("  ✅ TGEController V2 Upgrade Complete!");
    console.log("  distributeWelcomeBonus() is now available on-chain.");
    console.log("=".repeat(60));
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
