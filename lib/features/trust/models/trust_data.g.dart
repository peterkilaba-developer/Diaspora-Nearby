// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'trust_data.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

TrustData _$TrustDataFromJson(Map<String, dynamic> json) => TrustData(
  uid: json['uid'] as String,
  trustScore: (json['trustScore'] as num?)?.toDouble() ?? 0.0,
  level:
      $enumDecodeNullable(_$TrustLevelEnumMap, json['level']) ??
      TrustLevel.lowTrust,
  isVerified: json['isVerified'] as bool? ?? false,
  identityScore: (json['identityScore'] as num?)?.toDouble() ?? 0.0,
  activityScore: (json['activityScore'] as num?)?.toDouble() ?? 0.0,
  reputationScore: (json['reputationScore'] as num?)?.toDouble() ?? 0.0,
  vouchCount: (json['vouchCount'] as num?)?.toInt() ?? 0,
  reviewCount: (json['reviewCount'] as num?)?.toInt() ?? 0,
  averageRating: (json['averageRating'] as num?)?.toDouble() ?? 0.0,
  reportCount: (json['reportCount'] as num?)?.toInt() ?? 0,
  attendedEventsCount: (json['attendedEventsCount'] as num?)?.toInt() ?? 0,
  joinedEventsCount: (json['joinedEventsCount'] as num?)?.toInt() ?? 0,
  verifiedSolutionsCount:
      (json['verifiedSolutionsCount'] as num?)?.toInt() ?? 0,
  identityQRExchange: json['identityQRExchange'] as bool? ?? false,
  uniqueFamilyCount: (json['uniqueFamilyCount'] as num?)?.toInt() ?? 0,
  uniqueFriendCount: (json['uniqueFriendCount'] as num?)?.toInt() ?? 0,
  uniqueQrCount: (json['uniqueQrCount'] as num?)?.toInt() ?? 0,
  uniqueVouchCount: (json['uniqueVouchCount'] as num?)?.toInt() ?? 0,
  uniqueVerificationCount:
      (json['uniqueVerificationCount'] as num?)?.toInt() ?? 0,
  verifiedByCount: (json['verifiedByCount'] as num?)?.toInt() ?? 0,
  vouchedByCount: (json['vouchedByCount'] as num?)?.toInt() ?? 0,
  isCouncilEligible: json['isCouncilEligible'] as bool? ?? false,
  awardedQualificationMilestones:
      (json['awardedQualificationMilestones'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList() ??
      const [],
  verifiedCheckInCount: (json['verifiedCheckInCount'] as num?)?.toInt() ?? 0,
  unresponsiveLiaisonCount:
      (json['unresponsiveLiaisonCount'] as num?)?.toInt() ?? 0,
  reliabilityScore: (json['reliabilityScore'] as num?)?.toDouble() ?? 0.0,
  helpfulnessScore: (json['helpfulnessScore'] as num?)?.toDouble() ?? 0.0,
  blockedByCount: (json['blockedByCount'] as num?)?.toInt() ?? 0,
  flaggedMessagesCount: (json['flaggedMessagesCount'] as num?)?.toInt() ?? 0,
  bannedVoucheeCount: (json['bannedVoucheeCount'] as num?)?.toInt() ?? 0,
  rejectedFamilyConnectionsCount:
      (json['rejectedFamilyConnectionsCount'] as num?)?.toInt() ?? 0,
  fakeVerificationsCount:
      (json['fakeVerificationsCount'] as num?)?.toInt() ?? 0,
  eventNoShowCount: (json['eventNoShowCount'] as num?)?.toInt() ?? 0,
  reportedFraudCount: (json['reportedFraudCount'] as num?)?.toInt() ?? 0,
  referralCount: (json['referralCount'] as num?)?.toInt() ?? 0,
  awardedHtsTracking:
      (json['awardedHtsTracking'] as Map<String, dynamic>?)?.map(
        (k, e) => MapEntry(k, (e as num).toInt()),
      ) ??
      const {},
  lastUpdated: DateTime.parse(json['lastUpdated'] as String),
  vouchedBy:
      (json['vouchedBy'] as List<dynamic>?)?.map((e) => e as String).toList() ??
      const [],
  genesisFamilyIds:
      (json['genesisFamilyIds'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList() ??
      const [],
  genesisFriendIds:
      (json['genesisFriendIds'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList() ??
      const [],
  genesisQrIds:
      (json['genesisQrIds'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList() ??
      const [],
  genesisTrustIds:
      (json['genesisTrustIds'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList() ??
      const [],
);

Map<String, dynamic> _$TrustDataToJson(TrustData instance) => <String, dynamic>{
  'uid': instance.uid,
  'trustScore': instance.trustScore,
  'level': _$TrustLevelEnumMap[instance.level]!,
  'isVerified': instance.isVerified,
  'identityScore': instance.identityScore,
  'activityScore': instance.activityScore,
  'reputationScore': instance.reputationScore,
  'vouchCount': instance.vouchCount,
  'reviewCount': instance.reviewCount,
  'averageRating': instance.averageRating,
  'reportCount': instance.reportCount,
  'blockedByCount': instance.blockedByCount,
  'flaggedMessagesCount': instance.flaggedMessagesCount,
  'bannedVoucheeCount': instance.bannedVoucheeCount,
  'attendedEventsCount': instance.attendedEventsCount,
  'joinedEventsCount': instance.joinedEventsCount,
  'verifiedSolutionsCount': instance.verifiedSolutionsCount,
  'identityQRExchange': instance.identityQRExchange,
  'uniqueFamilyCount': instance.uniqueFamilyCount,
  'uniqueFriendCount': instance.uniqueFriendCount,
  'uniqueQrCount': instance.uniqueQrCount,
  'uniqueVouchCount': instance.uniqueVouchCount,
  'uniqueVerificationCount': instance.uniqueVerificationCount,
  'verifiedByCount': instance.verifiedByCount,
  'vouchedByCount': instance.vouchedByCount,
  'isCouncilEligible': instance.isCouncilEligible,
  'awardedQualificationMilestones': instance.awardedQualificationMilestones,
  'verifiedCheckInCount': instance.verifiedCheckInCount,
  'unresponsiveLiaisonCount': instance.unresponsiveLiaisonCount,
  'rejectedFamilyConnectionsCount': instance.rejectedFamilyConnectionsCount,
  'fakeVerificationsCount': instance.fakeVerificationsCount,
  'eventNoShowCount': instance.eventNoShowCount,
  'reportedFraudCount': instance.reportedFraudCount,
  'referralCount': instance.referralCount,
  'awardedHtsTracking': instance.awardedHtsTracking,
  'reliabilityScore': instance.reliabilityScore,
  'helpfulnessScore': instance.helpfulnessScore,
  'lastUpdated': instance.lastUpdated.toIso8601String(),
  'vouchedBy': instance.vouchedBy,
  'genesisFamilyIds': instance.genesisFamilyIds,
  'genesisFriendIds': instance.genesisFriendIds,
  'genesisQrIds': instance.genesisQrIds,
  'genesisTrustIds': instance.genesisTrustIds,
};

const _$TrustLevelEnumMap = {
  TrustLevel.lowTrust: 'lowTrust',
  TrustLevel.basicTrust: 'basicTrust',
  TrustLevel.mediumTrust: 'mediumTrust',
  TrustLevel.standardTrust: 'standardTrust',
  TrustLevel.highTrust: 'highTrust',
};

Vouch _$VouchFromJson(Map<String, dynamic> json) => Vouch(
  id: json['id'] as String,
  fromUserId: json['fromUserId'] as String,
  toUserId: json['toUserId'] as String,
  relationship: json['relationship'] as String,
  stakeAmount: (json['stakeAmount'] as num?)?.toInt() ?? 0,
  createdAt: DateTime.parse(json['createdAt'] as String),
);

Map<String, dynamic> _$VouchToJson(Vouch instance) => <String, dynamic>{
  'id': instance.id,
  'fromUserId': instance.fromUserId,
  'toUserId': instance.toUserId,
  'relationship': instance.relationship,
  'stakeAmount': instance.stakeAmount,
  'createdAt': instance.createdAt.toIso8601String(),
};
