import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';

import 'package:diaspora_nearby/features/chat/repository/report_repository.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:diaspora_nearby/features/trust/models/trust_data.dart';
import 'package:diaspora_nearby/features/trust/repository/trust_repository.dart';
import 'package:diaspora_nearby/features/profile/models/profile_data.dart';
import 'package:diaspora_nearby/features/dsp/models/user_points.dart';
import 'package:diaspora_nearby/features/dsp/services/points_service.dart';
import 'package:diaspora_nearby/features/dsp/services/epoch_service.dart';
// Note: We'll inject Repositories instead of circular Services if possible, or use Ref to read current state.

import 'package:diaspora_nearby/features/profile/repository/profile_repository.dart';
import 'package:diaspora_nearby/features/dsp/repository/points_repository.dart';
import 'package:diaspora_nearby/features/profile/repository/relationship_repository.dart';
import 'package:diaspora_nearby/features/chat/repository/chat_repository.dart';

import 'package:diaspora_nearby/core/utils/location_utils.dart';
import 'package:diaspora_nearby/features/dsp/services/emergency_fund_service.dart';

final trustServiceProvider = Provider<TrustService>((ref) {
  return TrustService(ref.read(trustRepositoryProvider), ref);
});

enum HTSActivityType {
  eventHosting, // Gain
  eventNoShow, // Loss
  fraudReporting, // Gain (when your report is verified)
  rejectedVouch, // Loss
  referral, // Gain
  flaggedMessage, // Loss
  verifiedSolution, // Gain
  fraudulentVerification, // Loss
  vote, // Gain
  missedVote, // Loss
  blockedBy, // Loss
  reportedFraud, // Loss (major)
  physicalPresence, // Gain [NEW]
}

final userTrustProvider = StreamProvider.family<TrustData?, String>((
  ref,
  userId,
) {
  return ref.read(trustRepositoryProvider).streamTrustData(userId);
});

final flaggedFieldsProvider = FutureProvider.family<List<String>, String>((
  ref,
  userId,
) {
  return ref.read(trustServiceProvider).getFlaggedFields(userId);
});

class IncompleteProfileException implements Exception {
  final List<String> missingFields;
  final bool isOwnProfile;
  final String message;

  IncompleteProfileException({
    required this.missingFields,
    required this.isOwnProfile,
    required this.message,
  });

  @override
  String toString() =>
      'IncompleteProfileException: $message (Missing: ${missingFields.join(', ')})';
}

class AlreadyConnectedException implements Exception {
  final String message;
  final String otherUid;

  AlreadyConnectedException({required this.message, required this.otherUid});

  @override
  String toString() => 'AlreadyConnectedException: $message';
}

class TrustService {
  final TrustRepository _repository;
  final Ref _ref;

  TrustService(this._repository, this._ref);

  /// [NEW] Central entry point for recording HTS activities
  Future<void> recordActivity(String userId, HTSActivityType type) async {
    // Trust counters and eligibility are server-owned. Legacy callers still
    // invoke this hook after UI actions, but a client assertion is not proof
    // that an economic or trust event occurred. Relevant backend workflows
    // write their verified metrics atomically; here we only refresh the view.
    debugPrint('Trust activity refresh requested: $type');
    _ref.invalidate(userTrustProvider(userId));
  }

  /// [NEW] Record a solution verification (entry point for Chat UI)
  Future<bool> markAsVerifiedSolution({
    required String reporterId,
    required String messageId,
    required String senderId,
    required String chatId,
  }) async {
    if (reporterId == senderId) return false;
    try {
      final response = await FirebaseFunctions.instance
          .httpsCallable('verifyChatSolution')
          .call<Map<String, dynamic>>({
            'chatId': chatId,
            'messageId': messageId,
          });
      return response.data['alreadyVerified'] != true;
    } catch (e) {
      debugPrint('Error marking solution: $e');
      return false;
    }
  }

  Future<TrustData?> getTrustData(String uid) => _repository.getTrustData(uid);

  /// Calculate and return the trust score for [userId] (or current logged-in user if null).
  Future<double> calculateTrustScore([String? userId]) async {
    final targetUid = userId ?? FirebaseAuth.instance.currentUser?.uid;
    if (targetUid == null || targetUid.isEmpty) return 0.0;

    await updateTrustForUser(targetUid);
    final trustData = await getTrustData(targetUid);
    return trustData?.trustScore ?? 0.0;
  }

  /// Helper to fetch data and recalculate
  Future<void> updateTrustForUser(String userId) async {
    // Recalculation used to fan out across relationships, ratings, chats,
    // verifications, and communities before attempting writes denied by the
    // production rules. Refresh the server-authored projection instead.
    if (FirebaseAuth.instance.currentUser?.uid == userId) {
      try {
        await FirebaseFunctions.instance
            .httpsCallable('evaluateProfileMilestone')
            .call<Map<String, dynamic>>({'userId': userId});
      } catch (e) {
        debugPrint('evaluateProfileMilestone sync note: $e');
      }
    }
    _ref.invalidate(userTrustProvider(userId));
    _ref.invalidate(userPointsProvider(userId));
  }

