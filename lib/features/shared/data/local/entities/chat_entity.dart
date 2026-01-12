import 'package:isar/isar.dart';

part 'chat_entity.g.dart';

@collection
class ChatEntity {
  Id id = Isar.autoIncrement;

  @Index(unique: true, replace: true)
  late String firestoreId;

  @Index()
  String? communityId;
  
  String? homeCountryCode;
  String? hostCountryCode;
  String? locationType;
  
  @Index()
  late String type; // 'community' | 'direct' | 'group' | 'event'
  
  late String name;
  String? photoUrl;
  
  // ProfileImage is complex, store as JSON for now
  String? profileImageJson;

  List<String>? participants;
  List<String>? admins;
  String? createdBy;
  
  LastMessageEntity? lastMessage;
  
  @Index()
  late int createdAt;
  
  @Index()
  late int updatedAt;
  
  String? eventId;
  int? memberCount;
  String? flag;

  // Local preferences
  bool isPinned = false;
  bool isPinnedBottom = false;
  bool isMuted = false;
  int unreadCount = 0;
}

@embedded
class LastMessageEntity {
  String? content;
  int? timestamp;
  String? senderId;
  String? senderName;
  String? type;
  List<String>? mentions;
  bool? forwarded;
  String? status;
  bool? deletedForEveryone;
}
