/**
 * DSP Points & Treasury module.
 * TGE Oracle, epoch management, awards, deductions, treasury sync.
 */
const { functions, admin, db } = require("./shared");
const { ethers } = require("ethers");

// ── Configuration (from environment) ──
// NOTE: do NOT cache these at module-load time. With Firebase Functions v1
// secrets, process.env.BACKEND_SIGNER_PRIVATE_KEY is populated by the runtime
// before the function handler runs, but caching at module level made one
// silent-skip bug already (2026-06-02). Always re-read via assertOnChainConfig
// inside the handler so the failure mode is loud if the binding is missing.
const { assertOnChainConfig, readOptionalConfig } = require("./on_chain_config");

const { MerkleTree } = require("merkletreejs");

const TGE_CONTROLLER_ABI = [
  "function executeTGE(address[] recipients, uint256[] amounts, uint8[] efficiencies, bytes32 merkleRoot) external",
  "function mintEpochSupply(uint256 amount) external",
  "function distributeWelcomeBonus(address userRecipient, uint256 userAmount, address[] treasuryRecipients, uint256[] treasuryAmounts, bytes32 merkleRoot) external",
  "function distributeGenesisTokens(address userRecipient, uint256 userAmount, address[] treasuryRecipients, uint256[] treasuryAmounts, bytes32 merkleRoot) external",
  "function publishTdeRoot(uint256 epoch, uint256 tdeEvent, bytes32 merkleRoot, uint256 totalBatchAmount) external",
  "function claimTdeTokens(address recipient, uint256 epoch, uint256 tdeEvent, uint256 earnedAmount, uint8 efficiency, bytes32[] proof) external",
  "function tdeClaimed(bytes32 key) view returns (bool)",
  "function currentEpoch() view returns (uint256)",
  "function currentTgeEvent() view returns (uint256)",
  "function tgeCount() view returns (uint256)",
  "function totalMinted() view returns (uint256)",
  "function totalDistributed() view returns (uint256)",
  "function totalBurned() view returns (uint256)",
  "function totalWelcomeBonuses() view returns (uint256)",
  "function getStats() view returns (uint256,uint256,uint256,uint256,uint256,uint256,uint256)",
  "function getLockedBalance() view returns (uint256)",
];

// ══════════════════════════════════════════════════════════════════
// ── TGE ORACLE: Snapshot-based Token Generation Event ──
// ══════════════════════════════════════════════════════════════════

/**
 * Calculate PCT (Proof of Community Trust) efficiency.
 * Score < 11 (0-10) = 0%, 11-90 = exact percent (11%-90%), 91+ = 100%
 * Matches EpochService.calculateEfficiency in Dart.
 */
function calculateEfficiency(trustScore) {
  const score = Number(trustScore) || 0;
  if (score < 11) return 0;
  if (score >= 91) return 100;
  return Math.round(Math.min(Math.max(score, 0), 100));
}

// ── Epoch Schedule (mirrors EpochService in Dart) ──────────────────────
// 10 Epochs, each with 10 TGE Events (10% of epoch target each)
const EPOCH_SCHEDULE = [
  { level: 1, dspTarget: 1000000 },       // 1M
  { level: 2, dspTarget: 10000000 },      // 10M
  { level: 3, dspTarget: 100000000 },     // 100M
  { level: 4, dspTarget: 1000000000 },    // 1B
  { level: 5, dspTarget: 10000000000 },   // 10B
  { level: 6, dspTarget: 100000000000 },  // 100B
  { level: 7, dspTarget: 1000000000000 }, // 1T
  { level: 8, dspTarget: 10000000000000 },// 10T
  { level: 9, dspTarget: 100000000000000 },// 100T
  { level: 10, dspTarget: 1000000000000000 },// 1QD
];

/**
 * Get the current epoch and completed TGE events based on cumulative DSP earnings.
 * Returns { epoch, completedEvents, nextMilestone }
 */
function getEpochState(cumulativeEarnings) {
  let currentEpoch = EPOCH_SCHEDULE[EPOCH_SCHEDULE.length - 1];
  for (const epoch of EPOCH_SCHEDULE) {
    if (cumulativeEarnings < epoch.dspTarget) {
      currentEpoch = epoch;
      break;
    }
  }

  const prevEpoch = EPOCH_SCHEDULE.find(e => e.level === currentEpoch.level - 1);
  const prevTarget = prevEpoch ? prevEpoch.dspTarget : 0;
  const dspRange = currentEpoch.dspTarget - prevTarget;
  const dspStep = Math.round(dspRange / 10);

  let completedEvents = Math.floor((cumulativeEarnings - prevTarget) / dspStep);
  completedEvents = Math.max(0, Math.min(10, completedEvents));

  const nextMilestone = prevTarget + (completedEvents + 1) * dspStep;

  return {
    epoch: currentEpoch.level,
    completedEvents,
    nextMilestone,
    dspStep,
  };
}

/**
 * Core TGE execution logic — shared by both auto-trigger and manual callable.
 * Creates snapshot of all DSP balances + PoCT, calls on-chain contract.
 */
/**
 * Check if a user has completed the 7 Proof of Humanity (PoH) Genesis Milestones.
 * Qualification grants access to TDE macro distributions.
 */
async function isPohQualified(userId, userDocData, pointsDocData) {
  if (userDocData && (userDocData.hasReceivedPohTokenDistribution === true ||
      (userDocData.welcomeBonusMilestonesStatus && userDocData.welcomeBonusMilestonesStatus.allMilestonesMet === true))) {
    return true;
  }

  const [userDoc, pointsDoc, trustDataDoc, trustScoresDoc] = await Promise.all([
    userDocData ? Promise.resolve({ exists: true, data: () => userDocData }) : db.collection("users").doc(userId).get(),
    pointsDocData ? Promise.resolve({ exists: true, data: () => pointsDocData }) : db.collection("user_points").doc(userId).get(),
    db.collection("trust_data").doc(userId).get(),
    db.collection("trust_scores").doc(userId).get(),
  ]);

  const userData = userDoc.exists ? userDoc.data() : {};
  const pointsData = pointsDoc.exists ? pointsDoc.data() : {};
  const trustData = trustDataDoc.exists
    ? trustDataDoc.data()
    : (trustScoresDoc.exists ? trustScoresDoc.data() : {});

  if (trustData && trustData.isPoHComplete === true) {
    return true;
  }

  const milestones = Array.isArray(trustData.awardedQualificationMilestones)
    ? trustData.awardedQualificationMilestones
    : [];

  // 1. Location Milestone (Active live location sharing)
  const hasLocation = !userData.cityVisibilityForfeited &&
    userData.showCurrentLocationName !== false &&
    !!(
      milestones.includes("LocationTransparency") ||
      userData.homeCountryCode ||
      pointsData.homeCountryCode ||
      userData.locationEnabled ||
      userData.currentLocation ||
      userData.currentCity ||
      userData.homeCity
    );

  // 2. Profile Complete Milestone (All 12 profile fields completed)
  const completedFields = countCompletedProfileMilestoneFields(userData);
  const totalFields = PROFILE_MILESTONE_FIELDS.length;
  const isProfileComplete = !!(
    milestones.includes("Profile") ||
    userData.isProfileComplete ||
    userData.isComplete ||
    (completedFields >= totalFields && totalFields > 0)
  );

  // 3. 10 QR Exchanges Milestone
  const qrCount = Number(trustData.uniqueQrCount || pointsData.qrConnectionCount || 0);
  const hasTenQr = milestones.includes("QR") || qrCount >= 10;

  // 4. Family Circle (10 Family Connections)
  const familyCount = Number(trustData.uniqueFamilyCount || 0);
  const hasTenFamily = milestones.includes("Family") || familyCount >= 10;

  // 5. Friend Circle (10 Friend Connections)
  const friendCount = Number(trustData.uniqueFriendCount || 0);
  const hasTenFriends = milestones.includes("Friend") || friendCount >= 10;

  // 6. Peer Verifications (10 Peer Profile Field Verifications)
  const verificationCount = Number(trustData.uniqueVerificationCount || 0);
  const hasTenVerifications = milestones.includes("Verified") || verificationCount >= 10;

  // 7. Ubuntu Emergency Fund Contribution (voluntary +10 PCT once members have tokens)
  // Excluded from the required completion gate to avoid token-requirement deadlock.
  return (
    hasLocation &&
    isProfileComplete &&
    hasTenQr &&
    hasTenFamily &&
    hasTenFriends &&
    hasTenVerifications
  );
}

