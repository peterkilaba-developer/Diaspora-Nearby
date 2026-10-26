/**
 * On-Chain Backfill: Release the 48,979 $DIASPORA that community treasuries
 * missed in past TDEs (up to epoch1_event4) when their conversion efficiency
 * was < 100% instead of 100%.
 *
 * How it works:
 *   1. Reads `tge_events/epoch1_event4`, `governance/*`, and on-chain
 *      `DiasporaToken.balanceOf(wallet)` for every community treasury.
 *   2. Computes `missedFromPastTdes = Math.max(0, Math.min(event4Dsp - onChain, currentDsp))`
 *      for each community treasury (totaling 48,979 $DIASPORA across 18 treasuries).
 *   3. Calls `DiasporaTGEControllerV2.distributeWelcomeBonus` from the Oracle
 *      Signer (`0xeef49F2a10f0EF143Cd8c710e013285F137F4dE6`) to transfer the
 *      exact missed $DIASPORA from the pre-minted Epoch 1 supply directly to
 *      each community treasury wallet on Base mainnet (without advancing
 *      `currentTgeEvent`).
 *   4. Deducts the newly minted $DIASPORA from `governance/{unitId}.treasuryBalance`,
 *      `communities/{commId}.points`, and `communities/{commId}/treasury/current.points`
 *      in Firestore so only post-TDE-5 DSP remains as unconverted DSP.
 *
 * Usage:
 *   node functions/scripts/backfill-treasury-onchain-mint.js          # dry run
 *   node functions/scripts/backfill-treasury-onchain-mint.js --apply  # execute on-chain + Firestore
 */
const fs = require("fs");
const os = require("os");
const path = require("path");
const {Firestore, FieldValue} = require("@google-cloud/firestore");
const {ethers} = require("ethers");

function loadEnv(envPath) {
  if (!fs.existsSync(envPath)) return;
  const lines = fs.readFileSync(envPath, "utf8").split("\n");
  for (const line of lines) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith("#")) continue;
    const eqIdx = trimmed.indexOf("=");
    if (eqIdx === -1) continue;
    const key = trimmed.substring(0, eqIdx).trim();
    const value = trimmed.substring(eqIdx + 1).trim();
    if (!process.env[key]) process.env[key] = value;
  }
}
loadEnv(path.join(__dirname, "..", "..", "blockchain", ".env"));
loadEnv(path.join(__dirname, "..", ".env"));

function createFirestoreClient() {
  const projectId = process.env.GCLOUD_PROJECT || process.env.GOOGLE_CLOUD_PROJECT || "diaspora-nearby-a3dac";
  try {
    const cfgPath = path.join(os.homedir(), ".config", "configstore", "firebase-tools.json");
    if (fs.existsSync(cfgPath)) {
      const cfg = JSON.parse(fs.readFileSync(cfgPath, "utf8"));
      if (cfg.tokens && cfg.tokens.access_token) {
        const authClient = {
          getAccessToken: async () => ({
            token: cfg.tokens.access_token,
            res: null,
          }),
          getRequestHeaders: async () => ({
            Authorization: `Bearer ${cfg.tokens.access_token}`,
          }),
        };
        return new Firestore({
          projectId,
          authClient,
          preferRest: true,
        });
      }
    }
  } catch (_) {
    // Fall back to default credentials
  }
  return new Firestore({projectId});
}

