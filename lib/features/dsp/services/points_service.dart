import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:diaspora_nearby/features/dsp/repository/points_repository.dart';
import 'package:diaspora_nearby/features/dsp/models/user_points.dart';

import 'package:diaspora_nearby/features/trust/services/trust_service.dart';
import 'package:diaspora_nearby/features/profile/repository/profile_repository.dart';

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

  PointsService(
    this._repository,
    this._trustService,
    this._profileRepository,
  );

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
  Future<int> _calculateReward(
    String userId, {
    required int baseReward,
  }) async {
    try {
      // 1. [UPDATED] Apply Epoch Multiplier (Global Scarcity)
      // This naturally reduces rewards as the platform scales (1.0 -> 0.1).
      final double epochMultiplier = await _getEpochMultiplierV2();

      // Final Reward = Base * EpochMultiplier
      final int finalReward = (baseReward * epochMultiplier).round();

      return finalReward;
    } catch (e) {
      debugPrint('Error calculating reward: $e');
      return baseReward;
    }
  }

  /// Checks if a new day has started and resets counters if needed.
  Future<void> _checkAndResetDaily(String userId, UserPoints userPoints) async {
    final now = DateTime.now();
    final lastUpdated = userPoints.lastUpdated;
    final isSameDay = now.year == lastUpdated.year &&
        now.month == lastUpdated.month &&
        now.day == lastUpdated.day;

    if (!isSameDay) {
      await _repository.resetDailyCounters(userId);
    }
  }


  /// Centralized DSP awarder that handles community tribute
  Future<void> _addPoints(String userId, int points, String action, {Map<String, dynamic>? metadata}) async {
    UserPoints? oldPoints = await _repository.getUserPoints(userId);

    // [SAFETY] If user doesn't have a points doc yet (e.g. initial set failed), 
    // initialize it first to ensure base fields (signupDate, streak, etc) exist.
    if (oldPoints == null) {
      await initializeUserPoints(userId);
      oldPoints = await _repository.getUserPoints(userId); // Re-fetch after initialization
    }

    await _checkAndResetDaily(userId, oldPoints!);

    await _repository.addPoints(userId, points, action, metadata: metadata);
  }

  /// Calculates a proportional penalty based on current total points.
  /// Used to ensure penalties scale with user involvement and earnings.
  Future<int> _calculateProportionalPenalty(String userId, double percentage, int minAmount) async {
    try {
      final userPoints = await _repository.getUserPoints(userId);
      final total = userPoints?.totalPoints ?? 0;
      final int proportionalAmount = (total * percentage).round();
      return proportionalAmount > minAmount ? proportionalAmount : minAmount;
    } catch (e) {
      debugPrint('Error calculating proportional penalty: $e');
      return minAmount;
    }
  }

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
  Future<void> awardManualPoints(String userId, int points, String reason, {Map<String, dynamic>? metadata}) async {
    await _addPoints(userId, points, reason, metadata: metadata);
  }

  // Initialize points for new user
  Future<void> initializeUserPoints(String userId) async {
    await _repository.initializeUserPoints(userId);
  }


  // [UPDATED] POA 2.0: Daily Share (In/Out) = 200 DSP
  Future<void> trackDailyShare(String userId, bool isIncoming) async {
    await _addPoints(userId, 100, isIncoming ? 'daily_share_incoming' : 'daily_share_outgoing');
    // Share updates streak
     final userPoints = await _repository.getUserPoints(userId);
      if (userPoints != null) {
         await _updateStreak(userId, userPoints);
      }
  }


  // Track message sent: 10 DSP (Constant)
  // Max 100/day already enforced in Repository.
  Future<void> trackMessageSent(String userId) async {
    try {
      final int points = await _calculateReward(
        userId,
        baseReward: 10, // [UPDATED] 10 DSP per message (doc: 10)
      );
      // We pass 1 as multiplier because we calculated the exact points already?
      // No, repository multiplies points * multiplier.
      // Existing repository: awardMessagePoint(userId, points, multiplier: 1).
      // We should refactor repository to just take 'amount' to be cleaner, but for now:
      await _repository.awardMessagePoint(userId, points);
      
      // Special check for message points since they use a different repo method
      _trustService.updateTrustForUser(userId);
    } catch (e) {
      print('Error tracking message sent: $e');
    }
  }

  // Track Community Message: 100 DSP (Constant)
  // ONE per community per day.
  Future<void> trackCommunityMessage(String userId, String communityId) async {
    try {
      final userPoints = await _repository.getUserPoints(userId);
      if (userPoints == null) return;
      await _checkAndResetDaily(userId, userPoints);

      // Refresh data after reset check (or assume it's updated)
      // If reset happened, dailyCommunitiesMessaged is empty.
      // If not, we check list.
      // Note: resetDailyCounters is async. We might need to re-fetch to be safe, or trust the reset.
      // Optimization: We can check local [dailyCommunitiesMessaged] if isSameDay is true.
      final now = DateTime.now();
      final lastUpdated = userPoints.lastUpdated;
      final isSameDay = now.year == lastUpdated.year &&
          now.month == lastUpdated.month &&
          now.day == lastUpdated.day;
      
      final List<String> messaged = isSameDay ? userPoints.dailyCommunitiesMessaged : [];

      if (messaged.contains(communityId)) return; // Already rewarded for this community

      final int points = await _calculateReward(
        userId,
        baseReward: 100,
      );

      await _addPoints(
        userId,
        points,
        'community_message',
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
      // Validation: Ensure we haven't DM'd this user before? 
      // This is hard to track solely in PointsService without a "List<String> messagedUsers".
      // Assuming ChatService calls this ONLY when a new chat doc is created.
      
      final int points = await _calculateReward(
        userId,
        baseReward: 100, // Reduced from 1000 for spam protection
      );

      await _addPoints(
        userId,
        points,
        'started_new_dm',
        metadata: {'targetUserId': targetUserId},
      );
     } catch (e) {
       print('Error tracking new DM: $e');
     }
  }

  // [NEW] Track Verifier Reward: 100 DSP (Constant)
  Future<void> trackVerifierReward(String userId) async {
    await _addPoints(userId, 100, 'verifier_reward');
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

  // Track External Share: 100 DSP (Constant)
  // Max 12/day.
  Future<bool> trackExternalShare(String userId, String contentType) async {
    try {
      final userPoints = await _repository.getUserPoints(userId);
      if (userPoints == null) return false;
      await _checkAndResetDaily(userId, userPoints);

      // Check Cap (12)
       final now = DateTime.now();
       final lastUpdated = userPoints.lastUpdated;
       final isSameDay = now.year == lastUpdated.year &&
          now.month == lastUpdated.month &&
          now.day == lastUpdated.day;
       final int currentShares = isSameDay ? userPoints.dailyShareCount : 0;
       
       if (currentShares >= 12) return false;

       
       // Share is now the Streak Activity
       await _updateStreak(userId, userPoints);

      final int points = await _calculateReward(
        userId,
        baseReward: 100, // [UPDATED] 100 DSP per share (doc: 100)
      );

      await _repository.awardSharePoints(userId, points, contentType);
      
      // actually awardSharePoints repo method also does the adding.
      // I'll stick to it.
      return true;
    } catch (e) {
      print('Error tracking external share: $e');
      return false;
    }
  }

  // Track Incoming Share: 100 DSP (Constant)
  Future<void> trackIncomingShare(String userId, String contentType) async {
    try {
       // Is there a daily limit for incoming shares? "Share (In): Max 12/Day"
       // Reuse tracking logic? 
       // Let's assume same limit bucket.
      final userPoints = await _repository.getUserPoints(userId);
      if (userPoints == null) return;
      await _checkAndResetDaily(userId, userPoints);

       final now = DateTime.now();
       final lastUpdated = userPoints.lastUpdated;
       final isSameDay = now.year == lastUpdated.year &&
          now.month == lastUpdated.month &&
          now.day == lastUpdated.day;
       final int currentShares = isSameDay ? userPoints.dailyShareCount : 0; // Shared bucket
       
       if (currentShares >= 12) return;

       
       // Share is now the Streak Activity
       await _updateStreak(userId, userPoints);

      final int points = await _calculateReward(
        userId,
        baseReward: 100, // [UPDATED] 100 DSP per share (doc: 100)
      );

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
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    int newStreak = 1;

    if (userPoints.lastActivityDate != null) {
      final lastActivity = DateTime(
        userPoints.lastActivityDate!.year,
        userPoints.lastActivityDate!.month,
        userPoints.lastActivityDate!.day,
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
       final int points = await _calculateReward(
        userId,
        baseReward: 10000,
      );
      await _addPoints(userId, points, 'streak_100', metadata: {'streak': newStreak});
    } else if (newStreak % 10 == 0) {
       final int points = await _calculateReward(
        userId,
        baseReward: 1000,
      );
      await _addPoints(userId, points, 'streak_10', metadata: {'streak': newStreak});
    }
  }

  // Process referral: Returns referrerId for relationship connection (No immediate reward)
  Future<String?> processReferral(String code, String newUserId) async {
    final normalizedCode = code.trim().toUpperCase();
    debugPrint('DSP: Processing referral code: $normalizedCode for new user: $newUserId');

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

      // [UPDATED] No immediate DSP reward.
      // Rewards are now contingent on establishing a verified relative connection.
      // We just log the referral for analytics.
      
      await _repository.incrementReferralCount(normalizedCode);
      debugPrint('DSP: Referral validated for $normalizedCode. Returning referrer: $referrerId');
      
      return referrerId;
    } catch (e) {
      debugPrint('DSP: Error processing referral: $e');
      return null;
    }
  }

  // Exploration Reward: 10 DSP
  Future<bool> trackExplorationReward(String userId, String actionId, {int points = 10}) async {
    try {
      await _repository.awardExplorationPoints(
        userId: userId,
        actionId: actionId,
        points: points,
        metadata: {'description': 'Exploration Reward: $actionId'},
      );
      
      return true;
    } catch (e) {
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
  }) async {
    try {
      if (status == 'accepted') {
        final senderPoints = await _calculateReward(senderId, baseReward: 1000);
        final receiverPoints = await _calculateReward(receiverId, baseReward: 1000);
        
        await _addPoints(senderId, senderPoints, 'relationship_accepted', metadata: {'partner': receiverId});
        await _addPoints(receiverId, receiverPoints, 'relationship_accepted', metadata: {'partner': senderId});
      } else if (status == 'rejected') {
        // Penalty is FLAT 1000.
        // Compensation is 1000.
        
        const penalty = 1000;
        final receiverComp = await _calculateReward(receiverId, baseReward: 1000);

        await _repository.deductPoints(senderId, penalty, 'relationship_rejected_penalty', metadata: {'partner': receiverId});
        await _addPoints(receiverId, receiverComp, 'relationship_rejected_compensation', metadata: {'partner': senderId});
      }
    } catch (e) {
      debugPrint('Error tracking relationship reward: $e');
    }
}

  // [NEW] POA 2.0 Relationship Action
  // Accepted: Sender +1000, Receiver +100
  // Rejected: Rejector +1000, Sender -1000
  Future<void> trackRelationshipAction(String senderId, String receiverId, bool isAccepted) async {
      try {
        if (isAccepted) {
          // Sender gets 1000
          await _addPoints(senderId, 1000, 'relationship_accepted_sender', metadata: {'partner': receiverId});
           // Receiver gets 100
          await _addPoints(receiverId, 100, 'relationship_accepted_receiver', metadata: {'partner': senderId});
        } else {
           // Rejector (Receiver) gets 1000
           await _addPoints(receiverId, 1000, 'relationship_rejected_reward', metadata: {'partner': senderId});
           // Sender loses 1000
           await deductPoints(userId: senderId, amount: 1000, reason: 'relationship_rejected_penalty');
        }
      } catch (e) {
        debugPrint('Error tracking relationship action: $e');
      }
  }

  // Report Spam: Sender -100 (Min) or 1%
  Future<void> reportSpam(String senderId) async {
    final penalty = await _calculateProportionalPenalty(senderId, 0.01, 100);
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

  // Vouching for Bad Actor: -1000 (Min) or 2%
  Future<void> recordVouchingBadActorPenalty(String userId) async {
    final penalty = await _calculateProportionalPenalty(userId, 0.02, 1000);
    await _repository.deductPoints(
      userId,
      penalty,
      'vouching_bad_actor_penalty',
    );
    await _trustService.updateTrustForUser(userId);
  }

  // --- [NEW] Travelers & Diaspora Rewards ---

  Future<void> trackVerifiedCheckIn(String userId) async {
    final points = await _calculateReward(userId, baseReward: 1000); // [UPDATED] 1,000 DSP
    await _addPoints(userId, points, 'verified_check_in');
  }

  Future<void> trackLocalKnowledgeHelper(
    String userId,
    String otherUserId,
  ) async {
    final points = await _calculateReward(userId, baseReward: 1000);
    await _addPoints(
      userId,
      points,
      'local_knowledge_helper',
      metadata: {'helpedUserId': otherUserId},
    );
    await _trustService.updateTrustForUser(userId);
  }

  Future<void> trackHostATraveler(String userId, String guestUserId) async {
    final points = await _calculateReward(userId, baseReward: 1000);
    await _addPoints(
      userId,
      points,
      'host_a_traveler',
      metadata: {'guestUserId': guestUserId},
    );
    await _trustService.updateTrustForUser(userId);
  }

  Future<void> trackEmergencyContactAnnual(String userId) async {
    final points = await _calculateReward(userId, baseReward: 1000);
    await _addPoints(userId, points, 'emergency_contact_annual_reward');
  }

  Future<void> trackOrganizationVetting(String userId) async {
    final points = await _calculateReward(userId, baseReward: 1000);
    await _addPoints(userId, points, 'organization_vetting');
  }

  Future<void> trackIdentityQRExchange(String userId, String otherUid, {bool isServiceProvider = false}) async {
    final int baseReward = isServiceProvider ? 1000 : 10000;
    final points = await _calculateReward(userId, baseReward: baseReward);
    await _addPoints(
      userId,
      points,
      isServiceProvider ? 'identity_qr_service_reward' : 'identity_qr_exchange',
      metadata: {'metUserId': otherUid},
    );
    // Trust update is handled by TrustService calling this.
  }

  // --- [NEW] Travelers & Diaspora Penalties ---

  // Event No-Show: -1000
  Future<void> recordEventNoShowPenalty(String userId) async {
    await _repository.deductPoints(userId, 1000, 'event_no_show_penalty');
    await _trustService.updateTrustForUser(userId);
  }

  // Demonstrable Misinfo: -1000 (Min) or 2%
  Future<void> recordMisinformationPenalty(String userId) async {
    final penalty = await _calculateProportionalPenalty(userId, 0.02, 1000);
    await _repository.deductPoints(userId, penalty, 'misinformation_penalty');
    await _trustService.updateTrustForUser(userId);
  }

  // Deceptive Org Submission: -10000 (Min) or 10%
  Future<void> recordDeceptiveOrgPenalty(String userId) async {
    final penalty = await _calculateProportionalPenalty(userId, 0.10, 10000);
    await _repository.deductPoints(
      userId,
      penalty,
      'deceptive_org_submission_penalty',
    );
    await _trustService.updateTrustForUser(userId);
  }

  // Unresponsive Liaison: -100
  Future<void> recordUnresponsiveLiaisonPenalty(String userId) async {
    await _repository.deductPoints(
      userId,
      100,
      'unresponsive_liaison_penalty',
    );
    await _trustService.updateTrustForUser(userId);
  }

  // Passthrough methods
  Future<String> generateReferralCode(String userId, String firstName, String countryCode) => 
      _repository.generateReferralCode(userId, firstName, countryCode);
      
  Future<String?> getReferralCode(String userId) => _repository.getReferralCode(userId);
  
  Future<void> transferPoints({required String fromUserId, required String toUserId, required int amount}) =>
      _repository.transferPoints(fromUserId: fromUserId, toUserId: toUserId, amount: amount);

  Future<void> syncTreasuryBalances() => _repository.syncTreasuryBalances();

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
}
