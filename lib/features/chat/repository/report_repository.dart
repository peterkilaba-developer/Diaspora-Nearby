import 'package:cloud_firestore/cloud_firestore.dart' as cf;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:diaspora_nearby/features/profile/repository/relationship_repository.dart';
import 'package:diaspora_nearby/features/trust/services/trust_service.dart';

final reportRepositoryProvider = Provider((ref) => ReportRepository(ref));

/// Outcome of a report submission. Callers use this to decide whether to award
/// the +100 DSP report reward (only on `success`, never on `duplicate`).
enum ReportResult { success, duplicate, failed }

class ReportRepository {
  final cf.FirebaseFirestore _firestore = cf.FirebaseFirestore.instance;
  final Ref _ref;

  ReportRepository(this._ref);

  Future<ReportResult> reportMessage({
    required String reporterId,
    required String messageId,
    required String senderId,
    required String reason,
  }) async {
    try {
      // 1. Check if this reporter already reported this message to avoid duplicates
      final existing = await _firestore
          .collection('reports')
          .where('type', isEqualTo: 'message')
          .where('messageId', isEqualTo: messageId)
          .where('reporterId', isEqualTo: reporterId)
          .get();

      if (existing.docs.isNotEmpty) {
        debugPrint('ℹ️ [ReportRepository] User already reported this message.');
        return ReportResult.duplicate;
      }

      // 2. Add the report record
      await _firestore.collection('reports').add({
        'reporterId': reporterId,
        'messageId': messageId,
        'reportedUserId': senderId,
        'reason': reason,
        'timestamp': cf.FieldValue.serverTimestamp(),
        'type': 'message',
        'status': 'pending',
      });

      // 3. Every unique new report on this user contributes 1 to
      //    profile.flaggedMessagesCount. P.o.C.T loss = -10 per 10 unique flags
      //    (see TrustService.recalculateTrustScore).
      await _ref
          .read(trustServiceProvider)
          .recordActivity(senderId, HTSActivityType.flaggedMessage);

      return ReportResult.success;
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
      // 1. Check for duplicate report by this reporter
      final existing = await _firestore
          .collection('reports')
          .where('type', isEqualTo: 'user')
          .where('reportedUserId', isEqualTo: reportedUserId)
          .where('reporterId', isEqualTo: reporterId)
          .get();

      if (existing.docs.isNotEmpty) {
        debugPrint('ℹ️ [ReportRepository] User already reported this sender.');
        return ReportResult.duplicate;
      }

      // 2. Add the report record
      await _firestore.collection('reports').add({
        'reporterId': reporterId,
        'reportedUserId': reportedUserId,
        'reason': reason,
        'timestamp': cf.FieldValue.serverTimestamp(),
        'type': 'user',
        'status': 'pending',
      });

      // 3. Every unique new report contributes 1 to
      //    profile.flaggedMessagesCount. P.o.C.T loss = -10 per 10 unique flags
      //    (see TrustService.recalculateTrustScore).
      await _ref
          .read(trustServiceProvider)
          .recordActivity(reportedUserId, HTSActivityType.flaggedMessage);

      return ReportResult.success;
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
