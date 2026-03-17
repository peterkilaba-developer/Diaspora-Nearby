const { ethers } = require("hardhat");

async function main() {
    const [deployer] = await ethers.getSigners();
    const TOKEN_ADDRESS = "0x453f81D3a4Bb142AE34C53798BE35e7600D1b25c";
    const TGE_ADDRESS = "0xa3F092357655C0Bc5fb2Ba4B61f25c5422F59FED";
    const BURN_ADDRESS = "0x000000000000000000000000000000000000dEaD";

    const token = await ethers.getContractAt("DiasporaToken", TOKEN_ADDRESS);

    const totalSupply = await token.totalSupply();
    const deployerBal = await token.balanceOf(deployer.address);
    const tgeBal = await token.balanceOf(TGE_ADDRESS);
    const deadBal = await token.balanceOf(BURN_ADDRESS);

    console.log("=".repeat(50));
    console.log("  $DIASPORA — Current State");
    console.log("=".repeat(50));
    console.log(`Total Supply:     ${ethers.formatUnits(totalSupply, 18)}`);
    console.log(`Deployer:         ${ethers.formatUnits(deployerBal, 18)}`);
    console.log(`TGEController:    ${ethers.formatUnits(tgeBal, 18)}`);
    console.log(`Dead Address:     ${ethers.formatUnits(deadBal, 18)}`);
    console.log(`Accounted:        ${ethers.formatUnits(deployerBal + tgeBal + deadBal, 18)}`);
    console.log(`Unaccounted:      ${ethers.formatUnits(totalSupply - deployerBal - tgeBal - deadBal, 18)}`);
}

main().catch(console.error);