async function performTGE(triggerSource) {
  // Fail loud if any required env is missing. Previously this returned null
  // silently which could be confused with "no users to TGE" by callers.
  const { backendSignerKey, tokenAddress, tgeControllerAddress } = assertOnChainConfig(
    "performTGE",
    ["backendSignerKey", "tokenAddress", "tgeControllerAddress"]
  );
  // Optional env overrides — if unset, performTGE reads the wallet for each
  // system slot directly from its governance/* doc. Useful only when you
  // want to repoint the slot without editing Firestore.
  const { foundersTreasuryAddress, liquidityTreasuryAddress } = readOptionalConfig();

  console.log(`[TGE Oracle] Starting TGE snapshot (triggered by: ${triggerSource})...`);

  // ── Step 1: Snapshot all user DSP balances ────────────────────────
  const userPointsSnap = await db.collection("user_points")
    .where("availablePoints", ">", 0)
    .get();

  const recipients = [];
  const amounts = [];
  const efficiencies = [];
  const snapshotDetails = [];

  let totalDsp = 0;
  let usersIncluded = 0;
  let usersSkipped = 0;

  for (const doc of userPointsSnap.docs) {
    const d = doc.data();
    const walletAddress = d.walletAddress;
    const dspBalance = d.availablePoints || 0;
    const trustScore = d.trustScore || 0;

    if (!walletAddress || walletAddress.length < 10) {
      usersSkipped++;
      continue;
    }
    if (dspBalance <= 0) {
      usersSkipped++;
      continue;
    }

    // TDE participation gate: User must complete all 7 Proof of Humanity (PoH) Milestones
    const userDoc = await db.collection("users").doc(doc.id).get();
    const userData = userDoc.exists ? userDoc.data() : null;
    const isPohMet = await isPohQualified(doc.id, userData, d);

    if (!isPohMet) {
      usersSkipped++;
      continue;
    }

    const efficiency = calculateEfficiency(trustScore);
    recipients.push(walletAddress);
    amounts.push(ethers.parseUnits(dspBalance.toString(), 18));
    efficiencies.push(efficiency);
    totalDsp += dspBalance;
    usersIncluded++;

    snapshotDetails.push({
      userId: doc.id,
      wallet: walletAddress,
      dsp: dspBalance,
      trustScore,
      efficiency,
      pohQualified: true,
    });
  }

  // ── Step 2: Snapshot community + system treasury balances ─────────
  //
  // FAIL-LOUD (post-TGE-1 hardening, 2026-06):
  //   Before this change, governance docs with missing walletAddress or
  //   missing averagePct/averagePoCT were silently dropped/zeroed. In TGE 1 (block
  //   44,914,723) that resulted in 17 of 24 "recipients" receiving 0 DSP
  //   because their averagePct/averagePoCT field was unset → eff=0 → 100% burned, and
  //   the Founders / Liquidity treasuries received NOTHING (they weren't
  //   even in the recipients list — their governance docs lacked
  //   walletAddress, so the silent-skip below dropped them).
  //
  //   We now collect missing fields and refuse to fire the TGE if ANY
  //   eligible community treasury (treasuryBalance > 0) is missing a
  //   required field. The healing path is to populate the field in
  //   Firestore and re-run.
  const govSnap = await db.collection("governance")
    .where("treasuryBalance", ">", 0)
    .get();

  let treasuriesIncluded = 0;
  const treasuryConfigErrors = [];

  for (const doc of govSnap.docs) {
    const d = doc.data();
    const walletAddress = d.walletAddress;
    const treasuryDsp = d.treasuryBalance || 0;

    if (treasuryDsp <= 0) continue; // legitimate: no funds to release

    if (!walletAddress || walletAddress.length < 10) {
      treasuryConfigErrors.push(
        `governance/${doc.id} (treasuryBalance=${treasuryDsp}) is missing walletAddress`
      );
      continue;
    }

    // CPCT: Average PCT of community members → decile efficiency.
    // Hard-fail on missing field — silent default to 0 burns the entire tribute.
    // System treasuries (founders / liquidity / burn) are exempt:
    // they're handled separately below with efficiency=100 per whitepaper.
    // `investors` is still skipped here to avoid mis-classifying the legacy
    // doc as a community treasury; it should hold treasuryBalance=0 after the
    // 2026-06-04 investors→liquidity migration.
    const SYSTEM_DOC_IDS = new Set(["founders", "liquidity", "investors", "burn"]);
    if (SYSTEM_DOC_IDS.has(doc.id)) continue;

    const isGlobalCommunity = doc.id === "global_community";
    let treasuryEfficiency = 100;
    const avgTrustScore = d.averagePoCT != null ? d.averagePoCT : (d.averagePct != null ? d.averagePct : 100);

    if (!isGlobalCommunity) {
      if (d.averagePoCT === undefined && d.averagePct === undefined) {
        treasuryConfigErrors.push(
          `governance/${doc.id} (treasuryBalance=${treasuryDsp}, wallet=${walletAddress}) ` +
          `is missing averagePoCT / averagePct — would silently burn 100% of tribute`
        );
        continue;
      }
      treasuryEfficiency = calculateEfficiency(avgTrustScore);
    }

    recipients.push(walletAddress);
    amounts.push(ethers.parseUnits(Math.floor(treasuryDsp).toString(), 18));
    efficiencies.push(treasuryEfficiency);
    totalDsp += Math.floor(treasuryDsp);
    treasuriesIncluded++;

    snapshotDetails.push({
      unitId: doc.id,
      unitName: d.name || doc.id,
      wallet: walletAddress,
      dsp: Math.floor(treasuryDsp),
      efficiency: treasuryEfficiency,
      averagePct: avgTrustScore,
      averagePoCT: avgTrustScore,
    });
  }

  if (treasuryConfigErrors.length > 0) {
    const msg =
      "[TGE Oracle] FAIL-LOUD: refusing to fire TGE with misconfigured community treasuries.\n" +
      treasuryConfigErrors.map((e) => "  - " + e).join("\n") +
      "\nFix the governance/* docs in Firestore and re-trigger.";
    console.error(msg);
    throw new Error(
      `performTGE aborted: ${treasuryConfigErrors.length} community treasury config error(s). See logs.`
    );
  }

  // ── Step 2b: Append system treasuries (Founders + Liquidity + Burn) ──
  //
  // Whitepaper guarantees 10% per slot per TGE for the system treasuries
  // (Founders, Liquidity, Burn). The V1 executeTGE signature has no built-in
  // concept of these slots, so we must append them explicitly with
  // efficiency=100 (no penalty burn — these are administered, not earned).
  //
  // Wallet resolution priority:
  //   1. env override (FOUNDERS_TREASURY_ADDRESS / LIQUIDITY_TREASURY_ADDRESS)
  //   2. governance/<id>.walletAddress (Safe address post-2026-06-04 migration)
  //
  // Amount source: governance/<id>.treasuryBalance, accumulated by
  // awardPoints() (10% per signup).
  //
  // The legacy `investors` slot was removed from this loop on 2026-06-04 after
  // the investors→liquidity data migration. governance/investors is preserved
  // as an audit trail (with treasuryBalance=0); awardPoints() no longer writes
  // to it. If you find treasuryBalance > 0 there in the future, something
  // regressed — run functions/scripts/migrate-investors-to-liquidity.js again.
  const systemSlotSpecs = [
    { id: "founders",  envWallet: foundersTreasuryAddress,  label: "Founders & Core Team" },
    { id: "liquidity", envWallet: liquidityTreasuryAddress, label: "Liquidity Treasury" },
    { id: "burn",      envWallet: null,                     label: "Deflationary Burn" },
  ];

  let systemSlotsIncluded = 0;
  for (const slot of systemSlotSpecs) {
    const govDoc = await db.collection("governance").doc(slot.id).get();
    if (!govDoc.exists) {
      console.warn(`[TGE Oracle] system slot governance/${slot.id} does not exist — skipping.`);
      continue;
    }
    const data = govDoc.data();
    const bal = data.treasuryBalance || 0;
    if (bal <= 0) {
      continue; // legitimate: nothing accrued for this slot since last TGE
    }
    const wallet = slot.envWallet || data.walletAddress;
    if (!wallet || wallet.length < 10) {
      console.warn(
        `[TGE Oracle] system slot governance/${slot.id} has treasuryBalance=${bal} ` +
        `but no resolvable wallet (env override unset, govDoc.walletAddress missing). ` +
        `Skipping — fix Firestore or set env override to include this slot in future TGEs.`
      );
      continue;
    }

    recipients.push(wallet);
    amounts.push(ethers.parseUnits(Math.floor(bal).toString(), 18));
    efficiencies.push(100); // system slot — no penalty burn
    totalDsp += Math.floor(bal);
    systemSlotsIncluded++;

    snapshotDetails.push({
      unitId: slot.id,
      unitName: slot.label,
      wallet,
      dsp: Math.floor(bal),
      efficiency: 100,
      systemSlot: true,
    });
  }

  if (recipients.length === 0) {
    console.log("[TGE Oracle] No eligible recipients. Aborting.");
    return null;
  }

  console.log(
    `[TGE Oracle] Snapshot: ${usersIncluded} users, ${treasuriesIncluded} community treasuries, ` +
    `${systemSlotsIncluded} system slots, ${totalDsp} DSP`
  );

  // ── Step 3: Call on-chain executeTGE ───────────────────────────────
  const provider = new ethers.JsonRpcProvider(process.env.RPC_URL || "https://mainnet.base.org");
  const signer = new ethers.Wallet(backendSignerKey, provider);
  const tgeController = new ethers.Contract(tgeControllerAddress, TGE_CONTROLLER_ABI, signer);

  const statsBefore = await tgeController.getStats();
  const epochBefore = Number(statsBefore[0]);
  const eventBefore = Number(statsBefore[1]);

  console.log(`[TGE Oracle] On-chain: Epoch ${epochBefore}, Event ${eventBefore}`);

  // Verify controller has sufficient locked tokens for this batch; auto-mint if new epoch requires pre-mint
  let batchTotalNeeded = 0n;
  for (const amt of amounts) {
    batchTotalNeeded += amt;
  }

  const lockedBalance = await tgeController.getLockedBalance();
  if (lockedBalance < batchTotalNeeded) {
    const epochEntry = EPOCH_SCHEDULE.find(e => e.level === epochBefore) || EPOCH_SCHEDULE[0];
    const epochSupplyTokens = epochEntry.dspTarget;
    console.log(
      `[TGE Oracle] Locked balance (${ethers.formatUnits(lockedBalance, 18)}) < batch needed (${ethers.formatUnits(batchTotalNeeded, 18)}). ` +
      `Auto-minting Epoch ${epochBefore} supply (${epochSupplyTokens} tokens)...`
    );
    const mintTx = await tgeController.mintEpochSupply(ethers.parseUnits(epochSupplyTokens.toString(), 18));
    await mintTx.wait();
    console.log(`[TGE Oracle] ✅ Pre-minted Epoch ${epochBefore} supply: ${mintTx.hash}`);
  }

  const keccak256 = ethers.keccak256;
  const leaves = [];
  const recipientsMap = {};

  for (let i = 0; i < recipients.length; i++) {
    const leaf = keccak256(
      ethers.AbiCoder.defaultAbiCoder().encode(
        ["address", "uint256", "uint256", "uint256", "uint8"],
        [recipients[i], epochBefore, eventBefore, amounts[i], efficiencies[i]]
      )
    );
    leaves.push(leaf);
  }
  const tree = new MerkleTree(leaves, keccak256, { sortPairs: true });
  const merkleRoot = tree.getHexRoot();

  for (const snap of snapshotDetails) {
    if (snap.userId) {
      recipientsMap[snap.userId] = {
        walletAddress: snap.wallet,
        earnedAmount: ethers.parseUnits(snap.dsp.toString(), 18).toString(),
        efficiency: snap.efficiency,
      };
    }
  }

  // Save snapshot for individual anytime pull claims
  await db.collection("tde_snapshots").doc(`epoch_${epochBefore}_tde_${eventBefore}`).set({
    epoch: epochBefore,
    tdeEvent: eventBefore,
    merkleRoot,
    totalBatchAmount: batchTotalNeeded.toString(),
    recipients: recipientsMap,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  const tx = await tgeController.executeTGE(recipients, amounts, efficiencies, merkleRoot);
  const receipt = await tx.wait();

  const statsAfter = await tgeController.getStats();
  const epochAfter = Number(statsAfter[0]);
  const eventAfter = Number(statsAfter[1]);

  console.log(`[TGE Oracle] ✅ TX: ${receipt.hash}`);
  console.log(`[TGE Oracle] Epoch ${epochBefore}→${epochAfter}, Event ${eventBefore}→${eventAfter}`);

  // ── Step 4: Record TGE event in Firestore (deterministic doc ID by epoch/event) ──
  let tdePenaltyBurn = 0;
  for (const snap of snapshotDetails) {
    if (!snap.systemSlot) {
      const eff = Number(snap.efficiency || 0);
      const burned = Math.floor(snap.dsp * ((100 - eff) / 100));
      if (burned > 0) tdePenaltyBurn += burned;
    }
  }

  const tgeEventDocId = `epoch${epochBefore}_event${eventBefore}`;
  const tgeRecord = {
    epoch: epochBefore,
    tgeEvent: eventBefore,
    txHash: receipt.hash,
    merkleRoot,
    totalDsp,
    tdePenaltyBurn,
    totalRecipients: recipients.length,
    usersIncluded,
    treasuriesIncluded,
    systemSlotsIncluded,
    triggerSource,
    timestamp: admin.firestore.FieldValue.serverTimestamp(),
    snapshot: snapshotDetails,
    status: "tx_complete_dsp_pending",
  };
  await db.collection("tge_events").doc(tgeEventDocId).set(tgeRecord);

  // ── Step 5: Deduct DSP from snapshotted participants & record TDE penalty burn ──
  const operations = [];
  if (tdePenaltyBurn > 0) {
    operations.push({
      ref: db.collection("system_stats").doc("treasury"),
      patch: {
        totalBurnedTde: admin.firestore.FieldValue.increment(tdePenaltyBurn),
        lastUpdated: admin.firestore.FieldValue.serverTimestamp(),
      },
    });
    operations.push({
      ref: db.collection("governance").doc("burn"),
      patch: {
        burnedAtTde: admin.firestore.FieldValue.increment(tdePenaltyBurn),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
    });
  }
  for (const snap of snapshotDetails) {
    if (snap.userId) {
      const userRef = db.collection("user_points").doc(snap.userId);
      const userPatch = {
        availablePoints: 0,
        lastUpdated: admin.firestore.FieldValue.serverTimestamp(),
        tgeHistory: admin.firestore.FieldValue.arrayUnion({
          epoch: epochBefore,
          tgeNumber: eventBefore,
          amount: snap.dsp * (snap.efficiency / 100),
          efficiency: snap.efficiency / 100,
          date: admin.firestore.Timestamp.now(),
          txHash: receipt.hash,
        }),
      };
      if (!snap.alreadyHadFirstTge) {
        userPatch.firstTgeReceivedAt = admin.firestore.FieldValue.serverTimestamp();
        userPatch.firstTgeEventId = tgeEventDocId;
      }
      operations.push({ ref: userRef, patch: userPatch });
    } else if (snap.unitId) {
      const govRef = db.collection("governance").doc(snap.unitId);
      operations.push({
        ref: govRef,
        patch: {
          treasuryBalance: 0,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
      });
    }
  }

  let dspDeductionStatus = "complete";
  let dspDeductionError = null;
  try {
    const BATCH_SIZE = 400; // Chunk to stay safely under Firestore's 500 limit
    for (let i = 0; i < operations.length; i += BATCH_SIZE) {
      const chunk = operations.slice(i, i + BATCH_SIZE);
      const chunkBatch = db.batch();
      for (const op of chunk) {
        chunkBatch.set(op.ref, op.patch, { merge: true });
      }
      await chunkBatch.commit();
    }
    await db.collection("tge_events").doc(tgeEventDocId).update({ status: "complete" });
    console.log(`[TGE Oracle] Successfully reset DSP points for ${snapshotDetails.length} participants (tdePenaltyBurn=${tdePenaltyBurn}).`);
  } catch (resetErr) {
    dspDeductionStatus = "tx_complete_dsp_pending";
    dspDeductionError = (resetErr.message || "unknown").slice(0, 500);
    console.error(`[TGE Oracle] ❌ DSP deduction failed AFTER on-chain TX. Recording pending state for healing.`, resetErr);
    await db.collection("tge_events").doc(tgeEventDocId).update({
      dspDeductionError,
      dspDeductionErrorAt: admin.firestore.FieldValue.serverTimestamp(),
    }).catch(() => {});
  }

  return {
    success: true,
    txHash: receipt.hash,
    epoch: epochBefore,
    tgeEvent: eventBefore,
    newEpoch: epochAfter,
    newTgeEvent: eventAfter,
    totalDsp,
    totalRecipients: recipients.length,
    dspDeductionStatus,
    dspDeductionError,
    tgeEventDocId,
  };
}

/**
 * AUTO-TRIGGER: Watches total DSP supply for TGE milestone crossings.
 * totalMinted = user earnings + all 10 expansion slots (community, founders, investors, burn)
 * When totalMinted crosses the next 10% epoch milestone, fires TGE automatically.
 */
exports.onGlobalDspMilestone = functions
  .runWith({ timeoutSeconds: 300, memory: "512MB", secrets: ["BACKEND_SIGNER_PRIVATE_KEY"] })
  .firestore.document("system_stats/dsp_supply")
  .onWrite(async (change) => {
    if (!change.after.exists) return null;

    const newData = change.after.data();
    const oldData = change.before.exists ? change.before.data() : {};

    const newSupply = newData.totalMinted || 0;
    const oldSupply = oldData.totalMinted || 0;

    // Only trigger if supply increased
    if (newSupply <= oldSupply) return null;

    // Calculate epoch state based on total supply
    const oldState = getEpochState(oldSupply);
    const newState = getEpochState(newSupply);

    // Check if we crossed a new TGE milestone
    if (newState.completedEvents <= oldState.completedEvents &&
      newState.epoch <= oldState.epoch) {
      return null; // No new milestone crossed
    }

    console.log(`[TGE Oracle] 🎯 MILESTONE CROSSED!`);
    console.log(`  Total Supply: ${oldSupply} → ${newSupply}`);
    console.log(`  Epoch ${oldState.epoch} Event ${oldState.completedEvents} → Epoch ${newState.epoch} Event ${newState.completedEvents}`);

    // Prevent duplicate triggers with a lock document
    const lockRef = db.collection("system_stats").doc("tge_lock");
    const lockKey = `epoch_${newState.epoch}_event_${newState.completedEvents}`;

    try {
      await db.runTransaction(async (transaction) => {
        const lockDoc = await transaction.get(lockRef);
        const lockData = lockDoc.exists ? lockDoc.data() : {};

        if (lockData[lockKey]) {
          console.log(`[TGE Oracle] Already processed ${lockKey}. Skipping.`);
          throw new Error("DUPLICATE"); // Abort transaction
        }

        // Set lock BEFORE executing TGE
        transaction.set(lockRef, {
          [lockKey]: true,
          lastTriggered: admin.firestore.FieldValue.serverTimestamp(),
          lastMilestone: lockKey,
        }, { merge: true });
      });
    } catch (e) {
      if (e.message === "DUPLICATE") return null;
      console.error("[TGE Oracle] Lock transaction failed:", e.message);
      return null;
    }

    // Execute TGE
    try {
      const result = await performTGE(`auto:${lockKey}`);
      if (result) {
        console.log(`[TGE Oracle] ✅ Auto-TGE complete: ${result.txHash}`);
      }
    } catch (error) {
      console.error(`[TGE Oracle] ❌ Auto-TGE failed:`, error.message);
      // Clear the lock so it can retry
      await lockRef.set({ [lockKey]: false }, { merge: true });
    }
  });

/**
 * MANUAL TRIGGER: Callable function for admin to force a TGE.
 * Useful for testing or emergency scenarios.
 */
exports.executeTGE = functions
  .runWith({ timeoutSeconds: 300, memory: "512MB", secrets: ["BACKEND_SIGNER_PRIVATE_KEY"] })
  .https.onCall(async (data, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError("unauthenticated", "Must be authenticated.");
    }
    // TODO: Add admin role check for production

    try {
      const result = await performTGE("manual:" + context.auth.uid);
      if (!result) {
        throw new functions.https.HttpsError(
          "failed-precondition",
          "No eligible recipients or missing config."
        );
      }
      return result;
    } catch (error) {
      if (error instanceof functions.https.HttpsError) throw error;
      throw new functions.https.HttpsError("internal", `TGE failed: ${error.message}`);
    }
  });

// ══════════════════════════════════════════════════════════════════════
// BACKFILL: reconstruct user_points.lifetimeEarnings from trust_data.
//
// Historical bug: the old `CROSS_USER_ACTIONS` allow-list in `awardPoints`
// rejected friend_connection / identity_qr_exchange / verified_by_peer /
// vouched_by_peer when the *other* party triggered the milestone, so
// `lifetimeEarnings.<key>` was never incremented even though counts grew
// in `trust_data`. This admin-only callable walks every user and writes
// `lifetimeEarnings.<key> = uniqueCount * 1000` for the affected actions
// IF the current value is below the reconstructed value (idempotent).
//
// It does NOT touch totalPoints / availablePoints — those balances would
// also be wrong but we don't want to mint phantom DSP retroactively. The
// goal here is purely UI restoration of the PoA "earned" counters.
// ══════════════════════════════════════════════════════════════════════
exports.backfillLifetimeEarnings = functions
  .runWith({ timeoutSeconds: 540, memory: '512MB' })
  .https.onCall(async (data, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError('unauthenticated', 'Sign in required.');
    }

    // Admin gate — Firestore isAdmin flag OR Auth custom claim.
    const callerId = context.auth.uid;
    const callerDoc = await db.collection('users').doc(callerId).get();
    let isCallerAdmin = callerDoc.exists && callerDoc.data().isAdmin === true;
    if (!isCallerAdmin) {
      try {
        const rec = await admin.auth().getUser(callerId);
        isCallerAdmin = rec.customClaims && rec.customClaims.admin === true;
      } catch (_) {}
    }
    if (!isCallerAdmin) {
      throw new functions.https.HttpsError('permission-denied', 'Admin only.');
    }

    const dryRun = data && data.dryRun === true;
    const trustToAction = {
      uniqueFamilyCount: 'family_connection',
      uniqueFriendCount: 'friend_connection',
      uniqueQrCount: 'identity_qr_exchange',
      verifiedByCount: 'verified_by_peer',
      uniqueVouchCount: 'vouched_by_peer',
    };
    const PER_UNIT = 1000;

    let usersScanned = 0;
    let usersUpdated = 0;
    const perActionTotals = {};

    // Walk user_points to ensure we touch every user with a wallet/balance.
    const upSnap = await db.collection('user_points').get();
    for (const upDoc of upSnap.docs) {
      usersScanned++;
      const userId = upDoc.id;
      const up = upDoc.data() || {};
      const lifetime = up.lifetimeEarnings || {};

      const tdSnap = await db.collection('trust_data').doc(userId).get();
      if (!tdSnap.exists) continue;
      const td = tdSnap.data() || {};

      const patch = {};
      for (const [field, action] of Object.entries(trustToAction)) {
        const count = Number(td[field] || 0);
        if (count <= 0) continue;
        const expected = count * PER_UNIT;
        const current = Number(lifetime[action] || 0);
        if (expected > current) {
          patch[`lifetimeEarnings.${action}`] = expected;
          perActionTotals[action] = (perActionTotals[action] || 0) + (expected - current);
        }
      }

      // Welcome bonus: if user_points exists but lifetimeEarnings.welcome_bonus is missing.
      if (!lifetime.welcome_bonus) {
        patch['lifetimeEarnings.welcome_bonus'] = 1000;
        perActionTotals.welcome_bonus = (perActionTotals.welcome_bonus || 0) + 1000;
      }

      // Sweep literal-dot garbage from the early script revision.
      for (const key of Object.keys(up)) {
        if (key.startsWith('lifetimeEarnings.')) {
          patch[key] = admin.firestore.FieldValue.delete();
        }
      }

      if (Object.keys(patch).length === 0) continue;
      usersUpdated++;
      if (!dryRun) {
        patch.lastUpdated = admin.firestore.FieldValue.serverTimestamp();
        // .update() interprets `lifetimeEarnings.<key>` as a nested-field
        // path. .set({merge:true}) would store the dot as a literal.
        await db.collection('user_points').doc(userId).update(patch);
      }
    }

    return {
      success: true,
      dryRun,
      usersScanned,
      usersUpdated,
      perActionTotals,
    };
  });

// ══════════════════════════════════════════════════════════════════════
// SECURE POINTS FUNCTIONS (Replaces client-side financial writes)
// ══════════════════════════════════════════════════════════════════════
// These Cloud Functions use the Admin SDK to bypass Firestore security
// rules and are the ONLY way to modify financial balances. The client
// calls these via httpsCallable instead of writing directly.

/**
 * awardPoints — Awards DSP points to any user.
 * Replaces the client-side addPoints(), awardMessagePoint(),
 * awardExplorationPoints(), awardSharePoints(), and initializeUserPoints().
 *
 * @param {string} userId — Target user
 * @param {number} points — Points to award
 * @param {string} action — Action type (e.g. 'welcome_bonus', 'message_sent')
 * @param {object} metadata — Optional metadata
 * @param {boolean} skipTreasury — If true, skip treasury distribution
 */
exports.awardPoints = functions
  .runWith({ secrets: ["BACKEND_SIGNER_PRIVATE_KEY"] })
  .https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Must be authenticated.");
  }

  const callerId = context.auth.uid;
  const { userId, points, action, metadata, skipTreasury } = data;

  // Validation
  if (!userId || !points || !action) {
    throw new functions.https.HttpsError("invalid-argument", "userId, points, and action are required.");
  }
  if (typeof points !== "number" || points <= 0 || points > 100000) {
    throw new functions.https.HttpsError("invalid-argument", "Points must be between 1 and 100000.");
  }

  // Security: Only the user themselves can earn points (or a known system action)
  const SELF_ACTIONS = [
    'message_sent', 'daily_message', 'exploration',
    'share_content', 'voice_call', 'video_call',
    'event_attendance', 'marketplace_listing', 'real_estate_listing',
    'flight_booking', 'car_rental', 'bereavement_contribution',
    'profile_completion', 'daily_streak',
    'host_location_moved', 'also_lived_in_added',
  ];

  // For cross-user awards (e.g. referral rewards, connection milestones),
  // only allow trusted actions. These are all triggered by the *other*
  // party's action on this user (e.g. when someone QR-scans the user, the
  // scanner's session ends up calling awardPoints for the scannee).
  const CROSS_USER_ACTIONS = [
    'trust_vouch_reward', 'vouch_reward',
    'vouch_consensus_agree',
    'family_connection', 'friend_connection',
    'identity_qr_exchange', 'identity_qr_exchange_continuous',
    'verified_by_peer', 'verifier_reward',
    'vouched_by_peer',
    'verified_solution_milestone', 'verified_solution_verifier_reward',
    'host_traveler_host_reward', 'host_traveler_guest_reward',
    'peer_visit_visitor_reward',
    'economy_transaction_seller',
    'referral_reward', 'referral_bonus', 'referral_reward_referrer',
    'event_hosting_per_attendee', 'event_attendance',
    'message_received', 'new_dm_received', 'reaction_received',
    'share_received', 'link_opened_by_peer'
  ];

  if (callerId !== userId && !CROSS_USER_ACTIONS.includes(action)) {
    throw new functions.https.HttpsError("permission-denied", "Cannot award points to another user for this action.");
  }

  try {
    const batch = db.batch();
    const userPointsRef = db.collection("user_points").doc(userId);

    // Update user balance. We use a NESTED-map increment under
    // `lifetimeEarnings` rather than the dot-notation key
    // `"lifetimeEarnings.<action>"` because `set({merge:true})` does not
    // interpret dotted keys as nested-field paths — it stores the dot as
    // part of a literal top-level field name. The nested-map form below
    // produces a real `lifetimeEarnings.<action>` field that the app can
    // read as `lifetimeEarnings['<action>']`.
    batch.set(userPointsRef, {
      totalPoints: admin.firestore.FieldValue.increment(points),
      availablePoints: admin.firestore.FieldValue.increment(points),
      lastUpdated: admin.firestore.FieldValue.serverTimestamp(),
      lifetimeEarnings: {
        [action]: admin.firestore.FieldValue.increment(points),
      },
    }, { merge: true });

    // Record transaction
    const txRef = db.collection("points_transactions").doc();
    batch.set(txRef, {
      userId,
      type: "earn",
      action,
      points,
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
      metadata: metadata || {},
      awardedBy: callerId,
    });

    // Treasury distribution (unless explicitly skipped)
    if (!skipTreasury) {
      // 2x expansion: user gets `points`, system mints `2 * points` total
      const totalMinted = points * 2;
      // 10% of TOTAL (not 10% of user points) → base-10 SAFT alignment
      const unit = Math.floor(totalMinted * 0.10); // 10% of total per treasury

      // System treasuries (Founders 10% + Liquidity 10% + Burn 10%)
      batch.set(db.collection("system_stats").doc("treasury"), {
        foundersPoints: admin.firestore.FieldValue.increment(unit),
        liquidityPoints: admin.firestore.FieldValue.increment(unit),
        burnedPoints: admin.firestore.FieldValue.increment(unit),
        lastUpdated: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });

      // Global supply tracking
      batch.set(db.collection("system_stats").doc("dsp_supply"), {
        totalMinted: admin.firestore.FieldValue.increment(totalMinted),
        lastUpdated: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });

      // Governance docs for system treasuries
      batch.set(db.collection("governance").doc("founders"), {
        id: "founders",
        name: "Founders & Core Team",
        type: "system",
        treasuryBalance: admin.firestore.FieldValue.increment(unit),
        title: "Founders Treasury",
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });

      batch.set(db.collection("governance").doc("liquidity"), {
        id: "liquidity",
        name: "Liquidity (DEX)",
        type: "system",
        treasuryBalance: admin.firestore.FieldValue.increment(unit),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });

      batch.set(db.collection("governance").doc("burn"), {
        id: "burn",
        name: "Deflationary Burn",
        type: "system",
        walletAddress: "0x000000000000000000000000000000000000dEaD",
        walletType: "burn",
        treasuryBalance: admin.firestore.FieldValue.increment(unit),
        title: "Burn Treasury",
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });

      // ── Community treasury distribution (remaining 20% of total) ──
      // Look up user's community memberships
      if (unit > 0) {
        try {
          const userDoc = await db.collection("users").doc(userId).get();
          if (userDoc.exists) {
            const memberships = userDoc.data().communityMemberships || [];

            const findMembership = (prefix) =>
              memberships.find((id) => id.startsWith(prefix)) || "";

            const homeContinent = findMembership("home_continent_");
            const homeCountry = findMembership("home_country_");
            const homeState = findMembership("home_state_");
            const homeCity = findMembership("home_city_");
            const hostContinent = findMembership("host_continent_");
            const hostCountry = findMembership("host_country_");
            const hostState = findMembership("host_state_");
            const hostCity = findMembership("host_city_");

            // Build allocation map: communityId -> fraction of unit
            const fractions = {};
            const addSlot = (id, fraction) => {
              const targetId = id || "global_community";
              fractions[targetId] = (fractions[targetId] || 0) + fraction;
            };

            // Global: always full unit
            addSlot("global_community", 1.0);

            // Home hierarchy
            addSlot(homeContinent, 1.0);
            if (homeState) {
              addSlot(homeCountry, 0.5);
              addSlot(homeState, 0.5);
            } else {
              addSlot(homeCountry, 1.0);
            }
            addSlot(homeCity, 1.0);

            // Host hierarchy
            addSlot(hostContinent, 1.0);
            if (hostState) {
              addSlot(hostCountry, 0.5);
              addSlot(hostState, 0.5);
            } else {
              addSlot(hostCountry, 1.0);
            }
            addSlot(hostCity, 1.0);

            // Distribute to each community
            for (const [commId, fraction] of Object.entries(fractions)) {
              const slotUnit = Math.round(unit * fraction);
              const slotBasis = Math.round(points * fraction);

              // Community treasury subcollection
              const tRef = db.collection("communities").doc(commId)
                .collection("treasury").doc("current");
              batch.set(tRef, {
                cumulativeEarnings: admin.firestore.FieldValue.increment(slotBasis + slotUnit),
                memberPoints: admin.firestore.FieldValue.increment(slotBasis),
                points: admin.firestore.FieldValue.increment(slotUnit),
                awardedBalance: admin.firestore.FieldValue.increment(slotUnit),
                updatedAt: admin.firestore.FieldValue.serverTimestamp(),
              }, { merge: true });

              // Mirror to top-level community doc
              batch.set(db.collection("communities").doc(commId), {
                cumulativeEarnings: admin.firestore.FieldValue.increment(slotBasis + slotUnit),
                memberPoints: admin.firestore.FieldValue.increment(slotBasis),
                points: admin.firestore.FieldValue.increment(slotUnit),
                awardedBalance: admin.firestore.FieldValue.increment(slotUnit),
                updatedAt: admin.firestore.FieldValue.serverTimestamp(),
              }, { merge: true });

              // Governance doc (maps community -> governance unit)
              const govId = commId === "global_community"
                ? "global_community"
                : (commId.includes("_") ? commId.substring(commId.indexOf("_") + 1) : commId);
              batch.set(db.collection("governance").doc(govId), {
                id: govId,
                communityId: commId,
                type: "community",
                treasuryBalance: admin.firestore.FieldValue.increment(slotUnit),
                updatedAt: admin.firestore.FieldValue.serverTimestamp(),
              }, { merge: true });
            }
          }
        } catch (communityErr) {
          // Don't fail the whole award if community distribution fails
          console.warn(`[awardPoints] Community distribution warning: ${communityErr.message}`);
        }
      }
    }

    await batch.commit();

    return { success: true, points, action };
  } catch (error) {
    console.error(`[awardPoints] Error:`, error.message);
    throw new functions.https.HttpsError("internal", `Failed to award points: ${error.message}`);
  }
});

