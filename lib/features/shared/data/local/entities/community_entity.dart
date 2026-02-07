import 'package:isar/isar.dart';

part 'community_entity.g.dart';

@collection
class CommunityEntity {
  Id id = Isar.autoIncrement;

  @Index(unique: true, replace: true)
  late String firestoreId;

  late String name;

  @Index()
  String? homeCountryCode;

  String? hostCountryCode;

  @Index()
  String? locationType; // 'home' | 'host' | 'global'

  List<String>? images;
  String? profileImage;
  String? type;

  int memberCount = 0;
  int? totalMembers;
  bool isPrivate = false;

  // Storing complex location map as JSON string or embedded object?
  // For simplicity within Isar, explicit fields are better for querying,
  // but JSON string is safer for "blobs".
  // Given we query by country/city, let's store key fields and full blob.
  String? locationJson;
  String? city;
  String? state;
  String? country;

  String? chatId;
  String? flag;

  List<String>? members;
  List<String>? admins;

  @Index()
  int? createdAt;
  int? updatedAt;
}