  /// Main Calculation Engine
  /// This should be called whenever a significant trust signal changes (Profile update, Daily streak, New Vouch)
  Future<void> recalculateTrustScore({
    required String userId,
    required ProfileData profile,
    required UserPoints points,
  }) async {
    // 1. Fetch Existing Data
    final trustDataOld = await _repository.getTrustData(userId);
    final relationships = await _ref
        .read(relationshipRepositoryProvider)
        .getRelationships(userId)
        .first;
    final ratingDetails = await _repository.getDetailedTrustRatingsForUser(
      userId,
    );
    final allVerifications = await _repository.getAllVerificationsForUser(
      userId,
    );
    final pointsService = _ref.read(pointsServiceProvider);

    // --- Milestone & Governance Tracking ---
    const familyTypes = {
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
      'relative',
    };

    final familyIds = relationships
        .where(
          (r) =>
              r.status == 'active' &&
              familyTypes.contains(r.type.toLowerCase()),
        )
        .map((r) => r.id)
        .toSet();

    // [UPDATED] Friend connections: all non-family active relationships,
    // EXCLUDING anyone already counted as family (mutually exclusive).
    final friendIds = relationships
        .where(
          (r) =>
              r.status == 'active' &&
              !familyTypes.contains(r.type.toLowerCase()) &&
              !familyIds.contains(r.id),
        )
        .map((r) => r.id)
        .toSet();

    debugPrint(
      '🎯 [Trust] Relationships for $userId: total=${relationships.length}, '
      'active=${relationships.where((r) => r.status == "active").length}, '
      'family=${familyIds.length}, friends=${friendIds.length}',
    );
    for (final r in relationships) {
      debugPrint('   → rel: id=${r.id}, type=${r.type}, status=${r.status}');
    }

    // [UPDATED] Circle of Trust (Family + Friends)
    final circleOfTrustIds = familyIds.union(friendIds);

    // QR is independent — QR connections can also be family, friend,
    // vouch, or verify. No exclusion applied.
    final allQrIds = await _repository.getQrExchangeUserIds(userId);
    final uniqueQrIds = allQrIds.toSet();
    debugPrint(
      '🎯 [Trust] QR IDs for $userId: allQrIds=$allQrIds, unique=${uniqueQrIds.length}',
    );

    // [UPDATED] Vouch / Staking: STRICTLY EXCLUDE Circle of Trust (Family AND Friends)
    // to prevent collusion in the dynamic prediction market.
    final uniqueVouchIds = ratingDetails
        .where((r) => (r['score'] as num) > 90)
        .map((r) => r['fromUserId'] as String)
        .where((id) => !circleOfTrustIds.contains(id))
        .toSet();

    final uniqueVerificationIds = allVerifications
        .map((v) => v['fromUserId'] as String)
        .where((id) => !uniqueVouchIds.contains(id))
        .toSet();

    // Counts for Milestones
    final uniqueFamilyCount = familyIds.length;
    final uniqueFriendCount = friendIds.length;
    final uniqueQrCount = uniqueQrIds.length;
    final uniqueVouchCount = uniqueVouchIds.length;
    final uniqueVerifiedCount = uniqueVerificationIds.length;
    final uniqueTrustIds = uniqueVouchIds.union(uniqueVerificationIds);
    final isProfileComplete = profile.isComplete;

    debugPrint(
      '🎯 [Trust] Milestone Counts for $userId: '
      'Family=$uniqueFamilyCount, Friend=$uniqueFriendCount, '
      'QR=$uniqueQrCount, Vouch=$uniqueVouchCount, '
      'Verified=$uniqueVerifiedCount, '
      'ProfileComplete=$isProfileComplete',
    );

    // --- 7 Proof of Humanity (PoH) Milestone Awards (10,000 DSP Lump Sum + 10 PCT Each) ---
    final milestones = List<String>.from(
      trustDataOld?.awardedQualificationMilestones ?? [],
    );

    // Create a writable copy of the ledger for tracking real-time DSP and PCT levels
    final ledger = Map<String, int>.from(
      trustDataOld?.awardedHtsTracking ?? {},
    );

    double milestonePoCT = 0;

    Future<void> checkAndAward(String milestone, int count) async {
      int previouslyAwardedDspCount = ledger['${milestone}_dsp_count'] ?? 0;

      debugPrint(
        '🎯 [Trust] checkAndAward: milestone=$milestone, '
        'count=$count, previouslyAwarded=$previouslyAwardedDspCount',
      );

      final threshold = milestone == 'Profile'
          ? profile.totalMilestoneFields
          : 10;

      if (milestone == 'Profile') {
        // 1. Profile Milestone: Pays 10,000 DSP only when ALL fields complete
        if (count >= threshold && previouslyAwardedDspCount < threshold) {
          pointsService.awardManualPoints(userId, 10000, 'profile_completion');
          ledger['${milestone}_dsp_count'] = threshold;

          if (!milestones.contains(milestone)) {
            milestones.add(milestone);
            await _ref
                .read(pointsRepositoryProvider)
                .markExplorationActionCompleted(
                  userId,
                  'milestone_10_profile_fields',
                );
            await _ref
                .read(pointsRepositoryProvider)
                .markExplorationActionCompleted(userId, 'complete_profile');
          }
        }
      } else if (milestone == 'QR') {
        // 2. Identity QR: 10,000 DSP lump sum at 10 scans; +1,000 DSP per unique scan for scan 11+
        if (count >= 10 && previouslyAwardedDspCount < 10) {
          pointsService.awardManualPoints(
            userId,
            10000,
            'identity_qr_exchange',
          );
          ledger['${milestone}_dsp_count'] = 10;
          previouslyAwardedDspCount = 10;

          if (!milestones.contains(milestone)) {
            milestones.add(milestone);
            await _ref
                .read(pointsRepositoryProvider)
                .markExplorationActionCompleted(userId, 'milestone_10_qr');
          }
        }
        if (count > 10 && count > previouslyAwardedDspCount) {
          final extraScans =
              count -
              (previouslyAwardedDspCount < 10 ? 10 : previouslyAwardedDspCount);
          if (extraScans > 0) {
            pointsService.awardManualPoints(
              userId,
              1000 * extraScans,
              'identity_qr_exchange_continuous',
            );
            ledger['${milestone}_dsp_count'] = count;
          }
        }
      } else {
        // 3. Family, Friend, Verified: Lump sum 10,000 DSP only when reaching 10 (0 incremental)
        if (count >= 10 && previouslyAwardedDspCount < 10) {
          String dspAction = 'Activity Reward: $milestone';
          if (milestone == 'Verified') dspAction = 'verified_by_peer';
          if (milestone == 'Family') dspAction = 'family_connection';
          if (milestone == 'Friend') dspAction = 'friend_connection';

          debugPrint('🎯 [Trust] AWARDING $userId: 10000 DSP for $dspAction');

          pointsService.awardManualPoints(userId, 10000, dspAction);

          ledger['${milestone}_dsp_count'] = 10;

          if (!milestones.contains(milestone)) {
            milestones.add(milestone);
            String? actionId;
            switch (milestone) {
              case 'Family':
                actionId = 'milestone_10_family';
                break;
              case 'Verified':
                actionId = 'milestone_10_verified';
                break;
              case 'Friend':
                actionId = 'milestone_10_friend';
                break;
            }
            if (actionId != null) {
              await _ref
                  .read(pointsRepositoryProvider)
                  .markExplorationActionCompleted(userId, actionId);
            }
          }
        }
      }

      // PCT: One-time +10 PCT award when count reaches required threshold.
      if (count >= threshold) {
        milestonePoCT += 10;
      }
    }

    // Check 5 count-based PoH milestones
    await checkAndAward('Family', uniqueFamilyCount);
    await checkAndAward('Friend', uniqueFriendCount);
    await checkAndAward('QR', uniqueQrCount);
    await checkAndAward('Verified', uniqueVerifiedCount);
    await checkAndAward('Profile', profile.completedMilestoneFieldCount);

    // --- Programmatic HTS Engine (The Ledger) ---
    // Continuous dynamic PCT earners (excluding Circle of Trust):
    // 1. Trust Slider: +1 PCT per 10 unique full-trust voters (>90)
    // 2. Economic Transactions: +1 PCT per 10 completed unique txns
    // Penalties: -10 PCT per 10 occurrences

    int htsPoctDelta = 0;

    // GAINS/LOSSES: Trust Slider Net Vouches (+1 PCT per 10 net full-trust voters, non-Circle of Trust)
    final fullTrustVoterIds = ratingDetails
        .where((r) => (r['score'] as num) > 90)
        .map((r) => r['fromUserId'] as String)
        .where((id) => !circleOfTrustIds.contains(id))
        .toSet()
        .toList();
    final fullTrustVouchCount = fullTrustVoterIds.length;

    final noTrustVoterIds = ratingDetails
        .where((r) => (r['score'] as num) >= 1 && (r['score'] as num) <= 10)
        .map((r) => r['fromUserId'] as String)
        .where((id) => !circleOfTrustIds.contains(id))
        .toSet()
        .toList();
    final noTrustVouchCount = noTrustVoterIds.length;

    final netVouches = fullTrustVouchCount - noTrustVouchCount;
    htsPoctDelta += netVouches ~/ 10;

    // GAINS: Economic Transactions (+1 PCT per 10 completed unique transactions)
    final economicTxCount = await _getCompletedEconomicTransactionCount(userId);
    htsPoctDelta += economicTxCount ~/ 10;

    // LOSSES: -10 PCT for every 10 occurrences
    htsPoctDelta -= ((trustDataOld?.flaggedMessagesCount ?? 0) ~/ 10) * 10;
    htsPoctDelta -= (profile.blockedByCount ?? 0) ~/ 10;
    htsPoctDelta -= (trustDataOld?.reportedFraudCount ?? 0) ~/ 10;
    htsPoctDelta -= (trustDataOld?.fakeVerificationsCount ?? 0) ~/ 10;
    htsPoctDelta -= (trustDataOld?.eventNoShowCount ?? 0) ~/ 10;
    htsPoctDelta -= (trustDataOld?.rejectedFamilyConnectionsCount ?? 0) ~/ 10;

    // --- Pillar 1: Location Transparency (10,000 DSP + 10 PCT) ---
    // Awarded when location transparency is active. If toggled off:
    // +10 PCT is permanently forfeited AND awarded 10,000 DSP is burned!
    double cityVisibilityPoCT = 0;
    final cityForfeited = profile.cityVisibilityForfeited == true;
    final hasCurrentLocation = profile.currentLocation != null;
    final visibilityOn = profile.showCurrentLocationName != false;
    final locationMilestoneAwarded =
        ledger['LocationTransparency_dsp_awarded'] == 1;

    if (!cityForfeited && hasCurrentLocation && visibilityOn) {
      cityVisibilityPoCT = 10;
      if (!locationMilestoneAwarded) {
        pointsService.awardManualPoints(userId, 10000, 'location_transparency');
        ledger['LocationTransparency_dsp_awarded'] = 1;
        if (!milestones.contains('LocationTransparency')) {
          milestones.add('LocationTransparency');
          await _ref
              .read(pointsRepositoryProvider)
              .markExplorationActionCompleted(userId, 'location_transparency');
        }
      }
    } else if (locationMilestoneAwarded && (cityForfeited || !visibilityOn)) {
      // User toggled off location: burn 10,000 DSP & permanently forfeit
      pointsService.deductPoints(
        userId: userId,
        amount: 10000,
        reason: 'location_transparency_burned',
      );
      ledger['LocationTransparency_dsp_awarded'] = -1; // marked as burned
    }

    // --- Community Participation: Event Attendance (+10 PCT at 10 check-ins) ---
    double eventAttendancePoCT = 0;
    final checkInCount = trustDataOld?.verifiedCheckInCount ?? 0;
    if (checkInCount >= 10) {
      eventAttendancePoCT = 10;
    }

    // --- Pillar 4: Ubuntu Emergency Fund Contribution (10,000 DSP + 10 PCT) ---
    double emergencyFundPoCT = 0;
    final hasStaked = await _ref
        .read(emergencyFundServiceProvider)
        .hasStaked(userId);
    final emergencyFundAwarded = ledger['EmergencyFund_dsp_awarded'] == 1;
    if (hasStaked) {
      emergencyFundPoCT = 10;
      if (!emergencyFundAwarded) {
        pointsService.awardManualPoints(
          userId,
          10000,
          'emergency_fund_contribution',
        );
        ledger['EmergencyFund_dsp_awarded'] = 1;
        if (!milestones.contains('EmergencyFund')) {
          milestones.add('EmergencyFund');
          await _ref
              .read(pointsRepositoryProvider)
              .markExplorationActionCompleted(userId, 'economy_emergency_fund');
        }
      }
    }

    // --- Seniority Milestone ---
    double seniorityScore = 0;
    int daysActive = 0;
    if (profile.createdAt != null) {
      daysActive = DateTime.now().difference(profile.createdAt!).inDays;
      seniorityScore = (daysActive / 100).floorToDouble();
    }

    // --- Group Chat Admin Check (for Council Eligibility) ---
    final isAdminOfLargeGroup = await _ref
        .read(chatRepositoryProvider)
        .isAdminOfLargeGroupChat(userId);

    // --- Final Score Calculation ---
    // PoH Base (70: 5 count milestones + Location + Ubuntu Emergency Fund)
    // + Participation (20) + Ongoing HTS delta.
    double finalScore =
        milestonePoCT +
        cityVisibilityPoCT +
        emergencyFundPoCT +
        eventAttendancePoCT +
        htsPoctDelta +
        seniorityScore;

    // Ensure 0-100 (PCT is usually 1-100, clamped for UI)
    if (finalScore > 100) finalScore = 100;
    if (finalScore < 0) finalScore = 0;

    // --- Status & Verification ---
    TrustLevel level = TrustLevelExtension.fromScore(finalScore);

    bool isProfileCompleteMilestone =
        profile.completedMilestoneFieldCount >= profile.totalMilestoneFields;
    bool isVerified =
        finalScore >= 80 ||
        (trustDataOld?.isVerified ?? false) ||
        isProfileCompleteMilestone;

    // --- Proof of Humanity (PoH) Genesis On-Chain Token Distribution (7,000 $DIASPORA) ---
    // Members qualify by completing the 6 non-fund milestones (Profile, 10 Family, 10 Friends,
    // 10 QR exchanges, 10 Peer verifications, and Location transparency).
    // Contribution to Ubuntu Emergency Fund is the 7th milestone (voluntary +10 PCT once members have tokens),
    // and is excluded from the required completion gate to avoid token-requirement deadlock.
    final isPoHComplete =
        uniqueFamilyCount >= 10 &&
        uniqueFriendCount >= 10 &&
        uniqueQrCount >= 10 &&
        uniqueVerificationIds.length >= 10 &&
        cityVisibilityPoCT >= 10 &&
        isProfileComplete;

    bool hasReceivedPohTokenDistribution =
        trustDataOld?.hasReceivedPohTokenDistribution ??
        (ledger['PohTokenDistribution_dsp_awarded'] == 1);

    if (isPoHComplete && !hasReceivedPohTokenDistribution) {
      // 7,000 DSP Genesis conversion to real on-chain $DIASPORA on Base blockchain
      pointsService.deductPoints(
        userId: userId,
        amount: 7000,
        reason: 'poh_genesis_token_distribution',
      );
      ledger['PohTokenDistribution_dsp_awarded'] = 1;
      hasReceivedPohTokenDistribution = true;
      debugPrint(
        '🌟 [PoH] User $userId completed all 7 PoH milestones! 7,000 DSP converted to on-chain \$DIASPORA on Base blockchain.',
      );
    }

    // --- Save & Sync ---
    final newTrustData = TrustData(
      uid: userId,
      trustScore: finalScore,
      level: level,
      isVerified: isVerified,
      identityScore:
          (isProfileComplete ? 5.0 : 0.0) + (uniqueQrCount > 0 ? 15.0 : 0.0),
      activityScore: (points.currentStreak * 1.0).clamp(0, 20),
      vouchTrustScore: (uniqueVouchCount * 2.0).clamp(0, 20),
      vouchCount: uniqueVouchCount,
      lastUpdated: DateTime.now(),
      vouchedBy: uniqueVouchIds.toList(),
      fullTrustVoterIds: fullTrustVoterIds,
      noTrustVoterIds: noTrustVoterIds,
      reviewCount: ratingDetails.length,
      averageRating: ratingDetails.isEmpty
          ? 0.0
          : ratingDetails
                    .map((r) => (r['score'] as num).toDouble())
                    .reduce((a, b) => a + b) /
                ratingDetails.length,
      reportCount: profile.advertReportCount ?? 0,
      attendedEventsCount: trustDataOld?.attendedEventsCount ?? 0,
      joinedEventsCount: trustDataOld?.joinedEventsCount ?? 0,
      verifiedSolutionsCount: trustDataOld?.verifiedSolutionsCount ?? 0,
      identityQRExchange: uniqueQrCount > 0,
      verifiedCheckInCount: trustDataOld?.verifiedCheckInCount ?? 0,
      reliabilityScore: trustDataOld?.reliabilityScore ?? 0,
      helpfulnessScore: trustDataOld?.helpfulnessScore ?? 0,
      uniqueFamilyCount: uniqueFamilyCount,
      uniqueFriendCount: uniqueFriendCount,
      uniqueVouchCount: uniqueVouchIds.length,
      uniqueVerificationCount: uniqueVerificationIds.length,
      uniqueQrCount: uniqueQrCount,
      vouchedByCount: fullTrustVouchCount,
      verifiedByCount: allVerifications.length,
      genesisFamilyIds: familyIds.take(10).toList(),
      genesisFriendIds: friendIds.take(10).toList(),
      genesisQrIds: uniqueQrIds.take(10).toList(),
      genesisTrustIds: uniqueTrustIds.take(10).toList(),
      genesisVerificationIds: uniqueVerificationIds.take(10).toList(),
      genesisVouchIds: uniqueVouchIds.take(10).toList(),
      isCouncilEligible:
          (isPoHComplete && daysActive >= 100) &&
          isAdminOfLargeGroup &&
          finalScore >= 91,
      isDdiEligible: (isPoHComplete && daysActive >= 100) && finalScore >= 91,
      hasReceivedPohTokenDistribution: hasReceivedPohTokenDistribution,
      awardedQualificationMilestones: milestones,
      awardedHtsTracking: ledger,
      referralCount: trustDataOld?.referralCount ?? 0,
      blockedByCount: profile.blockedByCount ?? 0,
      // Preserve trust_data's incremented value — `incrementTrustMetric`
      // writes here, so reading from profile would clobber every increment.
      flaggedMessagesCount: trustDataOld?.flaggedMessagesCount ?? 0,
      reportedFraudCount: trustDataOld?.reportedFraudCount ?? 0,
      fakeVerificationsCount: trustDataOld?.fakeVerificationsCount ?? 0,
      eventNoShowCount: trustDataOld?.eventNoShowCount ?? 0,
      rejectedFamilyConnectionsCount:
          trustDataOld?.rejectedFamilyConnectionsCount ?? 0,
    );

    await _repository.saveTrustData(newTrustData);

    // Sync to UserPoints & community averages
    final pointsRepo = _ref.read(pointsRepositoryProvider);
    await pointsRepo.updateTrustScore(userId, finalScore);

    if (profile.homeCountryCode != null) {
      await pointsRepo.updateCommunityOverallAveragePoCT(
        profile.homeCountryCode!,
      );
      final continentCode = getContinentByCountryCode(profile.homeCountryCode!);
      await pointsRepo.updateContinentOverallAveragePoCT(continentCode);
      await pointsRepo.updateGlobalOverallAveragePoCT();
    }
  }

