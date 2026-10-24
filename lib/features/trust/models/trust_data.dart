import 'package:json_annotation/json_annotation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

part 'trust_data.g.dart';

enum TrustLevel {
  @JsonValue('lowTrust')
  lowTrust, // 0-20
  @JsonValue('basicTrust')
  basicTrust, // 21-40
  @JsonValue('mediumTrust')
  mediumTrust, // 41-60
  @JsonValue('standardTrust')
  standardTrust, // 61-80
  @JsonValue('highTrust')
  highTrust, // 81-100
}

extension TrustLevelExtension on TrustLevel {
  String get displayName {
    switch (this) {
      case TrustLevel.lowTrust:
        return 'Low Trust';
      case TrustLevel.basicTrust:
        return 'Basic Trust';
      case TrustLevel.mediumTrust:
        return 'Medium Trust';
      case TrustLevel.standardTrust:
        return 'Standard Trust';
      case TrustLevel.highTrust:
        return 'High Trust';
    }
  }

  static TrustLevel fromScore(double score) {
    if (score >= 81) return TrustLevel.highTrust;
    if (score >= 61) return TrustLevel.standardTrust;
    if (score >= 41) return TrustLevel.mediumTrust;
    if (score >= 21) return TrustLevel.basicTrust;
    return TrustLevel.lowTrust;
  }
}

@JsonSerializable(explicitToJson: true)
class TrustData {
  final String uid;

  // Scores
  final double trustScore; // 0-100
  final TrustLevel level;
  final bool isVerified;

  // Component Scores (stored for transparency)
  final double identityScore;
  final double activityScore;
  final double vouchTrustScore;

  // Trust Metrics
  final int vouchCount;
  final int reviewCount;
  final double averageRating;
  final int reportCount; // Negative signal
  final int blockedByCount; // [NEW] -10 PCT for every 10 unique blocks
  final int flaggedMessagesCount; // [NEW] -10 PCT for every 10 unique flags
  final int
  bannedVoucheeCount; // [NEW] -10 PCT if someone you vouched for is banned
  final int
  fakeVerificationsCount; // [NEW] -10 PCT for every 10 fake verifications

  // [NEW] Reliability & Helpfulness metrics
  final int attendedEventsCount;
  final int joinedEventsCount;
  final int verifiedSolutionsCount;
  final bool identityQRExchange;

  // [NEW] Council Eligibility Metrics
  final int uniqueFamilyCount;
  final int uniqueFriendCount; // [NEW] Non-family relationship connections
  final int uniqueQrCount;
  final int uniqueVouchCount;
  final int uniqueVerificationCount; // [NEW] 10 standard verifications
  final int verifiedByCount; // How many peers verified this user
  final int vouchedByCount; // How many peers vouched for this user
  final bool isCouncilEligible;
  final bool
  isDdiEligible; // [NEW] 7 Genesis Milestones + 100+ days active + PCT 91+
  final List<String> awardedQualificationMilestones; // [NEW] Track awards
  final int verifiedCheckInCount;
  final int unresponsiveLiaisonCount;
  final int rejectedFamilyConnectionsCount; // [NEW] -10 PCT

  final int eventNoShowCount; // [NEW] -10 PCT
  final int reportedFraudCount; // [NEW] -10 PCT
  final int referralCount; // [NEW] +1 PCT per 10 referrals (linear)
  final bool
  hasReceivedPohTokenDistribution; // 7,000 DSP Genesis conversion to on-chain $DIASPORA

  // [NEW] Ledger for already awarded/penalized HTS units (sets of 10)
  final Map<String, int> awardedHtsTracking;

  // Components (Physical/Behavioral)
  final double reliabilityScore; // (attended/joined) * 100
  final double helpfulnessScore; // Based on verified solutions

  // Context
  final DateTime lastUpdated;

  // Vouching
  final List<String> vouchedBy; // UIDs of users who vouched for this user
  final List<String>
  fullTrustVoterIds; // UIDs of users who gave full trust (90-100)
  final List<String> noTrustVoterIds; // UIDs of users who gave no trust (0-10)

  // [NEW] Genesis Milestone qualifying IDs (deduplicated, max 10 each)
  final List<String> genesisFamilyIds;
  final List<String> genesisFriendIds;
  final List<String> genesisQrIds;
  final List<String> genesisTrustIds;
  final List<String> genesisVerificationIds;
  final List<String> genesisVouchIds;
  final Map<String, String> relationshipTypes;

