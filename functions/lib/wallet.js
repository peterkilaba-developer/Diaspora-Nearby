/**
 * Smart Wallet / Account Abstraction module.
 * 
 * ALL wallets are now Smart Contract Wallets via DiasporaWalletFactory (CREATE2).
 * EOA wallet generation has been fully removed to eliminate MSB/VASP exposure.
 * 
 * Architecture:
 * - Phone number → HMAC with server secret → CREATE2 salt → deterministic wallet address
 * - No private keys stored per-user (backend signer controls all wallets)
 * - Gasless transactions for users (backend pays gas)
 * - Wallet addresses can be computed BEFORE deployment
 */
const { functions, admin, db } = require("./shared");
const { requireAdmin, requireAppCheck, requireAuth } = require("./security");
const { ethers } = require("ethers");
const crypto = require("crypto");
const { parsePhoneNumberFromString } = require("libphonenumber-js");

// ── Smart Wallet Factory ABI (minimal interface) ──
const WALLET_FACTORY_ABI = [
  "function computeAddress(bytes32 phoneHash) view returns (address)",
  "function createWallet(bytes32 phoneHash) returns (address)",
  "function walletExists(bytes32 phoneHash) view returns (bool)",
  "function getWallet(bytes32 phoneHash) view returns (address)",
  "function migrateWallet(bytes32 oldPhoneHash, bytes32 newPhoneHash)",
];

const SMART_WALLET_ABI = [
  "function execute(address target, uint256 value, bytes data) returns (bytes)",
  "function transferToken(address token, address to, uint256 amount) returns (bool)",
  "function owner() view returns (address)",
];

// ── Configuration ──
// Do NOT cache process.env at module-load time. With Firebase Functions v1
// secrets, the secret is mounted before handlers run, but caching at module
// scope made one silent-skip bug already (2026-06-02). Use assertOnChainConfig
// from inside each handler so missing config is a loud, named error.
const { assertOnChainConfig } = require("./on_chain_config");