  // --- Physical Presence & Utility Actions ---

  Future<void> performCheckIn({
    required String userId,
    required String entityId,
    required String type,
    required double lat,
    required double lng,
  }) async {
    // 1. Verify distance (Simulated for backend logic, usually checked on FE)
    // In a real app, we'd fetch the entity (event/org) location here too.

    // 2. Save Record
    await _repository.saveCheckInRecord(userId, entityId, type);

    // 3. Update Points
    final pointsService = _ref.read(pointsServiceProvider);
    if (type == 'event') {
      await pointsService.trackVerifiedCheckIn(userId);
    }

    // 4. Update Trust Data via Centralized HTS Engine
    await recordActivity(userId, HTSActivityType.physicalPresence);
  }

  Future<int> performQRExchange({
    required String fromUid,
    required String toUid,
    required String handshakeToken,
    String? locationAddress,
  }) async {
    final profileRepo = _ref.read(profileRepositoryProvider);

    // 1. Fetch both profiles
    final fromProfile = await profileRepo.getUserProfile(fromUid);
    final toProfile = await profileRepo.getUserProfile(toUid);

    if (fromProfile == null || toProfile == null) {
      throw Exception("User profile not found.");
    }

    // 2. Enforce Profile Completeness
    final fromMissing = fromProfile.getMissingRequiredFields();
    if (fromMissing.isNotEmpty) {
      debugPrint(
        "❌ performQRExchange: fromProfile ($fromUid) is incomplete: $fromMissing",
      );
      throw IncompleteProfileException(
        missingFields: fromMissing,
        isOwnProfile: true, // Assuming fromUid is always the executor
        message:
            "You must complete your profile before you can connect via QR.",
      );
    }

    final toMissing = toProfile.getMissingRequiredFields();
    if (toMissing.isNotEmpty) {
      debugPrint(
        "❌ performQRExchange: toProfile ($toUid) is incomplete: $toMissing",
      );
      throw IncompleteProfileException(
        missingFields: toMissing,
        isOwnProfile: false,
        message:
            "The other user must complete their profile before you can connect via QR.",
      );
    }

    // A static profile URL is not proof of an in-person exchange. The backend
    // consumes a short-lived, single-use challenge embedded in the displayed
    // QR code and performs every trust mutation atomically.
    if (fromUid == 'unknown' || toUid == 'unknown') {
      throw Exception("Invalid user identification for QR exchange.");
    }
    try {
      final response = await FirebaseFunctions.instance
          .httpsCallable('completeQrHandshake')
          .call(<String, dynamic>{
            'token': handshakeToken,
            'locationAddress': ?locationAddress,
          });
      final result = Map<String, dynamic>.from(response.data as Map);
      if (result['peerUid'] != toUid) {
        throw StateError('The QR challenge does not match this profile.');
      }

      final scannerAward = (result['earnedPoints'] as num?)?.toInt() ?? 0;
      _ref.invalidate(userProfileProvider);
      return scannerAward;
    } on FirebaseFunctionsException catch (error) {
      if (error.code == 'already-exists') {
        throw AlreadyConnectedException(
          message: "You are already connected with this user.",
          otherUid: toUid,
        );
      }
      rethrow;
    }
  }

