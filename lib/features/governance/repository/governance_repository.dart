import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rxdart/rxdart.dart';
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

  Future<GovernanceUnit?> getGovernanceUnit(String id) async {
    final doc = await _firestore.collection('governance').doc(id).get();
    if (!doc.exists) return null;
    final data = doc.data()!;
    data['id'] ??= doc.id;
    data['name'] ??= doc.id.replaceAll('_', ' ').toUpperCase();
    data['type'] ??= 'local'; // Default type if missing
    return GovernanceUnit.fromJson(data);
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
    return GovernanceUnit.fromJson(data);
  }

  Future<void> saveGovernanceUnit(GovernanceUnit unit) async {
    await _firestore.collection('governance').doc(unit.id).set(unit.toJson());
  }

  Stream<GovernanceUnit?> watchGovernanceUnit(String id) {
    return _firestore
        .collection('governance')
        .doc(id)
        .snapshots()
        .map((doc) {
          if (!doc.exists) return null;
          final data = doc.data()!;
          data['id'] ??= doc.id;
          return GovernanceUnit.fromJson(data);
        })
        .onErrorReturn(null)
        .startWith(null);
  }

  Future<void> updateSigners(String id, List<String> signerIds) async {
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
    return snapshot.docs.map((doc) => doc.data()).toList();
  }

  Stream<List<Map<String, dynamic>>> watchVotes(String unitId) {
    return _firestore
        .collection('governance_votes')
        .where('unitId', isEqualTo: unitId)
        .limit(500)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) => doc.data()).toList());
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
    return snapshot.docs
        .map((doc) => ElectionResult.fromJson(doc.data()))
        .toList();
  }

  Stream<List<GovernanceUnit>> watchActiveElections() {
    return _firestore
        .collection('governance')
        .where('isActiveElection', isEqualTo: true)
        .limit(100)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs.map((doc) {
            final data = doc.data();
            data['id'] ??= doc.id;
            return GovernanceUnit.fromJson(data);
          }).toList(),
        );
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
      return GovernanceUnit.fromJson(data);
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
    return _firestore
        .collection('governance_votes')
        .where('unitId', isEqualTo: unitId)
        .where('role', isEqualTo: role)
        .limit(500)
        .snapshots()
        .map((s) => s.docs.map((d) => d.data()).toList());
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
        return participants.cast<String>();
      }
    }

    // Fallback: query community_members subcollection
    final membersSnapshot = await _firestore
        .collection('communities')
        .doc(communityId)
        .collection('members')
        .limit(500)
        .get();
    return membersSnapshot.docs.map((d) => d.id).toList();
  }

  /// Check if a user has already voted for a specific candidate in a role.
  Future<bool> hasVotedForCandidateRole(
    String unitId,
    String voterId,
    String candidateId,
    String role,
  ) async {
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