  TrustData({
    required this.uid,
    this.trustScore = 0.0,
    this.level = TrustLevel.lowTrust,
    this.isVerified = false,
    this.identityScore = 0.0,
    this.activityScore = 0.0,
    this.vouchTrustScore = 0.0,
    this.vouchCount = 0,
    this.reviewCount = 0,
    this.averageRating = 0.0,
    this.reportCount = 0,
    this.attendedEventsCount = 0,
    this.joinedEventsCount = 0,
    this.verifiedSolutionsCount = 0,
    this.identityQRExchange = false,
    this.uniqueFamilyCount = 0,
    this.uniqueFriendCount = 0,
    this.uniqueQrCount = 0,
    this.uniqueVouchCount = 0,
    this.uniqueVerificationCount = 0,
    this.verifiedByCount = 0,
    this.vouchedByCount = 0,
    this.isCouncilEligible = false,
    this.isDdiEligible = false,
    this.hasReceivedPohTokenDistribution = false,
    this.awardedQualificationMilestones = const [],
    this.verifiedCheckInCount = 0,
    this.unresponsiveLiaisonCount = 0,
    this.reliabilityScore = 0.0,
    this.helpfulnessScore = 0.0,
    this.blockedByCount = 0,
    this.flaggedMessagesCount = 0,
    this.bannedVoucheeCount = 0,
    this.fakeVerificationsCount = 0,
    this.rejectedFamilyConnectionsCount = 0,

    this.eventNoShowCount = 0,
    this.reportedFraudCount = 0,
    this.referralCount = 0,
    this.awardedHtsTracking = const {},
    required this.lastUpdated,
    this.vouchedBy = const [],
    this.fullTrustVoterIds = const [],
    this.noTrustVoterIds = const [],
    this.genesisFamilyIds = const [],
    this.genesisFriendIds = const [],
    this.genesisQrIds = const [],
    this.genesisTrustIds = const [],
    this.genesisVerificationIds = const [],
    this.genesisVouchIds = const [],
    this.relationshipTypes = const {},
  });

  factory TrustData.fromJson(Map<String, dynamic> json) {
    final normalized = Map<String, dynamic>.from(json);
    if (normalized['lastUpdated'] is Timestamp) {
      normalized['lastUpdated'] = (normalized['lastUpdated'] as Timestamp)
          .toDate()
          .toIso8601String();
    } else if (normalized['lastUpdated'] is! String) {
      normalized['lastUpdated'] = DateTime.now().toIso8601String();
    }
    return _$TrustDataFromJson(normalized);
  }

  Map<String, dynamic> toJson() => _$TrustDataToJson(this);

