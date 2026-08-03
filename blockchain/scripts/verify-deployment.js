import hre from "hardhat";

const connection = await hre.network.getOrCreate();
const { ethers } = connection;

async function main() {
    const TOKEN = "0x55d7e7d006938A15082752225ED44Fd130B87735";
    const TGE = "0xb6C049D47A2FaE5413c331760C22E715D0bF4d45";

    const token = await ethers.getContractAt("DiasporaToken", TOKEN);
    const tge = await ethers.getContractAt("DiasporaTGEController", TGE);

    console.log("=".repeat(55));
    console.log("  Verification — New $DIASPORA Contracts");
    console.log("=".repeat(55));
    console.log("Token:", TOKEN);
    console.log("Name:", await token.name());
    console.log("Symbol:", await token.symbol());
    console.log("Total Supply:", ethers.formatEther(await token.totalSupply()), "DIASPORA");
    console.log("Hard Cap:", ethers.formatEther(await token.HARD_CAP()), "DIASPORA");

    console.log("\nTGEController:", TGE);
    const stats = await tge.getStats();
    console.log("Epoch:", stats[0].toString());
    console.log("TDE:", stats[1].toString());
    console.log("Total Minted:", ethers.formatEther(stats[2]), "DIASPORA");
    console.log("Total Distributed:", ethers.formatEther(stats[3]), "DIASPORA");
    console.log("Total Burned:", ethers.formatEther(stats[4]), "DIASPORA");
    console.log("TGE Count:", stats[5].toString());
    console.log("Locked Balance:", ethers.formatEther(await tge.getLockedBalance()), "DIASPORA");

    const [deployer] = await ethers.getSigners();
    const balance = await ethers.provider.getBalance(deployer.address);
    console.log("\nDeployer:", deployer.address);
    console.log("ETH Balance:", ethers.formatEther(balance), "ETH");
}

main().catch(console.error);