/**
 * deductPoints — Deducts DSP points from a user.
 * Used for penalties, burns, and value sinks.
 * Supports cross-user deductions (e.g. spam reporter penalizing spammer)
 * via a trusted-action whitelist.
 *
 * @param {string} userId — Target user to deduct from (defaults to caller if omitted)
 * @param {number} points — Points to deduct
 * @param {string} action — Action type (e.g. 'trust_penalty', 'transfer_burn')
 * @param {object} metadata — Optional metadata
 */
exports.deductPoints = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Must be authenticated.");
  }

  const callerId = context.auth.uid;
  // Support cross-user: if userId is provided, deduct from that user; otherwise deduct from caller
  const userId = data.userId || callerId;
  const { points, action, metadata } = data;

  if (!points || !action) {
    throw new functions.https.HttpsError("invalid-argument", "points and action are required.");
  }
  if (typeof points !== "number" || points <= 0) {
    throw new functions.https.HttpsError("invalid-argument", "Points must be positive.");
  }

  // Cross-user deduction security: only whitelisted penalty actions
  const CROSS_USER_DEDUCT_ACTIONS = [
    'spam_report_penalty', 'relationship_rejected_penalty',
    'blocked_by_milestone', 'cumulative_block_penalty',
    'cumulative_flag_penalty', 'fake_verification_penalty',
    'confirmed_fraud_penalty', 'vouching_bad_actor_penalty',
    'vouch_consensus_disagree',
    'event_no_show_penalty', 'misinformation_penalty',
    'deceptive_org_submission_penalty', 'unresponsive_liaison_penalty',
    'chat_ad_penalty', 'poct_blocked_by_milestone',
  ];

  if (callerId !== userId) {
    // Allow partial matches for level-based penalties (e.g. cumulative_block_penalty_level_1)
    const isAllowed = CROSS_USER_DEDUCT_ACTIONS.some((allowed) =>
      action === allowed || action.startsWith(allowed));
    if (!isAllowed) {
      throw new functions.https.HttpsError("permission-denied", "Cannot deduct points from another user for this action.");
    }
  }

  try {
    // Verify user has enough balance
    const userPointsDoc = await db.collection("user_points").doc(userId).get();
    if (!userPointsDoc.exists) {
      throw new functions.https.HttpsError("not-found", "User points not found.");
    }

    const currentBalance = userPointsDoc.data().availablePoints || 0;
    if (currentBalance < points) {
      // For penalties, clamp to available balance instead of failing
      // This prevents penalties from being silently skipped
      console.warn(`[deductPoints] User ${userId} has ${currentBalance} but penalty is ${points}. Clamping.`);
    }

    const effectiveDeduction = Math.min(points, currentBalance);
    if (effectiveDeduction <= 0) {
      return { success: true, deducted: 0, action, reason: "no_balance" };
    }

    const batch = db.batch();

    // Deduct from target user
    batch.update(db.collection("user_points").doc(userId), {
      availablePoints: admin.firestore.FieldValue.increment(-effectiveDeduction),
      lastUpdated: admin.firestore.FieldValue.serverTimestamp(),
    });

    // Record transaction
    const txRef = db.collection("points_transactions").doc();
    batch.set(txRef, {
      userId,
      type: "spend",
      action,
      points: -effectiveDeduction,
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
      metadata: metadata || {},
      deductedBy: callerId,
    });

    // Record as burned utility
    batch.set(db.collection("system_stats").doc("treasury"), {
      totalInternalGdp: admin.firestore.FieldValue.increment(effectiveDeduction),
      totalBurnedUtility: admin.firestore.FieldValue.increment(effectiveDeduction),
      lastUpdated: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });

    await batch.commit();

    return { success: true, deducted: effectiveDeduction, action };
  } catch (error) {
    if (error instanceof functions.https.HttpsError) throw error;
    console.error(`[deductPoints] Error:`, error.message);
    throw new functions.https.HttpsError("internal", `Failed to deduct points: ${error.message}`);
  }
});

/**
 * Helper to distribute 1:1 Ubuntu Protocol matching supply for an awarded DSP amount.
 * When a user receives `userPointsAmount` DSP, the system mints an equal matching supply (2x total)
 * and distributes it:
 *   - 10% to Founders Treasury
 *   - 10% to Liquidity Treasury (Aerodrome DEX)
 *   - 10% Deflationary Burn
 *   - 70% split across the user's dual geographic community slots (and global community)
 */
async function distributeUbuntuMatchingSupply(batch, userId, userPointsAmount, now, reason = "ubuntu_match") {
  const totalMinted = userPointsAmount * 2; // 1:1 match
  const unit = Math.round(totalMinted * 0.10); // 10% of total (20% of userPointsAmount)
  const points = userPointsAmount;

  // 1. Supply increment
  batch.set(db.collection("system_stats").doc("dsp_supply"), {
    totalMinted: admin.firestore.FieldValue.increment(totalMinted),
    lastUpdated: now,
  }, { merge: true });

  // 2. System stats treasury
  batch.set(db.collection("system_stats").doc("treasury"), {
    foundersPoints: admin.firestore.FieldValue.increment(unit),
    liquidityPoints: admin.firestore.FieldValue.increment(unit),
    burnedPoints: admin.firestore.FieldValue.increment(unit),
    lastUpdated: now,
  }, { merge: true });

  // 3. Governance docs
  batch.set(db.collection("governance").doc("founders"), {
    id: "founders",
    name: "Founders & Core Team",
    type: "system",
    treasuryBalance: admin.firestore.FieldValue.increment(unit),
    title: "Founders Treasury",
    updatedAt: now,
  }, { merge: true });

  batch.set(db.collection("governance").doc("liquidity"), {
    id: "liquidity",
    name: "Liquidity (DEX)",
    type: "system",
    treasuryBalance: admin.firestore.FieldValue.increment(unit),
    updatedAt: now,
  }, { merge: true });

  // 4. Dual geographic community slots
  try {
    const userDoc = await db.collection("users").doc(userId).get();
    if (userDoc.exists) {
      const memberships = userDoc.data().communityMemberships || [];
      const findMembership = (prefix) => memberships.find((id) => id.startsWith(prefix)) || "";

      const homeContinent = findMembership("home_continent_");
      const homeCountry = findMembership("home_country_");
      const homeState = findMembership("home_state_");
      const homeCity = findMembership("home_city_");
      const hostContinent = findMembership("host_continent_");
      const hostCountry = findMembership("host_country_");
      const hostState = findMembership("host_state_");
      const hostCity = findMembership("host_city_");

      const fractions = {};
      const addSlot = (id, fraction) => {
        const targetId = id || "global_community";
        fractions[targetId] = (fractions[targetId] || 0) + fraction;
      };

      addSlot("global_community", 1.0);

      // Home hierarchy
      addSlot(homeContinent, 1.0);
      if (homeState) {
        addSlot(homeCountry, 0.5);
        addSlot(homeState, 0.5);
      } else {
        addSlot(homeCountry, 1.0);
      }
      addSlot(homeCity, 1.0);

      // Host hierarchy
      addSlot(hostContinent, 1.0);
      if (hostState) {
        addSlot(hostCountry, 0.5);
        addSlot(hostState, 0.5);
      } else {
        addSlot(hostCountry, 1.0);
      }
      addSlot(hostCity, 1.0);

      for (const [commId, fraction] of Object.entries(fractions)) {
        const slotUnit = Math.round(unit * fraction);
        const slotBasis = Math.round(points * fraction);

        const tRef = db.collection("communities").doc(commId)
          .collection("treasury").doc("current");
        batch.set(tRef, {
          cumulativeEarnings: admin.firestore.FieldValue.increment(slotBasis + slotUnit),
          memberPoints: admin.firestore.FieldValue.increment(slotBasis),
          points: admin.firestore.FieldValue.increment(slotUnit),
          awardedBalance: admin.firestore.FieldValue.increment(slotUnit),
          updatedAt: now,
        }, { merge: true });

        batch.set(db.collection("communities").doc(commId), {
          cumulativeEarnings: admin.firestore.FieldValue.increment(slotBasis + slotUnit),
          memberPoints: admin.firestore.FieldValue.increment(slotBasis),
          points: admin.firestore.FieldValue.increment(slotUnit),
          awardedBalance: admin.firestore.FieldValue.increment(slotUnit),
          updatedAt: now,
        }, { merge: true });

        const govId = commId === "global_community"
          ? "global_community"
          : (commId.includes("_") ? commId.substring(commId.indexOf("_") + 1) : commId);
        batch.set(db.collection("governance").doc(govId), {
          id: govId,
          communityId: commId,
          type: "community",
          treasuryBalance: admin.firestore.FieldValue.increment(slotUnit),
          updatedAt: now,
        }, { merge: true });
      }
    }
  } catch (commErr) {
    console.warn(`[distributeUbuntuMatchingSupply] Community distribution warning for ${userId}: ${commErr.message}`);
  }
}

/**
 * initializeUserPoints — Sets up a new user's points document with a 10,000 DSP
 * welcome bonus and distributes the 1:1 Ubuntu Protocol matching supply to
 * community and system treasuries.
 * Called once during signup after communities are provisioned.
 * Bots/unverified accounts with 0–10 PCT have 0% conversion efficiency at TGE
 * (100% of their DSP is burned), protecting token value while giving real
 * new members immediate personal & community DSP visibility.
 */
exports.initializeUserPoints = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Must be authenticated.");
  }

  const userId = context.auth.uid;
  const WELCOME_BONUS = 10000;

  try {
    const userPointsRef = db.collection("user_points").doc(userId);
    const doc = await userPointsRef.get();
    const docData = doc.exists ? doc.data() : null;

    // Already fully initialized with welcome bonus
    if (doc.exists && docData && docData.signupDate && docData.userId && docData.lifetimeEarnings?.welcome_bonus) {
      return { success: true, alreadyInitialized: true };
    }

    // Fetch home country code from users collection
    const userDoc = await db.collection("users").doc(userId).get();
    const countryCode = userDoc.exists ? (userDoc.data().homeCountryCode || null) : null;

    const batch = db.batch();
    const now = admin.firestore.FieldValue.serverTimestamp();

    if (!doc.exists) {
      // Fresh user — full initialization with 10,000 DSP welcome bonus
      batch.set(userPointsRef, {
        userId,
        totalPoints: WELCOME_BONUS,
        availablePoints: WELCOME_BONUS,
        currentStreak: 0,
        dailyMessageCount: 0,
        dailyShareCount: 0,
        dailyCommunitiesMessaged: [],
        completedExplorationActions: [],
        signupDate: now,
        lastUpdated: now,
        verifiedCount: 0,
        familyConnectionCount: 0,
        qrConnectionCount: 0,
        trustScore: 0,
        tgeHistory: [],
        lifetimeEarnings: { welcome_bonus: WELCOME_BONUS },
        ...(countryCode ? { homeCountryCode: countryCode } : {}),
      });
    } else {
      // Partial doc — backfill missing fields + award welcome bonus if missing
      const existingLifetime = docData.lifetimeEarnings || {};
      const welcomeBonusMissing = !existingLifetime.welcome_bonus;
      const bonusToAdd = welcomeBonusMissing ? WELCOME_BONUS : 0;

      const updates = {
        userId,
        signupDate: docData.signupDate || now,
        currentStreak: docData.currentStreak || 0,
        dailyMessageCount: docData.dailyMessageCount || 0,
        dailyShareCount: docData.dailyShareCount || 0,
        dailyCommunitiesMessaged: docData.dailyCommunitiesMessaged || [],
        completedExplorationActions: docData.completedExplorationActions || [],
        trustScore: docData.trustScore || 0,
        tgeHistory: docData.tgeHistory || [],
        verifiedCount: docData.verifiedCount || 0,
        familyConnectionCount: docData.familyConnectionCount || 0,
        qrConnectionCount: docData.qrConnectionCount || 0,
        lastUpdated: now,
      };

      if (countryCode) updates.homeCountryCode = countryCode;

      if (bonusToAdd > 0) {
        updates.totalPoints = (docData.totalPoints || 0) + bonusToAdd;
        updates.availablePoints = (docData.availablePoints || 0) + bonusToAdd;
        updates.lifetimeEarnings = {
          ...existingLifetime,
          welcome_bonus: bonusToAdd,
        };
      }

      batch.set(userPointsRef, updates, { merge: true });
    }

    // Record welcome bonus transaction & 1:1 Ubuntu matching supply if not yet awarded
    const existingLifetime = docData ? (docData.lifetimeEarnings || {}) : {};
    const shouldAwardBonus = !doc.exists || !existingLifetime.welcome_bonus;

    if (shouldAwardBonus) {
      const txRef = db.collection("points_transactions").doc();
      batch.set(txRef, {
        userId,
        type: "earn",
        action: "welcome_bonus",
        points: WELCOME_BONUS,
        timestamp: now,
        metadata: { description: "Welcome to Diaspora!" },
      });

      await distributeUbuntuMatchingSupply(batch, userId, WELCOME_BONUS, now, "welcome_bonus_match");
    }

    await batch.commit();

    return { success: true, welcomeBonusAwarded: shouldAwardBonus };
  } catch (error) {
    console.error(`[initializeUserPoints] Error:`, error.message);
    throw new functions.https.HttpsError("internal", `Failed to initialize: ${error.message}`);
  }
});

/**
 * getOrCreateReferralCode — Returns the authenticated user's referral code,
 * generating and storing a unique one in `referral_codes/{code}` if none exists.
 */
