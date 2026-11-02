import 'dart:async';
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
import 'package:diaspora_nearby/features/profile/models/relationship.dart';

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

  static final Map<String, String?> _verificationEligibilityCache = {};
  static final Map<String, Set<String>> _verifiedFieldsCache = {};

  bool hasCachedVerificationEligibility(String fromUserId, String toUserId) =>
      _verificationEligibilityCache.containsKey('${fromUserId}_$toUserId');

  String? getCachedVerificationEligibility(
    String fromUserId,
    String toUserId,
  ) => _verificationEligibilityCache['${fromUserId}_$toUserId'];

  Set<String>? getCachedVerifiedFields(String userId) =>
      _verifiedFieldsCache[userId];

  void cacheVerifiedFields(String userId, Set<String> fields) {
    _verifiedFieldsCache[userId] = Set<String>.from(fields);
  }

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
    final trustData =
        _repository.getCachedTrustData(targetUid) ??
        await getTrustData(targetUid);
    return trustData?.trustScore ?? 0.0;
  }

  /// Helper to fetch data and recalculate
  Future<void> updateTrustForUser(String userId) async {
    // Recalculation used to fan out across relationships, ratings, chats,
    // verifications, and communities before attempting writes denied by the
    // production rules. Refresh the server-authored projection instead.
    if (FirebaseAuth.instance.currentUser?.uid == userId) {
      unawaited(
        FirebaseFunctions.instance
            .httpsCallable('evaluateProfileMilestone')
            .call<Map<String, dynamic>>({'userId': userId})
            .then((_) {
              _ref.invalidate(userTrustProvider(userId));
              _ref.invalidate(userPointsProvider(userId));
            })
            .catchError((Object e) {
              debugPrint('evaluateProfileMilestone sync note: $e');
            }),
      );
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
    final relRepo = _ref.read(relationshipRepositoryProvider);
    final emergencyFundService = _ref.read(emergencyFundServiceProvider);
    final chatRepo = _ref.read(chatRepositoryProvider);
    final pointsRepo = _ref.read(pointsRepositoryProvider);

    // 1. Fetch Existing Data in Parallel
    final results = await Future.wait<dynamic>([
      _repository.getTrustData(userId),
      relRepo.getRelationships(userId).first,
      _repository.getDetailedTrustRatingsForUser(userId),
      _repository.getAllVerificationsForUser(userId),
      _repository.getQrExchangeUserIds(userId),
      _getCompletedEconomicTransactionCount(userId),
      emergencyFundService.hasStaked(userId),
      chatRepo.isAdminOfLargeGroupChat(userId),
    ]);

    final trustDataOld = results[0] as TrustData?;
    final relationships = results[1] as List<Relationship>;
    final ratingDetails = results[2] as List<Map<String, dynamic>>;
    final allVerifications = results[3] as List<Map<String, dynamic>>;
    final allQrIds = results[4] as List<String>;
    final economicTxCount = results[5] as int;
    final hasStaked = results[6] as bool;
    final isAdminOfLargeGroup = results[7] as bool;

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

    // Counts for Milestones (preserve server-authoritative counts if local subcollection query is partial/empty)
    int maxInt(int a, int b) => a > b ? a : b;
    final uniqueFamilyCount = maxInt(
      familyIds.length,
      trustDataOld?.uniqueFamilyCount ?? 0,
    );
    final uniqueFriendCount = maxInt(
      friendIds.length,
      trustDataOld?.uniqueFriendCount ?? 0,
    );
    final uniqueQrCount = maxInt(
      maxInt(uniqueQrIds.length, trustDataOld?.uniqueQrCount ?? 0),
      points.qrConnectionCount,
    );
    final uniqueVouchCount = uniqueVouchIds.length;
    final uniqueVerifiedCount = maxInt(
      uniqueVerificationIds.length,
      trustDataOld?.uniqueVerificationCount ?? 0,
    );
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

      // Server-authoritative PoH rewards are synced via evaluateProfileMilestone / syncProfileMilestoneAndTrust.
      // First 10 steps of Profile/Family/Friend/QR/Verified grant +1 PCT and 1,000 DSP (immediately converted at 100% into $DIASPORA).
      // Steps 11+ grant 1,000 DSP each (remaining as DSP for TDE conversion).
      if (count > previouslyAwardedDspCount) {
        ledger['${milestone}_dsp_count'] = count;
      }
      if (count >= 10 && !milestones.contains(milestone)) {
        milestones.add(milestone);
      }

      // PCT: +1 PCT per step for the first 10 steps (up to +10 PCT per pillar)
      milestonePoCT += count >= 10 ? 10 : (count > 0 ? count : 0);
    }

    // Check 5 count-based PoH milestones in parallel
    await Future.wait([
      checkAndAward('Family', uniqueFamilyCount),
      checkAndAward('Friend', uniqueFriendCount),
      checkAndAward('QR', uniqueQrCount),
      checkAndAward('Verified', uniqueVerifiedCount),
      checkAndAward('Profile', profile.completedMilestoneFieldCount),
    ]);

    // --- Programmatic HTS Engine (The Ledger) ---
    // Continuous dynamic PCT earners (+1 PCT per 10 events across all positive trust-building actions):
    // 1. Trust Slider Net Vouches (>90 minus 1-10, excluding Circle of Trust): +1 PCT per 10
    // 2. Automatic Proximity Connections (10+ min within 100 ft): +1 PCT per 10
    // 3. Grassroots Gatherings (60+ min within 100 ft, host or guest): +1 PCT per 10
    // 4. Event Attendance (QR / Venue check-ins): +1 PCT per 10
    // 5. Event Hosting (verified event attendees): +1 PCT per 10
    // 6. Additional Identity QR Exchanges beyond Genesis milestone (11+): +1 PCT per 10
    // 7. Additional Peer Verifications received (11+) & given: +1 PCT per 10
    // 8. Additional Family & Friend Connections beyond Genesis milestones (11+): +1 PCT per 10
    // 9. Verified Chat Solutions (authored or verified): +1 PCT per 10
    // 10. Member Referrals: +1 PCT per 10
    // 11. Completed Economic & Peer Stay / Hosting Transactions: +1 PCT per 10
    // 12. Governance Votes Cast: +1 PCT per 10
    // Penalties: -1 PCT per 10 occurrences (-10 PCT per 10 flagged messages)

    int htsPoctDelta = 0;

    // 1. Trust Slider Net Vouches (+1 PCT per 10 net full-trust voters, non-Circle of Trust)
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

    final lifetimeEarnings = points.lifetimeEarnings;

    int maxCount(int a, int b) => a > b ? a : b;

    // 2. Automatic Proximity Connections (+1 PCT per 10)
    final proximityConnectionsCount = maxCount(
      trustDataOld?.proximityConnectionsCount ?? 0,
      ((lifetimeEarnings['proximity_dwell_reward'] ?? 0) +
              (lifetimeEarnings['proximity_connection'] ?? 0)) ~/
          1000,
    );
    htsPoctDelta += proximityConnectionsCount ~/ 10;

    // 3. Grassroots Gatherings (+1 PCT per 10)
    final grassrootsGatheringsCount = maxCount(
      maxCount(
        trustDataOld?.grassrootsGatheringsCount ?? 0,
        trustDataOld?.verifiedGatheringVisitsCount ?? 0,
      ),
      ((lifetimeEarnings['peer_visit_host_reward'] ?? 0) +
              (lifetimeEarnings['peer_visit_visitor_reward'] ?? 0) +
              (lifetimeEarnings['verified_gathering_visit'] ?? 0) +
              (lifetimeEarnings['grassroots_gathering'] ?? 0)) ~/
          1000,
    );
    htsPoctDelta += grassrootsGatheringsCount ~/ 10;

    // 4. Event Attendance (QR / Venue check-ins: +1 PCT per 10)
    final checkInCount = maxCount(
      maxCount(
        trustDataOld?.verifiedCheckInCount ?? 0,
        trustDataOld?.attendedEventsCount ?? 0,
      ),
      ((lifetimeEarnings['event_attendance'] ?? 0) +
              (lifetimeEarnings['event_check_in'] ?? 0)) ~/
          1000,
    );
    htsPoctDelta += checkInCount ~/ 10;

    // 5. Event Hosting Attendees (+1 PCT per 10)
    final hostedEventAttendeesCount = maxCount(
      trustDataOld?.hostedEventAttendeesCount ?? 0,
      ((lifetimeEarnings['event_hosting_per_attendee'] ?? 0) +
              (lifetimeEarnings['event_hosting'] ?? 0)) ~/
          1000,
    );
    htsPoctDelta += hostedEventAttendeesCount ~/ 10;

    // 6. Additional Identity QR Exchanges beyond Genesis milestone (11+: +1 PCT per 10)
    final extraQrCount = uniqueQrCount > 10 ? uniqueQrCount - 10 : 0;
    htsPoctDelta += extraQrCount ~/ 10;

    // 7. Additional Peer Verifications received (11+) & Peer Verifications given (+1 PCT per 10)
    final extraVerifiedCount = uniqueVerifiedCount > 10
        ? uniqueVerifiedCount - 10
        : 0;
    htsPoctDelta += extraVerifiedCount ~/ 10;

    final verificationsGivenCount = maxCount(
      trustDataOld?.verificationsGivenCount ?? 0,
      ((lifetimeEarnings['verifier_reward'] ?? 0) +
              (lifetimeEarnings['verify_peer'] ?? 0)) ~/
          1000,
    );
    htsPoctDelta += verificationsGivenCount ~/ 10;

    // 8. Additional Family & Friend Connections beyond Genesis milestones (11+: +1 PCT per 10)
    final extraFamilyCount = uniqueFamilyCount > 10
        ? uniqueFamilyCount - 10
        : 0;
    htsPoctDelta += extraFamilyCount ~/ 10;

    final extraFriendCount = uniqueFriendCount > 10
        ? uniqueFriendCount - 10
        : 0;
    htsPoctDelta += extraFriendCount ~/ 10;

    // 9. Verified Chat Solutions (+1 PCT per 10)
    final verifiedSolutionsCount = maxCount(
      trustDataOld?.verifiedSolutionsCount ?? 0,
      ((lifetimeEarnings['verified_solution_milestone'] ?? 0) +
              (lifetimeEarnings['verified_solution_author_reward'] ?? 0) +
              (lifetimeEarnings['verified_solution_verifier_reward'] ?? 0) +
              (lifetimeEarnings['chat_solution'] ?? 0)) ~/
          1000,
    );
    htsPoctDelta += verifiedSolutionsCount ~/ 10;

    // 10. Member Referrals (+1 PCT per 10)
    final referralCount = maxCount(
      trustDataOld?.referralCount ?? 0,
      ((lifetimeEarnings['referral_reward_referrer'] ?? 0) +
              (lifetimeEarnings['referral_reward'] ?? 0) +
              (lifetimeEarnings['referral_bonus'] ?? 0) +
              (lifetimeEarnings['referral'] ?? 0)) ~/
          1000,
    );
    htsPoctDelta += referralCount ~/ 10;

    // 11. Completed Economic & Peer Stay / Hosting Transactions (+1 PCT per 10)
    final completedHostingCount = maxCount(
      trustDataOld?.completedHostingCount ?? 0,
      ((lifetimeEarnings['host_traveler_host_reward'] ?? 0) +
              (lifetimeEarnings['host_traveler_guest_reward'] ?? 0) +
              (lifetimeEarnings['hosting_settled'] ?? 0)) ~/
          1000,
    );
    final effectiveEconomicTxCount = maxCount(
      maxCount(economicTxCount, trustDataOld?.economicTxCount ?? 0),
      completedHostingCount,
    );
    htsPoctDelta += effectiveEconomicTxCount ~/ 10;

    // 12. Governance Votes Cast (+1 PCT per 10)
    final governanceVotesCount = maxCount(
      trustDataOld?.governanceVotesCount ?? 0,
      (lifetimeEarnings['governance_vote'] ?? 0) ~/ 100,
    );
    htsPoctDelta += governanceVotesCount ~/ 10;

    // LOSSES: Penalties per 10 occurrences (-1 PCT per 10)
    htsPoctDelta -= (trustDataOld?.flaggedMessagesCount ?? 0) ~/ 10;
    htsPoctDelta -= (profile.blockedByCount ?? 0) ~/ 10;
    htsPoctDelta -= (trustDataOld?.reportedFraudCount ?? 0) ~/ 10;
    htsPoctDelta -= (trustDataOld?.fakeVerificationsCount ?? 0) ~/ 10;
    htsPoctDelta -= (trustDataOld?.eventNoShowCount ?? 0) ~/ 10;
    htsPoctDelta -= (trustDataOld?.rejectedFamilyConnectionsCount ?? 0) ~/ 10;

    // --- Pillar 1: Location Transparency (10,000 DSP -> 10,000 $DIASPORA + 10 PCT) ---
    // Server-synced via evaluateProfileMilestone / syncProfileMilestoneAndTrust.
    double cityVisibilityPoCT = 0;
    final cityForfeited = profile.cityVisibilityForfeited == true;
    final hasCurrentLocation = profile.currentLocation != null;
    final visibilityOn = profile.showCurrentLocationName != false;
    final locationMilestoneAwarded =
        ledger['LocationTransparency_dsp_awarded'] == 1;

    if (!cityForfeited && hasCurrentLocation && visibilityOn) {
      cityVisibilityPoCT = 10;
      if (!locationMilestoneAwarded) {
        ledger['LocationTransparency_dsp_awarded'] = 1;
        if (!milestones.contains('LocationTransparency')) {
          milestones.add('LocationTransparency');
        }
      }
    } else if (locationMilestoneAwarded && (cityForfeited || !visibilityOn)) {
      ledger['LocationTransparency_dsp_awarded'] = -1; // marked as burned
    }

    // --- Pillar 4: Ubuntu Emergency Fund Contribution (10,000 DSP -> 10,000 $DIASPORA + 10 PCT) ---
    double emergencyFundPoCT = 0;
    final emergencyFundAwarded = ledger['EmergencyFund_dsp_awarded'] == 1;
    if (hasStaked) {
      emergencyFundPoCT = 10;
      if (!emergencyFundAwarded) {
        ledger['EmergencyFund_dsp_awarded'] = 1;
        if (!milestones.contains('EmergencyFund')) {
          milestones.add('EmergencyFund');
        }
      }
    } else {
      milestones.remove('EmergencyFund');
      milestones.remove('UbuntuEmergencyFund');
      ledger.remove('EmergencyFund_dsp_awarded');
    }

    // --- Seniority Milestone ---
    double seniorityScore = 0;
    int daysActive = 0;
    if (profile.createdAt != null) {
      daysActive = DateTime.now().difference(profile.createdAt!).inDays;
      seniorityScore = (daysActive / 100).floorToDouble();
    }

    // --- Final Score Calculation ---
    // PoH Base (70: 5 count milestones + Location + Ubuntu Emergency Fund)
    // + Ongoing HTS delta (+1 PCT per 10 events across all positive trust-building actions) + Seniority.
    double finalScore =
        milestonePoCT +
        cityVisibilityPoCT +
        emergencyFundPoCT +
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

    // --- Proof of Humanity (PoH) Completion & Unlock Status (10 QR Exchanges unlocks all $DIASPORA) ---
    final isPoHComplete =
        uniqueFamilyCount >= 10 &&
        uniqueFriendCount >= 10 &&
        uniqueQrCount >= 10 &&
        uniqueVerificationIds.length >= 10 &&
        cityVisibilityPoCT >= 10 &&
        isProfileComplete;

    bool hasReceivedPohTokenDistribution =
        uniqueQrCount >= 10 ||
        (trustDataOld?.hasReceivedPohTokenDistribution ?? false) ||
        (ledger['PohTokenDistribution_dsp_awarded'] == 1);

    if (uniqueQrCount >= 10) {
      ledger['PohTokenDistribution_dsp_awarded'] = 1;
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
      attendedEventsCount: checkInCount,
      joinedEventsCount: trustDataOld?.joinedEventsCount ?? 0,
      verifiedSolutionsCount: verifiedSolutionsCount,
      identityQRExchange: uniqueQrCount > 0,
      verifiedCheckInCount: checkInCount,
      proximityConnectionsCount: proximityConnectionsCount,
      grassrootsGatheringsCount: grassrootsGatheringsCount,
      verifiedGatheringVisitsCount: grassrootsGatheringsCount,
      hostedEventAttendeesCount: hostedEventAttendeesCount,
      verificationsGivenCount: verificationsGivenCount,
      completedHostingCount: completedHostingCount,
      economicTxCount: effectiveEconomicTxCount,
      governanceVotesCount: governanceVotesCount,
      reliabilityScore: trustDataOld?.reliabilityScore ?? 0,
      helpfulnessScore: trustDataOld?.helpfulnessScore ?? 0,
      uniqueFamilyCount: uniqueFamilyCount,
      uniqueFriendCount: uniqueFriendCount,
      uniqueVouchCount: uniqueVouchIds.length,
      uniqueVerificationCount: uniqueVerifiedCount,
      uniqueQrCount: uniqueQrCount,
      vouchedByCount: fullTrustVouchCount,
      verifiedByCount: allVerifications.length,
      genesisFamilyIds: familyIds.isNotEmpty
          ? familyIds.take(10).toList()
          : (trustDataOld?.genesisFamilyIds ?? []),
      genesisFriendIds: friendIds.isNotEmpty
          ? friendIds.take(10).toList()
          : (trustDataOld?.genesisFriendIds ?? []),
      genesisQrIds: uniqueQrIds.isNotEmpty
          ? uniqueQrIds.take(10).toList()
          : (trustDataOld?.genesisQrIds ?? []),
      genesisTrustIds: uniqueTrustIds.isNotEmpty
          ? uniqueTrustIds.take(10).toList()
          : (trustDataOld?.genesisTrustIds ?? []),
      genesisVerificationIds: uniqueVerificationIds.isNotEmpty
          ? uniqueVerificationIds.take(10).toList()
          : (trustDataOld?.genesisVerificationIds ?? []),
      genesisVouchIds: uniqueVouchIds.isNotEmpty
          ? uniqueVouchIds.take(10).toList()
          : (trustDataOld?.genesisVouchIds ?? []),
      isCouncilEligible:
          (isPoHComplete && daysActive >= 100) &&
          isAdminOfLargeGroup &&
          finalScore >= 91,
      isDdiEligible: (isPoHComplete && daysActive >= 100) && finalScore >= 91,
      hasReceivedPohTokenDistribution: hasReceivedPohTokenDistribution,
      awardedQualificationMilestones: milestones,
      awardedHtsTracking: ledger,
      referralCount: referralCount,
      blockedByCount: profile.blockedByCount ?? 0,
      flaggedMessagesCount: trustDataOld?.flaggedMessagesCount ?? 0,
      reportedFraudCount: trustDataOld?.reportedFraudCount ?? 0,
      fakeVerificationsCount: trustDataOld?.fakeVerificationsCount ?? 0,
      eventNoShowCount: trustDataOld?.eventNoShowCount ?? 0,
      rejectedFamilyConnectionsCount:
          trustDataOld?.rejectedFamilyConnectionsCount ?? 0,
    );

    final writeFutures = <Future<void>>[
      _repository.saveTrustData(newTrustData),
      pointsRepo.updateTrustScore(userId, finalScore),
    ];

    if (profile.homeCountryCode != null) {
      final continentCode = getContinentByCountryCode(profile.homeCountryCode!);
      writeFutures.addAll([
        pointsRepo.updateCommunityOverallAveragePoCT(profile.homeCountryCode!),
        pointsRepo.updateContinentOverallAveragePoCT(continentCode),
        pointsRepo.updateGlobalOverallAveragePoCT(),
      ]);
    }

    await Future.wait(writeFutures);
  }

  // --- Physical Presence & Utility Actions ---

  Future<void> performCheckIn({
    required String userId,
    required String entityId,
    required String type,
    required double lat,
    required double lng,
  }) async {
    final pointsService = _ref.read(pointsServiceProvider);
    await Future.wait([
      _repository.saveCheckInRecord(userId, entityId, type),
      if (type == 'event') pointsService.trackVerifiedCheckIn(userId),
    ]);

    await recordActivity(userId, HTSActivityType.physicalPresence);
  }

  Future<int> performQRExchange({
    required String fromUid,
    required String toUid,
    required String handshakeToken,
    String? locationAddress,
  }) async {
    final profileRepo = _ref.read(profileRepositoryProvider);

    // 1. Fetch both profiles (check memory cache first, then parallel fetch)
    var fromProfile = profileRepo.getCachedProfile(fromUid);
    var toProfile = profileRepo.getCachedProfile(toUid);

    if (fromProfile == null || toProfile == null) {
      final fetched = await Future.wait([
        fromProfile != null
            ? Future.value(fromProfile)
            : profileRepo.getUserProfile(fromUid),
        toProfile != null
            ? Future.value(toProfile)
            : profileRepo.getUserProfile(toUid),
      ]);
      fromProfile = fetched[0];
      toProfile = fetched[1];
    }

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

    final relRepo = _ref.read(relationshipRepositoryProvider);
    final profileRepo = _ref.read(profileRepositoryProvider);

    var relationships = relRepo.getCachedRelationships(fromUserId);
    var fromProfile = profileRepo.getCachedProfile(fromUserId);

    if (relationships == null || fromProfile == null) {
      final fetched = await Future.wait<dynamic>([
        relationships != null
            ? Future.value(relationships)
            : relRepo.getRelationshipsList(fromUserId),
        fromProfile != null
            ? Future.value(fromProfile)
            : profileRepo.getUserProfile(fromUserId),
      ]);
      relationships = fetched[0] as List<Relationship>;
      fromProfile = fetched[1] as ProfileData?;
    }

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

    await _repository.saveTrustRating(
      fromUserId: fromUserId,
      toUserId: toUserId,
      score: score,
      isFullTrust: isNowFullTrust, // kept for backward compatibility queries
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
    final existingVerified = _verifiedFieldsCache[toUserId] ?? <String>{};
    final updatedVerified = Set<String>.from(existingVerified);
    fields.forEach((key, value) {
      if (value == true) {
        updatedVerified.add(key);
      }
    });
    _verifiedFieldsCache[toUserId] = updatedVerified;
    _verificationEligibilityCache['${fromUserId}_$toUserId'] =
        'You have already verified this user.';

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

    final pairKey = '${fromUserId}_$toUserId';
    if (_repository.getCachedHasVerifiedUser(fromUserId, toUserId) == true) {
      const msg = 'You have already verified this user.';
      _verificationEligibilityCache[pairKey] = msg;
      return msg;
    }

    final relRepo = _ref.read(relationshipRepositoryProvider);
    final chatRepo = _ref.read(chatRepositoryProvider);

    final results = await Future.wait<dynamic>([
      _repository.hasVerifiedUser(fromUserId, toUserId),
      _repository.getLastVerificationTime(fromUserId),
      relRepo.getRelationship(userId: fromUserId, relatedUserId: toUserId),
      _repository.getQrExchangeUserIds(fromUserId),
      chatRepo.hasBilateralDialogue(fromUserId, toUserId),
    ]);

    final hasVerified = results[0] as bool;
    if (hasVerified) {
      const msg = 'You have already verified this user.';
      _verificationEligibilityCache[pairKey] = msg;
      return msg;
    }

    final lastTime = results[1] as DateTime?;
    if (lastTime != null) {
      final difference = DateTime.now().difference(lastTime);
      if (difference.inHours < 24) {
        final hoursLeft = 24 - difference.inHours;
        final msg =
            'Daily limit reached. You can verify another profile in $hoursLeft hours.';
        _verificationEligibilityCache[pairKey] = msg;
        return msg;
      }
    }

    final relationship = results[2] as Relationship?;
    final qrPeers = results[3] as List<String>;
    final hasBilateral = results[4] as bool;

    final isQrPeer = qrPeers.contains(toUserId);
    final isConnectedRelationship =
        relationship != null && relationship.status == 'active';

    if (!isConnectedRelationship && !isQrPeer && !hasBilateral) {
      const msg =
          'You can only verify profile fields for people in your Circle of Trust (Family or Friends), whom you have met in-person via QR exchange, or with whom you have engaged in a direct chat conversation (both users exchanging messages).';
      _verificationEligibilityCache[pairKey] = msg;
      return msg;
    }

    _verificationEligibilityCache[pairKey] = null;
    return null;
  }

  /// Checks if a user is eligible to vouch for another user.
  /// Returns null if allowed, otherwise returns a reason string.
  Future<String?> checkVouchEligibility(
    String fromUserId,
    String toUserId,
  ) async {
    if (fromUserId == toUserId) return "Cannot vouch for yourself";

    final relRepo = _ref.read(relationshipRepositoryProvider);

    final results = await Future.wait<dynamic>([
      _checkBasePoCTEligibility(fromUserId),
      _repository.hasVouched(fromUserId, toUserId),
      relRepo.getRelationship(userId: fromUserId, relatedUserId: toUserId),
    ]);

    final eligibilityError = results[0] as String?;
    if (eligibilityError != null) return eligibilityError;

    final alreadyVouched = results[1] as bool;
    if (alreadyVouched) {
      return "You have already vouched for this user";
    }

    final relationship = results[2] as Relationship?;
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
    final reportRepo = _ref.read(reportRepositoryProvider);

    final cachedProfile = profileRepo.getCachedProfile(userId);
    final cachedTrust = _repository.getCachedTrustData(userId);
    final cachedPoints = pointsRepo.getCachedUserPoints(userId);

    final results = await Future.wait<dynamic>([
      cachedProfile != null
          ? Future.value(cachedProfile)
          : profileRepo.getUserProfile(userId),
      cachedTrust != null
          ? Future.value(cachedTrust)
          : _repository.getTrustData(userId),
      cachedPoints != null
          ? Future.value(cachedPoints)
          : pointsRepo.getUserPoints(userId),
      reportRepo.getReportCount(userId),
    ]);

    final profile = results[0] as ProfileData?;
    if (profile == null) return "Profile not found.";
    if (!profile.isComplete) {
      return "You must complete your profile before you can verify or vouch for others.";
    }

    final trustData = results[1] as TrustData?;
    if (trustData == null || !trustData.isVerified) {
      return "You must be a Verified User to perform this action.";
    }

    final points = results[2] as UserPoints?;
    if (points == null || points.totalPoints < 10000) {
      return "You must have acquired at least 10,000 DSP to perform this action.";
    }

    final reports = results[3] as int;
    final blockedByCount = profile.blockedByCount ?? 0;
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
    _verifiedFieldsCache[userId] = verifiedFields;
    return verifiedFields;
  }

  // --- TGE Eligibility Checks ---
  // PCT is NOT a gate. It only affects DSP→$DIASPORA swap efficiency
  // via exact PCT percent in EpochService.calculateEfficiency().

  Future<bool> checkUserTgeEligibility(String userId, int epoch) async {
    final pointsRepo = _ref.read(pointsRepositoryProvider);
    final points =
        pointsRepo.getCachedUserPoints(userId) ??
        await pointsRepo.getUserPoints(userId);
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
    return false; // Placeholder
  }

  /// [NEW] Record a major breach and trigger trust recalculation
  Future<void> recordMajorBreach(String userId, String breachType) async {
    final trustDataOld =
        _repository.getCachedTrustData(userId) ??
        await _repository.getTrustData(userId);
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
