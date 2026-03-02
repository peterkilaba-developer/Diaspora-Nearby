import 'package:flutter/foundation.dart';
import '../../profile/models/profile_data.dart';
import '../../shared/models/location.dart';
import '../../dsp/models/user_points.dart';
import '../models/governance_roles.dart';
import '../models/governance_unit.dart';

/// Fully in-memory mock election data for testing the governance UI flow.
/// No Firestore writes — everything is injected at the UI layer.
///
/// ⚠️ TESTING ONLY — set [enabled] to false before production.
class MockElectionData {
  static const bool enabled = true;

  /// Whether mock data has been seeded in memory.
  static bool _isSeeded = false;
  static bool get isSeeded => _isSeeded;

  // ─── Mock vote state (mutable, in-memory) ────────────────────
  /// role -> candidateId -> {yay, nay, hold} counts
  static final Map<String, Map<String, Map<String, int>>> _voteCounts = {};

  // ─── Dummy location for mock profiles ────────────────────────
  static const _dummyLocation = UserLocation(
    formattedAddress: 'Mock City',
    placeId: 'mock_place',
  );

  // ─── 10 Mock Candidates ──────────────────────────────────────

  static const List<Map<String, String>> _mockUsers = [
    {'id': 'mock_001', 'first': 'Amara', 'last': 'Diallo', 'country': 'SN'},
    {'id': 'mock_002', 'first': 'Kwame', 'last': 'Asante', 'country': 'GH'},
    {'id': 'mock_003', 'first': 'Fatima', 'last': 'Ndongo', 'country': 'CM'},
    {'id': 'mock_004', 'first': 'Chidi', 'last': 'Okafor', 'country': 'NG'},
    {'id': 'mock_005', 'first': 'Aisha', 'last': 'Mwangi', 'country': 'KE'},
    {'id': 'mock_006', 'first': 'Tendai', 'last': 'Moyo', 'country': 'ZW'},
    {'id': 'mock_007', 'first': 'Salif', 'last': 'Keita', 'country': 'ML'},
    {'id': 'mock_008', 'first': 'Ngozi', 'last': 'Eze', 'country': 'NG'},
    {'id': 'mock_009', 'first': 'Kofi', 'last': 'Mensah', 'country': 'GH'},
    {'id': 'mock_010', 'first': 'Zainab', 'last': 'Traore', 'country': 'ML'},
  ];

  /// Role assignments:
  ///   President: mock_001, mock_002
  ///   Treasurer: mock_003, mock_004
  ///   Secretary: mock_005, mock_006
  ///   Council Member: mock_007, mock_008
  ///   Qualified pool: mock_009, mock_010
  static const Map<String, List<String>> _roleCandidates = {
    GovernanceRoles.president: ['mock_001', 'mock_002'],
    GovernanceRoles.treasurer: ['mock_003', 'mock_004'],
    GovernanceRoles.secretary: ['mock_005', 'mock_006'],
    GovernanceRoles.councilMember: ['mock_007', 'mock_008'],
  };

  static const List<String> qualifiedPoolIds = ['mock_009', 'mock_010'];

  static List<String> get allMockIds =>
      _mockUsers.map((u) => u['id']!).toList();

  // ─── Static in-memory ProfileData for mock IDs ───────────────

  static final Map<String, ProfileData> _mockProfiles = {
    for (final u in _mockUsers)
      u['id']!: ProfileData(
        uid: u['id']!,
        firstName: u['first']!,
        lastName: u['last']!,
        phone: '',
        profileImage: '',
        homeLocation: _dummyLocation,
        hostLocation: _dummyLocation,
        homeCountryCode: u['country'],
        bio: 'Mock candidate for governance testing',
      ),
  };

  /// Returns a mock profile if the ID is a mock candidate, null otherwise.
  static ProfileData? getMockProfile(String userId) {
    if (!enabled || !_isSeeded) return null;
    return _mockProfiles[userId];
  }

  /// Check if an ID belongs to a mock candidate.
  static bool isMockId(String id) => id.startsWith('mock_');

  // ─── Mock UserPoints for qualified pool ──────────────────────

  static List<UserPoints> get mockQualifiedCandidates {
    if (!enabled || !_isSeeded) return [];
    return qualifiedPoolIds.map((id) {
      final user = _mockUsers.firstWhere((u) => u['id'] == id);
      return UserPoints(
        userId: id,
        totalPoints: 500,
        availablePoints: 500,
        currentStreak: 3,
        dailyMessageCount: 0,
        lastUpdated: DateTime.now(),
        signupDate: DateTime.now().subtract(const Duration(days: 30)),
        trustScore: 50,
      );
    }).toList();
  }

