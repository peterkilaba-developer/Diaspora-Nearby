/**
 * Smart Wallet / Account Abstraction module.
 * 
 * ALL wallets are now Smart Contract Wallets via DiasporaWalletFactory (CREATE2).
 * EOA wallet generation has been fully removed to eliminate MSB/VASP exposure.
 * 
 * Architecture:
 * - Phone number → keccak256 hash → CREATE2 salt → deterministic wallet address
 * - No private keys stored per-user (backend signer controls all wallets)
 * - Gasless transactions for users (backend pays gas)
 * - Wallet addresses can be computed BEFORE deployment
 */
const { functions, admin, db } = require("./shared");
const { ethers } = require("ethers");

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

// ── Configuration (set via Firebase Functions config or .env) ──
const WALLET_FACTORY_ADDRESS = process.env.WALLET_FACTORY_ADDRESS || null;
const BACKEND_SIGNER_KEY = process.env.BACKEND_SIGNER_PRIVATE_KEY || null;
const RPC_URL = process.env.RPC_URL || "https://mainnet.base.org";
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

/**
 * Get the configured provider and signer for smart wallet operations.
 * Throws if the factory is not configured — no EOA fallback.
 */
function getSmartWalletInfra() {
  if (!WALLET_FACTORY_ADDRESS || !BACKEND_SIGNER_KEY) {
    console.error("[SmartWallet] CRITICAL: Factory or signer not configured.");
    return null;
  }

  const provider = new ethers.JsonRpcProvider(RPC_URL);
  const signer = new ethers.Wallet(BACKEND_SIGNER_KEY, provider);
  const factory = new ethers.Contract(WALLET_FACTORY_ADDRESS, WALLET_FACTORY_ABI, signer);

  return { provider, signer, factory };
}

/**
 * Compute the phone hash used as CREATE2 salt.
 * Normalizes the phone number first (trim whitespace, ensure + prefix).
 */
function computePhoneHash(phoneNumber) {
  // Normalize: trim, remove spaces, ensure starts with +
  let normalized = phoneNumber.trim().replace(/\s+/g, "");
  if (!normalized.startsWith("+")) {
    normalized = "+" + normalized;
  }
  return ethers.keccak256(ethers.toUtf8Bytes(normalized));
}

/**
 * Create a smart wallet for a given phone number.
 * Returns { address, phoneHash, isSmartWallet: true }.
 * No EOA fallback — throws if factory is unavailable.
 */
async function createSmartWalletForPhone(phoneNumber) {
  const infra = getSmartWalletInfra();

  if (!infra) {
    throw new Error("[SmartWallet] WalletFactory not configured. Cannot create wallet.");
  }

  const phoneHash = computePhoneHash(phoneNumber);

  // Check if wallet already exists
  const existingWallet = await infra.factory.getWallet(phoneHash);
  if (existingWallet !== ethers.ZeroAddress) {
    console.log(`[SmartWallet] Wallet already exists for phone hash: ${existingWallet}`);
    return {
      address: existingWallet,
      isSmartWallet: true,
      phoneHash: phoneHash,
    };
  }

  // Compute the deterministic address (pre-deployment)
  const predictedAddress = await infra.factory.computeAddress(phoneHash);
  console.log(`[SmartWallet] Predicted address for phone: ${predictedAddress}`);

  try {
    // Deploy the smart wallet on-chain
    const tx = await infra.factory.createWallet(phoneHash);
    const receipt = await tx.wait();
    console.log(`[SmartWallet] Created smart wallet: ${predictedAddress} (tx: ${receipt.hash})`);

    return {
      address: predictedAddress,
      isSmartWallet: true,
      phoneHash: phoneHash,
      txHash: receipt.hash,
    };
  } catch (error) {
    console.error(`[SmartWallet] On-chain deployment failed: ${error.message}`);
    // Fallback: store the predicted address even without deployment
    // The wallet can be deployed later (CREATE2 addresses are deterministic)
    return {
      address: predictedAddress,
      isSmartWallet: true,
      phoneHash: phoneHash,
      deploymentPending: true,
    };
  }
}

/**
 * Create a deterministic wallet for a community using its ID as salt.
 * No EOA fallback — throws if factory is unavailable.
 */
async function createSmartWalletForCommunity(communityId) {
  const infra = getSmartWalletInfra();

  if (!infra) {
    throw new Error("[SmartWallet] WalletFactory not configured. Cannot create community wallet.");
  }

  // Use community ID as deterministic salt
  const salt = ethers.keccak256(ethers.toUtf8Bytes(`community:${communityId}`));

  const existingWallet = await infra.factory.getWallet(salt);
  if (existingWallet !== ethers.ZeroAddress) {
    return { address: existingWallet, isSmartWallet: true };
  }

  const predictedAddress = await infra.factory.computeAddress(salt);

  try {
    const tx = await infra.factory.createWallet(salt);
    await tx.wait();
    console.log(`[SmartWallet] Created community wallet: ${predictedAddress}`);
    return { address: predictedAddress, isSmartWallet: true };
  } catch (error) {
    console.error(`[SmartWallet] Community wallet deployment failed: ${error.message}`);
    return { address: predictedAddress, isSmartWallet: true, deploymentPending: true };
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

      await change.after.ref.update({
        walletAddress: walletResult.address,
        walletGeneratedAt: admin.firestore.FieldValue.serverTimestamp(),
        walletType: "smart",
      });

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

      console.log(`[Wallet] Assigned ${walletResult.address} to Community ${communityId} (smart)`);
    } catch (e) {
      console.error(`[Wallet] Failed to create community wallet: ${e.message}`);
    }
  });

