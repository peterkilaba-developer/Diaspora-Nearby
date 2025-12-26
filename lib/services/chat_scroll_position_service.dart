import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:diaspora_nearby/providers/theme_provider.dart';

/// Service for persisting chat scroll positions 
/// Use to restore scroll position when user returns to a chat 
class ChatScrollPositionService {
  final SharedPreferences _prefs;
  static const String _keyPrefix = 'chat_scroll_';
  
  ChatScrollPositionService(this._prefs);

  /// Save scroll offset for a chat   
  Future<void> savePosition(String chatId, double offset) async {
    await _prefs.setDouble('$_keyPrefix$chatId', offset);
  }

  /// Get saved scroll offset for a chat   
  double? getPosition(String chatId) {
    return _prefs.getDouble('$_keyPrefix$chatId');
  }

  /// Clear scroll position for a chat   
  Future<void> clearPosition(String chatId) async {
    await _prefs.remove('$_keyPrefix$chatId');
  }

  /// Clear all saved positions (cleanup)   
  Future<void> clearAllPositions() async {
    final keys = _prefs.getKeys().where((k) => k.startsWith(_keyPrefix));
    for (final key in keys) {
      await _prefs.remove(key);
    }
  }
}

/// Provider for scroll position service 
final chatScrollPositionServiceProvider = Provider<ChatScrollPositionService>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return ChatScrollPositionService(prefs);
});

