import 'dart:convert';
import 'package:diaspora_nearby/models/message.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:diaspora_nearby/services/local_cache_service.dart';

// Helper to simulate the mojibake issue (corruption) if we were NOT using Base64
// But here we want to test that our solution WORKS.

void main() {
  group('LocalCacheService Tests', () {
    test('Should initialize correctly', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      LocalCacheService.init(prefs);
      expect(() => LocalCacheService.prefs, returnsNormally);
    });

    // CRITICAL: Emoji Encoding Test
    test('Should cache and retrieve messages with emojis correctly using Base64', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      LocalCacheService.init(prefs);

      final chatId = 'chat_123';
      final emojiContent = 'Hello Word! 😀 👍 🎉 ❤️';
      
      final messageData = {
        'id': 'msg_1',
        'chatId': chatId,
        'senderId': 'user_1',
        'content': emojiContent,
        'type': 'text',
        'timestamp': 1234567890,
      };

      // 1. Cache the message
      await LocalCacheService.cacheMessages(chatId, [messageData]);

      // 2. Verify it is stored as Base64 in SharedPreferences
      final storedString = prefs.getString('cached_msgs_$chatId');
      expect(storedString, isNotNull);
      
      // Attempt to decode as Base64 to verify format
      final decodedBytes = base64.decode(storedString!);
      final decodedString = utf8.decode(decodedBytes);
      final decodedJson = jsonDecode(decodedString) as List;
      
      expect(decodedJson.length, 1);
      expect(decodedJson[0]['content'], emojiContent);

      // 3. Retrieve using service method
      final cachedMessages = LocalCacheService.getCachedMessages(chatId);
      expect(cachedMessages.length, 1);
      expect(cachedMessages[0]['content'], emojiContent);
    });

    // Backward Compatibility Test
    test('Should handle old non-Base64 cached data gracefully', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      LocalCacheService.init(prefs);

      final chatId = 'old_chat_456';
      final plainJsonContent = '[{"id":"msg_old","content":"Old Message"}]';
      
      // Manually set old format (Plain JSON string)
      await prefs.setString('cached_msgs_$chatId', plainJsonContent);

      // Verify service can read it via fallback
      final cachedMessages = LocalCacheService.getCachedMessages(chatId);
      expect(cachedMessages.length, 1);
      expect(cachedMessages[0]['content'], 'Old Message');
    });

    test('Should cache an retrieve Organization data with Base64', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      LocalCacheService.init(prefs);

      final orgId = 'org_789';
      final orgData = {'name': 'Test Org 🏢', 'id': orgId}; // Emoji in name
      
      await LocalCacheService.cacheOrganization(orgId, orgData);
      
      // Check storage format
      final stored = prefs.getString('cached_org_$orgId');
      expect(stored, isNotNull);
      // It should NOT look like JSON start
      expect(stored!.startsWith('{'), isFalse); 
      
      final retrieved = LocalCacheService.getCachedOrganization(orgId);
      expect(retrieved, isNotNull);
      expect(retrieved!['name'], 'Test Org 🏢');
    });
  });
}
