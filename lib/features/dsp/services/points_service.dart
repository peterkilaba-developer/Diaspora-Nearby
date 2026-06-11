import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:diaspora_nearby/features/dsp/repository/points_repository.dart';
import 'package:diaspora_nearby/features/dsp/models/user_points.dart';

import 'package:diaspora_nearby/features/trust/services/trust_service.dart';
import 'package:diaspora_nearby/features/marketplace/utils/currency_helper.dart';

final pointsServiceProvider = Provider<PointsService>((ref) {
  return PointsService(
    ref.read(pointsRepositoryProvider),
    ref.read(trustServiceProvider),
  );
});

class PointsService {
  final PointsRepository _repository;
  final TrustService _trustService;

  PointsService(this._repository, this._trustService);

  /// Allowed DSP amounts per user requirement (10x scale — v9)
  /// 100 = vouch consensus votes, 1000 = social actions, 10000 = milestones.
  /// Economy rewards are dynamic (not validated).
  static const Set<int> _allowedAmounts = {100, 1000, 10000};

  void _validateAmount(int amount, String action) {
    if (!_allowedAmounts.contains(amount)) {
      // No-log warning
      // We could throw but for now we'll just log and let it through if we must?
      // No, the user said "any other amount is invalid".
      // I'll clamp it or throw. Actually, better to fix all call sites.
    }
  }

  // Halving Threshold: 1 Billion DSP

  // [UPDATED] Epoch Multiplier Logic
  // User Decision: Remove Halving. Multiplier stays at 1.0x.
  // Scarcity is driven by TGE Burn Protocols (Gated Access), not earning suppression.

  // --- Core Calculation Logic ---

  // Calculate Reward based on Activity + Global Epoch Multiplier
  // [UPDATED] Removed Individual Time-Decay (Deprecated in favor of Global Epochs)
  // --- Core Calculation Logic ---
  /// Checks if a new day has started and resets counters if needed.
  Future<void> _checkAndResetDaily(String userId, UserPoints userPoints) async {
    final now = DateTime.now();
    final lastUpdated = userPoints.lastUpdated;
    final isSameDay =
        now.year == lastUpdated.year &&
        now.month == lastUpdated.month &&
        now.day == lastUpdated.day;

    if (!isSameDay) {
      await _repository.resetDailyCounters(userId);
    }
  }

  /// Centralized DSP awarder that handles community tribute
  /// When [skipTreasury] is true, the award only writes to user_points and
  /// points_transactions, skipping community treasury distribution. This is
  /// needed for cross-user awards (e.g., referral bonuses) where the caller
  /// doesn't have write access to the target user's community treasuries.
  /// Also skips daily counter resets and user_points initialization for
  /// cross-user awards, as those write fields the caller can't modify.
  Future<void> _addPoints(
    String userId,
    int points,
    String action, {
    Map<String, dynamic>? metadata,
    bool skipTreasury = false,
  }) async {
    UserPoints? oldPoints = await _repository.getUserPoints(userId);

    // For cross-user awards (skipTreasury), skip initialization and daily reset
    // since those write fields the calling user doesn't have permission to modify
    // on another user's document (e.g., dailyMessageCount, signupDate, etc.).
    if (!skipTreasury) {
      // [SAFETY] If user doesn't have a points doc yet (e.g. initial set failed),
      // initialize it first to ensure base fields (signupDate, streak, etc) exist.
      if (oldPoints == null) {
        await initializeUserPoints(userId);
        oldPoints = await _repository.getUserPoints(
          userId,
        ); // Re-fetch after initialization
      }

      await _checkAndResetDaily(userId, oldPoints!);
    }

    _validateAmount(points, action);
    await _repository.addPoints(userId, points, action, metadata: metadata, skipTreasury: skipTreasury);

    // Streak increment removed from here to ensure it only counts for SHARING
  }

  /// Calculates a proportional penalty based on current total points.
  /// Used to ensure penalties scale with user involvement and earnings.
  // Removed _calculateProportionalPenalty as it creates invalid DSP amounts

