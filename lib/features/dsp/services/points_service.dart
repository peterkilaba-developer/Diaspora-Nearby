import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
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
  static const Set<int> _allowedAmounts = {10, 100, 1000, 10000};

  void _validateAmount(int amount, String action) {
    if (!_allowedAmounts.contains(amount)) {
      // No-log warning
    }
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

  UserPoints? _safeGetCachedPoints(String userId) {
    try {
      return _repository.getCachedUserPoints(userId);
    } catch (_) {
      return null;
    }
  }

  void _safeCachePoints(String userId, UserPoints points) {
    try {
      _repository.cacheUserPoints(userId, points);
    } catch (_) {}
  }

  /// Centralized DSP awarder that handles community tribute.
  /// Optimistically updates in-memory PointsRepository cache on frame 0
  /// and runs server-side award without redundant sequential pre-flight reads.
  Future<void> _addPoints(
    String userId,
    int points,
    String action, {
    Map<String, dynamic>? metadata,
    bool skipTreasury = false,
  }) async {
    bool isCurrentUser = true;
    try {
      final currentUid = FirebaseAuth.instance.currentUser?.uid;
      if (currentUid != null) {
        isCurrentUser = currentUid == userId;
      }
    } catch (_) {
      isCurrentUser = true;
    }

    // Optimistic local cache update in 0ms
    final cachedPoints = _safeGetCachedPoints(userId);
    if (cachedPoints != null) {
      final updatedEarnings = Map<String, int>.from(
        cachedPoints.lifetimeEarnings,
      );
      updatedEarnings[action] = (updatedEarnings[action] ?? 0) + points;
      _safeCachePoints(
        userId,
        cachedPoints.copyWith(
          totalPoints: cachedPoints.totalPoints + points,
          availablePoints: cachedPoints.availablePoints + points,
          lastUpdated: DateTime.now(),
          lifetimeEarnings: updatedEarnings,
        ),
      );
    }

    _validateAmount(points, action);

    final futures = <Future<void>>[
      _repository.addPoints(
        userId,
        points,
        action,
        metadata: metadata,
        skipTreasury: skipTreasury,
      ),
    ];

    if (!skipTreasury && isCurrentUser && cachedPoints != null) {
      futures.add(_checkAndResetDaily(userId, cachedPoints));
    }

    await Future.wait(futures);
  }

  // [DEPRECATED v8] Block penalty → -10 PCT / 10 blocks (in TrustService)
  Future<void> trackBlockPenalty(String userId, int newBlocksCount) async {
    debugPrint('DSP: Block penalty deprecated — PCT handled in TrustService');
    await _trustService.updateTrustForUser(userId);
  }

  // [DEPRECATED v8] Flag penalty → -10 PCT / 10 flags (in TrustService)
  Future<void> trackFlagPenalty(String userId, int newFlagCount) async {
    debugPrint('DSP: Flag penalty deprecated — PCT handled in TrustService');
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

  // Evaluates 7 Proof of Humanity milestones & auto-credits 7,000 $DIASPORA distribution
  Future<Map<String, dynamic>> evaluateWelcomeBonus() async {
    return await _repository.evaluateWelcomeBonus();
  }

  // [RESTORED] Daily Share awards 100 DSP
  Future<void> trackDailyShare(String userId, bool isIncoming) async {
    await _addPoints(userId, 100, 'daily_share');
  }

  // [RESTORED] Message sending awards 10 DSP.
  Future<void> trackMessageSent(String userId, {String? receiverId}) async {
    await Future.wait([
      _addPoints(userId, 10, 'message_sent'),
      if (receiverId != null) _addPoints(receiverId, 10, 'message_received'),
    ]);
  }

  // [RESTORED] Community messages award 100 DSP.
  Future<void> trackCommunityMessage(String userId, String communityId) async {
    await _addPoints(
      userId,
      100,
      'community_message',
      metadata: {'communityId': communityId},
    );
  }

  // [RESTORED] New DM awards 100 DSP.
  Future<void> trackNewDM(String userId, String targetUserId) async {
    await Future.wait([
      _addPoints(
        userId,
        100,
        'new_dm_conversation',
        metadata: {'targetUserId': targetUserId},
      ),
      _addPoints(
        targetUserId,
        100,
        'new_dm_received',
        metadata: {'starterUserId': userId},
      ),
    ]);
  }

  // [UPDATED v9] Verifier Reward: 1,000 DSP (10x scale)
  Future<void> trackVerifierReward(
    String userId, {
    String? verifiedUserId,
  }) async {
    await Future.wait([
      _addPoints(userId, 1000, 'verifier_reward'),
      if (verifiedUserId != null)
        _addPoints(verifiedUserId, 1000, 'verified_by_peer'),
      _repository.incrementVerifiedCount(userId),
    ]);

    await _trustService.updateTrustForUser(userId);
  }

  // [UPDATED v9] Vouch Consensus Vote: +100 (agree) or -100 (disagree) to voucher (10x scale).
  Future<void> trackVouchConsensusVote({
    required String voucherId,
    required bool isAgree,
  }) async {
    try {
      if (isAgree) {
        await _addPoints(voucherId, 100, 'vouch_consensus_agree');
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

  // [RESTORED] External shares award 100 DSP.
  Future<bool> trackExternalShare(String userId, String contentType) async {
    return false;
  }

  // [RESTORED] Incoming shares award 10 DSP.
  Future<void> trackIncomingShare(
    String userId,
    String contentType, {
    String? sharerId,
  }) async {}

  // Process referral: Returns referrerId for relationship connection (No immediate reward)
  Future<String?> processReferral(String code, String newUserId) async {
    final normalizedCode = code.trim().toUpperCase();
    debugPrint(
      'DSP: Processing referral code: $normalizedCode for new user: $newUserId',
    );

    try {
      final response = await FirebaseFunctions.instance
          .httpsCallable('redeemReferralCode')
          .call<Map<String, dynamic>>({'code': normalizedCode});
      final referrerId = response.data['referrerId'] as String?;
      if (referrerId == null || referrerId.isEmpty) return null;
      debugPrint('DSP: Referral redeemed securely. Referrer: $referrerId');
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
    debugPrint(
      'DSP: trackExplorationReward is deprecated and no longer awards DSP',
    );
    return false;
  }

  // [DEPRECATED v7] Feedback rewards removed. Not in 10-action system.
  Future<bool> trackFeedbackReward(String userId) async {
    debugPrint(
      'DSP: trackFeedbackReward is deprecated and no longer awards DSP',
    );
    return false;
  }

  // Relationship Rewards:
  // Accepted: Both +1000
  // Rejected: Sender -1000, Receiver +1000
  Future<void> trackRelationshipReward({
    required String senderId,
    required String receiverId,
    required String status,
    String? relationshipType,
  }) async {
    try {
      if (status == 'accepted') {
        final futures = <Future<void>>[];

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
            String? currentUid;
            try {
              currentUid = FirebaseAuth.instance.currentUser?.uid;
            } catch (_) {}
            if (currentUid == null) {
              futures.add(_repository.incrementFamilyConnectionCount(senderId));
              futures.add(
                _repository.incrementFamilyConnectionCount(receiverId),
              );
            } else if (currentUid == senderId) {
              futures.add(_repository.incrementFamilyConnectionCount(senderId));
            } else if (currentUid == receiverId) {
              futures.add(
                _repository.incrementFamilyConnectionCount(receiverId),
              );
            }
          }
        }

        if (futures.isNotEmpty) {
          await Future.wait(futures);
        }

        await Future.wait([
          _trustService.updateTrustForUser(senderId),
          _trustService.updateTrustForUser(receiverId),
        ]);
      } else if (status == 'rejected') {
        debugPrint('DSP: Relationship rejection penalty removed (v8)');
      }
    } catch (e) {
      debugPrint('Error tracking relationship reward: $e');
    }
  }

  // [DEPRECATED v8] Spam report DSP penalty removed → PCT milestone in TrustService
  Future<void> reportSpam(String senderId) async {
    debugPrint(
      'DSP: Spam report penalty deprecated — PCT handled in TrustService',
    );
    await _trustService.updateTrustForUser(senderId);
  }

  // [DEPRECATED v8] Fraud penalty removed (no way to verify)
  Future<void> recordFraudPenalty(String userId) async {
    debugPrint('DSP: Fraud penalty removed (v8)');
  }

  Future<void> trackProfileCompletion(String userId) async {
    try {
      await Future.wait([
        FirebaseFunctions.instance
            .httpsCallable('evaluateProfileMilestone')
            .call<Map<String, dynamic>>({'userId': userId}),
        _trustService.updateTrustForUser(userId),
      ]);
    } catch (e) {
      debugPrint('DSP: evaluateProfileMilestone fallback: $e');
      await trackCompleteProfile(userId);
    }
  }

  Future<void> trackCompleteProfile(String userId) async {
    final points =
        _safeGetCachedPoints(userId) ??
        await _repository.getUserPoints(userId);
    final alreadyEarned =
        (points?.lifetimeEarnings['profile_completion'] ?? 0) >= 10000;
    if (points != null &&
        !alreadyEarned &&
        !points.completedExplorationActions.contains(
          'milestone_10_profile_fields',
        )) {
      await Future.wait([
        awardManualPoints(userId, 10000, 'profile_completion'),
        _repository.markExplorationActionCompleted(
          userId,
          'milestone_10_profile_fields',
        ),
        _repository.markExplorationActionCompleted(userId, 'complete_profile'),
      ]);
      await _trustService.updateTrustForUser(userId);
    }
  }

  // [DEPRECATED v8] Vouching bad actor penalty removed (handled by staking)
  Future<void> recordVouchingBadActorPenalty(String userId) async {
    debugPrint(
      'DSP: Vouching bad actor penalty removed — handled by staking (v8)',
    );
  }

  // --- [NEW] Travelers & Diaspora Rewards ---

  // [DEPRECATED] Verified Check-in removed from PSA. No longer awards DSP.
  Future<void> trackVerifiedCheckIn(String userId) async {
    debugPrint(
      'DSP: trackVerifiedCheckIn is deprecated and no longer awards DSP',
    );
  }

  // [RESTORED] Daily check-in awards 10 DSP.
  Future<void> trackDailyCheckIn(String userId) async {
    final cached = _safeGetCachedPoints(userId);
    if (cached == null) {
      final pointsData = await _repository.getUserPoints(userId);
      if (pointsData == null) {
        await initializeUserPoints(userId);
      }
    }
    await FirebaseFunctions.instance.httpsCallable('recordDailyCheckIn').call();
  }

  // [NEW] Track Content Reaction
  Future<void> trackContentReaction(
    String userId,
    String targetId, {
    String? receiverId,
  }) async {
    await Future.wait([
      _addPoints(
        userId,
        10,
        'content_reaction',
        metadata: {'targetId': targetId},
      ),
      if (receiverId != null)
        _addPoints(
          receiverId,
          10,
          'reaction_received',
          metadata: {'targetId': targetId},
        ),
    ]);
  }

  // [NEW] Track Event Creation
  Future<void> trackEventCreation(String userId, String eventId) async {
    await _addPoints(
      userId,
      1000,
      'event_creation',
      metadata: {'eventId': eventId},
    );
  }

  // [NEW] Track Profile Update
  Future<void> trackProfileUpdate(String userId) async {
    await _addPoints(userId, 10, 'profile_update');
  }

  // [DEPRECATED v8] Chat ad DSP penalty removed → PCT milestone in TrustService
  Future<void> trackChatAdPenalty(String userId) async {
    debugPrint('DSP: Chat ad penalty deprecated — PCT handled in TrustService');
    await _trustService.updateTrustForUser(userId);
  }

  // [DEPRECATED] Local Knowledge removed from PSA. No longer awards DSP.
  Future<void> trackLocalKnowledgeHelper(
    String userId,
    String otherUserId,
  ) async {
    debugPrint(
      'DSP: trackLocalKnowledgeHelper is deprecated and no longer awards DSP',
    );
  }

  // [UPDATED] Host a Traveler: 1000 DSP + 100 DSP per night to both host and traveler.
  Future<void> trackHostATraveler(
    String userId,
    String guestUserId, {
    int nights = 1,
  }) async {
    try {
      final totalDsp = 1000 + (100 * nights);

      await Future.wait([
        _addPoints(
          userId,
          totalDsp,
          'host_traveler_host_reward',
          metadata: {'guestUserId': guestUserId, 'nights': nights},
        ),
        _addPoints(
          guestUserId,
          totalDsp,
          'host_traveler_guest_reward',
          metadata: {'hostUserId': userId, 'nights': nights},
          skipTreasury: true,
        ),
      ]);

      await Future.wait([
        _trustService.updateTrustForUser(userId),
        _trustService.updateTrustForUser(guestUserId),
      ]);
    } catch (e) {
      debugPrint('DSP: Error tracking host a traveler: $e');
    }
  }

  // [DEPRECATED v7] Travel booking no longer earns flat DSP.
  Future<void> trackTravelBooking(
    String userId,
    String bookingType, {
    String? bookingId,
    double? fiatAmount,
    String? countryCode,
  }) async {
    if (fiatAmount != null && fiatAmount > 0 && countryCode != null) {
      await trackEconomyTransaction(
        buyerUserId: userId,
        sellerUserId: userId,
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

  // [DEPRECATED] Emergency Contact removed from PSA. No longer awards DSP.
  Future<void> trackEmergencyContactHelp(String helperId) async {
    debugPrint(
      'DSP: trackEmergencyContactHelp is deprecated and no longer awards DSP',
    );
  }

  // [DEPRECATED] Emergency Help Fee removed from PSA.
  Future<bool> trackEmergencyHelpFee(String userId) async {
    debugPrint('DSP: trackEmergencyHelpFee is deprecated');
    return true;
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
    await _repository.incrementQrConnectionCount(userId);
  }

  // --- [DEPRECATED v8] All DSP penalties removed — PCT milestones in TrustService ---

  Future<void> recordEventNoShowPenalty(String userId) async {
    debugPrint('DSP: Event no-show penalty deprecated — PCT in TrustService');
    await _trustService.updateTrustForUser(userId);
  }

  Future<void> recordMisinformationPenalty(String userId) async {
    debugPrint('DSP: Misinformation penalty removed (v8)');
  }

  Future<void> recordDeceptiveOrgPenalty(String userId) async {
    debugPrint('DSP: Deceptive org penalty removed (v8)');
  }

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

  /// Transfers liquid on-chain assets ($DIASPORA tokens) between users via Smart Wallets.
  Future<void> transferAsset({
    required String fromUserId,
    required String toUserId,
    required int amount,
    required String assetType,
  }) async {
    if (assetType == 'points') {
      throw ArgumentError(
        'DSP points cannot be transferred between users to preserve Proof of Community Trust (PCT) integrity.',
      );
    }
    await _repository.transferAsset(
      fromUserId: fromUserId,
      toUserId: toUserId,
      amount: amount,
      assetType: assetType,
    );
  }

  Future<void> syncTreasuryBalances() => _repository.syncTreasuryBalances();

  /// Records a completed real-economy transaction as fiat GDP.
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
  Future<void> trackEconomyTransaction({
    required String buyerUserId,
    required String sellerUserId,
    required double fiatAmount,
    required String countryCode,
    String? transactionType,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      final usdAmount = CurrencyHelper.toUsd(fiatAmount, countryCode);
      if (usdAmount <= 0) return;

      final dspAmount = usdAmount.round();
      if (dspAmount <= 0) return;

      await Future.wait([
        _addPoints(
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
        ),
        if (sellerUserId != buyerUserId)
          _addPoints(
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
          ),
        recordFiatGdp(
          amount: fiatAmount,
          countryCode: countryCode,
          activityType: transactionType ?? 'economy_transaction',
          metadata: {
            'buyerUserId': buyerUserId,
            'sellerUserId': sellerUserId,
            ...?metadata,
          },
        ),
      ]);
    } catch (e) {
      debugPrint('DSP: Error tracking economy transaction: $e');
    }
  }

  // --- [UPDATED v9] Community Event Attendance (QR Check-in, 10x scale) ---
  Future<void> trackEventAttendance({
    required String attendeeUserId,
    required String hostUserId,
    required String eventId,
  }) async {
    try {
      await Future.wait([
        _addPoints(
          attendeeUserId,
          1000,
          'event_attendance',
          metadata: {'eventId': eventId, 'hostUserId': hostUserId},
        ),
        if (hostUserId != attendeeUserId)
          _addPoints(
            hostUserId,
            1000,
            'event_hosting_per_attendee',
            metadata: {'eventId': eventId, 'attendeeUserId': attendeeUserId},
            skipTreasury: true,
          ),
      ]);

      await Future.wait([
        _trustService.updateTrustForUser(attendeeUserId),
        if (hostUserId != attendeeUserId)
          _trustService.updateTrustForUser(hostUserId),
      ]);
    } catch (e) {
      debugPrint('DSP: Error tracking event attendance: $e');
    }
  }

  /// Community Pillar / Peer Visit Reward:
  Future<bool> trackPeerVisitReward({
    required String hostUserId,
    required String visitorUserId,
    String? locationAddress,
  }) async {
    try {
      if (hostUserId == visitorUserId) return false;

      final lastVisitTime = await _repository.getLastPeerVisitTime(
        hostUserId: hostUserId,
        visitorUserId: visitorUserId,
      );

      if (lastVisitTime != null) {
        final daysSinceLastVisit = DateTime.now()
            .difference(lastVisitTime)
            .inDays;
        if (daysSinceLastVisit < 7) {
          debugPrint(
            '⚠️ [PEER VISIT] Rate limit active: Pair ($hostUserId, $visitorUserId) rewarded $daysSinceLastVisit days ago.',
          );
          return false;
        }
      }

      await Future.wait([
        _repository.recordPeerVisit(
          hostUserId: hostUserId,
          visitorUserId: visitorUserId,
          locationAddress: locationAddress,
        ),
        _addPoints(
          hostUserId,
          1000,
          'peer_visit_host_reward',
          metadata: {
            'visitorUserId': visitorUserId,
            'locationAddress': locationAddress,
          },
        ),
        _addPoints(
          visitorUserId,
          1000,
          'peer_visit_visitor_reward',
          metadata: {
            'hostUserId': hostUserId,
            'locationAddress': locationAddress,
          },
          skipTreasury: true,
        ),
      ]);

      await Future.wait([
        _trustService.updateTrustForUser(hostUserId),
        _trustService.updateTrustForUser(visitorUserId),
      ]);

      debugPrint(
        '🤝 [PEER VISIT] Awarded 1,000 DSP each to Host ($hostUserId) & Visitor ($visitorUserId)',
      );
      return true;
    } catch (e) {
      debugPrint('DSP: Error tracking peer visit reward: $e');
      return false;
    }
  }

  Future<void> trackHostLocationMove(String userId) async {
    final userPoints =
        _safeGetCachedPoints(userId) ??
        await _repository.getUserPoints(userId);
    if (userPoints == null) return;
    if ((userPoints.lifetimeEarnings['host_location_moved'] ?? 0) > 0) return;
    await _repository.addPoints(userId, 1000, 'host_location_moved');
  }

  Future<void> trackAlsoLivedInAdded(String userId) async {
    final userPoints =
        _safeGetCachedPoints(userId) ??
        await _repository.getUserPoints(userId);
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

  Future<bool> trackConnectionFee({
    required String userId,
    required String relationshipType,
  }) async {
    debugPrint('DSP: Connection fee removed — all connections are free');
    return true;
  }
}
