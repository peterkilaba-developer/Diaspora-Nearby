import 'package:cloud_firestore/cloud_firestore.dart';

/// Status of a hosting session (after match is confirmed)
enum HostingSessionStatus {
  /// Both parties agreed, waiting for QR check-in
  confirmed,

  /// Traveler checked in via QR — session is live
  active,

  /// One party initiated end, waiting for the other to confirm
  endRequested,

  /// Both confirmed end — settlement pending
  ended,

  /// Both parties confirmed completion
  settled,

  /// Session was cancelled before check-in
  cancelled,
}

/// Represents an active or completed hosting session between a traveler and host.
///
/// Created when both parties agree on the arrangement.
/// Tracks check-in/check-out times and session completion.
///
/// Firestore collection: `hosting_sessions`
class HostingSession {
  final String id;

  // Linked hosting request
  final String requestId;

  // Participants
  final String travelerId;
  final String travelerName;
  final String? travelerPhoto;
  final String hostId;
  final String hostName;
  final String? hostPhoto;

  // Community context
  final String communityId;
  final String communityName;

  // Session timing
  final DateTime? checkInTime; // Set when QR scanned
  final DateTime? checkOutTime; // Set when both confirm end
  final DateTime plannedArrival; // From the original request
  final DateTime plannedDeparture; // From the original request

  // Completion
  final int? actualDays; // Calculated at checkout
  final int?
  totalDspCharged; // [DEPRECATED] Historical field — no longer written
  final bool travelerSettled; // Traveler confirmed the settlement
  final bool hostSettled; // Host confirmed the settlement

  // End-request tracking
  final String? endRequestedBy; // userId who initiated the end
  final DateTime? endRequestedAt;

  // Status
  final HostingSessionStatus status;
  final DateTime createdAt;
  final DateTime? updatedAt;

  // DM chat reference (for in-context messages)
  final String? chatId;

  const HostingSession({
    required this.id,
    required this.requestId,
    required this.travelerId,
    required this.travelerName,
    this.travelerPhoto,
    required this.hostId,
    required this.hostName,
    this.hostPhoto,
    required this.communityId,
    required this.communityName,
    this.checkInTime,
    this.checkOutTime,
    required this.plannedArrival,
    required this.plannedDeparture,
    this.actualDays,
    this.totalDspCharged,
    this.travelerSettled = false,
    this.hostSettled = false,
    this.endRequestedBy,
    this.endRequestedAt,
    this.status = HostingSessionStatus.confirmed,
    required this.createdAt,
    this.updatedAt,
    this.chatId,
  });

  /// Whether the session is currently live
  bool get isActive => status == HostingSessionStatus.active;

  /// Whether settlment is complete
  bool get isSettled => status == HostingSessionStatus.settled;

