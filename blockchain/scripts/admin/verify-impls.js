/**
 * Source-verify the live UUPS implementation contracts on Basescan.
 *
 * Prerequisites:
 *   - Set BASESCAN_API_KEY in blockchain/.env
 *     (get one free at https://basescan.org/myapikey)
 *   - hardhat-etherscan must be configured for `base-mainnet` in hardhat.config.js
 *
 * The PROXY contracts are auto-detected by Basescan ("Source Code (Proxy)" badge),
 * but the IMPLEMENTATION contracts they delegate to are separate and need explicit
 * verification.
 *
 * Usage:
 *   npx hardhat run scripts/admin/verify-impls.js --network base-mainnet
 */
const { run, ethers } = require("hardhat");

const LIVE_TOKEN = "0x55d7e7d006938A15082752225ED44Fd130B87735";
const LIVE_TGE = "0xb6C049D47A2FaE5413c331760C22E715D0bF4d45";
const IMPL_SLOT = "0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc";

async function getImpl(proxy) {
  const raw = await ethers.provider.getStorage(proxy, IMPL_SLOT);
  return "0x" + raw.slice(-40);
}

async function verifyOnce(address, label) {
  console.log(`\n→ Verifying ${label} impl at ${address}`);
  try {
    await run("verify:verify", { address, constructorArguments: [] });
    console.log(`  ✅ ${label} verified`);
  } catch (e) {
    if (e.message.toLowerCase().includes("already verified")) {
      console.log(`  ✓ ${label} already verified`);
    } else {
      console.error(`  ❌ ${label} verification failed:`, e.message);
    }
  }
}

async function main() {
  if (!process.env.BASESCAN_API_KEY || process.env.BASESCAN_API_KEY.includes("your_")) {
    console.error("❌ BASESCAN_API_KEY is not set in blockchain/.env");
    console.error("   Get a free key at https://basescan.org/myapikey");
    process.exit(1);
  }

  const tokenImpl = await getImpl(LIVE_TOKEN);
  const tgeImpl = await getImpl(LIVE_TGE);

  console.log("=".repeat(60));
  console.log("  Basescan source verification — live implementations");
  console.log("=".repeat(60));
  console.log("  DiasporaToken impl:        ", tokenImpl);
  console.log("  DiasporaTGEController impl:", tgeImpl);

  await verifyOnce(tokenImpl, "DiasporaToken");
  await verifyOnce(tgeImpl, "DiasporaTGEController");

  console.log("\nDone.");
}

main().catch((e) => {
  console.error(e);
  process.exitCode = 1;
});
