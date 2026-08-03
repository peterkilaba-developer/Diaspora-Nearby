import hre from "hardhat";

const connection = await hre.network.getOrCreate();
const { ethers } = connection;

/**
 * Test full epoch cycle: 10 TDE releases → epoch advances.
 * Verifies the TDE counter and epoch advancement logic on mainnet.
 */
async function main() {
    const [deployer] = await ethers.getSigners();

    // Production contracts (1M $DIASPORA — Epoch 1)
    const TOKEN_ADDRESS = "0x453f81D3a4Bb142AE34C53798BE35e7600D1b25c";
    const TGE_ADDRESS = "0xa3F092357655C0Bc5fb2Ba4B61f25c5422F59FED";

    const token = await ethers.getContractAt("DiasporaToken", TOKEN_ADDRESS);
    const tge = await ethers.getContractAt("DiasporaTGEController", TGE_ADDRESS);

    console.log("=".repeat(55));
    console.log("  $DIASPORA — Full Epoch Cycle Test");
    console.log("=".repeat(55));

    // Check starting state
    let stats = await tge.getStats();
    console.log(`\nStarting state: Epoch ${stats[0]}, TDE ${stats[1]}`);
    console.log(`Already minted: ${ethers.formatUnits(stats[2], 18)} DIASPORA`);

    const startEpoch = Number(stats[0]);
    const startEvent = Number(stats[1]);
    const eventsNeeded = 10 - startEvent; // TDE releases to complete this epoch

    console.log(`\nNeed ${eventsNeeded} more TDE releases to complete Epoch ${startEpoch}`);
    console.log(`Running ${eventsNeeded} mini TDE releases (10 $DIASPORA each)...\n`);

    for (let i = 0; i < eventsNeeded; i++) {
        // Small TDE: 1 recipient, 10 DIASPORA, 90% efficiency
        const tx = await tge.executeTGE(
            [deployer.address],
            [ethers.parseUnits("10", 18)],
            [90]
        );
        await tx.wait();

        stats = await tge.getStats();
        const epoch = Number(stats[0]);
        const event = Number(stats[1]);
        const totalEvents = Number(stats[5]);

        console.log(`  TDE #${i + 1}: Epoch ${epoch}, Event ${event} (total: ${totalEvents})`);

        // Check if epoch advanced
        if (epoch > startEpoch) {
            console.log(`\n  🎉 EPOCH ${startEpoch} COMPLETE → Now in Epoch ${epoch}!`);
        }
    }

    // Final stats
    stats = await tge.getStats();
    const supply = await token.totalSupply();
    const ethBal = await ethers.provider.getBalance(deployer.address);

    console.log("\n" + "=".repeat(55));
    console.log("  ✅ Epoch Cycle Test Complete");
    console.log("=".repeat(55));
    console.log(`  Current Epoch: ${stats[0]}`);
    console.log(`  Current TDE: ${stats[1]}`);
    console.log(`  Total TDE Releases: ${stats[5]}`);
    console.log(`  Total minted: ${ethers.formatUnits(stats[2], 18)} DIASPORA`);
    console.log(`  Total distributed: ${ethers.formatUnits(stats[3], 18)} DIASPORA`);
    console.log(`  Total burned: ${ethers.formatUnits(stats[4], 18)} DIASPORA`);
    console.log(`  Token supply: ${ethers.formatUnits(supply, 18)} DIASPORA`);
    console.log(`  ETH remaining: ${ethers.formatEther(ethBal)} ETH`);
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
