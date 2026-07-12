/**
 * Check whether the old "burn" smart wallets (CREATE2 from either salt scheme)
 * have any $DIASPORA balance left over from before the 2026-06-04 burn fix.
 *
 * Context: prior to 2026-06-04, ensureSystemWallets created a controllable
 * smart wallet for the burn slot using `treasury:burn` (or earlier
 * `system:burn_treasury`). Per-tribute burns already targeted 0x…dEaD
 * directly, but the burn smart wallet may have received funds from earlier
 * misconfigurations, manual sends, or older code paths. After the fix,
 * nothing new should land in those wallets — but anything sitting there is
 * still movable by the backend signer.
 *
 * This script is READ-ONLY. It checks both candidate burn-wallet addresses
 * and reports balances. If any have a non-zero balance, run the migration
 * script with destination = 0x…dEaD to retire them.
 *
 * Usage:
 *   npx hardhat run scripts/admin/check-burn-wallet-residue.js --network base-mainnet
 *
 * If a residue is found, sweep it with:
 *   SLOT=founders \   # any allowed slot — script doesn't update Firestore for burn
 *   SAFE_ADDRESS=0x000000000000000000000000000000000000dEaD \
 *   OLD_TREASURY_ADDRESS=0x<the burn smart wallet> \
 *   DRY_RUN=1 \
 *     npx hardhat run scripts/admin/migrate-treasury-balance-to-safe.js --network base-mainnet
 *
 *   ↑ Note: the migrate script's slot validation will reject this — that's
 *   intentional. For a burn-residue sweep, use a one-off `transferToken`
 *   call instead (see manual instructions printed by this script).
 */
import hre from "hardhat";

const connection = await hre.network.getOrCreate();
const { ethers } = connection;

const TOKEN_ADDRESS = "0x55d7e7d006938A15082752225ED44Fd130B87735";
const FACTORY_ADDRESS = "0x9cF797cf332595c00410fc4ee9FdEe5C59501945";
const BURN_DEAD = "0x000000000000000000000000000000000000dEaD";

// Both salt schemes seen historically in the codebase.
const CANDIDATE_SALTS = [
  "treasury:burn",
  "system:burn_treasury",
];

async function main() {
  const [signer] = await ethers.getSigners();
  const network = await ethers.provider.getNetwork();
  if (network.chainId !== 8453n) {
    console.error(`❌ Wrong network. Expected Base Mainnet (8453), got ${network.chainId}.`);
    process.exit(1);
  }

  console.log("=".repeat(64));
  console.log("  Burn smart-wallet residue check");
  console.log("=".repeat(64));
  console.log(`  Signer (backend):  ${signer.address}`);
  console.log(`  Token:             ${TOKEN_ADDRESS}`);
  console.log(`  Factory:           ${FACTORY_ADDRESS}`);

  const factory = await ethers.getContractAt("DiasporaWalletFactory", FACTORY_ADDRESS);
  const token = await ethers.getContractAt("DiasporaToken", TOKEN_ADDRESS);
  const decimals = await token.decimals();
  const fmt = (v) => ethers.formatUnits(v, decimals);

  // Also check the dead address itself, just for the report
  const deadBal = await token.balanceOf(BURN_DEAD);
  console.log(`\n📊 0x…dEaD (canonical burn): ${fmt(deadBal)} $DIASPORA  ← already irrecoverable, this is healthy`);

  let totalResidue = 0n;
  const residues = [];

  for (const salt of CANDIDATE_SALTS) {
    const saltHash = ethers.keccak256(ethers.toUtf8Bytes(salt));
    const computed = await factory.computeAddress(saltHash);
    const deployedHere = await factory.getWallet(saltHash);
    const codeAtComputed = await ethers.provider.getCode(computed);
    const bal = await token.balanceOf(computed);

    console.log(`\n🔍 salt "${salt}"`);
    console.log(`   keccak256:    ${saltHash}`);
    console.log(`   CREATE2 addr: ${computed}`);
    console.log(`   factory says: ${deployedHere === ethers.ZeroAddress ? "(not registered)" : deployedHere}`);
    console.log(`   has code:     ${codeAtComputed === "0x" ? "no — never deployed" : "yes — wallet exists"}`);
    console.log(`   balance:      ${fmt(bal)} $DIASPORA`);

    if (bal > 0n) {
      totalResidue += bal;
      residues.push({ salt, address: computed, balance: bal, deployed: codeAtComputed !== "0x" });
    }
  }

  console.log("\n" + "=".repeat(64));
  if (totalResidue === 0n) {
    console.log("  ✅ No residue. Both candidate burn wallets are empty.");
    console.log("=".repeat(64));
    return;
  }

  console.log(`  ⚠️  Found ${fmt(totalResidue)} $DIASPORA in old burn wallets.`);
  console.log("=".repeat(64));
  console.log("\n📋 To sweep each non-empty burn wallet to 0x…dEaD:\n");
  for (const r of residues) {
    if (!r.deployed) {
      console.log(`   • ${r.address}: NOT deployed on-chain — cannot call transferToken.`);
      console.log(`     If a balance shows here despite no code, that's an ERC-20 transfer to`);
      console.log(`     a CREATE2 prediction. You'd need to deploy the wallet first via`);
      console.log(`     factory.createWallet(${ethers.keccak256(ethers.toUtf8Bytes(r.salt))})`);
      console.log(`     then transferToken to 0x…dEaD. Investigate before doing this.\n`);
      continue;
    }
    console.log(`   • ${r.address} (${fmt(r.balance)} $DIASPORA):`);
    console.log(`     From hardhat console (--network base-mainnet):`);
    console.log(`       const w = await ethers.getContractAt("DiasporaSmartWallet", "${r.address}");`);
    console.log(`       await w.transferToken("${TOKEN_ADDRESS}", "${BURN_DEAD}", ${r.balance.toString()}n);\n`);
  }
}

main().catch((e) => {
  console.error(e);
  process.exitCode = 1;
});
