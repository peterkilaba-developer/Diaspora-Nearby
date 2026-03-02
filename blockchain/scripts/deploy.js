const { ethers, upgrades } = require("hardhat");

async function main() {
    const [deployer] = await ethers.getSigners();
    console.log("Starting deployment with account:", deployer.address);

    // Configuration - In production, use real Gnosis Safe addresses
    const ADMIN_ADDRESS = process.env.ADMIN_ADDRESS || deployer.address;
    const UPGRADER_ADDRESS = process.env.UPGRADER_ADDRESS || deployer.address;
    const FOUNDERS_VAULT = process.env.FOUNDERS_VAULT || "0x1111111111111111111111111111111111111111";
    const INVESTORS_VAULT = process.env.INVESTORS_VAULT || "0x2222222222222222222222222222222222222222";

    console.log("--- Deploying Contracts ---");

    // 1. Deploy DiasporaToken
    const DiasporaToken = await ethers.getContractFactory("DiasporaToken");
    const token = await upgrades.deployProxy(DiasporaToken, [ADMIN_ADDRESS, deployer.address, UPGRADER_ADDRESS], { kind: "uups" });
    await token.waitForDeployment();
    const tokenAddress = await token.getAddress();
    console.log("DiasporaToken Proxy:", tokenAddress);

    // 2. Deploy DiasporaRegistry
    const DiasporaRegistry = await ethers.getContractFactory("DiasporaRegistry");
    const registry = await upgrades.deployProxy(DiasporaRegistry, [ADMIN_ADDRESS, UPGRADER_ADDRESS], { kind: "uups" });
    await registry.waitForDeployment();
    const registryAddress = await registry.getAddress();
    console.log("DiasporaRegistry Proxy:", registryAddress);

    // 3. Deploy DiasporaTGEController
    const DiasporaTGEController = await ethers.getContractFactory("DiasporaTGEController");
    const tgeController = await upgrades.deployProxy(DiasporaTGEController, [ADMIN_ADDRESS, UPGRADER_ADDRESS, tokenAddress], { kind: "uups" });
    await tgeController.waitForDeployment();
    const tgeAddress = await tgeController.getAddress();
    console.log("DiasporaTGEController Proxy:", tgeAddress);

    // 4. Deploy DiasporaAllocationHub
    const DiasporaAllocationHub = await ethers.getContractFactory("DiasporaAllocationHub");
    const allocationHub = await upgrades.deployProxy(DiasporaAllocationHub, [
        ADMIN_ADDRESS,
        UPGRADER_ADDRESS,
        tokenAddress,
        registryAddress,
        tgeAddress,
        FOUNDERS_VAULT,
        INVESTORS_VAULT
    ], { kind: "uups" });
    await allocationHub.waitForDeployment();
    const hubAddress = await allocationHub.getAddress();
    console.log("DiasporaAllocationHub Proxy:", hubAddress);

    // 5. Deploy DiasporaExpansionEngine
    const DiasporaExpansionEngine = await ethers.getContractFactory("DiasporaExpansionEngine");
    const engine = await upgrades.deployProxy(DiasporaExpansionEngine, [
        ADMIN_ADDRESS,
        UPGRADER_ADDRESS,
        tgeAddress,
        hubAddress
    ], { kind: "uups" });
    await engine.waitForDeployment();
    const engineAddress = await engine.getAddress();
    console.log("DiasporaExpansionEngine Proxy:", engineAddress);

    console.log("\n--- Post-Deployment Configuration ---");

    // Connect Roles
    const MINTER_ROLE = await token.MINTER_ROLE();
    const ENGINE_ROLE = await tgeController.ENGINE_ROLE();
    const DISTRIBUTOR_ROLE = await allocationHub.DISTRIBUTOR_ROLE();

    console.log("Granting MINTER_ROLE to TGEController and AllocationHub...");
    await token.grantRole(MINTER_ROLE, tgeAddress);
    await token.grantRole(MINTER_ROLE, hubAddress);

    console.log("Granting ENGINE_ROLE to ExpansionEngine...");
    await tgeController.grantRole(ENGINE_ROLE, engineAddress);

    console.log("Granting DISTRIBUTOR_ROLE to ExpansionEngine...");
    await allocationHub.grantRole(DISTRIBUTOR_ROLE, engineAddress);

    console.log("\nDeployment and role configuration complete!");
    console.log("Token:", tokenAddress);
    console.log("Registry:", registryAddress);
    console.log("TGE Controller:", tgeAddress);
    console.log("Allocation Hub:", hubAddress);
    console.log("Expansion Engine:", engineAddress);
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
