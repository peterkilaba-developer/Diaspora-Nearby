import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:diaspora_nearby/features/chat/repository/report_repository.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:diaspora_nearby/features/trust/models/trust_data.dart';
import 'package:diaspora_nearby/features/trust/repository/trust_repository.dart';
import 'package:diaspora_nearby/features/profile/models/profile_data.dart';
import 'package:diaspora_nearby/features/dsp/models/user_points.dart';
import 'package:diaspora_nearby/features/dsp/services/points_service.dart';
// Note: We'll inject Repositories instead of circular Services if possible, or use Ref to read current state.

import 'package:diaspora_nearby/features/profile/repository/profile_repository.dart';
import 'package:diaspora_nearby/features/dsp/repository/points_repository.dart';
import 'package:diaspora_nearby/features/profile/repository/relationship_repository.dart';

import 'package:diaspora_nearby/core/utils/location_utils.dart';

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

final userTrustProvider = FutureProvider.family<TrustData?, String>((
  ref,
  userId,
) {
  return ref.read(trustServiceProvider).getTrustData(userId);
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

      // 6. Award 100 DSP to the verifier to incentivize verification
      try {
        await _ref
            .read(pointsServiceProvider)
            .awardPoints(
              userId: reporterId,
              amount: 100,
              reason: 'verified_solution_verifier_reward',
            );
        debugPrint(
          'Verified solution: 100 DSP awarded to verifier $reporterId',
        );
      } catch (e) {
        debugPrint('Error awarding verifier DSP: $e');
      }

      // 6. Count unique verifiers for THIS specific message
      //    Award 100 DSP + 1 PoCT at every 10 unique verifiers
      try {
        final messageVerifications = await FirebaseFirestore.instance
            .collection('verified_solutions')
            .where('messageId', isEqualTo: messageId)
            .get();
        final uniqueCount = messageVerifications.docs.length;

        if (uniqueCount > 0 && uniqueCount % 10 == 0) {
          // Award 100 DSP to the solution owner
          await _ref
              .read(pointsServiceProvider)
              .awardPoints(
                userId: senderId,
                amount: 100,
                reason: 'verified_solution_milestone',
              );

          // Award 1 PoCT to the solution owner
          await _ref
              .read(pointsServiceProvider)
              .awardPoints(
                userId: senderId,
                amount: 1,
                reason: 'poct_verified_solution_milestone',
              );

          debugPrint(
            'Verified solution milestone: $uniqueCount unique verifiers '
            'for message $messageId — 100 DSP + 1 PoCT awarded to $senderId',
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
      'wife', 'husband', 'daughter', 'son', 'mother', 'father',
      'sister', 'brother', 'aunt', 'uncle', 'nephew', 'niece', 'cousin',
    };

    final familyIds = relationships
        .where((r) => r.status == 'active' && familyTypes.contains(r.type.toLowerCase()))
        .map((r) => r.id)
        .toSet();

    // [NEW] Friend connections (all non-family active relationships)
    final friendIds = relationships
        .where((r) => r.status == 'active' && !familyTypes.contains(r.type.toLowerCase()))
        .map((r) => r.id)
        .toSet();

    final allQrIds = await _repository.getQrExchangeUserIds(userId);
    final uniqueQrIds = allQrIds.where((id) => !familyIds.contains(id)).toSet();

    final uniqueVouchIds = ratingDetails
        .where((r) => (r['score'] as num) >= 100)
        .map((r) => r['fromUserId'] as String)
        .where((id) => !familyIds.contains(id) && !uniqueQrIds.contains(id))
        .toSet();

    final uniqueVerificationIds = allVerifications
        .map((v) => v['fromUserId'] as String)
        .where(
          (id) =>
              !familyIds.contains(id) &&
              !uniqueQrIds.contains(id) &&
              !uniqueVouchIds.contains(id),
        )
        .toSet();

    // Counts for Milestones
    final uniqueFamilyCount = familyIds.length;
    final uniqueFriendCount = friendIds.length;
    final uniqueQrCount = uniqueQrIds.length;
    final uniqueTrustIds = uniqueVouchIds.union(uniqueVerificationIds);
    final uniqueTrustCount = uniqueTrustIds.length;
    final isProfileComplete = profile.isComplete;

    // --- Milestone Awards (10k DSP + 10 PoCT logic via Score Bonus) ---
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
    
    if (milestone == 'Profile') {
      // 1. Profile Milestone: Pays 10,000 DSP only when fully complete (>= 10)
      if (count >= 10 && previouslyAwardedDspCount < 10) {
        pointsService.awardManualPoints(
          userId,
          10000,
          'Governance Genesis: $milestone',
        );
        previouslyAwardedDspCount = 10;
        ledger['${milestone}_dsp_count'] = 10;
        
        if (!milestones.contains(milestone)) {
          milestones.add(milestone);
          await _ref
              .read(pointsRepositoryProvider)
              .markExplorationActionCompleted(userId, 'milestone_10_profile_fields');
          await _ref
              .read(pointsRepositoryProvider)
              .markExplorationActionCompleted(userId, 'complete_profile');
        }
      }
    } else {
      // 2. Connection Milestones: Pays 1,000 DSP instantly per connection
      if (count > previouslyAwardedDspCount) {
        int newActivities = count - previouslyAwardedDspCount;
        
        String dspAction = 'Activity Reward: $milestone';
        if (milestone == 'Verified') dspAction = 'verified_by_peer';
        if (milestone == 'Trust') dspAction = 'vouched_by_peer';
        if (milestone == 'Family') dspAction = 'family_connection';
        if (milestone == 'Friend') dspAction = 'friend_connection';
        if (milestone == 'QR') dspAction = 'identity_qr_exchange';

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
            case 'Family': actionId = 'milestone_10_family'; break;
            case 'QR': actionId = 'milestone_10_qr'; break;
            case 'Verified': actionId = 'milestone_10_verified'; break;
            case 'Friend': actionId = 'milestone_10_friend'; break;
            case 'Trust': actionId = 'milestone_10_trust'; break;
          }
          if (actionId != null) {
            await _ref
                .read(pointsRepositoryProvider)
                .markExplorationActionCompleted(userId, actionId);
          }
        }
      }
    }

    // 3. PoCT Milestone checks for ALL models (10x intervals: 10, 100, 1K, 10K...)
    int poctToAdd = 0;
    int threshold = 10;
    while (count >= threshold) {
      poctToAdd += 10;
      threshold *= 10;
    }
    milestonePoCT += poctToAdd;
  }

  await checkAndAward('Family', uniqueFamilyCount);
  await checkAndAward('Friend', uniqueFriendCount);
  await checkAndAward('QR', uniqueQrCount);
  await checkAndAward('Trust', uniqueTrustCount);
  await checkAndAward('Profile', profile.completedMilestoneFieldCount);

  // --- Programmatic HTS Engine (The Ledger) ---
    int htsPoctDelta = 0; 
    
    // GAINS: +1 PoCT for each activity from the beginning
    htsPoctDelta += trustDataOld?.attendedEventsCount ?? 0;
    htsPoctDelta += trustDataOld?.referralCount ?? 0;
    htsPoctDelta += trustDataOld?.verifiedSolutionsCount ?? 0;
    
    // LOSSES: -1 PoCT for each penalty from the beginning
    htsPoctDelta -= profile.blockedByCount ?? 0;
    htsPoctDelta -= profile.flaggedMessagesCount ?? 0;
    htsPoctDelta -= trustDataOld?.reportedFraudCount ?? 0;
    htsPoctDelta -= trustDataOld?.fakeVerificationsCount ?? 0;
    htsPoctDelta -= trustDataOld?.eventNoShowCount ?? 0;
    htsPoctDelta -= trustDataOld?.rejectedFamilyConnectionsCount ?? 0;


    // --- Seniority Milestone ---
    double seniorityScore = 0;
    if (profile.createdAt != null) {
      final daysActive = DateTime.now().difference(profile.createdAt!).inDays;
      seniorityScore = (daysActive / 100).floorToDouble();
    }

    // --- Final Score Calculation ---
    double finalScore = milestonePoCT + htsPoctDelta + seniorityScore;

    // Ensure 0-100 (PoCT is usually 1-100, but can exceed in theoretical systems, we clamp for UI)
    if (finalScore > 100) finalScore = 100;
    if (finalScore < 0) finalScore = 0;

    // --- Status & Verification ---
    TrustLevel level = TrustLevelExtension.fromScore(finalScore);

    // [UPDATED] Verification Condition:
    // 1. High Trust Score (>= 80) OR
    // 2. Already Verified (Legacy/Stickiness) OR
    // 3. Profile Completed (10+ Milestone fields)

    bool isProfileCompleteMilestone =
        profile.completedMilestoneFieldCount >= 10;
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
      uniqueQrCount: uniqueQrCount,
      isCouncilEligible:
          uniqueFamilyCount >= 10 &&
          uniqueQrCount >= 10 &&
          uniqueTrustCount >= 10 &&
          isProfileComplete,
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

    // 5. Save QR Connection Info (ONLY for the scanning user)
    // The target user (toUid) will update their own profile upon detecting the exchange record.
    final now = DateTime.now().toIso8601String();

    await profileRepo.updateProfileData(fromUid, {
      'firstQrConnection': QRConnectionInfo(
        otherUid: toUid,
        otherName: toProfile.fullName,
        locationAddress: savedAddress,
        timestamp: now,
      ).toJson(),
    });

    debugPrint("✅ performQRExchange: Scanner profile connection info updated.");

    // 6. Award Points (trackIdentityQRExchange awards 10,000 or 1,000 DSP)
    final pointsService = _ref.read(pointsServiceProvider);

    // logic:
    // - If it's my first connection: 10,000
    // - If I'm already verified AND the other person is NOT: 1,000 (I provided service)
    // - Otherwise: 0 or 1,000? Let's give 1,000 to anyone already verified who brings someone new.

    final fromWasVerified = fromTrust?.identityQRExchange ?? false;
    final toWasVerified = toTrust?.identityQRExchange ?? false;

    int scannerAward = 0;

    // Award to FROM (Scanner)
    if (!fromWasVerified) {
      scannerAward = 10000;
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

    // [VALUE SINK] Deduct 50 DSP Collateral from the voucher
    try {
      final pointsService = _ref.read(pointsServiceProvider);
      await pointsService.deductPoints(
        userId: fromUserId,
        amount: 50,
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

  /// Rate a user's trust (Slider Input)
  Future<void> rateUser({
    required String fromUserId,
    required String toUserId,
    required double score,
  }) async {
    if (fromUserId == toUserId) throw Exception("Cannot rate yourself");
    if (score < 0 || score > 100) throw Exception("Score must be 0-100");

    await _repository.saveTrustRating(
      fromUserId: fromUserId,
      toUserId: toUserId,
      score: score,
    );

    await updateTrustForUser(toUserId);
  }

  Future<double?> getMyRating(String fromUserId, String toUserId) =>
      _repository.getRating(fromUserId: fromUserId, toUserId: toUserId);

  Future<void> saveVerificationEvent({
    required String fromUserId,
    required String toUserId,
    required Map<String, bool> fields,
  }) async {
    // [VALUE SINK] Deduct 10 DSP Network Fee for verification
    try {
      final pointsService = _ref.read(pointsServiceProvider);
      await pointsService.deductPoints(
        userId: fromUserId,
        amount: 10,
        reason: 'Verification Network Fee',
      );
    } catch (e) {
      debugPrint('Error deducting verification fee: $e');
      // We still allow the event if balance check passes in UI, 
      // but the repository/service should ideally enforce this.
    }

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
        'wife', 'husband', 'daughter', 'son', 'mother', 'father',
        'sister', 'brother', 'aunt', 'uncle', 'nephew', 'niece', 'cousin',
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
        'wife', 'husband', 'daughter', 'son', 'mother', 'father',
        'sister', 'brother', 'aunt', 'uncle', 'nephew', 'niece', 'cousin',
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

    // 3. Check DSP Balance (at least 10,000 DSP)
    final points = await pointsRepo.getUserPoints(userId);
    if (points == null || points.totalPoints < 10000) {
      return "You must have acquired at least 10,000 DSP to perform this action.";
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

  Future<bool> checkUserTgeEligibility(String userId, int epoch) async {
    final points = await _ref
        .read(pointsRepositoryProvider)
        .getUserPoints(userId);
    final trust = await _repository.getTrustData(userId);

    if (points == null || trust == null) return false;

    final dsp = points.totalPoints;
    final poct = trust.trustScore;

    // Aligned with "100k Club" + "51 PoCT" gate strategy (Refined Model)
    const double gateDsp = 10000.0;
    const int gatePoct = 51; // Low Trust or higher can swap

    return dsp >= gateDsp && poct >= gatePoct;
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
}
