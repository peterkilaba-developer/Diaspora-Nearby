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
import '../../dsp/services/points_service.dart';
import '../../trust/services/trust_service.dart';
import '../../trust/repository/trust_repository.dart';
import '../../chat/services/chat_messaging_service.dart';
import 'mock_election_data.dart';
import '../../auth/repository/auth_repository.dart';

final governanceRepositoryProviderAlias = governanceRepositoryProvider;

final governanceServiceProvider = Provider((ref) => GovernanceService(ref));

class GovernanceService {
  final Ref _ref;

  GovernanceService(this._ref);

  // ────────────────────────────────────────────
  // QUALIFIED CANDIDATES POOL (Auto-populated)
  // ────────────────────────────────────────────

  /// Returns community members who meet all candidacy eligibility criteria.
  /// Excludes members who have already selected a role (are in roleCandidates).
  Future<List<UserPoints>> getQualifiedCandidates(String unitId) async {
    final repo = _ref.read(governanceRepositoryProvider);
    final unit = await repo.getGovernanceUnit(unitId);
    if (unit == null) return [];

    // Get community members
    final communityId = unit.communityId;
    if (communityId == null && !MockElectionData.enabled) return [];

    final memberIds = communityId != null
        ? await repo.getCommunityMemberIds(communityId)
        : <String>[];

    // IDs already running for a role — exclude from qualified pool
    final alreadyRunning = unit.allRoleCandidateIds.toSet();

    final trustRepo = _ref.read(trustRepositoryProvider);
    final pointsRepo = _ref.read(pointsRepositoryProvider);
    final List<UserPoints> qualified = [];

    for (final memberId in memberIds) {
      if (alreadyRunning.contains(memberId)) continue;

      // Check trust eligibility
      final trustData = await trustRepo.getTrustData(memberId);
      if (trustData == null || !trustData.isCouncilEligible) continue;

      // Fetch points data for display
      final up = await pointsRepo.getUserPoints(memberId);
      if (up != null) {
        qualified.add(up);
      }
    }

    // When mock data is seeded, add mock qualified pool + current user
    if (MockElectionData.isSeeded) {
      final existingIds = qualified.map((q) => q.userId).toSet();

      // Add mock qualified pool members from in-memory data
      for (final mockCandidate in MockElectionData.mockQualifiedCandidates) {
        if (alreadyRunning.contains(mockCandidate.userId)) continue;
        if (existingIds.contains(mockCandidate.userId)) continue;
        qualified.add(mockCandidate);
        existingIds.add(mockCandidate.userId);
      }

      // Add current user (the tester) if not already present
      final auth = _ref.read(authRepositoryProvider);
      final currentUserId = auth.currentUser?.uid;
      if (currentUserId != null &&
          !alreadyRunning.contains(currentUserId) &&
          !existingIds.contains(currentUserId)) {
        final up = await pointsRepo.getUserPoints(currentUserId);
        if (up != null) {
          qualified.add(up);
        } else {
          // Create a minimal UserPoints entry so the tester shows up
          qualified.add(UserPoints(
            userId: currentUserId,
            totalPoints: 0,
            availablePoints: 0,
            currentStreak: 0,
            dailyMessageCount: 0,
            lastUpdated: DateTime.now(),
            signupDate: DateTime.now(),
          ));
        }
      }
    }

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
    final unit = await repo.getGovernanceUnit(unitId);
    if (unit == null) throw Exception('Governance unit not found.');

    // 1. Verify user is qualified (skip for mock testing)
    if (!MockElectionData.enabled) {
      final trustData = await _ref
          .read(trustServiceProvider)
          .getTrustData(userId);
      if (trustData == null || !trustData.isCouncilEligible) {
        throw Exception('You do not meet the candidacy eligibility requirements.');
      }
    }

    // 2. Check user isn't already running for this role
    final currentCandidates = unit.roleCandidates[role] ?? [];
    if (currentCandidates.contains(userId)) {
      throw Exception('You are already running for ${GovernanceRoles.displayName(role)}.');
    }

    // 3. Add to role-specific candidate list
    await repo.addRoleCandidate(unitId, userId, role);

    // 4. Ensure election is active (continuous voting = always active)
    if (!unit.isActiveElection) {
      await repo.startElection(unitId, 365 * 100); // Effectively permanent
    }

    // 5. Cast self-vote (Yay)
    await repo.castRoleVote(
      unitId: unitId,
      voterId: userId,
      candidateId: userId,
      role: role,
      verdict: VoteVerdict.yay,
    );

    // 6. Record HTS activity (skip for mock)
    if (!MockElectionData.enabled) {
      await _ref
          .read(trustServiceProvider)
          .recordActivity(userId, HTSActivityType.vote);
    }

    // 7. Send system message to community chat (skip for mock)
    if (!MockElectionData.enabled) {
      await _sendCandidacyAnnouncement(unit, userId, role);
    }

    debugPrint(
      '✅ $userId selected role ${GovernanceRoles.displayName(role)} '
      'for unit $unitId and self-voted.',
    );
  }

