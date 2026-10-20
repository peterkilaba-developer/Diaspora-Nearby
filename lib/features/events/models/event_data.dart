import 'package:json_annotation/json_annotation.dart';
part 'event_data.g.dart';

@JsonSerializable(explicitToJson: true)
class Event {
  String id;
  String title;
  String description;
  String startDate;

  // ISO String YYYY-MM-DD
  String startTime;

  // HH:MM
  String? endDate;
  String? endTime;
  String location;
  String category;
  String? imageUrl;
  String creatorId;

  // List of user IDs who are attending (RSVP)
  List<String>? attendees;
  int? attendeeCount;

  // List of user IDs who actually showed up (Verified via QR)
  List<String>? confirmedAttendees;

  // List of user IDs who are interested
  List<String>? interested;

  // Private Event Invitations
  List<String>? invitedUserIds;
  bool? isPaid;
  double? ticketPrice;

  // Linked Chat ID (RTDB)
  String? chatId;

  // Filtering fields
  String? homeCountry;
  String? hostCountry;
  String? hostCity;
  String? hostState;
  String? homeCountryCode;
  String? hostCountryCode;
  String? attendingPermission;

  // 'all', 'home_country', 'host_country', 'private'
  int? maxAttendees;
  String? createdAt;

  // Venue Details
  String? venueName;
  String? venueAddress;
  String? venueCity;
  String? venueState;
  String? venueCountry;
  String? plusCode;

  // Status: 'published', 'hidden'
  String status;

  // Geolocation (Write-time optimized)
  final double? latitude;
  final double? longitude;

  // Enriched Data (Not persisted in Firestore)
  @JsonKey(includeFromJson: false, includeToJson: false)
  double? distance;

  @JsonKey(includeFromJson: false, includeToJson: false)
  String? creatorName;

  @JsonKey(includeFromJson: false, includeToJson: false)
  String? creatorPhoto;

  String? organizationId;
  String? organizationName;
  int? dspFee; // [DEPRECATED] No longer used — DSP fees removed

  Event({
    required this.id,
    required this.title,
    required this.description,
    required this.startDate,
    required this.startTime,
    this.endDate,
    this.endTime,
    required this.location,
    required this.category,
    this.imageUrl,
    required this.creatorId,
    this.attendees,
    this.attendeeCount,
    this.confirmedAttendees,
    this.interested,
    this.invitedUserIds,
    this.isPaid,
    this.ticketPrice,
    this.chatId,
    this.homeCountry,
    this.hostCountry,
    this.hostCity,
    this.hostState,
    this.homeCountryCode,
    this.hostCountryCode,
    this.attendingPermission,
    this.maxAttendees,
    this.createdAt,
    this.venueName,
    this.venueAddress,
    this.venueCity,
    this.venueState,
    this.venueCountry,
    this.plusCode,
    this.status = 'published',
    this.latitude,
    this.longitude,
    this.distance,
    this.creatorName,
    this.creatorPhoto,
    this.organizationId,
    this.organizationName,
    this.dspFee,
  });

  factory Event.fromJson(Map<String, dynamic> json) {
    final normalized = Map<String, dynamic>.from(json);

    String? toIsoString(dynamic value) {
      if (value == null) return null;
      if (value is String) return value;
      if (value is DateTime) return value.toIso8601String();
      try {
        final dt = (value as dynamic).toDate() as DateTime;
        return dt.toIso8601String();
      } catch (_) {
        return value.toString();
      }
    }

    String? toDateString(dynamic value) {
      final iso = toIsoString(value);
      if (iso == null) return null;
      if (iso.length >= 10 && RegExp(r'^\d{4}-\d{2}-\d{2}').hasMatch(iso)) {
        return iso.substring(0, 10);
      }
      try {
        final dt = DateTime.parse(iso);
        return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
      } catch (_) {
        return iso;
      }
    }

    List<String>? toStringList(dynamic value) {
      if (value is List) {
        return value
            .where((e) => e != null)
            .map((e) => e.toString())
            .toList();
      }
      return null;
    }

    normalized['id'] = (normalized['id'] ?? '').toString();
    normalized['title'] = (normalized['title'] ?? 'Untitled Event').toString();
    normalized['description'] = (normalized['description'] ?? '').toString();
    normalized['startDate'] = toDateString(normalized['startDate']) ?? '';
    normalized['startTime'] = (normalized['startTime'] ?? '00:00').toString();
    normalized['endDate'] = toDateString(normalized['endDate']);
    normalized['endTime'] = normalized['endTime']?.toString();
    normalized['location'] = (normalized['location'] ?? '').toString();
    normalized['category'] = (normalized['category'] ?? 'Other').toString();
    normalized['creatorId'] =
        (normalized['creatorId'] ?? normalized['createdBy'] ?? '').toString();
    normalized['createdAt'] = toIsoString(normalized['createdAt']);
    normalized['status'] = (normalized['status'] ?? 'published').toString();
    normalized['attendees'] = toStringList(normalized['attendees']);
    normalized['confirmedAttendees'] =
        toStringList(normalized['confirmedAttendees']);
    normalized['interested'] = toStringList(normalized['interested']);
    normalized['invitedUserIds'] = toStringList(normalized['invitedUserIds']);

    return _$EventFromJson(normalized);
  }
  Map<String, dynamic> toJson() => _$EventToJson(this);

