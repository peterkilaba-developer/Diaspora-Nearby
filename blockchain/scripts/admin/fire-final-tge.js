import hre from "hardhat";

const connection = await hre.network.getOrCreate();
const { ethers } = connection;

async function main() {
    const [deployer] = await ethers.getSigners();
    // Production contract (1M $DIASPORA — Epoch 1)
    const tge = await ethers.getContractAt("DiasporaTGEController", "0xa3F092357655C0Bc5fb2Ba4B61f25c5422F59FED");

    let stats = await tge.getStats();
    console.log(`Before: Epoch ${stats[0]}, Event ${stats[1]}, TGE count: ${stats[5]}`);

    console.log("Firing TGE #10 (final event of Epoch 1)...");
    const tx = await tge.executeTGE(
        [deployer.address],
        [ethers.parseUnits("10", 18)],
        [90]
    );
    await tx.wait();

    stats = await tge.getStats();
    console.log(`After:  Epoch ${stats[0]}, Event ${stats[1]}, TGE count: ${stats[5]}`);

    if (Number(stats[0]) === 2) {
        console.log("\n🎉 EPOCH 1 COMPLETE → Now in Epoch 2!");
    }
}

main().catch(console.error);
