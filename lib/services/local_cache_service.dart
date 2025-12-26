import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Service for caching user-generated data locally for immediate access
/// before Firestore propagation completes.
class LocalCacheService {
  static SharedPreferences? _prefs;
  
  // Cache key prefixes
  static const String _orgPrefix = 'cached_org_';
  static const String _chatPrefix = 'cached_chat_';
  static const String _eventPrefix = 'cached_event_';

  // List Keys
  static const String _myOrgsKey = 'my_created_orgs';
  static const String _myEventsKey = 'my_created_events';
  static const String _myChatsKey = 'my_chats';
  
  // Cache expiration (24 hours in milliseconds)
  static const int _expirationMs = 24 * 60 * 60 * 1000;

  /// Initialize with SharedPreferences instance
  static void init(SharedPreferences prefs) {
    _prefs = prefs;
    debugPrint('✅ LocalCacheService initialized');
  }

  /// Get prefs instance (throws if not initialized)
  static SharedPreferences get prefs {
    if (_prefs == null) {
      throw Exception('LocalCacheService not initialized. Call init() first.');
    }
    return _prefs!;
  }

  // ==================== ORGANIZATIONS ====================

  /// Cache organization data
  static Future<void> cacheOrganization(String orgId, Map<String, dynamic> data) async {
    try {
      final cacheData = {
        'data': data,
        'cachedAt': DateTime.now().millisecondsSinceEpoch,
      };
      await prefs.setString('$_orgPrefix$orgId', jsonEncode(cacheData));
      debugPrint('✅ Cached organization: $orgId');
    } catch (e) {
      debugPrint('Error caching org: $e');
    }
  }

  /// Get cached organization
  static Map<String, dynamic>? getCachedOrganization(String orgId) {
    try {
      final jsonStr = prefs.getString('$_orgPrefix$orgId');
      if (jsonStr == null) return null;
      
      final cacheData = jsonDecode(jsonStr);
      final cachedAt = cacheData['cachedAt'] as int? ?? 0;
      final now = DateTime.now().millisecondsSinceEpoch;
      
      // Check expiration
      if (now - cachedAt > _expirationMs) {
        prefs.remove('$_orgPrefix$orgId');
        return null;
      }
      
      return Map<String, dynamic>.from(cacheData['data']);
    } catch (e) {
      debugPrint('Error reading cached org: $e');
      return null;
    }
  }

  /// Add org ID to local list
  static Future<void> addToMyOrgsList(String orgId) async {
    try {
      final List<String> current = prefs.getStringList(_myOrgsKey) ?? [];
      if (!current.contains(orgId)) {
        current.add(orgId);
        await prefs.setStringList(_myOrgsKey, current);
      }
    } catch (e) {
      debugPrint('Error adding to org list: $e');
    }
  }

  /// Get all cached organizations from my list
  static List<Map<String, dynamic>> getMyCachedOrganizations() {
    final List<Map<String, dynamic>> results = [];
    try {
       final List<String> ids = prefs.getStringList(_myOrgsKey) ?? [];
       for (final id in ids) {
         final data = getCachedOrganization(id);
         if (data != null) {
           results.add(data);
         }
       }
    } catch (e) {
      debugPrint('Error fetching cached orgs: $e');
    }
    return results;
  }

  // ==================== EVENTS ====================

  static Future<void> cacheEvent(String eventId, Map<String, dynamic> data) async {
    try {
      final cacheData = {
        'data': data,
        'cachedAt': DateTime.now().millisecondsSinceEpoch,
      };
      await prefs.setString('$_eventPrefix$eventId', jsonEncode(cacheData));
      
      // Also add to list
      await addToMyEventsList(eventId);
      
      debugPrint('✅ Cached event: $eventId');
    } catch (e) {
      debugPrint('Error caching event: $e');
    }
  }

  static Map<String, dynamic>? getCachedEvent(String eventId) {
    try {
      final jsonStr = prefs.getString('$_eventPrefix$eventId');
      if (jsonStr == null) return null;
      
      final cacheData = jsonDecode(jsonStr);
      final cachedAt = cacheData['cachedAt'] as int? ?? 0;
      final now = DateTime.now().millisecondsSinceEpoch;
      
      if (now - cachedAt > _expirationMs) {
        prefs.remove('$_eventPrefix$eventId');
        return null;
      }
      return Map<String, dynamic>.from(cacheData['data']);
    } catch (e) {
      return null;
    }
  }

