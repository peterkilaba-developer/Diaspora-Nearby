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
  final double reputationScore;

  // Reputation Metrics
  final int vouchCount;
  final int reviewCount;
  final double averageRating;
  final int reportCount; // Negative signal
  final int blockedByCount; // [NEW] -10 PoCT for every 10 unique blocks
  final int flaggedMessagesCount; // [NEW] -10 PoCT for every 10 unique flags
  final int bannedVoucheeCount; // [NEW] -10 PoCT if someone you vouched for is banned

  // [NEW] Reliability & Helpfulness metrics
  final int attendedEventsCount;
  final int joinedEventsCount;
  final int verifiedSolutionsCount;
  final bool identityQRExchange;
  final int verifiedCheckInCount;
  final int unresponsiveLiaisonCount;
  final int rejectedFamilyConnectionsCount; // [NEW] -10 PoCT
  final int fakeVerificationsCount; // [NEW] -10 PoCT
  final int eventNoShowCount; // [NEW] -10 PoCT
  final int reportedFraudCount; // [NEW] -10 PoCT

  // Components (Physical/Behavioral)
  final double reliabilityScore; // (attended/joined) * 100
  final double helpfulnessScore; // Based on verified solutions

  // Context
  final DateTime lastUpdated;

  // Vouching
  final List<String> vouchedBy; // UIDs of users who vouched for this user

  TrustData({
    required this.uid,
    this.trustScore = 0.0,
    this.level = TrustLevel.lowTrust,
    this.isVerified = false,
    this.identityScore = 0.0,
    this.activityScore = 0.0,
    this.reputationScore = 0.0,
    this.vouchCount = 0,
    this.reviewCount = 0,
    this.averageRating = 0.0,
    this.reportCount = 0,
    this.attendedEventsCount = 0,
    this.joinedEventsCount = 0,
    this.verifiedSolutionsCount = 0,
    this.identityQRExchange = false,
    this.verifiedCheckInCount = 0,
    this.unresponsiveLiaisonCount = 0,
    this.reliabilityScore = 0.0,
    this.helpfulnessScore = 0.0,
    this.blockedByCount = 0,
    this.flaggedMessagesCount = 0,
    this.bannedVoucheeCount = 0,
    this.rejectedFamilyConnectionsCount = 0,
    this.fakeVerificationsCount = 0,
    this.eventNoShowCount = 0,
    this.reportedFraudCount = 0,
    required this.lastUpdated,
    this.vouchedBy = const [],
  });

  factory TrustData.fromJson(Map<String, dynamic> json) {
    if (json['lastUpdated'] is Timestamp) {
      json['lastUpdated'] = (json['lastUpdated'] as Timestamp)
          .toDate()
          .toIso8601String();
    }
    return _$TrustDataFromJson(json);
  }

  Map<String, dynamic> toJson() => _$TrustDataToJson(this);

  TrustData copyWith({
    String? uid,
    double? trustScore,
    TrustLevel? level,
    bool? isVerified,
    double? identityScore,
    double? activityScore,
    double? reputationScore,
    int? vouchCount,
    int? reviewCount,
    double? averageRating,
    int? reportCount,
    int? attendedEventsCount,
    int? joinedEventsCount,
    int? verifiedSolutionsCount,
    bool? identityQRExchange,
    int? verifiedCheckInCount,
    int? unresponsiveLiaisonCount,
    double? reliabilityScore,
    double? helpfulnessScore,
    DateTime? lastUpdated,
    List<String>? vouchedBy,
    int? blockedByCount,
    int? flaggedMessagesCount,
    int? bannedVoucheeCount,
    int? rejectedFamilyConnectionsCount,
    int? fakeVerificationsCount,
    int? eventNoShowCount,
    int? reportedFraudCount,
  }) {
    return TrustData(
      uid: uid ?? this.uid,
      trustScore: trustScore ?? this.trustScore,
      level: level ?? this.level,
      isVerified: isVerified ?? this.isVerified,
      identityScore: identityScore ?? this.identityScore,
      activityScore: activityScore ?? this.activityScore,
      reputationScore: reputationScore ?? this.reputationScore,
      vouchCount: vouchCount ?? this.vouchCount,
      reviewCount: reviewCount ?? this.reviewCount,
      averageRating: averageRating ?? this.averageRating,
      reportCount: reportCount ?? this.reportCount,
      attendedEventsCount: attendedEventsCount ?? this.attendedEventsCount,
      joinedEventsCount: joinedEventsCount ?? this.joinedEventsCount,
      verifiedSolutionsCount:
          verifiedSolutionsCount ?? this.verifiedSolutionsCount,
      identityQRExchange: identityQRExchange ?? this.identityQRExchange,
      verifiedCheckInCount: verifiedCheckInCount ?? this.verifiedCheckInCount,
      unresponsiveLiaisonCount: unresponsiveLiaisonCount ?? this.unresponsiveLiaisonCount,
      reliabilityScore: reliabilityScore ?? this.reliabilityScore,
      helpfulnessScore: helpfulnessScore ?? this.helpfulnessScore,
      lastUpdated: lastUpdated ?? this.lastUpdated,
      vouchedBy: vouchedBy ?? this.vouchedBy,
      blockedByCount: blockedByCount ?? this.blockedByCount,
      flaggedMessagesCount: flaggedMessagesCount ?? this.flaggedMessagesCount,
      bannedVoucheeCount: bannedVoucheeCount ?? this.bannedVoucheeCount,
      rejectedFamilyConnectionsCount: rejectedFamilyConnectionsCount ?? this.rejectedFamilyConnectionsCount,
      fakeVerificationsCount: fakeVerificationsCount ?? this.fakeVerificationsCount,
      eventNoShowCount: eventNoShowCount ?? this.eventNoShowCount,
      reportedFraudCount: reportedFraudCount ?? this.reportedFraudCount,
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
