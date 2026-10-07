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
const chamberLeadership = require("./lib/chamber_leadership");
const account = require("./lib/account");
const trust = require("./lib/trust");
const listings = require("./lib/listings");
const hosting = require("./lib/hosting");
const reports = require("./lib/reports");
const leads = require("./lib/leads");
const relationships = require("./lib/relationships");
const communities = require("./lib/communities");
const bookings = require("./lib/bookings");

// ── Re-export all functions ──
// Wallet (5)
exports.onCommunityWrite = wallet.onCommunityWrite;
exports.onUserWrite = wallet.onUserWrite;
exports.getOrCreateSmartWallet = wallet.getOrCreateSmartWallet;
exports.ensureSystemWallets = wallet.ensureSystemWallets;
exports.ensureCommunityTreasuryWallets = wallet.ensureCommunityTreasuryWallets;

// Proximity (2)
exports.checkProximity = proximity.checkProximity;
exports.checkProximityOnCreate = proximity.checkProximityOnCreate;
exports.findNearbyUsers = proximity.findNearbyUsers;
exports.searchUsers = proximity.searchUsers;

// Proxy (2)
exports.radioProxy = proxy.radioProxy;
exports.reportRadioStationHealth = proxy.reportRadioStationHealth;
exports.fetchRadioStations = proxy.fetchRadioStations;
exports.placesProxy = proxy.placesProxy;

// Chat (1)
exports.onDirectMessageCreated = chat.onDirectMessageCreated;
exports.onChatWritten = chat.onChatWritten;
exports.createChat = chat.createChat;
exports.setOrganizationFollow = chat.setOrganizationFollow;
exports.manageOrganizationAdmin = chat.manageOrganizationAdmin;
exports.setBusinessChamberLink = chat.setBusinessChamberLink;
exports.joinChat = chat.joinChat;
exports.joinCommunity = chat.joinCommunity;
exports.manageChatMembers = chat.manageChatMembers;
exports.updateChatMetadata = chat.updateChatMetadata;
exports.reactToMessage = chat.reactToMessage;
exports.setEventAttendance = chat.setEventAttendance;
exports.setEventInterest = chat.setEventInterest;
exports.createEventCheckInChallenge = chat.createEventCheckInChallenge;
exports.completeEventCheckIn = chat.completeEventCheckIn;
exports.onEventDeleted = chat.onEventDeleted;

// Notifications (2)
exports.onPointsTransactionCreated = notifications.onPointsTransactionCreated;
exports.manageUserFCMTopics = notifications.manageUserFCMTopics;

// Admin (2)
exports.hardResetDatabase = adminReset.hardResetDatabase;
exports.setAdminClaim = adminReset.setAdminClaim;
exports.deleteMyAccount = account.deleteMyAccount;
exports.createQrHandshake = trust.createQrHandshake;
exports.completeQrHandshake = trust.completeQrHandshake;
exports.verifyChatSolution = trust.verifyChatSolution;
exports.recordListingView = listings.recordListingView;
exports.setListingSaved = listings.setListingSaved;
exports.createHostingRequest = hosting.createHostingRequest;
exports.createHostingSession = hosting.createHostingSession;
exports.createHostingCheckInChallenge = hosting.createHostingCheckInChallenge;
exports.completeHostingCheckIn = hosting.completeHostingCheckIn;
exports.updateHostingSessionState = hosting.updateHostingSessionState;
exports.submitReport = reports.submitReport;
exports.submitLiquidityInterest = leads.submitLiquidityInterest;
exports.submitFeedback = leads.submitFeedback;
exports.submitAppRequest = leads.submitAppRequest;
exports.sendRelationshipRequest = relationships.sendRelationshipRequest;
exports.respondRelationshipRequest = relationships.respondRelationshipRequest;
exports.cancelRelationshipRequest = relationships.cancelRelationshipRequest;
exports.ensureDirectChat = relationships.ensureDirectChat;
exports.setUserBlocked = relationships.setUserBlocked;
exports.removeRelationship = relationships.removeRelationship;
exports.markRelationshipDeceased = relationships.markRelationshipDeceased;
exports.ensureCommunity = communities.ensureCommunity;
exports.provisionSignupCommunities = communities.provisionSignupCommunities;
exports.createPeerBooking = bookings.createPeerBooking;
exports.updatePeerBookingStatus = bookings.updatePeerBookingStatus;

// Chamber Leadership (1) — Triggered on leadershipRequests doc update.
// Performs the actual appointment when an admin flips `approved: true`.
exports.onChamberLeadershipRequestApproved =
    chamberLeadership.onChamberLeadershipRequestApproved;

