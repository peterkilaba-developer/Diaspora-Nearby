import 'package:cloud_firestore/cloud_firestore.dart' hide Transaction;
import 'package:json_annotation/json_annotation.dart';

part 'chat.g.dart';

/// Profile image for community chats
@JsonSerializable()
class ChatProfileImage {
  final String type; // 'flag' | 'icon' | 'gradient-icon'
  final String value;
  final String? backgroundColor;
  final String? gradientFrom;
  final String? gradientTo;

  const ChatProfileImage({
    required this.type,
    required this.value,
    this.backgroundColor,
    this.gradientFrom,
    this.gradientTo,
  });

  factory ChatProfileImage.fromJson(Map<String, dynamic> json) =>
      _$ChatProfileImageFromJson(json);
  Map<String, dynamic> toJson() => _$ChatProfileImageToJson(this);

  /// Create from Firestore document data
  factory ChatProfileImage.fromFirestore(Map<String, dynamic> data) {
    return ChatProfileImage(
      type: data['type'] as String? ?? 'icon',
      value: data['value'] as String? ?? '',
      backgroundColor: data['backgroundColor'] as String?,
      gradientFrom: data['gradientFrom'] as String?,
      gradientTo: data['gradientTo'] as String?,
    );
  }

  /// Convert to Firestore-compatible map
  Map<String, dynamic> toFirestore() => {
    'type': type,
    'value': value,
    if (backgroundColor != null) 'backgroundColor': backgroundColor,
    if (gradientFrom != null) 'gradientFrom': gradientFrom,
    if (gradientTo != null) 'gradientTo': gradientTo,
  };
}

/// Last message preview for chat list
@JsonSerializable()
class LastMessage {
  final String id; // [NEW] Added ID
  final String content;
  final int timestamp;
  final String senderId;
  final String senderName;
  final String
  type; // 'text' | 'image' | 'video' | 'audio' | 'location' | 'document' | 'system' | 'money-transfer'
  final List<String>? mentions;
  final bool? forwarded;
  final String? status; // 'sent' | 'delivered' | 'read'
  final bool? deletedForEveryone;
  final Map<String, dynamic>? metadata; // [NEW]

  const LastMessage({
    this.id = '',
    required this.content,
    required this.timestamp,
    required this.senderId,
    required this.senderName,
    required this.type,
    this.mentions,
    this.forwarded,
    this.status,
    this.deletedForEveryone,
    this.metadata,
  });

  factory LastMessage.fromJson(Map<String, dynamic> json) =>
      _$LastMessageFromJson(json);
  Map<String, dynamic> toJson() => _$LastMessageToJson(this);

  /// Create from Firestore document data
  factory LastMessage.fromFirestore(Map<String, dynamic> data) {
    return LastMessage(
      id: data['id'] as String? ?? '',
      content: data['content'] as String? ?? '',
      timestamp: (data['timestamp'] is Timestamp)
          ? (data['timestamp'] as Timestamp).millisecondsSinceEpoch
          : (data['timestamp'] as int? ?? 0),
      senderId: data['senderId'] as String? ?? '',
      senderName: data['senderName'] as String? ?? 'Unknown',
      type: data['type'] as String? ?? 'text',
      mentions: (data['mentions'] as List<dynamic>?)?.cast<String>(),
      forwarded: data['forwarded'] as bool?,
      status: data['status'] as String?,
      deletedForEveryone: data['deletedForEveryone'] as bool?,
      metadata: (data['metadata'] is Map)
          ? Map<String, dynamic>.from(data['metadata'] as Map)
          : null,
    );
  }

  /// Convert to Firestore-compatible map
  Map<String, dynamic> toFirestore() => {
    'id': id,
    'content': content,
    'timestamp': timestamp,
    'senderId': senderId,
    'senderName': senderName,
    'type': type,
    if (mentions != null) 'mentions': mentions,
    if (forwarded != null) 'forwarded': forwarded,
    if (status != null) 'status': status,
    if (deletedForEveryone != null) 'deletedForEveryone': deletedForEveryone,
    if (metadata != null) 'metadata': metadata,
  };

