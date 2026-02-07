import 'package:cloud_firestore/cloud_firestore.dart' as cf;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:diaspora_nearby/features/dsp/services/points_service.dart';
import 'package:diaspora_nearby/features/profile/repository/relationship_repository.dart';

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

      // 3. [NEW] Check unique reporter threshold for automated penalty
      final snapshot = await _firestore
          .collection('reports')
          .where('type', isEqualTo: 'message')
          .where('messageId', isEqualTo: messageId)
          .get();

      // Filter for unique reporters just in case (though we checked for existing above)
      final uniqueReporters = snapshot.docs.map((d) => d.data()['reporterId']).toSet();

      if (uniqueReporters.length == 5) {
        debugPrint('🚨 [ReportRepository] Message $messageId reached 5 unique reports. Triggering automated penalties.');
        
        // A. Trigger immediate Spam Penalty (proportional 1% or min 100 DSP)
        await _ref.read(pointsServiceProvider).reportSpam(senderId);

        // B. Increment author's flaggedMessagesCount and check for Fraud trigger
        final authorRef = _firestore.collection('users').doc(senderId);
        bool shouldTriggerFraudPenalty = false;

        await _firestore.runTransaction((transaction) async {
          final authorSnap = await transaction.get(authorRef);
          if (authorSnap.exists) {
            final data = authorSnap.data()!;
            final currentCount = (data['flaggedMessagesCount'] as num?)?.toInt() ?? 0;
            final newCount = currentCount + 1;
            
            transaction.update(authorRef, {'flaggedMessagesCount': newCount});
            
            if (newCount == 5) {
              shouldTriggerFraudPenalty = true;
            }
          }
        });

        if (shouldTriggerFraudPenalty) {
          debugPrint('🚨 [ReportRepository] User $senderId reached 5 flagged messages. Triggering automatic Fraud Penalty.');
          // recordFraudPenalty is proportional (10% or min 5,000 DSP)
          await _ref.read(pointsServiceProvider).recordFraudPenalty(senderId);
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
    await _ref.read(relationshipRepositoryProvider).blockUser(
      userId: currentUserId,
      relatedUserId: targetUserId,
    );
  }

  Future<void> unblockUser(String currentUserId, String targetUserId) async {
    // Delegate to RelationshipRepository
    await _ref.read(relationshipRepositoryProvider).unblockUser(
      userId: currentUserId,
      relatedUserId: targetUserId,
    );
  }

  Future<void> reportUser({
    required String reporterId,
    required String reportedUserId,
    required String reason,
  }) async {
    try {
      await _firestore.collection('reports').add({
        'reporterId': reporterId,
        'reportedUserId': reportedUserId,
        'reason': reason,
        'timestamp': cf.FieldValue.serverTimestamp(),
        'type': 'user',
        'status': 'pending',
      });
    } catch (e) {
      debugPrint('Error reporting user: $e');
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