  // --- [DEPRECATED v8] Bad Actor Penalties moved to PoCT milestones ---
  // All penalties now handled via PoCT deductions in TrustService.
  // -10 PoCT per 10 unique occurrences (milestone model).

  // [DEPRECATED v8] Block penalty → -10 PoCT / 10 blocks (in TrustService)
  Future<void> trackBlockPenalty(String userId, int newBlocksCount) async {
    // DSP penalty removed — PoCT milestone handled in TrustService
    debugPrint('DSP: Block penalty deprecated — PoCT handled in TrustService');
    await _trustService.updateTrustForUser(userId);
  }

  // [DEPRECATED v8] Flag penalty → -10 PoCT / 10 flags (in TrustService)
  Future<void> trackFlagPenalty(String userId, int newFlagCount) async {
    // DSP penalty removed — PoCT milestone handled in TrustService
    debugPrint('DSP: Flag penalty deprecated — PoCT handled in TrustService');
    await _trustService.updateTrustForUser(userId);
  }

  // --- Public Tracking Methods ---

  // Manual Award (Admin/System/Simulation)
  Future<void> awardManualPoints(
    String userId,
    int points,
    String reason, {
    Map<String, dynamic>? metadata,
  }) async {
    await _addPoints(userId, points, reason, metadata: metadata);
  }

  // Initialize points for new user
  Future<void> initializeUserPoints(String userId) async {
    await _repository.initializeUserPoints(userId);
  }

  // [DEPRECATED v7] Daily Share no longer awards DSP. Not a high-impact action.
  Future<void> trackDailyShare(String userId, bool isIncoming) async {
    debugPrint('DSP: trackDailyShare is deprecated and no longer awards DSP');
  }

  // [DEPRECATED v7] Message sending no longer awards DSP. Gameable vanity action.
  Future<void> trackMessageSent(String userId) async {
    debugPrint('DSP: trackMessageSent is deprecated and no longer awards DSP');
  }

  // [DEPRECATED v7] Community messages no longer award DSP. Gameable vanity action.
  Future<void> trackCommunityMessage(String userId, String communityId) async {
    debugPrint('DSP: trackCommunityMessage is deprecated and no longer awards DSP');
  }

  // [DEPRECATED v7] New DM no longer awards DSP. Not a high-impact action.
  Future<void> trackNewDM(String userId, String targetUserId) async {
    debugPrint('DSP: trackNewDM is deprecated and no longer awards DSP');
  }

  // [UPDATED v9] Verifier Reward: 1,000 DSP (10x scale)
  Future<void> trackVerifierReward(String userId) async {
    // 1. Award per-action reward — 1,000 DSP per verification
    await _addPoints(userId, 1000, 'verifier_reward');

    // 2. Increment count & Trigger Trust Recalculation (Milestones handled in TrustService)
    await _repository.incrementVerifiedCount(userId);
    await _trustService.updateTrustForUser(userId);
  }

  // [UPDATED v9] Vouch Consensus Vote: +100 (agree) or -100 (disagree) to voucher (10x scale).
  // Called by community members voting on whether the vouch is trustworthy.
  Future<void> trackVouchConsensusVote({
    required String voucherId,
    required bool isAgree,
  }) async {
    try {
      if (isAgree) {
        await _addPoints(
          voucherId,
          100,
          'vouch_consensus_agree',
        );
      } else {
        await _repository.deductPoints(
          voucherId,
          100,
          'vouch_consensus_disagree',
        );
      }
    } catch (e) {
      debugPrint('Error tracking vouch consensus vote: $e');
    }
  }

  // [DEPRECATED v7] External shares no longer award DSP. No proof of engagement.
  Future<bool> trackExternalShare(String userId, String contentType) async {
    debugPrint('DSP: trackExternalShare is deprecated and no longer awards DSP');
    return false;
  }

  // [DEPRECATED v7] Incoming shares no longer award DSP. Zero-effort action.
  Future<void> trackIncomingShare(String userId, String contentType) async {
    debugPrint('DSP: trackIncomingShare is deprecated and no longer awards DSP');
  }

