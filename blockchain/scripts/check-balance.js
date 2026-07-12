import hre from "hardhat";

const connection = await hre.network.getOrCreate();
const { ethers } = connection;

async function main() {
    const [deployer] = await ethers.getSigners();
    console.log("Checking address:", deployer.address);

    // Check Base Mainnet
    const baseMainnet = new ethers.JsonRpcProvider("https://mainnet.base.org");
    const bal = await baseMainnet.getBalance(deployer.address);
    console.log("Base Mainnet:", ethers.formatEther(bal), "ETH");

    if (bal >= ethers.parseEther("0.001")) {
        console.log("✅ Sufficient for deployment (~2 proxies + role config)");
    } else {
        console.log("❌ Need at least 0.001 ETH");
    }
}

main().catch(console.error);