  static Future<void> addToMyEventsList(String eventId) async {
    try {
      final List<String> current = prefs.getStringList(_myEventsKey) ?? [];
      if (!current.contains(eventId)) {
        current.add(eventId);
        await prefs.setStringList(_myEventsKey, current);
      }
    } catch (e) {
      debugPrint('Error adding to event list: $e');
    }
  }

  static List<Map<String, dynamic>> getMyCachedEvents() {
    final List<Map<String, dynamic>> results = [];
    try {
       final List<String> ids = prefs.getStringList(_myEventsKey) ?? [];
       for (final id in ids) {
         final data = getCachedEvent(id);
         if (data != null) {
           results.add(data);
         }
       }
    } catch (e) {
      debugPrint('Error fetching cached events: $e');
    }
    return results;
  }

  // ==================== CHATS ====================

  static Future<void> cacheChat(String chatId, Map<String, dynamic> data) async {
    try {
      final cacheData = {
        'data': data,
        'cachedAt': DateTime.now().millisecondsSinceEpoch,
      };
      await prefs.setString('$_chatPrefix$chatId', jsonEncode(cacheData));
      
      // Add to list
      await addToMyChatsList(chatId);
      
      debugPrint('✅ Cached chat: $chatId');
    } catch (e) {
      debugPrint('Error caching chat: $e');
    }
  }

  static Map<String, dynamic>? getCachedChat(String chatId) {
    try {
      final jsonStr = prefs.getString('$_chatPrefix$chatId');
      if (jsonStr == null) return null;
      
      final cacheData = jsonDecode(jsonStr);
      // Chats update frequently, maybe shorter expiration? 
      // check expiration
      final cachedAt = cacheData['cachedAt'] as int? ?? 0;
      if (DateTime.now().millisecondsSinceEpoch - cachedAt > _expirationMs) {
         return null;
      }
      
      return Map<String, dynamic>.from(cacheData['data']);
    } catch (e) {
      return null;
    }
  }

  static Future<void> addToMyChatsList(String chatId) async {
    try {
      final List<String> current = prefs.getStringList(_myChatsKey) ?? [];
      if (!current.contains(chatId)) {
        current.add(chatId);
        await prefs.setStringList(_myChatsKey, current);
      }
    } catch (e) {
      debugPrint('Error adding to chat list: $e');
    }
  }

  static List<Map<String, dynamic>> getMyCachedChats() {
    final List<Map<String, dynamic>> results = [];
    try {
       final List<String> ids = prefs.getStringList(_myChatsKey) ?? [];
       for (final id in ids) {
         final data = getCachedChat(id);
         if (data != null) {
           results.add(data);
         }
       }
    } catch (e) {
      debugPrint('Error fetching cached chats: $e');
    }
    return results;
  }

  // ==================== MESSAGES ====================

  static const String _messagesPrefix = 'cached_msgs_';

  /// Cache list of messages for a chat
  static Future<void> cacheMessages(String chatId, List<Map<String, dynamic>> messages) async {
    try {
      // Limit to last 100 messages to prevent massive local storage usage
      final msgsToCache = messages.length > 100 
          ? messages.sublist(messages.length - 100) 
          : messages;
          
      final jsonStr = jsonEncode(msgsToCache);
      await prefs.setString('$_messagesPrefix$chatId', jsonStr);
    } catch (e) {
      debugPrint('Error caching messages: $e');
    }
  }

  /// Get cached messages for a chat
  static List<Map<String, dynamic>> getCachedMessages(String chatId) {
    try {
      final jsonStr = prefs.getString('$_messagesPrefix$chatId');
      if (jsonStr == null) return [];

      final List<dynamic> list = jsonDecode(jsonStr);
      return list.cast<Map<String, dynamic>>();
    } catch (e) {
      debugPrint('Error reading cached messages: $e');
      return [];
    }
  }
}