const TGE_CONTROLLER_ABI = [
  "function executeTGE(address[] recipients, uint256[] amounts, uint8[] efficiencies, bytes32 merkleRoot) external",
  "function distributeWelcomeBonus(address userRecipient, uint256 userAmount, address[] treasuryRecipients, uint256[] treasuryAmounts, bytes32 merkleRoot) external",
  "function distributeGenesisTokens(address userRecipient, uint256 userAmount, address[] treasuryRecipients, uint256[] treasuryAmounts, bytes32 merkleRoot) external",
  "function claimTdeTokens(address recipient, uint256 epoch, uint256 tdeEvent, uint256 earnedAmount, uint8 efficiency, bytes32[] proof) external",
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

/**
 * Get the configured provider and signer for smart wallet operations.
 * Throws (NOT returns null) if config missing — callers must rely on this
 * for fail-loud behavior. Previously returned null on missing config, which
 * forced every caller to handle the null case and risked inconsistent behavior.
 */
function getSmartWalletInfra() {
  const cfg = assertOnChainConfig("getSmartWalletInfra", [
    "walletFactoryAddress",
    "backendSignerKey",
    "rpcUrl",
  ]);
  const provider = new ethers.JsonRpcProvider(cfg.rpcUrl);
  const signer = new ethers.Wallet(cfg.backendSignerKey, provider);
  const factory = new ethers.Contract(cfg.walletFactoryAddress, WALLET_FACTORY_ABI, signer);
  return { provider, signer, factory };
}

/**
 * Compute a keyed, opaque wallet identifier used as the CREATE2 salt.
 *
 * Normalizes via libphonenumber-js to canonical E.164 so that the salt is
 * insensitive to client-side formatting variations (spaces, dashes, retained
 * national trunk prefix). This is load-bearing: the hash is the salt for
 * CREATE2 wallet deployment, so two clients passing the "same" number in
 * different surface forms MUST produce the same hash, otherwise the same
 * person ends up with two distinct wallet addresses.
 *
 * Audited 2026-06-02: zero existing Firebase Auth users had a trunk-prefix
 * mismatch between stored phone and canonical E.164, so promoting the
 * normalization here is safe (no existing CREATE2 address would shift).
 */
function computePhoneHash(phoneNumber) {
  const trimmed = (phoneNumber || "").trim();
  if (!trimmed) {
    throw new Error("computePhoneHash: empty phone number");
  }

  const parsed = parsePhoneNumberFromString(trimmed);
  let normalized;
  if (parsed && parsed.isValid()) {
    normalized = parsed.number; // E.164, leading "+"
  } else {
    // Fall back to the legacy minimal normalization so an unparseable but
    // pre-existing string still hashes the same as before. Loud-log so we
    // can investigate any production occurrences.
    console.warn("[computePhoneHash] Invalid stored phone format; using normalized fallback");
    normalized = trimmed.replace(/\s+/g, "");
    if (!normalized.startsWith("+")) normalized = "+" + normalized;
  }
  const pepper = process.env.WALLET_ID_PEPPER;
  if (!pepper || pepper.length < 32) {
    throw new Error("computePhoneHash: WALLET_ID_PEPPER is missing or too short");
  }
  return `0x${crypto.createHmac("sha256", pepper).update(normalized).digest("hex")}`;
}

/**
 * Create a smart wallet for a given phone number.
 * Returns { address, phoneHash, isSmartWallet: true }.
 * No EOA fallback — throws if factory is unavailable.
 */
async function createSmartWalletForPhone(phoneNumber) {
  const infra = getSmartWalletInfra(); // throws if config missing

  const phoneHash = computePhoneHash(phoneNumber);

  // Check if wallet already exists
  const existingWallet = await infra.factory.getWallet(phoneHash);
  if (existingWallet !== ethers.ZeroAddress) {
    console.log(`[SmartWallet] Wallet already exists for phone hash: ${existingWallet}`);
    return { address: existingWallet, isSmartWallet: true, phoneHash, deploymentPending: false };
  }

  // Compute the deterministic address (pre-deployment)
  const predictedAddress = await infra.factory.computeAddress(phoneHash);
  console.log(`[SmartWallet] Predicted address for phone: ${predictedAddress}`);

  try {
    const tx = await infra.factory.createWallet(phoneHash);
    const receipt = await tx.wait();
    console.log(`[SmartWallet] Created smart wallet: ${predictedAddress} (tx: ${receipt.hash})`);
    return {
      address: predictedAddress,
      isSmartWallet: true,
      phoneHash,
      txHash: receipt.hash,
      deploymentPending: false,
    };
  } catch (error) {
    // CREATE2 addresses are deterministic, so the address is still valid even
    // if deployment failed. The wallet can be deployed later by the healing
    // function `retryPendingWalletDeployments` (the contract code at this
    // address won't exist until then, but ERC-20 transfers to it still work
    // and accumulate balance that the deployed wallet can later move).
    //
    // We return `deploymentPending: true` so the caller can store this flag.
    // Previously the flag was dropped on the floor; now callers MUST handle it.
    console.error(`[SmartWallet] On-chain deployment failed for ${predictedAddress}: ${error.message}`);
    return {
      address: predictedAddress,
      isSmartWallet: true,
      phoneHash,
      deploymentPending: true,
      deploymentError: (error.message || "unknown").slice(0, 500),
    };
  }
}

/**
 * Create a deterministic wallet for a community using its ID as salt.
 * No EOA fallback — throws if factory is unavailable.
 */
async function createSmartWalletForCommunity(communityId) {
  const infra = getSmartWalletInfra(); // throws on missing config

  const salt = ethers.keccak256(ethers.toUtf8Bytes(`community:${communityId}`));

  const existingWallet = await infra.factory.getWallet(salt);
  if (existingWallet !== ethers.ZeroAddress) {
    return { address: existingWallet, isSmartWallet: true, deploymentPending: false };
  }

  const predictedAddress = await infra.factory.computeAddress(salt);

  try {
    const tx = await infra.factory.createWallet(salt);
    await tx.wait();
    console.log(`[SmartWallet] Created community wallet: ${predictedAddress}`);
    return { address: predictedAddress, isSmartWallet: true, deploymentPending: false };
  } catch (error) {
    console.error(`[SmartWallet] Community wallet deployment failed for ${communityId} (${predictedAddress}): ${error.message}`);
    return {
      address: predictedAddress,
      isSmartWallet: true,
      deploymentPending: true,
      deploymentError: (error.message || "unknown").slice(0, 500),
    };
  }
}

// ── 1. Auto-create Smart Wallet for Communities ──
exports.onCommunityWrite = functions
  .runWith({ secrets: ["BACKEND_SIGNER_PRIVATE_KEY"] })
  .firestore.document("communities/{communityId}")
  .onWrite(async (change, context) => {
    if (!change.after.exists) return null;

    const newData = change.after.data();
    const communityId = context.params.communityId;

    // Skip if wallet already assigned
    if (newData.walletAddress) return null;

    console.log(`[Wallet] Creating smart wallet for Community: ${communityId}`);

    try {
      const walletResult = await createSmartWalletForCommunity(communityId);

      // Always store the predicted address. If deploymentPending is true, the
      // contract isn't deployed at that CREATE2 address yet — that's recorded
      // so the healing function `retryPendingWalletDeployments` can complete
      // the deploy later. ERC-20 transfers TO this address still work (tokens
      // accumulate at the address) but execute()/transferToken() calls from
      // it require the contract to be deployed first.
      const update = {
        walletAddress: walletResult.address,
        walletGeneratedAt: admin.firestore.FieldValue.serverTimestamp(),
        walletType: "smart",
      };
      if (walletResult.deploymentPending) {
        update.walletDeploymentPending = true;
        update.walletDeploymentError = walletResult.deploymentError || "unknown";
        update.walletDeploymentErrorAt = admin.firestore.FieldValue.serverTimestamp();
      } else {
        update.walletDeploymentPending = false;
      }
      await change.after.ref.update(update);

      // Also update the governance doc so TGE can snapshot this treasury
      const govId = communityId === "global_community"
        ? "global_community"
        : (communityId.includes("_") ? communityId.substring(communityId.indexOf("_") + 1) : communityId);

      await db.collection("governance").doc(govId).set({
        walletAddress: walletResult.address,
        walletType: "smart",
        communityId: communityId,
        type: "community",
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });

      console.log(`[Wallet] Assigned ${walletResult.address} to Community ${communityId} (smart, pending=${!!walletResult.deploymentPending})`);
    } catch (e) {
      // Catastrophic failure (e.g., config missing). Record observable state
      // so the healing function can retry. Previously this was a console.error
      // and silent skip — the community had no wallet, no error trail.
      console.error(`[Wallet] Failed to create community wallet for ${communityId}: ${e.message}`);
      await change.after.ref.update({
        walletDeploymentPending: true,
        walletDeploymentError: (e.message || "unknown").slice(0, 500),
        walletDeploymentErrorAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }
  });

// ── 2. Auto-create Smart Wallet for Users (Phone-based) ──
exports.onUserWrite = functions
  .runWith({ secrets: ["BACKEND_SIGNER_PRIVATE_KEY", "WALLET_ID_PEPPER"] })
  .firestore
  .document("users/{userId}")
  .onWrite(async (change, context) => {
    if (!change.after.exists) return null;

    const newData = change.after.data();
    const userId = context.params.userId;

    // Skip if wallet already assigned
    if (newData.walletAddress) return null;

    // Get the user's phone number from Firebase Auth
    let phoneNumber = newData.phoneNumber || null;

    if (!phoneNumber) {
      try {
        const userRecord = await admin.auth().getUser(userId);
        phoneNumber = userRecord.phoneNumber || null;
      } catch (e) {
        console.log(`[Wallet] Could not get auth record for ${userId}: ${e.message}`);
      }
    }

    if (phoneNumber) {
      // ── SMART WALLET: Use phone number for deterministic address ──
      console.log(`[SmartWallet] Creating phone-based wallet for User: ${userId}`);

      try {
        const walletResult = await createSmartWalletForPhone(phoneNumber);

        const update = {
          walletAddress: walletResult.address,
          walletGeneratedAt: admin.firestore.FieldValue.serverTimestamp(),
          walletType: "smart",
          walletPhoneHash: walletResult.phoneHash || null,
          walletSaltVersion: 2,
        };
        if (walletResult.deploymentPending) {
          update.walletDeploymentPending = true;
          update.walletDeploymentError = walletResult.deploymentError || "unknown";
          update.walletDeploymentErrorAt = admin.firestore.FieldValue.serverTimestamp();
        } else {
          update.walletDeploymentPending = false;
        }
        await change.after.ref.update(update);

        console.log(`[SmartWallet] Assigned ${walletResult.address} to User ${userId} (smart, pending=${!!walletResult.deploymentPending})`);
      } catch (e) {
        // Catastrophic failure (e.g., config missing or transient). Record
        // observable state so the healing function can retry. Previously this
        // was a silent console.error.
        console.error(`[SmartWallet] Failed to create user wallet for ${userId}: ${e.message}`);
        await change.after.ref.update({
          walletDeploymentPending: true,
          walletDeploymentError: (e.message || "unknown").slice(0, 500),
          walletDeploymentErrorAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      }
    } else {
      // No phone number available yet — wallet will be created when phone is verified
      console.log(`[Wallet] No phone number for User ${userId}. Wallet creation deferred until phone verification.`);
    }
  });

// ── 3. Callable: Get or Create Smart Wallet ──
// Called explicitly from the Flutter app after phone authentication.
exports.getOrCreateSmartWallet = functions
  .runWith({ secrets: ["BACKEND_SIGNER_PRIVATE_KEY", "WALLET_ID_PEPPER"] })
  .https.onCall(async (data, context) => {
  requireAppCheck(context);
  const userId = requireAuth(context);

  // 1. Check if user already has a SMART wallet (no action needed)
  const userDoc = await db.collection("users").doc(userId).get();
  const existingWalletType = userDoc.exists ? (userDoc.data().walletType || null) : null;
  const existingAddress = userDoc.exists ? userDoc.data().walletAddress : null;

  if (existingAddress && existingWalletType === "smart") {
    return {
      success: true,
      address: existingAddress,
      walletType: "smart",
      alreadyExisted: true,
    };
  }

  // 2. Get phone number from Firebase Auth
  let phoneNumber = null;
  try {
    const userRecord = await admin.auth().getUser(userId);
    phoneNumber = userRecord.phoneNumber;
  } catch (e) {
    console.error(`[SmartWallet] Failed to get auth record: ${e.message}`);
  }

  if (!phoneNumber) {
    phoneNumber = userDoc.exists ? userDoc.data().phoneNumber : null;
  }

  if (!phoneNumber) {
    throw new functions.https.HttpsError(
      "failed-precondition",
      "No phone number found. Complete phone verification first."
    );
  }

  // 2b. Dedupe: refuse if a DIFFERENT user already owns the wallet derived
  // from this phone. Wallet addresses are deterministic on phoneHash, so
  // letting two Firebase users bind to the same on-chain wallet would mean
  // both can spend the same balance.
  const phoneHash = computePhoneHash(phoneNumber);
  const collisionSnap = await db
    .collection("users")
    .where("walletPhoneHash", "==", phoneHash)
    .limit(2)
    .get();
  const collidingUid = collisionSnap.docs
    .map((d) => d.id)
    .find((uid) => uid !== userId);
  if (collidingUid) {
    console.warn(
      `[SmartWallet] Phone hash collision: ${userId} tried to bind a phone already linked to ${collidingUid}`
    );
    throw new functions.https.HttpsError(
      "already-exists",
      "This phone number is already linked to another account. Sign in with SMS verification using that phone, or use a different phone number."
    );
  }

  // 3. Create smart wallet (or retrieve existing one for this phone)
  const walletResult = await createSmartWalletForPhone(phoneNumber);

  // 4. Save wallet data + observable deployment state
  const userUpdate = {
    walletAddress: walletResult.address,
    walletGeneratedAt: admin.firestore.FieldValue.serverTimestamp(),
    walletType: "smart",
    walletPhoneHash: walletResult.phoneHash || null,
    walletSaltVersion: 2,
  };
  if (walletResult.deploymentPending) {
    userUpdate.walletDeploymentPending = true;
    userUpdate.walletDeploymentError = walletResult.deploymentError || "unknown";
    userUpdate.walletDeploymentErrorAt = admin.firestore.FieldValue.serverTimestamp();
  } else {
    userUpdate.walletDeploymentPending = false;
  }
  await db.collection("users").doc(userId).set(userUpdate, { merge: true });

  // 5. Also update user_points collection
  await db.collection("user_points").doc(userId).set(
    { walletAddress: walletResult.address },
    { merge: true }
  );

  console.log(`[SmartWallet] Wallet for ${userId}: ${walletResult.address} (smart)`);

  return {
    success: true,
    address: walletResult.address,
    walletType: "smart",
    alreadyExisted: false,
  };
});

// ── 4. System & Community Treasury Wallets (Callable) ──
// Creates smart wallets for the spendable system treasuries (founders,
// liquidity/investors) and records the canonical burn address. Writes
// walletAddress to governance docs so TGE can snapshot them.
//
// Burn is special: it is always 0x000…dEaD, never a smart wallet, so that
// burned tokens are irrecoverable by anyone (including the backend signer).

/**
 * Helper: Create a deterministic smart wallet for a system treasury.
 * @param {object} infra - Smart wallet infrastructure (provider, signer, factory)  
 * @param {string} label - Unique identifier, e.g. "system:founders_treasury"
 * @returns {{ address: string, alreadyExisted: boolean }}
 */
async function createSystemTreasuryWallet(infra, label) {
  const salt = ethers.keccak256(ethers.toUtf8Bytes(label));

  // Check if already deployed
  const existingWallet = await infra.factory.getWallet(salt);
  if (existingWallet !== ethers.ZeroAddress) {
    console.log(`[SmartWallet] ${label} wallet already exists: ${existingWallet}`);
    return { address: existingWallet, alreadyExisted: true };
  }

  // Deploy
  const tx = await infra.factory.createWallet(salt);
  await tx.wait();
  const walletAddress = await infra.factory.getWallet(salt);
  console.log(`[SmartWallet] Created ${label} wallet: ${walletAddress}`);
  return { address: walletAddress, alreadyExisted: false };
}

/**
 * ensureSystemWallets — Provisions the system treasury addresses:
 *   1. Founders Treasury  — smart wallet (salt: "treasury:founders")
 *   2. Liquidity (DEX)    — Safe multisig, NOT created here (governance/liquidity.walletAddress
 *      is set manually via repoint-treasury-wallet.js after the Safe is deployed)
 *   3. Burn               — fixed dead address 0x000…dEaD (NOT a smart wallet)
 *
 * The legacy `investors` slot was removed on 2026-06-04 — see
 * functions/scripts/migrate-investors-to-liquidity.js. Re-running this function
 * is now safe and will NOT clobber any of the Safe-managed treasuries.
 *
 * Writes walletAddress into governance/{founders,burn} so TGE performTGE()
 * can snapshot balances. The burn entry is recorded for audit/UI consistency
 * only; no on-chain wallet exists for it. Liquidity's walletAddress is left
 * untouched (assumed to already point at the Safe).
 */
exports.ensureSystemWallets = functions
  .runWith({ timeoutSeconds: 120, memory: "256MB", secrets: ["BACKEND_SIGNER_PRIVATE_KEY"] })
  .https.onCall(async (data, context) => {
    requireAppCheck(context);
    const callerId = requireAdmin(context);

    // getSmartWalletInfra() throws via assertOnChainConfig if any required
    // env var is missing — surfaces a clear named error to the caller.
    const infra = getSmartWalletInfra();

    console.log(`[Wallet] ensureSystemWallets triggered by ${callerId}`);

    const results = {};

    // ── 1. Founders Treasury ──
    try {
      const founders = await createSystemTreasuryWallet(infra, "treasury:founders");
      results.founders = founders;

      // Write to system_stats/treasury
      await db.collection("system_stats").doc("treasury").set({
        foundersWallet: founders.address,
        foundersWalletType: "smart",
        ...(!founders.alreadyExisted && { foundersWalletGeneratedAt: admin.firestore.FieldValue.serverTimestamp() }),
      }, { merge: true });

      // Write walletAddress to governance doc (needed for TGE snapshot)
      await db.collection("governance").doc("founders").set({
        id: "founders",
        name: "Founders & Core Team",
        type: "system",
        title: "Founders Treasury",
        walletAddress: founders.address,
        walletType: "smart",
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });

      console.log(`[Wallet] ✅ Founders: ${founders.address} (${founders.alreadyExisted ? "existing" : "new"})`);
    } catch (e) {
      console.error(`[Wallet] ❌ Founders wallet failed: ${e.message}`);
      results.founders = { error: e.message };
    }

    // ── 2. Liquidity (DEX) Treasury ──
    // Post-2026-06-04: Liquidity is a Safe multisig, not a factory-created
    // smart wallet. governance/liquidity.walletAddress is set manually after
    // Safe deployment via functions/scripts/repoint-treasury-wallet.js — this
    // function intentionally does NOT touch governance/liquidity.walletAddress
    // so re-running ensureSystemWallets cannot clobber the Safe pointer.
    //
    // The deprecated `investors` slot is also intentionally NOT recreated here.
    // If governance/investors still exists in your project, it's an audit
    // artifact only (treasuryBalance should be 0 post-migration).
    results.liquidity = { skipped: "managed by Safe; see governance/liquidity" };
    console.log(`[Wallet] ⏭️  Liquidity: Safe-managed (no smart wallet to create)`);

    // ── 3. Burn Treasury ──
    // Burn is the canonical Ethereum dead address — NOT a smart wallet. A burn
    // wallet that the backend signer could move funds out of would defeat the
    // purpose ("burned" tokens must be unrecoverable by anyone, including us).
    // TGE/tribute distributions already send the burn slot directly to 0x...dEaD
    // (see dsp.js BURN_ADDRESS constants); this just records that fact in
    // Firestore for UI and audit consistency.
    try {
      const BURN_ADDRESS = "0x000000000000000000000000000000000000dEaD";

      await db.collection("system_stats").doc("treasury").set({
        burnWallet: BURN_ADDRESS,
        burnWalletType: "burn",
        burnWalletUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });

      await db.collection("governance").doc("burn").set({
        id: "burn",
        name: "Deflationary Burn",
        type: "system",
        title: "Burn Treasury",
        walletAddress: BURN_ADDRESS,
        walletType: "burn",
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });

      results.burn = { address: BURN_ADDRESS, alreadyExisted: true, external: true };
      console.log(`[Wallet] ✅ Burn: ${BURN_ADDRESS} (dead address — not a controllable wallet)`);
    } catch (e) {
      console.error(`[Wallet] ❌ Burn address record failed: ${e.message}`);
      results.burn = { error: e.message };
    }

    return {
      success: true,
      message: "System treasury wallets provisioned",
      wallets: results,
    };
  });

/**
 * ensureCommunityTreasuryWallets — Batch-backfill wallets for ALL existing communities.
 * 
 * For each community doc missing a walletAddress, creates a smart wallet using
 * the salt "community:{communityId}" and writes the address to both:
 *   - communities/{communityId}.walletAddress
 *   - governance/{govId}.walletAddress  (so TGE can snapshot it)
 * 
 * This is an admin-only callable for backfilling communities created before
 * the WalletFactory was deployed. New communities are handled automatically
 * by the onCommunityWrite trigger.
 */
exports.ensureCommunityTreasuryWallets = functions
  .runWith({ timeoutSeconds: 540, memory: "512MB", secrets: ["BACKEND_SIGNER_PRIVATE_KEY"] })
  .https.onCall(async (data, context) => {
    requireAppCheck(context);
    const callerId = requireAdmin(context);

    // getSmartWalletInfra() throws via assertOnChainConfig if any required
    // env var is missing — surfaces a clear named error to the caller.
    const infra = getSmartWalletInfra();

    console.log(`[Wallet] ensureCommunityTreasuryWallets triggered by ${callerId}`);

    const requestedLimit = Number(data && data.limit || 20);
    const limit = Number.isInteger(requestedLimit) ?
      Math.min(Math.max(requestedLimit, 1), 50) : 20;
    const cursor = data && data.cursor;
    if (cursor != null && (typeof cursor !== "string" || cursor.length > 1500)) {
      throw new functions.https.HttpsError("invalid-argument", "Invalid pagination cursor.");
    }
    let query = db.collection("communities")
      .orderBy(admin.firestore.FieldPath.documentId())
      .limit(limit);
    if (cursor) query = query.startAfter(cursor);
    const commSnap = await query.get();
    const results = { created: 0, skipped: 0, failed: 0, errors: [] };

    for (const doc of commSnap.docs) {
      const communityId = doc.id;
      const communityData = doc.data();

      // Skip if already has a wallet
      if (communityData.walletAddress) {
        results.skipped++;

        // But still ensure governance doc has the wallet address
        const govId = communityId === "global_community"
          ? "global_community"
          : (communityId.includes("_") ? communityId.substring(communityId.indexOf("_") + 1) : communityId);

        await db.collection("governance").doc(govId).set({
          walletAddress: communityData.walletAddress,
          walletType: "smart",
        }, { merge: true });

        continue;
      }

      try {
        const walletResult = await createSmartWalletForCommunity(communityId);

        // Write to community doc
        await doc.ref.update({
          walletAddress: walletResult.address,
          walletGeneratedAt: admin.firestore.FieldValue.serverTimestamp(),
          walletType: "smart",
        });

        // Write to governance doc (for TGE)
        const govId = communityId === "global_community"
          ? "global_community"
          : (communityId.includes("_") ? communityId.substring(communityId.indexOf("_") + 1) : communityId);

        await db.collection("governance").doc(govId).set({
          walletAddress: walletResult.address,
          walletType: "smart",
          communityId: communityId,
          type: "community",
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });

        results.created++;
        console.log(`[Wallet] ✅ Community ${communityId}: ${walletResult.address}`);
      } catch (e) {
        results.failed++;
        results.errors.push({ communityId, error: e.message });
        console.error(`[Wallet] ❌ Community ${communityId}: ${e.message}`);
      }
    }

    console.log(`[Wallet] Community wallets done: ${results.created} created, ${results.skipped} skipped, ${results.failed} failed`);

    return {
      success: true,
      message: `Community wallets: ${results.created} created, ${results.skipped} already had wallets, ${results.failed} failed`,
      nextCursor: commSnap.empty ? null : commSnap.docs[commSnap.docs.length - 1].id,
      hasMore: commSnap.size === limit,
      ...results,
    };
  });



/**
 * retryPendingWalletDeployments — heals users and community treasuries whose
 * smart-wallet on-chain deployment failed.
 *
 * The fail-loud refactor of onUserWrite / onCommunityWrite / createSmartWalletFor*
 * (2026-06-02) sets these fields whenever the factory.createWallet() call
 * fails (e.g., RPC error, insufficient gas, network blip):
 *   - walletDeploymentPending: true
 *   - walletDeploymentError: <reason>
 *   - walletDeploymentErrorAt: <timestamp>
 *
 * This function scans both `users` and `communities` for pending docs,
 * retries `factory.createWallet(salt)` for each, and clears the pending
 * fields on success.
 *
 * Safe to re-run — the factory's getWallet() check ensures we don't
 * double-deploy. If a wallet is already on-chain, the doc gets cleared
 * without any tx.
 *
 * Admin-only callable. Usage from client:
 *   const fn = firebase.functions().httpsCallable('retryPendingWalletDeployments');
 *   await fn({ scope: 'users', limit: 25 });
 *   await fn({ scope: 'communities', limit: 25 });
 *   await fn({ scope: 'both', limit: 50 });  // default
 *   await fn({ dryRun: true });              // just count
 */
exports.retryPendingWalletDeployments = functions
  .runWith({ timeoutSeconds: 540, memory: "512MB", secrets: ["BACKEND_SIGNER_PRIVATE_KEY"] })
  .https.onCall(async (data, context) => {
    requireAppCheck(context);
    requireAdmin(context);

    const infra = getSmartWalletInfra(); // throws on missing config
    const dryRun = data && data.dryRun === true;
    const limit = Math.min(Math.max(Number(data && data.limit) || 50, 1), 200);
    const scope = (data && data.scope) || "both";

    const results = {
      ok: true,
      scope,
      dryRun,
      users: { found: 0, succeeded: 0, skipped: 0, failed: 0, items: [] },
      communities: { found: 0, succeeded: 0, skipped: 0, failed: 0, items: [] },
    };

    async function attemptDeploy(salt, label) {
      // Idempotent: skip if already deployed on-chain
      const existing = await infra.factory.getWallet(salt);
      if (existing !== ethers.ZeroAddress) {
        return { alreadyDeployed: true, address: existing };
      }
      const predicted = await infra.factory.computeAddress(salt);
      if (dryRun) return { dryRun: true, address: predicted };
      const tx = await infra.factory.createWallet(salt);
      const receipt = await tx.wait();
      return { deployed: true, address: predicted, txHash: receipt.hash };
    }

    // ── Users ───────────────────────────────────────────────────────
    if (scope === "users" || scope === "both") {
      const snap = await db.collection("users")
        .where("walletDeploymentPending", "==", true)
        .limit(limit)
        .get();
      results.users.found = snap.size;
      for (const doc of snap.docs) {
        const uid = doc.id;
        const u = doc.data();
        try {
          if (!u.walletPhoneHash) {
            results.users.skipped++;
            results.users.items.push({ uid, status: "no_phone_hash" });
            continue;
          }
          const out = await attemptDeploy(u.walletPhoneHash, `user:${uid}`);
          if (!dryRun) {
            await db.collection("users").doc(uid).set({
              walletDeploymentPending: false,
              walletDeploymentError: admin.firestore.FieldValue.delete(),
              walletDeploymentErrorAt: admin.firestore.FieldValue.delete(),
              walletDeploymentRetriedAt: admin.firestore.FieldValue.serverTimestamp(),
            }, { merge: true });
          }
          results.users.succeeded++;
          results.users.items.push({ uid, status: out.alreadyDeployed ? "already_deployed" : (out.dryRun ? "dry_run" : "deployed"), address: out.address, txHash: out.txHash });
        } catch (e) {
          results.users.failed++;
          const msg = (e.message || "unknown").slice(0, 500);
          results.users.items.push({ uid, status: "failed", error: msg });
          if (!dryRun) {
            await db.collection("users").doc(uid).set({
              walletDeploymentError: `retry_failed: ${msg}`,
              walletDeploymentErrorAt: admin.firestore.FieldValue.serverTimestamp(),
            }, { merge: true });
          }
        }
      }
    }

    // ── Communities ─────────────────────────────────────────────────
    if (scope === "communities" || scope === "both") {
      const snap = await db.collection("communities")
        .where("walletDeploymentPending", "==", true)
        .limit(limit)
        .get();
      results.communities.found = snap.size;
      for (const doc of snap.docs) {
        const cid = doc.id;
        try {
          const salt = ethers.keccak256(ethers.toUtf8Bytes(`community:${cid}`));
          const out = await attemptDeploy(salt, `community:${cid}`);
          if (!dryRun) {
            await db.collection("communities").doc(cid).set({
              walletDeploymentPending: false,
              walletDeploymentError: admin.firestore.FieldValue.delete(),
              walletDeploymentErrorAt: admin.firestore.FieldValue.delete(),
              walletDeploymentRetriedAt: admin.firestore.FieldValue.serverTimestamp(),
            }, { merge: true });
          }
          results.communities.succeeded++;
          results.communities.items.push({ cid, status: out.alreadyDeployed ? "already_deployed" : (out.dryRun ? "dry_run" : "deployed"), address: out.address, txHash: out.txHash });
        } catch (e) {
          results.communities.failed++;
          const msg = (e.message || "unknown").slice(0, 500);
          results.communities.items.push({ cid, status: "failed", error: msg });
          if (!dryRun) {
            await db.collection("communities").doc(cid).set({
              walletDeploymentError: `retry_failed: ${msg}`,
              walletDeploymentErrorAt: admin.firestore.FieldValue.serverTimestamp(),
            }, { merge: true });
          }
        }
      }
    }

    return results;
  });

// Export infrastructure for use by transfer.js
module.exports.getSmartWalletInfra = getSmartWalletInfra;
module.exports.SMART_WALLET_ABI = SMART_WALLET_ABI;
