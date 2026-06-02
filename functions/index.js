/**
 * Diaspora Nearby – Cloud Functions Entry Point
 * 
 * This file re-exports all Cloud Functions from domain-specific modules
 * under functions/lib/. Each module handles a focused area:
 * 
 *   wallet.js      – Smart wallet creation (users + communities)
 *   proximity.js   – Nearby compatriot detection & alerts
 *   proxy.js       – CORS proxies (Radio Browser, Google Places)
 *   chat.js        – Chat message push notifications
 *   notifications.js – Points transaction alerts & FCM topic management
 *   admin_reset.js – Database reset (dev/testing)
 *   transfer.js    – Peer-to-peer DSP transfers
 *   travel.js      – Amadeus Travel API proxy
 *   payments.js    – Stripe emergency fund checkout & webhooks
 *   dsp.js         – DSP points (awards, deductions, TGE, treasury sync)
 * 
 * Shared utilities (admin SDK, Firestore, sendPushToUser) live in shared.js.
 */

const admin = require("firebase-admin");
admin.initializeApp();

// ── Import all domain modules ──
const wallet = require("./lib/wallet");
const proximity = require("./lib/proximity");
const proxy = require("./lib/proxy");
const chat = require("./lib/chat");
const notifications = require("./lib/notifications");
const adminReset = require("./lib/admin_reset");
const transfer = require("./lib/transfer");
const travel = require("./lib/travel");
const payments = require("./lib/payments");
const dsp = require("./lib/dsp");
const blockchain = require("./lib/blockchain");
const chambers = require("./lib/chambers");
const governance = require("./lib/governance");
const ddi = require("./lib/ddi");

// ── Re-export all functions ──
// Wallet (4) — `ensureCommunityTreasuryWallets` removed 2026-06-01 (one-shot
// backfill superseded by scripts/backfill-wallets.js + scripts/register-treasury-wallets.js).
// Source remains in lib/wallet.js for re-deploy if ever needed.
exports.onCommunityWrite = wallet.onCommunityWrite;
exports.onUserWrite = wallet.onUserWrite;
exports.getOrCreateSmartWallet = wallet.getOrCreateSmartWallet;
exports.ensureSystemWallets = wallet.ensureSystemWallets;

// Proximity (2)
exports.checkProximity = proximity.checkProximity;
exports.checkProximityOnCreate = proximity.checkProximityOnCreate;

// Proxy (2)
exports.radioProxy = proxy.radioProxy;
exports.placesProxy = proxy.placesProxy;

// Chat (1)
exports.onDirectMessageCreated = chat.onDirectMessageCreated;

// Notifications (2)
exports.onPointsTransactionCreated = notifications.onPointsTransactionCreated;
exports.manageUserFCMTopics = notifications.manageUserFCMTopics;

// Admin (1) — `setAdminClaim` removed 2026-06-01 (admin grants are issued
// locally via scripts/set-admin.js using the Admin SDK; no Flutter callers).
// Source remains in lib/admin_reset.js for re-deploy if ever needed.
exports.hardResetDatabase = adminReset.hardResetDatabase;

// Transfer (3)
exports.transferDiaspora = transfer.transferDiaspora;
exports.getTokenBalance = transfer.getTokenBalance;
exports.getBatchTokenBalances = transfer.getBatchTokenBalances;

// Travel (1)
exports.amadeusProxy = travel.amadeusProxy;

// Payments (2)
exports.createEmergencyFundCheckout = payments.createEmergencyFundCheckout;
exports.stripeEmergencyFundWebhook = payments.stripeEmergencyFundWebhook;

// DSP (10)
exports.onGlobalDspMilestone = dsp.onGlobalDspMilestone;
exports.executeTGE = dsp.executeTGE;
exports.awardPoints = dsp.awardPoints;
exports.deductPoints = dsp.deductPoints;
exports.initializeUserPoints = dsp.initializeUserPoints;
exports.awardMessagePoints = dsp.awardMessagePoints;
exports.awardExplorationPoints = dsp.awardExplorationPoints;
exports.awardSharePoints = dsp.awardSharePoints;
exports.recordFiatGdp = dsp.recordFiatGdp;
exports.syncTreasuryBalances = dsp.syncTreasuryBalances;

// Blockchain (1)
exports.getTokenTransfers = blockchain.getTokenTransfers;

// Play Store — `addPlayStoreTester` removed 2026-06-01.
// Landing page no longer captures emails; testers self-serve via the public
// Closed Testing Google Group + Play Store opt-in link.
// Source file lib/play_store.js can be safely deleted if/when desired.

// Bilateral Chambers (3)
exports.ensureSignupChamber = chambers.ensureSignupChamber;
exports.joinChamber = chambers.joinChamber;
exports.manageChamber = chambers.manageChamber;

// Governance (2)
exports.nominateForGovernanceRole = governance.nominateForGovernanceRole;
exports.evaluateGovernanceVote = governance.evaluateGovernanceVote;

// DDI Loans (4)
exports.submitDdiLoanApplication = ddi.submitDdiLoanApplication;
exports.joinDdiDiscussion = ddi.joinDdiDiscussion;
exports.castDdiLoanVote = ddi.castDdiLoanVote;
exports.resolveDdiLoanVoting = ddi.resolveDdiLoanVoting;
