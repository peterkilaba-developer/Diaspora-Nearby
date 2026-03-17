const { ethers } = require("ethers");
require("dotenv").config();

const message = `[basescan.org 08/03/2026 23:14:49] I, hereby verify that I am the owner/creator of the address [0x453f81D3a4Bb142AE34C53798BE35e7600D1b25c]`;

async function main() {
    const wallet = new ethers.Wallet(process.env.PRIVATE_KEY);
    const signature = await wallet.signMessage(message);
    // Write to file for clean output
    require("fs").writeFileSync("signature-output.txt",
        `Address: ${wallet.address}\nSignature: ${signature}\n`
    );
    console.log("Signature written to signature-output.txt");
}

main().catch(console.error);
