/**
 * DSP Points & Treasury module.
 * TGE Oracle, epoch management, awards, deductions, treasury sync.
 */
const { functions, admin, db } = require("./shared");
const { ethers } = require("ethers");

// ── Configuration (from environment) ──
const BACKEND_SIGNER_KEY = process.env.BACKEND_SIGNER_PRIVATE_KEY || null;
const TOKEN_ADDRESS = process.env.TOKEN_ADDRESS || null;
const TGE_CONTROLLER_ADDRESS = process.env.TGE_CONTROLLER_ADDRESS || null;

const TGE_CONTROLLER_ABI = [
  "function executeTGE(address[] recipients, uint256[] amounts, uint8[] efficiencies) external",
  "function distributeWelcomeBonus(address[] recipients, uint256[] amounts) external",
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
 * Calculate PoCT efficiency on a decile scale (matches EpochService.calculateEfficiency)
 * Score 0 = 0%, 1-10 = 10%, 11-20 = 20%, ... 91-100 = 100%
 */
function calculateEfficiency(trustScore) {
  if (!trustScore || trustScore <= 0) return 0;
  const efficiency = Math.ceil(trustScore / 10) * 10; // Decile: 0-100
  return Math.min(efficiency, 100);
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
async function performTGE(triggerSource) {
  if (!TOKEN_ADDRESS || !TGE_CONTROLLER_ADDRESS || !BACKEND_SIGNER_KEY) {
    console.error("[TGE Oracle] Missing contract addresses or signer key in .env");
    return null;
  }

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
    });
  }

  // ── Step 2: Snapshot community treasury balances ──────────────────
  const govSnap = await db.collection("governance")
    .where("treasuryBalance", ">", 0)
    .get();

  let treasuriesIncluded = 0;

  for (const doc of govSnap.docs) {
    const d = doc.data();
    const walletAddress = d.walletAddress;
    const treasuryDsp = d.treasuryBalance || 0;

    if (!walletAddress || walletAddress.length < 10 || treasuryDsp <= 0) {
      continue;
    }

    // APoCT: Average PoCT of community members → decile efficiency
    const avgPoCT = d.averagePoCT || 0;
    const treasuryEfficiency = Math.min(Math.ceil(avgPoCT / 10) * 10, 100);

    recipients.push(walletAddress);
    amounts.push(ethers.parseUnits(Math.floor(treasuryDsp).toString(), 18));
    efficiencies.push(treasuryEfficiency);
    totalDsp += Math.floor(treasuryDsp);
    treasuriesIncluded++;

    snapshotDetails.push({
      unitId: doc.id,
      unitName: d.name,
      wallet: walletAddress,
      dsp: Math.floor(treasuryDsp),
      efficiency: treasuryEfficiency,
      averagePoCT: avgPoCT,
    });
  }

  if (recipients.length === 0) {
    console.log("[TGE Oracle] No eligible recipients. Aborting.");
    return null;
  }

  console.log(`[TGE Oracle] Snapshot: ${usersIncluded} users, ${treasuriesIncluded} treasuries, ${totalDsp} DSP`);

  // ── Step 3: Call on-chain executeTGE ───────────────────────────────
  const provider = new ethers.JsonRpcProvider("https://mainnet.base.org");
  const signer = new ethers.Wallet(BACKEND_SIGNER_KEY, provider);
  const tgeController = new ethers.Contract(TGE_CONTROLLER_ADDRESS, TGE_CONTROLLER_ABI, signer);

  const statsBefore = await tgeController.getStats();
  const epochBefore = Number(statsBefore[0]);
  const eventBefore = Number(statsBefore[1]);

  console.log(`[TGE Oracle] On-chain: Epoch ${epochBefore}, Event ${eventBefore}`);

  const tx = await tgeController.executeTGE(recipients, amounts, efficiencies);
  const receipt = await tx.wait();

  const statsAfter = await tgeController.getStats();
  const epochAfter = Number(statsAfter[0]);
  const eventAfter = Number(statsAfter[1]);

  console.log(`[TGE Oracle] ✅ TX: ${receipt.hash}`);
  console.log(`[TGE Oracle] Epoch ${epochBefore}→${epochAfter}, Event ${eventBefore}→${eventAfter}`);

  // ── Step 4: Record in Firestore ────────────────────────────────────
  const tgeRecord = {
    epoch: epochBefore,
    tgeEvent: eventBefore,
    txHash: receipt.hash,
    totalDsp,
    totalRecipients: recipients.length,
    usersIncluded,
    treasuriesIncluded,
    triggerSource,
    timestamp: admin.firestore.FieldValue.serverTimestamp(),
    snapshot: snapshotDetails,
  };

  await db.collection("tge_events").add(tgeRecord);

  return {
    success: true,
    txHash: receipt.hash,
    epoch: epochBefore,
    tgeEvent: eventBefore,
    newEpoch: epochAfter,
    newTgeEvent: eventAfter,
    totalDsp,
    totalRecipients: recipients.length,
  };
}

