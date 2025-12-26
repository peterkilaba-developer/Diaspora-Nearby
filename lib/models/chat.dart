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
}

/// Last message preview for chat list
@JsonSerializable()
class LastMessage {
  final String content;
  final int timestamp;
  final String senderId;
  final String senderName;
  final String type; // 'text' | 'image' | 'video' | 'audio' | 'location' | 'document' | 'system' | 'money-transfer'
  final bool? forwarded;
  final String? status; // 'sent' | 'delivered' | 'read'

  const LastMessage({
    required this.content,
    required this.timestamp,
    required this.senderId,
    required this.senderName,
    required this.type,
    this.forwarded,
    this.status,
  });

  factory LastMessage.fromJson(Map<String, dynamic> json) =>
      _$LastMessageFromJson(json);
  Map<String, dynamic> toJson() => _$LastMessageToJson(this);

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
      content: data['content'] as String? ?? '',
      timestamp: parseInt(data['timestamp']),
      senderId: data['senderId'] as String? ?? '',
      senderName: data['senderName'] as String? ?? 'Unknown',
      type: data['type'] as String? ?? 'text',
      forwarded: data['forwarded'] as bool?,
      status: data['status'] as String?,
    );
  }
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
    this.isPinned = false,
    this.isPinnedBottom = false,
    this.isMuted = false,
    this.unreadCount = 0,
  });

  factory Chat.fromJson(Map<String, dynamic> json) => _$ChatFromJson(json);
  Map<String, dynamic> toJson() => _$ChatToJson(this);

  /// Check if this is a direct chat
  bool get isDirect => type == 'direct';
  
  /// Check if this is a community chat
  bool get isCommunity => type == 'community';
  
  /// Check if this is a group chat
  bool get isGroup => type == 'group';
  
  /// Check if this is an event chat
  bool get isEvent => type == 'event' || eventId != null;

  /// Check if this is an organization chat
  bool get isOrganization => type == 'organization';

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
      if (value is Map) return value.keys.map((e) => e.toString()).toList();
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
      photoUrl: data['photoUrl'] as String?,
      profileImage: (data['profileImage'] is Map)
          ? ChatProfileImage.fromJson(Map<String, dynamic>.from(data['profileImage']))
          : null,
      participants: parseParticipants(data['participants']),
      admins: data['admins'] is List ? List<String>.from(data['admins']) : null,
      createdBy: data['createdBy'] as String?,
      lastMessage: (data['lastMessage'] is Map)
          ? LastMessage.fromRTDB(Map<String, dynamic>.from(data['lastMessage']))
          : null,
      createdAt: parseInt(data['createdAt']),
      updatedAt: parseInt(data['updatedAt']),
      eventId: data['eventId'] as String?,
      memberCount: parseInt(data['memberCount'], 0),
      flag: data['flag'] as String?,
    );
  }
}