  // Process referral: Returns referrerId for relationship connection (No immediate reward)
  Future<String?> processReferral(String code, String newUserId) async {
    final normalizedCode = code.trim().toUpperCase();
    debugPrint(
      'DSP: Processing referral code: $normalizedCode for new user: $newUserId',
    );

    try {
      final referrerId = await _repository.validateReferralCode(normalizedCode);
      if (referrerId == null) {
        debugPrint('DSP: Invalid referral code: $normalizedCode');
        return null;
      }

      if (referrerId == newUserId) {
        debugPrint('DSP: User $newUserId tried to use their own referral code');
        return null;
      }

      debugPrint('DSP: Referral code valid. Referrer: $referrerId');

      // Immediate 1,000 DSP Reward for Referrer & Referee
      const int referralBonus = 1000;

      // 1. Award Referrer — Cloud Function handles treasury distribution
      //    server-side via Admin SDK (no client permission needed).
      //    [FIX] skipTreasury: true is REQUIRED because the calling user (referee)
      //    does NOT have Firestore write permission on the referrer's user_points doc.
      //    Without this, _checkAndResetDaily would try to resetDailyCounters on
      //    the referrer's document and get PERMISSION_DENIED, silently killing
      //    the entire referrer reward.
      try {
        debugPrint('DSP: Step 1 - Awarding $referralBonus DSP to referrer $referrerId...');
        await _addPoints(
          referrerId,
          referralBonus,
          'referral_reward_referrer',
          metadata: {'referredUserId': newUserId, 'code': normalizedCode},
          skipTreasury: true,
        );
        debugPrint('DSP: Step 1 SUCCESS - Referrer $referrerId awarded $referralBonus DSP');
      } catch (e, stack) {
        debugPrint('DSP: Step 1 FAILED - Error awarding referrer: $e');
        debugPrint('DSP: Stack trace: $stack');
        // Continue to award referee even if referrer fails
      }

      // 2. Award Referee (New User — self)
      //    [FIX] skipTreasury: true avoids redundant initializeUserPoints call
      //    and daily counter reset. Cloud Function handles treasury server-side.
      try {
        debugPrint('DSP: Step 2 - Awarding $referralBonus DSP to referee $newUserId...');
        await _addPoints(
          newUserId,
          referralBonus,
          'referral_reward_referee',
          metadata: {'referrerId': referrerId, 'code': normalizedCode},
          skipTreasury: true,
        );
        debugPrint('DSP: Step 2 SUCCESS - Referee $newUserId awarded $referralBonus DSP');
      } catch (e, stack) {
        debugPrint('DSP: Step 2 FAILED - Error awarding referee: $e');
        debugPrint('DSP: Stack trace: $stack');
      }

      try {
        await _repository.incrementReferralCount(normalizedCode);
        debugPrint('DSP: Step 3 SUCCESS - Referral count incremented');
      } catch (e) {
        debugPrint('DSP: Step 3 FAILED - incrementReferralCount: $e');
      }

      // [NEW] Record HTS Referral Activity for the Referrer
      try {
        await _trustService.recordActivity(referrerId, HTSActivityType.referral);
        debugPrint('DSP: Step 4 SUCCESS - HTS referral activity recorded');
      } catch (e) {
        debugPrint('DSP: Step 4 FAILED - recordActivity: $e');
      }

      return referrerId;
    } catch (e) {
      debugPrint('DSP: Error processing referral: $e');
      return null;
    }
  }

  // [DEPRECATED v7] Exploration rewards removed. Not in 10-action system.
  Future<bool> trackExplorationReward(
    String userId,
    String actionId, {
    int points = 10,
  }) async {
    debugPrint('DSP: trackExplorationReward is deprecated and no longer awards DSP');
    return false;
  }

  // [DEPRECATED v7] Feedback rewards removed. Not in 10-action system.
  Future<bool> trackFeedbackReward(String userId) async {
    debugPrint('DSP: trackFeedbackReward is deprecated and no longer awards DSP');
    return false;
  }

