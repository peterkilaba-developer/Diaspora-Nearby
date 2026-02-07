import 'package:isar/isar.dart';

part 'event_entity.g.dart';

@collection
class EventEntity {
  Id id = Isar.autoIncrement;

  @Index(unique: true, replace: true)
  late String firestoreId;

  late String title;
  late String description;

  @Index()
  late String startDate;
  late String startTime;
  String? endDate;
  String? endTime;

  late String location;
  late String category;
  String? imageUrl;
  late String creatorId;

  List<String>? attendees;
  int? attendeeCount;
  List<String>? interested;
  List<String>? invitedUserIds;

  bool? isPaid;
  double? ticketPrice;

  String? chatId;

  @Index()
  String? homeCountry;
  @Index()
  String? hostCountry;
  String? hostCity;
  String? hostState;

  String? homeCountryCode;
  String? hostCountryCode;

  String? attendingPermission;
  int? maxAttendees;

  @Index()
  String? createdAt;
  String? updatedAt;

  String? venueName;
  String? venueAddress;
  String? venueCity;
  String? venueState;
  String? venueCountry;

  String? status;

  double? latitude;
  double? longitude;

  String? organizationId;
  String? organizationName;
}
