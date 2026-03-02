import 'package:diaspora_nearby/features/profile/models/profile_data.dart';
import 'package:diaspora_nearby/features/community/models/community_data.dart';
import 'package:diaspora_nearby/features/dsp/models/points_transaction.dart';
import 'package:diaspora_nearby/features/trust/models/trust_data.dart';
import 'package:diaspora_nearby/features/chat/models/chat.dart';
import 'package:diaspora_nearby/features/chat/models/message.dart';
import 'package:diaspora_nearby/features/shared/models/location.dart';

/// Test data generators for consistent test fixtures
class TestData {
  // User IDs
  static const String userId1 = 'user_test_1';
  static const String userId2 = 'user_test_2';
  static const String userId3 = 'user_test_3';

  // Community IDs
  static const String communityId1 = 'community_test_1';
  static const String communityId2 = 'community_test_2';

  static const UserLocation mockLocation = UserLocation(
    formattedAddress: '123 Test St, Test City, TS',
    placeId: 'test_place_id',
    city: 'Test City',
    country: 'Test Country',
    countryCode: 'TS',
  );

  /// Generate a test ProfileData
  static ProfileData createProfile({
    String? userId,
    String? firstName,
    String? lastName,
  }) {
    return ProfileData(
      uid: userId ?? userId1,
      firstName: firstName ?? 'Test',
      lastName: lastName ?? 'User',
      phone: '+1234567890',
      profileImage: 'https://example.com/photo.jpg',
      homeLocation: mockLocation,
      hostLocation: mockLocation,
      bio: 'Test bio',
      interests: ['tech'],
      createdAt: DateTime(2024, 1, 1),
    );
  }

  /// Generate a test CommunityData
  static CommunityData createCommunity({
    String? id,
    String? name,
  }) {
    return CommunityData(
      id: id ?? communityId1,
      name: name ?? 'Test Community',
      profileImage: 'https://example.com/community.jpg',
    );
  }

  /// Generate a test PointsTransaction
  static PointsTransaction createTransaction({
    String? userId,
    String action = 'message_sent',
    int points = 10,
  }) {
    return PointsTransaction(
      id: 'trans_test_1',
      userId: userId ?? userId1,
      type: 'earn',
      action: action,
      points: points,
      timestamp: DateTime.now(),
    );
  }

  /// Generate a test TrustData
  static TrustData createTrustData({
    String? userId,
  }) {
    return TrustData(
      uid: userId ?? userId1,
      trustScore: 50.0,
      level: TrustLevel.mediumTrust,
      lastUpdated: DateTime(2024, 1, 1),
    );
  }

  /// Generate a test Chat
  static Chat createChat({
    String? id,
    List<String>? participants,
  }) {
    return Chat(
      id: id ?? 'chat_test_1',
      type: 'direct',
      name: 'Test Chat',
      participants: participants ?? [userId1, userId2],
      createdAt: DateTime(2024, 1, 1).millisecondsSinceEpoch,
      updatedAt: DateTime(2024, 1, 1).millisecondsSinceEpoch,
    );
  }

  /// Generate a test Message
  static Message createMessage({
    String? chatId,
    String? senderId,
    String content = 'Test message',
  }) {
    return Message(
      id: 'message_test_1',
      chatId: chatId ?? 'chat_test_1',
      senderId: senderId ?? userId1,
      senderName: 'Test Sender',
      content: content,
      type: 'text',
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );
  }
}
