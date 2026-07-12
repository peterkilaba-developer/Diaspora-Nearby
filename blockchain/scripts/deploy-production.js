import hre from "hardhat";
import { upgrades as createUpgrades } from "@openzeppelin/hardhat-upgrades";

const connection = await hre.network.getOrCreate();
const { ethers } = connection;
const upgrades = await createUpgrades(hre, connection);

/**
 * Fresh production deployment of $DIASPORA on Base Mainnet.
 * Deploys DiasporaToken + TGEController with clean state.
 *
 * Usage: npx hardhat run scripts/deploy-production.js --network base-mainnet
 */
async function main() {
    const [deployer] = await ethers.getSigners();
    const balance = await ethers.provider.getBalance(deployer.address);
    const network = await ethers.provider.getNetwork();

    console.log("=".repeat(60));
    console.log("  $DIASPORA — Fresh Production Deployment");
    console.log("=".repeat(60));
    console.log("Deployer:", deployer.address);
    console.log("Balance:", ethers.formatEther(balance), "ETH");
    console.log("Network:", network.chainId === 8453n ? "Base Mainnet ⚡" : `Chain ${network.chainId}`);
    console.log("-".repeat(60));

    if (balance < ethers.parseEther("0.002")) {
        console.error("❌ Insufficient balance. Need at least 0.002 ETH for gas.");
        process.exit(1);
    }

    const ADMIN_ADDRESS = deployer.address;
    const UPGRADER_ADDRESS = deployer.address;

    // ── Step 1: Deploy DiasporaToken ($DIASPORA) ────────────────────
    console.log("\n📦 Step 1/2: Deploying DiasporaToken ($DIASPORA)...");
    console.log("   Name: Diaspora | Symbol: DIASPORA | Hard Cap: 1 Quadrillion");

    const DiasporaToken = await ethers.getContractFactory("DiasporaToken");
    const token = await upgrades.deployProxy(
        DiasporaToken,
        [ADMIN_ADDRESS, deployer.address, UPGRADER_ADDRESS],
        { kind: "uups" }
    );
    await token.waitForDeployment();
    const tokenAddress = await token.getAddress();
    console.log("   ✅ DiasporaToken:", tokenAddress);

    // Verify token details
    try {
        const name = await token.name();
        const symbol = await token.symbol();
        const decimals = await token.decimals();
        console.log(`   📋 Verified: ${name} (${symbol}), ${decimals} decimals`);
    } catch (e) {
        console.log("   ⏳ Token deployed (verification will be available shortly)");
    }

    // ── Step 2: Deploy TGEController ────────────────────────────────
    console.log("\n📦 Step 2/2: Deploying DiasporaTGEController...");
    console.log("   Pre-minted epoch supply model (mint → lock → distribute)");

    const DiasporaTGEController = await ethers.getContractFactory("DiasporaTGEController");
    const tgeController = await upgrades.deployProxy(
        DiasporaTGEController,
        [ADMIN_ADDRESS, UPGRADER_ADDRESS, tokenAddress],
        { kind: "uups" }
    );
    await tgeController.waitForDeployment();
    const tgeAddress = await tgeController.getAddress();
    console.log("   ✅ DiasporaTGEController:", tgeAddress);

    // ── Step 3: Configure Roles ──────────────────────────────────────
    console.log("\n🔗 Configuring Roles...");

    // TGEController needs MINTER_ROLE to pre-mint epoch supply
    const MINTER_ROLE = await token.MINTER_ROLE();
    console.log("   Granting MINTER_ROLE to TGEController...");
    await token.grantRole(MINTER_ROLE, tgeAddress);
    console.log("   ✅ TGEController can now mint $DIASPORA");

    // ── Summary ──────────────────────────────────────────────────────
    const finalBalance = await ethers.provider.getBalance(deployer.address);
    const gasUsed = balance - finalBalance;

    // Verify initial state
    const stats = await tgeController.getStats();

    console.log("\n" + "=".repeat(60));
    console.log("  ✅ DEPLOYMENT COMPLETE — Fresh $DIASPORA on Base!");
    console.log("=".repeat(60));
    console.log("\n📋 Contract Addresses:\n");
    console.log("  DIASPORA_TOKEN=" + tokenAddress);
    console.log("  TGE_CONTROLLER=" + tgeAddress);
    console.log("\n📊 Initial State:");
    console.log("  Epoch:", stats[0].toString());
    console.log("  TGE Event:", stats[1].toString());
    console.log("  Total Minted:", ethers.formatUnits(stats[2], 18), "DIASPORA");
    console.log("  Total Supply:", ethers.formatUnits(await token.totalSupply(), 18), "DIASPORA");
    console.log("\n⛽ Gas used:", ethers.formatEther(gasUsed), "ETH");
    console.log("💰 Remaining:", ethers.formatEther(finalBalance), "ETH");
    console.log("\n📝 Update functions/.env with:");
    console.log("  TOKEN_ADDRESS=" + tokenAddress);
    console.log("  TGE_CONTROLLER_ADDRESS=" + tgeAddress);
    console.log('\n🔒 Next step: Run mint-epoch-supply.js to pre-mint Epoch 1 (1,000,000 $DIASPORA)');
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
