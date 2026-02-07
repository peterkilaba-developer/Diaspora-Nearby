// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'governance_unit.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

GovernanceUnit _$GovernanceUnitFromJson(Map<String, dynamic> json) =>
    GovernanceUnit(
      id: json['id'] as String,
      name: json['name'] as String,
      communityId: json['communityId'] as String?,
      level: $enumDecodeNullable(_$GovernanceLevelEnumMap, json['level']) ??
          GovernanceLevel.local,
      type: $enumDecode(_$GovernanceTypeEnumMap, json['type']),
      walletAddress: json['walletAddress'] as String?,
      signers: (json['signers'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
      councilMembers: (json['councilMembers'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
      requiredSignatures: (json['requiredSignatures'] as num?)?.toInt() ?? 3,
      totalPillars: (json['totalPillars'] as num?)?.toInt() ?? 0,
      lastElectionAt: (json['lastElectionAt'] as num?)?.toInt(),
      nextElectionAt: (json['nextElectionAt'] as num?)?.toInt(),
      treasuryBalance: (json['treasuryBalance'] as num?)?.toDouble() ?? 0,
      isActiveElection: json['isActiveElection'] as bool? ?? false,
      electionEndTime: (json['electionEndTime'] as num?)?.toInt(),
    );

Map<String, dynamic> _$GovernanceUnitToJson(GovernanceUnit instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'communityId': instance.communityId,
      'level': _$GovernanceLevelEnumMap[instance.level]!,
      'type': _$GovernanceTypeEnumMap[instance.type]!,
      'walletAddress': instance.walletAddress,
      'signers': instance.signers,
      'councilMembers': instance.councilMembers,
      'requiredSignatures': instance.requiredSignatures,
      'totalPillars': instance.totalPillars,
      'lastElectionAt': instance.lastElectionAt,
      'nextElectionAt': instance.nextElectionAt,
      'treasuryBalance': instance.treasuryBalance,
      'isActiveElection': instance.isActiveElection,
      'electionEndTime': instance.electionEndTime,
    };

const _$GovernanceLevelEnumMap = {
  GovernanceLevel.local: 'local',
  GovernanceLevel.state: 'state',
  GovernanceLevel.country: 'country',
  GovernanceLevel.continent: 'continent',
  GovernanceLevel.global: 'global',
};

const _$GovernanceTypeEnumMap = {
  GovernanceType.country: 'country',
  GovernanceType.continent: 'continent',
  GovernanceType.global: 'global',
  GovernanceType.local: 'local',
  GovernanceType.state: 'state',
};
