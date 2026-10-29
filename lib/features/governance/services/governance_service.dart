import 'dart:async';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../community/repository/community_repository.dart';
import '../../dsp/models/user_points.dart';
import '../../dsp/repository/points_repository.dart';
import '../models/governance_unit.dart';
import '../models/governance_roles.dart';
import '../models/election_result.dart';
import '../repository/governance_repository.dart';
import '../../trust/models/trust_data.dart';
import '../../trust/services/trust_service.dart';
import '../../trust/repository/trust_repository.dart';

final governanceRepositoryProviderAlias = governanceRepositoryProvider;

final governanceServiceProvider = Provider((ref) => GovernanceService(ref));

class GovernanceService {
  final Ref _ref;

  GovernanceService(this._ref);

  static final Map<String, List<UserPoints>> _qualifiedCandidatesCache = {};

  List<UserPoints>? getCachedQualifiedCandidates(String unitId) =>
      _qualifiedCandidatesCache[unitId];

  void cacheQualifiedCandidates(String unitId, List<UserPoints> candidates) {
    _qualifiedCandidatesCache[unitId] = candidates;
  }

  Map<String, VoteSummary>? getCachedRoleCandidateVotes(
    String unitId,
    String role,
  ) {
    final repo = _ref.read(governanceRepositoryProvider);
    final votes = repo.getCachedRoleVotes(unitId, role);
    if (votes == null) return null;
    return _summarizeVotes(votes, role);
  }

  Map<String, VoteSummary> _summarizeVotes(
    List<Map<String, dynamic>> votes,
    String role,
  ) {
    final Map<String, VoteSummary> summaries = {};
    final Map<String, List<String>> candidateVerdicts = {};
    for (final vote in votes) {
      final cid = vote['candidateId'] as String;
      final verdict = vote['verdict'] as String? ?? VoteVerdict.abstain;
      candidateVerdicts.putIfAbsent(cid, () => []).add(verdict);
    }

    for (final entry in candidateVerdicts.entries) {
      int yay = 0, nay = 0, abstain = 0;
      for (final v in entry.value) {
        if (v == VoteVerdict.yay) yay++;
        if (v == VoteVerdict.nay) nay++;
        if (v == VoteVerdict.abstain) abstain++;
      }
      summaries[entry.key] = VoteSummary(
        candidateId: entry.key,
        role: role,
        yayCount: yay,
        nayCount: nay,
        abstainCount: abstain,
      );
    }
    return summaries;
  }

  // ────────────────────────────────────────────
  // QUALIFIED CANDIDATES POOL (Auto-populated)
  // ────────────────────────────────────────────

  /// Returns community members who meet all candidacy eligibility criteria.
  /// Excludes members who have already selected a role (are in roleCandidates).
  Future<List<UserPoints>> getQualifiedCandidates(String unitId) async {
    final repo = _ref.read(governanceRepositoryProvider);
    final unit =
        repo.getCachedGovernanceUnit(unitId) ??
        await repo.getGovernanceUnit(unitId);
    if (unit == null) return _qualifiedCandidatesCache[unitId] ?? [];

    // Get community members
    final communityId = unit.communityId;
    if (communityId == null) return _qualifiedCandidatesCache[unitId] ?? [];

    final memberIds =
        repo.getCachedCommunityMemberIds(communityId) ??
        await repo.getCommunityMemberIds(communityId);

    // IDs already running for a role — exclude from qualified pool
    final alreadyRunning = unit.allRoleCandidateIds.toSet();

    final trustRepo = _ref.read(trustRepositoryProvider);
    final pointsRepo = _ref.read(pointsRepositoryProvider);

    final candidateMemberIds = memberIds
        .where((id) => !alreadyRunning.contains(id))
        .toList();

    final results = await Future.wait(
      candidateMemberIds.map((memberId) async {
        final trustData =
            trustRepo.getCachedTrustData(memberId) ??
            await trustRepo.getTrustData(memberId);
        if (trustData == null || !trustData.isCouncilEligible) return null;

        return pointsRepo.getCachedUserPoints(memberId) ??
            await pointsRepo.getUserPoints(memberId);
      }),
    );

    final qualified = results.whereType<UserPoints>().toList();
    _qualifiedCandidatesCache[unitId] = qualified;
    return qualified;
  }

  // ────────────────────────────────────────────────────
  // ROLE SELECTION & SELF-VOTE (Candidate declares run)
  // ────────────────────────────────────────────────────

