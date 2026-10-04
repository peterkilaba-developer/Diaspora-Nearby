import 'package:diaspora_nearby/features/chat/models/chat.dart';
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
}
