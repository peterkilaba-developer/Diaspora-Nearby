import 'package:cloud_firestore/cloud_firestore.dart';

/// Types of actionable/system notifications stored in Firestore.
enum NotificationType {
  /// A host showed interest in the traveler's hosting request
  hostingInterest,

  /// The traveler selected a host — notifies the host
  hostingSelected,

  /// Hosting session status changed (check-in, end request, settled, etc.)
  hostingSessionEvent,

  /// Someone sent a relationship / connection request
  relationshipRequest,

  /// A relationship request was accepted
  relationshipAccepted,

  /// Invited to join a group chat
  groupInvitation,

  /// Emergency fund / proxy transfer request
  proxyRequest,

  /// DSP transfer received
  dspTransfer,

  /// Generic system notification
  system,
}

/// A persisted notification item stored under `users/{uid}/notifications/{id}`.
class NotificationItem {
  final String id;
  final NotificationType type;
  final String title;
  final String body;

  /// Arbitrary payload keyed by type.  e.g. { "requestId": "...", "hostId": "..." }
  final Map<String, dynamic> payload;

  /// Whether the user has seen / opened this notification.
  final bool isRead;

  /// Whether this notification requires user action (e.g. accept/decline).
  final bool actionRequired;

  /// Whether the required action has been completed.
  final bool actionCompleted;

  final DateTime createdAt;

  const NotificationItem({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    this.payload = const {},
    this.isRead = false,
    this.actionRequired = false,
    this.actionCompleted = false,
    required this.createdAt,
  });

  // ── Firestore serialization ──────────────────────────────────────────

  Map<String, dynamic> toMap() {
    return {
      'type': type.name,
      'title': title,
      'body': body,
      'payload': payload,
      'isRead': isRead,
      'actionRequired': actionRequired,
      'actionCompleted': actionCompleted,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }

  factory NotificationItem.fromMap(String id, Map<String, dynamic> map) {
    return NotificationItem(
      id: id,
      type: _parseType(map['type'] as String?),
      title: map['title'] as String? ?? '',
      body: map['body'] as String? ?? '',
      payload: (map['payload'] as Map<String, dynamic>?) ?? {},
      isRead: map['isRead'] as bool? ?? false,
      actionRequired: map['actionRequired'] as bool? ?? false,
      actionCompleted: map['actionCompleted'] as bool? ?? false,
      createdAt: _parseTimestamp(map['createdAt']),
    );
  }

  NotificationItem copyWith({
    String? id,
    NotificationType? type,
    String? title,
    String? body,
    Map<String, dynamic>? payload,
    bool? isRead,
    bool? actionRequired,
    bool? actionCompleted,
    DateTime? createdAt,
  }) {
    return NotificationItem(
      id: id ?? this.id,
      type: type ?? this.type,
      title: title ?? this.title,
      body: body ?? this.body,
      payload: payload ?? this.payload,
      isRead: isRead ?? this.isRead,
      actionRequired: actionRequired ?? this.actionRequired,
      actionCompleted: actionCompleted ?? this.actionCompleted,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  // ── Helpers ──────────────────────────────────────────────────────────

  static NotificationType _parseType(String? value) {
    if (value == null) return NotificationType.system;
    return NotificationType.values.firstWhere(
      (e) => e.name == value,
      orElse: () => NotificationType.system,
    );
  }

  static DateTime _parseTimestamp(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is String) return DateTime.parse(value);
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    return DateTime.now();
  }
}
