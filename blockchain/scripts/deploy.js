import hre from "hardhat";
import { upgrades as createUpgrades } from "@openzeppelin/hardhat-upgrades";

const connection = await hre.network.getOrCreate();
const { ethers } = connection;
const upgrades = await createUpgrades(hre, connection);

async function main() {
    const [deployer] = await ethers.getSigners();
    const balance = await ethers.provider.getBalance(deployer.address);

    console.log("=".repeat(60));
    console.log("  $DIASPORA — Diaspora Token Deployment");
    console.log("=".repeat(60));
    console.log("Deployer:", deployer.address);
    console.log("Balance:", ethers.formatEther(balance), "ETH");
    console.log("Network:", (await ethers.provider.getNetwork()).chainId === 8453n ? "Base Mainnet ⚡" : (await ethers.provider.getNetwork()).name);
    console.log("-".repeat(60));

    if (balance < ethers.parseEther("0.001")) {
        console.error("❌ Insufficient balance. Need at least 0.001 ETH for gas.");
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

    // TGEController needs MINTER_ROLE to mint tokens at TGE events
    const MINTER_ROLE = await token.MINTER_ROLE();
    console.log("   Granting MINTER_ROLE to TGEController...");
    await token.grantRole(MINTER_ROLE, tgeAddress);
    console.log("   ✅ TGEController can now mint $DIASPORA");

    // ── Summary ──────────────────────────────────────────────────────
    const finalBalance = await ethers.provider.getBalance(deployer.address);
    const gasUsed = balance - finalBalance;

    console.log("\n" + "=".repeat(60));
    console.log("  ✅ DEPLOYMENT COMPLETE — $DIASPORA is live on Base!");
    console.log("=".repeat(60));
    console.log("\n📋 Contract Addresses:\n");
    console.log("  DIASPORA_TOKEN=" + tokenAddress);
    console.log("  TGE_CONTROLLER=" + tgeAddress);
    console.log("\n⛽ Gas used:", ethers.formatEther(gasUsed), "ETH");
    console.log("💰 Remaining:", ethers.formatEther(finalBalance), "ETH");
    console.log("\n📝 Add to functions/.env:");
    console.log("  TOKEN_ADDRESS=" + tokenAddress);
    console.log("  TGE_CONTROLLER_ADDRESS=" + tgeAddress);
    console.log("\n🏗️ Architecture:");
    console.log("  • DiasporaToken — ERC-20 with 1QD hard cap, UUPS upgradeable");
    console.log("  • TGEController — Snapshot-based TGE, mints/distributes/burns");
    console.log("  • WalletFactory — Deploy separately to this network");
    console.log("  • All DSP logic — Off-chain in Firestore + Cloud Functions");
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
