/**
 * Force-import live production proxies into .openzeppelin/base.json.
 *
 * Why: the live token, live TGE, and wallet factory were deployed outside this
 * workspace (or before the manifest was tracked), so the OpenZeppelin upgrades
 * plugin doesn't know about them. Future `upgrades.upgradeProxy()` calls will
 * fail with "deployment not found" until we register them.
 *
 * Safe / idempotent: forceImport only reads on-chain state and writes to the
 * local manifest file. No transactions sent.
 *
 * Usage:
 *   npx hardhat run scripts/admin/force-import.js --network base-mainnet
 */
import hre from "hardhat";
import { upgrades as createUpgrades } from "@openzeppelin/hardhat-upgrades";

const connection = await hre.network.getOrCreate();
const { ethers } = connection;
const upgrades = await createUpgrades(hre, connection);

const LIVE_TOKEN = "0x55d7e7d006938A15082752225ED44Fd130B87735";
const LIVE_TGE = "0xb6C049D47A2FaE5413c331760C22E715D0bF4d45";

async function main() {
  console.log("=".repeat(60));
  console.log("  Force-import live proxies into OZ manifest");
  console.log("=".repeat(60));

  console.log("\n→ DiasporaToken proxy:", LIVE_TOKEN);
  const Token = await ethers.getContractFactory("DiasporaToken");
  await upgrades.forceImport(LIVE_TOKEN, Token, { kind: "uups" });
  console.log("  ✅ imported");

  console.log("\n→ DiasporaTGEController proxy:", LIVE_TGE);
  const TGE = await ethers.getContractFactory("DiasporaTGEController");
  await upgrades.forceImport(LIVE_TGE, TGE, { kind: "uups" });
  console.log("  ✅ imported");

  console.log("\n✅ Manifest updated: .openzeppelin/base.json now tracks production proxies.");
  console.log("   Commit the updated file.");
}

main().catch((e) => {
  console.error(e);
  process.exitCode = 1;
});