  /// Candidate selects the role they want to run for.
  /// This auto-registers them as a candidate and casts a self-vote (Yay).
  /// Triggers system message to community chat.
  Future<void> selectRoleAndSelfVote(
    String unitId,
    String userId,
    String role,
  ) async {
    final repo = _ref.read(governanceRepositoryProvider);
    final trustRepo = _ref.read(trustRepositoryProvider);

    var unit = repo.getCachedGovernanceUnit(unitId);
    var trustData = trustRepo.getCachedTrustData(userId);

    if (unit == null || trustData == null) {
      final fetched = await Future.wait([
        unit != null ? Future.value(unit) : repo.getGovernanceUnit(unitId),
        trustData != null
            ? Future.value(trustData)
            : _ref.read(trustServiceProvider).getTrustData(userId),
      ]);
      unit = fetched[0] as GovernanceUnit?;
      trustData = fetched[1] as TrustData?;
    }

    if (unit == null) throw Exception('Governance unit not found.');

    // 1. Verify user is qualified
    if (trustData == null || !trustData.isCouncilEligible) {
      throw Exception(
        'You do not meet the candidacy eligibility requirements.',
      );
    }

    // 2. Check user isn't already running for this role
    final currentCandidates = unit.roleCandidates[role] ?? [];
    if (currentCandidates.contains(userId)) {
      throw Exception(
        'You are already running for ${GovernanceRoles.displayName(role)}.',
      );
    }

    // Optimistically update local governance unit & qualified pool caches
    final updatedJson = unit.toJson();
    final updatedRoleCandidates = Map<String, dynamic>.from(
      updatedJson['roleCandidates'] as Map? ?? {},
    );
    updatedRoleCandidates[role] = [...currentCandidates, userId];
    updatedJson['roleCandidates'] = updatedRoleCandidates;
    repo.cacheGovernanceUnit(GovernanceUnit.fromJson(updatedJson));

    final cachedQualified = _qualifiedCandidatesCache[unitId];
    if (cachedQualified != null) {
      _qualifiedCandidatesCache[unitId] = cachedQualified
          .where((c) => c.userId != userId)
          .toList();
    }

    // 3. Register candidacy through a protected structural mutation.
    await FirebaseFunctions.instance
        .httpsCallable('nominateForGovernanceRole')
        .call({'unitId': unitId, 'role': role});

    // 4. Cast self-vote (Yay)
    await repo.castRoleVote(
      unitId: unitId,
      voterId: userId,
      candidateId: userId,
      role: role,
      verdict: VoteVerdict.yay,
    );

    // 5. Send system message to community chat. Trust metrics are updated only
    // by backend workflows; a client vote is not allowed to mutate them.
    await _sendCandidacyAnnouncement(unit, userId, role);

    debugPrint(
      '✅ $userId selected role ${GovernanceRoles.displayName(role)} '
      'for unit $unitId and self-voted.',
    );
  }

  /// Send system message to community chat announcing candidacy.
  /// Handled server-side inside `nominateForGovernanceRole`.
  Future<void> _sendCandidacyAnnouncement(
    GovernanceUnit unit,
    String userId,
    String role,
  ) async {
    // Server-side `nominateForGovernanceRole` posts the system announcement
    // directly with the Admin SDK so clients do not fail on senderId=='system'.
    return;
  }

  // ────────────────────────────────
  // VOTING (Yay / Nay / Hold)
  // ────────────────────────────────

  /// Casts a Yay/Nay/Hold vote for a candidate in a specific role.
  Future<void> castRoleVote({
    required String unitId,
    required String voterId,
    required String candidateId,
    required String role,
    required String verdict,
  }) async {
    final repo = _ref.read(governanceRepositoryProvider);

    // 1. Verify community has 4+ members
    final unit =
        repo.getCachedGovernanceUnit(unitId) ??
        await repo.getGovernanceUnit(unitId);
    if (unit == null) throw Exception('Governance unit not found.');

    if (unit.communityId != null) {
      final community = await _ref
          .read(communityRepositoryProvider)
          .getCommunity(unit.communityId!);
      final memberCount = community?.memberCount ?? 0;
      if (memberCount < 4) {
        throw Exception('Community must have at least 4 members for voting.');
      }
    }

    // 2. Cast the vote
    await repo.castRoleVote(
      unitId: unitId,
      voterId: voterId,
      candidateId: candidateId,
      role: role,
      verdict: verdict,
    );

    // 3. Check if winner can be declared or vote-out applies (background)
    unawaited(_evaluateManagedRoleStatus(unitId, candidateId, role));

    debugPrint(
      '✅ $voterId voted $verdict for $candidateId as $role in $unitId',
    );
  }