const DRY_RUN = !process.argv.includes("--apply");
const TOKEN_ADDRESS = "0x55d7e7d006938A15082752225ED44Fd130B87735";
const TGE_ADDRESS = process.env.TGE_CONTROLLER_ADDRESS || "0xb6C049D47A2FaE5413c331760C22E715D0bF4d45";
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function main() {
  const db = createFirestoreClient();
  const provider = new ethers.JsonRpcProvider(process.env.RPC_URL || "https://mainnet.base.org");
  const pk = process.env.BACKEND_SIGNER_PRIVATE_KEY || process.env.PRIVATE_KEY;
  if (!pk) {
    throw new Error("Missing BACKEND_SIGNER_PRIVATE_KEY or PRIVATE_KEY in environment.");
  }
  const signer = new ethers.Wallet(pk, provider);
  const ethBal = await provider.getBalance(signer.address);

  console.log(`\n=== On-Chain Community Treasury $DIASPORA Backfill (${DRY_RUN ? "DRY RUN" : "APPLY"}) ===`);
  console.log(`Oracle Signer: ${signer.address}`);
  console.log(`Signer ETH:    ${ethers.formatEther(ethBal)} ETH\n`);

  const token = new ethers.Contract(
    TOKEN_ADDRESS,
    ["function balanceOf(address) view returns (uint256)"],
    provider
  );
  const tge = new ethers.Contract(
    TGE_ADDRESS,
    [
      "function distributeWelcomeBonus(address userRecipient, uint256 userAmount, address[] treasuryRecipients, uint256[] treasuryAmounts, bytes32 merkleRoot) external",
      "function getLockedBalance() view returns (uint256)",
    ],
    signer
  );

  const [tgeDoc, govSnap, commSnap] = await Promise.all([
    db.collection("tge_events").doc("epoch1_event4").get(),
    db.collection("governance").get(),
    db.collection("communities").get(),
  ]);

  const govMap = {};
  govSnap.forEach((d) => { govMap[d.id] = d.data(); });

  const commByGovId = {};
  commSnap.forEach((d) => {
    const cid = d.id;
    const gid = cid === "global_community"
      ? "global_community"
      : (cid.includes("_") ? cid.substring(cid.indexOf("_") + 1) : cid);
    commByGovId[gid] = cid;
  });

  const snap = tgeDoc.data().snapshot || [];
  const allocations = [];
  let totalToMint = 0;

  for (const s of snap) {
    if (s.systemSlot) continue;
    const g = govMap[s.unitId] || {};
    const wallet = g.walletAddress || s.wallet;
    await sleep(75);
    const balWei = await token.balanceOf(wallet);
    const onChain = Math.floor(Number(ethers.formatUnits(balWei, 18)));
    const currentDsp = Number(g.treasuryBalance || 0);
    const missed = Math.max(0, Math.min(s.dsp - onChain, currentDsp));
    if (missed > 0) {
      totalToMint += missed;
      allocations.push({
        unitId: s.unitId,
        commId: g.communityId || commByGovId[s.unitId] || null,
        wallet,
        event4Dsp: s.dsp,
        onChainBefore: onChain,
        toMint: missed,
        dspAfter: currentDsp - missed,
      });
    }
  }

  for (const a of allocations) {
    console.log(
      `  ${a.unitId.padEnd(40)} | wallet=${a.wallet} | mint=+${String(a.toMint).padEnd(6)} $DIASPORA | onChain: ${String(a.onChainBefore).padEnd(6)} -> ${String(a.onChainBefore + a.toMint).padEnd(6)} | remainingDsp=${a.dspAfter}`
    );
  }
  console.log(`\nTotal $DIASPORA to mint to ${allocations.length} community treasuries: ${totalToMint} $DIASPORA`);

  if (allocations.length === 0) {
    console.log("Nothing to backfill — all community treasuries are already reconciled on-chain.");
    return;
  }

  // Sort ascending by `toMint` so the smallest allocation (<= 1,000 cap) serves as `userRecipient`
  allocations.sort((a, b) => a.toMint - b.toMint);
  const first = allocations[0];
  const rest = allocations.slice(1);

  const userRecipient = first.wallet;
  const userAmount = ethers.parseUnits(first.toMint.toString(), 18);
  const treasuryRecipients = rest.map((r) => r.wallet);
  const treasuryAmounts = rest.map((r) => ethers.parseUnits(r.toMint.toString(), 18));
  const merkleRoot = ethers.solidityPackedKeccak256(
    ["address", "uint256", "address[]", "uint256[]"],
    [userRecipient, userAmount, treasuryRecipients, treasuryAmounts]
  );

  const gasEst = await tge.distributeWelcomeBonus.estimateGas(
    userRecipient,
    userAmount,
    treasuryRecipients,
    treasuryAmounts,
    merkleRoot
  );
  const block = await provider.getBlock("latest");
  const minCostWei = gasEst * ((block.baseFeePerGas || 5000000n) + 100000n);
  console.log(`Estimated Gas: ${gasEst.toString()} (~${ethers.formatEther(minCostWei)} ETH minimum)`);

  if (ethBal < minCostWei) {
    console.log(
      `\n⚠️  Oracle Signer (${signer.address}) currently has ${ethers.formatEther(ethBal)} ETH, ` +
      `which is slightly below the ~${ethers.formatEther(minCostWei)} ETH needed for Base L2 gas.\n` +
      `Top up ${signer.address} with >= 0.0001 ETH on Base Mainnet and re-run with --apply.`
    );
    if (!DRY_RUN) process.exit(1);
    return;
  }

  if (DRY_RUN) {
    console.log("\nDRY RUN complete. Re-run with --apply to execute on-chain and update Firestore.");
    return;
  }

  console.log("\nSubmitting on-chain backfill transaction...");
  const tx = await tge.distributeWelcomeBonus(
    userRecipient,
    userAmount,
    treasuryRecipients,
    treasuryAmounts,
    merkleRoot
  );
  console.log(`TX submitted: ${tx.hash}`);
  const receipt = await tx.wait();
  console.log(`✅ TX confirmed in block ${receipt.blockNumber}: ${receipt.hash}`);

  // Deduct newly minted $DIASPORA from Firestore DSP balances
  const batch = db.batch();
  for (const a of allocations) {
    batch.set(db.collection("governance").doc(a.unitId), {
      treasuryBalance: FieldValue.increment(-a.toMint),
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
    if (a.commId) {
      batch.set(db.collection("communities").doc(a.commId), {
        points: FieldValue.increment(-a.toMint),
        updatedAt: FieldValue.serverTimestamp(),
      }, {merge: true});
      batch.set(db.collection("communities").doc(a.commId).collection("treasury").doc("current"), {
        points: FieldValue.increment(-a.toMint),
        updatedAt: FieldValue.serverTimestamp(),
      }, {merge: true});
    }
  }
  await batch.commit();
  console.log("✅ Firestore DSP balances updated to reflect newly minted on-chain $DIASPORA.");
}

main().catch((err) => {
  console.error("Backfill failed:", err);
  process.exit(1);
});
