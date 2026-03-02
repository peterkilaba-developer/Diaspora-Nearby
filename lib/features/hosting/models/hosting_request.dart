import 'package:cloud_firestore/cloud_firestore.dart';

/// Status of a hosting request
enum HostingRequestStatus {
  /// Traveler posted the request, waiting for hosts to show interest
  pending,

  /// A host has been selected and both parties agreed
  matched,

  /// The hosting session is currently active (checked in)
  active,

  /// Hosting completed and settled
  completed,

  /// Request was cancelled by the traveler
  cancelled,

  /// Request expired (travel dates passed without a match)
  expired,
}

/// A traveler's request for hosting in a community they're visiting.
///
/// Firestore collection: `hosting_requests`
class HostingRequest {
  final String id;

  // Traveler info
  final String travelerId;
  final String travelerName;
  final String? travelerPhoto;
  final String? travelerFlag; // Home country flag emoji

  // Target community
  final String communityId;
  final String communityName;

  // Travel details
  final DateTime arrivalDate;
  final DateTime departureDate;
  final String? purpose; // e.g., 'Business', 'Vacation', 'Family visit', 'Education'
  final String? notes; // Additional info from traveler
  final int? guestCount; // Number of guests (default 1)

  // Host preferences
  final String? preferredArea; // Preferred neighborhood/area
  final List<String>? languages; // Languages the traveler speaks

  // Matching state
  final List<String> interestedHostIds; // Hosts who showed interest
  final String? matchedHostId; // The host chosen by the traveler
  final String? matchedHostName;

  // Status
  final HostingRequestStatus status;
  final DateTime createdAt;
  final DateTime? updatedAt;

  // Community chat message reference (for the broadcast message)
  final String? chatMessageId;

  const HostingRequest({
    required this.id,
    required this.travelerId,
    required this.travelerName,
    this.travelerPhoto,
    this.travelerFlag,
    required this.communityId,
    required this.communityName,
    required this.arrivalDate,
    required this.departureDate,
    this.purpose,
    this.notes,
    this.guestCount = 1,
    this.preferredArea,
    this.languages,
    this.interestedHostIds = const [],
    this.matchedHostId,
    this.matchedHostName,
    this.status = HostingRequestStatus.pending,
    required this.createdAt,
    this.updatedAt,
    this.chatMessageId,
  });

  /// Number of days for the stay
  int get stayDuration {
    return departureDate.difference(arrivalDate).inDays;
  }

  /// Whether the request is still open for hosts to show interest
  bool get isOpen => status == HostingRequestStatus.pending;

  /// Whether this request has expired (departure date has passed)
  bool get isExpired => DateTime.now().isAfter(departureDate);

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'travelerId': travelerId,
      'travelerName': travelerName,
      'travelerPhoto': travelerPhoto,
      'travelerFlag': travelerFlag,
      'communityId': communityId,
      'communityName': communityName,
      'arrivalDate': Timestamp.fromDate(arrivalDate),
      'departureDate': Timestamp.fromDate(departureDate),
      'purpose': purpose,
      'notes': notes,
      'guestCount': guestCount ?? 1,
      'preferredArea': preferredArea,
      'languages': languages,
      'interestedHostIds': interestedHostIds,
      'matchedHostId': matchedHostId,
      'matchedHostName': matchedHostName,
      'status': status.name,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt':
          updatedAt != null ? Timestamp.fromDate(updatedAt!) : null,
      'chatMessageId': chatMessageId,
    };
  }

  factory HostingRequest.fromMap(Map<String, dynamic> map) {
    return HostingRequest(
      id: map['id'] ?? '',
      travelerId: map['travelerId'] ?? '',
      travelerName: map['travelerName'] ?? '',
      travelerPhoto: map['travelerPhoto'] as String?,
      travelerFlag: map['travelerFlag'] as String?,
      communityId: map['communityId'] ?? '',
      communityName: map['communityName'] ?? '',
      arrivalDate: _parseTimestamp(map['arrivalDate']),
      departureDate: _parseTimestamp(map['departureDate']),
      purpose: map['purpose'] as String?,
      notes: map['notes'] as String?,
      guestCount: map['guestCount'] as int? ?? 1,
      preferredArea: map['preferredArea'] as String?,
      languages: (map['languages'] as List<dynamic>?)
          ?.map((e) => e.toString())
          .toList(),
      interestedHostIds: (map['interestedHostIds'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      matchedHostId: map['matchedHostId'] as String?,
      matchedHostName: map['matchedHostName'] as String?,
      status: _parseStatus(map['status'] as String?),
      createdAt: _parseTimestamp(map['createdAt']),
      updatedAt: map['updatedAt'] != null
          ? _parseTimestamp(map['updatedAt'])
          : null,
      chatMessageId: map['chatMessageId'] as String?,
    );
  }

  HostingRequest copyWith({
    String? id,
    String? travelerId,
    String? travelerName,
    String? travelerPhoto,
    String? travelerFlag,
    String? communityId,
    String? communityName,
    DateTime? arrivalDate,
    DateTime? departureDate,
    String? purpose,
    String? notes,
    int? guestCount,
    String? preferredArea,
    List<String>? languages,
    List<String>? interestedHostIds,
    String? matchedHostId,
    String? matchedHostName,
    HostingRequestStatus? status,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? chatMessageId,
  }) {
    return HostingRequest(
      id: id ?? this.id,
      travelerId: travelerId ?? this.travelerId,
      travelerName: travelerName ?? this.travelerName,
      travelerPhoto: travelerPhoto ?? this.travelerPhoto,
      travelerFlag: travelerFlag ?? this.travelerFlag,
      communityId: communityId ?? this.communityId,
      communityName: communityName ?? this.communityName,
      arrivalDate: arrivalDate ?? this.arrivalDate,
      departureDate: departureDate ?? this.departureDate,
      purpose: purpose ?? this.purpose,
      notes: notes ?? this.notes,
      guestCount: guestCount ?? this.guestCount,
      preferredArea: preferredArea ?? this.preferredArea,
      languages: languages ?? this.languages,
      interestedHostIds: interestedHostIds ?? this.interestedHostIds,
      matchedHostId: matchedHostId ?? this.matchedHostId,
      matchedHostName: matchedHostName ?? this.matchedHostName,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      chatMessageId: chatMessageId ?? this.chatMessageId,
    );
  }

  // --- Helpers ---

  static DateTime _parseTimestamp(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is String) return DateTime.parse(value);
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    return DateTime.now();
  }

  static HostingRequestStatus _parseStatus(String? value) {
    if (value == null) return HostingRequestStatus.pending;
    return HostingRequestStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () => HostingRequestStatus.pending,
    );
  }
}
