import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:diaspora_nearby/features/notifications/models/notification_item.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Provider
// ─────────────────────────────────────────────────────────────────────────────

final notificationsRepositoryProvider = Provider<NotificationsRepository>((
  ref,
) {
  return NotificationsRepository(FirebaseFirestore.instance);
});

// ─────────────────────────────────────────────────────────────────────────────
// Repository
// ─────────────────────────────────────────────────────────────────────────────

class NotificationsRepository {
  final FirebaseFirestore _firestore;

  NotificationsRepository(this._firestore);

  /// Subcollection path for a user's notifications.
  CollectionReference<Map<String, dynamic>> _userNotifications(String userId) {
    return _firestore
        .collection('users')
        .doc(userId)
        .collection('notifications');
  }

  // ── Write ────────────────────────────────────────────────────────────

  /// Create a new notification for [userId].
  /// Returns the generated document ID.
  Future<String> addNotification(String userId, NotificationItem item) async {
    try {
      final docRef = await _userNotifications(userId).add(item.toMap());
      debugPrint(
        '🔔 [NotificationsRepo] Added notification ${docRef.id} for user $userId',
      );
      return docRef.id;
    } catch (e) {
      debugPrint('❌ [NotificationsRepo] Error adding notification: $e');
      rethrow;
    }
  }

  /// Create a notification only if no duplicate exists (by dedup key).
  /// [dedupKey] should be a unique string like "hosting_interest_{requestId}_{hostId}".
  Future<void> addIfNotDuplicate({
    required String userId,
    required String dedupKey,
    required NotificationItem item,
  }) async {
    try {
      final existing = await _userNotifications(
        userId,
      ).where('payload.dedupKey', isEqualTo: dedupKey).limit(1).get();

      if (existing.docs.isEmpty) {
        final data = item.toMap();
        // Embed the dedup key inside the payload for future lookups
        (data['payload'] as Map<String, dynamic>)['dedupKey'] = dedupKey;
        await _userNotifications(userId).add(data);
        debugPrint(
          '🔔 [NotificationsRepo] Added notification (dedup: $dedupKey)',
        );
      } else {
        // Update the existing notification's body/title if needed
        await existing.docs.first.reference.update({
          'title': item.title,
          'body': item.body,
          'isRead': false, // Re-surface as unread
          'actionCompleted': false,
          'createdAt': Timestamp.fromDate(item.createdAt),
        });
        debugPrint(
          '🔔 [NotificationsRepo] Updated existing notification (dedup: $dedupKey)',
        );
      }
    } catch (e) {
      debugPrint('❌ [NotificationsRepo] Error in addIfNotDuplicate: $e');
    }
  }

  // ── Update ───────────────────────────────────────────────────────────

  /// Mark a single notification as read.
  Future<void> markAsRead(String userId, String notificationId) async {
    try {
      await _userNotifications(
        userId,
      ).doc(notificationId).update({'isRead': true});
    } catch (e) {
      debugPrint('❌ [NotificationsRepo] Error marking as read: $e');
    }
  }

  /// Mark all notifications as read.
  Future<void> markAllAsRead(String userId) async {
    try {
      final unread = await _userNotifications(
        userId,
      ).where('isRead', isEqualTo: false).limit(500).get();
      final batch = _firestore.batch();
      for (final doc in unread.docs) {
        batch.update(doc.reference, {'isRead': true});
      }
      await batch.commit();
      debugPrint(
        '🔔 [NotificationsRepo] Marked ${unread.docs.length} notifications as read',
      );
    } catch (e) {
      debugPrint('❌ [NotificationsRepo] Error marking all as read: $e');
    }
  }

  /// Mark a notification's action as completed.
  Future<void> markActionCompleted(String userId, String notificationId) async {
    try {
      await _userNotifications(
        userId,
      ).doc(notificationId).update({'actionCompleted': true, 'isRead': true});
    } catch (e) {
      debugPrint('❌ [NotificationsRepo] Error marking action completed: $e');
    }
  }

