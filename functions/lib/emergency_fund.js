/**
 * Community Emergency Fund — $DIASPORA payment, transparency, auto-disbursement.
 *
 * Replaces the Stripe USD flow with on-chain $DIASPORA payments.
 *   - Contribution: $100 USD-equivalent in $DIASPORA, priced via live valuation oracle.
 *   - Treasury wallet: deterministic CREATE2 wallet derived from salt "treasury:emergency_fund".
 *   - Auto-disbursement: Firestore trigger on emergency_fund_claims when status -> approved.
 *   - Ledger: emergency_fund_ledger collection captures every deposit + payout with tx hash
 *     and full recipient info (publicly readable for transparency).
 */
const { functions, admin, db } = require("./shared");
const { ethers } = require("ethers");
const { getSmartWalletInfra, SMART_WALLET_ABI } = require("./wallet");

const FUND_SALT_LABEL = "treasury:emergency_fund";
const CONTRIBUTION_USD = 100;
const PROMISSORY_DSP = 1000;

// Abuse guardrails (per beneficiary)
const PAYOUT_COOLDOWN_DAYS = 90;
const PAYOUT_ANNUAL_CAP_USD = 1000;

// ── ERC-20 helpers ──
const ERC20_ABI = [
  "function balanceOf(address) view returns (uint256)",
  "function decimals() view returns (uint8)",
  "function transfer(address to, uint256 amount) returns (bool)",
];

function getTokenAddress() {
  const addr = process.env.DIASPORA_TOKEN_ADDRESS;
  if (!addr) throw new functions.https.HttpsError("failed-precondition", "DIASPORA_TOKEN_ADDRESS env not set");
  return addr;
}

/** Compute or fetch the fund treasury wallet address. */
async function getFundTreasuryAddress(infra) {
  const salt = ethers.keccak256(ethers.toUtf8Bytes(FUND_SALT_LABEL));
  let addr = await infra.factory.getWallet(salt);
  if (addr === ethers.ZeroAddress) {
    addr = await infra.factory.computeAddress(salt);
    // Deploy on first use
    try {
      const tx = await infra.factory.createWallet(salt);
      await tx.wait();
      console.log(`[EmergencyFund] Treasury wallet deployed: ${addr}`);
    } catch (e) {
      console.warn(`[EmergencyFund] Treasury deploy deferred: ${e.message}`);
    }
  }
  // Cache in system_stats for transparency screen
  await db.collection("system_stats").doc("emergency_fund").set({
    treasuryWallet: addr,
    walletType: "smart",
    lastUpdated: admin.firestore.FieldValue.serverTimestamp(),
  }, { merge: true });
  return addr;
}

/**
 * Implied $DIASPORA price oracle (USD per token).
 * Mirrors the client-side ValuationService formula so quotes are consistent.
 * Reads TGE stats + total users + fiat GDP from system_stats.
 *
 * Falls back to the base price of $0.001 if any input is missing.
 */
async function getDiasporaPriceUsd() {
  const basePrice = 0.001;
  try {
    const treasury = (await db.collection("system_stats").doc("treasury").get()).data() || {};
    const supplyDoc = (await db.collection("system_stats").doc("dsp_supply").get()).data() || {};
    const usersAgg = await db.collection("users").count().get();
    const totalUsers = usersAgg.data().count || 0;
    const totalMinted = Number(supplyDoc.totalMinted || treasury.totalMinted) || 0;
    const totalBurned =
      (Number(treasury.totalBurnedUtility) || 0) +
      (Number(treasury.burnedPoints) || 0) +
      (Number(treasury.totalBurnedTde) || 0);
    const currentEpoch = Number(treasury.currentEpoch) || 1;
    const fiatGdpUsd = Number(treasury.totalFiatGdpUsd || treasury.fiatGdpUsd) || 0;

    const networkMult = totalUsers > 0 ? Math.log(Math.max(totalUsers, 1)) / (Math.LN10 * 10) : 0;
    const rawDef = totalMinted > 0 ? totalBurned / totalMinted : 0;
    const deflation = Math.min(rawDef, 0.5);
    const epochScarcity = 1 + Math.max(currentEpoch, 1) * 0.1;
    const networkBaseline = basePrice * (1 + networkMult + deflation) * epochScarcity;

    const circulatingSupply = Number(treasury.circulatingSupply) || Math.max(totalMinted - totalBurned, 0);
    const gdpFloorPerToken = (circulatingSupply > 0 && fiatGdpUsd > 0) ? (fiatGdpUsd / circulatingSupply) : 0;

    return networkBaseline + gdpFloorPerToken;
  } catch (e) {
    console.warn(`[EmergencyFund] Price oracle fallback to base: ${e.message}`);
    return basePrice;
  }
}

