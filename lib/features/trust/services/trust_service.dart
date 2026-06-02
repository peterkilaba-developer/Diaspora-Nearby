import 'package:cloud_firestore/cloud_firestore.dart';

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
    final fieldName = _getMetricFieldName(type);

    // 1. Increment the counter in Firestore
    await _repository.incrementTrustMetric(userId, fieldName);

    // 2. Fetch fresh data and trigger recalculation
    final profile = await _ref
        .read(profileRepositoryProvider)
        .getUserProfile(userId);
    final points = await _ref
        .read(pointsRepositoryProvider)
        .getUserPoints(userId);

    if (profile != null && points != null) {
      await recalculateTrustScore(
        userId: userId,
        profile: profile,
        points: points,
      );
    }
  }

  /// [NEW] Record a solution verification (entry point for Chat UI)
  Future<bool> markAsVerifiedSolution({
    required String reporterId,
    required String messageId,
    required String senderId,
    required String chatId,
  }) async {
    // 1. Prevent self-verification
    if (reporterId == senderId) return false;

    // 2. Prevent duplicate verification for the same message by same user
    final id = '${reporterId}_$messageId';
    final doc = await FirebaseFirestore.instance
        .collection('verified_solutions')
        .doc(id)
        .get();
    if (doc.exists) return false;

    try {
      // 3. Record the event
      await FirebaseFirestore.instance
          .collection('verified_solutions')
          .doc(id)
          .set({
            'reporterId': reporterId,
            'messageId': messageId,
            'senderId': senderId,
            'chatId': chatId,
            'timestamp': FieldValue.serverTimestamp(),
          });

      // 4. Update message metadata in Firestore to show badge
      if (chatId.isNotEmpty) {
        try {
          await FirebaseFirestore.instance
              .collection('chats')
              .doc(chatId)
              .collection('messages')
              .doc(messageId)
              .update({'metadata.isVerifiedSolution': true});
        } catch (e) {
          debugPrint('Error updating message metadata: $e');
        }
      }

      // 5. Record the HTS activity for the sender
      await recordActivity(senderId, HTSActivityType.verifiedSolution);

      // 6. Award 1,000 DSP to the verifier to incentivize verification
      try {
        await _ref
            .read(pointsServiceProvider)
            .awardPoints(
              userId: reporterId,
              amount: 1000,
              reason: 'verified_solution_verifier_reward',
            );
        debugPrint(
          'Verified solution: 1,000 DSP awarded to verifier $reporterId',
        );
      } catch (e) {
        debugPrint('Error awarding verifier DSP: $e');
      }

      // 6. Count unique verifiers for THIS specific message
      //    Award 1,000 DSP at every 10 unique verifiers
      //    PoCT is handled by the milestone system via verifiedSolutionsCount
      try {
        final messageVerifications = await FirebaseFirestore.instance
            .collection('verified_solutions')
            .where('messageId', isEqualTo: messageId)
            .get();
        final uniqueCount = messageVerifications.docs.length;

        if (uniqueCount > 0 && uniqueCount % 10 == 0) {
          // Award 1,000 DSP to the solution owner
          await _ref
              .read(pointsServiceProvider)
              .awardPoints(
                userId: senderId,
                amount: 1000,
                reason: 'verified_solution_milestone',
              );

          debugPrint(
            'Verified solution milestone: $uniqueCount unique verifiers '
            'for message $messageId — 1,000 DSP awarded to $senderId',
          );
        }
      } catch (e) {
        debugPrint('Error checking verified solution milestone: $e');
      }

      return true;
    } catch (e) {
      debugPrint('Error marking solution: $e');
      return false;
    }
  }

  /// [NEW] Vet an Organization (Organization Vetting: 1000 DSP)
  Future<bool> vetOrganization({
    required String vetterId,
    required String orgId,
    required String orgOwnerId,
  }) async {
    if (vetterId == orgOwnerId) return false;

    // Prevent duplicate vetting
    final id = '${vetterId}_${orgId}_vetting';
    final doc = await FirebaseFirestore.instance
        .collection('organization_vettings')
        .doc(id)
        .get();
    if (doc.exists) return false;

    try {
      await FirebaseFirestore.instance
          .collection('organization_vettings')
          .doc(id)
          .set({
            'vetterId': vetterId,
            'orgId': orgId,
            'timestamp': FieldValue.serverTimestamp(),
          });

      // Award DSP (Organization Vetting: 1000 DSP)
      // Awarded to the VETTER for doing the work
      try {
        await _ref
            .read(pointsServiceProvider)
            .trackOrganizationVetting(vetterId);
      } catch (e) {
        debugPrint('Error awarding Org Vetting points: $e');
      }

      // Record Activity (Check-in / Physical Presence proxy?)
      await recordActivity(vetterId, HTSActivityType.physicalPresence);

      return true;
    } catch (e) {
      debugPrint('Error vetting organization: $e');
      return false;
    }
  }

  String _getMetricFieldName(HTSActivityType type) {
    switch (type) {
      case HTSActivityType.eventHosting:
        return 'attendedEventsCount';
      case HTSActivityType.eventNoShow:
        return 'eventNoShowCount';
      case HTSActivityType.fraudReporting:
        return 'reportCount';
      case HTSActivityType.rejectedVouch:
        return 'rejectedFamilyConnectionsCount';
      case HTSActivityType.referral:
        return 'referralCount';
      case HTSActivityType.flaggedMessage:
        return 'flaggedMessagesCount';
      case HTSActivityType.verifiedSolution:
        return 'verifiedSolutionsCount';
      case HTSActivityType.fraudulentVerification:
        return 'fakeVerificationsCount';
      case HTSActivityType.vote:
        return 'uniqueVerificationCount';
      case HTSActivityType.missedVote:
        return 'unresponsiveLiaisonCount';
      case HTSActivityType.blockedBy:
        return 'blockedByCount';
      case HTSActivityType.reportedFraud:
        return 'reportedFraudCount';
      case HTSActivityType.physicalPresence:
        return 'attendedEventsCount';
    }
  }

  Future<TrustData?> getTrustData(String uid) => _repository.getTrustData(uid);

  /// Helper to fetch data and recalculate
  Future<void> updateTrustForUser(String userId) async {
    try {
      final profileRepo = _ref.read(profileRepositoryProvider);
      final pointsRepo = _ref.read(pointsRepositoryProvider);

      final profile = await profileRepo.getUserProfile(userId);
      // Handle case where user points might not exist yet (new user)
      UserPoints? points = await pointsRepo.getUserPoints(userId);

      if (profile == null) return;

      // If points don't exist, create dummy/default for calculation
      points ??= UserPoints(
        userId: userId,
        totalPoints: 0,
        availablePoints: 0,
        currentStreak: 0,
        dailyMessageCount: 0,
        lastUpdated: DateTime.now(),
        signupDate: DateTime.now(), // [FIX] Added
      );

      await recalculateTrustScore(
        userId: userId,
        profile: profile,
        points: points,
      );
    } catch (e) {
      debugPrint('Error updating trust for user $userId: $e');
    }
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
    final vouches = await _repository.getVouchesForUser(userId);
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

    // [UPDATED] QR is independent — QR connections can also be family, friend,
    // vouch, or verify. No exclusion applied.
    final allQrIds = await _repository.getQrExchangeUserIds(userId);
    final uniqueQrIds = allQrIds.toSet();
    debugPrint(
      '🎯 [Trust] QR IDs for $userId: allQrIds=$allQrIds, unique=${uniqueQrIds.length}',
    );

    // [UPDATED] Vouch/Verify: only exclude family members (conflict of interest),
    // but QR users CAN also be vouchers/verifiers.
    final uniqueVouchIds = ratingDetails
        .where((r) => (r['score'] as num) > 90)
        .map((r) => r['fromUserId'] as String)
        .where((id) => !familyIds.contains(id))
        .toSet();

    final uniqueVerificationIds = allVerifications
        .map((v) => v['fromUserId'] as String)
        .where((id) => !familyIds.contains(id) && !uniqueVouchIds.contains(id))
        .toSet();

    // Counts for Milestones
    // [UPDATED v3] Vouch and Verified are now SEPARATE milestones
    final uniqueFamilyCount = familyIds.length;
    final uniqueFriendCount = friendIds.length;
    final uniqueQrCount = uniqueQrIds.length;
    final uniqueVouchCount = uniqueVouchIds.length;
    final uniqueVerifiedCount = uniqueVerificationIds.length;
    // Legacy combined set — kept for genesisTrustIds storage
    final uniqueTrustIds = uniqueVouchIds.union(uniqueVerificationIds);
    final isProfileComplete = profile.isComplete;

    debugPrint(
      '🎯 [Trust] Milestone Counts for $userId: '
      'Family=$uniqueFamilyCount, Friend=$uniqueFriendCount, '
      'QR=$uniqueQrCount, Vouch=$uniqueVouchCount, '
      'Verified=$uniqueVerifiedCount, '
      'ProfileComplete=$isProfileComplete',
    );

    // --- Milestone Awards (1,000 DSP for Profile + 1,000 DSP per connection) ---
    final milestones = List<String>.from(
      trustDataOld?.awardedQualificationMilestones ?? [],
    );

    // Create a writable copy of the ledger for tracking real-time DSP and PoCT levels
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

      if (milestone == 'Profile') {
        // 1. Profile Milestone: Pays 10,000 DSP only when ALL fields complete (10x scale)
        //    [UPDATED v9] Changed from 1,000 to 10,000 DSP
        final totalFields = profile.totalMilestoneFields;
        if (count >= totalFields && previouslyAwardedDspCount < totalFields) {
          pointsService.awardManualPoints(userId, 10000, 'profile_completion');
          previouslyAwardedDspCount = totalFields;
          ledger['${milestone}_dsp_count'] = totalFields;

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
      } else {
        // 2. Connection Milestones: Pays 1,000 DSP (10x scale) instantly per connection
        if (count > previouslyAwardedDspCount) {
          int newActivities = count - previouslyAwardedDspCount;

          String dspAction = 'Activity Reward: $milestone';
          if (milestone == 'Verified') dspAction = 'verified_by_peer';
          if (milestone == 'Vouch') dspAction = 'vouched_by_peer';
          if (milestone == 'Family') dspAction = 'family_connection';
          if (milestone == 'Friend') dspAction = 'friend_connection';
          if (milestone == 'QR') dspAction = 'identity_qr_exchange';

          debugPrint(
            '🎯 [Trust] AWARDING $userId: ${1000 * newActivities} DSP for $dspAction ($newActivities new)',
          );

          pointsService.awardManualPoints(
            userId,
            1000 * newActivities,
            dspAction,
          );

          previouslyAwardedDspCount = count;
          ledger['${milestone}_dsp_count'] = count;

          // UI Exploration action sync at 10
          if (count >= 10 && !milestones.contains(milestone)) {
            milestones.add(milestone);
            String? actionId;
            switch (milestone) {
              case 'Family':
                actionId = 'milestone_10_family';
                break;
              case 'QR':
                actionId = 'milestone_10_qr';
                break;
              case 'Verified':
                actionId = 'milestone_10_verified';
                break;
              case 'Friend':
                actionId = 'milestone_10_friend';
                break;
              case 'Vouch':
                actionId = 'milestone_10_vouch';
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

      // 3. PoCT: One-time +10 PoCT award when count reaches required threshold.
      //    Awarded once per milestone. After threshold, only DSP is earned.
      //    [UPDATED v3] 6 Genesis Milestones = 60 max PoCT
      //    Profile requires ALL fields (totalMilestoneFields), others require 10.
      final threshold = milestone == 'Profile'
          ? profile.totalMilestoneFields
          : 10;
      if (count >= threshold) {
        milestonePoCT += 10;
      }
    }

    // [UPDATED v3] Vouch and Verified are now SEPARATE milestones
    await checkAndAward('Family', uniqueFamilyCount);
    await checkAndAward('Friend', uniqueFriendCount);
    await checkAndAward('QR', uniqueQrCount);
    await checkAndAward('Verified', uniqueVerifiedCount);
    await checkAndAward('Vouch', uniqueVouchCount);
    await checkAndAward('Profile', profile.completedMilestoneFieldCount);

    // --- Programmatic HTS Engine (The Ledger) ---
    // [UPDATED v3] Multiple ongoing PoCT earners:
    // 1. Trust Slider: +1 PoCT per 10 unique full-trust voters (>90, staked 1,000 DSP)
    // 2. Economic Transactions: +1 PoCT per 10 completed unique txns
    // Penalties: -10 PoCT per 10 occurrences (milestone-based)

    int htsPoctDelta = 0;

    // GAINS: Trust Slider full-trust vouches (+1 PoCT per 10 unique full-trust voters)
    final fullTrustVouchCount = ratingDetails
        .where((r) => (r['score'] as num) > 90)
        .map((r) => r['fromUserId'] as String)
        .toSet()
        .length;
    htsPoctDelta += fullTrustVouchCount ~/ 10;

    // GAINS: Economic Transactions (+1 PoCT per 10 completed unique transactions)
    final economicTxCount = await _getCompletedEconomicTransactionCount(userId);
    htsPoctDelta += economicTxCount ~/ 10;

    // LOSSES: -10 PoCT per 10 occurrences
    htsPoctDelta -= (profile.blockedByCount ?? 0) ~/ 10;
    htsPoctDelta -= (profile.flaggedMessagesCount ?? 0) ~/ 10;
    htsPoctDelta -= (trustDataOld?.reportedFraudCount ?? 0) ~/ 10;
    htsPoctDelta -= (trustDataOld?.fakeVerificationsCount ?? 0) ~/ 10;
    htsPoctDelta -= (trustDataOld?.eventNoShowCount ?? 0) ~/ 10;
    htsPoctDelta -= (trustDataOld?.rejectedFamilyConnectionsCount ?? 0) ~/ 10;

    // --- Transparency: City Visibility (+10 PoCT one-time) ---
    double cityVisibilityPoCT = 0;
    if (profile.showCurrentLocationName == true) {
      cityVisibilityPoCT = 10;
    }

    // --- Community Participation: Event Attendance (+10 PoCT at 10 check-ins) ---
    double eventAttendancePoCT = 0;
    final checkInCount = trustDataOld?.verifiedCheckInCount ?? 0;
    if (checkInCount >= 10) {
      eventAttendancePoCT = 10;
    }

    // --- Community Participation: Emergency Fund Contributor (+10 PoCT) ---
    double emergencyFundPoCT = 0;
    final hasStaked = await _ref
        .read(emergencyFundServiceProvider)
        .hasStaked(userId);
    if (hasStaked) {
      emergencyFundPoCT = 10;
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
    // [UPDATED v3] Genesis (60) + Transparency (10) + Participation (20) + Ongoing
    double finalScore =
        milestonePoCT +
        cityVisibilityPoCT +
        eventAttendancePoCT +
        emergencyFundPoCT +
        htsPoctDelta +
        seniorityScore;

    // Ensure 0-100 (PoCT is usually 1-100, but can exceed in theoretical systems, we clamp for UI)
    if (finalScore > 100) finalScore = 100;
    if (finalScore < 0) finalScore = 0;

    // --- Status & Verification ---
    TrustLevel level = TrustLevelExtension.fromScore(finalScore);

    // [UPDATED] Verification Condition:
    // 1. High Trust Score (>= 80) OR
    // 2. Already Verified (Legacy/Stickiness) OR
    // 3. Profile Completed (ALL Milestone fields)

    bool isProfileCompleteMilestone =
        profile.completedMilestoneFieldCount >= profile.totalMilestoneFields;
    bool isVerified =
        finalScore >= 80 ||
        (trustDataOld?.isVerified ?? false) ||
        isProfileCompleteMilestone;

    // --- Save & Sync ---
    final newTrustData = TrustData(
      uid: userId,
      trustScore: finalScore,
      level: level,
      isVerified: isVerified,
      identityScore:
          (isProfileComplete ? 5.0 : 0.0) +
          (uniqueQrCount > 0 ? 15.0 : 0.0), // Simplified Legacy Fallback
      activityScore: (points.currentStreak * 1.0).clamp(0, 20),
      reputationScore: (vouches.length * 2.0).clamp(0, 20),
      vouchCount: vouches.length,
      lastUpdated: DateTime.now(),
      vouchedBy: vouches.map((v) => v.fromUserId).toList(),
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
      isCouncilEligible:
          daysActive >= 100 && isAdminOfLargeGroup && finalScore >= 90,
      awardedQualificationMilestones: milestones,
      awardedHtsTracking: ledger,
      referralCount: trustDataOld?.referralCount ?? 0,
      blockedByCount: profile.blockedByCount ?? 0,
      flaggedMessagesCount: profile.flaggedMessagesCount ?? 0,
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
    } else if (type == 'org') {
      await pointsService.trackOrganizationVetting(userId);
    }

    // 4. Update Trust Data via Centralized HTS Engine
    await recordActivity(userId, HTSActivityType.physicalPresence);
  }

  Future<int> performQRExchange({
    required String fromUid,
    required String toUid,
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

    debugPrint("✅ performQRExchange: Both profiles complete.");
    debugPrint("📍 performQRExchange: locationAddress = $locationAddress");

    // 2.1 Check for Duplicate Connection (Prevent double-payment)
    if (fromUid == 'unknown' || toUid == 'unknown') {
      debugPrint("❌ performQRExchange: Invalid UIDs detected (unknown)");
      throw Exception("Invalid user identification for QR exchange.");
    }

    final alreadyConnected = await _repository.hasExchangedQR(fromUid, toUid);
    if (alreadyConnected) {
      debugPrint(
        "⚠️ performQRExchange: Users already connected. Skipping reward logic.",
      );
      throw AlreadyConnectedException(
        message: "You are already connected with this user.",
        otherUid: toUid,
      );
    }

    // 3. Save Records for both
    // Use a fallback for locationAddress if it's null but we want to know where it failed
    final savedAddress = locationAddress ?? "Location Unavailable";

    await _repository.saveQRExchangeRecord(
      fromUid,
      toUid,
      locationAddress: savedAddress,
    );
    await _repository.saveQRExchangeRecord(
      toUid,
      fromUid,
      locationAddress: savedAddress,
    );

    debugPrint(
      "✅ performQRExchange: QR Exchange records saved with address: $savedAddress",
    );

    // 4. Mark Identity QR Exchanged (in trust_data)
    // Fetch trust data to determine if they were already verified
    final fromTrust = await _repository.getTrustData(fromUid);
    final toTrust = await _repository.getTrustData(toUid);

    await _repository.markIdentityQRExchanged(fromUid);
    await _repository.markIdentityQRExchanged(toUid);

    debugPrint("✅ performQRExchange: Identity QR flags updated.");

    // 5. Save QR Connection Info for BOTH users
    final now = DateTime.now().toIso8601String();

    await profileRepo.updateProfileData(fromUid, {
      'firstQrConnection': QRConnectionInfo(
        otherUid: toUid,
        otherName: toProfile.fullName,
        locationAddress: savedAddress,
        timestamp: now,
      ).toJson(),
    });

    await profileRepo.updateProfileData(toUid, {
      'firstQrConnection': QRConnectionInfo(
        otherUid: fromUid,
        otherName: fromProfile.fullName,
        locationAddress: savedAddress,
        timestamp: now,
      ).toJson(),
    });

    debugPrint("✅ performQRExchange: Both profiles' connection info updated.");

    // 6. Award Points (trackIdentityQRExchange awards 1,000 DSP per exchange)
    final pointsService = _ref.read(pointsServiceProvider);

    // logic:
    // - If it's my first connection: 1,000 DSP
    // - If I'm already verified AND the other person is NOT: 1,000 (I provided service)

    final fromWasVerified = fromTrust?.identityQRExchange ?? false;
    final toWasVerified = toTrust?.identityQRExchange ?? false;

    int scannerAward = 0;

    // Award to FROM (Scanner)
    if (!fromWasVerified) {
      scannerAward = 1000;
      await pointsService.trackIdentityQRExchange(
        fromUid,
        toUid,
        isServiceProvider: false,
      );
    } else if (!toWasVerified) {
      scannerAward = 1000;
      await pointsService.trackIdentityQRExchange(
        fromUid,
        toUid,
        isServiceProvider: true,
      );
    }

    // Award to TO (Scanned)
    if (!toWasVerified) {
      await pointsService.trackIdentityQRExchange(
        toUid,
        fromUid,
        isServiceProvider: false,
      );
    } else if (!fromWasVerified) {
      await pointsService.trackIdentityQRExchange(
        toUid,
        fromUid,
        isServiceProvider: true,
      );
    }

    debugPrint(
      "✅ performQRExchange: DSP points awarded ($scannerAward to scanner).",
    );

    // 7. Update Trust for both
    await updateTrustForUser(fromUid);
    await updateTrustForUser(toUid);

    debugPrint("✅ performQRExchange: Trust scores recalculated.");

    // 8. Invalidate Profile Cache
    _ref.invalidate(userProfileProvider);
    debugPrint(
      "✅ performQRExchange: Profile provider invalidated. Scanner side complete.",
    );

    return scannerAward;
  }

  /// Vouch for a user
  Future<void> vouchForUser({
    required String fromUserId,
    required String toUserId,
    required String relationship,
    int stakeAmount = 0,
  }) async {
    // 1. Validation
    if (fromUserId == toUserId) throw Exception("Cannot vouch for yourself");

    final alreadyVouched = await _repository.hasVouched(fromUserId, toUserId);
    if (alreadyVouched) {
      throw Exception("You have already vouched for this user");
    }

    // 2. Create Vouch Record
    final vouch = Vouch(
      id: '${fromUserId}_${toUserId}_${DateTime.now().millisecondsSinceEpoch}',
      fromUserId: fromUserId,
      toUserId: toUserId,
      relationship: relationship,
      stakeAmount: stakeAmount,
      createdAt: DateTime.now(),
    );

    await _repository.createVouch(vouch);

    // [UPDATED v8] Deduct 1,000 DSP Collateral from the voucher
    try {
      final pointsService = _ref.read(pointsServiceProvider);
      await pointsService.deductPoints(
        userId: fromUserId,
        amount: 1000,
        reason: 'Vouch Collateral (Locked for Sybil Defense)',
      );
    } catch (e) {
      debugPrint('Error deducting vouch collateral: $e');
    }

    // 3. Award Staged Vouch Reward
    try {
      final pointsService = _ref.read(pointsServiceProvider);
      await pointsService.trackVouchReward(fromUserId, toUserId);
    } catch (e) {
      debugPrint('Error awarding vouch reward: $e');
    }

    // 4. Trigger Recalculation
    await updateTrustForUser(toUserId);
  }

  /// Rate a user's trust (Slider Input) with Staking Economics.
  ///
  /// Every first-time rating earns the rater 1,000 DSP (vouch reward).
  /// If the score is > 90 (full trust), 1,000 DSP is staked (locked).
  /// If the score is ≤ 90, the rater keeps the 1,000 DSP free.
  ///
  /// Staker economics (full trust only):
  ///   - Each subsequent rater who also gives full trust: staker earns +100 DSP
  ///   - Each subsequent rater who gives ≤90: -100 DSP burned from stake
  ///   - Stake hits 0: full-trust vouch auto-removed
  ///   - Slide back below 91: remaining stake refunded
  Future<void> rateUser({
    required String fromUserId,
    required String toUserId,
    required double score,
  }) async {
    if (fromUserId == toUserId) throw Exception("Cannot rate yourself");
    if (score < 0 || score > 100) throw Exception("Score must be 0-100");

    final pointsService = _ref.read(pointsServiceProvider);
    final existingDoc = await _repository.getTrustRatingDoc(
      fromUserId: fromUserId,
      toUserId: toUserId,
    );
    final isFirstRating = existingDoc == null;
    final wasFullTrust = existingDoc?['isFullTrust'] == true;
    final isNowFullTrust = score > 90;

    // --- Step 1: Award 1,000 DSP vouch reward on FIRST rating ---
    // This is a one-time reward per user pair regardless of score.
    if (isFirstRating) {
      await pointsService.awardPoints(
        userId: fromUserId,
        amount: 1000,
        reason: 'trust_vouch_reward',
      );
    }

    // --- Step 2: Handle staking transitions ---
    if (isNowFullTrust && !wasFullTrust) {
      // ENTERING full-trust: stake 1,000 DSP.
      // For first rating, this effectively locks the just-awarded vouch reward.
      // For re-rating, this deducts from existing balance.
      await pointsService.deductPoints(
        userId: fromUserId,
        amount: 1000,
        reason: 'trust_stake_full_trust',
      );
      // Fetch rater's name for the notification
      final fromProfile = await _ref
          .read(profileRepositoryProvider)
          .getUserProfile(fromUserId);
      await _repository.saveTrustRating(
        fromUserId: fromUserId,
        toUserId: toUserId,
        score: score,
        isFullTrust: true,
        stakedAmount: 1000,
        remainingStake: 1000,
        fromUserName: fromProfile?.fullName,
      );
    } else if (!isNowFullTrust && wasFullTrust) {
      // EXITING full-trust: refund remaining stake
      final remaining = (existingDoc?['remainingStake'] as num?)?.toInt() ?? 0;
      if (remaining > 0) {
        await pointsService.awardPoints(
          userId: fromUserId,
          amount: remaining,
          reason: 'trust_stake_refund',
        );
      }
      await _repository.saveTrustRating(
        fromUserId: fromUserId,
        toUserId: toUserId,
        score: score,
        isFullTrust: false,
        stakedAmount: 0,
        remainingStake: 0,
      );
    } else {
      // Regular rating update (same zone, no staking change)
      await _repository.saveTrustRating(
        fromUserId: fromUserId,
        toUserId: toUserId,
        score: score,
        isFullTrust: isNowFullTrust,
        stakedAmount: isNowFullTrust
            ? (existingDoc?['stakedAmount'] as num?)?.toInt() ?? 1000
            : 0,
        remainingStake: isNowFullTrust
            ? (existingDoc?['remainingStake'] as num?)?.toInt() ?? 1000
            : 0,
      );
    }

    // --- Step 3: Process staker economics for ALL existing stakers ---
    await _processStakerEconomics(
      toUserId: toUserId,
      newRaterIsFullTrust: isNowFullTrust,
      newRaterId: fromUserId,
    );

    await updateTrustForUser(toUserId);
  }

  /// Process staker economics when a new rating comes in.
  ///
  /// For each existing full-trust staker (excluding the new rater):
  ///   - If new rater gave full trust (>90): staker earns +100 DSP
  ///   - If new rater gave ≤90: staker loses -100 DSP from stake (burned)
  ///   - If stake depletes to 0: auto-remove full-trust vouch
  Future<void> _processStakerEconomics({
    required String toUserId,
    required bool newRaterIsFullTrust,
    required String newRaterId,
  }) async {
    final pointsService = _ref.read(pointsServiceProvider);
    final stakers = await _repository.getFullTrustStakersForUser(toUserId);

    for (final staker in stakers) {
      final stakerId = staker['fromUserId'] as String;
      if (stakerId == newRaterId) continue; // Skip the new rater themselves

      final remaining = (staker['remainingStake'] as num?)?.toInt() ?? 0;

      if (newRaterIsFullTrust) {
        // Agreement: staker earns +100 DSP (unlimited, not from stake)
        await pointsService.awardPoints(
          userId: stakerId,
          amount: 100,
          reason: 'trust_stake_agreement_reward',
        );
      } else {
        // Disagreement: -100 DSP burned from stake
        final newRemaining = remaining - 100;
        if (newRemaining <= 0) {
          // Stake depleted: auto-remove full-trust vouch
          await _repository.updateStakerBalance(
            fromUserId: stakerId,
            toUserId: toUserId,
            remainingStake: 0,
            isFullTrust: false,
          );
        } else {
          await _repository.updateStakerBalance(
            fromUserId: stakerId,
            toUserId: toUserId,
            remainingStake: newRemaining,
          );
        }
      }
    }
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

  /// Checks if a user is eligible to verify another user.
  /// Returns null if allowed, otherwise returns a reason string.
  Future<String?> checkVerificationEligibility(
    String fromUserId,
    String toUserId,
  ) async {
    // [NEW] Base PoCT Conditions
    final baseError = await _checkBasePoCTEligibility(fromUserId);
    if (baseError != null) return baseError;

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

    // 3. Check Relationships (Only prevent FAMILY from verifying each other — Conflict of Interest)
    final relRepo = _ref.read(relationshipRepositoryProvider);
    final relationship = await relRepo.getRelationship(
      userId: fromUserId,
      relatedUserId: toUserId,
    );
    if (relationship != null && relationship.status == 'active') {
      // Only block if the relationship is a family type
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
      if (familyTypes.contains(relationship.type.toLowerCase())) {
        return 'You cannot verify a family member (Conflict of Interest).';
      }
    }

    return null;
  }

  /// Checks if a user is eligible to vouch for another user.
  /// Returns null if allowed, otherwise returns a reason string.
  Future<String?> checkVouchEligibility(
    String fromUserId,
    String toUserId,
  ) async {
    // [NEW] Base PoCT Conditions
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
      };
      if (familyTypes.contains(relationship.type.toLowerCase())) {
        return 'You cannot vouch for a family member (Conflict of Interest).';
      }
    }

    return null;
  }

  /// Helper to enforce base PoCT conditions for any trust action.
  Future<String?> _checkBasePoCTEligibility(String userId) async {
    final profileRepo = _ref.read(profileRepositoryProvider);
    final pointsRepo = _ref.read(pointsRepositoryProvider);

    // 1. Check Profile Completeness
    final profile = await profileRepo.getUserProfile(userId);
    if (profile == null) return "Profile not found.";
    if (!profile.isComplete) {
      return "You must complete your profile before you can verify or vouch for others.";
    }

    // 2. Check Verified Status (implied PoCT >= 30)
    final trustData = await _repository.getTrustData(userId);
    if (trustData == null || !trustData.isVerified) {
      return "You must be a Verified User to perform this action.";
    }

    // 3. Check Anti-Sybil Gate (Must have performed QR Identity Exchange)
    final points = await pointsRepo.getUserPoints(userId);
    if (points == null || points.qrConnectionCount <= 0) {
      return "You must perform at least one QR Identity Exchange to prove humanity before performing this action.";
    }

    // [NEW] 4. Check Negative Signals / Restraints
    final reportRepo = _ref.read(reportRepositoryProvider);
    final reports = await reportRepo.getReportCount(userId);
    final blockedByCount = profile.blockedByCount ?? 0;
    final flaggedMessagesCount = profile.flaggedMessagesCount ?? 0;

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
  // PoCT is NOT a gate. It only affects DSP→$DIASPORA swap efficiency
  // via the decile scale in EpochService.calculateEfficiency().

  Future<bool> checkUserTgeEligibility(String userId, int epoch) async {
    final points = await _ref
        .read(pointsRepositoryProvider)
        .getUserPoints(userId);
    if (points == null) return false;

    final epochService = _ref.read(epochServiceProvider);
    return epochService.isEligibleForTGE(
      hasIdentityQr: points.qrConnectionCount > 0,
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
  /// for the ongoing PoCT earner: +1 PoCT per 10 completed transactions.
  Future<int> _getCompletedEconomicTransactionCount(String userId) async {
    try {
      final firestore = FirebaseFirestore.instance;
      // Count completed P2P/B2B/C2B/B2C transactions (sent + received)
      final sentQuery = await firestore
          .collection('users')
          .doc(userId)
          .collection('transactions')
          .where(
            'type',
            whereIn: [
              'dsp_transfer_sent',
              'fiat_transfer_sent',
              'token_transfer_sent',
              'p2p_transfer',
              'b2b_transfer',
              'c2b_transfer',
              'b2c_transfer',
            ],
          )
          .count()
          .get();
      return sentQuery.count ?? 0;
    } catch (e) {
      debugPrint('⚠️ [Trust] Error counting economic txns: $e');
      return 0;
    }
  }
}