  /// Rate a user's trust (Slider Input).
  ///
  /// DSP rewards and staking combat are now securely enforced via the backend
  /// (Firebase Function 'onVouchWrite' trigger in dsp.js). The client simply
  /// validates the input and persists the score.
  Future<void> rateUser({
    required String fromUserId,
    required String toUserId,
    required double score,
  }) async {
    if (fromUserId == toUserId) throw Exception("Cannot rate yourself");
    if (score < 0 || score > 100) throw Exception("Score must be 0-100");

    final relationships = await _ref
        .read(relationshipRepositoryProvider)
        .getRelationshipsList(fromUserId);
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
      'relative',
    };
    final isFamilyMember = relationships.any(
      (r) =>
          r.id == toUserId &&
          r.status == 'active' &&
          familyTypes.contains(r.type.toLowerCase()),
    );
    if (isFamilyMember) {
      throw Exception(
        "You cannot vouch for a family member (Conflict of Interest).",
      );
    }

    // Circle of Trust Anti-Collusion Firewall:
    // Close relationships (Family + Friends) CANNOT participate in staked ratings (1-10 or 91-100).
    final isStakedRating = score <= 10 || score > 90;
    if (isStakedRating) {
      final isInCircleOfTrust = relationships.any(
        (r) => r.id == toUserId && r.status == 'active',
      );
      if (isInCircleOfTrust) {
        throw Exception(
          "Members in your Circle of Trust cannot participate in Trust Slider staking to prevent collusion.",
        );
      }
    }

