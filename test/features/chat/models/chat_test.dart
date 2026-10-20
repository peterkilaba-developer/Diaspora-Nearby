import 'package:diaspora_nearby/features/chat/models/chat.dart';
import 'package:diaspora_nearby/features/chat/repository/chat_repository.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Chat classification', () {
    Future<Chat> parseChat(String id, Map<String, dynamic> data) async {
      final firestore = FakeFirebaseFirestore();
      await firestore.collection('chats').doc(id).set({
        'name': 'Test chat',
        'participants': ['user-1', 'user-2'],
        'createdAt': 1,
        'updatedAt': 1,
        ...data,
      });
      return Chat.fromFirestore(
        await firestore.collection('chats').doc(id).get(),
      );
    }

    test('legacy community chat marked direct cannot transfer value', () async {
      final chat = await parseChat('chat_kenya_chicago', {'type': 'direct'});

      expect(chat.isCommunity, isTrue);
      expect(chat.isDirect, isFalse);
      expect(chat.supportsValueTransfer, isFalse);
    });

    test('community metadata overrides a stale direct type', () async {
      final chat = await parseChat('legacy-id', {
        'type': 'direct',
        'communityId': 'kenya_chicago',
      });

      expect(chat.type, 'community');
      expect(chat.supportsValueTransfer, isFalse);
    });

    test('two-person direct chat can transfer value', () async {
      final chat = await parseChat('direct_123', {'type': 'direct'});

      expect(chat.isDirect, isTrue);
      expect(chat.supportsValueTransfer, isTrue);
    });

    test(
      'multi-participant chat cannot transfer even if mislabeled direct',
      () {
        final chat = Chat(
          id: 'direct_123',
          type: 'direct',
          name: 'Legacy chat',
          participants: const ['user-1', 'user-2', 'user-3'],
          createdAt: 1,
          updatedAt: 1,
        );

        expect(chat.supportsValueTransfer, isFalse);
      },
    );
  });

  group('Chat timestamp ordering', () {
    test(
      'withUserPreferences prioritizes lastMessage.timestamp over sync updatedAt',
      () {
        final chat = Chat(
          id: 'chat_home_country_tz',
          type: 'community',
          name: 'Tanzania Community',
          participants: const ['user-1'],
          createdAt: 1000,
          updatedAt: 2000,
          lastMessage: const LastMessage(
            id: 'msg-1',
            content: 'Karibu',
            timestamp: 2000,
            senderId: 'user-2',
            senderName: 'Juma',
            type: 'text',
          ),
        );

        // Simulate a later sync that bumped userChat.updatedAt to 999999
        // without a newer message.
        final hydrated = chat.withUserPreferences({
          'updatedAt': 999999,
          'isPinned': false,
        });

        expect(hydrated.updatedAt, 2000);
      },
    );

    test(
      'compareChatsByLatest orders chats with latest message on top and respects pins',
      () {
        final olderCommunity = Chat(
          id: 'chat_comm_1',
          type: 'community',
          name: 'Older Community',
          participants: const ['u1'],
          createdAt: 1000,
          updatedAt: 999999, // e.g. bumped by metadata/sync
          lastMessage: const LastMessage(
            id: 'm1',
            content: 'Old msg',
            timestamp: 3000,
            senderId: 'u2',
            senderName: 'A',
            type: 'text',
          ),
        );

        final newerDirect = Chat(
          id: 'direct_1',
          type: 'direct',
          name: 'Newer DM',
          participants: const ['u1', 'u2'],
          createdAt: 2000,
          updatedAt: 5000,
          lastMessage: const LastMessage(
            id: 'm2',
            content: 'Latest msg',
            timestamp: 5000,
            senderId: 'u2',
            senderName: 'B',
            type: 'text',
          ),
        );

        final emptyNewGroup = Chat(
          id: 'group_1',
          type: 'group',
          name: 'Empty Group',
          participants: const ['u1'],
          createdAt: 4000,
          updatedAt: 4000,
        );

        final pinnedTop = Chat(
          id: 'chat_pinned_top',
          type: 'direct',
          name: 'Pinned Top',
          participants: const ['u1', 'u3'],
          createdAt: 500,
          updatedAt: 500,
          isPinned: true,
        );

        final pinnedBottom = Chat(
          id: 'chat_pinned_bottom',
          type: 'community',
          name: 'Pinned Bottom',
          participants: const ['u1'],
          createdAt: 8000,
          updatedAt: 8000,
          isPinnedBottom: true,
        );

        final list = [
          olderCommunity,
          pinnedBottom,
          emptyNewGroup,
          newerDirect,
          pinnedTop,
        ]..sort(ChatRepository.compareChatsByLatest);

        expect(list.map((c) => c.id).toList(), [
          'chat_pinned_top',
          'direct_1',
          'chat_comm_1',
          'group_1',
          'chat_pinned_bottom',
        ]);
      },
    );
  });
}