  /// Create from RTDB with null-safe parsing
  factory LastMessage.fromRTDB(Map<String, dynamic> data) {
    // Helper to safely parse int values
    int parseInt(dynamic value, [int defaultValue = 0]) {
      if (value == null) return defaultValue;
      if (value is int) return value;
      if (value is num) return value.toInt();
      if (value is String) return int.tryParse(value) ?? defaultValue;
      return defaultValue;
    }

    return LastMessage(
      id: data['id'] as String? ?? '', // [NEW] Parse ID
      content: data['content'] as String? ?? '',
      timestamp: parseInt(data['timestamp']),
      senderId: data['senderId'] as String? ?? '',
      senderName: data['senderName'] as String? ?? 'Unknown',
      type: data['type'] as String? ?? 'text',
      mentions: (data['mentions'] is List)
          ? (data['mentions'] as List).map((e) => e.toString()).toList()
          : (data['mentions'] is Map)
          ? (data['mentions'] as Map).keys.map((e) => e.toString()).toList()
          : null,
      forwarded: data['forwarded'] as bool?,
      status: data['status'] as String?,
      deletedForEveryone: data['deletedForEveryone'] as bool?,
      metadata: (data['metadata'] is Map)
          ? Map<String, dynamic>.from(data['metadata'] as Map)
          : null,
    );
  }

  bool isOwnMessage(String userId) => senderId == userId;

  bool get isDeleted => deletedForEveryone == true || type == 'deleted';
}

/// Chat conversation model
/// Supports: direct, community, group, event chats
@JsonSerializable(explicitToJson: true)
class Chat {
  final String id;
  final String? communityId;
  final String? homeCountryCode;
  final String? hostCountryCode;
  final String? locationType; // 'home' | 'host' | 'global'
  final String type; // 'community' | 'direct' | 'group' | 'event'
  final String name;
  final String? photoUrl;
  final ChatProfileImage? profileImage;
  final List<String> participants;
  final List<String>? admins;
  final String? createdBy;
  final LastMessage? lastMessage;
  final int createdAt;
  final int updatedAt;
  final String? eventId;
  final int? memberCount; // [NEW] Explicit count for communities
  final String? flag;
  final String? description; // [NEW]
  final Map<String, dynamic>? metadata; // [NEW]

  // Local preferences (not stored in RTDB)
  @JsonKey(includeFromJson: false, includeToJson: false)
  bool isPinned;
  @JsonKey(includeFromJson: false, includeToJson: false)
  bool isPinnedBottom;
  @JsonKey(includeFromJson: false, includeToJson: false)
  bool isMuted;
  @JsonKey(includeFromJson: false, includeToJson: false)
  int unreadCount;

  Chat({
    required this.id,
    this.communityId,
    this.homeCountryCode,
    this.hostCountryCode,
    this.locationType,
    required this.type,
    required this.name,
    this.photoUrl,
    this.profileImage,
    required this.participants,
    this.admins,
    this.createdBy,
    this.lastMessage,
    required this.createdAt,
    required this.updatedAt,
    this.eventId,
    this.memberCount,
    this.flag,
    this.metadata,
    this.description,
    this.isPinned = false,
    this.isPinnedBottom = false,
    this.isMuted = false,
    this.unreadCount = 0,
  });

  factory Chat.fromJson(Map<String, dynamic> json) => _$ChatFromJson(json);
  Map<String, dynamic> toJson() => _$ChatToJson(this);

