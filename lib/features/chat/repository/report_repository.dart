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
          '🚨 [ReportRepository] Message $messageId reached ${uniqueReporters.length} unique reports. Deducting 100 DSP + 1 PoCT from $senderId.',
        );

        // Deduct 100 DSP + 1 PoCT from the message sender
        final pointsService = _ref.read(pointsServiceProvider);
        await pointsService.deductPoints(
          userId: senderId,
          amount: 100,
          reason: 'reported_message_milestone_${uniqueReporters.length ~/ 10}',
        );
        await pointsService.deductPoints(
          userId: senderId,
          amount: 1,
          reason: 'poct_reported_message_milestone_${uniqueReporters.length ~/ 10}',
        );

        // Use TrustService for automated penalty/score recalculation
        await _ref
            .read(trustServiceProvider)
            .recordActivity(senderId, HTSActivityType.flaggedMessage);

        // Charge Ad Penalty if reported for advertising/spam
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

      // 4. At every 10 unique reporters → deduct 100 DSP + 1 PoCT from reported user
      if (uniqueReporters.isNotEmpty && uniqueReporters.length % 10 == 0) {
        debugPrint(
          '🚨 [ReportRepository] User $reportedUserId reached ${uniqueReporters.length} unique user reports. Deducting 100 DSP + 1 PoCT.',
        );

        final pointsService = _ref.read(pointsServiceProvider);
        await pointsService.deductPoints(
          userId: reportedUserId,
          amount: 100,
          reason: 'reported_user_milestone_${uniqueReporters.length ~/ 10}',
        );
        await pointsService.deductPoints(
          userId: reportedUserId,
          amount: 1,
          reason: 'poct_reported_user_milestone_${uniqueReporters.length ~/ 10}',
        );

        // HTS signal
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
