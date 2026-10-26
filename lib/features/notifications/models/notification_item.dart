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

  // ── Travel / Peer Bookings ──────────────────────────────────────────

  /// Guest created a booking request for a host's listing
  travelBookingRequest,

  /// Host confirmed a booking request
  travelBookingConfirmed,

  /// Host declined a booking request
  travelBookingDeclined,

  /// Guest or host cancelled an existing booking
  travelBookingCancelled,

  /// Reminder 24h before a confirmed trip
  travelTripReminder,

  // ── Events ──────────────────────────────────────────────────────────

  /// New event created in the user's community
  eventNew,

  /// Reminder before event start (24h / 1h)
  eventReminder,

  /// Organizer updated event details
  eventUpdate,

  /// Event the user joined was cancelled
  eventCancelled,

  /// Someone joined the organizer's event
  eventNewAttendee,

  // ── Governance / Elections ──────────────────────────────────────────

  /// An election started in the user's community
  electionStarted,

  /// Election ending within 24h
  electionEndingSoon,

  /// Election results are available
  electionResults,

  // ── Marketplace ─────────────────────────────────────────────────────

  /// Buyer inquired about seller's listing
  marketplaceInquiry,

  /// Listing the user saved changed status (sold, etc.)
  marketplaceStatusChange,

  /// Price drop on a saved listing
  marketplacePriceDrop,

  // ── Real Estate ─────────────────────────────────────────────────────

  /// Buyer inquired about a real estate listing
  realEstateInquiry,

  /// New property matching user's saved search
  realEstateMatch,

  /// Price changed on a saved property
  realEstatePriceChange,

  /// Property status changed (sold / rented)
  realEstateStatusChange,

  // ── Trust & Verification ────────────────────────────────────────────

  /// A peer verified the user's identity
  trustPeerVerified,

  /// A peer vouched for the user
  trustPeerVouched,

  /// A peer gave the user full trust (staked 1,000 DSP)
  trustFullTrustReceived,

  /// A peer gave the user no trust (staked 1,000 DSP)
  trustNoTrustReceived,

  /// Another staker agreed with the user's staked trust rating (+100 DSP consensus)
  trustStakeConsensusAgree,

  /// Another staker opposed the user's staked trust rating (-100 DSP slash)
  trustStakeConsensusDisagree,

  /// User reached a PCT milestone (10, 100, 1K, etc.)
  trustMilestone,

  // ── Community ───────────────────────────────────────────────────────

  /// User was auto-added to a community
  communityJoined,

  /// New member joined the user's community (for admins)
  communityNewMember,

  // ── Organization ────────────────────────────────────────────────────

  /// User was invited to join an organization
  orgInvitation,

  /// Admin posted an announcement to organization members
  orgAnnouncement,

  // ── Emergency Fund ──────────────────────────────────────────────────

  /// User staked DSP promissory for emergency fund
  emergencyFundStaked,

  /// User's annual contribution payment succeeded
  emergencyFundPaymentSuccess,

  /// User's emergency fund membership is now active
  emergencyFundMembershipActive,

  /// User's staked DSP has been refunded after payment
  emergencyFundDspRefunded,

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
    switch (value) {
      case 'trust_full_trust_received':
        return NotificationType.trustFullTrustReceived;
      case 'trust_no_trust_received':
        return NotificationType.trustNoTrustReceived;
      case 'trust_stake_consensus_agree':
        return NotificationType.trustStakeConsensusAgree;
      case 'trust_stake_consensus_disagree':
        return NotificationType.trustStakeConsensusDisagree;
    }
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
