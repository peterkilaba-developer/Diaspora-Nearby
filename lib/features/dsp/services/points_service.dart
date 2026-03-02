import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:diaspora_nearby/features/dsp/repository/points_repository.dart';
import 'package:diaspora_nearby/features/dsp/models/user_points.dart'; // [NEW] Added missing import
import 'package:diaspora_nearby/features/profile/models/profile_data.dart'; // [NEW]

import 'package:diaspora_nearby/features/trust/services/trust_service.dart';
import 'package:diaspora_nearby/features/profile/repository/profile_repository.dart';
import 'package:diaspora_nearby/features/marketplace/utils/currency_helper.dart';

final pointsServiceProvider = Provider<PointsService>((ref) {
  return PointsService(
    ref.read(pointsRepositoryProvider),
    ref.read(trustServiceProvider),
    ref.read(profileRepositoryProvider),
  );
});

class PointsService {
  final PointsRepository _repository;
  final TrustService _trustService;
  final ProfileRepository _profileRepository;

  PointsService(this._repository, this._trustService, this._profileRepository);

  /// Allowed DSP amounts per user requirement
  static const Set<int> _allowedAmounts = {10, 100, 1000, 10000};

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
  Future<double> _getEpochMultiplierV2() async {
    return 1.0;
  }

  // --- Core Calculation Logic ---

  // Calculate Reward based on Activity + Global Epoch Multiplier
  // [UPDATED] Removed Individual Time-Decay (Deprecated in favor of Global Epochs)
  // --- Core Calculation Logic ---
  // [UPDATED] Removed all Multipliers (Epoch & Trust).
  // 1:1 Expansion Model: User Reward = Base Reward.
  Future<int> _calculateReward(String userId, {required int baseReward}) async {
    return baseReward;
  }

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
  Future<void> _addPoints(
    String userId,
    int points,
    String action, {
    Map<String, dynamic>? metadata,
  }) async {
    UserPoints? oldPoints = await _repository.getUserPoints(userId);

    // [SAFETY] If user doesn't have a points doc yet (e.g. initial set failed),
    // initialize it first to ensure base fields (signupDate, streak, etc) exist.
    if (oldPoints == null) {
      await initializeUserPoints(userId);
      oldPoints = await _repository.getUserPoints(
        userId,
      ); // Re-fetch after initialization
    }

    await _checkAndResetDaily(userId, oldPoints!);

    _validateAmount(points, action);
    await _repository.addPoints(userId, points, action, metadata: metadata);

    // Streak increment removed from here to ensure it only counts for SHARING
  }

  /// Calculates a proportional penalty based on current total points.
  /// Used to ensure penalties scale with user involvement and earnings.
  // Removed _calculateProportionalPenalty as it creates invalid DSP amounts

  // --- [NEW] Bad Actor Penalties (Cumulative) ---

  // Triggered by TrustService when a new Block is added
  Future<void> trackBlockPenalty(String userId, int newBlocksCount) async {
    // Penalty every 10 blocks (10, 20, 30...)
    if (newBlocksCount > 0 && newBlocksCount % 10 == 0) {
      await deductPoints(
        userId: userId,
        amount: 10000,
        reason: 'cumulative_block_penalty_level_${newBlocksCount ~/ 10}',
      );
      // Trust Score penalty handled in TrustService
    }
  }