  Future<void> _evaluateManagedRoleStatus(
    String unitId,
    String candidateId,
    String role,
  ) async {
    try {
      final result = await FirebaseFunctions.instance
          .httpsCallable('evaluateGovernanceVote')
          .call({'unitId': unitId, 'candidateId': candidateId, 'role': role});
      final data = Map<String, dynamic>.from(result.data as Map);

      if (data['promoted'] == true) {
        debugPrint('$candidateId elected as $role in $unitId.');
      }

      final removedMembers =
          (data['removedMembers'] as List<dynamic>? ?? const [])
              .map((entry) => Map<String, dynamic>.from(entry as Map))
              .toList();
      await _announceManagedVoteOuts(unitId, removedMembers);
    } catch (e) {
      debugPrint('Error evaluating governance vote: $e');
    }
  }

  Future<void> _announceManagedVoteOuts(
    String unitId,
    List<Map<String, dynamic>> removedMembers,
  ) async {
    // Server-side `evaluateGovernanceVote` posts the vote-out system message
    // directly with the Admin SDK so clients do not fail on senderId=='system'.
    return;
  }

  // ──────────────────────────────────
  // VOTE SUMMARY STREAMS (Live UI)
  // ──────────────────────────────────

  /// Stream live vote summaries for all candidates in a specific role.
  Stream<Map<String, VoteSummary>> watchRoleCandidateVotes(
    String unitId,
    String role,
  ) {
    final repo = _ref.read(governanceRepositoryProvider);
    return repo
        .watchRoleVotes(unitId, role)
        .map((votes) => _summarizeVotes(votes, role));
  }

  // ──────────────────────────────────
  // LEGACY SUPPORT & UTILITIES
  // ──────────────────────────────────

  /// Checks if a user is considered a "Pillar" (High Trust)
  Future<bool> isPillar(String userId) async {
    final trustData =
        _ref.read(trustRepositoryProvider).getCachedTrustData(userId) ??
        await _ref.read(trustServiceProvider).getTrustData(userId);
    return trustData != null && trustData.level == TrustLevel.highTrust;
  }

  /// [LEGACY] Get registered candidates (old flow).
  /// Now returns role candidates for backward compat.
  Future<List<UserPoints>> getCandidates(String unitId) async {
    return getQualifiedCandidates(unitId);
  }

  /// [LEGACY] Triggers a re-tally for a governance unit.
  Future<void> tallyElection(String unitId) async {
    final repo = _ref.read(governanceRepositoryProvider);
    final unit =
        repo.getCachedGovernanceUnit(unitId) ??
        await repo.getGovernanceUnit(unitId);
    if (unit == null) return;

    // In continuous voting, tallying happens per-vote via _evaluateRoleStatus.
    // This legacy method can be used for batch recalculation.
    final futures = <Future<void>>[];
    for (final role in GovernanceRoles.all) {
      final candidates = unit.roleCandidates[role] ?? [];
      for (final candidateId in candidates) {
        futures.add(_evaluateManagedRoleStatus(unitId, candidateId, role));
      }
    }
    await Future.wait(futures);
  }

  Future<void> startElection(String unitId, {int durationDays = 7}) async {
    final repo = _ref.read(governanceRepositoryProvider);
    await repo.startElection(unitId, durationDays);
  }

  /// [LEGACY] castVote — redirects to new role-based system.
  Future<void> castVote({
    required String unitId,
    required String voterId,
    required String candidateId,
    String? signerId,
  }) async {
    // Default to council_member role for backward compat
    await castRoleVote(
      unitId: unitId,
      voterId: voterId,
      candidateId: candidateId,
      role: GovernanceRoles.councilMember,
      verdict: VoteVerdict.yay,
    );
  }

  /// [LEGACY] watchElectionResults — kept for backward compat.
  Stream<List<ElectionResult>> watchElectionResults(String unitId) {
    final repo = _ref.read(governanceRepositoryProvider);
    return repo.watchVotes(unitId).map((votes) {
      final Map<String, int> tallyMap = {};
      for (var vote in votes) {
        final candidateId = vote['candidateId'] as String;
        tallyMap[candidateId] = (tallyMap[candidateId] ?? 0) + 1;
      }

      return tallyMap.entries
          .map(
            (e) => ElectionResult(
              id: 'live_${e.key}',
              unitId: unitId,
              unitName: 'Live Tally',
              timestamp: DateTime.now().millisecondsSinceEpoch,
              winners: [],
              tally: {e.key: e.value},
              totalVotes: e.value,
            ),
          )
          .toList();
    });
  }

