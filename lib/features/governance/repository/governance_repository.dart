import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/governance_unit.dart';
import '../models/election_result.dart';

final governanceRepositoryProvider = Provider((ref) => GovernanceRepository());

class GovernanceRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<GovernanceUnit?> getGovernanceUnit(String id) async {
    final doc = await _firestore.collection('governance').doc(id).get();
    if (!doc.exists) return null;
    return GovernanceUnit.fromJson(doc.data()!);
  }

  Future<GovernanceUnit?> getGovernanceUnitByCommunityId(String communityId) async {
    final snapshot = await _firestore
        .collection('governance')
        .where('communityId', isEqualTo: communityId)
        .limit(1)
        .get();
    if (snapshot.docs.isEmpty) return null;
    return GovernanceUnit.fromJson(snapshot.docs.first.data());
  }

  Future<void> saveGovernanceUnit(GovernanceUnit unit) async {
    await _firestore.collection('governance').doc(unit.id).set(unit.toJson());
  }

  Stream<GovernanceUnit?> watchGovernanceUnit(String id) {
    return _firestore
        .collection('governance')
        .doc(id)
        .snapshots()
        .map((doc) => doc.exists ? GovernanceUnit.fromJson(doc.data()!) : null);
  }

  Future<void> updateSigners(String id, List<String> signerIds) async {
    await _firestore.collection('governance').doc(id).update({
      'signers': signerIds,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> updateGovernanceStructure(String id, {List<String>? councilMembers, List<String>? signers}) async {
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
        .get();
    return snapshot.docs.map((doc) => doc.data()).toList();
  }

  Future<void> startElection(String id, int durationDays) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final endTime = now + (durationDays * 24 * 60 * 60 * 1000);
    await _firestore.collection('governance').doc(id).set({
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

    await _firestore.collection('governance_votes').doc('${unitId}_$voterId').set(data);
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
        .get();
    return snapshot.docs.map((doc) => ElectionResult.fromJson(doc.data())).toList();
  }

  Stream<List<GovernanceUnit>> watchActiveElections() {
    return _firestore
        .collection('governance')
        .where('isActiveElection', isEqualTo: true)
        .snapshots()
        .map((snapshot) =>
            snapshot.docs.map((doc) => GovernanceUnit.fromJson(doc.data())).toList());
  }
}
