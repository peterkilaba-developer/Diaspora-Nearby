import 'package:flutter_test/flutter_test.dart';
import 'package:diaspora_nearby/models/message.dart';

void main() {
  group('Message Model Tests', () {
    test('Should parse basic text message from RTDB format', () {
      final data = {
        'senderId': 'user_1',
        'senderName': 'John Doe',
        'content': 'Hello World',
        'type': 'text',
        'timestamp': 1678888888000,
        'status': 'sent'
      };

      final message = Message.fromRTDB('msg_1', 'chat_1', data);

      expect(message.id, 'msg_1');
      expect(message.chatId, 'chat_1');
      expect(message.senderId, 'user_1');
      expect(message.content, 'Hello World');
      expect(message.type, 'text');
      expect(message.timestamp, 1678888888000);
    });

    test('Should parse message with emoji content correctly', () {
      final data = {
        'senderId': 'user_1',
        'senderName': 'John Doe',
        'content': 'Hello 😀',
        'type': 'text',
        'timestamp': 1678888888000,
      };

      final message = Message.fromRTDB('msg_2', 'chat_1', data);
      expect(message.content, 'Hello 😀');
    });

    test('Should handle null/missing fields gracefully', () {
      final data = {
        // Missing senderId (should default empty)
        // Missing senderName (should default Unknown)
        // Missing content (should default empty)
        'timestamp': '123456', // String timestamp should be parsed
      };

      final message = Message.fromRTDB('msg_3', 'chat_1', data);

      expect(message.senderId, '');
      expect(message.senderName, 'Unknown');
      expect(message.content, '');
      expect(message.timestamp, 123456);
      expect(message.type, 'text'); // Default
    });

    test('Should parse location message', () {
      final data = {
        'senderId': 'user_1',
        'senderName': 'John',
        'content': 'My Location',
        'type': 'location',
        'timestamp': 123,
        'location': {
          'lat': 37.7749,
          'lng': -122.4194,
          'address': 'San Francisco'
        }
      };

      final message = Message.fromRTDB('msg_loc', 'chat_1', data);
      
      expect(message.type, 'location');
      expect(message.location, isNotNull);
      expect(message.location!.lat, 37.7749);
      expect(message.location!.lng, -122.4194);
      expect(message.location!.address, 'San Francisco');
    });

    test('Should serialize to JSON correctly', () {
      final message = Message(
        id: 'msg_json',
        chatId: 'chat_json',
        senderId: 'user_x',
        senderName: 'User X',
        content: 'Test JSON',
        type: 'text',
        timestamp: 1000,
        status: 'read',
      );

      final json = message.toJson();
      
      expect(json['id'], 'msg_json');
      expect(json['content'], 'Test JSON');
      expect(json['status'], 'read');
    });
  });
}
