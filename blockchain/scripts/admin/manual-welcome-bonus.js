/**
 * One-off: retroactively distribute the welcome bonus to a user whose signup
 * skipped the on-chain step due to the missing `secrets:` binding on
 * `initializeUserPoints` (fixed 2026-06-02, see commit history).
 *
 * Calls TGEControllerV2.distributeWelcomeBonus directly from the deployer EOA
 * (which still holds TGE_ORACLE_ROLE).
 *
 * Inputs to fill in below:
 *   - USER_WALLET: the user's smart-wallet address (Firestore: users/<uid>.walletAddress)
 *   - COMMUNITY_TREASURY_WALLETS: array of {communityId, fraction, walletAddress}
 *     mirroring the dsp.js distribution. Run `node -e ...` against Firestore
 *     to pull each community's walletAddress for the user's memberships.
 *
 * The treasury split per signup (per landing-page tokenomics):
 *   - User:        1,000 DIASPORA  (capped + deduped lifetime)
 *   - Burn:        100  (10%)
 *   - Founders:    100  (10%)
 *   - Liquidity:   100  (10% — code path still reads governance/investors doc)
 *   - Community:   100 per slot, up to 7 slots = 700 (70%)
 *
 * Usage:
 *   USER_WALLET=0x... npx hardhat run scripts/admin/manual-welcome-bonus.js --network base-mainnet
 *
 * Safety:
 *   - Refuses if the user already received a welcome bonus on-chain (V2 enforces
 *     this anyway via welcomeBonusReceived mapping)
 *   - Logs the transaction hash and updates expected Firestore field hints
 */
const { ethers } = require("hardhat");

const TGE = "0xb6C049D47A2FaE5413c331760C22E715D0bF4d45";
const TOKEN = "0x55d7e7d006938A15082752225ED44Fd130B87735";
const BURN = "0x000000000000000000000000000000000000dEaD";

// ── FILL IN ────────────────────────────────────────────────────────────────
const USER_WALLET = process.env.USER_WALLET || ""; // pass via env

// Treasury wallet addresses (from Firestore governance/{id}.walletAddress):
const FOUNDERS_WALLET = process.env.FOUNDERS_WALLET || ""; // governance/founders.walletAddress
const LIQUIDITY_WALLET = process.env.LIQUIDITY_WALLET || ""; // governance/investors.walletAddress (legacy doc name; semantically "Liquidity Treasury")

// Community treasury wallets mirroring the user's geographic hierarchy.
// Each entry: { id: "global_community" | "home_continent_..." | ..., fraction: 1.0 | 0.5, walletAddress: "0x..." }
// For the standard signup, you'd have ~7 entries totaling fraction-sum = 7.
// Pass as a JSON string in env COMMUNITY_TREASURIES, e.g.:
//   COMMUNITY_TREASURIES='[{"id":"global_community","fraction":1,"walletAddress":"0x..."},{"id":"home_continent_asia","fraction":1,"walletAddress":"0x..."},...]'
const COMMUNITY_TREASURIES = JSON.parse(process.env.COMMUNITY_TREASURIES || "[]");
// ───────────────────────────────────────────────────────────────────────────

const TGE_ABI = [
  "function distributeWelcomeBonus(address userRecipient, uint256 userAmount, address[] treasuryRecipients, uint256[] treasuryAmounts, bytes32 merkleRoot) external",
  "function welcomeBonusReceived(address) view returns (uint256)",
  "function maxWelcomeBonusPerRecipient() view returns (uint256)",
  "function getLockedBalance() view returns (uint256)",
];

