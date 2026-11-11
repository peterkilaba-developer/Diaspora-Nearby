import 'package:diaspora_nearby/features/chat/models/chat.dart';
import 'package:diaspora_nearby/features/chat/models/message.dart';
import 'package:diaspora_nearby/features/chat/repository/chat_repository.dart';
import 'package:diaspora_nearby/features/chat/screens/chats_list_screen.dart';
import 'package:diaspora_nearby/features/chat/widgets/message_content/dsp_transfer_message_content.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Diaspora AI Agent Welcome, Pinning & Location Distribution Card', () {
    test('local AI welcome message includes PoH, 12 profile fields offer, and QR Exchange emphasis', () {
      final text = ChatsListScreen.buildLocalAiAgentWelcomeText();
      expect(text, contains('Proof of Humanity (PoH)'));
      expect(text, contains('12 profile fields'));
      expect(text, contains('10,000 DSP'));
      expect(text, contains(r'$DIASPORA'));
      expect(text, contains('QR Exchange'));
      expect(text, contains('10 in-person QR Exchanges'));

      final actions = ChatsListScreen.buildLocalWelcomeAiActions();
      expect(
        actions.any((a) => a['type'] == 'prompt' && (a['prompt'] as String).contains('12 profile fields')),
        isTrue,
      );
      expect(
        actions.any((a) => a['type'] == 'navigate' && a['route'] == '/profile?showQr=true'),
        isTrue,
      );
    });

    test('AI Agent chat pinned by default sorts to top and drops below newer chats when unpinned', () {
      final aiChatPinned = Chat(
        id: 'ai_agent_user_1',
        type: 'direct',
        name: 'Diaspora AI',
        participants: const ['user_1', 'diaspora_ai_agent'],
        createdAt: 1000,
        updatedAt: 1000,
        isPinned: true,
      );

      final newerPeerChat = Chat(
        id: 'direct_peer_1',
        type: 'direct',
        name: 'Ama',
        participants: const ['user_1', 'user_2'],
        createdAt: 2000,
        updatedAt: 5000,
        isPinned: false,
      );

      final listWhenPinned = <Chat>[newerPeerChat, aiChatPinned]..sort(ChatRepository.compareChatsByLatest);
      expect(listWhenPinned.first.id, 'ai_agent_user_1');

      final aiChatUnpinned = aiChatPinned.withUserPreferences({'pinned': false});
      expect(aiChatUnpinned.isPinned, isFalse);

      final listWhenUnpinned = <Chat>[aiChatUnpinned, newerPeerChat]..sort(ChatRepository.compareChatsByLatest);
      expect(listWhenUnpinned.first.id, 'direct_peer_1');
    });

    testWidgets('DSPTransferMessageContent renders Location Transparency PoH card without raw markdown asterisks', (
      WidgetTester tester,
    ) async {
      final message = Message(
        id: 'msg_loc_1',
        chatId: 'chat_ai_1',
        senderId: 'diaspora_ai_agent',
        senderName: 'Diaspora AI',
        content: '+10,000 \$DIASPORA distributed for Location Transparency!',
        timestamp: DateTime.now().millisecondsSinceEpoch,
        type: 'dsp_transfer',
        status: 'sent',
        metadata: {
          'isAiAgent': true,
          'isConversion': true,
          'conversionKind': 'poh_100',
          'amount': 10000,
          'currency': 'DIASPORA',
          'assetType': 'token',
          'headerLabel': r'Location Transparency • +10,000 $DIASPORA',
          'footerLabel': '100% PoH Conversion Confirmed',
          'explanationText':
              r'Welcome to **Proof of Humanity (PoH)**! Complete your **12 profile fields** for **10,000 DSP** and unlock via **QR EXCHANGE**.',
          'nextTaskTitle': r'Earn Your Next +10,000 $DIASPORA & Unlock via QR Exchange',
          'nextTaskBody':
              r'Reply right here to fill your **12 profile fields** and scan **10 QR Exchanges**.',
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: DSPTransferMessageContent(message: message, isOwn: false),
            ),
          ),
        ),
      );

      expect(find.text(r'Location Transparency • +10,000 $DIASPORA'), findsOneWidget);
      expect(find.text('+10,000'), findsOneWidget);
      expect(
        find.textContaining('Welcome to Proof of Humanity (PoH)!', findRichText: true),
        findsOneWidget,
      );
      expect(
        find.textContaining('QR EXCHANGE', findRichText: true),
        findsOneWidget,
      );
      expect(
        find.textContaining('**Proof of Humanity', findRichText: true),
        findsNothing,
      );
    });
  });
}