/**
 * AUTO-TRIGGER: Watches total DSP supply for TGE milestone crossings.
 * totalMinted = user earnings + all 10 expansion slots (community, founders, investors, burn)
 * When totalMinted crosses the next 10% epoch milestone, fires TGE automatically.
 */
exports.onGlobalDspMilestone = functions
  .runWith({ timeoutSeconds: 300, memory: "512MB" })
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
  .runWith({ timeoutSeconds: 300, memory: "512MB" })
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
exports.awardPoints = functions.https.onCall(async (data, context) => {
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
    'welcome_bonus', 'message_sent', 'daily_message', 'exploration',
    'share_content', 'referral_signup', 'voice_call', 'video_call',
    'event_attendance', 'marketplace_listing', 'real_estate_listing',
    'flight_booking', 'car_rental', 'bereavement_contribution',
    'profile_completion', 'daily_streak',
  ];

  // For cross-user awards (e.g. referral rewards), only allow trusted actions
  const CROSS_USER_ACTIONS = [
    'referral_signup', 'referral_reward_referrer', 'referral_reward_referee',
    'trust_vouch_reward', 'family_connection',
  ];

  if (callerId !== userId && !CROSS_USER_ACTIONS.includes(action)) {
    throw new functions.https.HttpsError("permission-denied", "Cannot award points to another user for this action.");
  }

  try {
    const batch = db.batch();
    const userPointsRef = db.collection("user_points").doc(userId);

    // Update user balance
    batch.set(userPointsRef, {
      totalPoints: admin.firestore.FieldValue.increment(points),
      availablePoints: admin.firestore.FieldValue.increment(points),
      lastUpdated: admin.firestore.FieldValue.serverTimestamp(),
      [`lifetimeEarnings.${action}`]: admin.firestore.FieldValue.increment(points),
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

      // System treasuries (Founders 10% + Investors 10% + Burn 10%)
      batch.set(db.collection("system_stats").doc("treasury"), {
        foundersPoints: admin.firestore.FieldValue.increment(unit),
        investorsPoints: admin.firestore.FieldValue.increment(unit),
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

      batch.set(db.collection("governance").doc("investors"), {
        id: "investors",
        name: "Investors & Partners",
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
              if (!id) return;
              fractions[id] = (fractions[id] || 0) + fraction;
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
 * initializeUserPoints — Sets up a new user's points doc with welcome bonus.
 * Called once during signup. Handles both fresh users and partial docs.
 */
exports.initializeUserPoints = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Must be authenticated.");
  }

  const userId = context.auth.uid;

  try {
    const userPointsRef = db.collection("user_points").doc(userId);
    const doc = await userPointsRef.get();
    const docData = doc.exists ? doc.data() : null;

    // Already fully initialized
    if (doc.exists && docData && docData.signupDate && docData.userId) {
      return { success: true, alreadyInitialized: true };
    }

    // Fetch home country code from users collection
    const userDoc = await db.collection("users").doc(userId).get();
    const countryCode = userDoc.exists ? (userDoc.data().homeCountryCode || null) : null;

    const batch = db.batch();
    const now = admin.firestore.FieldValue.serverTimestamp();

    if (!doc.exists) {
      // Fresh user — full initialization with 1000 DSP welcome bonus
      batch.set(userPointsRef, {
        userId,
        totalPoints: 1000,
        availablePoints: 1000,
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
        lifetimeEarnings: { welcome_bonus: 1000 },
        ...(countryCode ? { homeCountryCode: countryCode } : {}),
      });
    } else {
      // Partial doc — backfill missing fields + award welcome bonus if missing
      const existingLifetime = docData.lifetimeEarnings || {};
      const welcomeBonusMissing = !existingLifetime.welcome_bonus;
      const bonusToAdd = welcomeBonusMissing ? 1000 : 0;

      const updates = {
        userId,
        signupDate: now,
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
        updates["lifetimeEarnings.welcome_bonus"] = bonusToAdd;
      }

      batch.set(userPointsRef, updates, { merge: true });
    }

    // Check if welcome bonus should be awarded
    const existingLifetime = docData ? (docData.lifetimeEarnings || {}) : {};
    const shouldAwardBonus = !doc.exists || !existingLifetime.welcome_bonus;

    if (shouldAwardBonus) {
      // Record transaction
      const txRef = db.collection("points_transactions").doc();
      batch.set(txRef, {
        userId,
        type: "earn",
        action: "welcome_bonus",
        points: 1000,
        timestamp: now,
        metadata: { description: "Welcome to Diaspora!" },
      });

      // 2x expansion: 1000 user DSP → 2000 totalMinted
      batch.set(db.collection("system_stats").doc("dsp_supply"), {
        totalMinted: admin.firestore.FieldValue.increment(2000),
        lastUpdated: now,
      }, { merge: true });

      // Treasury distribution: 10% of TOTAL each to founders, investors, burn
      const unit = 200; // 10% of totalMinted (2000)
      const points = 1000;
      batch.set(db.collection("system_stats").doc("treasury"), {
        foundersPoints: admin.firestore.FieldValue.increment(unit),
        investorsPoints: admin.firestore.FieldValue.increment(unit),
        burnedPoints: admin.firestore.FieldValue.increment(unit),
        lastUpdated: now,
      }, { merge: true });

      // Governance docs for system treasuries
      batch.set(db.collection("governance").doc("founders"), {
        id: "founders",
        name: "Founders & Core Team",
        type: "system",
        treasuryBalance: admin.firestore.FieldValue.increment(unit),
        title: "Founders Treasury",
        updatedAt: now,
      }, { merge: true });

      batch.set(db.collection("governance").doc("investors"), {
        id: "investors",
        name: "Investors & Partners",
        type: "system",
        treasuryBalance: admin.firestore.FieldValue.increment(unit),
        updatedAt: now,
      }, { merge: true });

      // ── Community treasury distribution ──
      // Look up user's community memberships (may not exist yet for brand-new users)
      if (unit > 0) {
        try {
          const initUserDoc = userDoc.exists ? userDoc : await db.collection("users").doc(userId).get();
          if (initUserDoc.exists) {
            const memberships = initUserDoc.data().communityMemberships || [];

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

            const fractions = {};
            const addSlot = (id, fraction) => {
              if (!id) return;
              fractions[id] = (fractions[id] || 0) + fraction;
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

              // Community treasury subcollection
              const tRef = db.collection("communities").doc(commId)
                .collection("treasury").doc("current");
              batch.set(tRef, {
                cumulativeEarnings: admin.firestore.FieldValue.increment(slotBasis + slotUnit),
                memberPoints: admin.firestore.FieldValue.increment(slotBasis),
                points: admin.firestore.FieldValue.increment(slotUnit),
                awardedBalance: admin.firestore.FieldValue.increment(slotUnit),
                updatedAt: now,
              }, { merge: true });

              // Mirror to top-level community doc
              batch.set(db.collection("communities").doc(commId), {
                cumulativeEarnings: admin.firestore.FieldValue.increment(slotBasis + slotUnit),
                memberPoints: admin.firestore.FieldValue.increment(slotBasis),
                points: admin.firestore.FieldValue.increment(slotUnit),
                awardedBalance: admin.firestore.FieldValue.increment(slotUnit),
                updatedAt: now,
              }, { merge: true });

              // Governance doc
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
        } catch (communityErr) {
          // Don't fail initialization if community distribution fails
          console.warn(`[initializeUserPoints] Community distribution warning: ${communityErr.message}`);
        }
      }

      // ── Token Welcome Bonus: Instant DSP→$DIASPORA conversion ──
      // Mirrors the DSP distribution above but converts to on-chain tokens
      // at 100% efficiency immediately, rather than waiting for TGE milestone.
      if (BACKEND_SIGNER_KEY && TGE_CONTROLLER_ADDRESS && TOKEN_ADDRESS) {
        try {
          // Idempotency: skip if already sent (prevents double-distribution on retry)
          const preCheck = await db.collection("users").doc(userId).get();
          if (preCheck.exists && preCheck.data().tokenWelcomeBonusSent === true) {
            console.log(`[Token Welcome Bonus] Already sent for user ${userId}, skipping.`);
          } else {
            // Wait for smart wallet to be created by onUserWrite trigger (race condition)
            let userWalletAddress = preCheck.exists ? preCheck.data().walletAddress : null;
            if (!userWalletAddress) {
              // Retry up to 3 times with 2s delay for async wallet creation
              for (let attempt = 1; attempt <= 3 && !userWalletAddress; attempt++) {
                console.log(`[Token Welcome Bonus] Wallet not ready, waiting 2s (attempt ${attempt}/3)...`);
                await new Promise((resolve) => setTimeout(resolve, 2000));
                const retryDoc = await db.collection("users").doc(userId).get();
                userWalletAddress = retryDoc.exists ? retryDoc.data().walletAddress : null;
              }
            }

            if (userWalletAddress) {
              const RPC_URL = process.env.RPC_URL || "https://mainnet.base.org";
              const provider = new ethers.JsonRpcProvider(RPC_URL);
              const signer = new ethers.Wallet(BACKEND_SIGNER_KEY, provider);
              const tge = new ethers.Contract(TGE_CONTROLLER_ADDRESS, TGE_CONTROLLER_ABI, signer);

              const BURN_ADDRESS = "0x000000000000000000000000000000000000dEaD";
              const DEPLOYER_FALLBACK = signer.address; // Fallback if treasury wallet not created yet

              // Look up system treasury wallet addresses from governance docs
              const [foundersGov, investorsGov] = await Promise.all([
                db.collection("governance").doc("founders").get(),
                db.collection("governance").doc("investors").get(),
              ]);
              const foundersWallet = foundersGov.exists ? foundersGov.data().walletAddress : null;
              const investorsWallet = investorsGov.exists ? investorsGov.data().walletAddress : null;

              // Build the exact same community fractions as DSP distribution
              const recipientList = [];
              const amountList = [];
              let totalTokens = 0n;

              // 1. User: 1,000 $DIASPORA
              recipientList.push(userWalletAddress);
              amountList.push(ethers.parseUnits("1000", 18));
              totalTokens += ethers.parseUnits("1000", 18);

              // 2. Burn: 100 $DIASPORA (10% of tribute)
              recipientList.push(BURN_ADDRESS);
              amountList.push(ethers.parseUnits("100", 18));
              totalTokens += ethers.parseUnits("100", 18);

              // 3. Founders: 100 $DIASPORA (10% of tribute)
              recipientList.push(foundersWallet || DEPLOYER_FALLBACK);
              amountList.push(ethers.parseUnits("100", 18));
              totalTokens += ethers.parseUnits("100", 18);
              if (!foundersWallet) console.warn("[Token Welcome Bonus] Founders wallet not found, using deployer fallback");

              // 4. Investors: 100 $DIASPORA (10% of tribute)
              recipientList.push(investorsWallet || DEPLOYER_FALLBACK);
              amountList.push(ethers.parseUnits("100", 18));
              totalTokens += ethers.parseUnits("100", 18);
              if (!investorsWallet) console.warn("[Token Welcome Bonus] Investors wallet not found, using deployer fallback");

              // 5. Community treasuries: 700 $DIASPORA (70% of tribute)
              //    Mirror exact same fractions as DSP distribution (unit=100 per slot)
              const initUserDoc2 = preCheck; // Already fetched above
              const memberships2 = initUserDoc2.exists ? (initUserDoc2.data().communityMemberships || []) : [];
              const findMembership2 = (prefix) => memberships2.find((id) => id.startsWith(prefix)) || "";

              const communitySlots = {};
              const addCommunitySlot = (id, fraction) => {
                if (!id) return;
                communitySlots[id] = (communitySlots[id] || 0) + fraction;
              };

              addCommunitySlot("global_community", 1.0);
              const hcont = findMembership2("home_continent_");
              const hcountry = findMembership2("home_country_");
              const hstate = findMembership2("home_state_");
              const hcity = findMembership2("home_city_");
              const xcont = findMembership2("host_continent_");
              const xcountry = findMembership2("host_country_");
              const xstate = findMembership2("host_state_");
              const xcity = findMembership2("host_city_");

              addCommunitySlot(hcont, 1.0);
              if (hstate) { addCommunitySlot(hcountry, 0.5); addCommunitySlot(hstate, 0.5); }
              else { addCommunitySlot(hcountry, 1.0); }
              addCommunitySlot(hcity, 1.0);

              addCommunitySlot(xcont, 1.0);
              if (xstate) { addCommunitySlot(xcountry, 0.5); addCommunitySlot(xstate, 0.5); }
              else { addCommunitySlot(xcountry, 1.0); }
              addCommunitySlot(xcity, 1.0);

              // Look up wallet addresses for each community
              let communityTokensDistributed = 0n;
              for (const [commId, fraction] of Object.entries(communitySlots)) {
                const slotAmount = Math.round(100 * fraction); // unit=100 (10% of 1000)
                if (slotAmount <= 0) continue;

                const commDoc = await db.collection("communities").doc(commId).get();
                const commWallet = commDoc.exists ? commDoc.data().walletAddress : null;

                if (commWallet) {
                  recipientList.push(commWallet);
                  amountList.push(ethers.parseUnits(slotAmount.toString(), 18));
                  communityTokensDistributed += ethers.parseUnits(slotAmount.toString(), 18);
                  totalTokens += ethers.parseUnits(slotAmount.toString(), 18);
                } else {
                  // Community wallet not yet created — send to deployer as fallback
                  console.warn(`[Token Welcome Bonus] Community ${commId} has no wallet, using system treasury`);
                  recipientList.push(DEPLOYER_FALLBACK);
                  amountList.push(ethers.parseUnits(slotAmount.toString(), 18));
                  totalTokens += ethers.parseUnits(slotAmount.toString(), 18);
                }
              }

              // Check TGEController has enough supply
              const lockedBalance = await tge.getLockedBalance();

              if (lockedBalance >= totalTokens) {
                console.log(`[Token Welcome Bonus] Distributing ${ethers.formatUnits(totalTokens, 18)} $DIASPORA for user ${userId} (${recipientList.length} recipients)...`);

                // Retry loop for nonce collisions — the same backend signer is
                // used by both onCommunityWrite (wallet creation) and this bonus
                // distribution. When they run concurrently the signer nonce can
                // be stale. We retry with a fresh provider/signer so ethers
                // re-fetches the latest nonce from the network.
                const MAX_TX_RETRIES = 3;
                let txHash = null;
                for (let attempt = 1; attempt <= MAX_TX_RETRIES; attempt++) {
                  try {
                    // Create a fresh signer each attempt so ethers fetches the
                    // current nonce from the network (no stale cache).
                    const retryProvider = new ethers.JsonRpcProvider(RPC_URL);
                    const retrySigner = new ethers.Wallet(BACKEND_SIGNER_KEY, retryProvider);
                    const retryTge = new ethers.Contract(TGE_CONTROLLER_ADDRESS, TGE_CONTROLLER_ABI, retrySigner);

                    const tx = await retryTge.distributeWelcomeBonus(recipientList, amountList);
                    const receipt = await tx.wait();
                    txHash = receipt.hash;
                    console.log(`[Token Welcome Bonus] ✅ Distributed on attempt ${attempt}! TX: ${txHash}`);
                    break; // success — exit retry loop
                  } catch (nonceErr) {
                    const msg = (nonceErr.message || "").toLowerCase();
                    const isNonceError = nonceErr.code === "NONCE_EXPIRED" ||
                      nonceErr.code === "REPLACEMENT_UNDERPRICED" ||
                      msg.includes("nonce") ||
                      msg.includes("already known") ||
                      msg.includes("replacement");
                    if (isNonceError && attempt < MAX_TX_RETRIES) {
                      const waitSec = attempt * 5; // 5s, 10s
                      console.warn(`[Token Welcome Bonus] Nonce collision on attempt ${attempt}, retrying in ${waitSec}s...`);
                      await new Promise((r) => setTimeout(r, waitSec * 1000));
                    } else {
                      throw nonceErr; // Not a nonce error, or last attempt — propagate
                    }
                  }
                }

                if (!txHash) {
                  throw new Error("distributeWelcomeBonus failed after all retries");
                }

                // Record token welcome bonus transaction in Firestore
                const tokenBonusTxRef = db.collection("points_transactions").doc();
                batch.set(tokenBonusTxRef, {
                  userId,
                  type: "earn",
                  action: "token_welcome_bonus",
                  assetType: "token",
                  points: 1000,
                  txHash,
                  timestamp: now,
                  metadata: {
                    description: "Welcome Bonus — 1,000 $DIASPORA",
                    totalDistributed: Number(ethers.formatUnits(totalTokens, 18)),
                    userAmount: 1000,
                    burnAmount: 100,
                    foundersAmount: 100,
                    investorsAmount: 100,
                    communityAmount: Number(ethers.formatUnits(communityTokensDistributed, 18)),
                    recipientCount: recipientList.length,
                  },
                });

                // Mark user as having received token welcome bonus
                batch.set(db.collection("users").doc(userId), {
                  tokenWelcomeBonusSent: true,
                  tokenWelcomeBonusTx: txHash,
                }, { merge: true });

                // Deduct DSP balance (consumed by conversion)
                batch.set(userPointsRef, {
                  totalPoints: admin.firestore.FieldValue.increment(-1000),
                  availablePoints: admin.firestore.FieldValue.increment(-1000),
                }, { merge: true });

                console.log(`[Token Welcome Bonus] User ${userId} DSP deducted, token bonus recorded.`);
              } else {
                console.warn(`[Token Welcome Bonus] Insufficient epoch supply. Locked: ${ethers.formatUnits(lockedBalance, 18)}, Needed: ${ethers.formatUnits(totalTokens, 18)}`);
              }
            } else {
              console.warn(`[Token Welcome Bonus] User ${userId} has no wallet address yet. Token bonus deferred.`);
            }
          } // end else (idempotency check)
        } catch (tokenBonusErr) {
          // Don't fail user initialization if token bonus fails
          console.error(`[Token Welcome Bonus] Error for ${userId}:`, tokenBonusErr.message);
        }
      }
    } // end if (shouldAwardBonus)

    await batch.commit();

    return { success: true, welcomeBonusAwarded: shouldAwardBonus };
  } catch (error) {
    console.error(`[initializeUserPoints] Error:`, error.message);
    throw new functions.https.HttpsError("internal", `Failed to initialize: ${error.message}`);
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

      // Treasury distribution: 10% of TOTAL each to founders, investors, burn
      const unit = Math.floor(pointsToAward * 0.20); // 10% of total (points × 2 × 0.10)
      if (unit > 0) {
        transaction.set(db.collection("system_stats").doc("treasury"), {
          foundersPoints: admin.firestore.FieldValue.increment(unit),
          investorsPoints: admin.firestore.FieldValue.increment(unit),
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

        transaction.set(db.collection("governance").doc("investors"), {
          id: "investors", name: "Investors & Partners", type: "system",
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
          if (!id) return;
          fractions[id] = (fractions[id] || 0) + fraction;
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
          const govId = commId === "global_community" ? "global_community"
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

      // Treasury: 10% of TOTAL each to founders, investors, burn
      const unit = Math.floor(points * 0.20); // 10% of total (points × 2 × 0.10)
      if (unit > 0) {
        transaction.set(db.collection("system_stats").doc("treasury"), {
          foundersPoints: admin.firestore.FieldValue.increment(unit),
          investorsPoints: admin.firestore.FieldValue.increment(unit),
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

        transaction.set(db.collection("governance").doc("investors"), {
          id: "investors", name: "Investors & Partners", type: "system",
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
          if (!id) return;
          fractions[id] = (fractions[id] || 0) + fraction;
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
          const govId = commId === "global_community" ? "global_community"
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
          investorsPoints: admin.firestore.FieldValue.increment(unit),
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

        transaction.set(db.collection("governance").doc("investors"), {
          id: "investors", name: "Investors & Partners", type: "system",
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
          if (!id) return;
          fractions[id] = (fractions[id] || 0) + fraction;
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
          const govId = commId === "global_community" ? "global_community"
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
    const batch = db.batch();

    // Increment global fiat GDP counter
    batch.set(db.collection("system_stats").doc("treasury"), {
      totalFiatGdpUsd: admin.firestore.FieldValue.increment(amountUsd),
      lastFiatGdpUpdate: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });

    // Log individual GDP transaction for audit trail
    const gdpTxRef = db.collection("gdp_transactions").doc();
    batch.set(gdpTxRef, {
      id: gdpTxRef.id,
      amountUsd,
      activityType,
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
      recordedBy: context.auth.uid,
      ...(metadata || {}),
    });

    await batch.commit();

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
  .runWith({ timeoutSeconds: 300, memory: "512MB" })
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
      const communityPoCTs = {};

      let totalUserPoints = 0;
      let totalFoundersPoints = 0;
      let totalInvestorsPoints = 0;
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
        totalInvestorsPoints += unit;

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
          if (!communityPoCTs[cid]) communityPoCTs[cid] = [];
          communityPoCTs[cid].push(trustScore);
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
        investorsPoints: totalInvestorsPoints,
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

      batch.set(db.collection("governance").doc("investors"), {
        treasuryBalance: totalInvestorsPoints,
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

        const pocts = communityPoCTs[commId] || [];
        const avgPoCT = pocts.length > 0 ? pocts.reduce((a, b) => a + b, 0) / pocts.length : 0;

        const treasuryRef = db.collection("communities").doc(commId).collection("treasury").doc("current");
        batch.set(treasuryRef, {
          points: communityPointsMap[commId],
          cumulativeEarnings: communityBasisMap[commId],
          memberPoints: communityMemberPointsMap[commId],
          awardedBalance: communityPointsMap[commId],
          averagePoCT: avgPoCT,
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
          averagePoCT: avgPoCT,
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
          averagePoCT: avgPoCT,
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
        totalInvestorsPoints,
        totalBurnedPoints,
        communitiesProcessed: Object.keys(communityPointsMap).length,
      };
    } catch (error) {
      console.error(`[syncTreasuryBalances] Error:`, error.message);
      throw new functions.https.HttpsError("internal", `Failed: ${error.message}`);
    }
  });