  // ─── Governance Unit injection ───────────────────────────────

  /// Creates a modified copy of the governance unit with mock candidates
  /// injected into the roleCandidates map.
  static GovernanceUnit injectMockCandidates(GovernanceUnit unit) {
    if (!enabled || !_isSeeded) return unit;

    final merged = Map<String, List<String>>.from(
      unit.roleCandidates.map(
        (key, value) => MapEntry(key, List<String>.from(value)),
      ),
    );

    for (final entry in _roleCandidates.entries) {
      final existing = merged[entry.key] ?? [];
      final combined = {...existing, ...entry.value}.toList();
      merged[entry.key] = combined;
    }

    return GovernanceUnit(
      id: unit.id,
      name: unit.name,
      communityId: unit.communityId,
      level: unit.level,
      type: unit.type,
      walletAddress: unit.walletAddress,
      signers: unit.signers,
      councilMembers: unit.councilMembers,
      candidateIds: unit.candidateIds,
      councilRoles: unit.councilRoles,
      roleCandidates: merged,
      requiredSignatures: unit.requiredSignatures,
      totalPillars: unit.totalPillars,
      lastElectionAt: unit.lastElectionAt,
      nextElectionAt: unit.nextElectionAt,
      treasuryBalance: unit.treasuryBalance,
      isActiveElection: true,
      electionEndTime: unit.electionEndTime,
    );
  }

  // ─── In-memory vote tracking ─────────────────────────────────

  /// Cast a mock vote (purely in-memory).
  static void castMockVote(String role, String candidateId, String verdict) {
    _voteCounts.putIfAbsent(role, () => {});
    _voteCounts[role]!.putIfAbsent(
      candidateId,
      () => {'yay': 0, 'nay': 0, 'hold': 0},
    );
    _voteCounts[role]![candidateId]![verdict] =
        (_voteCounts[role]![candidateId]![verdict] ?? 0) + 1;
  }

  /// Get mock vote summary for a candidate in a role.
  static VoteSummary getMockVoteSummary(String role, String candidateId) {
    final counts = _voteCounts[role]?[candidateId];
    return VoteSummary(
      candidateId: candidateId,
      role: role,
      yayCount: counts?['yay'] ?? 0,
      nayCount: counts?['nay'] ?? 0,
      holdCount: counts?['hold'] ?? 0,
    );
  }

  /// Get all mock vote summaries for a role.
  static Map<String, VoteSummary> getMockVoteSummaries(String role) {
    final result = <String, VoteSummary>{};
    final roleCounts = _voteCounts[role] ?? {};
    for (final candidateId in roleCounts.keys) {
      result[candidateId] = getMockVoteSummary(role, candidateId);
    }
    return result;
  }

  // ─── Seed / Clean ────────────────────────────────────────────

  /// Seed mock data in memory with pre-built vote distributions.
  static void seedAll() {
    _isSeeded = true;

    // Clear any previous mock votes
    _voteCounts.clear();

    // Pre-seed some votes for visual variety
    final seedVotes = <String, Map<String, List<String>>>{
      GovernanceRoles.president: {
        'mock_001': ['yay', 'yay', 'yay', 'hold', 'nay'],
        'mock_002': ['yay', 'nay', 'hold'],
      },
      GovernanceRoles.treasurer: {
        'mock_003': ['yay', 'yay', 'yay', 'yay'],
        'mock_004': ['yay', 'nay', 'nay', 'hold', 'hold'],
      },
      GovernanceRoles.secretary: {
        'mock_005': ['yay', 'yay', 'hold'],
        'mock_006': ['yay', 'yay', 'yay', 'nay'],
      },
      GovernanceRoles.councilMember: {
        'mock_007': ['yay', 'yay', 'yay'],
        'mock_008': ['yay', 'nay'],
      },
    };

    for (final roleEntry in seedVotes.entries) {
      for (final candidateEntry in roleEntry.value.entries) {
        for (final verdict in candidateEntry.value) {
          castMockVote(roleEntry.key, candidateEntry.key, verdict);
        }
      }
    }

    debugPrint('🎉 Mock election data seeded in memory');
  }

  /// Clean all mock data from memory.
  static void cleanAll() {
    _isSeeded = false;
    _voteCounts.clear();
    debugPrint('🧹 Mock election data cleaned');
  }
}