  /// Duration of the actual stay (null if not yet checked out)
  int? get stayDurationDays {
    if (checkInTime == null) return null;
    final end = checkOutTime ?? DateTime.now();
    final days = end.difference(checkInTime!).inDays;
    return days < 1 ? 1 : days; // Minimum 1 day
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'requestId': requestId,
      'travelerId': travelerId,
      'travelerName': travelerName,
      'travelerPhoto': travelerPhoto,
      'hostId': hostId,
      'hostName': hostName,
      'hostPhoto': hostPhoto,
      'communityId': communityId,
      'communityName': communityName,
      'checkInTime': checkInTime != null
          ? Timestamp.fromDate(checkInTime!)
          : null,
      'checkOutTime': checkOutTime != null
          ? Timestamp.fromDate(checkOutTime!)
          : null,
      'plannedArrival': Timestamp.fromDate(plannedArrival),
      'plannedDeparture': Timestamp.fromDate(plannedDeparture),
      'actualDays': actualDays,
      'totalDspCharged': totalDspCharged,
      'travelerSettled': travelerSettled,
      'hostSettled': hostSettled,
      'endRequestedBy': endRequestedBy,
      'endRequestedAt': endRequestedAt != null
          ? Timestamp.fromDate(endRequestedAt!)
          : null,
      'status': status.name,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': updatedAt != null ? Timestamp.fromDate(updatedAt!) : null,
      'chatId': chatId,
    };
  }

  factory HostingSession.fromMap(Map<String, dynamic> map) {
    return HostingSession(
      id: map['id'] ?? '',
      requestId: map['requestId'] ?? '',
      travelerId: map['travelerId'] ?? '',
      travelerName: map['travelerName'] ?? '',
      travelerPhoto: map['travelerPhoto'] as String?,
      hostId: map['hostId'] ?? '',
      hostName: map['hostName'] ?? '',
      hostPhoto: map['hostPhoto'] as String?,
      communityId: map['communityId'] ?? '',
      communityName: map['communityName'] ?? '',
      checkInTime: _parseOptionalTimestamp(map['checkInTime']),
      checkOutTime: _parseOptionalTimestamp(map['checkOutTime']),
      plannedArrival: _parseTimestamp(map['plannedArrival']),
      plannedDeparture: _parseTimestamp(map['plannedDeparture']),
      actualDays: map['actualDays'] as int?,
      totalDspCharged: map['totalDspCharged'] as int?,
      travelerSettled: map['travelerSettled'] as bool? ?? false,
      hostSettled: map['hostSettled'] as bool? ?? false,
      endRequestedBy: map['endRequestedBy'] as String?,
      endRequestedAt: _parseOptionalTimestamp(map['endRequestedAt']),
      status: _parseStatus(map['status'] as String?),
      createdAt: _parseTimestamp(map['createdAt']),
      updatedAt: _parseOptionalTimestamp(map['updatedAt']),
      chatId: map['chatId'] as String?,
    );
  }

  HostingSession copyWith({
    String? id,
    String? requestId,
    String? travelerId,
    String? travelerName,
    String? travelerPhoto,
    String? hostId,
    String? hostName,
    String? hostPhoto,
    String? communityId,
    String? communityName,
    DateTime? checkInTime,
    DateTime? checkOutTime,
    DateTime? plannedArrival,
    DateTime? plannedDeparture,
    int? actualDays,
    int? totalDspCharged,
    bool? travelerSettled,
    bool? hostSettled,
    String? endRequestedBy,
    DateTime? endRequestedAt,
    HostingSessionStatus? status,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? chatId,
  }) {
    return HostingSession(
      id: id ?? this.id,
      requestId: requestId ?? this.requestId,
      travelerId: travelerId ?? this.travelerId,
      travelerName: travelerName ?? this.travelerName,
      travelerPhoto: travelerPhoto ?? this.travelerPhoto,
      hostId: hostId ?? this.hostId,
      hostName: hostName ?? this.hostName,
      hostPhoto: hostPhoto ?? this.hostPhoto,
      communityId: communityId ?? this.communityId,
      communityName: communityName ?? this.communityName,
      checkInTime: checkInTime ?? this.checkInTime,
      checkOutTime: checkOutTime ?? this.checkOutTime,
      plannedArrival: plannedArrival ?? this.plannedArrival,
      plannedDeparture: plannedDeparture ?? this.plannedDeparture,
      actualDays: actualDays ?? this.actualDays,
      totalDspCharged: totalDspCharged ?? this.totalDspCharged,
      travelerSettled: travelerSettled ?? this.travelerSettled,
      hostSettled: hostSettled ?? this.hostSettled,
      endRequestedBy: endRequestedBy ?? this.endRequestedBy,
      endRequestedAt: endRequestedAt ?? this.endRequestedAt,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      chatId: chatId ?? this.chatId,
    );
  }

  // --- Helpers ---

  static DateTime _parseTimestamp(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is String) return DateTime.parse(value);
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    return DateTime.now();
  }

  static DateTime? _parseOptionalTimestamp(dynamic value) {
    if (value == null) return null;
    return _parseTimestamp(value);
  }

  static HostingSessionStatus _parseStatus(String? value) {
    if (value == null) return HostingSessionStatus.confirmed;
    return HostingSessionStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () => HostingSessionStatus.confirmed,
    );
  }
}