    final isNowFullTrust = score > 90;

    // Fetch rater's name for notifications (only strictly needed if entering full trust, but good to have)
    final fromProfile = await _ref
        .read(profileRepositoryProvider)
        .getUserProfile(fromUserId);

    await _repository.saveTrustRating(
      fromUserId: fromUserId,
      toUserId: toUserId,
      score: score,
      isFullTrust: isNowFullTrust, // kept for backward compatibility queries
      // The backend derives stake fields. Clients always submit zero so they
      // cannot manufacture a refundable stake balance.
      stakedAmount: 0,
      remainingStake: 0,
      fromUserName: fromProfile?.fullName,
    );
  }

  Future<double?> getMyRating(String fromUserId, String toUserId) =>
      _repository.getRating(fromUserId: fromUserId, toUserId: toUserId);

  Future<void> saveVerificationEvent({
    required String fromUserId,
    required String toUserId,
    required Map<String, bool> fields,
  }) async {
    // [DEPRECATED v8] Verification network fee removed — no DSP cost

    return _repository.saveVerificationEvent(
      fromUserId: fromUserId,
      toUserId: toUserId,
      fields: fields,
    );
  }

  Future<List<String>> getFlaggedFields(String userId) =>
      _repository.getFlaggedFields(userId);

  /// Checks if a user is eligible to verify another user's profile fields.
  /// Returns null if allowed, otherwise returns a reason string.
  Future<String?> checkVerificationEligibility(
    String fromUserId,
    String toUserId,
  ) async {
    if (fromUserId == toUserId) return "You cannot verify your own profile.";

    // 1. Check if already verified this specific user
    final hasVerified = await _repository.hasVerifiedUser(fromUserId, toUserId);
    if (hasVerified) {
      return 'You have already verified this user.';
    }

    // 2. Check daily limit (1 verification per 24 hours)
    final lastTime = await _repository.getLastVerificationTime(fromUserId);
    if (lastTime != null) {
      final difference = DateTime.now().difference(lastTime);
      if (difference.inHours < 24) {
        final hoursLeft = 24 - difference.inHours;
        return 'Daily limit reached. You can verify another profile in $hoursLeft hours.';
      }
    }

    // 3. Must be a connected Friend, Family, In-Person QR peer, or have bilateral chat dialogue (no verifying total strangers without interaction)
    final relRepo = _ref.read(relationshipRepositoryProvider);
    final relationship = await relRepo.getRelationship(
      userId: fromUserId,
      relatedUserId: toUserId,
    );
    final qrPeers = await _repository.getQrExchangeUserIds(fromUserId);
    final isQrPeer = qrPeers.contains(toUserId);
    final isConnectedRelationship =
        relationship != null && relationship.status == 'active';

    final chatRepo = _ref.read(chatRepositoryProvider);
    final hasBilateral = await chatRepo.hasBilateralDialogue(
      fromUserId,
      toUserId,
    );

    if (!isConnectedRelationship && !isQrPeer && !hasBilateral) {
      return 'You can only verify profile fields for people in your Circle of Trust (Family or Friends), whom you have met in-person via QR exchange, or with whom you have engaged in a direct chat conversation (both users exchanging messages).';
    }

    return null;
  }

  /// Checks if a user is eligible to vouch for another user.
  /// Returns null if allowed, otherwise returns a reason string.
  Future<String?> checkVouchEligibility(
    String fromUserId,
    String toUserId,
  ) async {
    // [NEW] Base PCT Conditions
    // 4. Check Vouch Eligibility (Must be Verified - via Profile or QR)
    final eligibilityError = await _checkBasePoCTEligibility(fromUserId);
    if (eligibilityError != null) return eligibilityError;

    // Removed strict QR check here as _checkBasePoCTEligibility now covers isVerified status
    // which includes profile completion.

    // 1. Validation
    if (fromUserId == toUserId) return "Cannot vouch for yourself";

    final alreadyVouched = await _repository.hasVouched(fromUserId, toUserId);
    if (alreadyVouched) {
      return "You have already vouched for this user";
    }

    // 2. Check Relationships (Only prevent FAMILY from vouching for each other — Conflict of Interest)
    final relRepo = _ref.read(relationshipRepositoryProvider);
    final relationship = await relRepo.getRelationship(
      userId: fromUserId,
      relatedUserId: toUserId,
    );
    if (relationship != null && relationship.status == 'active') {
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
        'relative',
      };
      if (familyTypes.contains(relationship.type.toLowerCase())) {
        return 'You cannot vouch for a family member (Conflict of Interest).';
      }
    }

    return null;
  }

  /// Helper to enforce base PCT conditions for any trust action.
  Future<String?> _checkBasePoCTEligibility(String userId) async {
    final profileRepo = _ref.read(profileRepositoryProvider);
    final pointsRepo = _ref.read(pointsRepositoryProvider);

    // 1. Check Profile Completeness
    final profile = await profileRepo.getUserProfile(userId);
    if (profile == null) return "Profile not found.";
    if (!profile.isComplete) {
      return "You must complete your profile before you can verify or vouch for others.";
    }

    // 2. Check Verified Status (implied PCT >= 30)
    final trustData = await _repository.getTrustData(userId);
    if (trustData == null || !trustData.isVerified) {
      return "You must be a Verified User to perform this action.";
    }

    // 3. Check DSP Balance (at least 10,000 DSP)
    final points = await pointsRepo.getUserPoints(userId);
    if (points == null || points.totalPoints < 10000) {
      return "You must have acquired at least 10,000 DSP to perform this action.";
    }

    // [NEW] 4. Check Negative Signals / Restraints
    final reportRepo = _ref.read(reportRepositoryProvider);
    final reports = await reportRepo.getReportCount(userId);
    final blockedByCount = profile.blockedByCount ?? 0;
    // `trustData` is non-null here — verified-status check above returned
    // early if it was null.
    final flaggedMessagesCount = trustData.flaggedMessagesCount;

    if (reports >= 5 || blockedByCount >= 5 || flaggedMessagesCount >= 5) {
      return "Your account is under restriction due to multiple negative community signals. You cannot verify or vouch for others.";
    }

    return null;
  }

  /// Returns a set of field keys that have been verified (true) by at least one user.
  Future<Set<String>> getVerifiedFields(String userId) async {
    final allVerifications = await _repository.getAllVerificationsForUser(
      userId,
    );
    final Set<String> verifiedFields = {};

    for (final v in allVerifications) {
      final Map<String, dynamic> fields = v['fields'] ?? {};
      fields.forEach((key, val) {
        if (val == true) {
          verifiedFields.add(key);
        }
      });
    }
    return verifiedFields;
  }

  // --- TGE Eligibility Checks ---
  // PCT is NOT a gate. It only affects DSP→$DIASPORA swap efficiency
  // via exact PCT percent in EpochService.calculateEfficiency().

  Future<bool> checkUserTgeEligibility(String userId, int epoch) async {
    final points = await _ref
        .read(pointsRepositoryProvider)
        .getUserPoints(userId);
    if (points == null) return false;

    final epochService = _ref.read(epochServiceProvider);
    return epochService.isEligibleForTGE(
      epochNumber: epoch,
      userTotalDsp: points.availablePoints.toDouble(),
    );
  }

  Future<bool> checkCommunityTgeEligibility(
    String communityId,
    int epoch,
  ) async {
    // Needs CommunityRepository to fetch user count and treasury balance.
    // Mocking logic for now as CommunityRepository isn't injected here yet.
    // In real implementation, we'd fetch Community doc.
    return false; // Placeholder
  }

  /// [NEW] Record a major breach and trigger trust recalculation
  Future<void> recordMajorBreach(String userId, String breachType) async {
    final trustDataOld = await _repository.getTrustData(userId);
    if (trustDataOld == null) return;

    int updatedCount = 0;
    String field = '';

    switch (breachType) {
      case 'family_rejected':
        field = 'rejectedFamilyConnectionsCount';
        updatedCount = trustDataOld.rejectedFamilyConnectionsCount + 1;
        break;
      case 'fake_verification':
        field = 'fakeVerificationsCount';
        updatedCount = trustDataOld.fakeVerificationsCount + 1;
        break;
      case 'event_no_show':
        field = 'eventNoShowCount';
        updatedCount = trustDataOld.eventNoShowCount + 1;
        break;
      case 'fraud':
        field = 'reportedFraudCount';
        updatedCount = trustDataOld.reportedFraudCount + 1;
        break;
    }

    if (field.isNotEmpty) {
      await _repository.updateTrustCounter(userId, field, updatedCount);
      await updateTrustForUser(userId);
    }
  }

  /// [v3] Count completed economic transactions (DSP transfers, fiat, token)
  /// for the ongoing PCT earner: +1 PCT per 10 completed transactions.
  Future<int> _getCompletedEconomicTransactionCount(String userId) async {
    try {
      return await _ref
          .read(pointsRepositoryProvider)
          .getCompletedEconomicTransactionCount(userId);
    } catch (e) {
      debugPrint('⚠️ [Trust] Error counting economic txns: $e');
      return 0;
    }
  }
}