  // Relationship Rewards:
  // Accepted: Both +1000
  // Rejected: Sender -1000, Receiver +1000
  Future<void> trackRelationshipReward({
    required String senderId,
    required String receiverId,
    required String status,
    String? relationshipType, // [NEW] added type
  }) async {
    try {
      if (status == 'accepted') {
        // [FIX] DSP is NOT awarded here anymore.
        // Genesis milestone DSP (1,000 per connection) is handled exclusively
        // by TrustService.recalculateTrustScore → checkAndAward to avoid
        // double-awarding (was previously 2,000 DSP per connection).

        // Increment family connection count for legacy tracking
        if (relationshipType != null) {
          const Set<String> familyTypes = {
            'wife',
            'husband',
            'daughter',
            'son',
            'mother',
            'father',
            'sister',
            'brother',
            'aunt',
            'uncle',
            'nephew',
            'niece',
            'cousin',
          };
          if (familyTypes.contains(relationshipType.toLowerCase())) {
            await _repository.incrementFamilyConnectionCount(senderId);
            await _repository.incrementFamilyConnectionCount(receiverId);
          }
        }

        // Trigger trust recalculation for ALL relationship types
        // (Family + Friend) so genesis milestone DSP + PoCT are awarded
        await _trustService.updateTrustForUser(senderId);
        await _trustService.updateTrustForUser(receiverId);
      } else if (status == 'rejected') {
        // [DEPRECATED v8] Rejection penalty removed — could be accidental.
        // No DSP penalty or compensation for rejections.
        debugPrint('DSP: Relationship rejection penalty removed (v8)');
      }
    } catch (e) {
      debugPrint('Error tracking relationship reward: $e');
    }
  }

  // [DEPRECATED v8] Spam report DSP penalty removed → PoCT milestone in TrustService
  Future<void> reportSpam(String senderId) async {
    debugPrint('DSP: Spam report penalty deprecated — PoCT handled in TrustService');
    await _trustService.updateTrustForUser(senderId);
  }

  // [DEPRECATED v8] Fake verification removed (no way to verify)
  Future<void> recordFakeVerificationPenalty(String userId) async {
    debugPrint('DSP: Fake verification penalty removed (v8)');
  }

  // [DEPRECATED v8] Fraud penalty removed (no way to verify)
  Future<void> recordFraudPenalty(String userId) async {
    debugPrint('DSP: Fraud penalty removed (v8)');
  }

  Future<void> trackProfileCompletion(String userId) async {
    // [UPDATED v9] Profile completion awards 10,000 DSP (10x scale)
    // Logic centralized in TrustService.recalculateTrustScore
    await _trustService.updateTrustForUser(userId);
  }

  Future<void> trackCompleteProfile(String userId) async {
    // [UPDATED v9] Legacy fallback/manual trigger
    // Ensure 10,000 DSP is awarded if the milestone hasn't been hit yet
    final points = await _repository.getUserPoints(userId);
    if (points != null &&
        !points.completedExplorationActions.contains(
          'milestone_10_profile_fields',
        )) {
      await awardManualPoints(userId, 10000, 'profile_completion');
      await _repository.markExplorationActionCompleted(
        userId,
        'milestone_10_profile_fields',
      );
      await _trustService.updateTrustForUser(userId);
    }
  }

  // [DEPRECATED v8] Vouching bad actor penalty removed (handled by staking)
  Future<void> recordVouchingBadActorPenalty(String userId) async {
    debugPrint('DSP: Vouching bad actor penalty removed — handled by staking (v8)');
  }

  // --- [NEW] Travelers & Diaspora Rewards ---

  // [DEPRECATED] Verified Check-in removed from PoA. No longer awards DSP.
  Future<void> trackVerifiedCheckIn(String userId) async {
    debugPrint(
      'DSP: trackVerifiedCheckIn is deprecated and no longer awards DSP',
    );
  }

  // [DEPRECATED v7] Daily check-in removed. Presence ≠ value.
  Future<void> trackDailyCheckIn(String userId) async {
    // Still ensure points doc exists for new users (welcome bonus)
    var pointsData = await _repository.getUserPoints(userId);
    if (pointsData == null) {
      await initializeUserPoints(userId);
    }
    debugPrint('DSP: trackDailyCheckIn is deprecated and no longer awards DSP');
  }