async function main() {
  if (!ethers.isAddress(USER_WALLET)) {
    throw new Error("USER_WALLET env var must be a valid 0x address");
  }
  if (!ethers.isAddress(FOUNDERS_WALLET)) {
    throw new Error("FOUNDERS_WALLET env var must be a valid 0x address");
  }
  if (!ethers.isAddress(LIQUIDITY_WALLET)) {
    throw new Error("LIQUIDITY_WALLET env var must be a valid 0x address");
  }

  const [signer] = await ethers.getSigners();
  const network = await ethers.provider.getNetwork();
  if (network.chainId !== 8453n) {
    throw new Error(`Wrong network. Expected Base Mainnet (8453), got ${network.chainId}`);
  }

  const tge = new ethers.Contract(TGE, TGE_ABI, signer);

  // ── Pre-flight ────
  const cap = await tge.maxWelcomeBonusPerRecipient();
  const already = await tge.welcomeBonusReceived(USER_WALLET);
  const locked = await tge.getLockedBalance();
  console.log("=".repeat(60));
  console.log("  Manual welcome-bonus distribution");
  console.log("=".repeat(60));
  console.log("  TGE proxy:        ", TGE);
  console.log("  User recipient:   ", USER_WALLET);
  console.log("  Welcome cap:      ", ethers.formatUnits(cap, 18), "DIASPORA");
  console.log("  Already received: ", ethers.formatUnits(already, 18), "DIASPORA");
  console.log("  TGE locked supply:", ethers.formatUnits(locked, 18), "DIASPORA");

  if (already > 0n) {
    console.error("\n❌ User has already received a welcome bonus. Aborting to prevent double-pay.");
    process.exit(1);
  }

  const userAmount = ethers.parseUnits("1000", 18);

  // ── Build treasuries ────
  const treasuries = [
    { label: "Burn", address: BURN, amount: ethers.parseUnits("100", 18) },
    { label: "Founders", address: FOUNDERS_WALLET, amount: ethers.parseUnits("100", 18) },
    { label: "Liquidity", address: LIQUIDITY_WALLET, amount: ethers.parseUnits("100", 18) },
  ];
  for (const c of COMMUNITY_TREASURIES) {
    if (!ethers.isAddress(c.walletAddress)) {
      throw new Error(`Invalid wallet in COMMUNITY_TREASURIES for ${c.id}: ${c.walletAddress}`);
    }
    const slotAmount = ethers.parseUnits(Math.round(100 * c.fraction).toString(), 18);
    treasuries.push({ label: `Community: ${c.id}`, address: c.walletAddress, amount: slotAmount });
  }

  const treasuryRecipients = treasuries.map((t) => t.address);
  const treasuryAmounts = treasuries.map((t) => t.amount);
  const totalTreasury = treasuryAmounts.reduce((a, b) => a + b, 0n);
  const total = userAmount + totalTreasury;

  console.log("\n  Distribution:");
  console.log(`    User:           ${ethers.formatUnits(userAmount, 18)} DIASPORA → ${USER_WALLET}`);
  for (const t of treasuries) {
    console.log(`    ${t.label.padEnd(15)} ${ethers.formatUnits(t.amount, 18)} DIASPORA → ${t.address}`);
  }
  console.log(`    TOTAL:          ${ethers.formatUnits(total, 18)} DIASPORA`);

  if (locked < total) {
    console.error(`\n❌ Insufficient locked supply (${ethers.formatUnits(locked, 18)} < ${ethers.formatUnits(total, 18)})`);
    process.exit(1);
  }

  // ── Merkle commitment ────
  const merkleRoot = ethers.solidityPackedKeccak256(
    ["address", "uint256", "address[]", "uint256[]"],
    [USER_WALLET, userAmount, treasuryRecipients, treasuryAmounts]
  );
  console.log("\n  Commitment hash:", merkleRoot);

  // ── Execute ────
  console.log("\n  → Sending tx...");
  const tx = await tge.distributeWelcomeBonus(
    USER_WALLET,
    userAmount,
    treasuryRecipients,
    treasuryAmounts,
    merkleRoot
  );
  console.log("    tx hash:", tx.hash);
  const receipt = await tx.wait();
  console.log(`    ✅ Mined in block ${receipt.blockNumber} (gas ${receipt.gasUsed})`);

  console.log("\n" + "=".repeat(60));
  console.log("  ✅ Welcome bonus distributed.");
  console.log("=".repeat(60));
  console.log("\n  Next: update the user's Firestore doc:");
  console.log("    users/<uid>.tokenWelcomeBonusSent = true");
  console.log("    users/<uid>.tokenWelcomeBonusTx   = '" + tx.hash + "'");
}

main().catch((e) => {
  console.error(e);
  process.exitCode = 1;
});