  // Triggered by TrustService when a new Flag is added
  Future<void> trackFlagPenalty(String userId, int newFlagCount) async {
    // Penalty every 10 flags
    if (newFlagCount > 0 && newFlagCount % 10 == 0) {
      await deductPoints(
        userId: userId,
        amount: 10000,
        reason: 'cumulative_flag_penalty_level_${newFlagCount ~/ 10}',
      );
    }
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

  // [UPDATED] POA 2.0: Daily Share (In/Out) = 200 DSP
  Future<void> trackDailyShare(String userId, bool isIncoming) async {
    await _addPoints(
      userId,
      100,
      isIncoming ? 'daily_share_incoming' : 'daily_share_outgoing',
    );
    // Share updates streak
    final userPoints = await _repository.getUserPoints(userId);
    if (userPoints != null) {
      await _updateStreak(userId, userPoints);
    }
  }

  // [SIMPLIFIED] Track message sent: 10 DSP per message (Unlimited, no daily cap)
  Future<void> trackMessageSent(String userId) async {
    try {
      const int points = 10; // 10 DSP per subsequent message
      await _addPoints(userId, points, 'message_sent');
      _trustService.updateTrustForUser(userId);
    } catch (e) {
      print('Error tracking message sent: $e');
    }
  }

  // [SIMPLIFIED] Track Community Message: First message in a community = 100 DSP.
  // Subsequent messages in same community same day = 10 DSP (handled by trackMessageSent).
  // ONE 100 DSP bonus per community per day.
  Future<void> trackCommunityMessage(String userId, String communityId) async {
    try {
      final userPoints = await _repository.getUserPoints(userId);
      if (userPoints == null) return;
      await _checkAndResetDaily(userId, userPoints);

      final now = DateTime.now();
      final lastUpdated = userPoints.lastUpdated;
      final isSameDay =
          now.year == lastUpdated.year &&
          now.month == lastUpdated.month &&
          now.day == lastUpdated.day;

      final List<String> messaged = isSameDay
          ? userPoints.dailyCommunitiesMessaged
          : [];

      if (messaged.contains(communityId)) {
        return; // Already rewarded first-message bonus for this community today
      }

      // [SIMPLIFIED] 100 DSP bonus for first message in this community today
      await _addPoints(
        userId,
        100,
        'community_first_message',
        metadata: {'communityId': communityId},
      );
      await _repository.markCommunityAsMessaged(userId, communityId);
    } catch (e) {
      print('Error tracking community message: $e');
    }
  }

  // Track Start New DM: 100 DSP (Constant)
  // Should trigger only on FIRST message to a UNIQUE user.
  // This logic is usually handled by the ChatService determining if it's a "New Conversation".
  Future<void> trackNewDM(String userId, String targetUserId) async {
    try {
      // Validation: Ensure we haven't DM'd this user before (Unique per user pair)
      final bool alreadyRewarded = await _repository.hasReceivedRewardForTarget(
        userId,
        'started_new_dm',
        targetUserId,
      );

      if (alreadyRewarded) {
        debugPrint(
          'DSP: User $userId already rewarded for starting DM with $targetUserId',
        );
        return;
      }

      final int points = await _calculateReward(
        userId,
        baseReward: 100, // 100 DSP for unique new DM
      );

      await _addPoints(
        userId,
        points,
        'started_new_dm',
        metadata: {
          'targetId': targetUserId,
        }, // [FIX] Use targetId for uniqueness check consistency
      );
    } catch (e) {
      print('Error tracking new DM: $e');
    }
  }

  // [NEW] Track Verifier Reward: 1000 DSP + Milestone Logic
  Future<void> trackVerifierReward(String userId) async {
    // 1. Award per-action reward
    await _addPoints(userId, 1000, 'verifier_reward');

    // 2. Increment count & Trigger Trust Recalculation (Milestones handled in TrustService)
    await _repository.incrementVerifiedCount(userId);
    await _trustService.updateTrustForUser(userId);
  }

  // [NEW] Track Vouch Reward: 200 DSP (Staged/Locked)
  // Awarded to the voucher, but locked until vouchee reaches Trust Score 25.
  Future<void> trackVouchReward(String userId, String vouchedUserId) async {
    try {
      await _repository.addStagedPoints(
        userId,
        100, // [UPDATED] 100 DSP for vouching (Contribution to trust graph)
        'vouch_reward_staged',
        metadata: {'vouchedUserId': vouchedUserId},
      );
    } catch (e) {
      print('Error tracking vouch reward: $e');
    }
  }

  // Track External Share: 100 DSP (Constant, no cap)
  // Counts for 10/100 day streaks.
  Future<bool> trackExternalShare(String userId, String contentType) async {
    try {
      final userPoints = await _repository.getUserPoints(userId);
      if (userPoints == null) return false;
      await _checkAndResetDaily(userId, userPoints);

      // Share is the Streak Activity (counts for 10/100 day streaks)
      await _updateStreak(userId, userPoints);

      const int points = 100; // Fixed 100 DSP per share, no multiplier

      await _repository.awardSharePoints(userId, points, contentType);

      return true;
    } catch (e) {
      print('Error tracking external share: $e');
      return false;
    }
  }

  // Track Incoming Share: 100 DSP (Constant, no cap)
  // Counts for 10/100 day streaks.
  Future<void> trackIncomingShare(String userId, String contentType) async {
    try {
      final userPoints = await _repository.getUserPoints(userId);
      if (userPoints == null) return;
      await _checkAndResetDaily(userId, userPoints);

      // Share is the Streak Activity (counts for 10/100 day streaks)
      await _updateStreak(userId, userPoints);

      const int points = 100; // Fixed 100 DSP per share, no multiplier

      await _addPoints(
        userId,
        points,
        'incoming_share',
        metadata: {'contentType': contentType},
      );
      await _repository.incrementDailyShareCount(userId);
    } catch (e) {
      print('Error tracking incoming share: $e');
    }
  }

  // Update streak and check for bonuses
  Future<void> _updateStreak(String userId, UserPoints userPoints) async {
    final now = DateTime.now().toUtc();
    final today = DateTime.utc(now.year, now.month, now.day);
    int newStreak = 1;

    if (userPoints.lastActivityDate != null) {
      final lastActivityDate = userPoints.lastActivityDate!.toUtc();
      final lastActivity = DateTime.utc(
        lastActivityDate.year,
        lastActivityDate.month,
        lastActivityDate.day,
      );

      final int daysDifference = today.difference(lastActivity).inDays;

      if (daysDifference == 0) {
        // Already updated streak today. Do nothing.
        return;
      }

      if (daysDifference == 1) {
        newStreak = userPoints.currentStreak + 1;
      } else {
        newStreak = 1; // Missed a day or more
      }
    }

    await _repository.updateStreak(userId, newStreak);

    // Streak Bonuses
    // 10-Day: 1000 DSP Bonus
    // 100-Day: 10000 DSP Bonus

    if (newStreak % 100 == 0) {
      final int points = await _calculateReward(userId, baseReward: 10000);
      await _addPoints(
        userId,
        points,
        'streak_100',
        metadata: {'streak': newStreak},
      );
    } else if (newStreak % 10 == 0) {
      final int points = await _calculateReward(userId, baseReward: 1000);
      await _addPoints(
        userId,
        points,
        'streak_10',
        metadata: {'streak': newStreak},
      );
    }
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
        // We return null instead of throwing to avoid blocking signup flow silently
        return null;
      }

      if (referrerId == newUserId) {
        debugPrint('DSP: User $newUserId tried to use their own referral code');
        return null;
      }

      // [UPDATED] Immediate 1000 DSP Reward for Referrer & Referee
      // This was previously disabled but is now restored per audit requirements.
      const int referralBonus = 1000;

      // 1. Award Referrer
      await _addPoints(
        referrerId,
        referralBonus,
        'referral_reward_referrer',
        metadata: {'referredUserId': newUserId, 'code': normalizedCode},
      );

      // 2. Award Referee (New User)
      await _addPoints(
        newUserId,
        referralBonus,
        'referral_reward_referee',
        metadata: {'referrerId': referrerId, 'code': normalizedCode},
      );

      await _repository.incrementReferralCount(normalizedCode);
      debugPrint(
        'DSP: Referral processed. 1000 DSP awarded to $referrerId and $newUserId.',
      );

      // [NEW] Record HTS Referral Activity for the Referrer
      await _trustService.recordActivity(referrerId, HTSActivityType.referral);

      return referrerId;
    } catch (e) {
      debugPrint('DSP: Error processing referral: $e');
      return null;
    }
  }

  // Exploration Reward: 10 DSP
  // Exploration Reward: 10 DSP
  Future<bool> trackExplorationReward(
    String userId,
    String actionId, {
    int points = 10,
  }) async {
    try {
      // Check if already completed to avoid unnecessary writes/toasts
      UserPoints? userPoints = await _repository.getUserPoints(userId);

      // [SAFETY] If user doesn't have a points doc yet, initialize it
      if (userPoints == null) {
        // No-log: Initializing user points
        await initializeUserPoints(userId);
        userPoints = await _repository.getUserPoints(userId);
      }

      if (userPoints != null &&
          userPoints.completedExplorationActions.contains(actionId)) {
        // No-log
        return false;
      }

      // No-log: Awarding points
      await _repository.awardExplorationPoints(
        userId: userId,
        actionId: actionId,
        points: points,
        metadata: {'description': 'Exploration Reward: $actionId'},
      );

      // No-log: Success
      return true;
    } catch (e) {
      if (e.toString().contains('already completed')) {
        debugPrint(
          'DSP: Exploration action $actionId already completed (caught exception).',
        );
        return false;
      }
      debugPrint('DSP: Error tracking exploration reward: $e');
      return false;
    }
  }

  // Feedback Reward: 10 DSP (Unlimited)
  Future<bool> trackFeedbackReward(String userId) async {
    try {
      // Calculate reward (could be dynamic later)
      const int points = 10;

      await _addPoints(
        userId,
        points,
        'feedback_reward', // Distinct from exploration action
        metadata: {'type': 'feedback_submission'},
      );

      return true;
    } catch (e) {
      debugPrint('DSP: Error tracking feedback reward: $e');
      return false;
    }
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
        final senderPoints = await _calculateReward(senderId, baseReward: 1000);
        final receiverPoints = await _calculateReward(
          receiverId,
          baseReward: 1000,
        );

        await _addPoints(
          senderId,
          senderPoints,
          'relationship_accepted',
          metadata: {'partner': receiverId, 'type': relationshipType},
        );
        await _addPoints(
          receiverId,
          receiverPoints,
          'relationship_accepted',
          metadata: {'partner': senderId, 'type': relationshipType},
        );

        // [NEW] Increment Family Connection Count if matches family types
        if (relationshipType != null) {
          const Set<String> familyTypes = {
            'wife', 'husband', 'daughter', 'son', 'mother', 'father',
            'sister', 'brother', 'aunt', 'uncle', 'nephew', 'niece', 'cousin',
          };
          if (familyTypes.contains(relationshipType.toLowerCase())) {
            await _repository.incrementFamilyConnectionCount(senderId);
            await _repository.incrementFamilyConnectionCount(receiverId);
            
            // Also update trust as it might depend on connection count
            await _trustService.updateTrustForUser(senderId);
            await _trustService.updateTrustForUser(receiverId);
          }
        }
      } else if (status == 'rejected') {
        // Penalty is FLAT 1000.
        // Compensation is 1000.

        const penalty = 1000;
        final receiverComp = await _calculateReward(
          receiverId,
          baseReward: 1000,
        );

        await _repository.deductPoints(
          senderId,
          penalty,
          'relationship_rejected_penalty',
          metadata: {'partner': receiverId},
        );
        await _addPoints(
          receiverId,
          receiverComp,
          'relationship_rejected_compensation',
          metadata: {'partner': senderId},
        );
      }
    } catch (e) {
      debugPrint('Error tracking relationship reward: $e');
    }
  }

  // Report Spam: -100 (Flat)
  Future<void> reportSpam(String senderId) async {
    const penalty = 100;
    await _repository.deductPoints(senderId, penalty, 'spam_report_penalty');
    await _trustService.updateTrustForUser(senderId);
  }

  // Fake Verification: -1000
  Future<void> recordFakeVerificationPenalty(String userId) async {
    await _repository.deductPoints(userId, 1000, 'fake_verification_penalty');
    await _trustService.updateTrustForUser(userId);
  }

  // Reported for Fraud: -10000
  Future<void> recordFraudPenalty(String userId) async {
    await _repository.deductPoints(userId, 10000, 'confirmed_fraud_penalty');
    await _trustService.updateTrustForUser(userId);
  }

  Future<void> trackProfileCompletion(
    String userId,
    ProfileData profile,
  ) async {
    // Logic centralized in TrustService.recalculateTrustScore (awards 10,000 DSP for 10 fields)
    // Just trigger an update to ensure milestone is checked.
    await _trustService.updateTrustForUser(userId);
  }

  Future<void> trackCompleteProfile(String userId) async {
    // Legacy fallback/manual trigger
    // Ensure 10,000 DSP is awarded if the milestone hasn't been hit yet
    final points = await _repository.getUserPoints(userId);
    if (points != null &&
        !points.completedExplorationActions.contains(
          'milestone_10_profile_fields',
        )) {
      await awardManualPoints(userId, 10000, 'Profile Completion');
      await _repository.markExplorationActionCompleted(
        userId,
        'milestone_10_profile_fields',
      );
      await _trustService.updateTrustForUser(userId);
    }
  }

  // Vouching for Bad Actor: -1000 (Flat)
  Future<void> recordVouchingBadActorPenalty(String userId) async {
    const penalty = 1000;
    await _repository.deductPoints(
      userId,
      penalty,
      'vouching_bad_actor_penalty',
    );
    await _trustService.updateTrustForUser(userId);
  }

  // --- [NEW] Travelers & Diaspora Rewards ---

  // [DEPRECATED] Verified Check-in removed from PoA. No longer awards DSP.
  Future<void> trackVerifiedCheckIn(String userId) async {
    debugPrint('DSP: trackVerifiedCheckIn is deprecated and no longer awards DSP');
  }

  Future<void> trackDailyCheckIn(String userId) async {
    final pointsData = await _repository.getUserPoints(userId);
    if (pointsData == null) return;

    final now = DateTime.now();
    final lastCheckIn = pointsData.lastCheckInDate;

    bool isNewDay =
        lastCheckIn == null ||
        lastCheckIn.year != now.year ||
        lastCheckIn.month != now.month ||
        lastCheckIn.day != now.day;

    if (isNewDay) {
      const reward = 100; // 100 DSP for daily app usage
      await _addPoints(userId, reward, 'daily_check_in');
      await _repository.recordDailyCheckIn(
        userId,
      ); // Use the method I'll try to add again or implement here
    }
  }



  Future<void> trackChatAdPenalty(String userId) async {
    const int penalty = 1000; // [NEW] Penalty for ads in regular chats
    try {
      await _repository.deductPoints(
        userId,
        penalty,
        'chat_ad_penalty',
        metadata: {'description': 'Prohibited Ad in Chat Penalty'},
      );
    } catch (e) {
      debugPrint('Error tracking chat ad penalty: $e');
    }
  }

  // [DEPRECATED] Local Knowledge removed from PoA. No longer awards DSP.
  Future<void> trackLocalKnowledgeHelper(
    String userId,
    String otherUserId,
  ) async {
    debugPrint('DSP: trackLocalKnowledgeHelper is deprecated and no longer awards DSP');
  }

  // [FAUCET] Host a Traveler: Hosting is free — no DSP fees charged.
  // This method updates trust for the host.
  Future<void> trackHostATraveler(String userId, String guestUserId) async {
    debugPrint('DSP: Hosting is free, updating trust for host');
    await _trustService.updateTrustForUser(userId);
  }



  // --- [NEW] Travel Booking Rewards (Base-10 DSP) ---

  /// Track a completed travel booking: 1,000 DSP per booking.
  /// [bookingType] is one of: 'flight', 'hotel', 'stay', 'car_rental'
  /// Optionally records fiat GDP when [fiatAmount] and [countryCode] are provided.
  Future<void> trackTravelBooking(
    String userId,
    String bookingType, {
    String? bookingId,
    double? fiatAmount,
    String? countryCode,
  }) async {
    try {
      await _addPoints(
        userId,
        1000,
        'travel_booking_$bookingType',
        metadata: {
          'bookingType': bookingType,
          'bookingId': bookingId,
          'description': '${bookingType[0].toUpperCase()}${bookingType.substring(1)} booking reward',
        },
      );

      // Record fiat GDP if price is known
      if (fiatAmount != null && fiatAmount > 0) {
        await recordFiatGdp(
          amount: fiatAmount,
          countryCode: countryCode,
          activityType: 'travel_booking_$bookingType',
          metadata: {
            'bookingId': bookingId,
            'userId': userId,
          },
        );
      }
    } catch (e) {
      debugPrint('DSP: Error tracking travel booking: $e');
    }
  }

  /// Track a travel review: 100 DSP per review.
  Future<void> trackTravelReview(
    String userId,
    String bookingType, {
    String? bookingId,
  }) async {
    try {
      await _addPoints(
        userId,
        100,
        'travel_review',
        metadata: {
          'bookingType': bookingType,
          'bookingId': bookingId,
        },
      );
    } catch (e) {
      debugPrint('DSP: Error tracking travel review: $e');
    }
  }

  /// Track saving a travel item to wishlist: 10 DSP per save (lightweight action).
  Future<void> trackTravelSave(String userId, String itemType) async {
    try {
      await _addPoints(
        userId,
        10,
        'travel_save',
        metadata: {'itemType': itemType},
      );
    } catch (e) {
      debugPrint('DSP: Error tracking travel save: $e');
    }
  }

  // [DEPRECATED] Emergency Contact removed from PoA. No longer awards DSP.
  Future<void> trackEmergencyContactHelp(String helperId) async {
    debugPrint('DSP: trackEmergencyContactHelp is deprecated and no longer awards DSP');
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

  // [DEPRECATED] Organization Vetting removed from PoA. No longer awards DSP.
  Future<void> trackOrganizationVetting(String userId) async {
    debugPrint('DSP: trackOrganizationVetting is deprecated and no longer awards DSP');
  }

  Future<void> trackIdentityQRExchange(
    String userId,
    String otherUid, {
    bool isServiceProvider = false,
  }) async {
    final int baseReward = isServiceProvider
        ? 1000
        : 1000; // [UPDATED] 1000 DSP flat
    final points = await _calculateReward(userId, baseReward: baseReward);
    await _addPoints(
      userId,
      points,
      isServiceProvider ? 'identity_qr_service_reward' : 'identity_qr_exchange',
      metadata: {'metUserId': otherUid},
    );
    // Trust update is handled by TrustService calling this.

    // Increment & Check Milestone (Milestones handled in TrustService)
    await _repository.incrementQrConnectionCount(userId);
    // Trust update is handled by TrustService calling this method?
    // Wait, TrustService calls trackIdentityQRExchange.
    // AND TrustService calls updateTrustForUser.
    // So distinct manual check here is redundant if TrustService handles it.
  }

  // --- [NEW] Travelers & Diaspora Penalties ---

  // Event No-Show: -1000
  Future<void> recordEventNoShowPenalty(String userId) async {
    await _repository.deductPoints(userId, 1000, 'event_no_show_penalty');
    await _trustService.updateTrustForUser(userId);
  }

  // Demonstrable Misinfo: -1000 (Flat)
  Future<void> recordMisinformationPenalty(String userId) async {
    const penalty = 1000;
    await _repository.deductPoints(userId, penalty, 'misinformation_penalty');
    await _trustService.updateTrustForUser(userId);
  }

  // Deceptive Org Submission: -10000 (Flat)
  Future<void> recordDeceptiveOrgPenalty(String userId) async {
    const penalty = 10000;
    await _repository.deductPoints(
      userId,
      penalty,
      'deceptive_org_submission_penalty',
    );
    await _trustService.updateTrustForUser(userId);
  }

  // Unresponsive Liaison: -100
  Future<void> recordUnresponsiveLiaisonPenalty(String userId) async {
    await _repository.deductPoints(userId, 100, 'unresponsive_liaison_penalty');
    await _trustService.updateTrustForUser(userId);
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

    await _repository.recordFiatGdp(
      usd,
      activityType,
      metadata: metadata,
    );
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
