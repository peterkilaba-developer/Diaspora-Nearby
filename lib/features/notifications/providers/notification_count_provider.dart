import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:diaspora_nearby/features/auth/repository/auth_repository.dart';
import 'package:diaspora_nearby/features/notifications/models/notification_item.dart';
import 'package:diaspora_nearby/features/notifications/repository/notifications_repository.dart';

/// Streams the count of unread notifications for the current user.
final unreadNotificationCountProvider = StreamProvider.autoDispose<int>((ref) {
  final user = ref.watch(authRepositoryProvider).currentUser;
  if (user == null) return Stream.value(0);

  return ref
      .watch(notificationsRepositoryProvider)
      .watchUnreadCount(user.uid);
});

/// Streams the count of pending action-required notifications.
/// This is used for the bell icon badge on the home screen so users
/// always know there is unfinished business.
final pendingActionCountProvider = StreamProvider.autoDispose<int>((ref) {
  final user = ref.watch(authRepositoryProvider).currentUser;
  if (user == null) return Stream.value(0);

  return ref
      .watch(notificationsRepositoryProvider)
      .watchPendingActionCount(user.uid);
});

/// Streams all notifications for the current user (newest first).
final notificationsStreamProvider =
    StreamProvider.autoDispose<List<NotificationItem>>((ref) {
  final user = ref.watch(authRepositoryProvider).currentUser;
  if (user == null) return Stream.value([]);

  return ref
      .watch(notificationsRepositoryProvider)
      .watchNotifications(user.uid);
});

/// Streams only action-required notifications (pending user action).
final actionRequiredNotificationsProvider =
    StreamProvider.autoDispose<List<NotificationItem>>((ref) {
  final user = ref.watch(authRepositoryProvider).currentUser;
  if (user == null) return Stream.value([]);

  return ref
      .watch(notificationsRepositoryProvider)
      .watchActionRequired(user.uid);
});
