import 'package:diaspora_nearby/features/profile/models/profile_data.dart';
import 'package:diaspora_nearby/features/community/models/community_data.dart';
import 'package:diaspora_nearby/features/dsp/models/point_record.dart';
import 'package:diaspora_nearby/features/trust/models/trust_data.dart';
import 'package:diaspora_nearby/features/chat/models/chat.dart';
import 'package:diaspora_nearby/features/chat/models/message.dart';

/// Test data generators for consistent test fixtures
class TestData {
  // User IDs
  static const String userId1 = 'user_test_1';
  static const String userId2 = 'user_test_2';
  static const String userId3 = 'user_test_3';

  // Community IDs
  static const String communityId1 = 'community_test_1';
  static const String communityId2 = 'community_test_2';

  /// Generate a test ProfileData
  static ProfileData createProfile({
    String? userId,
    String? displayName,
    bool isVerified = false,
  }) {
    return ProfileData(
      userId: userId ?? userId1,
      displayName: displayName ?? 'Test User',
      bio: 'Test bio',
      photoUrl: 'https://example.com/photo.jpg',
      interests: ['tech', 'music', 'sports'],
      isVerified: isVerified,
      createdAt: DateTime(2024, 1, 1),
    );
  }

  /// Generate a test CommunityData
  static CommunityData createCommunity({
    String? id,
    String? name,
    CommunityType type = CommunityType.city,
    String? parentId,
  }) {
    return CommunityData(
      id: id ?? communityId1,
      name: name ?? 'Test Community',
      type: type,
      parentId: parentId,
      childIds: [],
      memberCount: 10,
      createdAt: DateTime(2024, 1, 1),
    );
  }

  /// Generate a test PointRecord
  static PointRecord createPointRecord({
    String? userId,
    String activityType = 'message_sent',
    int points = 1,
  }) {
    return PointRecord(
      id: 'point_test_1',
      userId: userId ?? userId1,
      activityType: activityType,
      points: points,
      timestamp: DateTime.now(),
    );
  }

  /// Generate a test TrustData
  static TrustData createTrustData({
    String? userId1,
    String? userId2,
    TrustLevel level = TrustLevel.known,
  }) {
    return TrustData(
      id: 'trust_test_1',
      userId1: userId1 ?? TestData.userId1,
      userId2: userId2 ?? TestData.userId2,
      level: level,
      createdAt: DateTime(2024, 1, 1),
    );
  }

  /// Generate a test Chat
  static Chat createChat({
    String? id,
    List<String>? participants,
  }) {
    return Chat(
      id: id ?? 'chat_test_1',
      participants: participants ?? [userId1, userId2],
      unreadCounts: {userId1: 0, userId2: 0},
      createdAt: DateTime(2024, 1, 1),
    );
  }

  /// Generate a test Message
  static Message createMessage({
    String? chatId,
    String? senderId,
    String content = 'Test message',
    MessageType type = MessageType.text,
  }) {
    return Message(
      id: 'message_test_1',
      chatId: chatId ?? 'chat_test_1',
      senderId: senderId ?? userId1,
      content: content,
      type: type,
      timestamp: DateTime.now(),
      isRead: false,
    );
  }
}
