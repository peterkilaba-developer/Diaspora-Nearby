// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'election_result.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ElectionResult _$ElectionResultFromJson(Map<String, dynamic> json) =>
    ElectionResult(
      id: json['id'] as String,
      unitId: json['unitId'] as String,
      unitName: json['unitName'] as String,
      timestamp: (json['timestamp'] as num).toInt(),
      winners: (json['winners'] as List<dynamic>)
          .map((e) => e as String)
          .toList(),
      tally: Map<String, int>.from(json['tally'] as Map),
      totalVotes: (json['totalVotes'] as num).toInt(),
    );

Map<String, dynamic> _$ElectionResultToJson(ElectionResult instance) =>
    <String, dynamic>{
      'id': instance.id,
      'unitId': instance.unitId,
      'unitName': instance.unitName,
      'timestamp': instance.timestamp,
      'winners': instance.winners,
      'tally': instance.tally,
      'totalVotes': instance.totalVotes,
    };
