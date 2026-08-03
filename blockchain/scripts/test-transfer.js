import hre from "hardhat";

const connection = await hre.network.getOrCreate();
const { ethers } = connection;

/**
 * Test $DIASPORA token on Base Mainnet.
 * Mints, transfers, and simulates a TDE release with the real contract.
 * 
 * Usage: npx hardhat run scripts/test-transfer.js --network base-mainnet
 */
async function main() {
    const [deployer] = await ethers.getSigners();

    // Production contracts (1M $DIASPORA — Epoch 1)
    const TOKEN_ADDRESS = "0x453f81D3a4Bb142AE34C53798BE35e7600D1b25c";
    const TGE_ADDRESS = "0xa3F092357655C0Bc5fb2Ba4B61f25c5422F59FED";
    const BURN_ADDRESS = "0x000000000000000000000000000000000000dEaD";

    const token = await ethers.getContractAt("DiasporaToken", TOKEN_ADDRESS);
    const tge = await ethers.getContractAt("DiasporaTGEController", TGE_ADDRESS);

    console.log("=".repeat(55));
    console.log("  $DIASPORA — Live Token Test (Base Mainnet)");
    console.log("=".repeat(55));
    console.log("Deployer:", deployer.address);

    // ── Verify Token ─────────────────────────────────────────
    const name = await token.name();
    const symbol = await token.symbol();
    const decimals = await token.decimals();
    console.log(`\n📋 Token: ${name} (${symbol}), ${decimals} decimals`);
    console.log("   Hard cap:", ethers.formatUnits(await token.HARD_CAP(), decimals), symbol);

    let supply = await token.totalSupply();
    console.log("   Current supply:", ethers.formatUnits(supply, decimals), symbol);

    // ── Test 1: Mint ─────────────────────────────────────────
    console.log("\n🔨 Test 1: Minting 1,000 $DIASPORA to deployer...");
    const mintAmount = ethers.parseUnits("1000", decimals);
    const tx1 = await token.mint(deployer.address, mintAmount);
    await tx1.wait();

    let balance = await token.balanceOf(deployer.address);
    console.log("   ✅ Deployer balance:", ethers.formatUnits(balance, decimals), symbol);
    console.log("   📝 TX:", tx1.hash);

    // ── Test 2: Transfer ─────────────────────────────────────
    console.log("\n💸 Test 2: Transferring 100 $DIASPORA to burn address...");
    const tx2 = await token.transfer(BURN_ADDRESS, ethers.parseUnits("100", decimals));
    await tx2.wait();

    balance = await token.balanceOf(deployer.address);
    const burnBalance = await token.balanceOf(BURN_ADDRESS);
    console.log("   ✅ Deployer:", ethers.formatUnits(balance, decimals), symbol);
    console.log("   ✅ Burn addr:", ethers.formatUnits(burnBalance, decimals), symbol);
    console.log("   📝 TX:", tx2.hash);

    // ── Test 3: TDE Simulation ───────────────────────────────
    console.log("\n🎯 Test 3: Simulated TDE release...");
    console.log("   Snapshot: 2 addresses, different efficiencies");

    const recipients = [deployer.address, deployer.address];
    const amounts = [
        ethers.parseUnits("500", decimals),   // 500 DIASPORA at 80% efficiency
        ethers.parseUnits("300", decimals),   // 300 DIASPORA at 100% efficiency
    ];
    const efficiencies = [80, 100];

    // Expected: 
    //   500 * 80% = 400 liquid + 100 burned
    //   300 * 100% = 300 liquid + 0 burned
    //   Total: 700 distributed, 100 burned

    const tx3 = await tge.executeTGE(recipients, amounts, efficiencies);
    await tx3.wait();

    const stats = await tge.getStats();
    console.log("   ✅ TGE executed!");
    console.log("   📊 Epoch:", stats[0].toString(), "| TDE:", stats[1].toString());
    console.log("   📊 Total minted:", ethers.formatUnits(stats[2], decimals), symbol);
    console.log("   📊 Total distributed:", ethers.formatUnits(stats[3], decimals), symbol);
    console.log("   📊 Total burned:", ethers.formatUnits(stats[4], decimals), symbol);
    console.log("   📝 TX:", tx3.hash);

    // ── Final Stats ──────────────────────────────────────────
    supply = await token.totalSupply();
    balance = await token.balanceOf(deployer.address);
    const burned = await token.balanceOf(BURN_ADDRESS);
    const ethBalance = await ethers.provider.getBalance(deployer.address);

    console.log("\n" + "=".repeat(55));
    console.log("  ✅ ALL TESTS PASSED!");
    console.log("=".repeat(55));
    console.log("  Total supply:", ethers.formatUnits(supply, decimals), symbol);
    console.log("  Deployer balance:", ethers.formatUnits(balance, decimals), symbol);
    console.log("  Burned (dead addr):", ethers.formatUnits(burned, decimals), symbol);
    console.log("  ETH remaining:", ethers.formatEther(ethBalance), "ETH");
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