exports.getOrCreateReferralCode = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Must be authenticated.");
  }

  const userId = context.auth.uid;

  try {
    const existingSnap = await db
      .collection("referral_codes")
      .where("userId", "==", userId)
      .limit(1)
      .get();

    if (!existingSnap.empty) {
      const existingData = existingSnap.docs[0].data();
      const existingCode = existingData.code || existingSnap.docs[0].id;
      await db.collection("users").doc(userId).set({ referralCode: existingCode }, { merge: true });
      return { success: true, code: existingCode };
    }

    const userDoc = await db.collection("users").doc(userId).get();
    const userData = userDoc.exists ? userDoc.data() : {};

    const rawFirstName = String(data?.firstName || userData.firstName || "MEMBER")
      .trim()
      .toUpperCase()
      .replace(/[^A-Z0-9]/g, "");
    const prefixName = (rawFirstName || "MEMBER").slice(0, 12);

    const rawCountry = String(data?.countryCode || userData.homeCountryCode || userData.hostCountryCode || "GL")
      .trim()
      .toUpperCase()
      .replace(/[^A-Z]/g, "");
    const countryCode = (rawCountry || "GL").slice(0, 2);

    const chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
    let code = "";
    let isUnique = false;

    for (let attempt = 0; attempt < 10; attempt++) {
      let rand = "";
      for (let i = 0; i < 4; i++) {
        rand += chars.charAt(Math.floor(Math.random() * chars.length));
      }
      code = `${prefixName}-${countryCode}-${rand}`;
      const codeDoc = await db.collection("referral_codes").doc(code).get();
      if (!codeDoc.exists) {
        isUnique = true;
        break;
      }
    }

    if (!isUnique) {
      throw new functions.https.HttpsError("internal", "Could not generate a unique referral code.");
    }

    await db.collection("referral_codes").doc(code).set({
      code,
      userId,
      firstName: userData.firstName || data?.firstName || "",
      countryCode,
      usedCount: 0,
      createdAt: new Date().toISOString(),
    });
    await db.collection("users").doc(userId).set({ referralCode: code }, { merge: true });

    return { success: true, code };
  } catch (error) {
    if (error instanceof functions.https.HttpsError) throw error;
    console.error(`[getOrCreateReferralCode] Error:`, error.message);
    throw new functions.https.HttpsError("internal", `Failed to get/create referral code: ${error.message}`);
  }
});

/**
 * redeemReferralCode — Validates a referral code for a newly signed-up user and
 * awards 1,000 DSP (plus 1:1 Ubuntu matching supply) to the referrer who invited them.
 */
exports.redeemReferralCode = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Must be authenticated.");
  }

  const refereeId = context.auth.uid;
  const rawCode = String(data?.code || "").trim().toUpperCase();
  if (!rawCode) {
    throw new functions.https.HttpsError("invalid-argument", "Referral code is required.");
  }

  const REFERRAL_BONUS = 1000;

  try {
    // 1. Resolve referrer from referral_codes/{code} or direct userId fallback
    let codeDoc = await db.collection("referral_codes").doc(rawCode).get();
    let referrerId = null;
    let resolvedCode = rawCode;

    if (codeDoc.exists) {
      referrerId = codeDoc.data().userId;
    } else {
      // Fallback: check if rawCode is a direct UID (e.g., from older share links)
      const userByUid = await db.collection("users").doc(rawCode).get();
      if (userByUid.exists) {
        referrerId = userByUid.id;
      }
    }

    if (!referrerId) {
      throw new functions.https.HttpsError("not-found", "Invalid referral code.");
    }

    if (referrerId === refereeId) {
      throw new functions.https.HttpsError("failed-precondition", "Cannot use your own referral code.");
    }

    // 2. Prevent duplicate redemption by the same user
    const refereeDocRef = db.collection("users").doc(refereeId);
    const refereeDoc = await refereeDocRef.get();
    if (refereeDoc.exists && refereeDoc.data().referredBy) {
      return {
        success: true,
        alreadyRedeemed: true,
        referrerId: refereeDoc.data().referredBy,
      };
    }

    const batch = db.batch();
    const now = admin.firestore.FieldValue.serverTimestamp();

    // Mark referee as referred
    batch.set(refereeDocRef, {
      referredBy: referrerId,
      referredWithCode: resolvedCode,
      referredAt: now,
    }, { merge: true });

    // Increment referral code usage counter if codeDoc exists
    if (codeDoc.exists) {
      batch.update(codeDoc.ref, {
        usedCount: admin.firestore.FieldValue.increment(1),
        lastUsedAt: now,
      });
    }

    // 3. Award 1,000 DSP to the referrer + 1:1 Ubuntu matching supply
    const referrerPointsRef = db.collection("user_points").doc(referrerId);
    batch.set(referrerPointsRef, {
      totalPoints: admin.firestore.FieldValue.increment(REFERRAL_BONUS),
      availablePoints: admin.firestore.FieldValue.increment(REFERRAL_BONUS),
      lastUpdated: now,
      lifetimeEarnings: {
        referral_reward_referrer: admin.firestore.FieldValue.increment(REFERRAL_BONUS),
      },
    }, { merge: true });

    const txRef = db.collection("points_transactions").doc();
    batch.set(txRef, {
      userId: referrerId,
      type: "earn",
      action: "referral_reward_referrer",
      points: REFERRAL_BONUS,
      timestamp: now,
      metadata: {
        referredUserId: refereeId,
        code: resolvedCode,
        description: "Referral Bonus — Invited a new member",
      },
    });

    await distributeUbuntuMatchingSupply(
      batch,
      referrerId,
      REFERRAL_BONUS,
      now,
      "referral_reward_referrer_match"
    );

    await batch.commit();

    return {
      success: true,
      referrerId,
      code: resolvedCode,
      pointsAwarded: REFERRAL_BONUS,
    };
  } catch (error) {
    if (error instanceof functions.https.HttpsError) throw error;
    console.error(`[redeemReferralCode] Error:`, error.message);
    throw new functions.https.HttpsError("internal", `Failed to redeem referral code: ${error.message}`);
  }
});

/**
 * awardMessagePoints — Awards DSP for sending messages with daily cap (100/day).
 * Uses a transaction to atomically read-check-update the daily counter.
 */
exports.awardMessagePoints = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Must be authenticated.");
  }

  const userId = context.auth.uid;
  const { points, multiplier } = data;

  if (!points || typeof points !== "number" || points <= 0) {
    throw new functions.https.HttpsError("invalid-argument", "Valid points amount required.");
  }

  const effectiveMultiplier = multiplier || 1;

  try {
    let awarded = false;

    await db.runTransaction(async (transaction) => {
      const userPointsRef = db.collection("user_points").doc(userId);
      const userDocRef = db.collection("users").doc(userId);

      // ── All reads FIRST (Firestore requirement) ──
      const snapshot = await transaction.get(userPointsRef);
      const msgUserDoc = await transaction.get(userDocRef);

      if (!snapshot.exists) return;

      const docData = snapshot.data();
      const now = new Date();
      const lastUpdated = docData.lastUpdated ? docData.lastUpdated.toDate() : null;

      let dailyCount = docData.dailyMessageCount || 0;
      if (!lastUpdated || lastUpdated.getDate() !== now.getDate() ||
        lastUpdated.getMonth() !== now.getMonth() ||
        lastUpdated.getFullYear() !== now.getFullYear()) {
        dailyCount = 0;
      }

      if (dailyCount >= 100) return; // Daily cap reached

      const pointsToAward = points * effectiveMultiplier;

      // ── All writes AFTER reads ──

      transaction.update(userPointsRef, {
        totalPoints: admin.firestore.FieldValue.increment(pointsToAward),
        availablePoints: admin.firestore.FieldValue.increment(pointsToAward),
        dailyMessageCount: dailyCount + 1,
        lastUpdated: admin.firestore.FieldValue.serverTimestamp(),
        "lifetimeEarnings.daily_message": admin.firestore.FieldValue.increment(pointsToAward),
      });

      // Record transaction
      const txRef = db.collection("points_transactions").doc();
      transaction.set(txRef, {
        userId,
        type: "earn",
        action: "message_sent",
        points: pointsToAward,
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
      });

      // Treasury distribution: 10% of TOTAL each to founders, liquidity, burn
      const unit = Math.floor(pointsToAward * 0.20); // 10% of total (points × 2 × 0.10)
      if (unit > 0) {
        transaction.set(db.collection("system_stats").doc("treasury"), {
          foundersPoints: admin.firestore.FieldValue.increment(unit),
          liquidityPoints: admin.firestore.FieldValue.increment(unit),
          burnedPoints: admin.firestore.FieldValue.increment(unit),
          lastUpdated: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });

        // Governance docs for system treasuries
        transaction.set(db.collection("governance").doc("founders"), {
          id: "founders", name: "Founders & Core Team", type: "system",
          treasuryBalance: admin.firestore.FieldValue.increment(unit),
          title: "Founders Treasury",
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });

        transaction.set(db.collection("governance").doc("liquidity"), {
          id: "liquidity", name: "Liquidity (DEX)", type: "system",
          treasuryBalance: admin.firestore.FieldValue.increment(unit),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });
      }

      // 2x expansion
      transaction.set(db.collection("system_stats").doc("dsp_supply"), {
        totalMinted: admin.firestore.FieldValue.increment(pointsToAward * 2),
        lastUpdated: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });

      // Community treasury distribution (using pre-read msgUserDoc)
      if (unit > 0 && msgUserDoc.exists) {
        const memberships = msgUserDoc.data().communityMemberships || [];
        const findMembership = (prefix) =>
          memberships.find((id) => id.startsWith(prefix)) || "";

        const fractions = {};
        const addSlot = (id, fraction) => {
          const targetId = id || "global_community";
          fractions[targetId] = (fractions[targetId] || 0) + fraction;
        };
        addSlot("global_community", 1.0);
        const homeContinent = findMembership("home_continent_");
        const homeCountry = findMembership("home_country_");
        const homeState = findMembership("home_state_");
        const homeCity = findMembership("home_city_");
        const hostContinent = findMembership("host_continent_");
        const hostCountry = findMembership("host_country_");
        const hostState = findMembership("host_state_");
        const hostCity = findMembership("host_city_");
        addSlot(homeContinent, 1.0);
        if (homeState) { addSlot(homeCountry, 0.5); addSlot(homeState, 0.5); }
        else { addSlot(homeCountry, 1.0); }
        addSlot(homeCity, 1.0);
        addSlot(hostContinent, 1.0);
        if (hostState) { addSlot(hostCountry, 0.5); addSlot(hostState, 0.5); }
        else { addSlot(hostCountry, 1.0); }
        addSlot(hostCity, 1.0);

        for (const [commId, fraction] of Object.entries(fractions)) {
          const slotUnit = Math.round(unit * fraction);
          const slotBasis = Math.round(pointsToAward * fraction);
          const tRef = db.collection("communities").doc(commId).collection("treasury").doc("current");
          transaction.set(tRef, {
            cumulativeEarnings: admin.firestore.FieldValue.increment(slotBasis + slotUnit),
            memberPoints: admin.firestore.FieldValue.increment(slotBasis),
            points: admin.firestore.FieldValue.increment(slotUnit),
            awardedBalance: admin.firestore.FieldValue.increment(slotUnit),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          }, { merge: true });
          transaction.set(db.collection("communities").doc(commId), {
            cumulativeEarnings: admin.firestore.FieldValue.increment(slotBasis + slotUnit),
            memberPoints: admin.firestore.FieldValue.increment(slotBasis),
            points: admin.firestore.FieldValue.increment(slotUnit),
            awardedBalance: admin.firestore.FieldValue.increment(slotUnit),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          }, { merge: true });
          const govId = commId === "global_community"
            ? "global_community"
            : (commId.includes("_") ? commId.substring(commId.indexOf("_") + 1) : commId);
          transaction.set(db.collection("governance").doc(govId), {
            id: govId, communityId: commId, type: "community",
            treasuryBalance: admin.firestore.FieldValue.increment(slotUnit),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          }, { merge: true });
        }
      }

      awarded = true;
    });

    return { success: true, awarded };
  } catch (error) {
    console.error(`[awardMessagePoints] Error:`, error.message);
    throw new functions.https.HttpsError("internal", `Failed: ${error.message}`);
  }
});

/**
 * awardExplorationPoints — One-time exploration action rewards.
 * Checks completedExplorationActions to prevent duplicate awards.
 */
exports.awardExplorationPoints = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Must be authenticated.");
  }

  const userId = context.auth.uid;
  const { actionId, points, metadata } = data;

  if (!actionId || !points || typeof points !== "number") {
    throw new functions.https.HttpsError("invalid-argument", "actionId and points required.");
  }

  try {
    await db.runTransaction(async (transaction) => {
      const userPointsRef = db.collection("user_points").doc(userId);
      const userDocRef = db.collection("users").doc(userId);

      // ── All reads FIRST (Firestore requirement) ──
      const snapshot = await transaction.get(userPointsRef);
      const expUserDoc = await transaction.get(userDocRef);

      if (snapshot.exists) {
        const docData = snapshot.data();
        const completedActions = docData.completedExplorationActions || [];
        if (completedActions.includes(actionId)) {
          throw new functions.https.HttpsError("already-exists", "Action already completed.");
        }
      }

      // ── All writes AFTER reads ──

      // Update user points
      transaction.set(userPointsRef, {
        totalPoints: admin.firestore.FieldValue.increment(points),
        availablePoints: admin.firestore.FieldValue.increment(points),
        lastUpdated: admin.firestore.FieldValue.serverTimestamp(),
        completedExplorationActions: admin.firestore.FieldValue.arrayUnion(actionId),
        "lifetimeEarnings.exploration_reward": admin.firestore.FieldValue.increment(points),
      }, { merge: true });

      // Record transaction
      const txRef = db.collection("points_transactions").doc();
      transaction.set(txRef, {
        userId,
        type: "earn",
        action: `exploration_${actionId}`,
        points,
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
        metadata: metadata || {},
      });

      // Treasury: 10% of TOTAL each to founders, liquidity, burn
      const unit = Math.floor(points * 0.20); // 10% of total (points × 2 × 0.10)
      if (unit > 0) {
        transaction.set(db.collection("system_stats").doc("treasury"), {
          foundersPoints: admin.firestore.FieldValue.increment(unit),
          liquidityPoints: admin.firestore.FieldValue.increment(unit),
          burnedPoints: admin.firestore.FieldValue.increment(unit),
          lastUpdated: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });

        // Governance docs for system treasuries
        transaction.set(db.collection("governance").doc("founders"), {
          id: "founders", name: "Founders & Core Team", type: "system",
          treasuryBalance: admin.firestore.FieldValue.increment(unit),
          title: "Founders Treasury",
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });

        transaction.set(db.collection("governance").doc("liquidity"), {
          id: "liquidity", name: "Liquidity (DEX)", type: "system",
          treasuryBalance: admin.firestore.FieldValue.increment(unit),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });
      }

      // 2x expansion
      transaction.set(db.collection("system_stats").doc("dsp_supply"), {
        totalMinted: admin.firestore.FieldValue.increment(points * 2),
        lastUpdated: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });

      // Community treasury distribution (using pre-read expUserDoc)
      if (unit > 0 && expUserDoc.exists) {
        const memberships = expUserDoc.data().communityMemberships || [];
        const findMembership = (prefix) =>
          memberships.find((id) => id.startsWith(prefix)) || "";

        const fractions = {};
        const addSlot = (id, fraction) => {
          const targetId = id || "global_community";
          fractions[targetId] = (fractions[targetId] || 0) + fraction;
        };
        addSlot("global_community", 1.0);
        const homeContinent = findMembership("home_continent_");
        const homeCountry = findMembership("home_country_");
        const homeState = findMembership("home_state_");
        const homeCity = findMembership("home_city_");
        const hostContinent = findMembership("host_continent_");
        const hostCountry = findMembership("host_country_");
        const hostState = findMembership("host_state_");
        const hostCity = findMembership("host_city_");
        addSlot(homeContinent, 1.0);
        if (homeState) { addSlot(homeCountry, 0.5); addSlot(homeState, 0.5); }
        else { addSlot(homeCountry, 1.0); }
        addSlot(homeCity, 1.0);
        addSlot(hostContinent, 1.0);
        if (hostState) { addSlot(hostCountry, 0.5); addSlot(hostState, 0.5); }
        else { addSlot(hostCountry, 1.0); }
        addSlot(hostCity, 1.0);

        for (const [commId, fraction] of Object.entries(fractions)) {
          const slotUnit = Math.round(unit * fraction);
          const slotBasis = Math.round(points * fraction);
          const tRef = db.collection("communities").doc(commId).collection("treasury").doc("current");
          transaction.set(tRef, {
            cumulativeEarnings: admin.firestore.FieldValue.increment(slotBasis + slotUnit),
            memberPoints: admin.firestore.FieldValue.increment(slotBasis),
            points: admin.firestore.FieldValue.increment(slotUnit),
            awardedBalance: admin.firestore.FieldValue.increment(slotUnit),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          }, { merge: true });
          transaction.set(db.collection("communities").doc(commId), {
            cumulativeEarnings: admin.firestore.FieldValue.increment(slotBasis + slotUnit),
            memberPoints: admin.firestore.FieldValue.increment(slotBasis),
            points: admin.firestore.FieldValue.increment(slotUnit),
            awardedBalance: admin.firestore.FieldValue.increment(slotUnit),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          }, { merge: true });
          const govId = commId === "global_community"
            ? "global_community"
            : (commId.includes("_") ? commId.substring(commId.indexOf("_") + 1) : commId);
          transaction.set(db.collection("governance").doc(govId), {
            id: govId, communityId: commId, type: "community",
            treasuryBalance: admin.firestore.FieldValue.increment(slotUnit),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          }, { merge: true });
        }
      }
    });

    return { success: true };
  } catch (error) {
    if (error instanceof functions.https.HttpsError) throw error;
    console.error(`[awardExplorationPoints] Error:`, error.message);
    throw new functions.https.HttpsError("internal", `Failed: ${error.message}`);
  }
});

/**
 * awardSharePoints — Awards DSP for sharing content with daily cap (12/day).
 */