// ===================================================================
// Callable: getEmergencyFundContributionQuote
// Returns { usd, pricePerToken, amountDiaspora } — how much $DIASPORA the user must pay.
// ===================================================================
exports.getEmergencyFundContributionQuote = functions.https.onCall(async (data, context) => {
  if (!context.auth) throw new functions.https.HttpsError("unauthenticated", "Sign in required");
  const price = await getDiasporaPriceUsd();
  const amountDiaspora = Math.ceil(CONTRIBUTION_USD / price);
  return {
    usd: CONTRIBUTION_USD,
    pricePerToken: price.toFixed(6),
    amountDiaspora,
  };
});

// ===================================================================
// Callable: payEmergencyFundInDiaspora
// Transfers the $100-equivalent $DIASPORA from the user's smart wallet
// to the fund treasury wallet. On success: activates membership, marks
// promissory as refunded, writes ledger row.
// ===================================================================
exports.payEmergencyFundInDiaspora = functions
  .runWith({ secrets: ["BACKEND_SIGNER_PRIVATE_KEY"], timeoutSeconds: 120 })
  .https.onCall(async (data, context) => {
    if (!context.auth) throw new functions.https.HttpsError("unauthenticated", "Sign in required");
    const userId = context.auth.uid;

    // 1. Resolve user wallet
    const userDoc = await db.collection("users").doc(userId).get();
    const userWallet = userDoc.exists ? userDoc.data().walletAddress : null;
    if (!userWallet) throw new functions.https.HttpsError("failed-precondition", "No wallet — verify your phone first.");

    // 2. Quote price + treasury wallet
    const price = await getDiasporaPriceUsd();
    const amountDiaspora = Math.ceil(CONTRIBUTION_USD / price);
    const infra = getSmartWalletInfra();
    const treasury = await getFundTreasuryAddress(infra);
    const token = new ethers.Contract(getTokenAddress(), ERC20_ABI, infra.signer);
    const decimals = await token.decimals();
    const amountWei = ethers.parseUnits(String(amountDiaspora), decimals);

    // 5. Check on-chain balance
    const balance = await token.balanceOf(userWallet);
    if (balance < amountWei) {
      throw new functions.https.HttpsError("failed-precondition",
        `Insufficient $DIASPORA: have ${ethers.formatUnits(balance, decimals)}, need ${amountDiaspora}`);
    }

    // 6. Execute transfer via user's smart wallet (backend signer is the owner)
    const userSmartWallet = new ethers.Contract(userWallet, SMART_WALLET_ABI, infra.signer);
    const tx = await userSmartWallet.transferToken(getTokenAddress(), treasury, amountWei);
    const receipt = await tx.wait();
    const txHash = receipt.hash;
    console.log(`[EmergencyFund] User ${userId} paid ${amountDiaspora} $DIASPORA → ${treasury} (${txHash})`);

    // 7. Activate membership + refund promissory + write ledger row
    const batch = db.batch();
    batch.set(db.collection("emergency_fund_memberships").doc(userId), {
      userId,
      status: "active",
      isBetaAccess: false,
      paidAmountDiaspora: amountDiaspora,
      paidAmountUsdEquivalent: CONTRIBUTION_USD,
      paymentTxHash: txHash,
      paidAt: admin.firestore.FieldValue.serverTimestamp(),
      nextPaymentDate: admin.firestore.Timestamp.fromDate(new Date(Date.now() + 365 * 86400 * 1000)),
      annualContribution: CONTRIBUTION_USD,
      joinedDate: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });

    batch.set(db.collection("emergency_fund_stakers").doc(userId), {
      status: "contributed",
      contributedAt: admin.firestore.FieldValue.serverTimestamp(),
      paymentTxHash: txHash,
    }, { merge: true });

    const ledgerRef = db.collection("emergency_fund_ledger").doc();
    batch.set(ledgerRef, {
      kind: "contribution",
      userId,
      fromWallet: userWallet,
      toWallet: treasury,
      amountDiaspora,
      amountUsdEquivalent: CONTRIBUTION_USD,
      pricePerToken: price,
      txHash,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    // PoCT +10 incentive
    const trustRef = db.collection("trust_scores").doc(userId);
    batch.set(trustRef, {
      poct: admin.firestore.FieldValue.increment(10),
      lastPoctAwardReason: "emergency_fund_contribution",
      lastPoctAwardAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });

    await batch.commit();

    return { success: true, txHash, amountDiaspora, treasury };
  });

// ===================================================================
// Callable: getEmergencyFundStats
// Public-ish transparency endpoint: returns treasury balance, totals,
// staker count. Anyone authenticated can read.
// ===================================================================
exports.getEmergencyFundStats = functions
  .runWith({ secrets: ["BACKEND_SIGNER_PRIVATE_KEY"] })
  .https.onCall(async (data, context) => {
    if (!context.auth) throw new functions.https.HttpsError("unauthenticated", "Sign in required");

    const stakerAgg = await db.collection("emergency_fund_stakers").count().get();
    const stakerCount = stakerAgg.data().count || 0;
    const membersAgg = await db.collection("emergency_fund_memberships")
      .where("status", "==", "active").count().get();
    const activeMembers = membersAgg.data().count || 0;

    let treasuryAddress = null;
    let treasuryBalance = "0";
    try {
      const infra = getSmartWalletInfra();
      treasuryAddress = await getFundTreasuryAddress(infra);
      const token = new ethers.Contract(getTokenAddress(), ERC20_ABI, infra.provider);
      const [bal, decimals] = await Promise.all([
        token.balanceOf(treasuryAddress),
        token.decimals(),
      ]);
      treasuryBalance = ethers.formatUnits(bal, decimals);
    } catch (e) {
      console.warn(`[EmergencyFund] Stats: balance fetch failed: ${e.message}`);
    }

    return {
      treasuryAddress,
      treasuryBalanceDiaspora: treasuryBalance,
      promissoryDspLocked: stakerCount * PROMISSORY_DSP,
      stakerCount,
      activeMembers,
    };
  });

// ===================================================================
// Firestore trigger: onEmergencyClaimWrite
// When a claim's status transitions to "approved", auto-disburse
// from treasury to the recipient's wallet, then write ledger row.
// Admins set status=approved + payoutAmountUsd on the claim doc.
// ===================================================================
exports.onEmergencyClaimWrite = functions
  .runWith({ secrets: ["BACKEND_SIGNER_PRIVATE_KEY"], timeoutSeconds: 120 })
  .firestore.document("emergency_fund_claims/{claimId}")
  .onWrite(async (change, context) => {
    if (!change.after.exists) return null;
    const after = change.after.data();
    const before = change.before.exists ? change.before.data() : {};
    if (after.status !== "approved" || before.status === "approved") return null;
    if (after.payoutTxHash) return null; // idempotency guard

    const claimId = context.params.claimId;
    const payoutUsd = Number(after.payoutAmountUsd) || 0;
    if (payoutUsd <= 0) {
      console.warn(`[EmergencyFund] Claim ${claimId} approved with no payoutAmountUsd — skipping disbursement`);
      return null;
    }

    // Recipient wallet — prefer explicit beneficiaryWallet, fall back to claimant's wallet
    let recipientWallet = after.beneficiaryWallet || null;
    let recipientUserId = after.beneficiaryUserId || after.userId;
    if (!recipientWallet && recipientUserId) {
      const u = await db.collection("users").doc(recipientUserId).get();
      recipientWallet = u.exists ? u.data().walletAddress : null;
    }
    if (!recipientWallet) {
      console.error(`[EmergencyFund] Claim ${claimId}: no recipient wallet`);
      await change.after.ref.update({ disbursementError: "no_recipient_wallet" });
      return null;
    }

    // Per-beneficiary abuse guardrails: 90-day cooldown + annual USD cap.
    // We scope to beneficiaryUserId (or userId if absent) so collusion
    // between distinct accounts is the only way around the cap.
    try {
      const beneficiaryKey = recipientUserId;
      if (beneficiaryKey) {
        const cooldownCutoff = admin.firestore.Timestamp.fromMillis(
          Date.now() - PAYOUT_COOLDOWN_DAYS * 86400 * 1000
        );
        const recentSnap = await db.collection("emergency_fund_ledger")
          .where("kind", "==", "disbursement")
          .where("beneficiaryUserId", "==", beneficiaryKey)
          .where("createdAt", ">=", cooldownCutoff)
          .get();
        if (!recentSnap.empty) {
          const msg = `cooldown_violation: beneficiary ${beneficiaryKey} received a disbursement within ${PAYOUT_COOLDOWN_DAYS} days`;
          console.warn(`[EmergencyFund] ${msg}`);
          await change.after.ref.update({ disbursementError: msg, status: "rejected" });
          return null;
        }
        const yearCutoff = admin.firestore.Timestamp.fromMillis(
          Date.now() - 365 * 86400 * 1000
        );
        const yearSnap = await db.collection("emergency_fund_ledger")
          .where("kind", "==", "disbursement")
          .where("beneficiaryUserId", "==", beneficiaryKey)
          .where("createdAt", ">=", yearCutoff)
          .get();
        const yearTotal = yearSnap.docs.reduce(
          (sum, d) => sum + (Number(d.data().amountUsdEquivalent) || 0), 0
        );
        if (yearTotal + payoutUsd > PAYOUT_ANNUAL_CAP_USD) {
          const msg = `annual_cap_exceeded: beneficiary ${beneficiaryKey} would exceed $${PAYOUT_ANNUAL_CAP_USD}/yr (current $${yearTotal} + payout $${payoutUsd})`;
          console.warn(`[EmergencyFund] ${msg}`);
          await change.after.ref.update({ disbursementError: msg, status: "rejected" });
          return null;
        }
      }
    } catch (e) {
      console.warn(`[EmergencyFund] Cap check failed (proceeding): ${e.message}`);
    }

    try {
      const infra = getSmartWalletInfra();
      const treasury = await getFundTreasuryAddress(infra);
      const price = await getDiasporaPriceUsd();
      const amountDiaspora = Math.ceil(payoutUsd / price);
      const token = new ethers.Contract(getTokenAddress(), ERC20_ABI, infra.signer);
      const decimals = await token.decimals();
      const amountWei = ethers.parseUnits(String(amountDiaspora), decimals);

      const treasuryWallet = new ethers.Contract(treasury, SMART_WALLET_ABI, infra.signer);
      const tx = await treasuryWallet.transferToken(getTokenAddress(), recipientWallet, amountWei);
      const receipt = await tx.wait();
      const txHash = receipt.hash;
      console.log(`[EmergencyFund] Claim ${claimId} disbursed ${amountDiaspora} $DIASPORA → ${recipientWallet} (${txHash})`);

      const batch = db.batch();
      batch.update(change.after.ref, {
        status: "paid",
        payoutTxHash: txHash,
        payoutAmountDiaspora: amountDiaspora,
        payoutPricePerToken: price,
        paidAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      batch.set(db.collection("emergency_fund_ledger").doc(), {
        kind: "disbursement",
        claimId,
        emergencyType: after.type || null,
        userId: after.userId,
        beneficiaryUserId: recipientUserId,
        beneficiaryName: after.beneficiaryName || null,
        beneficiaryCountry: after.beneficiaryCountry || null,
        relationship: after.relationship || null,
        description: after.description || null,
        fromWallet: treasury,
        toWallet: recipientWallet,
        amountDiaspora,
        amountUsdEquivalent: payoutUsd,
        pricePerToken: price,
        txHash,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      await batch.commit();
    } catch (e) {
      console.error(`[EmergencyFund] Disbursement failed for ${claimId}: ${e.message}`);
      await change.after.ref.update({
        disbursementError: (e.message || "unknown").slice(0, 500),
        disbursementErrorAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }
    return null;
  });

// ===================================================================

// Callable: slashPromissoryForFraud (admin only)

// Marks a staker as slashed when a claim is later found fraudulent.

// Writes a transparent ledger row so the slash is publicly auditable.

// ===================================================================

exports.slashPromissoryForFraud = functions.https.onCall(async (data, context) => {

  if (!context.auth) throw new functions.https.HttpsError("unauthenticated", "Sign in required");

  const callerDoc = await db.collection("users").doc(context.auth.uid).get();

  if (!callerDoc.exists || !callerDoc.data().isAdmin) {

    throw new functions.https.HttpsError("permission-denied", "Admin only");

  }

  const { userId, claimId, reason } = data || {};

  if (!userId || !reason) throw new functions.https.HttpsError("invalid-argument", "userId + reason required");



  const stakerRef = db.collection("emergency_fund_stakers").doc(userId);

  const stakerSnap = await stakerRef.get();

  if (!stakerSnap.exists) throw new functions.https.HttpsError("not-found", "Staker not found");

  if (stakerSnap.data().status === "slashed") {

    return { success: true, alreadySlashed: true };

  }



  const batch = db.batch();

  batch.set(stakerRef, {

    status: "slashed",

    slashedAt: admin.firestore.FieldValue.serverTimestamp(),

    slashedBy: context.auth.uid,

    slashReason: String(reason).slice(0, 500),

    slashClaimId: claimId || null,

  }, { merge: true });



  batch.set(db.collection("emergency_fund_ledger").doc(), {

    kind: "slash",

    userId,

    claimId: claimId || null,

    amountDspSlashed: PROMISSORY_DSP,

    reason: String(reason).slice(0, 500),

    slashedBy: context.auth.uid,

    createdAt: admin.firestore.FieldValue.serverTimestamp(),

  });



  // Membership lapses on slash

  batch.set(db.collection("emergency_fund_memberships").doc(userId), {

    status: "inactive",

    slashedAt: admin.firestore.FieldValue.serverTimestamp(),

  }, { merge: true });



  await batch.commit();

  console.log(`[EmergencyFund] Slashed ${userId} promissory (claim=${claimId}): ${reason}`);

  return { success: true, slashedDsp: PROMISSORY_DSP };

});

/**
 * stakeEmergencyFundPromissory — Backward compatibility stub.
 * Promissory staking is deprecated as all users can contribute directly.
 */
exports.stakeEmergencyFundPromissory = functions.https.onCall(async (data, context) => {
  if (!context.auth) throw new functions.https.HttpsError("unauthenticated", "Sign in required");
  return { success: true, legacy: true, message: "Promissory staking is no longer required." };
});

/**
 * submitEmergencyClaim — Submits a support claim to the Ubuntu Emergency Fund.
 * Enforces minimum 100 days active account age and 3-tier limits:
 *   - Standard Tier: <= $1,000 USD
 *   - Fast-Track Tier: $1,001 to $50,000 USD (Authorized within 24h by Town & Country Secretaries)
 *   - Community Vote Tier: Over $50,000 USD (Requires 10 full trust score members, 51% approval in 48h community vote)
 */
exports.submitEmergencyClaim = functions.https.onCall(async (data, context) => {
  if (!context.auth) throw new functions.https.HttpsError("unauthenticated", "Sign in required");
  const userId = context.auth.uid;
  const input = data || {};

  const userDoc = await db.collection("users").doc(userId).get();
  if (!userDoc.exists) {
    throw new functions.https.HttpsError("not-found", "User profile not found.");
  }
  const userData = userDoc.data();

  // Enforce minimum 100 days active account age
  let daysActive = 0;
  if (userData.createdAt) {
    const created = userData.createdAt.toDate ? userData.createdAt.toDate() : new Date(userData.createdAt);
    daysActive = Math.floor((Date.now() - created.getTime()) / (1000 * 60 * 60 * 24));
  }
  if (daysActive < 100) {
    throw new functions.https.HttpsError(
      "failed-precondition",
      `Emergency Fund claims require a minimum of 100 days of active community membership (Current: ${daysActive} days).`
    );
  }

  const requestedAmountUsd = Number(input.requestedAmountUsd || input.amountUsd || 0);
  if (!Number.isFinite(requestedAmountUsd) || requestedAmountUsd <= 0) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "Requested claim amount must be greater than $0."
    );
  }

  const tier = requestedAmountUsd <= 1000
    ? "standard"
    : (requestedAmountUsd <= 50000 ? "fast_track" : "community_vote");

  const claimRef = db.collection("emergency_fund_claims").doc();
  const now = admin.firestore.FieldValue.serverTimestamp();

  await claimRef.set({
    id: claimRef.id,
    userId,
    claimantName: `${userData.firstName || ""} ${userData.lastName || ""}`.trim() || "Member",
    claimantWallet: userData.walletAddress || null,
    emergencyType: input.emergencyType || input.type || "General Emergency",
    description: String(input.description || "").slice(0, 3000),
    beneficiaryName: input.beneficiaryName || `${userData.firstName || ""} ${userData.lastName || ""}`.trim(),
    beneficiaryCountry: input.beneficiaryCountry || userData.homeCountry || null,
    relationship: input.relationship || "Self",
    requestedAmountUsd,
    payoutAmountUsd: requestedAmountUsd,
    tier,
    status: tier === "community_vote" ? "pending_community_vote" : "pending",
    requiresCommunityVote: tier === "community_vote",
    communityVoteQuorum: tier === "community_vote" ? 10 : 0,
    communityVoteApprovalThreshold: tier === "community_vote" ? 0.51 : 0,
    communityVoteWindowHours: tier === "community_vote" ? 48 : 0,
    daysActiveAtSubmission: daysActive,
    createdAt: now,
    updatedAt: now,
  });

  return {
    success: true,
    claimId: claimRef.id,
    tier,
    requestedAmountUsd,
  };
});