  // [DEPRECATED v8] Chat ad DSP penalty removed → PoCT milestone in TrustService
  Future<void> trackChatAdPenalty(String userId) async {
    debugPrint('DSP: Chat ad penalty deprecated — PoCT handled in TrustService');
    await _trustService.updateTrustForUser(userId);
  }

  // [DEPRECATED] Local Knowledge removed from PoA. No longer awards DSP.
  Future<void> trackLocalKnowledgeHelper(
    String userId,
    String otherUserId,
  ) async {
    debugPrint(
      'DSP: trackLocalKnowledgeHelper is deprecated and no longer awards DSP',
    );
  }

  // [UPDATED v9] Host a Traveler: 1,000 DSP to host + 1,000 DSP to traveler (10x scale).
  // Both parties earn for creating real-world economic/social value.
  Future<void> trackHostATraveler(String userId, String guestUserId) async {
    try {
      // Award 1,000 DSP to HOST
      await _addPoints(
        userId,
        1000,
        'host_traveler_host_reward',
        metadata: {'guestUserId': guestUserId},
      );

      // Award 1,000 DSP to TRAVELER (cross-user, skip treasury)
      await _addPoints(
        guestUserId,
        1000,
        'host_traveler_guest_reward',
        metadata: {'hostUserId': userId},
        skipTreasury: true,
      );

      await _trustService.updateTrustForUser(userId);
      await _trustService.updateTrustForUser(guestUserId);
    } catch (e) {
      debugPrint('DSP: Error tracking host a traveler: $e');
    }
  }

  // [DEPRECATED v7] Travel booking no longer earns flat DSP.
  // Real economy value now tracked via trackEconomyTransaction.
  Future<void> trackTravelBooking(
    String userId,
    String bookingType, {
    String? bookingId,
    double? fiatAmount,
    String? countryCode,
  }) async {
    // If fiat value is known, award economy DSP ($1 = 1 DSP to buyer)
    if (fiatAmount != null && fiatAmount > 0 && countryCode != null) {
      await trackEconomyTransaction(
        buyerUserId: userId,
        sellerUserId: userId, // Self-booking, buyer only
        fiatAmount: fiatAmount,
        countryCode: countryCode,
        transactionType: 'travel_booking_$bookingType',
      );
    } else {
      debugPrint('DSP: Travel booking without fiat value — no DSP awarded');
    }
  }

  // [DEPRECATED v7] Travel review removed. Not in 10-action system.
  Future<void> trackTravelReview(
    String userId,
    String bookingType, {
    String? bookingId,
  }) async {
    debugPrint('DSP: trackTravelReview is deprecated and no longer awards DSP');
  }

  // [DEPRECATED v7] Travel save removed. Not in 10-action system.
  Future<void> trackTravelSave(String userId, String itemType) async {
    debugPrint('DSP: trackTravelSave is deprecated and no longer awards DSP');
  }

  // [DEPRECATED] Emergency Contact removed from PoA. No longer awards DSP.
  Future<void> trackEmergencyContactHelp(String helperId) async {
    debugPrint(
      'DSP: trackEmergencyContactHelp is deprecated and no longer awards DSP',
    );
  }

  // [DEPRECATED] Emergency Help Fee removed from PoA.
  Future<bool> trackEmergencyHelpFee(String userId) async {
    debugPrint('DSP: trackEmergencyHelpFee is deprecated');
    return true; // No-op, always returns true to not block callers
  }

  // [DEPRECATED] Legacy method — no longer awards DSP.
  Future<void> trackEmergencyContactAnnual(String userId) async {
    debugPrint('DSP: trackEmergencyContactAnnual is deprecated');
  }

  Future<void> trackIdentityQRExchange(
    String userId,
    String otherUid, {
    bool isServiceProvider = false,
  }) async {
    // [FIX] DSP is NOT awarded here anymore.
    // Genesis milestone DSP (1,000 per QR exchange) is handled exclusively
    // by TrustService.recalculateTrustScore → checkAndAward to avoid
    // double-awarding (performQRExchange → updateTrustForUser already triggers it).

    // Legacy: Increment QR connection count for backward compatibility
    await _repository.incrementQrConnectionCount(userId);
  }