// ── 2. Auto-create Smart Wallet for Users (Phone-based) ──
exports.onUserWrite = functions
  .runWith({ secrets: ["BACKEND_SIGNER_PRIVATE_KEY"] })
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

        await change.after.ref.update({
          walletAddress: walletResult.address,
          walletGeneratedAt: admin.firestore.FieldValue.serverTimestamp(),
          walletType: "smart",
          walletPhoneHash: walletResult.phoneHash || null,
        });

        console.log(`[SmartWallet] Assigned ${walletResult.address} to User ${userId} (smart)`);
      } catch (e) {
        console.error(`[SmartWallet] Failed to create user wallet: ${e.message}`);
      }
    } else {
      // No phone number available yet — wallet will be created when phone is verified
      console.log(`[Wallet] No phone number for User ${userId}. Wallet creation deferred until phone verification.`);
    }
  });

// ── 3. Callable: Get or Create Smart Wallet ──
// Called explicitly from the Flutter app after phone authentication.
exports.getOrCreateSmartWallet = functions
  .runWith({ secrets: ["BACKEND_SIGNER_PRIVATE_KEY"] })
  .https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "User must be authenticated.");
  }

  const userId = context.auth.uid;

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

  // 4. Save wallet data
  await db.collection("users").doc(userId).update({
    walletAddress: walletResult.address,
    walletGeneratedAt: admin.firestore.FieldValue.serverTimestamp(),
    walletType: "smart",
    walletPhoneHash: walletResult.phoneHash || null,
  });

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
// Creates smart wallets for ALL system treasuries (founders, investors, burn)
// and writes walletAddress to governance docs so TGE can snapshot them.

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
 * ensureSystemWallets — Creates smart wallets for ALL system treasuries:
 *   1. Founders Treasury  (salt: "system:founders_treasury")
 *   2. Investors Treasury  (salt: "system:investors_treasury")
 *   3. Burn Treasury       (salt: "system:burn_treasury")
 * 
 * Also writes walletAddress into governance docs ("founders", "investors")
 * so TGE performTGE() can snapshot their balances.
 */
exports.ensureSystemWallets = functions
  .runWith({ timeoutSeconds: 120, memory: "256MB", secrets: ["BACKEND_SIGNER_PRIVATE_KEY"] })
  .https.onCall(async (data, context) => {
    if (!context.auth) throw new functions.https.HttpsError("unauthenticated", "User must be authenticated.");

    const callerId = context.auth.uid;
    const callerDoc = await db.collection("users").doc(callerId).get();
    if (!callerDoc.exists || !callerDoc.data().isAdmin) {
      throw new functions.https.HttpsError("permission-denied", "Admin access required.");
    }

    const infra = getSmartWalletInfra();
    if (!infra) {
      throw new functions.https.HttpsError(
        "failed-precondition",
        "WalletFactory not configured. Cannot create system wallets."
      );
    }

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

    // ── 2. Investors Treasury ──
    try {
      const investors = await createSystemTreasuryWallet(infra, "treasury:investors");
      results.investors = investors;

      await db.collection("system_stats").doc("treasury").set({
        investorsWallet: investors.address,
        investorsWalletType: "smart",
        ...(!investors.alreadyExisted && { investorsWalletGeneratedAt: admin.firestore.FieldValue.serverTimestamp() }),
      }, { merge: true });

      // Write walletAddress to governance doc (needed for TGE snapshot)
      await db.collection("governance").doc("investors").set({
        id: "investors",
        name: "Investors & Partners",
        type: "system",
        title: "Investors Treasury",
        walletAddress: investors.address,
        walletType: "smart",
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });

      console.log(`[Wallet] ✅ Investors: ${investors.address} (${investors.alreadyExisted ? "existing" : "new"})`);
    } catch (e) {
      console.error(`[Wallet] ❌ Investors wallet failed: ${e.message}`);
      results.investors = { error: e.message };
    }

    // ── 3. Burn Treasury ──
    try {
      const burn = await createSystemTreasuryWallet(infra, "treasury:burn");
      results.burn = burn;

      await db.collection("system_stats").doc("treasury").set({
        burnWallet: burn.address,
        burnWalletType: "smart",
        ...(!burn.alreadyExisted && { burnWalletGeneratedAt: admin.firestore.FieldValue.serverTimestamp() }),
      }, { merge: true });

      // Burn doesn't need governance doc (no TGE distribution to burn address)
      // but store it for transparency/audit
      await db.collection("governance").doc("burn").set({
        id: "burn",
        name: "Deflationary Burn",
        type: "system",
        title: "Burn Treasury",
        walletAddress: burn.address,
        walletType: "smart",
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });

      console.log(`[Wallet] ✅ Burn: ${burn.address} (${burn.alreadyExisted ? "existing" : "new"})`);
    } catch (e) {
      console.error(`[Wallet] ❌ Burn wallet failed: ${e.message}`);
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
    if (!context.auth) throw new functions.https.HttpsError("unauthenticated", "User must be authenticated.");

    const callerId = context.auth.uid;
    const callerDoc = await db.collection("users").doc(callerId).get();
    if (!callerDoc.exists || !callerDoc.data().isAdmin) {
      throw new functions.https.HttpsError("permission-denied", "Admin access required.");
    }

    const infra = getSmartWalletInfra();
    if (!infra) {
      throw new functions.https.HttpsError(
        "failed-precondition",
        "WalletFactory not configured."
      );
    }

    console.log(`[Wallet] ensureCommunityTreasuryWallets triggered by ${callerId}`);

    const commSnap = await db.collection("communities").get();
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
      ...results,
    };
  });



// Export infrastructure for use by transfer.js
module.exports.getSmartWalletInfra = getSmartWalletInfra;
module.exports.SMART_WALLET_ABI = SMART_WALLET_ABI;
