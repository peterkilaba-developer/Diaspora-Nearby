import 'package:json_annotation/json_annotation.dart';

part 'governance_unit.g.dart';

enum GovernanceType { country, continent, global, local, state }
enum GovernanceLevel { local, state, country, continent, global }

@JsonSerializable()
class GovernanceUnit {
  final String id;
  final String name;
  final String? communityId; // Link to the community
  final GovernanceLevel level;
  final GovernanceType type; // Deprecated or mapped to level
  final String? walletAddress;
  final List<String> signers;
  final List<String> councilMembers;
  final int requiredSignatures;
  final int totalPillars;
  final int? lastElectionAt;
  final int? nextElectionAt;
  final double treasuryBalance; // In $DSP
  final bool isActiveElection;
  final int? electionEndTime;

  GovernanceUnit({
    required this.id,
    required this.name,
    this.communityId,
    this.level = GovernanceLevel.local,
    required this.type,
    this.walletAddress,
    this.signers = const [],
    this.councilMembers = const [],
    this.requiredSignatures = 3,
    this.totalPillars = 0,
    this.lastElectionAt,
    this.nextElectionAt,
    this.treasuryBalance = 0,
    this.isActiveElection = false,
    this.electionEndTime,
  });

  factory GovernanceUnit.fromJson(Map<String, dynamic> json) =>
      _$GovernanceUnitFromJson(json);

  Map<String, dynamic> toJson() => _$GovernanceUnitToJson(this);

  GovernanceUnit copyWith({
    String? id,
    String? name,
    String? communityId,
    GovernanceLevel? level,
    GovernanceType? type,
    String? walletAddress,
    List<String>? signers,
    List<String>? councilMembers,
    int? requiredSignatures,
    int? totalPillars,
    int? lastElectionAt,
    int? nextElectionAt,
    double? treasuryBalance,
    bool? isActiveElection,
    int? electionEndTime,
  }) {
    return GovernanceUnit(
      id: id ?? this.id,
      name: name ?? this.name,
      communityId: communityId ?? this.communityId,
      level: level ?? this.level,
      type: type ?? this.type,
      walletAddress: walletAddress ?? this.walletAddress,
      signers: signers ?? this.signers,
      councilMembers: councilMembers ?? this.councilMembers,
      requiredSignatures: requiredSignatures ?? this.requiredSignatures,
      totalPillars: totalPillars ?? this.totalPillars,
      lastElectionAt: lastElectionAt ?? this.lastElectionAt,
      nextElectionAt: nextElectionAt ?? this.nextElectionAt,
      treasuryBalance: treasuryBalance ?? this.treasuryBalance,
      isActiveElection: isActiveElection ?? this.isActiveElection,
      electionEndTime: electionEndTime ?? this.electionEndTime,
    );
  }

  bool get isTreasuryBearing => level.index >= GovernanceLevel.country.index;
}