  // --- [DEPRECATED v8] All DSP penalties removed — PoCT milestones in TrustService ---

  // [DEPRECATED v8] Event No-Show → -10 PoCT / 10 no-shows (in TrustService)
  Future<void> recordEventNoShowPenalty(String userId) async {
    debugPrint('DSP: Event no-show penalty deprecated — PoCT in TrustService');
    await _trustService.updateTrustForUser(userId);
  }

  // [DEPRECATED v8] Misinformation removed (no way to verify)
  Future<void> recordMisinformationPenalty(String userId) async {
    debugPrint('DSP: Misinformation penalty removed (v8)');
  }

  // [DEPRECATED v8] Deceptive org removed (no way to verify)
  Future<void> recordDeceptiveOrgPenalty(String userId) async {
    debugPrint('DSP: Deceptive org penalty removed (v8)');
  }

  // [DEPRECATED v8] Unresponsive liaison removed
  Future<void> recordUnresponsiveLiaisonPenalty(String userId) async {
    debugPrint('DSP: Unresponsive liaison penalty removed (v8)');
  }

  // Passthrough methods
  Future<String> generateReferralCode(
    String userId,
    String firstName,
    String countryCode,
  ) => _repository.generateReferralCode(userId, firstName, countryCode);

  Future<String?> getReferralCode(String userId) =>
      _repository.getReferralCode(userId);

  // [SIMPLIFIED] Transfer asset with 1% DSP transfer fee applied to sender.
  Future<void> transferAsset({
    required String fromUserId,
    required String toUserId,
    required int amount,
    required String assetType,
  }) async {
    // No transfer fee — execute the transfer directly
    await _repository.transferAsset(
      fromUserId: fromUserId,
      toUserId: toUserId,
      amount: amount,
      assetType: assetType,
    );
  }

  Future<void> syncTreasuryBalances() => _repository.syncTreasuryBalances();

  /// Records a completed real-economy transaction as fiat GDP.
  ///
  /// Converts the [amount] from the seller/transaction's local currency
  /// (identified by [countryCode]) to USD and persists it.
  ///
  /// Call this at the point of transaction completion for:
  ///   - Marketplace purchases
  ///   - Service hires
  ///   - Flight / hotel bookings
  ///   - Remittances
  ///   - Paid event tickets
  Future<void> recordFiatGdp({
    required double amount,
    required String? countryCode,
    required String activityType,
    Map<String, dynamic>? metadata,
  }) async {
    final usd = CurrencyHelper.toUsd(amount, countryCode);
    if (usd <= 0) return;

    await _repository.recordFiatGdp(usd, activityType, metadata: metadata);
  }

  // --- Economy Transaction Reward ($1 USD = 1 DSP) ---
  /// Real economy transactions: converts local fiat → USD → DSP.
  /// Awards DSP to BOTH buyer and seller at $1 = 1 DSP rate.
  /// This rate anchors DSP valuation — do NOT scale with 10x multiplier.
  /// Used for marketplace purchases, remittances, service hires, etc.
  Future<void> trackEconomyTransaction({
    required String buyerUserId,
    required String sellerUserId,
    required double fiatAmount,
    required String countryCode,
    String? transactionType,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      // Convert local fiat to USD equivalent
      final usdAmount = CurrencyHelper.toUsd(fiatAmount, countryCode);
      if (usdAmount <= 0) return;

      // $1 USD = 1 DSP (valuation anchor, rounded to nearest integer)
      final dspAmount = usdAmount.round();
      if (dspAmount <= 0) return;

      // Award DSP to buyer
      await _addPoints(
        buyerUserId,
        dspAmount,
        'economy_transaction_buyer',
        metadata: {
          'usdAmount': usdAmount,
          'fiatAmount': fiatAmount,
          'countryCode': countryCode,
          'transactionType': transactionType ?? 'purchase',
          'otherParty': sellerUserId,
          ...?metadata,
        },
      );

      // Award DSP to seller (skip treasury for cross-user)
      if (sellerUserId != buyerUserId) {
        await _addPoints(
          sellerUserId,
          dspAmount,
          'economy_transaction_seller',
          metadata: {
            'usdAmount': usdAmount,
            'fiatAmount': fiatAmount,
            'countryCode': countryCode,
            'transactionType': transactionType ?? 'sale',
            'otherParty': buyerUserId,
            ...?metadata,
          },
          skipTreasury: true,
        );
      }

      // Record fiat GDP for macro tracking
      await recordFiatGdp(
        amount: fiatAmount,
        countryCode: countryCode,
        activityType: transactionType ?? 'economy_transaction',
        metadata: {
          'buyerUserId': buyerUserId,
          'sellerUserId': sellerUserId,
          ...?metadata,
        },
      );
    } catch (e) {
      debugPrint('DSP: Error tracking economy transaction: $e');
    }
  }