exports.awardSharePoints = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Must be authenticated.");
  }

  const userId = context.auth.uid;
  const { points, contentType } = data;

  if (!points || typeof points !== "number" || points <= 0) {
    throw new functions.https.HttpsError("invalid-argument", "Valid points amount required.");
  }

  try {
    let rewarded = false;

    await db.runTransaction(async (transaction) => {
      const userPointsRef = db.collection("user_points").doc(userId);
      const userDocRef = db.collection("users").doc(userId);

      // ── All reads FIRST (Firestore requirement) ──
      const snapshot = await transaction.get(userPointsRef);
      const shareUserDoc = await transaction.get(userDocRef);

      if (!snapshot.exists) return;

      const docData = snapshot.data();
      const now = new Date();
      const lastUpdated = docData.lastUpdated ? docData.lastUpdated.toDate() : null;

      let dailyShareCount = docData.dailyShareCount || 0;
      if (!lastUpdated || lastUpdated.getDate() !== now.getDate() ||
        lastUpdated.getMonth() !== now.getMonth() ||
        lastUpdated.getFullYear() !== now.getFullYear()) {
        dailyShareCount = 0;
      }

      if (dailyShareCount >= 12) return; // Daily cap

      // ── All writes AFTER reads ──

      transaction.update(userPointsRef, {
        totalPoints: admin.firestore.FieldValue.increment(points),
        availablePoints: admin.firestore.FieldValue.increment(points),
        dailyShareCount: dailyShareCount + 1,
        lastUpdated: admin.firestore.FieldValue.serverTimestamp(),
        "lifetimeEarnings.content_shared": admin.firestore.FieldValue.increment(points),
      });

      // Record transaction
      const txRef = db.collection("points_transactions").doc();
      transaction.set(txRef, {
        userId,
        type: "earn",
        action: "content_shared",
        points,
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
        metadata: { contentType: contentType || "unknown" },
      });

      // Treasury: 10% of TOTAL each
      const unit = Math.floor(points * 0.20); // 10% of total (points × 2 × 0.10)
      if (unit > 0) {
        transaction.set(db.collection("system_stats").doc("treasury"), {
          foundersPoints: admin.firestore.FieldValue.increment(unit),
          liquidityPoints: admin.firestore.FieldValue.increment(unit),
          burnedPoints: admin.firestore.FieldValue.increment(unit),
          lastUpdated: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });

        // Governance docs for system treasuries
        transaction.set(db.collection("governance").doc("founders"), {
          id: "founders", name: "Founders & Core Team", type: "system",
          treasuryBalance: admin.firestore.FieldValue.increment(unit),
          title: "Founders Treasury",
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });

        transaction.set(db.collection("governance").doc("liquidity"), {
          id: "liquidity", name: "Liquidity (DEX)", type: "system",
          treasuryBalance: admin.firestore.FieldValue.increment(unit),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });
      }

      // 2x expansion
      transaction.set(db.collection("system_stats").doc("dsp_supply"), {
        totalMinted: admin.firestore.FieldValue.increment(points * 2),
        lastUpdated: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });

      // Community treasury distribution (using pre-read shareUserDoc)
      if (unit > 0 && shareUserDoc.exists) {
        const memberships = shareUserDoc.data().communityMemberships || [];
        const findMembership = (prefix) =>
          memberships.find((id) => id.startsWith(prefix)) || "";

        const fractions = {};
        const addSlot = (id, fraction) => {
          const targetId = id || "global_community";
          fractions[targetId] = (fractions[targetId] || 0) + fraction;
        };
        addSlot("global_community", 1.0);
        const homeContinent = findMembership("home_continent_");
        const homeCountry = findMembership("home_country_");
        const homeState = findMembership("home_state_");
        const homeCity = findMembership("home_city_");
        const hostContinent = findMembership("host_continent_");
        const hostCountry = findMembership("host_country_");
        const hostState = findMembership("host_state_");
        const hostCity = findMembership("host_city_");
        addSlot(homeContinent, 1.0);
        if (homeState) { addSlot(homeCountry, 0.5); addSlot(homeState, 0.5); }
        else { addSlot(homeCountry, 1.0); }
        addSlot(homeCity, 1.0);
        addSlot(hostContinent, 1.0);
        if (hostState) { addSlot(hostCountry, 0.5); addSlot(hostState, 0.5); }
        else { addSlot(hostCountry, 1.0); }
        addSlot(hostCity, 1.0);

        for (const [commId, fraction] of Object.entries(fractions)) {
          const slotUnit = Math.round(unit * fraction);
          const slotBasis = Math.round(points * fraction);
          const tRef = db.collection("communities").doc(commId).collection("treasury").doc("current");
          transaction.set(tRef, {
            cumulativeEarnings: admin.firestore.FieldValue.increment(slotBasis + slotUnit),
            memberPoints: admin.firestore.FieldValue.increment(slotBasis),
            points: admin.firestore.FieldValue.increment(slotUnit),
            awardedBalance: admin.firestore.FieldValue.increment(slotUnit),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          }, { merge: true });
          transaction.set(db.collection("communities").doc(commId), {
            cumulativeEarnings: admin.firestore.FieldValue.increment(slotBasis + slotUnit),
            memberPoints: admin.firestore.FieldValue.increment(slotBasis),
            points: admin.firestore.FieldValue.increment(slotUnit),
            awardedBalance: admin.firestore.FieldValue.increment(slotUnit),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          }, { merge: true });
          const govId = commId === "global_community"
            ? "global_community"
            : (commId.includes("_") ? commId.substring(commId.indexOf("_") + 1) : commId);
          transaction.set(db.collection("governance").doc(govId), {
            id: govId, communityId: commId, type: "community",
            treasuryBalance: admin.firestore.FieldValue.increment(slotUnit),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          }, { merge: true });
        }
      }

      rewarded = true;
    });

    return { success: true, rewarded };
  } catch (error) {
    console.error(`[awardSharePoints] Error:`, error.message);
    throw new functions.https.HttpsError("internal", `Failed: ${error.message}`);
  }
});

/**
 * recordFiatGdp — Records a real-economy transaction's fiat value as GDP output.
 * Writes to system_stats/treasury (blocked for clients) via Admin SDK.
 */
exports.recordFiatGdp = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Must be authenticated.");
  }

  const { amountUsd, activityType, metadata } = data;

  if (!amountUsd || typeof amountUsd !== "number" || amountUsd <= 0) {
    throw new functions.https.HttpsError("invalid-argument", "Valid positive amountUsd required.");
  }
  if (!activityType || typeof activityType !== "string") {
    throw new functions.https.HttpsError("invalid-argument", "activityType string required.");
  }

  // Cap at $1M per transaction for safety
  if (amountUsd > 1000000) {
    throw new functions.https.HttpsError("invalid-argument", "Amount exceeds maximum.");
  }

  try {
    // Global treasury counter (platform-wide, regardless of corridor).
    await db.collection("system_stats").doc("treasury").set({
      totalFiatGdpUsd: admin.firestore.FieldValue.increment(amountUsd),
      lastFiatGdpUpdate: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });

    // Unified corridor roll-up. Derives the corridor from the caller's
    // profile and bumps their chamber's GDP counters. Audit row is
    // written inside the helper (no double-log).
    const callerProfile = (
      await db.collection("users").doc(context.auth.uid).get()
    ).data() || {};
    const { recordCorridorActivity } = require("./corridor_activity");
    await recordCorridorActivity({
      homeCountryCode: callerProfile.homeCountryCode,
      hostCountryCode: callerProfile.hostCountryCode,
      amountUsd,
      activityType,
      actorUid: context.auth.uid,
      metadata: metadata || {},
    });

    return { success: true, amountUsd, activityType };
  } catch (error) {
    console.error(`[recordFiatGdp] Error:`, error.message);
    throw new functions.https.HttpsError("internal", `Failed: ${error.message}`);
  }
});

/**
 * syncTreasuryBalances — Admin-only reconciliation function.
 * Recalculates all treasury balances from source of truth (user_points).
 */
exports.syncTreasuryBalances = functions
  .runWith({ timeoutSeconds: 300, memory: "512MB", secrets: ["BACKEND_SIGNER_PRIVATE_KEY"] })
  .https.onCall(async (data, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError("unauthenticated", "Must be authenticated.");
    }

    // TODO: Add admin role check for production
    const callerId = context.auth.uid;
    console.log(`[syncTreasuryBalances] Triggered by ${callerId}`);

    try {
      const userPointsSnap = await db.collection("user_points").get();
      const usersSnap = await db.collection("users").get();

      const userProfiles = {};
      usersSnap.forEach((doc) => {
        userProfiles[doc.id] = doc.data();
      });

      const communityPointsMap = {};
      const communityBasisMap = {};
      const communityMemberPointsMap = {};
      const communityPCTs = {};

      let totalUserPoints = 0;
      let totalFoundersPoints = 0;
      let totalLiquidityPoints = 0;
      let totalBurnedPoints = 0;

      userPointsSnap.forEach((doc) => {
        const userId = doc.id;
        const pointsData = doc.data();
        const userPoints = pointsData.totalPoints || 0;
        const trustScore = Number(pointsData.trustScore || 0);

        if (userPoints <= 0) return;

        totalUserPoints += userPoints;
        const unit = Math.floor(userPoints * 0.10);

        totalFoundersPoints += unit;
        totalLiquidityPoints += unit;

        // Community hierarchy distribution
        const userMemberships = (userProfiles[userId] || {}).communityMemberships || [];

        const findMembership = (prefix) => {
          const match = userMemberships.find((id) => String(id).startsWith(prefix));
          return match ? String(match) : "";
        };

        const slotFractions = {};

        const addSlot = (id, fraction) => {
          const effectiveId = (!id || id === "") ? "global_community" : id;
          slotFractions[effectiveId] = (slotFractions[effectiveId] || 0) + fraction;
        };

        addSlot("global_community", 1.0);

        // Home hierarchy
        const homeContinent = findMembership("home_continent_");
        const homeCountry = findMembership("home_country_");
        const homeState = findMembership("home_state_");
        const homeCity = findMembership("home_city_");

        addSlot(homeContinent, 1.0);
        if (homeState) {
          addSlot(homeCountry, 0.5);
          addSlot(homeState, 0.5);
        } else {
          addSlot(homeCountry, 1.0);
        }
        addSlot(homeCity, 1.0);

        // Host hierarchy
        const hostContinent = findMembership("host_continent_");
        const hostCountry = findMembership("host_country_");
        const hostState = findMembership("host_state_");
        const hostCity = findMembership("host_city_");

        addSlot(hostContinent, 1.0);
        if (hostState) {
          addSlot(hostCountry, 0.5);
          addSlot(hostState, 0.5);
        } else {
          addSlot(hostCountry, 1.0);
        }
        addSlot(hostCity, 1.0);

        totalBurnedPoints += unit; // Fixed burn

        for (const [cid, fraction] of Object.entries(slotFractions)) {
          const slotUnit = Math.round(unit * fraction);
          const slotBasis = Math.round(userPoints * fraction);

          communityPointsMap[cid] = (communityPointsMap[cid] || 0) + slotUnit;
          communityBasisMap[cid] = (communityBasisMap[cid] || 0) + slotBasis + slotUnit;
          communityMemberPointsMap[cid] = (communityMemberPointsMap[cid] || 0) + slotBasis;
          if (!communityPCTs[cid]) communityPCTs[cid] = [];
          communityPCTs[cid].push(trustScore);
        }
      });

      // Write results in batches (max 500 ops per batch)
      let batch = db.batch();
      let opCount = 0;

      const commitIfNeeded = async () => {
        if (opCount >= 490) {
          await batch.commit();
          batch = db.batch();
          opCount = 0;
        }
      };

      // System treasury
      batch.set(db.collection("system_stats").doc("treasury"), {
        foundersPoints: totalFoundersPoints,
        liquidityPoints: totalLiquidityPoints,
        burnedPoints: totalBurnedPoints,
        lastUpdated: admin.firestore.FieldValue.serverTimestamp(),
        syncedBy: callerId,
      }, { merge: true });
      opCount++;

      // Governance docs
      batch.set(db.collection("governance").doc("founders"), {
        treasuryBalance: totalFoundersPoints,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });
      opCount++;

      batch.set(db.collection("governance").doc("liquidity"), {
        treasuryBalance: totalLiquidityPoints,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });
      opCount++;

      batch.set(db.collection("governance").doc("burn"), {
        id: "burn",
        name: "Deflationary Burn",
        type: "system",
        walletAddress: "0x000000000000000000000000000000000000dEaD",
        walletType: "burn",
        treasuryBalance: totalBurnedPoints,
        title: "Burn Treasury",
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });
      opCount++;

      // Community treasuries
      for (const commId of Object.keys(communityPointsMap)) {
        await commitIfNeeded();

        const pcts = communityPCTs[commId] || [];
        const avgPct = pcts.length > 0 ? pcts.reduce((a, b) => a + b, 0) / pcts.length : 0;

        const treasuryRef = db.collection("communities").doc(commId).collection("treasury").doc("current");
        batch.set(treasuryRef, {
          points: communityPointsMap[commId],
          cumulativeEarnings: communityBasisMap[commId],
          memberPoints: communityMemberPointsMap[commId],
          awardedBalance: communityPointsMap[commId],
          averagePct: avgPct,
          averagePoCT: avgPct,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });
        opCount++;

        await commitIfNeeded();

        // Governance doc
        const govId = commId === "global_community"
          ? "global_community"
          : (commId.includes("_") ? commId.substring(commId.indexOf("_") + 1) : commId);
        batch.set(db.collection("governance").doc(govId), {
          treasuryBalance: communityPointsMap[commId] || 0,
          averagePct: avgPct,
          averagePoCT: avgPct,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });
        opCount++;

        await commitIfNeeded();

        // Mirror to top-level community doc
        batch.set(db.collection("communities").doc(commId), {
          points: communityPointsMap[commId],
          cumulativeEarnings: communityBasisMap[commId],
          memberPoints: communityMemberPointsMap[commId],
          awardedBalance: communityPointsMap[commId] || 0,
          averagePct: avgPct,
          averagePoCT: avgPct,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });
        opCount++;
      }

      await commitIfNeeded();

      // Global supply
      batch.set(db.collection("system_stats").doc("dsp_supply"), {
        totalMinted: Math.round(totalUserPoints * 2.0),
        lastUpdated: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });
      opCount++;

      await batch.commit();

      return {
        success: true,
        totalUserPoints,
        totalFoundersPoints,
        totalLiquidityPoints,
        totalBurnedPoints,
        communitiesProcessed: Object.keys(communityPointsMap).length,
      };
    } catch (error) {
      console.error(`[syncTreasuryBalances] Error:`, error.message);
      throw new functions.https.HttpsError("internal", `Failed: ${error.message}`);
    }
  });

/**
 * retryPendingWelcomeBonuses — heals users whose on-chain welcome bonus
 * failed during initializeUserPoints.
 *
 * The fail-loud refactor of the welcome bonus block (2026-06-02) sets these
 * fields on the user doc whenever the on-chain step doesn't complete:
 *   - tokenWelcomeBonusPending: true
 *   - tokenWelcomeBonusError: <reason>
 *   - tokenWelcomeBonusErrorAt: <timestamp>
 *
 * This function scans for those users and retries each one through the full
 * welcome-bonus distribution path. It's safe to call repeatedly — the V2
 * contract's per-user dedupe will reject double-pay attempts on-chain, and
 * we double-check `tokenWelcomeBonusSent` before invoking.
 *
 * Can be invoked manually for incident response, or scheduled via the
 * client to run periodically (e.g. every 10 minutes). For now it's an
 * admin-only callable so the operator decides when to run it.
 */
exports.retryPendingWelcomeBonuses = functions
  .runWith({ timeoutSeconds: 540, memory: "512MB", secrets: ["BACKEND_SIGNER_PRIVATE_KEY"] })
  .https.onCall(async (data, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError("unauthenticated", "Must be authenticated.");
    }
    // Admin-only — relies on Firebase Auth custom claims
    if (!context.auth.token || context.auth.token.admin !== true) {
      throw new functions.https.HttpsError("permission-denied", "Admin only.");
    }

    // Fail-loud config check BEFORE doing any work
    const { backendSignerKey, tgeControllerAddress, walletFactoryAddress } = assertOnChainConfig(
      "retryPendingWelcomeBonuses",
      ["backendSignerKey", "tgeControllerAddress", "walletFactoryAddress"]
    );

    const dryRun = data && data.dryRun === true;
    const limit = Math.min(Math.max(Number(data && data.limit) || 25, 1), 100);

    // Find pending users
    const pendingSnap = await db.collection("users")
      .where("tokenWelcomeBonusPending", "==", true)
      .limit(limit)
      .get();

    if (pendingSnap.empty) {
      return { ok: true, found: 0, retried: 0, skipped: 0, succeeded: 0, failed: 0, dryRun };
    }

    const results = { ok: true, found: pendingSnap.size, retried: 0, skipped: 0, succeeded: 0, failed: 0, dryRun, items: [] };

    if (dryRun) {
      for (const d of pendingSnap.docs) {
        results.items.push({ uid: d.id, walletAddress: d.data().walletAddress || null, error: d.data().tokenWelcomeBonusError || null });
      }
      return results;
    }

    const RPC_URL = process.env.RPC_URL || "https://mainnet.base.org";
    const provider = new ethers.JsonRpcProvider(RPC_URL);
    const signer = new ethers.Wallet(backendSignerKey, provider);
    const tge = new ethers.Contract(tgeControllerAddress, TGE_CONTROLLER_ABI, signer);
    const factory = new ethers.Contract(
      walletFactoryAddress,
      ["function computeAddress(bytes32 phoneHash) view returns (address)"],
      provider
    );

    for (const doc of pendingSnap.docs) {
      const userId = doc.id;
      const u = doc.data();
      try {
        // Double-check we're not about to double-pay
        if (u.tokenWelcomeBonusSent === true) {
          await db.collection("users").doc(userId).set({
            tokenWelcomeBonusPending: false,
            tokenWelcomeBonusError: admin.firestore.FieldValue.delete(),
          }, { merge: true });
          results.skipped++;
          results.items.push({ uid: userId, status: "already_sent" });
          continue;
        }
        if (!u.walletAddress) {
          results.skipped++;
          results.items.push({ uid: userId, status: "no_wallet_address" });
          continue;
        }

        // Build the distribution exactly like initializeUserPoints does
        const userAmount = ethers.parseUnits("1000", 18);
        const BURN = "0x000000000000000000000000000000000000dEaD";
        const DEPLOYER_FALLBACK = signer.address;

        // Read live treasury wallets from Firestore. Post-2026-06-04 these
        // are Safe addresses, NOT factory-computed smart wallets. Computing
        // from CREATE2 salts here would target the abandoned pre-migration
        // wallets and lose tokens. See [[project-treasury-safe-addresses]].
        const [foundersGov, liquidityGov] = await Promise.all([
          db.collection("governance").doc("founders").get(),
          db.collection("governance").doc("liquidity").get(),
        ]);
        const foundersWallet = (foundersGov.exists && foundersGov.data().walletAddress) || DEPLOYER_FALLBACK;
        const liquidityWallet = (liquidityGov.exists && liquidityGov.data().walletAddress) || DEPLOYER_FALLBACK;
        if (!foundersGov.exists || !foundersGov.data().walletAddress) {
          console.warn("[Token Welcome Bonus retry] Founders wallet not found in Firestore, using deployer fallback");
        }
        if (!liquidityGov.exists || !liquidityGov.data().walletAddress) {
          console.warn("[Token Welcome Bonus retry] Liquidity wallet not found in Firestore, using deployer fallback");
        }

        const treasuryRecipients = [BURN, foundersWallet, liquidityWallet];
        const treasuryAmounts = [
          ethers.parseUnits("100", 18),
          ethers.parseUnits("100", 18),
          ethers.parseUnits("100", 18),
        ];

        // Community slots — same fraction math as the original path
        const memberships = u.communityMemberships || [];
        const find = (prefix) => memberships.find((id) => id.startsWith(prefix)) || "";
        const hcont = find("home_continent_");
        const hcountry = find("home_country_");
        const hstate = find("home_state_");
        const hcity = find("home_city_");
        const xcont = find("host_continent_");
        const xcountry = find("host_country_");
        const xstate = find("host_state_");
        const xcity = find("host_city_");

        const slots = {};
        const addSlot = (id, frac) => {
          const targetId = id || "global_community";
          slots[targetId] = (slots[targetId] || 0) + frac;
        };
        addSlot("global_community", 1);
        addSlot(hcont, 1);
        if (hstate) { addSlot(hcountry, 0.5); addSlot(hstate, 0.5); } else { addSlot(hcountry, 1); }
        addSlot(hcity, 1);
        addSlot(xcont, 1);
        if (xstate) { addSlot(xcountry, 0.5); addSlot(xstate, 0.5); } else { addSlot(xcountry, 1); }
        addSlot(xcity, 1);

        for (const [commId, frac] of Object.entries(slots)) {
          const slotAmount = Math.round(100 * frac);
          if (slotAmount <= 0) continue;
          const salt = ethers.keccak256(ethers.toUtf8Bytes("community:" + commId));
          const wallet = await factory.computeAddress(salt).catch(() => DEPLOYER_FALLBACK);
          treasuryRecipients.push(wallet);
          treasuryAmounts.push(ethers.parseUnits(slotAmount.toString(), 18));
        }

        const merkleRoot = ethers.solidityPackedKeccak256(
          ["address", "uint256", "address[]", "uint256[]"],
          [u.walletAddress, userAmount, treasuryRecipients, treasuryAmounts]
        );

        const tx = await tge.distributeWelcomeBonus(
          u.walletAddress,
          userAmount,
          treasuryRecipients,
          treasuryAmounts,
          merkleRoot
        );
        const receipt = await tx.wait();

        await db.collection("users").doc(userId).set({
          tokenWelcomeBonusSent: true,
          tokenWelcomeBonusTx: receipt.hash,
          tokenWelcomeBonusPending: false,
          tokenWelcomeBonusError: admin.firestore.FieldValue.delete(),
          tokenWelcomeBonusErrorAt: admin.firestore.FieldValue.delete(),
        }, { merge: true });

        results.retried++;
        results.succeeded++;
        results.items.push({ uid: userId, status: "success", txHash: receipt.hash });
      } catch (e) {
        results.retried++;
        results.failed++;
        const msg = (e.message || "unknown").slice(0, 500);
        results.items.push({ uid: userId, status: "failed", error: msg });
        await db.collection("users").doc(userId).set({
          tokenWelcomeBonusError: `retry_failed: ${msg}`,
          tokenWelcomeBonusErrorAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });
      }
    }

    return results;
  });

