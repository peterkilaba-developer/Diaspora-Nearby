import 'package:cloud_firestore/cloud_firestore.dart' as cf;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:diaspora_nearby/features/dsp/services/points_service.dart';
import 'package:diaspora_nearby/features/profile/repository/relationship_repository.dart';
import 'package:diaspora_nearby/features/trust/services/trust_service.dart';

final reportRepositoryProvider = Provider((ref) => ReportRepository(ref));

class ReportRepository {
  final cf.FirebaseFirestore _firestore = cf.FirebaseFirestore.instance;
  final Ref _ref;

  ReportRepository(this._ref);

  Future<bool> reportMessage({
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
        return true;
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

      // 3. [UPDATED] Check unique reporter threshold for automated HTS signal
      final snapshot = await _firestore
          .collection('reports')
          .where('type', isEqualTo: 'message')
          .where('messageId', isEqualTo: messageId)
          .get();

      final uniqueReporters = snapshot.docs
          .map((d) => (d.data())['reporterId'])
          .toSet();

      if (uniqueReporters.isNotEmpty && uniqueReporters.length % 10 == 0) {
        debugPrint(
          '🚨 [ReportRepository] Message $messageId reached ${uniqueReporters.length} unique reports. Deducting -10 PoCT from $senderId.',
        );

        // [UPDATED v8] DSP deduction removed — only PoCT milestone deduction
        // -10 PoCT per 10 unique reporters
        final trustService = _ref.read(trustServiceProvider);
        await trustService.recordActivity(senderId, HTSActivityType.flaggedMessage);

        // Chat ad penalty (PoCT-only, no DSP) still triggers trust recalculation
        if (reason == 'Prohibited Advertising' || reason == 'Spam or Scam') {
          await _ref.read(pointsServiceProvider).trackChatAdPenalty(senderId);
        }
      }

      return true;
    } catch (e) {
      debugPrint('Error reporting message: $e');
      return false;
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

  Future<bool> reportUser({
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
        return false;
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

      // 3. Count unique reporters for this user
      final snapshot = await _firestore
          .collection('reports')
          .where('type', isEqualTo: 'user')
          .where('reportedUserId', isEqualTo: reportedUserId)
          .get();

      final uniqueReporters = snapshot.docs
          .map((d) => (d.data())['reporterId'])
          .toSet();

      // 4. [UPDATED v8] At every 10 unique reporters → deduct -10 PoCT (no DSP)
      if (uniqueReporters.isNotEmpty && uniqueReporters.length % 10 == 0) {
        debugPrint(
          '🚨 [ReportRepository] User $reportedUserId reached ${uniqueReporters.length} unique user reports. Deducting -10 PoCT.',
        );

        // [UPDATED v8] DSP deduction removed — only PoCT milestone
        // HTS signal triggers trust recalculation which handles PoCT
        await _ref
            .read(trustServiceProvider)
            .recordActivity(reportedUserId, HTSActivityType.flaggedMessage);
      }

      return true;
    } catch (e) {
      debugPrint('Error reporting user: $e');
      return false;
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
