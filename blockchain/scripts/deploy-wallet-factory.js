const { ethers } = require("hardhat");

async function main() {
    const [deployer] = await ethers.getSigners();
    console.log("Deployer:", deployer.address);

    const balance = await ethers.provider.getBalance(deployer.address);
    console.log("Balance:", ethers.formatEther(balance), "ETH");

    const ADMIN = process.env.ADMIN_ADDRESS || deployer.address;
    const SIGNER = process.env.BACKEND_SIGNER || deployer.address;

    console.log("Admin:", ADMIN);
    console.log("Backend Signer:", SIGNER);
    console.log("\nDeploying DiasporaWalletFactory...");

    const Factory = await ethers.getContractFactory("DiasporaWalletFactory");
    const factory = await Factory.deploy(ADMIN, SIGNER);
    await factory.waitForDeployment();
    const addr = await factory.getAddress();

    console.log("\n=== DEPLOYED ===");
    console.log("WalletFactory:", addr);
    console.log("Verify: npx hardhat verify --network base-sepolia " + addr + " " + ADMIN + " " + SIGNER);
}

main().catch((e) => { console.error(e); process.exitCode = 1; });
