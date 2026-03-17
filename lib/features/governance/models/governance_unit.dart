enum GovernanceType { country, continent, global, local, state }

enum GovernanceLevel { local, state, country, continent, global }

class GovernanceUnit {
  final String id;
  final String name;
  final String? communityId; // Link to the community
  final GovernanceLevel level;
  final GovernanceType type; // Deprecated or mapped to level
  final String? walletAddress;
  final List<String> signers;
  final List<String> councilMembers;
  final List<String>
  candidateIds; // [LEGACY] Users who registered as candidates
  final Map<String, String> councilRoles; // userId -> role (President, etc)
  final Map<String, List<String>>
  roleCandidates; // [NEW] role -> [userId1, userId2] — candidates per role
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
    this.candidateIds = const [],
    this.councilRoles = const {},
    this.roleCandidates = const {},
    this.requiredSignatures = 3,
    this.totalPillars = 0,
    this.lastElectionAt,
    this.nextElectionAt,
    this.treasuryBalance = 0,
    this.isActiveElection = false,
    this.electionEndTime,
  });

  factory GovernanceUnit.fromJson(Map<String, dynamic> json) {
    return GovernanceUnit(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'Unknown Unit',
      communityId: json['communityId'] as String?,
      level: _parseGovernanceLevel(json['level']),
      type: _parseGovernanceType(json['type']),
      walletAddress: json['walletAddress'] as String?,
      signers: (json['signers'] as List<dynamic>?)?.cast<String>() ?? [],
      councilMembers:
          (json['councilMembers'] as List<dynamic>?)?.cast<String>() ?? [],
      candidateIds:
          (json['candidateIds'] as List<dynamic>?)?.cast<String>() ?? [],
      councilRoles:
          (json['councilRoles'] as Map<dynamic, dynamic>?)
              ?.cast<String, String>() ??
          {},
      roleCandidates: _parseRoleCandidates(json['roleCandidates']),
      requiredSignatures: json['requiredSignatures'] as int? ?? 3,
      totalPillars: json['totalPillars'] as int? ?? 0,
      lastElectionAt: json['lastElectionAt'] as int?,
      nextElectionAt: json['nextElectionAt'] as int?,
      treasuryBalance: (json['treasuryBalance'] as num? ?? 0).toDouble(),
      isActiveElection: json['isActiveElection'] as bool? ?? false,
      electionEndTime: json['electionEndTime'] as int?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'communityId': communityId,
      'level': level.index,
      'type': type.index,
      'walletAddress': walletAddress,
      'signers': signers,
      'councilMembers': councilMembers,
      'candidateIds': candidateIds,
      'councilRoles': councilRoles,
      'roleCandidates': roleCandidates.map((k, v) => MapEntry(k, v)),
      'requiredSignatures': requiredSignatures,
      'totalPillars': totalPillars,
      'lastElectionAt': lastElectionAt,
      'nextElectionAt': nextElectionAt,
      'treasuryBalance': treasuryBalance,
      'isActiveElection': isActiveElection,
      'electionEndTime': electionEndTime,
    };
  }

  GovernanceUnit copyWith({
    String? id,
    String? name,
    String? communityId,
    GovernanceLevel? level,
    GovernanceType? type,
    String? walletAddress,
    List<String>? signers,
    List<String>? councilMembers,
    List<String>? candidateIds,
    int? requiredSignatures,
    int? totalPillars,
    int? lastElectionAt,
    int? nextElectionAt,
    double? treasuryBalance,
    bool? isActiveElection,
    int? electionEndTime,
    Map<String, String>? councilRoles,
    Map<String, List<String>>? roleCandidates,
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
      candidateIds: candidateIds ?? this.candidateIds,
      councilRoles: councilRoles ?? this.councilRoles,
      roleCandidates: roleCandidates ?? this.roleCandidates,
      requiredSignatures: requiredSignatures ?? this.requiredSignatures,
      totalPillars: totalPillars ?? this.totalPillars,
      lastElectionAt: lastElectionAt ?? this.lastElectionAt,
      nextElectionAt: nextElectionAt ?? this.nextElectionAt,
      treasuryBalance: treasuryBalance ?? this.treasuryBalance,
      isActiveElection: isActiveElection ?? this.isActiveElection,
      electionEndTime: electionEndTime ?? this.electionEndTime,
    );
  }

  bool get isTreasuryBearing => level != GovernanceLevel.global;

  /// All user IDs currently running for any role.
  List<String> get allRoleCandidateIds {
    final ids = <String>{};
    for (final list in roleCandidates.values) {
      ids.addAll(list);
    }
    return ids.toList();
  }

  /// Parse roleCandidates from Firestore JSON.
  static Map<String, List<String>> _parseRoleCandidates(dynamic raw) {
    if (raw == null) return {};
    final map = raw as Map<dynamic, dynamic>;
    return map.map((k, v) {
      final key = k as String;
      final value = (v as List<dynamic>?)?.cast<String>() ?? [];
      return MapEntry(key, value);
    });
  }

  /// Parse [GovernanceLevel] from either an int index or a string name.
  static GovernanceLevel _parseGovernanceLevel(dynamic raw) {
    if (raw is int) {
      return (raw >= 0 && raw < GovernanceLevel.values.length)
          ? GovernanceLevel.values[raw]
          : GovernanceLevel.local;
    }
    if (raw is String) {
      return GovernanceLevel.values.firstWhere(
        (e) => e.name == raw,
        orElse: () => GovernanceLevel.local,
      );
    }
    return GovernanceLevel.local;
  }

  /// Parse [GovernanceType] from either an int index or a string name.
  static GovernanceType _parseGovernanceType(dynamic raw) {
    if (raw is int) {
      return (raw >= 0 && raw < GovernanceType.values.length)
          ? GovernanceType.values[raw]
          : GovernanceType.local;
    }
    if (raw is String) {
      return GovernanceType.values.firstWhere(
        (e) => e.name == raw,
        orElse: () => GovernanceType.local,
      );
    }
    return GovernanceType.local;
  }
}
