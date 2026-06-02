const { ethers, upgrades } = require("hardhat");

/**
 * Deploy ONLY the TGE Controller (Token already deployed).
 * Usage: npx hardhat run scripts/deploy-tge-only.js --network base-mainnet
 */
async function main() {
    const [deployer] = await ethers.getSigners();
    const balance = await ethers.provider.getBalance(deployer.address);

    const TOKEN_ADDRESS = "0x55d7e7d006938A15082752225ED44Fd130B87735";

    console.log("=".repeat(60));
    console.log("  $DIASPORA — Deploy TGE Controller (Token already deployed)");
    console.log("=".repeat(60));
    console.log("Deployer:", deployer.address);
    console.log("Balance:", ethers.formatEther(balance), "ETH");
    console.log("Token:", TOKEN_ADDRESS);
    console.log("-".repeat(60));

    const ADMIN_ADDRESS = deployer.address;
    const UPGRADER_ADDRESS = deployer.address;

    // Deploy TGEController
    console.log("\n📦 Deploying DiasporaTGEController...");
    const DiasporaTGEController = await ethers.getContractFactory("DiasporaTGEController");
    const tgeController = await upgrades.deployProxy(
        DiasporaTGEController,
        [ADMIN_ADDRESS, UPGRADER_ADDRESS, TOKEN_ADDRESS],
        { kind: "uups" }
    );
    await tgeController.waitForDeployment();
    const tgeAddress = await tgeController.getAddress();
    console.log("   ✅ DiasporaTGEController:", tgeAddress);

    // Grant MINTER_ROLE to TGEController
    console.log("\n🔗 Granting MINTER_ROLE to TGEController...");
    const token = await ethers.getContractAt("DiasporaToken", TOKEN_ADDRESS);
    const MINTER_ROLE = await token.MINTER_ROLE();
    const tx = await token.grantRole(MINTER_ROLE, tgeAddress);
    await tx.wait();
    console.log("   ✅ TGEController can now mint $DIASPORA");

    // Summary
    const finalBalance = await ethers.provider.getBalance(deployer.address);
    console.log("\n" + "=".repeat(60));
    console.log("  ✅ TGE CONTROLLER DEPLOYED!");
    console.log("=".repeat(60));
    console.log("\n  TOKEN_ADDRESS=" + TOKEN_ADDRESS);
    console.log("  TGE_CONTROLLER_ADDRESS=" + tgeAddress);
    console.log("\n⛽ Gas used:", ethers.formatEther(balance - finalBalance), "ETH");
    console.log("💰 Remaining:", ethers.formatEther(finalBalance), "ETH");
    console.log('\n🔒 Next: Run mint-epoch-supply.js to pre-mint Epoch 1');
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