/**
 * retryPendingTGEDeductions — heals TGE events whose on-chain TX succeeded
 * but whose Firestore DSP deduction failed.
 *
 * Why this matters: `performTGE` calls the on-chain `executeTGE` BEFORE
 * deducting DSP balances in Firestore. If Firestore is briefly unavailable
 * during step 5, the on-chain TX is already mined — users have new $DIASPORA.
 * But the off-chain DSP balance was never deducted, so users would also still
 * see the same DSP points in the app (and could be paid again at the next TGE).
 *
 * This function scans tge_events docs with `status: "tx_complete_dsp_pending"`
 * and replays the deduction batch using the stored `snapshot` array. Idempotent:
 * after the deduction lands, status flips to "complete" and the doc is excluded
 * from future scans.
 *
 * Admin-only callable.
 */
exports.retryPendingTGEDeductions = functions
  .runWith({ timeoutSeconds: 540, memory: "512MB" })
  .https.onCall(async (data, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError("unauthenticated", "Must be authenticated.");
    }
    if (!context.auth.token || context.auth.token.admin !== true) {
      throw new functions.https.HttpsError("permission-denied", "Admin only.");
    }

    const dryRun = data && data.dryRun === true;
    const limit = Math.min(Math.max(Number(data && data.limit) || 10, 1), 50);

    const snap = await db.collection("tge_events")
      .where("status", "==", "tx_complete_dsp_pending")
      .limit(limit)
      .get();

    const results = { ok: true, dryRun, found: snap.size, succeeded: 0, failed: 0, items: [] };
    if (snap.empty) return results;

    for (const doc of snap.docs) {
      const id = doc.id;
      const ev = doc.data();
      try {
        if (!Array.isArray(ev.snapshot) || ev.snapshot.length === 0) {
          results.failed++;
          results.items.push({ id, status: "failed", error: "no_snapshot_array" });
          continue;
        }

        if (dryRun) {
          results.items.push({
            id,
            status: "dry_run",
            epoch: ev.epoch,
            tgeEvent: ev.tgeEvent,
            snapshotSize: ev.snapshot.length,
            txHash: ev.txHash,
          });
          continue;
        }

        const operations = [];
        for (const s of ev.snapshot) {
          if (s.userId) {
            operations.push({
              ref: db.collection("user_points").doc(s.userId),
              data: {
                availablePoints: admin.firestore.FieldValue.increment(-s.dsp),
                lastUpdated: admin.firestore.FieldValue.serverTimestamp(),
              },
            });
          } else if (s.unitId) {
            operations.push({
              ref: db.collection("governance").doc(s.unitId),
              data: {
                treasuryBalance: admin.firestore.FieldValue.increment(-s.dsp),
                updatedAt: admin.firestore.FieldValue.serverTimestamp(),
              },
            });
          }
        }

        const BATCH_SIZE = 400;
        for (let i = 0; i < operations.length; i += BATCH_SIZE) {
          const chunk = operations.slice(i, i + BATCH_SIZE);
          const chunkBatch = db.batch();
          for (const op of chunk) {
            chunkBatch.set(op.ref, op.data, { merge: true });
          }
          await chunkBatch.commit();
        }
        await db.collection("tge_events").doc(id).update({
          status: "complete",
          dspDeductionRetriedAt: admin.firestore.FieldValue.serverTimestamp(),
          dspDeductionError: admin.firestore.FieldValue.delete(),
        });

        results.succeeded++;
        results.items.push({ id, status: "deducted", epoch: ev.epoch, tgeEvent: ev.tgeEvent, txHash: ev.txHash });
      } catch (e) {
        results.failed++;
        const msg = (e.message || "unknown").slice(0, 500);
        results.items.push({ id, status: "failed", error: msg });
      }
    }

    return results;
  });


// V4 trust mechanics: trust rating staking trigger.
exports.onVouchWrite = functions.firestore
  .document("trust_ratings/{ratingId}")
  .onWrite(async (change) => {
    const beforeData = change.before.data();
    const afterData = change.after.data();

    if (!afterData) {
      if (beforeData && beforeData.remainingStake > 0) {
        await db.collection("user_points").doc(beforeData.fromUserId).set({
          availablePoints: admin.firestore.FieldValue.increment(beforeData.remainingStake),
          lastUpdated: admin.firestore.FieldValue.serverTimestamp()
        }, { merge: true });

        await db.collection("points_transactions").doc().set({
          userId: beforeData.fromUserId,
          points: beforeData.remainingStake,
          amount: beforeData.remainingStake,
          action: "trust_stake_refund",
          type: "earn",
          timestamp: admin.firestore.FieldValue.serverTimestamp()
        });
      }
      if (beforeData && beforeData.toUserId) {
        try {
          await syncProfileMilestoneAndTrust(beforeData.toUserId);
        } catch (err) {
          console.warn(`[onVouchWrite] syncProfileMilestoneAndTrust warning on delete: ${err.message}`);
        }
      }
      return null;
    }

    const fromUserId = afterData.fromUserId;
    const toUserId = afterData.toUserId;
    const score = afterData.score;
    const scoreChanged = beforeData ? beforeData.score !== afterData.score : true;
    const partiesChanged = beforeData ?
      beforeData.fromUserId !== afterData.fromUserId ||
      beforeData.toUserId !== afterData.toUserId :
      true;
    const coreRatingChanged = !beforeData || scoreChanged || partiesChanged;

    const isNowNoTrust = score >= 1 && score <= 10;
    const isNowFullTrust = score > 90;
    const isNowStaked = isNowNoTrust || isNowFullTrust;

    const wasNoTrust = beforeData ? (beforeData.score >= 1 && beforeData.score <= 10) : false;
    const wasFullTrust = beforeData ? (beforeData.score > 90) : false;
    const wasStaked = wasNoTrust || wasFullTrust;

    const batch = db.batch();
    const now = admin.firestore.FieldValue.serverTimestamp();

    // 1. First-time vouch reward
    if (!beforeData) {
       // Reward voucher
       batch.set(db.collection("user_points").doc(fromUserId), {
           availablePoints: admin.firestore.FieldValue.increment(1000),
           totalPoints: admin.firestore.FieldValue.increment(1000),
           lastUpdated: now,
           lifetimeEarnings: {
             trust_vouch_reward: admin.firestore.FieldValue.increment(1000),
           },
       }, {merge: true});

       batch.set(db.collection("points_transactions").doc(), {
          userId: fromUserId,
          points: 1000,
          amount: 1000,
          action: "trust_vouch_reward",
          type: "earn",
          timestamp: now,
          metadata: { toUserId, score }
       });

       await distributeUbuntuMatchingSupply(batch, fromUserId, 1000, now, "trust_vouch_reward_match");

       // Reward vouchee
       batch.set(db.collection("user_points").doc(toUserId), {
           availablePoints: admin.firestore.FieldValue.increment(1000),
           totalPoints: admin.firestore.FieldValue.increment(1000),
           lastUpdated: now,
           lifetimeEarnings: {
             vouched_by_peer: admin.firestore.FieldValue.increment(1000),
             trust_vouch_reward: admin.firestore.FieldValue.increment(1000),
           },
       }, {merge: true});

       batch.set(db.collection("points_transactions").doc(), {
          userId: toUserId,
          points: 1000,
          amount: 1000,
          action: "vouched_by_peer",
          type: "earn",
          timestamp: now,
          metadata: { fromUserId, score }
       });

       await distributeUbuntuMatchingSupply(batch, toUserId, 1000, now, "vouched_by_peer_match");
    }

    // 2. Staking logic
    let remainingStake = afterData.remainingStake || 0;
    let stakedAmount = afterData.stakedAmount || 0;

    if (coreRatingChanged && isNowStaked && !wasStaked) {
       // Deduct 1000 DSP (lock)
       batch.set(db.collection("user_points").doc(fromUserId), {
           availablePoints: admin.firestore.FieldValue.increment(-1000),
           lastUpdated: now
       }, {merge: true});

       batch.set(db.collection("points_transactions").doc(), {
          userId: fromUserId,
          points: -1000,
          amount: 1000,
          action: "trust_stake_locked",
          type: "spend",
          timestamp: now,
          metadata: { toUserId, score }
       });
       stakedAmount = 1000;
       remainingStake = 1000;
    } else if (coreRatingChanged && !isNowStaked && wasStaked) {
       // Refund remaining stake
       if (remainingStake > 0) {
           batch.set(db.collection("user_points").doc(fromUserId), {
               availablePoints: admin.firestore.FieldValue.increment(remainingStake),
               lastUpdated: now
           }, {merge: true});
           batch.set(db.collection("points_transactions").doc(), {
               userId: fromUserId,
               points: remainingStake,
               amount: remainingStake,
               action: "trust_stake_refund",
               type: "earn",
               timestamp: now,
               metadata: { toUserId, score }
           });
       }
       stakedAmount = 0;
       remainingStake = 0;
    }

    let updateVouch = false;
    if (afterData.remainingStake !== remainingStake || afterData.stakedAmount !== stakedAmount || afterData.isFullTrust !== isNowFullTrust) {
        updateVouch = true;
    }

    // 3. Stake Combat
    // Only actual rating changes should run combat. The metadata update below
    // writes back into this document and must not replay rewards or penalties.
    if (coreRatingChanged && isNowStaked && remainingStake > 0) {
        const otherVouchesSnap = await db.collection("trust_ratings")
            .where("toUserId", "==", toUserId)
            .get();

        for (const doc of otherVouchesSnap.docs) {
            const vouch = doc.data();
            if (vouch.fromUserId === fromUserId) continue;

            const otherIsNoTrust = vouch.score >= 1 && vouch.score <= 10;
            const otherIsFullTrust = vouch.score > 90;
            const otherIsStaked = otherIsNoTrust || otherIsFullTrust;

            if (!otherIsStaked || vouch.remainingStake <= 0) continue;

            if ((isNowNoTrust && otherIsNoTrust) || (isNowFullTrust && otherIsFullTrust)) {
                // Agreeing staker earns +100 DSP consensus reward
                batch.set(db.collection("user_points").doc(vouch.fromUserId), {
                    availablePoints: admin.firestore.FieldValue.increment(100),
                    totalPoints: admin.firestore.FieldValue.increment(100),
                    lastUpdated: now,
                    lifetimeEarnings: {
                      vouch_consensus_agree: admin.firestore.FieldValue.increment(100),
                    },
                }, { merge: true });

                batch.set(db.collection("points_transactions").doc(), {
                    userId: vouch.fromUserId,
                    points: 100,
                    amount: 100,
                    action: "vouch_consensus_agree",
                    type: "earn",
                    timestamp: now,
                    metadata: { toUserId, agreedWith: fromUserId, score }
                });
            } else {
                // Deduct 100 DSP from the other staker's locked stake
                const otherRemaining = vouch.remainingStake - 100;
                let newScore = vouch.score;
                let otherIsNowFullTrust = otherIsFullTrust;

                if (otherRemaining <= 0) {
                    newScore = 50; // Auto-cancel to standard trust
                    otherIsNowFullTrust = false;
                }

                batch.update(doc.ref, {
                    remainingStake: Math.max(0, otherRemaining),
                    score: newScore,
                    isFullTrust: otherIsNowFullTrust
                });

                batch.set(db.collection("points_transactions").doc(), {
                    userId: vouch.fromUserId,
                    points: -100,
                    amount: 100,
                    action: "vouch_consensus_disagree",
                    type: "penalty",
                    timestamp: now,
                    metadata: { toUserId, disagreedWith: fromUserId, score, remainingStake: Math.max(0, otherRemaining) }
                });
            }
        }
    }

    if (updateVouch) {
        batch.update(change.after.ref, {
            stakedAmount: stakedAmount,
            remainingStake: remainingStake,
            isFullTrust: isNowFullTrust
        });
    }

    await batch.commit();

    if (toUserId) {
      try {
        await syncProfileMilestoneAndTrust(toUserId);
      } catch (err) {
        console.warn(`[onVouchWrite] syncProfileMilestoneAndTrust warning for ${toUserId}: ${err.message}`);
      }
    }

    return null;
  });

/**
 * evaluatePoHGenesisStatus — Evaluates PoH 6 base milestones and Genesis 7,000 $DIASPORA claim status.
 * Milestone 7 (Ubuntu Emergency Fund) is deferred post-genesis.
 */
exports.evaluatePoHGenesisStatus = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "User must be authenticated.");
  }
  const userId = context.auth.uid;

  try {
    await syncProfileMilestoneAndTrust(userId);
  } catch (err) {
    console.warn(`[evaluatePoHGenesisStatus] syncProfileMilestoneAndTrust warning: ${err.message}`);
  }

  const [userDoc, pointsDoc, trustDataDoc, trustScoresDoc] = await Promise.all([
    db.collection("users").doc(userId).get(),
    db.collection("user_points").doc(userId).get(),
    db.collection("trust_data").doc(userId).get(),
    db.collection("trust_scores").doc(userId).get(),
  ]);

  if (!userDoc.exists) {
    throw new functions.https.HttpsError("not-found", "User profile not found.");
  }
  const userData = userDoc.data() || {};
  const pointsData = pointsDoc.exists ? (pointsDoc.data() || {}) : {};
  const trustData = trustDataDoc.exists
    ? (trustDataDoc.data() || {})
    : (trustScoresDoc.exists ? (trustScoresDoc.data() || {}) : {});
  const poh = userData.pohMilestones || {};
  const milestones = Array.isArray(trustData.awardedQualificationMilestones)
    ? trustData.awardedQualificationMilestones
    : [];

  const locationEnabled =
    !userData.cityVisibilityForfeited &&
    userData.showCurrentLocationName !== false &&
    !!(
      milestones.includes("LocationTransparency") ||
      userData.locationSharingEnabled ||
      userData.locationEnabled ||
      userData.currentLocation ||
      userData.currentCity ||
      userData.homeCity ||
      poh.locationEnabled
    );

  const completedFields = countCompletedProfileMilestoneFields(userData);
  const profileComplete = !!(
    milestones.includes("Profile") ||
    userData.isProfileComplete ||
    userData.isComplete ||
    completedFields >= PROFILE_MILESTONE_FIELDS.length ||
    poh.profileComplete
  );

  const qrCount = Number(
    trustData.uniqueQrCount ?? pointsData.qrConnectionCount ?? poh.qrExchangesCount ?? 0
  );
  const familyCount = Number(
    trustData.uniqueFamilyCount ?? pointsData.familyConnectionCount ?? poh.familyConnectionsCount ?? 0
  );
  const friendCount = Number(
    trustData.uniqueFriendCount ?? poh.friendConnectionsCount ?? 0
  );
  const peerVerificationsCount = Number(
    trustData.uniqueVerificationCount ?? pointsData.verifiedCount ?? poh.peerVerificationsCount ?? 0
  );
  const emergencyFundContributed = !!(
    milestones.includes("EmergencyFund") ||
    milestones.includes("UbuntuEmergencyFund") ||
    trustData.emergencyFundContributor ||
    poh.emergencyFundContributed
  );

  const baseMilestonesComplete = (
    locationEnabled &&
    profileComplete &&
    qrCount >= 10 &&
    familyCount >= 10 &&
    friendCount >= 10 &&
    peerVerificationsCount >= 10
  );

  const genesisClaimed = !!userData.tokenGenesisDistributionSent || !!userData.tokenWelcomeBonusSent;

  return {
    baseMilestonesComplete,
    genesisClaimed,
    milestones: {
      locationEnabled,
      profileComplete,
      qrCount,
      familyCount,
      friendCount,
      peerVerificationsCount,
      emergencyFundDeferred: true,
      emergencyFundContributed,
    },
    genesisAmount: 7000,
  };
});