  /// Mark a notification's action as completed by its dedup key.
  /// This is used when actions are completed outside the notifications screen
  /// (e.g. accepting a relationship request from the profile page).
  Future<void> markActionCompletedByDedupKey(
    String userId,
    String dedupKey,
  ) async {
    try {
      final snap = await _userNotifications(
        userId,
      ).where('payload.dedupKey', isEqualTo: dedupKey).limit(1).get();
      if (snap.docs.isNotEmpty) {
        await snap.docs.first.reference.update({
          'actionCompleted': true,
          'isRead': true,
        });
        debugPrint(
          '🔔 [NotificationsRepo] Marked action completed by dedupKey: $dedupKey',
        );
      }
    } catch (e) {
      debugPrint(
        '❌ [NotificationsRepo] Error marking action completed by dedupKey: $e',
      );
    }
  }

  // ── Delete ───────────────────────────────────────────────────────────

  /// Delete a single notification.
  Future<void> deleteNotification(String userId, String notificationId) async {
    try {
      await _userNotifications(userId).doc(notificationId).delete();
    } catch (e) {
      debugPrint('❌ [NotificationsRepo] Error deleting notification: $e');
    }
  }

  /// Clear all notifications for a user.
  Future<void> clearAll(String userId) async {
    try {
      final all = await _userNotifications(userId).limit(500).get();
      final batch = _firestore.batch();
      for (final doc in all.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    } catch (e) {
      debugPrint('❌ [NotificationsRepo] Error clearing all: $e');
    }
  }

  // ── Read / Stream ────────────────────────────────────────────────────

  /// Stream all notifications for a user, ordered by createdAt descending.
  Stream<List<NotificationItem>> watchNotifications(String userId) {
    return _userNotifications(userId)
        .orderBy('createdAt', descending: true)
        .limit(100)
        .snapshots()
        .map(
          (snap) => snap.docs
              .map((doc) => NotificationItem.fromMap(doc.id, doc.data()))
              .toList(),
        );
  }

  /// Stream only actionable (action required & not completed) notifications.
  Stream<List<NotificationItem>> watchActionRequired(String userId) {
    return _userNotifications(userId)
        .where('actionRequired', isEqualTo: true)
        .where('actionCompleted', isEqualTo: false)
        .orderBy('createdAt', descending: true)
        .limit(100)
        .snapshots()
        .map(
          (snap) => snap.docs
              .map((doc) => NotificationItem.fromMap(doc.id, doc.data()))
              .toList(),
        );
  }

  /// Stream completed action-required notifications.
  Stream<List<NotificationItem>> watchCompletedActions(String userId) {
    return _userNotifications(userId)
        .where('actionRequired', isEqualTo: true)
        .where('actionCompleted', isEqualTo: true)
        .orderBy('createdAt', descending: true)
        .limit(50)
        .snapshots()
        .map(
          (snap) => snap.docs
              .map((doc) => NotificationItem.fromMap(doc.id, doc.data()))
              .toList(),
        );
  }

  /// Stream count of unread notifications.
  Stream<int> watchUnreadCount(String userId) {
    return _userNotifications(userId)
        .where('isRead', isEqualTo: false)
        .limit(500)
        .snapshots()
        .map((snap) => snap.docs.length);
  }

  /// Stream count of pending action-required notifications (not yet completed).
  Stream<int> watchPendingActionCount(String userId) {
    return _userNotifications(userId)
        .where('actionRequired', isEqualTo: true)
        .where('actionCompleted', isEqualTo: false)
        .limit(500)
        .snapshots()
        .map((snap) => snap.docs.length);
  }

  /// One-shot fetch of all notifications for a user.
  Future<List<NotificationItem>> getNotificationsOnce(String userId) async {
    final snap = await _userNotifications(
      userId,
    ).orderBy('createdAt', descending: true).limit(200).get();
    return snap.docs
        .map((d) => NotificationItem.fromMap(d.id, d.data()))
        .toList();
  }
}
