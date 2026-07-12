/**
 * One-off CORRECTIVE MINT for TGE 1 missed founders + liquidity allocations.
 *
 * Background:
 *   TGE 1 fired on 2026-04-19 (tx 0xbf42e794…761850, block 44,914,723) via the
 *   V1 executeTGE pipeline. The off-chain oracle in functions/lib/dsp.js only
 *   appended `governance/*` docs to the recipients array; the Founders and
 *   Liquidity (Investors/SAFT) system treasuries were not appended because
 *   their governance docs lacked `walletAddress` at snapshot time. Net effect:
 *
 *     Founders treasury  (0xda9073…0D3F):  0 DSP ever received
 *     Liquidity treasury (0x3c788A…48d5):  0 DSP ever received
 *
 *   The whitepaper guarantees 10% of every TGE batch to each. TGE 1's batch
 *   total was 80,807 DSP, so the missed amount is 8,080.7 DSP per slot.
 *
 *   The token has 1T headroom (only ~1M minted of 1T cap), so the cleanest
 *   remediation is to mint directly from the token contract to each treasury.
 *
 * What this script does:
 *   - Reads the missed amount from env (defaults to 8081 DSP each, the
 *     post-rounding 10% of TGE 1's 80,807 batch).
 *   - Calls DiasporaToken.mint(recipient, amount) twice, once per treasury.
 *
 * Required role:
 *   The caller must hold MINTER_ROLE on the token. Today that's the deployer
 *   EOA (pre-Safe migration). After HANDOFF.md step 1 lands this should be
 *   executed via the Safe Transaction Builder.
 *
 * Usage (deployer EOA, mainnet):
 *   cd blockchain
 *   FOUNDERS_AMOUNT=8081 LIQUIDITY_AMOUNT=8081 \
 *     npx hardhat run scripts/admin/corrective-mint-tge1-treasuries.js \
 *     --network base-mainnet
 *
 * Dry-run (just print the would-be calls):
 *   DRY_RUN=1 npx hardhat run scripts/admin/corrective-mint-tge1-treasuries.js \
 *     --network base-mainnet
 *
 * Safety:
 *   - Refuses to run twice — checks for a marker tx by inspecting whether the
 *     founders treasury already has a non-zero balance from a mint.
 *   - Refuses if the env amounts exceed 20,000 DSP each (sanity guardrail —
 *     correct value is ~8,081; anything order-of-magnitude higher is a typo).
 */
import hre from "hardhat";

const connection = await hre.network.getOrCreate();
const { ethers } = connection;

const TOKEN = "0x55d7e7d006938A15082752225ED44Fd130B87735";
const FOUNDERS = "0xda9073CbA407648d5EB3271F6B18CEbBd1290D3F";
const LIQUIDITY = "0x3c788A75744589CAC7371dfe1bf64DB1047048d5";

const TOKEN_ABI = [
  "function mint(address to, uint256 amount) external",
  "function balanceOf(address) view returns (uint256)",
  "function hasRole(bytes32 role, address account) view returns (bool)",
  "function MINTER_ROLE() view returns (bytes32)",
  "function getHardCapProgress() view returns (uint256 currentSupply, uint256 hardCap, uint256 percentage)",
];

async function main() {
  const dryRun = process.env.DRY_RUN === "1";
  const foundersAmount = Number(process.env.FOUNDERS_AMOUNT || "8081");
  const liquidityAmount = Number(process.env.LIQUIDITY_AMOUNT || "8081");

  if (foundersAmount <= 0 || liquidityAmount <= 0) {
    throw new Error("FOUNDERS_AMOUNT and LIQUIDITY_AMOUNT must be > 0");
  }
  if (foundersAmount > 20000 || liquidityAmount > 20000) {
    throw new Error(
      `Sanity guardrail: each amount must be <= 20,000 DSP. ` +
      `Got founders=${foundersAmount}, liquidity=${liquidityAmount}. ` +
      `The correct value for TGE 1 is ~8,081 DSP each (10% of the 80,807 batch). ` +
      `If you genuinely need to mint more, raise this cap by hand.`
    );
  }

  const [signer] = await ethers.getSigners();
  console.log("Signer:", signer.address);
  console.log("Network:", (await ethers.provider.getNetwork()).name);
  console.log();

  const token = new ethers.Contract(TOKEN, TOKEN_ABI, signer);

  const MINTER_ROLE = await token.MINTER_ROLE();
  const hasRole = await token.hasRole(MINTER_ROLE, signer.address);
  if (!hasRole) {
    throw new Error(
      `Signer ${signer.address} does NOT hold MINTER_ROLE on token. ` +
      `Either use the deployer EOA (pre-Safe migration) or run this via the ` +
      `Safe Transaction Builder (post-migration).`
    );
  }

  const foundersBalBefore = await token.balanceOf(FOUNDERS);
  const liquidityBalBefore = await token.balanceOf(LIQUIDITY);

  console.log("=== Before ===");
  console.log("  Founders   balance:", ethers.formatEther(foundersBalBefore));
  console.log("  Liquidity  balance:", ethers.formatEther(liquidityBalBefore));

  if (foundersBalBefore > 0n || liquidityBalBefore > 0n) {
    throw new Error(
      "Refusing to mint: at least one treasury already has a non-zero balance. " +
      "This may mean the corrective mint has already been executed. Investigate " +
      "via Basescan transfer history before re-running."
    );
  }

  const foundersWei = ethers.parseEther(foundersAmount.toString());
  const liquidityWei = ethers.parseEther(liquidityAmount.toString());

  const cap = await token.getHardCapProgress();
  console.log(
    `  Supply: ${ethers.formatEther(cap[0])} / ${ethers.formatEther(cap[1])} ` +
    `(${cap[2]}%)`
  );
  console.log();

  console.log("=== Planned mints ===");
  console.log(`  mint(${FOUNDERS}, ${foundersAmount} DSP)   // Founders & Core Team`);
  console.log(`  mint(${LIQUIDITY}, ${liquidityAmount} DSP)   // Liquidity / Investors Treasury`);
  console.log();

  if (dryRun) {
    console.log("DRY_RUN=1 set — exiting without sending transactions.");
    return;
  }

  console.log("Sending tx 1/2 — Founders mint...");
  const tx1 = await token.mint(FOUNDERS, foundersWei);
  const r1 = await tx1.wait();
  console.log("  ✅", r1.hash);

  console.log("Sending tx 2/2 — Liquidity mint...");
  const tx2 = await token.mint(LIQUIDITY, liquidityWei);
  const r2 = await tx2.wait();
  console.log("  ✅", r2.hash);

  console.log();
  console.log("=== After ===");
  console.log("  Founders   balance:", ethers.formatEther(await token.balanceOf(FOUNDERS)));
  console.log("  Liquidity  balance:", ethers.formatEther(await token.balanceOf(LIQUIDITY)));
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