// Transfer (3)
exports.transferDiaspora = transfer.transferDiaspora;
exports.getTokenBalance = transfer.getTokenBalance;
exports.getBatchTokenBalances = transfer.getBatchTokenBalances;

// Travel (1)

// Chamber Leadership (1) — Triggered on leadershipRequests doc update.
// Performs the actual appointment when an admin flips `approved: true`.
exports.onChamberLeadershipRequestApproved =
    chamberLeadership.onChamberLeadershipRequestApproved;

// Transfer (3)
exports.transferDiaspora = transfer.transferDiaspora;
exports.getTokenBalance = transfer.getTokenBalance;
exports.getBatchTokenBalances = transfer.getBatchTokenBalances;

// Travel (1)
exports.amadeusProxy = travel.amadeusProxy;

// Payments (2)
exports.createEmergencyFundCheckout = payments.createEmergencyFundCheckout;
exports.stripeEmergencyFundWebhook = payments.stripeEmergencyFundWebhook;

// Ubuntu Emergency Fund — $DIASPORA flow
const emergencyFund = require("./lib/emergency_fund");
exports.getEmergencyFundContributionQuote = emergencyFund.getEmergencyFundContributionQuote;
exports.payEmergencyFundInDiaspora = emergencyFund.payEmergencyFundInDiaspora;
exports.getEmergencyFundStats = emergencyFund.getEmergencyFundStats;
exports.stakeEmergencyFundPromissory = emergencyFund.stakeEmergencyFundPromissory;
exports.slashPromissoryForFraud = emergencyFund.slashPromissoryForFraud;

// DSP (10)
exports.onVouchWrite = dsp.onVouchWrite;
exports.onGlobalDspMilestone = dsp.onGlobalDspMilestone;
exports.executeTGE = dsp.executeTGE;
exports.awardPoints = dsp.awardPoints;
exports.backfillLifetimeEarnings = dsp.backfillLifetimeEarnings;
exports.getOrCreateReferralCode = dsp.getOrCreateReferralCode;
exports.redeemReferralCode = dsp.redeemReferralCode;
exports.deductPoints = dsp.deductPoints;
exports.initializeUserPoints = dsp.initializeUserPoints;
exports.evaluateWelcomeBonus = dsp.evaluateWelcomeBonus;
exports.recordDailyCheckIn = dsp.recordDailyCheckIn;
exports.awardMessagePoints = dsp.awardMessagePoints;
exports.awardExplorationPoints = dsp.awardExplorationPoints;
exports.awardSharePoints = dsp.awardSharePoints;
exports.recordFiatGdp = dsp.recordFiatGdp;
exports.syncTreasuryBalances = dsp.syncTreasuryBalances;
exports.retryPendingWelcomeBonuses = dsp.retryPendingWelcomeBonuses;
exports.retryPendingWalletDeployments = wallet.retryPendingWalletDeployments;
exports.retryPendingTGEDeductions = dsp.retryPendingTGEDeductions;

// Blockchain (1)
exports.getTokenTransfers = blockchain.getTokenTransfers;

// Play Store (1)
const playStore = require("./lib/play_store");
exports.addPlayStoreTester = playStore.addPlayStoreTester;

// Chambers (3) — restored from feature/develop-catchup-2026-06 (aaf6d9f);
// these were deployed to prod but missing from main, so every deploy
// offered to delete them.
const chambers = require("./lib/chambers");
exports.ensureSignupChamber = chambers.ensureSignupChamber;
exports.joinChamber = chambers.joinChamber;
exports.setChamberFollow = chambers.setChamberFollow;
exports.leaveChamber = chambers.leaveChamber;
exports.manageChamber = chambers.manageChamber;


// Governance (2)
const governance = require("./lib/governance");
exports.nominateForGovernanceRole = governance.nominateForGovernanceRole;
exports.castGovernanceVote = governance.castGovernanceVote;
exports.evaluateGovernanceVote = governance.evaluateGovernanceVote;

// DDI Loans (5)
const ddi = require("./lib/ddi");
exports.submitDdiLoanApplication = ddi.submitDdiLoanApplication;
exports.joinDdiDiscussion = ddi.joinDdiDiscussion;
exports.castDdiLoanVote = ddi.castDdiLoanVote;
exports.resolveDdiLoanVoting = ddi.resolveDdiLoanVoting;
exports.getDdiFundingCascade = ddi.getDdiFundingCascade;

// Custom Auth (2)
const auth = require("./lib/auth");
exports.requestWhatsAppOtp = auth.requestWhatsAppOtp;
exports.verifyWhatsAppOtp = auth.verifyWhatsAppOtp;
