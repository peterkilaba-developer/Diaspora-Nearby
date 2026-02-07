const hre = require("hardhat");

async function main() {
    console.log("Deploying Diaspora Token...");

    // In production, these should be the addresses of your Gnosis Safe Multi-sigs
    const ADMIN_ADDRESS = process.env.ADMIN_ADDRESS || "0x0000000000000000000000000000000000000000";
    const MINTER_ADDRESS = process.env.MINTER_ADDRESS || "0x0000000000000000000000000000000000000000";

    const DiasporaToken = await hre.ethers.getContractFactory("DiasporaToken");
    const token = await DiasporaToken.deploy(ADMIN_ADDRESS, MINTER_ADDRESS);

    await token.waitForDeployment();

    console.log(`Diaspora Token deployed to: ${await token.getAddress()}`);
    console.log(`Admin set to: ${ADMIN_ADDRESS}`);
    console.log(`Minter set to: ${MINTER_ADDRESS}`);
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
