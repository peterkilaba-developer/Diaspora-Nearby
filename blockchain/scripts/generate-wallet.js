/**
 * Generate a new deployer wallet for Base Mainnet.
 * 
 * IMPORTANT: Save the private key securely (password manager, NOT git).
 * This wallet will be the admin/owner of all deployed contracts.
 * 
 * Usage: node scripts/generate-wallet.js
 */
const { ethers } = require("ethers");

const wallet = ethers.Wallet.createRandom();

console.log("=".repeat(60));
console.log("  🔑 NEW DEPLOYER WALLET GENERATED");
console.log("=".repeat(60));
console.log("");
console.log("  Address:     ", wallet.address);
console.log("  Private Key: ", wallet.privateKey);
console.log("  Mnemonic:    ", wallet.mnemonic.phrase);
console.log("");
console.log("=".repeat(60));
console.log("  ⚠️  SAVE THESE SECURELY — YOU WILL NEED THEM");
console.log("=".repeat(60));
console.log("");
console.log("Next steps:");
console.log("  1. Save the private key in your password manager");
console.log("  2. Send at least 0.05 ETH to the address above on Base Mainnet");
console.log("  3. Update blockchain/.env with: PRIVATE_KEY=<your private key without 0x>");
console.log("  4. Run the deployment script");
console.log("");
console.log("To fund this wallet:");
console.log("  - Coinbase: Withdraw ETH → Base network → paste address above");
console.log("  - Bridge:   bridge.base.org → send from Ethereum L1");
console.log("  - MetaMask: Add Base network, send ETH to address above");
