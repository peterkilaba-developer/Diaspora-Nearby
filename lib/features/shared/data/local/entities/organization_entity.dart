import 'package:isar/isar.dart';

part 'organization_entity.g.dart';

@collection
class OrganizationEntity {
  Id id = Isar.autoIncrement;

  @Index(unique: true, replace: true)
  late String firestoreId;

  String? name; // Maps to 'name' or 'businessName'
  String? businessName; // Kept separate if needed, or normalized to name
  String? profileImage; // Maps to 'profileImage' or 'logoUrl'
  String? logoUrl;

  String? description;
  String? website;
  String? email;
  String? phone;
  String? address;
  
  String? superAdminId;
  List<String>? admins;
  List<String>? pendingAdmins;
  List<String>? followers;

  String? chatId;
  String? status; // 'active', 'pending', etc.

  @Index()
  int? createdAt;
  int? updatedAt;

  // Generic metadata blob for any extra fields
  String? metadataJson;
}
