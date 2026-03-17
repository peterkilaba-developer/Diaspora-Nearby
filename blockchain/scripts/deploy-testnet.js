const { ethers, upgrades } = require("hardhat");

/**
 * Deploy test token + TGE controller to Sepolia for testing transfers.
 * This is a test copy — the real token is on Base Mainnet.
 */
async function main() {
    const [deployer] = await ethers.getSigners();
    const balance = await ethers.provider.getBalance(deployer.address);

    console.log("=".repeat(50));
    console.log("  $DIASPORA Testnet Deployment (Sepolia)");
    console.log("=".repeat(50));
    console.log("Deployer:", deployer.address);
    console.log("Balance:", ethers.formatEther(balance), "ETH");

    // Deploy Token
    console.log("\n📦 Deploying test DiasporaToken...");
    const DiasporaToken = await ethers.getContractFactory("DiasporaToken");
    const token = await upgrades.deployProxy(
        DiasporaToken,
        [deployer.address, deployer.address, deployer.address],
        { kind: "uups" }
    );
    await token.waitForDeployment();
    const tokenAddress = await token.getAddress();
    console.log("  ✅ Token:", tokenAddress);

    // Deploy TGE Controller
    console.log("\n📦 Deploying test TGEController...");
    const DiasporaTGEController = await ethers.getContractFactory("DiasporaTGEController");
    const tge = await upgrades.deployProxy(
        DiasporaTGEController,
        [deployer.address, deployer.address, tokenAddress],
        { kind: "uups" }
    );
    await tge.waitForDeployment();
    const tgeAddress = await tge.getAddress();
    console.log("  ✅ TGEController:", tgeAddress);

    // Grant MINTER_ROLE to TGEController
    const MINTER_ROLE = await token.MINTER_ROLE();
    await token.grantRole(MINTER_ROLE, tgeAddress);
    console.log("  ✅ MINTER_ROLE granted to TGEController");

    const finalBalance = await ethers.provider.getBalance(deployer.address);
    console.log("\n✅ Testnet deployment complete!");
    console.log("Gas used:", ethers.formatEther(balance - finalBalance), "ETH");
    console.log("\nSave these for testing:");
    console.log("  TEST_TOKEN_ADDRESS=" + tokenAddress);
    console.log("  TEST_TGE_CONTROLLER=" + tgeAddress);
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
