const { ethers } = require("ethers");
require("dotenv").config();

const timestamp = process.argv[2];
if (!timestamp) {
    console.error("Usage: node scripts/quick-sign.js <timestamp>");
    console.error("Example: node scripts/quick-sign.js \"23:14:49\"");
    process.exit(1);
}

const message = `[basescan.org 15/03/2026 ${timestamp}] I, hereby verify that I am the owner/creator of the address [0x453f81D3a4Bb142AE34C53798BE35e7600D1b25c]`;

async function main() {
    const wallet = new ethers.Wallet(process.env.PRIVATE_KEY);
    const signature = await wallet.signMessage(message);
    console.log(`\nMessage: ${message}`);
    console.log(`\nAddress: ${wallet.address}`);
    console.log(`\nSignature:\n${signature}`);
}

main().catch(console.error);
