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

  // List of user IDs who are attending
  List<String>? attendees;
  int? attendeeCount;

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
  
  // Status: 'draft', 'published'
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
    this.status = 'draft',
    this.latitude,
    this.longitude,
    this.distance,
    this.creatorName,
    this.creatorPhoto,
    this.organizationId,
    this.organizationName,
  });

  factory Event.fromJson(Map<String, dynamic> json) => _$EventFromJson(json);
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
    String? status,
    double? latitude,
    double? longitude,
    String? organizationId,
    String? organizationName,
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
      status: status ?? this.status,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      organizationId: organizationId ?? this.organizationId,
      organizationName: organizationName ?? this.organizationName,
    );
  }
}

