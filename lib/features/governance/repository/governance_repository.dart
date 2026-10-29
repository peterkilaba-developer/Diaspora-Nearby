import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/governance_unit.dart';
import '../models/election_result.dart';
import '../models/governance_roles.dart';

final governanceRepositoryProvider = Provider((ref) => GovernanceRepository());

/// Riverpod StreamProvider to watch a governance unit by its ID.
/// Used by _GovernanceUnitCard instead of StreamBuilder so that
/// ref.watch(treasuryTokenBalanceProvider) can chain properly.
final governanceUnitStreamProvider =
    StreamProvider.family<GovernanceUnit?, String>((ref, id) {
      return ref.watch(governanceRepositoryProvider).watchGovernanceUnit(id);
    });

class GovernanceRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static final Map<String, GovernanceUnit> _unitCache = {};
  static List<GovernanceUnit>? _activeElectionsCache;
  static final Map<String, List<Map<String, dynamic>>> _roleVotesCache = {};
  static final Map<String, List<Map<String, dynamic>>> _votesCache = {};
  static final Map<String, List<ElectionResult>> _historyCache = {};
  static final Map<String, List<String>> _communityMemberIdsCache = {};

  GovernanceUnit? getCachedGovernanceUnit(String id) => _unitCache[id];

  void cacheGovernanceUnit(GovernanceUnit unit) {
    _unitCache[unit.id] = unit;
  }

  List<GovernanceUnit>? getCachedActiveElections() => _activeElectionsCache;

  List<Map<String, dynamic>>? getCachedRoleVotes(String unitId, String role) =>
      _roleVotesCache['${unitId}_$role'];

  void cacheRoleVotes(
    String unitId,
    String role,
    List<Map<String, dynamic>> votes,
  ) {
    _roleVotesCache['${unitId}_$role'] = votes;
  }

  List<ElectionResult>? getCachedElectionHistory(String unitId) =>
      _historyCache[unitId];

  List<String>? getCachedCommunityMemberIds(String communityId) =>
      _communityMemberIdsCache[communityId];

  Future<GovernanceUnit?> getGovernanceUnit(String id) async {
    final doc = await _firestore.collection('governance').doc(id).get();
    if (!doc.exists) return _unitCache[id];
    final data = doc.data()!;
    data['id'] ??= doc.id;
    data['name'] ??= doc.id.replaceAll('_', ' ').toUpperCase();
    data['type'] ??= 'local'; // Default type if missing
    final unit = GovernanceUnit.fromJson(data);
    _unitCache[id] = unit;
    return unit;
  }

  Future<GovernanceUnit?> getGovernanceUnitByCommunityId(
    String communityId,
  ) async {
    final snapshot = await _firestore
        .collection('governance')
        .where('communityId', isEqualTo: communityId)
        .limit(1)
        .get();
    if (snapshot.docs.isEmpty) return null;
    final doc = snapshot.docs.first;
    final data = doc.data();
    data['id'] ??= doc.id;
    final unit = GovernanceUnit.fromJson(data);
    _unitCache[unit.id] = unit;
    return unit;
  }

  Future<void> saveGovernanceUnit(GovernanceUnit unit) async {
    _unitCache[unit.id] = unit;
    await _firestore.collection('governance').doc(unit.id).set(unit.toJson());
  }

  Stream<GovernanceUnit?> watchGovernanceUnit(String id) {
    return Stream.multi((controller) {
      final cached = _unitCache[id];
      if (cached != null) {
        controller.add(cached);
      }
      final sub = _firestore.collection('governance').doc(id).snapshots().listen(
        (doc) {
          if (!doc.exists || doc.data() == null) {
            controller.add(_unitCache[id]);
            return;
          }
          final data = Map<String, dynamic>.from(doc.data()!);
          data['id'] ??= doc.id;
          data['name'] ??= doc.id.replaceAll('_', ' ').toUpperCase();
          data['type'] ??= 'local';
          final unit = GovernanceUnit.fromJson(data);
          _unitCache[id] = unit;
          controller.add(unit);
        },
        onError: (_) => controller.add(_unitCache[id]),
        onDone: controller.close,
      );
      controller.onCancel = sub.cancel;
    });
  }

  Future<void> updateSigners(String id, List<String> signerIds) async {
    final cached = _unitCache[id];
    if (cached != null) {
      final json = cached.toJson();
      json['signers'] = signerIds;
      _unitCache[id] = GovernanceUnit.fromJson(json);
    }
    await _firestore.collection('governance').doc(id).update({
      'signers': signerIds,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> updateGovernanceStructure(
    String id, {
    List<String>? councilMembers,
    List<String>? signers,
  }) async {
    final cached = _unitCache[id];
    if (cached != null) {
      final json = cached.toJson();
      if (councilMembers != null) json['councilMembers'] = councilMembers;
      if (signers != null) json['signers'] = signers;
      _unitCache[id] = GovernanceUnit.fromJson(json);
    }
    final Map<String, dynamic> updates = {
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (councilMembers != null) updates['councilMembers'] = councilMembers;
    if (signers != null) updates['signers'] = signers;

    await _firestore.collection('governance').doc(id).update(updates);
  }

  Future<List<Map<String, dynamic>>> getVotes(String unitId) async {
    final snapshot = await _firestore
        .collection('governance_votes')
        .where('unitId', isEqualTo: unitId)
        .limit(500)
        .get();
    final list = snapshot.docs.map((doc) => doc.data()).toList();
    _votesCache[unitId] = list;
    return list;
  }

  Stream<List<Map<String, dynamic>>> watchVotes(String unitId) {
    return Stream.multi((controller) {
      final cached = _votesCache[unitId];
      if (cached != null) {
        controller.add(cached);
      }
      final sub = _firestore
          .collection('governance_votes')
          .where('unitId', isEqualTo: unitId)
          .limit(500)
          .snapshots()
          .listen(
            (snapshot) {
              final list = snapshot.docs.map((doc) => doc.data()).toList();
              _votesCache[unitId] = list;
              controller.add(list);
            },
            onError: controller.addError,
            onDone: controller.close,
          );
      controller.onCancel = sub.cancel;
    });
  }

  Future<void> startElection(String id, int durationDays) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final endTime = now + (durationDays * 24 * 60 * 60 * 1000);

    // [FIX] Ensure required fields exist even when merging/creating
    await _firestore.collection('governance').doc(id).set({
      'id': id,
      'isActiveElection': true,
      'electionEndTime': endTime,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> endElection(String id) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final nextElectionAt = now + (365 * 24 * 60 * 60 * 1000); // 1 Year Term

    await _firestore.collection('governance').doc(id).update({
      'isActiveElection': false,
      'lastElectionAt': now,
      'nextElectionAt': nextElectionAt,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> castVote({
    required String unitId,
    required String voterId,
    required String candidateId,
    String? signerId,
  }) async {
    final data = {
      'unitId': unitId,
      'voterId': voterId,
      'candidateId': candidateId,
      'timestamp': FieldValue.serverTimestamp(),
    };

    if (signerId != null) {
      data['signerId'] = signerId;
    }

    await _firestore
        .collection('governance_votes')
        .doc('${unitId}_$voterId')
        .set(data);
  }

  Future<void> saveElectionResult(ElectionResult result) async {
    await _firestore
        .collection('governance_history')
        .doc(result.id)
        .set(result.toJson());
  }

  Future<List<ElectionResult>> getElectionHistory(String unitId) async {
    final snapshot = await _firestore
        .collection('governance_history')
        .where('unitId', isEqualTo: unitId)
        .orderBy('timestamp', descending: true)
        .limit(100)
        .get();
    final list = snapshot.docs
        .map((doc) => ElectionResult.fromJson(doc.data()))
        .toList();
    _historyCache[unitId] = list;
    return list;
  }

  Stream<List<GovernanceUnit>> watchActiveElections() {
    return Stream.multi((controller) {
      final cached = _activeElectionsCache;
      if (cached != null) {
        controller.add(cached);
      }
      final sub = _firestore
          .collection('governance')
          .where('isActiveElection', isEqualTo: true)
          .limit(100)
          .snapshots()
          .listen(
            (snapshot) {
              final list = snapshot.docs.map((doc) {
                final data = doc.data();
                data['id'] ??= doc.id;
                final unit = GovernanceUnit.fromJson(data);
                _unitCache[unit.id] = unit;
                return unit;
              }).toList();
              _activeElectionsCache = list;
              controller.add(list);
            },
            onError: controller.addError,
            onDone: controller.close,
          );
      controller.onCancel = sub.cancel;
    });
  }

  Future<List<GovernanceUnit>> getGovernanceUnitsForUser(String userId) async {
    final snapshot = await _firestore
        .collection('governance')
        .where('councilMembers', arrayContains: userId)
        .limit(100)
        .get();

    return snapshot.docs.map((doc) {
      final data = doc.data();
      data['id'] ??= doc.id;
      final unit = GovernanceUnit.fromJson(data);
      _unitCache[unit.id] = unit;
      return unit;
    }).toList();
  }

  // ──── NEW: Role-Based Voting System ────

  /// Cast a role-specific vote with Yay/Nay/Hold verdict.
  /// Doc ID: ${unitId}_${role}_${candidateId}_${voterId} → 1 vote per voter per candidate per role.
  Future<void> castRoleVote({
    required String unitId,
    required String voterId,
    required String candidateId,
    required String role,
    required String verdict,
  }) async {
    final key = '${unitId}_$role';
    final existing = List<Map<String, dynamic>>.from(
      _roleVotesCache[key] ?? const [],
    );
    existing.removeWhere(
      (v) => v['candidateId'] == candidateId && v['voterId'] == voterId,
    );
    existing.add({
      'unitId': unitId,
      'role': role,
      'candidateId': candidateId,
      'voterId': voterId,
      'verdict': verdict,
    });
    _roleVotesCache[key] = existing;

    await FirebaseFunctions.instance.httpsCallable('castGovernanceVote').call({
      'unitId': unitId,
      'candidateId': candidateId,
      'role': role,
      'verdict': verdict,
    });
  }

  /// Get all votes for a specific candidate in a specific role.
  Future<List<Map<String, dynamic>>> getVotesForCandidateRole(
    String unitId,
    String candidateId,
    String role,
  ) async {
    final snapshot = await _firestore
        .collection('governance_votes')
        .where('unitId', isEqualTo: unitId)
        .where('candidateId', isEqualTo: candidateId)
        .where('role', isEqualTo: role)
        .limit(500)
        .get();
    return snapshot.docs.map((doc) => doc.data()).toList();
  }

  /// Stream votes for a specific role in a unit (live tallying).
  Stream<List<Map<String, dynamic>>> watchRoleVotes(
    String unitId,
    String role,
  ) {
    final key = '${unitId}_$role';
    return Stream.multi((controller) {
      final cached = _roleVotesCache[key];
      if (cached != null) {
        controller.add(cached);
      }
      final sub = _firestore
          .collection('governance_votes')
          .where('unitId', isEqualTo: unitId)
          .where('role', isEqualTo: role)
          .limit(500)
          .snapshots()
          .listen(
            (s) {
              final list = s.docs.map((d) => d.data()).toList();
              _roleVotesCache[key] = list;
              controller.add(list);
            },
            onError: controller.addError,
            onDone: controller.close,
          );
      controller.onCancel = sub.cancel;
    });
  }

  /// Get vote summary (yay/nay/abstain counts) for a candidate.
  Future<VoteSummary> getCandidateVoteSummary(
    String unitId,
    String candidateId,
    String role,
  ) async {
    final votes = await getVotesForCandidateRole(unitId, candidateId, role);
    int yay = 0, nay = 0, abstain = 0;
    for (final vote in votes) {
      switch (vote['verdict'] as String?) {
        case VoteVerdict.yay:
          yay++;
          break;
        case VoteVerdict.nay:
          nay++;
          break;
        case VoteVerdict.abstain:
          abstain++;
          break;
      }
    }
    return VoteSummary(
      candidateId: candidateId,
      role: role,
      yayCount: yay,
      nayCount: nay,
      abstainCount: abstain,
    );
  }

  /// Add a user to the role-specific candidate list.
  Future<void> addRoleCandidate(
    String unitId,
    String userId,
    String role,
  ) async {
    final cached = _unitCache[unitId];
    if (cached != null) {
      final json = cached.toJson();
      final roleCandidates = Map<String, dynamic>.from(
        json['roleCandidates'] as Map? ?? {},
      );
      final current = List<String>.from(roleCandidates[role] as List? ?? []);
      if (!current.contains(userId)) current.add(userId);
      roleCandidates[role] = current;
      json['roleCandidates'] = roleCandidates;
      _unitCache[unitId] = GovernanceUnit.fromJson(json);
    }
    await _firestore.collection('governance').doc(unitId).set({
      'roleCandidates': {
        role: FieldValue.arrayUnion([userId]),
      },
    }, SetOptions(merge: true));
  }

  /// Remove a user from the role-specific candidate list.
  Future<void> removeRoleCandidate(
    String unitId,
    String userId,
    String role,
  ) async {
    await _firestore.collection('governance').doc(unitId).update({
      'roleCandidates.$role': FieldValue.arrayRemove([userId]),
    });
  }

  /// Update council: add member with role.
  Future<void> addCouncilMember(
    String unitId,
    String userId,
    String role,
  ) async {
    await _firestore.collection('governance').doc(unitId).update({
      'councilMembers': FieldValue.arrayUnion([userId]),
      'councilRoles.$userId': role,
    });
  }

  /// Remove a council member (vote-out).
  Future<void> removeCouncilMember(String unitId, String userId) async {
    await _firestore.collection('governance').doc(unitId).update({
      'councilMembers': FieldValue.arrayRemove([userId]),
      'councilRoles.$userId': FieldValue.delete(),
    });
  }

  /// Get community member IDs by looking up the community group chat participants.
  Future<List<String>> getCommunityMemberIds(String communityId) async {
    // Try group chat participants first
    final chatDoc = await _firestore
        .collection('chats')
        .doc('community_$communityId')
        .get();
    if (chatDoc.exists) {
      final data = chatDoc.data();
      final participants = data?['participants'] as List<dynamic>?;
      if (participants != null && participants.isNotEmpty) {
        final list = participants.cast<String>();
        _communityMemberIdsCache[communityId] = list;
        return list;
      }
    }

    // Fallback: query community_members subcollection
    final membersSnapshot = await _firestore
        .collection('communities')
        .doc(communityId)
        .collection('members')
        .limit(500)
        .get();
    final list = membersSnapshot.docs.map((d) => d.id).toList();
    _communityMemberIdsCache[communityId] = list;
    return list;
  }

  /// Check if a user has already voted for a specific candidate in a role.
  Future<bool> hasVotedForCandidateRole(
    String unitId,
    String voterId,
    String candidateId,
    String role,
  ) async {
    final cachedVotes = _roleVotesCache['${unitId}_$role'];
    if (cachedVotes != null) {
      return cachedVotes.any(
        (v) => v['candidateId'] == candidateId && v['voterId'] == voterId,
      );
    }
    final snapshot = await _firestore
        .collection('governance_votes')
        .where('unitId', isEqualTo: unitId)
        .where('role', isEqualTo: role)
        .where('candidateId', isEqualTo: candidateId)
        .where('voterId', isEqualTo: voterId)
        .limit(1)
        .get();
    return snapshot.docs.isNotEmpty;
  }
}