/**
 * generateTdeClaimProof — Generates Merkle proof for user pull claim.
 * Users can claim their earned tokens anytime without epoch expiration.
 */
exports.generateTdeClaimProof = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "User must be authenticated.");
  }
  const userId = context.auth.uid;
  const epoch = Number(data?.epoch) || 1;
  const tdeEvent = Number(data?.tdeEvent) || 0;

  const tdeDoc = await db.collection("tde_snapshots").doc(`epoch_${epoch}_tde_${tdeEvent}`).get();
  if (!tdeDoc.exists) {
    throw new functions.https.HttpsError("not-found", "TDE event snapshot not found.");
  }

  const snapshot = tdeDoc.data();
  const userEntry = (snapshot.recipients || {})[userId];
  if (!userEntry) {
    throw new functions.https.HttpsError("not-found", "User is not eligible for this TDE.");
  }

  const userDoc = await db.collection("users").doc(userId).get();
  const walletAddress = userDoc.data()?.walletAddress;
  if (!walletAddress) {
    throw new functions.https.HttpsError("failed-precondition", "User has no wallet address.");
  }

  const { MerkleTree } = require("merkletreejs");
  const ethers = require("ethers");
  const keccak256 = ethers.keccak256;

  const leaves = [];
  let userLeaf = null;

  for (const [uid, alloc] of Object.entries(snapshot.recipients)) {
    const leaf = keccak256(
      ethers.AbiCoder.defaultAbiCoder().encode(
        ["address", "uint256", "uint256", "uint256", "uint8"],
        [alloc.walletAddress, epoch, tdeEvent, alloc.earnedAmount, alloc.efficiency]
      )
    );
    leaves.push(leaf);
    if (uid === userId) {
      userLeaf = leaf;
    }
  }

  const tree = new MerkleTree(leaves, keccak256, { sortPairs: true });
  const proof = tree.getHexProof(userLeaf);

  return {
    proof,
    walletAddress,
    epoch,
    tdeEvent,
    earnedAmount: userEntry.earnedAmount,
    efficiency: userEntry.efficiency,
    root: tree.getHexRoot(),
  };
});

/**
 * claimTdeTokens — Relayed execution of on-chain claimTdeTokens for gasless user claims.
 * Tokens are claimable anytime without epoch expiration.
 * Scores below 91 PCT do NOT freeze claims; efficiency decile determines liquid tokens.
 * Only tokens lost from the efficiency gate get burned to 0x...dEaD.
 */
exports.claimTdeTokens = functions
  .runWith({ timeoutSeconds: 60, memory: "256MB", secrets: ["BACKEND_SIGNER_PRIVATE_KEY"] })
  .https.onCall(async (data, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError("unauthenticated", "User must be authenticated.");
    }
    const userId = context.auth.uid;
    const epoch = Number(data?.epoch);
    const tdeEvent = Number(data?.tdeEvent);

    if (isNaN(epoch) || isNaN(tdeEvent)) {
      throw new functions.https.HttpsError("invalid-argument", "Epoch and tdeEvent are required numbers.");
    }

    const tdeDoc = await db.collection("tde_snapshots").doc(`epoch_${epoch}_tde_${tdeEvent}`).get();
    if (!tdeDoc.exists) {
      throw new functions.https.HttpsError("not-found", "TDE event snapshot not found.");
    }

    const snapshot = tdeDoc.data();
    const userEntry = (snapshot.recipients || {})[userId];
    if (!userEntry) {
      throw new functions.https.HttpsError("not-found", "User has no allocation for this TDE.");
    }

    const userDoc = await db.collection("users").doc(userId).get();
    const walletAddress = userDoc.data()?.walletAddress;
    if (!walletAddress) {
      throw new functions.https.HttpsError("failed-precondition", "User has no wallet address.");
    }

    const backendSignerKey = process.env.BACKEND_SIGNER_PRIVATE_KEY;
    const tgeControllerAddress = process.env.TGE_CONTROLLER_ADDRESS || process.env.DSP_DISTRIBUTOR_ADDRESS;
    if (!backendSignerKey || !tgeControllerAddress) {
      throw new functions.https.HttpsError("internal", "Smart contract relayer not configured.");
    }

    const provider = new ethers.JsonRpcProvider(process.env.RPC_URL || "https://mainnet.base.org");
    const signer = new ethers.Wallet(backendSignerKey, provider);
    const tgeController = new ethers.Contract(tgeControllerAddress, TGE_CONTROLLER_ABI, signer);

    const leaves = [];
    let userLeaf = null;

    for (const [uid, alloc] of Object.entries(snapshot.recipients)) {
      const leaf = ethers.keccak256(
        ethers.AbiCoder.defaultAbiCoder().encode(
          ["address", "uint256", "uint256", "uint256", "uint8"],
          [alloc.walletAddress, epoch, tdeEvent, alloc.earnedAmount, alloc.efficiency]
        )
      );
      leaves.push(leaf);
      if (uid === userId) {
        userLeaf = leaf;
      }
    }

    if (!userLeaf) {
      throw new functions.https.HttpsError("not-found", "Leaf not generated for user.");
    }

    const tree = new MerkleTree(leaves, ethers.keccak256, { sortPairs: true });
    const proof = tree.getHexProof(userLeaf);

    const earnedBn = BigInt(userEntry.earnedAmount);
    const eff = Number(userEntry.efficiency);
    const liquidBn = (earnedBn * BigInt(eff)) / 100n;
    const burnedBn = earnedBn - liquidBn;

    const claimKey = ethers.keccak256(
      ethers.AbiCoder.defaultAbiCoder().encode(
        ["address", "uint256", "uint256"],
        [walletAddress, epoch, tdeEvent]
      )
    );
    const isAlreadyClaimed = await tgeController.tdeClaimed(claimKey);
    if (isAlreadyClaimed) {
      return {
        alreadyClaimed: true,
        message: "Tokens for this TDE have already been claimed.",
      };
    }

    const tx = await tgeController.claimTdeTokens(
      walletAddress,
      epoch,
      tdeEvent,
      earnedBn,
      eff,
      proof
    );
    const receipt = await tx.wait();

    // Mark claimed in user_points
    const userRef = db.collection("user_points").doc(userId);
    const userSnap = await userRef.get();
    if (userSnap.exists) {
      const pointsData = userSnap.data();
      const tgeHistory = (pointsData.tgeHistory || []).map((entry) => {
        if (entry.epoch === epoch && (entry.tdeNumber === tdeEvent + 1 || entry.tgeNumber === tdeEvent)) {
          return {
            ...entry,
            claimed: true,
            claimedAt: admin.firestore.Timestamp.now(),
            txHash: receipt.hash,
          };
        }
        return entry;
      });
      await userRef.update({
        tgeHistory,
        lastUpdated: admin.firestore.FieldValue.serverTimestamp(),
      });
    }

    return {
      success: true,
      txHash: receipt.hash,
      liquid: ethers.formatUnits(liquidBn, 18),
      burned: ethers.formatUnits(burnedBn, 18),
      efficiency: eff,
    };
  });

exports.evaluateWelcomeBonus = exports.evaluatePoHGenesisStatus;

/**
 * recordDailyCheckIn — Records daily check-in, tracking streaks and awarding retention rewards.
 */
exports.recordDailyCheckIn = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "User must be authenticated.");
  }
  const userId = context.auth.uid;
  const now = new Date();
  const nowIso = now.toISOString();
  const nowTimestamp = admin.firestore.FieldValue.serverTimestamp();

  let awardedBonus = 0;
  let streak = 1;
  let isFirstToday = false;

  await db.runTransaction(async (transaction) => {
    const userPointsRef = db.collection("user_points").doc(userId);
    const userPointsSnap = await transaction.get(userPointsRef);

    if (!userPointsSnap.exists) {
      throw new functions.https.HttpsError("not-found", "User points document not found.");
    }

    const d = userPointsSnap.data();
    const lastDateStr = d.lastCheckInDate;
    let isSameDay = false;
    let isConsecutive = false;

    if (lastDateStr) {
      const lastDate = new Date(lastDateStr);
      isSameDay = (
        lastDate.getUTCFullYear() === now.getUTCFullYear() &&
        lastDate.getUTCMonth() === now.getUTCMonth() &&
        lastDate.getUTCDate() === now.getUTCDate()
      );

      const diffMs = now.getTime() - lastDate.getTime();
      const diffHours = diffMs / (1000 * 60 * 60);
      isConsecutive = !isSameDay && diffHours <= 48;
    }

    if (isSameDay) {
      isFirstToday = false;
      streak = d.currentStreak || 1;
      return;
    }

    isFirstToday = true;
    streak = isConsecutive ? (d.currentStreak || 0) + 1 : 1;

    let dailyPoints = 10;
    awardedBonus = dailyPoints;

    // 10-day streak bonus: 1,000 DSP
    if (streak === 10) {
      awardedBonus += 1000;
    }
    // 100-day super streak bonus: 10,000 DSP
    if (streak === 100) {
      awardedBonus += 10000;
    }

    transaction.update(userPointsRef, {
      currentStreak: streak,
      lastCheckInDate: nowIso,
      totalPoints: admin.firestore.FieldValue.increment(awardedBonus),
      availablePoints: admin.firestore.FieldValue.increment(awardedBonus),
      lastUpdated: nowTimestamp,
    });

    const txRef = db.collection("points_transactions").doc();
    transaction.set(txRef, {
      userId,
      type: "earn",
      action: "daily_check_in",
      points: awardedBonus,
      streak,
      timestamp: nowTimestamp,
      metadata: {
        description: `Daily Check-In (Day ${streak})`,
        streak,
      },
    });
  });

  return {
    success: true,
    isFirstToday,
    currentStreak: streak,
    pointsAwarded: awardedBonus,
  };
});

/**
 * Required profile milestone fields (12 fields matching ProfileData in Dart).
 */
const PROFILE_MILESTONE_FIELDS = [
  "bio",
  "occupation",
  "yearsInHostCountry",
  "industry",
  "profession",
  "languages",
  "meetingPreferences",
  "availability",
  "interests",
  "servicesOffered",
  "lookingFor",
  "education",
];

function countCompletedProfileMilestoneFields(userData) {
  if (!userData || typeof userData !== "object") return 0;
  let completed = 0;
  for (const field of PROFILE_MILESTONE_FIELDS) {
    const val = userData[field];
    if (Array.isArray(val)) {
      if (val.length > 0) completed++;
    } else if (typeof val === "string") {
      if (val.trim().length > 0) completed++;
    } else if (val != null) {
      completed++;
    }
  }
  return completed;
}

function getTrustLevelFromScore(score) {
  if (score >= 81) return "highTrust";
  if (score >= 61) return "standardTrust";
  if (score >= 41) return "mediumTrust";
  if (score >= 21) return "basicTrust";
  return "lowTrust";
}

const FAMILY_TYPES_SET = new Set([
  "wife", "husband", "daughter", "son", "mother", "father", "sister",
  "brother", "aunt", "uncle", "nephew", "niece", "cousin", "relative",
]);

/**
 * syncProfileMilestoneAndTrust — Server-authoritative evaluation of all 7
 * Proof of Humanity (PoH) Genesis Milestones (+10,000 DSP & +10 PCT each),
 * continuous HTS deltas (QR 11+, net vouches, seniority, event attendance, penalties),
 * and full projection sync to trust_data, trust_scores, user_points, and governance.
 * Idempotent: safe to call from any trigger or callable.
 */