  /// Create from Firestore document snapshot
  factory Chat.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return Chat.fromFirestoreData(doc.id, data);
  }

  /// Create from Firestore data map (for use with snapshots or manual construction)
  factory Chat.fromFirestoreData(String id, Map<String, dynamic> data) {
    // Parse timestamp safely (Firestore returns Timestamp objects)
    int parseTimestamp(dynamic value, [int defaultValue = 0]) {
      if (value == null) return defaultValue;
      if (value is Timestamp) return value.millisecondsSinceEpoch;
      if (value is int) return value;
      if (value is num) return value.toInt();
      if (value is String) return int.tryParse(value) ?? defaultValue;
      return defaultValue;
    }

    return Chat(
      id: id,
      communityId: data['communityId'] as String?,
      homeCountryCode: data['homeCountryCode'] as String?,
      hostCountryCode: data['hostCountryCode'] as String?,
      locationType: data['locationType'] as String?,
      type: data['type'] as String? ?? 'direct',
      name: data['name'] as String? ?? 'Chat',
      photoUrl: data['photoUrl'] as String?,
      profileImage: (data['profileImage'] is Map)
          ? ChatProfileImage.fromFirestore(
              Map<String, dynamic>.from(data['profileImage'] as Map),
            )
          : null,
      participants: (data['participants'] as List<dynamic>?)?.cast<String>() ?? [],
      admins: (data['admins'] as List<dynamic>?)?.cast<String>(),
      createdBy: data['createdBy'] as String?,
      lastMessage: (data['lastMessage'] is Map)
          ? LastMessage.fromFirestore(
              Map<String, dynamic>.from(data['lastMessage'] as Map),
            )
          : null,
      createdAt: parseTimestamp(data['createdAt']),
      updatedAt: parseTimestamp(data['updatedAt']),
      eventId: data['eventId'] as String?,
      memberCount: data['memberCount'] as int? ?? 0,
      flag: data['flag'] as String?,
      metadata: (data['metadata'] is Map)
          ? Map<String, dynamic>.from(data['metadata'] as Map)
          : null,
      description: data['description'] as String?,
    );
  }

  /// Apply per-user preferences from userChats subcollection
  Chat withUserPreferences(Map<String, dynamic> userChatData) {
    return copyWith(
      isPinned: userChatData['isPinned'] as bool? ?? false,
      isPinnedBottom: userChatData['isPinnedBottom'] as bool? ?? false,
      isMuted: userChatData['isMuted'] as bool? ?? false,
      unreadCount: userChatData['unreadCount'] as int? ?? 0,
    );
  }

  /// Convert to Firestore-compatible map (for the chats collection)
  Map<String, dynamic> toFirestore() => {
    'type': type,
    'name': name,
    if (communityId != null) 'communityId': communityId,
    if (homeCountryCode != null) 'homeCountryCode': homeCountryCode,
    if (hostCountryCode != null) 'hostCountryCode': hostCountryCode,
    if (locationType != null) 'locationType': locationType,
    if (photoUrl != null) 'photoUrl': photoUrl,
    if (profileImage != null) 'profileImage': profileImage!.toFirestore(),
    'participants': participants,
    if (admins != null) 'admins': admins,
    if (createdBy != null) 'createdBy': createdBy,
    if (lastMessage != null) 'lastMessage': lastMessage!.toFirestore(),
    'createdAt': createdAt,
    'updatedAt': updatedAt,
    if (eventId != null) 'eventId': eventId,
    if (memberCount != null) 'memberCount': memberCount,
    if (flag != null) 'flag': flag,
    if (metadata != null) 'metadata': metadata,
    if (description != null) 'description': description,
  };

  /// Convert user preferences to Firestore map (for userChats subcollection)
  Map<String, dynamic> toUserChatFirestore() => {
    'isPinned': isPinned,
    'isPinnedBottom': isPinnedBottom,
    'isMuted': isMuted,
    'unreadCount': unreadCount,
    'joinedAt': FieldValue.serverTimestamp(),
  };

  /// Check if this is a direct chat
  bool get isDirect => type == 'direct' || id.startsWith('direct_');

  /// Check if this is a community chat
  bool get isCommunity =>
      type == 'community' ||
      id.startsWith('chat_') ||
      id.startsWith('home_') ||
      id.startsWith('host_') ||
      id.startsWith('past_') ||
      id == 'global_community';

  /// Check if this is a group chat
  bool get isGroup => type == 'group' || id.startsWith('group_');

  /// Check if this is an event chat
  bool get isEvent => type == 'event' || eventId != null;

  /// Check if this is an organization chat
  bool get isOrganization => type == 'organization' || id.startsWith('org_');

  /// Check if this is a channel
  bool get isChannel => type == 'channel';

  /// Get the other participant ID for direct chats
  String? getOtherParticipantId(String currentUserId) {
    if (!isDirect) return null;
    return participants.firstWhere(
      (id) => id != currentUserId,
      orElse: () => '',
    );
  }

  /// Create from RTDB with null-safe parsing
  factory Chat.fromRTDB(String id, Map<String, dynamic> data) {
    // Helper to safely parse int values
    int parseInt(dynamic value, [int defaultValue = 0]) {
      if (value == null) return defaultValue;
      if (value is int) return value;
      if (value is num) return value.toInt();
      if (value is String) return int.tryParse(value) ?? defaultValue;
      return defaultValue;
    }

    // Parse participants safely
    List<String> parseParticipants(dynamic value) {
      if (value == null) return [];
      if (value is List) return value.map((e) => e.toString()).toList();
      if (value is Map) {
        // Handle both { "uid": true } and { "0": "uid" } formats
        if (value.isEmpty) return [];
        final firstVal = value.values.first;
        if (firstVal is bool || (firstVal is num && firstVal == 1)) {
          // Assume Set format: { uid: true }
          return value.keys.map((e) => e.toString()).toList();
        }
        // Assume List-as-Map format: { "0": "uid" }
        return value.values.map((e) => e.toString()).toList();
      }
      return [];
    }

    return Chat(
      id: id,
      communityId: data['communityId'] as String?,
      homeCountryCode: data['homeCountryCode'] as String?,
      hostCountryCode: data['hostCountryCode'] as String?,
      locationType: data['locationType'] as String?,
      type: data['type'] as String? ?? 'direct',
      name: data['name'] as String? ?? 'Chat',
      photoUrl:
          data['photoUrl'] as String? ??
          (data['profileImage'] is String
              ? data['profileImage'] as String
              : (data['image'] as String?)),
      profileImage: (data['profileImage'] is Map)
          ? ChatProfileImage.fromJson(
              Map<String, dynamic>.from(data['profileImage'] as Map),
            )
          : null,
      participants: parseParticipants(data['participants']),
      admins: data['admins'] is List ? List<String>.from(data['admins']) : null,
      createdBy: data['createdBy'] as String?,
      lastMessage: (data['lastMessage'] is Map)
          ? LastMessage.fromRTDB(
              Map<String, dynamic>.from(data['lastMessage'] as Map),
            )
          : null,
      createdAt: parseInt(data['createdAt']),
      updatedAt: parseInt(data['updatedAt']),
      eventId: data['eventId'] as String?,
      memberCount: parseInt(data['memberCount'], 0),
      flag: data['flag'] as String?,
      metadata: (data['metadata'] is Map)
          ? Map<String, dynamic>.from(data['metadata'] as Map)
          : null,
      description: data['description'] as String?,
      unreadCount: parseInt(data['unreadCount'], 0),
      isPinned: data['pinned'] == true || data['isPinned'] == true,
      isPinnedBottom:
          data['pinnedBottom'] == true || data['isPinnedBottom'] == true,
      isMuted: data['muted'] == true || data['isMuted'] == true,
    );
  }

  Chat copyWith({
    String? id,
    String? communityId,
    String? homeCountryCode,
    String? hostCountryCode,
    String? locationType,
    String? type,
    String? name,
    String? photoUrl,
    ChatProfileImage? profileImage,
    List<String>? participants,
    List<String>? admins,
    String? createdBy,
    LastMessage? lastMessage,
    int? createdAt,
    int? updatedAt,
    String? eventId,
    int? memberCount,
    String? flag,
    Map<String, dynamic>? metadata,
    String? description,
    bool? isPinned,
    bool? isPinnedBottom,
    bool? isMuted,
    int? unreadCount,
  }) {
    return Chat(
      id: id ?? this.id,
      communityId: communityId ?? this.communityId,
      homeCountryCode: homeCountryCode ?? this.homeCountryCode,
      hostCountryCode: hostCountryCode ?? this.hostCountryCode,
      locationType: locationType ?? this.locationType,
      type: type ?? this.type,
      name: name ?? this.name,
      photoUrl: photoUrl ?? this.photoUrl,
      profileImage: profileImage ?? this.profileImage,
      participants: participants ?? this.participants,
      admins: admins ?? this.admins,
      createdBy: createdBy ?? this.createdBy,
      lastMessage: lastMessage ?? this.lastMessage,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      eventId: eventId ?? this.eventId,
      memberCount: memberCount ?? this.memberCount,
      flag: flag ?? this.flag,
      metadata: metadata ?? this.metadata,
      description: description ?? this.description,
      isPinned: isPinned ?? this.isPinned,
      isPinnedBottom: isPinnedBottom ?? this.isPinnedBottom,
      isMuted: isMuted ?? this.isMuted,
      unreadCount: unreadCount ?? this.unreadCount,
    );
  }
}