  TrustData copyWith({
    String? uid,
    double? trustScore,
    TrustLevel? level,
    bool? isVerified,
    double? identityScore,
    double? activityScore,
    double? vouchTrustScore,
    int? vouchCount,
    int? reviewCount,
    double? averageRating,
    int? reportCount,
    int? attendedEventsCount,
    int? joinedEventsCount,
    int? verifiedSolutionsCount,
    bool? identityQRExchange,
    int? uniqueFamilyCount,
    int? uniqueFriendCount,
    int? uniqueQrCount,
    int? uniqueVouchCount,
    int? uniqueVerificationCount,
    int? verifiedByCount,
    int? vouchedByCount,
    bool? isCouncilEligible,
    bool? isDdiEligible,
    bool? hasReceivedPohTokenDistribution,
    List<String>? awardedQualificationMilestones,
    int? verifiedCheckInCount,
    int? unresponsiveLiaisonCount,
    double? reliabilityScore,
    double? helpfulnessScore,
    DateTime? lastUpdated,
    List<String>? vouchedBy,
    List<String>? fullTrustVoterIds,
    List<String>? noTrustVoterIds,
    List<String>? genesisFamilyIds,
    List<String>? genesisFriendIds,
    List<String>? genesisQrIds,
    List<String>? genesisTrustIds,
    List<String>? genesisVerificationIds,
    List<String>? genesisVouchIds,
    Map<String, String>? relationshipTypes,
    int? blockedByCount,
    int? flaggedMessagesCount,
    int? bannedVoucheeCount,
    int? fakeVerificationsCount,
    int? rejectedFamilyConnectionsCount,

    int? eventNoShowCount,
    int? reportedFraudCount,
    int? referralCount,
    Map<String, int>? awardedHtsTracking,
  }) {
    return TrustData(
      uid: uid ?? this.uid,
      trustScore: trustScore ?? this.trustScore,
      level: level ?? this.level,
      isVerified: isVerified ?? this.isVerified,
      identityScore: identityScore ?? this.identityScore,
      activityScore: activityScore ?? this.activityScore,
      vouchTrustScore: vouchTrustScore ?? this.vouchTrustScore,
      vouchCount: vouchCount ?? this.vouchCount,
      reviewCount: reviewCount ?? this.reviewCount,
      averageRating: averageRating ?? this.averageRating,
      reportCount: reportCount ?? this.reportCount,
      attendedEventsCount: attendedEventsCount ?? this.attendedEventsCount,
      joinedEventsCount: joinedEventsCount ?? this.joinedEventsCount,
      verifiedSolutionsCount:
          verifiedSolutionsCount ?? this.verifiedSolutionsCount,
      identityQRExchange: identityQRExchange ?? this.identityQRExchange,
      uniqueFamilyCount: uniqueFamilyCount ?? this.uniqueFamilyCount,
      uniqueFriendCount: uniqueFriendCount ?? this.uniqueFriendCount,
      uniqueQrCount: uniqueQrCount ?? this.uniqueQrCount,
      uniqueVouchCount: uniqueVouchCount ?? this.uniqueVouchCount,
      uniqueVerificationCount:
          uniqueVerificationCount ?? this.uniqueVerificationCount,
      verifiedByCount: verifiedByCount ?? this.verifiedByCount,
      vouchedByCount: vouchedByCount ?? this.vouchedByCount,
      isCouncilEligible: isCouncilEligible ?? this.isCouncilEligible,
      isDdiEligible: isDdiEligible ?? this.isDdiEligible,
      hasReceivedPohTokenDistribution:
          hasReceivedPohTokenDistribution ??
          this.hasReceivedPohTokenDistribution,
      awardedQualificationMilestones:
          awardedQualificationMilestones ?? this.awardedQualificationMilestones,
      verifiedCheckInCount: verifiedCheckInCount ?? this.verifiedCheckInCount,
      unresponsiveLiaisonCount:
          unresponsiveLiaisonCount ?? this.unresponsiveLiaisonCount,
      reliabilityScore: reliabilityScore ?? this.reliabilityScore,
      helpfulnessScore: helpfulnessScore ?? this.helpfulnessScore,
      lastUpdated: lastUpdated ?? this.lastUpdated,
      vouchedBy: vouchedBy ?? this.vouchedBy,
      fullTrustVoterIds: fullTrustVoterIds ?? this.fullTrustVoterIds,
      noTrustVoterIds: noTrustVoterIds ?? this.noTrustVoterIds,
      genesisFamilyIds: genesisFamilyIds ?? this.genesisFamilyIds,
      genesisFriendIds: genesisFriendIds ?? this.genesisFriendIds,
      genesisQrIds: genesisQrIds ?? this.genesisQrIds,
      genesisTrustIds: genesisTrustIds ?? this.genesisTrustIds,
      genesisVerificationIds:
          genesisVerificationIds ?? this.genesisVerificationIds,
      genesisVouchIds: genesisVouchIds ?? this.genesisVouchIds,
      relationshipTypes: relationshipTypes ?? this.relationshipTypes,
      blockedByCount: blockedByCount ?? this.blockedByCount,
      flaggedMessagesCount: flaggedMessagesCount ?? this.flaggedMessagesCount,
      bannedVoucheeCount: bannedVoucheeCount ?? this.bannedVoucheeCount,
      fakeVerificationsCount:
          fakeVerificationsCount ?? this.fakeVerificationsCount,
      rejectedFamilyConnectionsCount:
          rejectedFamilyConnectionsCount ?? this.rejectedFamilyConnectionsCount,

      eventNoShowCount: eventNoShowCount ?? this.eventNoShowCount,
      reportedFraudCount: reportedFraudCount ?? this.reportedFraudCount,
      referralCount: referralCount ?? this.referralCount,
      awardedHtsTracking: awardedHtsTracking ?? this.awardedHtsTracking,
    );
  }
}

@JsonSerializable(explicitToJson: true)
class Vouch {
  final String id;
  final String fromUserId;
  final String toUserId;
  final String relationship; // e.g., "neighbor", "colleague", "friend"
  final int stakeAmount; // Amount of DSP staked (if any)
  final DateTime createdAt;

  Vouch({
    required this.id,
    required this.fromUserId,
    required this.toUserId,
    required this.relationship,
    this.stakeAmount = 0,
    required this.createdAt,
  });

  factory Vouch.fromJson(Map<String, dynamic> json) {
    if (json['createdAt'] is Timestamp) {
      json['createdAt'] = (json['createdAt'] as Timestamp)
          .toDate()
          .toIso8601String();
    }
    return _$VouchFromJson(json);
  }

  Map<String, dynamic> toJson() => _$VouchToJson(this);
}