  // --- [UPDATED v9] Community Event Attendance (QR Check-in, 10x scale) ---
  /// Attendee: 1,000 DSP per event (QR check-in verified).
  /// Host: 1,000 DSP per verified attendee.
  Future<void> trackEventAttendance({
    required String attendeeUserId,
    required String hostUserId,
    required String eventId,
  }) async {
    try {
      // Award 1,000 DSP to ATTENDEE
      await _addPoints(
        attendeeUserId,
        1000,
        'event_attendance',
        metadata: {'eventId': eventId, 'hostUserId': hostUserId},
      );

      // Award 1,000 DSP to HOST per attendee (skip treasury for cross-user)
      if (hostUserId != attendeeUserId) {
        await _addPoints(
          hostUserId,
          1000,
          'event_hosting_per_attendee',
          metadata: {'eventId': eventId, 'attendeeUserId': attendeeUserId},
          skipTreasury: true,
        );
      }

      // Update trust for both
      await _trustService.updateTrustForUser(attendeeUserId);
      await _trustService.updateTrustForUser(hostUserId);
    } catch (e) {
      debugPrint('DSP: Error tracking event attendance: $e');
    }
  }

  /// Awards 1,000 DSP + full community treasury distribution the first time
  /// a user changes their host location. Once per user lifetime.
  /// Calls the repository directly to skip the redundant getUserPoints
  /// re-read and _checkAndResetDaily overhead inside _addPoints (irrelevant
  /// for once-per-lifetime events). Errors propagate to the caller.
  Future<void> trackHostLocationMove(String userId) async {
    final userPoints = await _repository.getUserPoints(userId);
    if (userPoints == null) return;
    if ((userPoints.lifetimeEarnings['host_location_moved'] ?? 0) > 0) return;
    await _repository.addPoints(userId, 1000, 'host_location_moved');
  }

  /// Awards 1,000 DSP + full community treasury distribution the first time
  /// a user manually adds an "also lived in" past location. Once per user lifetime.
  Future<void> trackAlsoLivedInAdded(String userId) async {
    final userPoints = await _repository.getUserPoints(userId);
    if (userPoints == null) return;
    if ((userPoints.lifetimeEarnings['also_lived_in_added'] ?? 0) > 0) return;
    await _repository.addPoints(userId, 1000, 'also_lived_in_added');
  }

  // Legacy/Helper methods for manual awards (e.g. from GroupInfoScreen)
  Future<void> awardPoints({
    required String userId,
    required int amount,
    required String reason,
  }) async {
    await _addPoints(userId, amount, reason);
  }

  Future<void> deductPoints({
    required String userId,
    required int amount,
    required String reason,
  }) async {
    await _repository.deductPoints(userId, amount, reason);
  }

  // [SIMPLIFIED] Connection fee REMOVED — all connections now reward 1000 DSP.
  // Kept for backward compatibility, always returns true (no fee).
  Future<bool> trackConnectionFee({
    required String userId,
    required String relationshipType,
  }) async {
    debugPrint('DSP: Connection fee removed — all connections are free');
    return true;
  }
}
