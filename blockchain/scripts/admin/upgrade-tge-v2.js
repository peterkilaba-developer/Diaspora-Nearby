/**
 * Upgrade the live TGEController proxy from V1 to V2.
 *
 * NOTE: This file replaces the original V1→intermediate upgrade script. The
 * current live contract already has `distributeWelcomeBonus`. This script
 * now drives the V1 → V2 upgrade that adds the welcome-bonus cap, per-user
 * dedupe, Merkle commitments, and reconciliation view — see
 * blockchain/IMPROVEMENTS.md for context.
 *
 * Prerequisites:
 *   1. Safe (`0xE06F8690e96a8BAAbCBe48664Ff1238F69082244`) holds UPGRADER_ROLE
 *      on the live TGE controller. (Already true as of 2026-06-01.)
 *   2. `functions/lib/dsp.js` is already staged for the V2 signature.
 *      Run `firebase deploy --only functions` within minutes of the on-chain
 *      upgrade to keep backend and contract in sync.
 *
 * IMPORTANT: this script PREPARES the upgrade. It does NOT submit the
 * transaction — the upgrade has to be initiated by the UPGRADER_ROLE holder
 * (the Safe), not the deployer EOA. The script:
 *   1. Validates storage-layout compatibility (will refuse if it's not safe).
 *   2. Deploys the new V2 implementation contract (paid from deployer EOA, ~$0.20).
 *   3. Prints the calldata the Safe needs to execute against the proxy.
 *
 * Then in the Safe UI:
 *   - Apps → Transaction Builder → New transaction
 *   - To:    0xb6C049D47A2FaE5413c331760C22E715D0bF4d45
 *   - Value: 0
 *   - Data:  <calldata from this script>
 *   - 2 of 3 signers approve and execute.
 *
 * Finally:
 *   cd functions && firebase deploy --only functions
 *
 * Usage:
 *   npx hardhat run scripts/admin/upgrade-tge-v2.js --network base-mainnet
 */
const { ethers, upgrades } = require("hardhat");

const TGE_PROXY = "0xb6C049D47A2FaE5413c331760C22E715D0bF4d45";
const WELCOME_CAP = ethers.parseUnits("1000", 18); // 1000 DIASPORA per user (matches landing-page tokenomics)

async function main() {
  const network = await ethers.provider.getNetwork();
  if (network.chainId !== 8453n) {
    console.error(`❌ Wrong network. Expected Base Mainnet (8453), got ${network.chainId}.`);
    process.exit(1);
  }

  console.log("=".repeat(60));
  console.log("  Prepare TGEController V2 upgrade");
  console.log("=".repeat(60));
  console.log("  Proxy:       ", TGE_PROXY);
  console.log("  Welcome cap: ", ethers.formatUnits(WELCOME_CAP, 18), "DIASPORA");

  const V2 = await ethers.getContractFactory("DiasporaTGEControllerV2");

  console.log("\n→ Validating storage layout compatibility...");
  await upgrades.validateUpgrade(TGE_PROXY, V2, { kind: "uups" });
  console.log("  ✅ Layout compatible");

  console.log("\n→ Deploying new V2 implementation...");
  const v2Impl = await upgrades.prepareUpgrade(TGE_PROXY, V2, { kind: "uups" });
  console.log("  ✅ New impl deployed at:", v2Impl);

  // Build the calldata: upgradeToAndCall(newImpl, initializeV2(WELCOME_CAP))
  const initData = V2.interface.encodeFunctionData("initializeV2", [WELCOME_CAP]);
  const upgradeCalldata = V2.interface.encodeFunctionData("upgradeToAndCall", [v2Impl, initData]);

  console.log("\n" + "=".repeat(60));
  console.log("  📋 SAFE TRANSACTION TO EXECUTE");
  console.log("=".repeat(60));
  console.log("\n  To:    ", TGE_PROXY);
  console.log("  Value: 0");
  console.log("  Data:  ", upgradeCalldata);
  console.log("\n  Use https://app.safe.global → Apps → Transaction Builder.");
  console.log("  Collect 2 of 3 signatures, then execute.");

  console.log("\n" + "=".repeat(60));
  console.log("  📋 IMMEDIATELY AFTER THE ON-CHAIN UPGRADE LANDS");
  console.log("=".repeat(60));
  console.log("\n    cd ../functions && firebase deploy --only functions");
  console.log("");
  console.log("  This pushes the dsp.js update that matches the V2 distributeWelcomeBonus");
  console.log("  signature. Until both land, new signups will fail to receive their");
  console.log("  on-chain $DIASPORA welcome bonus (DSP off-chain points still work).");

  console.log("\n  Verification after upgrade:");
  console.log("    node -e \"const{ethers}=require('ethers');const p=new ethers.JsonRpcProvider('https://mainnet.base.org');");
  console.log("      const c=new ethers.Contract('" + TGE_PROXY + "',");
  console.log("        ['function maxWelcomeBonusPerRecipient() view returns (uint256)'],p);");
  console.log("      c.maxWelcomeBonusPerRecipient().then(v=>console.log('cap:',ethers.formatUnits(v,18),'DIASPORA'))\"");
}

main().catch((e) => {
  console.error(e);
  process.exitCode = 1;
});