  /// Send system message to community chat announcing candidacy.
  Future<void> _sendCandidacyAnnouncement(
    GovernanceUnit unit,
    String userId,
    String role,
  ) async {
    if (unit.communityId == null) return;

    try {
      final chatId = 'community_${unit.communityId}';
      final roleName = GovernanceRoles.displayName(role);
      final roleEmoji = GovernanceRoles.emoji(role);

      // Check community has min 4 members
      final community = await _ref
          .read(communityRepositoryProvider)
          .getCommunity(unit.communityId!);
      final memberCount = community?.memberCount ?? 0;
      if (memberCount < 4) {
        debugPrint('⚠️ Community has < 4 members, skipping vote notification.');
        return;
      }

      final chatService = _ref.read(chatMessagingServiceProvider);
      await chatService.sendTextMessage(
        chatId,
        '$roleEmoji A community member has announced their candidacy for '
        '$roleName! Open Voice of Diaspora to cast your vote: '
        'Yay ✅, Nay ❌, or Hold ⏸️',
        senderIdOverride: 'system',
        senderNameOverride: '🗳️ Voice of Diaspora',
        type: 'system',
        metadata: {
          'systemType': 'election_announcement',
          'candidateId': userId,
          'role': role,
          'unitId': unit.id,
        },
      );
    } catch (e) {
      debugPrint('Error sending candidacy announcement: $e');
    }
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

    // Check if this is a mock/test vote (voterId has timestamp suffix)
    final isMockVote = MockElectionData.enabled &&
        voterId.contains(RegExp(r'_\d{13}$'));

    // 1. Verify community has 4+ members (skip for mock votes)
    final unit = await repo.getGovernanceUnit(unitId);
    if (unit == null) throw Exception('Governance unit not found.');

    if (!isMockVote && unit.communityId != null) {
      final community = await _ref
          .read(communityRepositoryProvider)
          .getCommunity(unit.communityId!);
      final memberCount = community?.memberCount ?? 0;
      if (memberCount < 4) {
        throw Exception(
          'Community must have at least 4 members for voting.',
        );
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

    // 3. Record HTS governance activity (skip for mock votes)
    if (!isMockVote) {
      await _ref
          .read(trustServiceProvider)
          .recordActivity(voterId, HTSActivityType.vote);
    }

    // 4. Check if winner can be declared or vote-out applies
    await _evaluateRoleStatus(unitId, candidateId, role);

    debugPrint(
      '✅ $voterId voted $verdict for $candidateId as $role in $unitId',
    );
  }

  /// Evaluate after each vote: promote winner or vote-out losing leader.
  Future<void> _evaluateRoleStatus(
    String unitId,
    String candidateId,
    String role,
  ) async {
    final repo = _ref.read(governanceRepositoryProvider);
    final unit = await repo.getGovernanceUnit(unitId);
    if (unit == null) return;

    // Check quorum: 50% of community must have voted on this candidate
    int totalMembers = 0;
    if (unit.communityId != null) {
      final community = await _ref
          .read(communityRepositoryProvider)
          .getCommunity(unit.communityId!);
      totalMembers = community?.memberCount ?? 0;
    }
    if (totalMembers < 4) return;

    final quorumTarget = (totalMembers * 0.5).ceil();

    // Check the candidate who just received a vote
    final summary = await repo.getCandidateVoteSummary(
      unitId,
      candidateId,
      role,
    );

    if (summary.totalVotes >= quorumTarget && summary.isWinning) {
      // Candidate has quorum + >50% favorable → promote to council
      await repo.addCouncilMember(unitId, candidateId, role);

      // Award governance achievement
      final pointsService = _ref.read(pointsServiceProvider);
      await pointsService.awardManualPoints(
        candidateId,
        10000,
        'Governance Achievement: Elected as ${GovernanceRoles.displayName(role)}',
      );
      await _ref.read(trustServiceProvider).updateTrustForUser(candidateId);

      debugPrint(
        '🏆 $candidateId won $role in $unitId with '
        '${summary.yayCount} Yay / ${summary.nayCount} Nay',
      );
    }

    // Vote-out check: if existing leader drops below 50% favorable
    await checkAndApplyVoteOut(unitId);
  }

  // ──────────────────────────────────
  // VOTE-OUT (Auto-remove sub-50%)
  // ──────────────────────────────────

  /// Check all current council members. If anyone's favorable rate drops
  /// below 50%, automatically remove them from the council.
  Future<void> checkAndApplyVoteOut(String unitId) async {
    final repo = _ref.read(governanceRepositoryProvider);
    final unit = await repo.getGovernanceUnit(unitId);
    if (unit == null) return;

    for (final memberId in List<String>.from(unit.councilMembers)) {
      final role = unit.councilRoles[memberId];
      if (role == null) continue;

      final summary = await repo.getCandidateVoteSummary(
        unitId,
        memberId,
        role,
      );

      // Only vote out if there are enough decisive votes and rate < 50%
      if (summary.decisiveVotes >= 3 && summary.shouldBeVotedOut) {
        await repo.removeCouncilMember(unitId, memberId);

        // Send chat notification about vote-out
        if (unit.communityId != null) {
          try {
            final chatId = 'community_${unit.communityId}';
            final roleName = GovernanceRoles.displayName(role);
            final chatService = _ref.read(chatMessagingServiceProvider);
            await chatService.sendTextMessage(
              chatId,
              '⚠️ A $roleName has been removed from council by community '
              'vote (favorable rate dropped below 50%). '
              'The role is now open for new candidates.',
              senderIdOverride: 'system',
              senderNameOverride: '🗳️ Voice of Diaspora',
              type: 'system',
              metadata: {
                'systemType': 'election_vote_out',
                'removedUserId': memberId,
                'role': role,
                'unitId': unitId,
              },
            );
          } catch (e) {
            debugPrint('Error sending vote-out notification: $e');
          }
        }

        debugPrint(
          '🚫 $memberId voted out as $role from $unitId '
          '(${summary.yayCount} Yay / ${summary.nayCount} Nay)',
        );
      }
    }
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
    return repo.watchRoleVotes(unitId, role).map((votes) {
      final Map<String, VoteSummary> summaries = {};

      // Group votes by candidate
      final Map<String, List<String>> candidateVerdicts = {};
      for (final vote in votes) {
        final cid = vote['candidateId'] as String;
        final verdict = vote['verdict'] as String? ?? VoteVerdict.hold;
        candidateVerdicts.putIfAbsent(cid, () => []).add(verdict);
      }

      for (final entry in candidateVerdicts.entries) {
        int yay = 0, nay = 0, hold = 0;
        for (final v in entry.value) {
          if (v == VoteVerdict.yay) yay++;
          if (v == VoteVerdict.nay) nay++;
          if (v == VoteVerdict.hold) hold++;
        }
        summaries[entry.key] = VoteSummary(
          candidateId: entry.key,
          role: role,
          yayCount: yay,
          nayCount: nay,
          holdCount: hold,
        );
      }
      return summaries;
    });
  }

  // ──────────────────────────────────
  // LEGACY SUPPORT & UTILITIES
  // ──────────────────────────────────

  /// Checks if a user is considered a "Pillar" (High Trust)
  Future<bool> isPillar(String userId) async {
    final trustData = await _ref
        .read(trustServiceProvider)
        .getTrustData(userId);
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
    final unit = await repo.getGovernanceUnit(unitId);
    if (unit == null) return;

    // In continuous voting, tallying happens per-vote via _evaluateRoleStatus.
    // This legacy method can be used for batch recalculation.
    for (final role in GovernanceRoles.all) {
      final candidates = unit.roleCandidates[role] ?? [];
      for (final candidateId in candidates) {
        await _evaluateRoleStatus(unitId, candidateId, role);
      }
    }
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
    final unit = await repo.getGovernanceUnit(unitId);
    if (unit?.communityId == null) return 0;

    final community = await _ref
        .read(communityRepositoryProvider)
        .getCommunity(unit!.communityId!);
    return community?.memberCount ?? 0;
  }

  /// Refined TGE eligibility check
  Future<bool> checkTgeEligibility(String unitId) async {
    final unit = await _ref
        .read(governanceRepositoryProviderAlias)
        .getGovernanceUnit(unitId);
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

    final targetCommunity = await communityRepo.getCommunity(
      targetUnit.communityId!,
    );
    if (targetCommunity == null) return false;

    for (final lowerUnit in candidateUnits) {
      if (lowerUnit.communityId == null) continue;
      final lowerCommunity = await communityRepo.getCommunity(
        lowerUnit.communityId!,
      );
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
    for (var level in levels) {
      final snapshot = await FirebaseFirestore.instance
          .collection('governance')
          .where('level', isEqualTo: level.index)
          .get();
      final units = snapshot.docs
          .map((doc) => GovernanceUnit.fromJson(doc.data()))
          .toList();

      for (var unit in units) {
        await checkAndApplyVoteOut(unit.id);
      }
    }
  }
}
