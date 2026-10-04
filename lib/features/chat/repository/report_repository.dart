import 'package:cloud_firestore/cloud_firestore.dart' as cf;
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:diaspora_nearby/features/profile/repository/relationship_repository.dart';

final reportRepositoryProvider = Provider((ref) => ReportRepository(ref));

/// Outcome of a report submission. Callers use this to decide whether to award
/// the +100 DSP report reward (only on `success`, never on `duplicate`).
enum ReportResult { success, duplicate, failed }

class ReportRepository {
  final cf.FirebaseFirestore _firestore = cf.FirebaseFirestore.instance;
  final FirebaseFunctions _functions = FirebaseFunctions.instance;
  final Ref _ref;

  ReportRepository(this._ref);

  Future<ReportResult> reportMessage({
    required String reporterId,
    required String chatId,
    required String messageId,
    required String senderId,
    required String reason,
  }) async {
    try {
      final result = await _functions.httpsCallable('submitReport').call({
        'type': 'message',
        'reporterId': reporterId,
        'chatId': chatId,
        'messageId': messageId,
        'reportedUserId': senderId,
        'reason': reason,
      });
      final data = Map<String, dynamic>.from(result.data as Map);
      return data['duplicate'] == true
          ? ReportResult.duplicate
          : ReportResult.success;
    } catch (e) {
      debugPrint('Error reporting message: $e');
      return ReportResult.failed;
    }
  }

  Future<void> blockUser(String currentUserId, String targetUserId) async {
    // Delegate to RelationshipRepository to ensure consistent logic (increments blockedByCount, etc)
    await _ref
        .read(relationshipRepositoryProvider)
        .blockUser(userId: currentUserId, relatedUserId: targetUserId);
  }

  Future<void> unblockUser(String currentUserId, String targetUserId) async {
    // Delegate to RelationshipRepository
    await _ref
        .read(relationshipRepositoryProvider)
        .unblockUser(userId: currentUserId, relatedUserId: targetUserId);
  }

  Future<ReportResult> reportUser({
    required String reporterId,
    required String reportedUserId,
    required String reason,
  }) async {
    try {
      final result = await _functions.httpsCallable('submitReport').call({
        'type': 'user',
        'reporterId': reporterId,
        'reportedUserId': reportedUserId,
        'reason': reason,
      });
      final data = Map<String, dynamic>.from(result.data as Map);
      return data['duplicate'] == true
          ? ReportResult.duplicate
          : ReportResult.success;
    } catch (e) {
      debugPrint('Error reporting user: $e');
      return ReportResult.failed;
    }
  }

  Future<int> getReportCount(String userId) async {
    try {
      final snapshot = await _firestore
          .collection('reports')
          .where('reportedUserId', isEqualTo: userId)
          .count()
          .get();
      return snapshot.count ?? 0;
    } catch (e) {
      debugPrint('Error getting report count: $e');
      return 0;
    }
  }
}
