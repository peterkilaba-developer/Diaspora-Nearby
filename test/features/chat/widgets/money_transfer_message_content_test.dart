import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:diaspora_nearby/features/chat/models/message.dart';
import 'package:diaspora_nearby/features/chat/widgets/message_content/money_transfer_message_content.dart';

void main() {
  testWidgets(
    'MoneyTransferMessageContent renders remittance information properly',
    (WidgetTester tester) async {
      final message = Message(
        id: 'msg_123',
        chatId: 'chat_123',
        senderId: 'user_sender',
        senderName: 'Jane Doe',
        content: 'Sent 100 USD (≈ 270,000 TZS)',
        timestamp: DateTime.now().millisecondsSinceEpoch,
        type: 'money-transfer',
        status: 'sent',
        metadata: {
          'amount': 100.0,
          'currency': 'USD',
          'convertedAmount': 270000.0,
          'convertedCurrency': 'TZS',
          'exchangeRate': 2700.0,
          'fee': 0.0,
          'status': 'Completed',
          'deliveryMethod': 'Mobile Money / Bank Settlement',
          'assetType': 'fiat',
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MoneyTransferMessageContent(message: message, isOwn: true),
          ),
        ),
      );

      // Verify main card texts
      expect(find.text('Sent Remittance'), findsOneWidget);
      expect(find.text('100'), findsOneWidget);
      expect(find.text('USD'), findsWidgets);
      expect(find.text('≈ 270,000 TZS'), findsOneWidget);
      expect(find.text('0% Fee'), findsOneWidget);
      expect(find.text('Details'), findsOneWidget);

      // Tap Details button
      await tester.tap(find.text('Details'));
      await tester.pumpAndSettle();

      // Verify bottom sheet contents
      expect(find.text('Remittance Receipt'), findsOneWidget);
      expect(find.text('Mobile Money / Bank Settlement'), findsOneWidget);
      expect(find.text('Instant Settlement (Completed)'), findsOneWidget);
      expect(find.text('1 USD = 2,700.00 TZS'), findsOneWidget);
      expect(find.text('Free (\$0.00 Covered)'), findsOneWidget);
    },
  );
}