  Event copyWith({
    String? id,
    String? title,
    String? description,
    String? startDate,
    String? startTime,
    String? endDate,
    String? endTime,
    String? location,
    String? category,
    String? imageUrl,
    String? creatorId,
    List<String>? attendees,
    int? attendeeCount,
    List<String>? confirmedAttendees,
    List<String>? interested,
    List<String>? invitedUserIds,
    bool? isPaid,
    double? ticketPrice,
    String? chatId,
    String? homeCountry,
    String? hostCountry,
    String? hostCity,
    String? hostState,
    String? homeCountryCode,
    String? hostCountryCode,
    String? attendingPermission,
    int? maxAttendees,
    String? createdAt,
    String? venueName,
    String? venueAddress,
    String? venueCity,
    String? venueState,
    String? venueCountry,
    String? plusCode,
    String? status,
    double? latitude,
    double? longitude,
    String? organizationId,
    String? organizationName,
    int? dspFee,
  }) {
    return Event(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      startDate: startDate ?? this.startDate,
      startTime: startTime ?? this.startTime,
      endDate: endDate ?? this.endDate,
      endTime: endTime ?? this.endTime,
      location: location ?? this.location,
      category: category ?? this.category,
      imageUrl: imageUrl ?? this.imageUrl,
      creatorId: creatorId ?? this.creatorId,
      attendees: attendees ?? this.attendees,
      attendeeCount: attendeeCount ?? this.attendeeCount,
      confirmedAttendees: confirmedAttendees ?? this.confirmedAttendees,
      interested: interested ?? this.interested,
      invitedUserIds: invitedUserIds ?? this.invitedUserIds,
      isPaid: isPaid ?? this.isPaid,
      ticketPrice: ticketPrice ?? this.ticketPrice,
      chatId: chatId ?? this.chatId,
      homeCountry: homeCountry ?? this.homeCountry,
      hostCountry: hostCountry ?? this.hostCountry,
      hostCity: hostCity ?? this.hostCity,
      hostState: hostState ?? this.hostState,
      homeCountryCode: homeCountryCode ?? this.homeCountryCode,
      hostCountryCode: hostCountryCode ?? this.hostCountryCode,
      attendingPermission: attendingPermission ?? this.attendingPermission,
      maxAttendees: maxAttendees ?? this.maxAttendees,
      createdAt: createdAt ?? this.createdAt,
      venueName: venueName ?? this.venueName,
      venueAddress: venueAddress ?? this.venueAddress,
      venueCity: venueCity ?? this.venueCity,
      venueState: venueState ?? this.venueState,
      venueCountry: venueCountry ?? this.venueCountry,
      plusCode: plusCode ?? this.plusCode,
      status: status ?? this.status,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      organizationId: organizationId ?? this.organizationId,
      organizationName: organizationName ?? this.organizationName,
      dspFee: dspFee ?? this.dspFee,
    );
  }

  // Shared UI Helpers
  Map<String, dynamic> getStatusBadgeInfo() {
    final now = DateTime.now();
    DateTime? start;
    try {
      start = DateTime.parse('$startDate $startTime');
    } catch (_) {
      try {
        start = DateTime.parse(startDate);
      } catch (_) {}
    }

    if (start == null) return {};

    DateTime? end;
    if (endDate != null && endTime != null) {
      try {
        end = DateTime.parse('$endDate $endTime');
      } catch (_) {
        try {
          end = DateTime.parse(endDate!);
        } catch (_) {}
      }
    }
    // Default end if missing: 3 hours after start
    end ??= start.add(const Duration(hours: 3));

    String? statusText;
    // We return color as String or generic type and let UI resolve Color object?
    // Models cannot easily import flutter/material.dart for Colors class if this is a pure model package.
    // Assuming 'color': 'green' | 'orange' | 'red' for now, or just logic.
    // Actually, this project seems to mix UI usage? No, models usually pure.
    // Check imports... json_annotation.
    // I won't return Color object. I'll return a semantic status string.

    String semanticColor = 'secondary'; // default

    final diffToStart = start.difference(now);
    final diffToEnd = end.difference(now);

    if (now.isAfter(start) && now.isBefore(end)) {
      statusText = 'Happening Now';
      semanticColor = 'green';
      if (diffToEnd.inHours < 4 && diffToEnd.inHours >= 1) {
        statusText = 'Ends in ${diffToEnd.inHours}h';
      } else if (diffToEnd.inHours < 1 && diffToEnd.inMinutes > 0) {
        statusText = 'Ends in ${diffToEnd.inMinutes}m';
      }
    } else if (diffToStart.isNegative == false) {
      // Future Event
      if (diffToStart.inHours < 24) {
        if (diffToStart.inHours >= 1) {
          statusText = 'Starts in ${diffToStart.inHours}h';
        } else {
          statusText = 'Starts in ${diffToStart.inMinutes}m';
        }
      } else if (diffToStart.inHours >= 24 && diffToStart.inHours < 48) {
        final tomorrow = DateTime(now.year, now.month, now.day + 1);
        final eventDate = DateTime(start.year, start.month, start.day);

        if (eventDate.isAtSameMomentAs(tomorrow)) {
          statusText = 'Tomorrow';
        } else {
          statusText = 'In ${(diffToStart.inHours / 24).round()} days';
        }
      } else {
        final days = diffToStart.inDays;
        statusText = 'In $days days';
      }
    }

    return {'text': statusText, 'color': semanticColor};
  }
}