async function syncProfileMilestoneAndTrust(userId) {
  if (!userId) return { success: false, reason: "missing_userId" };

  const [
    userDoc,
    privateDoc,
    pointsDoc,
    trustDataDoc,
    trustScoresDoc,
    stakerDoc,
    membershipDoc,
    relationshipsSnap,
    qrSnap,
    verificationsSnap,
    ratingsSnap,
  ] = await Promise.all([
    db.collection("users").doc(userId).get(),
    db.collection("user_private").doc(userId).get(),
    db.collection("user_points").doc(userId).get(),
    db.collection("trust_data").doc(userId).get(),
    db.collection("trust_scores").doc(userId).get(),
    db.collection("emergency_fund_stakers").doc(userId).get(),
    db.collection("emergency_fund_memberships").doc(userId).get(),
    db.collection("users").doc(userId).collection("relationships").where("status", "==", "active").get(),
    db.collection("qr_exchanges").where("users", "array-contains", userId).get(),
    db.collection("field_verifications").where("toUserId", "==", userId).get(),
    db.collection("trust_ratings").where("toUserId", "==", userId).get(),
  ]);

  if (!userDoc.exists) {
    return { success: false, reason: "user_not_found" };
  }

  const userData = userDoc.data() || {};
  const privateData = privateDoc.exists ? (privateDoc.data() || {}) : {};
  const pointsData = pointsDoc.exists ? (pointsDoc.data() || {}) : {};
  const trustData = trustDataDoc.exists
    ? (trustDataDoc.data() || {})
    : (trustScoresDoc.exists ? (trustScoresDoc.data() || {}) : {});

  const completedFields = countCompletedProfileMilestoneFields(userData);
  const totalFields = PROFILE_MILESTONE_FIELDS.length; // 12
  const isProfileComplete = completedFields >= totalFields;

  const milestones = new Set(
    Array.isArray(trustData.awardedQualificationMilestones)
      ? trustData.awardedQualificationMilestones
      : []
  );
  const ledger = {
    ...(trustData.awardedHtsTracking && typeof trustData.awardedHtsTracking === "object"
      ? trustData.awardedHtsTracking
      : {}),
  };

  const lifetimeEarnings = pointsData.lifetimeEarnings || {};
  const completedExplorationActions = new Set(
    Array.isArray(pointsData.completedExplorationActions)
      ? pointsData.completedExplorationActions
      : []
  );

  // 1. Compute Family & Friend sets from active relationships
  const familyIdsSet = new Set();
  const friendIdsSet = new Set();
  for (const relDoc of relationshipsSnap.docs) {
    const r = relDoc.data() || {};
    const peerId = String(r.id || relDoc.id || "").trim();
    if (!peerId || peerId === userId) continue;
    const rType = String(r.type || "").trim().toLowerCase();
    if (FAMILY_TYPES_SET.has(rType)) {
      familyIdsSet.add(peerId);
    }
  }
  for (const relDoc of relationshipsSnap.docs) {
    const r = relDoc.data() || {};
    const peerId = String(r.id || relDoc.id || "").trim();
    if (!peerId || peerId === userId) continue;
    const rType = String(r.type || "").trim().toLowerCase();
    if (!FAMILY_TYPES_SET.has(rType) && !familyIdsSet.has(peerId)) {
      friendIdsSet.add(peerId);
    }
  }
  // Preserve any existing genesis IDs if subcollection was empty during migration
  if (familyIdsSet.size === 0 && Array.isArray(trustData.genesisFamilyIds)) {
    for (const id of trustData.genesisFamilyIds) {
      if (typeof id === "string" && id.trim()) familyIdsSet.add(id.trim());
    }
  }
  if (friendIdsSet.size === 0 && Array.isArray(trustData.genesisFriendIds)) {
    for (const id of trustData.genesisFriendIds) {
      if (typeof id === "string" && id.trim() && !familyIdsSet.has(id.trim())) {
        friendIdsSet.add(id.trim());
      }
    }
  }

  const circleOfTrustIds = new Set([...familyIdsSet, ...friendIdsSet]);

  // 2. Compute Unique QR Exchanges
  const qrIdsSet = new Set(
    Array.isArray(trustData.genesisQrIds)
      ? trustData.genesisQrIds.filter((id) => typeof id === "string" && id.trim())
      : []
  );
  for (const qDoc of qrSnap.docs) {
    const q = qDoc.data() || {};
    const users = Array.isArray(q.users) ? q.users : [];
    for (const u of users) {
      if (typeof u === "string" && u.trim() && u.trim() !== userId) {
        qrIdsSet.add(u.trim());
      }
    }
    const otherUid = q.fromUid === userId ? q.toUid : (q.toUid === userId ? q.fromUid : null);
    if (typeof otherUid === "string" && otherUid.trim() && otherUid.trim() !== userId) {
      qrIdsSet.add(otherUid.trim());
    }
  }

  // 3. Compute Trust Ratings (Strictly excluding Circle of Trust for Full/No Trust staking)
  const fullTrustVoterIdsSet = new Set();
  const noTrustVoterIdsSet = new Set();
  let ratingSum = 0;
  let reviewCount = 0;
  for (const rDoc of ratingsSnap.docs) {
    const r = rDoc.data() || {};
    const fromId = String(r.fromUserId || "").trim();
    const score = Number(r.score || 0);
    if (!fromId || fromId === userId || score <= 0) continue;
    reviewCount++;
    ratingSum += score;
    if (!circleOfTrustIds.has(fromId)) {
      if (score > 90) {
        fullTrustVoterIdsSet.add(fromId);
      } else if (score >= 1 && score <= 10) {
        noTrustVoterIdsSet.add(fromId);
      }
    }
  }
  const averageRating = reviewCount > 0 ? ratingSum / reviewCount : Number(trustData.averageRating || 0);

  // 4. Compute Field Verifications
  const verificationIdsSet = new Set();
  let verifiedFieldsTotal = 0;
  let flaggedFieldsTotal = 0;
  for (const vDoc of verificationsSnap.docs) {
    const v = vDoc.data() || {};
    const fromId = String(v.fromUserId || "").trim();
    if (!fromId || fromId === userId) continue;
    const fields = v.fields && typeof v.fields === "object" ? v.fields : {};
    let hasVerifiedField = false;
    for (const status of Object.values(fields)) {
      if (status === "verified" || status === true) {
        hasVerifiedField = true;
        verifiedFieldsTotal++;
      } else if (status === "flagged" || status === false) {
        flaggedFieldsTotal++;
      }
    }
    if (hasVerifiedField || Object.keys(fields).length > 0) {
      if (!fullTrustVoterIdsSet.has(fromId)) {
        verificationIdsSet.add(fromId);
      }
    }
  }
  if (verificationIdsSet.size === 0 && Array.isArray(trustData.genesisVerificationIds)) {
    for (const id of trustData.genesisVerificationIds) {
      if (typeof id === "string" && id.trim() && !fullTrustVoterIdsSet.has(id.trim())) {
        verificationIdsSet.add(id.trim());
      }
    }
  }

  const uniqueFamilyCount = Math.max(familyIdsSet.size, Number(trustData.uniqueFamilyCount || 0));
  const uniqueFriendCount = Math.max(friendIdsSet.size, Number(trustData.uniqueFriendCount || 0));
  const uniqueQrCount = Math.max(
    qrIdsSet.size,
    Number(trustData.uniqueQrCount || pointsData.qrConnectionCount || 0)
  );
  const uniqueVerificationCount = Math.max(
    verificationIdsSet.size,
    Number(trustData.uniqueVerificationCount || 0)
  );
  const uniqueVouchCount = fullTrustVoterIdsSet.size;
  const noTrustVouchCount = noTrustVoterIdsSet.size;

  const now = admin.firestore.FieldValue.serverTimestamp();
  const batch = db.batch();
  const userPointsRef = db.collection("user_points").doc(userId);
  let anyDspChanged = false;
  let awardedProfileDsp = false;
  const newExplorationActions = [];

  async function awardMilestoneDsp(action, amount, description, extraMeta = {}) {
    anyDspChanged = true;
    batch.set(
      userPointsRef,
      {
        userId,
        totalPoints: admin.firestore.FieldValue.increment(amount),
        availablePoints: admin.firestore.FieldValue.increment(amount),
        lastUpdated: now,
        lifetimeEarnings: {
          [action]: admin.firestore.FieldValue.increment(amount),
        },
      },
      { merge: true }
    );

    const txRef = db.collection("points_transactions").doc();
    batch.set(txRef, {
      userId,
      type: "earn",
      action,
      points: amount,
      amount,
      timestamp: now,
      metadata: {
        description,
        ...extraMeta,
      },
    });

    await distributeUbuntuMatchingSupply(
      batch,
      userId,
      amount,
      now,
      `${action}_match`
    );
  }

  // ── Milestone 1: Profile Completion (12 fields -> 10,000 DSP + 10 PCT) ──
  const alreadyAwardedProfileDsp =
    Number(lifetimeEarnings.profile_completion || 0) >= 10000 ||
    Number(ledger.Profile_dsp_count || 0) >= totalFields ||
    completedExplorationActions.has("milestone_10_profile_fields");

  if (isProfileComplete) {
    milestones.add("Profile");
    ledger.Profile_dsp_count = totalFields;
    newExplorationActions.push("milestone_10_profile_fields", "complete_profile");

    if (!alreadyAwardedProfileDsp) {
      awardedProfileDsp = true;
      await awardMilestoneDsp(
        "profile_completion",
        10000,
        `Completed all ${totalFields} profile milestone fields`,
        { completedFields, totalFields }
      );
    }
  }

  // ── Milestone 2: Family Circle (10 Family -> 10,000 DSP + 10 PCT) ──
  if (uniqueFamilyCount >= 10) {
    milestones.add("Family");
    newExplorationActions.push("milestone_10_family");
    const alreadyAwardedFamilyMilestone =
      Number(ledger.Family_dsp_count || 0) >= 10 ||
      completedExplorationActions.has("milestone_10_family");
    if (!alreadyAwardedFamilyMilestone) {
      ledger.Family_dsp_count = 10;
      await awardMilestoneDsp(
        "family_connection",
        10000,
        "Completed 10 Family Circle connections milestone",
        { uniqueFamilyCount }
      );
    } else {
      ledger.Family_dsp_count = Math.max(Number(ledger.Family_dsp_count || 0), 10);
    }
  }

  // ── Milestone 3: Friend Circle (10 Friends -> 10,000 DSP + 10 PCT) ──
  if (uniqueFriendCount >= 10) {
    milestones.add("Friend");
    newExplorationActions.push("milestone_10_friend");
    const alreadyAwardedFriendMilestone =
      Number(ledger.Friend_dsp_count || 0) >= 10 ||
      completedExplorationActions.has("milestone_10_friend");
    if (!alreadyAwardedFriendMilestone) {
      ledger.Friend_dsp_count = 10;
      await awardMilestoneDsp(
        "friend_connection",
        10000,
        "Completed 10 Friend Circle connections milestone",
        { uniqueFriendCount }
      );
    } else {
      ledger.Friend_dsp_count = Math.max(Number(ledger.Friend_dsp_count || 0), 10);
    }
  }

  // ── Milestone 4: Identity QR Exchanges (10 QR -> 10,000 DSP + 10 PCT; 11+ -> 1,000 DSP each) ──
  let prevQrDspCount = Number(ledger.QR_dsp_count || 0);
  if (uniqueQrCount >= 10) {
    milestones.add("QR");
    newExplorationActions.push("milestone_10_qr");
    const alreadyAwardedQrMilestone =
      prevQrDspCount >= 10 ||
      completedExplorationActions.has("milestone_10_qr");
    if (!alreadyAwardedQrMilestone) {
      prevQrDspCount = 10;
      ledger.QR_dsp_count = 10;
      await awardMilestoneDsp(
        "identity_qr_exchange",
        10000,
        "Completed 10 Identity QR Exchanges milestone",
        { uniqueQrCount }
      );
    } else if (prevQrDspCount < 10) {
      prevQrDspCount = 10;
      ledger.QR_dsp_count = 10;
    }
    if (uniqueQrCount > 10 && uniqueQrCount > prevQrDspCount) {
      const extraScans = uniqueQrCount - prevQrDspCount;
      if (extraScans > 0) {
        ledger.QR_dsp_count = uniqueQrCount;
        await awardMilestoneDsp(
          "identity_qr_exchange_continuous",
          1000 * extraScans,
          `Completed ${extraScans} additional Identity QR Exchange(s)`,
          { extraScans, uniqueQrCount }
        );
      }
    }
  }

  // ── Milestone 5: Peer Verifications (10 Verifications -> 10,000 DSP + 10 PCT) ──
  if (uniqueVerificationCount >= 10) {
    milestones.add("Verified");
    newExplorationActions.push("milestone_10_verified");
    const alreadyAwardedVerifiedMilestone =
      Number(ledger.Verified_dsp_count || 0) >= 10 ||
      completedExplorationActions.has("milestone_10_verified");
    if (!alreadyAwardedVerifiedMilestone) {
      ledger.Verified_dsp_count = 10;
      await awardMilestoneDsp(
        "verified_by_peer",
        10000,
        "Completed 10 Peer Profile Verifications milestone",
        { uniqueVerificationCount }
      );
    } else {
      ledger.Verified_dsp_count = Math.max(Number(ledger.Verified_dsp_count || 0), 10);
    }
  }

  // ── Milestone 6: Location Transparency (10,000 DSP + 10 PCT; burned & forfeited if turned off) ──
  const cityForfeited = userData.cityVisibilityForfeited === true;
  const hasCurrentLocation = !!(
    userData.currentLocation ||
    privateData.currentLocation ||
    userData.currentCity ||
    userData.locationEnabled ||
    userData.locationSharingEnabled
  );
  const visibilityOn = userData.showCurrentLocationName !== false;
  const locationMilestoneAwarded =
    Number(ledger.LocationTransparency_dsp_awarded || 0) === 1 ||
    Number(lifetimeEarnings.location_transparency || 0) >= 10000 ||
    completedExplorationActions.has("location_transparency");

  let cityVisibilityPoCT = 0;
  if (!cityForfeited && hasCurrentLocation && visibilityOn) {
    cityVisibilityPoCT = 10;
    milestones.add("LocationTransparency");
    newExplorationActions.push("location_transparency");
    if (!locationMilestoneAwarded && Number(ledger.LocationTransparency_dsp_awarded || 0) !== -1) {
      ledger.LocationTransparency_dsp_awarded = 1;
      await awardMilestoneDsp(
        "location_transparency",
        10000,
        "Enabled Location Transparency milestone"
      );
    } else if (Number(ledger.LocationTransparency_dsp_awarded || 0) === 0) {
      ledger.LocationTransparency_dsp_awarded = 1;
    }
  } else if (locationMilestoneAwarded && Number(ledger.LocationTransparency_dsp_awarded || 0) !== -1 && (cityForfeited || !visibilityOn)) {
    // User toggled off location after earning milestone: burn 10,000 DSP & permanently forfeit
    milestones.delete("LocationTransparency");
    ledger.LocationTransparency_dsp_awarded = -1;
    anyDspChanged = true;
    const currentAvail = Number(pointsData.availablePoints || 0);
    const burnAmount = Math.min(10000, Math.max(0, currentAvail));
    if (burnAmount > 0) {
      batch.set(
        userPointsRef,
        {
          totalPoints: admin.firestore.FieldValue.increment(-burnAmount),
          availablePoints: admin.firestore.FieldValue.increment(-burnAmount),
          lastUpdated: now,
        },
        { merge: true }
      );
      batch.set(db.collection("points_transactions").doc(), {
        userId,
        type: "burn",
        action: "location_transparency_burned",
        points: -burnAmount,
        amount: burnAmount,
        timestamp: now,
        metadata: { description: "Location transparency disabled — milestone forfeited" },
      });
    }
    if (!cityForfeited) {
      batch.set(db.collection("users").doc(userId), { cityVisibilityForfeited: true }, { merge: true });
    }
  }

  // ── Milestone 7: Ubuntu Emergency Fund Contribution (10,000 DSP + 10 PCT) ──
  const membershipData = membershipDoc.exists ? (membershipDoc.data() || {}) : {};
  const hasEmergencyFund =
    stakerDoc.exists ||
    membershipData.status === "active" ||
    trustData.emergencyFundContributor === true ||
    milestones.has("EmergencyFund") ||
    milestones.has("UbuntuEmergencyFund");
  const emergencyFundAwarded =
    Number(ledger.EmergencyFund_dsp_awarded || 0) === 1 ||
    Number(lifetimeEarnings.emergency_fund_contribution || 0) >= 10000 ||
    completedExplorationActions.has("economy_emergency_fund");

  let emergencyFundPoCT = 0;
  if (hasEmergencyFund) {
    emergencyFundPoCT = 10;
    milestones.add("EmergencyFund");
    newExplorationActions.push("economy_emergency_fund");
    if (!emergencyFundAwarded) {
      ledger.EmergencyFund_dsp_awarded = 1;
      await awardMilestoneDsp(
        "emergency_fund_contribution",
        10000,
        "Contributed to Ubuntu Emergency Fund milestone"
      );
    } else {
      ledger.EmergencyFund_dsp_awarded = 1;
    }
  }

  if (newExplorationActions.length > 0) {
    batch.set(
      userPointsRef,
      {
        completedExplorationActions: admin.firestore.FieldValue.arrayUnion(...newExplorationActions),
        lastUpdated: now,
      },
      { merge: true }
    );
  }

  // ── Calculate Authoritative PCT Score ──
  let milestonePoCT = 0;
  if (isProfileComplete || milestones.has("Profile")) milestonePoCT += 10;
  if (uniqueFamilyCount >= 10 || milestones.has("Family")) milestonePoCT += 10;
  if (uniqueFriendCount >= 10 || milestones.has("Friend")) milestonePoCT += 10;
  if (uniqueQrCount >= 10 || milestones.has("QR")) milestonePoCT += 10;
  if (uniqueVerificationCount >= 10 || milestones.has("Verified")) milestonePoCT += 10;

  const verifiedCheckInCount = Number(trustData.verifiedCheckInCount || 0);
  const eventAttendancePoCT = verifiedCheckInCount >= 10 ? 10 : 0;

  // Continuous HTS Deltas
  let htsPoctDelta = 0;
  if (uniqueQrCount > 10) {
    htsPoctDelta += Math.floor((uniqueQrCount - 10) / 10);
  }
  const netVouches = uniqueVouchCount - noTrustVouchCount;
  htsPoctDelta += Math.trunc(netVouches / 10);

  const flaggedMessagesCount = Number(trustData.flaggedMessagesCount || 0);
  const blockedByCount = Number(userData.blockedByCount ?? trustData.blockedByCount ?? 0);
  const reportedFraudCount = Number(trustData.reportedFraudCount || 0);
  const fakeVerificationsCount = Number(trustData.fakeVerificationsCount || 0);
  const eventNoShowCount = Number(trustData.eventNoShowCount || 0);
  const rejectedFamilyConnectionsCount = Number(trustData.rejectedFamilyConnectionsCount || 0);

  htsPoctDelta -= Math.floor(flaggedMessagesCount / 10) * 10;
  htsPoctDelta -= Math.floor(blockedByCount / 10);
  htsPoctDelta -= Math.floor(reportedFraudCount / 10);
  htsPoctDelta -= Math.floor(fakeVerificationsCount / 10);
  htsPoctDelta -= Math.floor(eventNoShowCount / 10);
  htsPoctDelta -= Math.floor(rejectedFamilyConnectionsCount / 10);

  // Seniority (+1 PCT per 100 days active)
  let daysActive = 0;
  let createdAtDate = null;
  const rawCreatedAt = userData.createdAt || pointsData.signupDate;
  if (rawCreatedAt) {
    if (typeof rawCreatedAt.toDate === "function") {
      createdAtDate = rawCreatedAt.toDate();
    } else if (typeof rawCreatedAt === "string" || typeof rawCreatedAt === "number") {
      const parsed = new Date(rawCreatedAt);
      if (!isNaN(parsed.getTime())) createdAtDate = parsed;
    }
  }
  if (createdAtDate) {
    daysActive = Math.max(0, Math.floor((Date.now() - createdAtDate.getTime()) / (1000 * 60 * 60 * 24)));
  }
  const seniorityScore = Math.floor(daysActive / 100);

  const calculatedPoCT =
    milestonePoCT +
    cityVisibilityPoCT +
    emergencyFundPoCT +
    eventAttendancePoCT +
    htsPoctDelta +
    seniorityScore;

  const finalTrustScore = Math.min(100, Math.max(0, calculatedPoCT));
  const level = getTrustLevelFromScore(finalTrustScore);
  const isVerified = Boolean(trustData.isVerified) || isProfileComplete || finalTrustScore >= 80;
  const identityScore = (isProfileComplete ? 5 : 0) + (uniqueQrCount > 0 ? 15 : 0);

  const isPoHComplete =
    isProfileComplete &&
    uniqueFamilyCount >= 10 &&
    uniqueFriendCount >= 10 &&
    uniqueQrCount >= 10 &&
    uniqueVerificationCount >= 10 &&
    cityVisibilityPoCT >= 10;

  const isDdiEligible = isPoHComplete && daysActive >= 100 && finalTrustScore >= 91;
  const isCouncilEligible = Boolean(trustData.isCouncilEligible) || (isDdiEligible && Boolean(userData.isAdminOfLargeGroup));

  const uniqueTrustIds = Array.from(new Set([...fullTrustVoterIdsSet, ...verificationIdsSet]));

  const trustPatch = {
    uid: userId,
    trustScore: finalTrustScore,
    level,
    isVerified,
    isPoHComplete,
    isDdiEligible,
    isCouncilEligible,
    emergencyFundContributor: hasEmergencyFund,
    identityScore,
    activityScore: Math.min(20, Math.max(0, Number(pointsData.currentStreak || 0))),
    vouchTrustScore: Math.min(20, uniqueVouchCount * 2),
    vouchCount: uniqueVouchCount,
    vouchedBy: Array.from(fullTrustVoterIdsSet),
    fullTrustVoterIds: Array.from(fullTrustVoterIdsSet),
    noTrustVoterIds: Array.from(noTrustVoterIdsSet),
    reviewCount,
    averageRating,
    identityQRExchange: uniqueQrCount > 0,
    uniqueFamilyCount,
    uniqueFriendCount,
    uniqueQrCount,
    uniqueVerificationCount,
    uniqueVouchCount,
    vouchedByCount: uniqueVouchCount,
    verifiedByCount: verificationsSnap.size,
    verifiedFieldsCount: verifiedFieldsTotal,
    flaggedFieldsCount: flaggedFieldsTotal,
    genesisFamilyIds: Array.from(familyIdsSet).slice(0, 10),
    genesisFriendIds: Array.from(friendIdsSet).slice(0, 10),
    genesisQrIds: Array.from(qrIdsSet).slice(0, 10),
    genesisTrustIds: uniqueTrustIds.slice(0, 10),
    genesisVerificationIds: Array.from(verificationIdsSet).slice(0, 10),
    genesisVouchIds: Array.from(fullTrustVoterIdsSet).slice(0, 10),
    blockedByCount,
    awardedQualificationMilestones: Array.from(milestones),
    awardedHtsTracking: ledger,
    lastUpdated: now,
  };

  batch.set(db.collection("trust_data").doc(userId), trustPatch, { merge: true });
  batch.set(db.collection("trust_scores").doc(userId), trustPatch, { merge: true });
  batch.set(
    userPointsRef,
    {
      trustScore: finalTrustScore,
      qrConnectionCount: uniqueQrCount,
      familyConnectionCount: uniqueFamilyCount,
      verifiedCount: uniqueVerificationCount,
      lastUpdated: now,
    },
    { merge: true }
  );

  // Sync community governance averagePoCT / averagePct so performTGE never fails on missing averagePoCT
  const memberships = Array.isArray(userData.communityMemberships) ? userData.communityMemberships : [];
  for (const commId of memberships) {
    if (!commId || typeof commId !== "string") continue;
    const govId = commId === "global_community"
      ? "global_community"
      : (commId.includes("_") ? commId.substring(commId.indexOf("_") + 1) : commId);
    if (govId) {
      batch.set(
        db.collection("governance").doc(govId),
        {
          id: govId,
          communityId: commId,
          type: "community",
          averagePoCT: finalTrustScore,
          averagePct: finalTrustScore,
          updatedAt: now,
        },
        { merge: true }
      );
    }
  }

  await batch.commit();

  return {
    success: true,
    completedFields,
    totalFields,
    isProfileComplete,
    isPoHComplete,
    awardedProfileDsp,
    anyDspChanged,
    trustScore: finalTrustScore,
    isVerified,
  };
}

exports.syncProfileMilestoneAndTrust = syncProfileMilestoneAndTrust;
exports.distributeUbuntuMatchingSupply = distributeUbuntuMatchingSupply;

/**
 * evaluateProfileMilestone — Client-callable endpoint triggered after profile updates
 * or trust refreshes to ensure profile completion rewards (+10,000 DSP and +10 PCT)
 * are evaluated and synced by the server.
 */
exports.evaluateProfileMilestone = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "User must be authenticated.");
  }
  const callerId = context.auth.uid;
  const targetUserId = (data && typeof data.userId === "string" && data.userId.trim())
    ? data.userId.trim()
    : callerId;

  // Only allow evaluating self unless admin
  if (targetUserId !== callerId && !(context.auth.token && context.auth.token.admin === true)) {
    throw new functions.https.HttpsError("permission-denied", "Can only evaluate your own profile milestone.");
  }

  return await syncProfileMilestoneAndTrust(targetUserId);
});
