import 'package:cloud_firestore/cloud_firestore.dart' as cf;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final reportRepositoryProvider = Provider((ref) => ReportRepository());

class ReportRepository {
  final cf.FirebaseFirestore _firestore = cf.FirebaseFirestore.instance;

  Future<bool> reportMessage({
    required String reporterId,
    required String messageId,
    required String senderId,
    required String reason,
  }) async {
    try {
      await _firestore.collection('reports').add({
        'reporterId': reporterId,
        'messageId': messageId,
        'reportedUserId': senderId,
        'reason': reason,
        'timestamp': cf.FieldValue.serverTimestamp(),
        'type': 'message',
        'status': 'pending',
      });
      return true;
    } catch (e) {
      debugPrint('Error reporting message: $e');
      return false;
    }
  }

  Future<void> blockUser(String currentUserId, String targetUserId) async {
    try {
      final userDoc = await _firestore.collection('users').doc(currentUserId).get();
      if (userDoc.exists) {
        final List<String> blockedUsers = List<String>.from(userDoc.data()?['blockedUsers'] ?? []);
        if (!blockedUsers.contains(targetUserId)) {
          blockedUsers.add(targetUserId);
          await _firestore.collection('users').doc(currentUserId).update({
            'blockedUsers': blockedUsers,
          });
        }
      }
    } catch (e) {
      debugPrint('Error blocking user: $e');
    }
  }

  Future<void> unblockUser(String currentUserId, String targetUserId) async {
    try {
      final userDoc = await _firestore.collection('users').doc(currentUserId).get();
      if (userDoc.exists) {
        final List<String> blockedUsers = List<String>.from(userDoc.data()?['blockedUsers'] ?? []);
        if (blockedUsers.contains(targetUserId)) {
          blockedUsers.remove(targetUserId);
          await _firestore.collection('users').doc(currentUserId).update({
            'blockedUsers': blockedUsers,
          });
        }
      }
    } catch (e) {
      debugPrint('Error unblocking user: $e');
    }
  }
}
