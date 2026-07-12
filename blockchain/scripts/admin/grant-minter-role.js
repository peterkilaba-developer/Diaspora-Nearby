import hre from "hardhat";

const connection = await hre.network.getOrCreate();
const { ethers } = connection;

/**
 * Grant MINTER_ROLE on DiasporaToken to the TGE Controller.
 * Usage: npx hardhat run scripts/grant-minter-role.js --network base-mainnet
 */
async function main() {
    const TOKEN_ADDRESS = "0x55d7e7d006938A15082752225ED44Fd130B87735";
    const TGE_ADDRESS = "0xb6C049D47A2FaE5413c331760C22E715D0bF4d45";

    const [deployer] = await ethers.getSigners();
    console.log("Deployer:", deployer.address);

    const token = await ethers.getContractAt("DiasporaToken", TOKEN_ADDRESS);
    const MINTER_ROLE = await token.MINTER_ROLE();
    
    // Check if already granted
    const hasRole = await token.hasRole(MINTER_ROLE, TGE_ADDRESS);
    if (hasRole) {
        console.log("✅ TGEController already has MINTER_ROLE — skipping");
        return;
    }

    console.log("Granting MINTER_ROLE to TGEController...");
    const tx = await token.grantRole(MINTER_ROLE, TGE_ADDRESS);
    const receipt = await tx.wait();
    console.log("✅ Done! TX:", receipt.hash);
}

main().catch((e) => { console.error(e); process.exitCode = 1; });
