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

final userTrustProvider = FutureProvider.family<TrustData?, String>((
  ref,
  userId,
) {
  return ref.read(trustServiceProvider).getTrustData(userId);
});

final flaggedFieldsProvider = FutureProvider.family<List<String>, String>((ref, userId) {
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
  String toString() => 'IncompleteProfileException: $message (Missing: ${missingFields.join(', ')})';
}

class AlreadyConnectedException implements Exception {
  final String message;
  final String otherUid;

  AlreadyConnectedException({
    required this.message,
    required this.otherUid,
  });

  @override
  String toString() => 'AlreadyConnectedException: $message';
}

class TrustService {
  final TrustRepository _repository;
  final Ref _ref;

  TrustService(this._repository, this._ref);

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
    // 1. Fetch Reputation Data
    final vouches = await _repository.getVouchesForUser(userId);
    // final vouches = <Vouch>[]; // (Removed empty list stub)
    final trustDataOld = await _repository.getTrustData(userId);

    // Fetch Relationships (New Weighted Factor)
    final relRepo = _ref.read(relationshipRepositoryProvider);
    final relationships = await relRepo.getRelationships(userId).first;
    final activeRelCount = relationships.where((r) => r.status == 'active').length;

    // 2. Calculate Identity Score (Max 30)
    double identityScore = 0;
    if (profile.profileImage.isNotEmpty) identityScore += 5;
    if (profile.bio != null && profile.bio!.isNotEmpty) identityScore += 5;

    // Identity completeness (Photo, Bio, Home/Host Town, Occupation, Education)
    if (profile.occupation != null && profile.occupation!.isNotEmpty) identityScore += 5;
    if (profile.education != null && profile.education!.isNotEmpty) identityScore += 5;

    // Account Age > 6 months
    if (profile.createdAt != null) {
      final createdResult = DateTime.now().difference(profile.createdAt!);
      if (createdResult.inDays > 180) {
        identityScore += 10;
      } else if (createdResult.inDays > 30) {
        identityScore += 5;
      }
    }

    // Note: Social/Business links removed as per Blueprint update.

    // Clamp Identity
    if (identityScore > 30) identityScore = 30;

    // [UPDATED] 2. PoCT Identity Score (Max 20)
    // 0 pts: Mandatory only - Default.
    // 5 pts: Level 1: Complete Profile.
    // 10 pts: Level 2: Peer Verified (Received field verification).
    // 20 pts: Level 3: QR Verified.
    
    identityScore = 0; // Reset to recalculate based on new logic
    
    // Check Tier 1: Complete Profile (All 10 Fields Required)
    // Fields: Bio, Education, Years in Host Country, Industry, Profession, 
    // Languages, Meeting Preferences, Availability, Services Offered, Looking For.

    bool isProfileComplete = true;

    // 1. Bio
    if (profile.bio == null || profile.bio!.isEmpty) isProfileComplete = false;
    // 2. Education
    if (profile.education == null || profile.education!.isEmpty) isProfileComplete = false;
    // 3. Years in Host Country
    if (profile.yearsInHostCountry == null || profile.yearsInHostCountry!.isEmpty) isProfileComplete = false;
    // 4. Industry
    if (profile.industry == null || profile.industry!.isEmpty) isProfileComplete = false;
    // 5. Profession
    if (profile.profession == null || profile.profession!.isEmpty) isProfileComplete = false;
    // 6. Languages
    if (profile.languages == null || profile.languages!.isEmpty) isProfileComplete = false;
    // 7. Meeting Preferences
    if (profile.meetingPreferences == null || profile.meetingPreferences!.isEmpty) isProfileComplete = false;
    // 8. Availability
    if (profile.availability == null || profile.availability!.isEmpty) isProfileComplete = false;
    // 9. Services Offered
    if (profile.servicesOffered == null || profile.servicesOffered!.isEmpty) isProfileComplete = false;
    // 10. Looking For
    if (profile.lookingFor == null || profile.lookingFor!.isEmpty) isProfileComplete = false;

    if (isProfileComplete) {
      identityScore = 5;
    }
    
    // Check Peer Verification (Level 2)
    if (vouches.isNotEmpty) {
       identityScore = 10; // Level 2: +5 from Level 1, Total 10
    }
    
    // Check QR Verification (Level 3)
    bool hasQrExchange = (trustDataOld?.identityQRExchange ?? false) || (profile.firstQrConnection != null);

    if (hasQrExchange) {
      identityScore = 20;
    }

    // Clamp Identity
    if (identityScore > 20) identityScore = 20;

    // 3. [UPDATED] Calculate Activity Score (Max 20)
    double activityScore = 0;
    
    // Streak: 1 pt per day (Max 10)
    activityScore += (points.currentStreak * 1.0).clamp(0.0, 10.0);
    
    // Participation (Max 10): 
    // - Daily Posts (Community Messages): 1 pt each (Max 5)
    final dailyPostsCount = points.dailyCommunitiesMessaged.length;
    activityScore += (dailyPostsCount * 1.0).clamp(0.0, 5.0);
    
    // - DMs/Standard Messages: 0.1 pt each (Max 5)
    activityScore += (points.dailyMessageCount * 0.1).clamp(0.0, 5.0);

    // Clamp Activity
    if (activityScore > 20) activityScore = 20;

    // [NEW] 3.1 Calculate Reliability Score (Max 20)
    double reliabilityScore = 0;

    final joined = trustDataOld?.joinedEventsCount ?? 0;
    final attended = trustDataOld?.attendedEventsCount ?? 0;

    if (joined > 0) {
      double rate = attended / joined;
      double volumeBonus = (attended * 4.0).clamp(0.0, 20.0);
      reliabilityScore = rate * volumeBonus;
    } else {
      reliabilityScore = 0;
    }

    // [NEW] 3.2 Calculate Helpfulness Score (Max 20)
    final solutions = trustDataOld?.verifiedSolutionsCount ?? 0;
    double helpfulnessScore = (solutions * 4.0).clamp(0, 20);

    // 4. Calculate Reputation Score (Max 20)
    double reputationScore = 0;

    // +2 per unique vouch (Max 10)
    reputationScore += (vouches.length * 2).clamp(0, 10);

    // +2 per active relationship (Max 10)
    reputationScore += (activeRelCount * 2).clamp(0, 10);

    // [NEW] DSP Balance Factor (Max 6)
    if (points.totalPoints > 0) {
      reputationScore += (points.totalPoints / 1000).clamp(0, 6);
    }

    // Fetch Peer Ratings Details
    final ratingDetails =
        await _repository.getDetailedTrustRatingsForUser(userId);
    final ratings =
        ratingDetails.map((d) => (d['score'] as num).toDouble()).toList();

    double averageRating = 0.0;
    if (ratings.isNotEmpty) {
      averageRating = ratings.reduce((a, b) => a + b) / ratings.length;
    }

    // Clamp Reputation (Automated part)
    if (reputationScore > 20) reputationScore = 20; // [UPDATED] Clamp at 20

    // 4. [UPDATED] Fetch Negative Signals & Penalties
    final reportRepo = _ref.read(reportRepositoryProvider);
    final profileRepo = _ref.read(profileRepositoryProvider);
    
    int reportCount = 0;
    try {
      reportCount = await reportRepo.getReportCount(userId);
    } catch (e) {
      debugPrint('⚠️ [TrustService] Error fetching report count for $userId (possible permission denied): $e');
    }

    // Check for "Bad Actor" Vouch chain penalty (If you vouch for someone banned for fraud)
    final vouchees = await _repository.getVouchesByVoucher(userId);
    int bannedVoucheeCount = 0;
    for (final v in vouchees) {
      final voucheeProfile = await profileRepo.getUserProfile(v.toUserId);
      if (voucheeProfile?.isBanned == true) {
        bannedVoucheeCount++;
      }
    }

    double penaltyScore = 0;
    
    // Standardized Major Penalties: -10 PoCT (Refined Model)
    // 1. Unique Blocks (Every 10)
    final blockedByCount = profile.blockedByCount ?? 0;
    if (blockedByCount >= 10) {
      penaltyScore += (blockedByCount / 10).floor() * 10.0;
    }

    // 2. Unique Flags/Reports (Every 10)
    final flaggedMessagesCount = profile.flaggedMessagesCount ?? 0;
    if (flaggedMessagesCount >= 10) {
      penaltyScore += (flaggedMessagesCount / 10).floor() * 10.0;
    }

    // 3. One-off Major Breaches (-10 each)
    penaltyScore += (trustDataOld?.reportedFraudCount ?? 0) * 10.0;
    penaltyScore += (trustDataOld?.rejectedFamilyConnectionsCount ?? 0) * 10.0;
    penaltyScore += (trustDataOld?.fakeVerificationsCount ?? 0) * 10.0;
    penaltyScore += (trustDataOld?.eventNoShowCount ?? 0) * 10.0;
    penaltyScore += (bannedVoucheeCount * 10.0);

    // 4. Minor Breaches
    final unresponsiveCount = trustDataOld?.unresponsiveLiaisonCount ?? 0;
    penaltyScore += unresponsiveCount * 1.0; // -1 PoCT per instance

    // --- Verified Status Calculation ---
    bool isVerified = false;
    if (profile.isComplete) {
      // Check Field Verifications
      final allVerifications =
          await _repository.getAllVerificationsForUser(userId);

      // Map Field -> Set of Verifiers who said TRUE
      final Map<String, Set<String>> fieldVerifiers = {};

      for (final v in allVerifications) {
        final String verifierId = v['fromUserId'];
        final Map<String, dynamic> fields = v['fields'] ?? {};
        fields.forEach((key, val) {
          if (val == true) {
            // Verified TRUE
            fieldVerifiers.putIfAbsent(key, () => {}).add(verifierId);
          }
        });
      }

      // Required verified fields
      final requiredFields = [
        'First Name',
        'Last Name',
        'Profile Photo',
        'Home Town',
        'Current Host Town',
        'Bio',
        'Occupation',
        'Relatives',
      ];

      // Simplified Greedy Check:
      bool allFieldsCovered = requiredFields.every(
        (f) => fieldVerifiers.containsKey(f) && fieldVerifiers[f]!.isNotEmpty,
      );
      int uniqueVerifierCount =
          fieldVerifiers.values.expand((s) => s).toSet().length;

      // [NEW REQUIREMENT] At least 2 unrelated users vouching 100% on the trust slider
      int qualifiedVoucherCount = 0;

      for (final rating in ratingDetails) {
        final double score = (rating['score'] as num).toDouble();
        final String fromUid = rating['fromUserId'];

        if (score == 100.0) {
          // Check relationship status
          final bool isRelative = relationships.any(
            (r) =>
                r.id == fromUid &&
                r.status == 'active' &&
                (r.type == 'Relative' || r.type == 'Family'),
          );

          if (!isRelative) {
            qualifiedVoucherCount++;
          }
        }
      }

      if (allFieldsCovered &&
          uniqueVerifierCount >= requiredFields.length &&
          activeRelCount >= 2 &&
          qualifiedVoucherCount >= 2) {
        isVerified = true;
      }
    }

    // [NEW] QR Verification overrides everything
    if (hasQrExchange) {
      isVerified = true;
    }

    // 5. Final Formula
    // Identity(20) + Activity(20) + Reliability(20) + Helpfulness(20) + Reputation(20) = 100.

    final double automatedScore =
        identityScore +
        activityScore +
        reliabilityScore +
        helpfulnessScore +
        reputationScore;

    double finalScore = automatedScore;

    // [UPDATED] Peer Rating Consideration
    // Removed Weighted Average. Trust Score is purely automated.
    // Penalty logic handled in penalties section below.

    // [REMOVED] Verified Badge Guarantee (Now granular)
    // if (isVerified && finalScore < 80) {
    //   finalScore = 80;
    // }

    // Update isVerified boolean if finalScore is high and all conditions met
    isVerified = isVerified || finalScore >= 80;

    // Apply Penalties
    finalScore -= penaltyScore;

    // Ensure 0-100
    if (finalScore > 100) finalScore = 100;
    if (finalScore < 0) finalScore = 0;

    // 6. Status Determination (Purely PoCT Score Based)
    // [UPDATED] Thresholds based on Refined Model (DSP_EARNING_MODEL.md)
    TrustLevel level = TrustLevel.lowTrust;

    if (finalScore >= 81) {
      level = TrustLevel.highTrust;
    } else if (finalScore >= 61) {
      level = TrustLevel.standardTrust;
    } else if (finalScore >= 41) {
      level = TrustLevel.mediumTrust;
    } else if (finalScore >= 21) {
      level = TrustLevel.basicTrust;
    } else {
      level = TrustLevel.lowTrust;
    }
    
    // Note: To be a "High Trust Member" (Pillar) in UI, user usually needs 100+ PoCT, 
    // but the bracket starts at 91 for efficiency rates.

    // 7. Save
    final newTrustData = TrustData(
      uid: userId,
      trustScore: finalScore,
      level: level,
      isVerified: isVerified,
      identityScore: identityScore,
      activityScore: activityScore,
      reputationScore: reputationScore,
      vouchCount: vouches.length,
      lastUpdated: DateTime.now(),
      vouchedBy: vouches.map((v) => v.fromUserId).toList(),
      reviewCount: ratings.length,
      averageRating: averageRating,
      reportCount: reportCount,
      attendedEventsCount: attended,
      joinedEventsCount: joined,
      verifiedSolutionsCount: solutions,
      identityQRExchange: hasQrExchange,
      verifiedCheckInCount: trustDataOld?.verifiedCheckInCount ?? 0,
      reliabilityScore: reliabilityScore,
      helpfulnessScore: helpfulnessScore,
    );

    await _repository.saveTrustData(newTrustData);

    // 8. [NEW] Sync Score to UserPoints (for Leaderboard/Average)
    final pointsRepo = _ref.read(pointsRepositoryProvider);
    await pointsRepo.updateTrustScore(userId, finalScore);
    
    // 9. [NEW] Trigger Community Average Update
    if (profile.homeCountryCode != null) {
      await pointsRepo.updateCommunityOverallAveragePoCT(profile.homeCountryCode!);
      
      // Update Continent Average
      final continentCode = getContinentByCountryCode(profile.homeCountryCode!);
      await pointsRepo.updateContinentOverallAveragePoCT(continentCode);
      
      // Update Global Average
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
      await _repository.incrementAttendedEventsCount(userId);
    } else if (type == 'org') {
      await pointsService.trackOrganizationVetting(userId);
    }

    // 4. Update Trust Data
    await _repository.incrementVerifiedCheckInCount(userId);
    await updateTrustForUser(userId);
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
      debugPrint("❌ performQRExchange: fromProfile ($fromUid) is incomplete: $fromMissing");
      throw IncompleteProfileException(
        missingFields: fromMissing,
        isOwnProfile: true, // Assuming fromUid is always the executor
        message: "You must complete your profile before you can connect via QR.",
      );
    }

    final toMissing = toProfile.getMissingRequiredFields();
    if (toMissing.isNotEmpty) {
      debugPrint("❌ performQRExchange: toProfile ($toUid) is incomplete: $toMissing");
      throw IncompleteProfileException(
        missingFields: toMissing,
        isOwnProfile: false,
        message: "The other user must complete their profile before you can connect via QR.",
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
      debugPrint("⚠️ performQRExchange: Users already connected. Skipping reward logic.");
      throw AlreadyConnectedException(
        message: "You are already connected with this user.",
        otherUid: toUid,
      );
    }

    // 3. Save Records for both
    // Use a fallback for locationAddress if it's null but we want to know where it failed
    final savedAddress = locationAddress ?? "Location Unavailable";

    await _repository.saveQRExchangeRecord(fromUid, toUid,
        locationAddress: savedAddress);
    await _repository.saveQRExchangeRecord(toUid, fromUid,
        locationAddress: savedAddress);

    debugPrint("✅ performQRExchange: QR Exchange records saved with address: $savedAddress");

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
      await pointsService.trackIdentityQRExchange(fromUid, toUid, isServiceProvider: false);
    } else if (!toWasVerified) {
      scannerAward = 1000;
      await pointsService.trackIdentityQRExchange(fromUid, toUid, isServiceProvider: true);
    }

    // Award to TO (Scanned)
    if (!toWasVerified) {
      await pointsService.trackIdentityQRExchange(toUid, fromUid, isServiceProvider: false);
    } else if (!fromWasVerified) {
      await pointsService.trackIdentityQRExchange(toUid, fromUid, isServiceProvider: true);
    }

    debugPrint("✅ performQRExchange: DSP points awarded ($scannerAward to scanner).");

    // 7. Update Trust for both
    await updateTrustForUser(fromUid);
    await updateTrustForUser(toUid);

    debugPrint("✅ performQRExchange: Trust scores recalculated.");

    // 8. Invalidate Profile Cache
    _ref.invalidate(userProfileProvider);
    debugPrint("✅ performQRExchange: Profile provider invalidated. Scanner side complete.");
    
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
  }) =>
      _repository.saveVerificationEvent(
          fromUserId: fromUserId, toUserId: toUserId, fields: fields);

  Future<List<String>> getFlaggedFields(String userId) =>
      _repository.getFlaggedFields(userId);

  /// Checks if a user is eligible to verify another user.
  /// Returns null if allowed, otherwise returns a reason string.
  Future<String?> checkVerificationEligibility(String fromUserId, String toUserId) async {
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
    
    // 3. Check Relationships (Prevent related users from verifying each other)
    final relRepo = _ref.read(relationshipRepositoryProvider);
    final relationship = await relRepo.getRelationship(userId: fromUserId, relatedUserId: toUserId);
    if (relationship != null && relationship.status == 'active') {
       return 'You cannot verify a relative (Conflict of Interest).';
    }

    return null;
  }

  /// Checks if a user is eligible to vouch for another user.
  /// Returns null if allowed, otherwise returns a reason string.
  Future<String?> checkVouchEligibility(String fromUserId, String toUserId) async {
    // [NEW] Base PoCT Conditions
    // 4. Check Vouch Eligibility (Must be QR Verified - Level 3)
    final trustData = await _repository.getTrustData(fromUserId);
    bool isQrVerified = trustData?.identityQRExchange ?? false;

    if (!isQrVerified) {
       // Fallback: Check profile directly in case TrustData is stale
       final profile = await _ref.read(profileRepositoryProvider).getUserProfile(fromUserId);
       if (profile?.firstQrConnection != null) {
         isQrVerified = true;
       }
    }

    if (!isQrVerified) {
       return "You must be fully Identity Verified (QR Exchange) to vouch for others.";
    }

    // 1. Validation
    if (fromUserId == toUserId) return "Cannot vouch for yourself";

    final alreadyVouched = await _repository.hasVouched(fromUserId, toUserId);
    if (alreadyVouched) {
      return "You have already vouched for this user";
    }
    
    // 2. Check Relationships (Prevent related users from vouching for each other)
    final relRepo = _ref.read(relationshipRepositoryProvider);
    final relationship = await relRepo.getRelationship(userId: fromUserId, relatedUserId: toUserId);
    if (relationship != null && relationship.status == 'active') {
       return 'You cannot vouch for a relative (Conflict of Interest).';
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
    final allVerifications = await _repository.getAllVerificationsForUser(userId);
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
    final points = await _ref.read(pointsRepositoryProvider).getUserPoints(userId);
    final trust = await _repository.getTrustData(userId);
    
    if (points == null || trust == null) return false;
    
    final dsp = points.totalPoints;
    final poct = trust.trustScore;

    // Aligned with "100k Club" + "51 PoCT" gate strategy (Refined Model)
    const double gateDsp = 100000.0;
    const int gatePoct = 51; // Low Trust or higher can swap

    return dsp >= gateDsp && poct >= gatePoct;
  }

  Future<bool> checkCommunityTgeEligibility(String communityId, int epoch) async {
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