  /// Gets community member count.
  Future<int> getCommunityMemberCount(String unitId) async {
    final repo = _ref.read(governanceRepositoryProvider);
    final unit =
        repo.getCachedGovernanceUnit(unitId) ??
        await repo.getGovernanceUnit(unitId);
    if (unit?.communityId == null) return 0;

    final community = await _ref
        .read(communityRepositoryProvider)
        .getCommunity(unit!.communityId!);
    return community?.memberCount ?? 0;
  }

  /// Refined TGE eligibility check
  Future<bool> checkTgeEligibility(String unitId) async {
    final repo = _ref.read(governanceRepositoryProviderAlias);
    final unit =
        repo.getCachedGovernanceUnit(unitId) ??
        await repo.getGovernanceUnit(unitId);
    if (unit == null) return false;
    return unit.signers.length >= 3;
  }

  /// Checks if a user is eligible for promotion to a higher council level.
  Future<bool> shouldPromoteToHigherCouncil(
    String userId,
    GovernanceUnit targetUnit,
  ) async {
    if (targetUnit.level == GovernanceLevel.local) {
      return true;
    }

    final repo = _ref.read(governanceRepositoryProviderAlias);
    final communityRepo = _ref.read(communityRepositoryProvider);
    final userMemberships = await repo.getGovernanceUnitsForUser(userId);
    if (userMemberships.isEmpty) return false;

    GovernanceLevel requiredLowerLevel = GovernanceLevel.local;
    switch (targetUnit.level) {
      case GovernanceLevel.state:
        requiredLowerLevel = GovernanceLevel.local;
        break;
      case GovernanceLevel.country:
        requiredLowerLevel = GovernanceLevel.state;
        break;
      case GovernanceLevel.continent:
        requiredLowerLevel = GovernanceLevel.country;
        break;
      case GovernanceLevel.global:
        requiredLowerLevel = GovernanceLevel.continent;
        break;
      default:
        break;
    }

    final candidateUnits = userMemberships
        .where((unit) => unit.level == requiredLowerLevel)
        .toList();

    if (candidateUnits.isEmpty) return false;
    if (targetUnit.communityId == null) return false;

    final lowerCommunityIds = candidateUnits
        .map((u) => u.communityId)
        .whereType<String>()
        .toList();

    final communities = await Future.wait([
      communityRepo.getCommunity(targetUnit.communityId!),
      ...lowerCommunityIds.map((id) => communityRepo.getCommunity(id)),
    ]);

    final targetCommunity = communities.first;
    if (targetCommunity == null) return false;

    for (var i = 1; i < communities.length; i++) {
      final lowerCommunity = communities[i];
      if (lowerCommunity == null) continue;

      if (targetUnit.level == GovernanceLevel.global) return true;

      bool isContained = false;
      final tLoc = targetCommunity.location ?? {};
      final lLoc = lowerCommunity.location ?? {};

      if (targetUnit.level == GovernanceLevel.state) {
        if (tLoc['state'] == lLoc['state'] &&
            tLoc['countryCode'] == lLoc['countryCode']) {
          isContained = true;
        }
      } else if (targetUnit.level == GovernanceLevel.country) {
        if ((targetCommunity.homeCountryCode == lLoc['countryCode']) ||
            (tLoc['countryCode'] == lLoc['countryCode'])) {
          isContained = true;
        }
      } else if (targetUnit.level == GovernanceLevel.continent) {
        isContained = true;
      }

      if (isContained) return true;
    }

    return false;
  }

  /// Periodically called to check vote-out status across all units.
  Future<void> checkAndTriggerElections() async {
    // In continuous voting, this mainly checks vote-out status
    final levels = GovernanceLevel.values;
    final snapshots = await Future.wait(
      levels.map(
        (level) => FirebaseFirestore.instance
            .collection('governance')
            .where('level', isEqualTo: level.index)
            .limit(200)
            .get(),
      ),
    );

    final evalFutures = <Future<void>>[];
    for (final snapshot in snapshots) {
      final units = snapshot.docs
          .map((doc) => GovernanceUnit.fromJson(doc.data()))
          .toList();

      for (final unit in units) {
        for (final memberId in unit.councilMembers) {
          final role = unit.councilRoles[memberId];
          if (role != null) {
            evalFutures.add(
              _evaluateManagedRoleStatus(unit.id, memberId, role),
            );
          }
        }
      }
    }
    await Future.wait(evalFutures);
  }
}
