import 'package:json_annotation/json_annotation.dart';

part 'election_result.g.dart';

@JsonSerializable()
class ElectionResult {
  final String id;
  final String unitId;
  final String unitName;
  final int timestamp; // Milliseconds since epoch
  final List<String> winners; // Selected signers
  final Map<String, int> tally; // CandidateID -> VoteCount
  final int totalVotes;

  ElectionResult({
    required this.id,
    required this.unitId,
    required this.unitName,
    required this.timestamp,
    required this.winners,
    required this.tally,
    required this.totalVotes,
  });

  factory ElectionResult.fromJson(Map<String, dynamic> json) =>
      _$ElectionResultFromJson(json);

  Map<String, dynamic> toJson() => _$ElectionResultToJson(this);
}
