import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:diaspora_nearby/core/providers/theme_provider.dart';

final sessionServiceProvider = Provider<SessionService>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return SessionService(prefs);
});

class SessionService {
  final SharedPreferences _prefs;
  static final Set<String> _memoryCachedUsers = <String>{};

  SessionService(this._prefs);

  // Storage keys
  static const String _keyUserId = 'session_user_id';
  static const String _keyLastLogin = 'session_last_login';
  static const String _keyHasCompletedOnboarding =
      'session_completed_onboarding';
  static const String _keyLastScreen = 'session_last_screen';
  static const String _keyProfileComplete = 'session_profile_complete';
  static const String _keyIsReturningUser = 'is_returning_user';

  /// Save complete session on successful login
  Future<void> saveSession({
    required String userId,
    bool hasCompletedOnboarding = false,
    bool profileComplete = false,
    String? lastScreen,
    bool isReturningUser = true,
  }) async {
    if (profileComplete) {
      _memoryCachedUsers.add(userId);
    }
    await Future.wait([
      _prefs.setString(_keyUserId, userId),
      _prefs.setString(_keyLastLogin, DateTime.now().toIso8601String()),
      _prefs.setBool(_keyHasCompletedOnboarding, hasCompletedOnboarding),
      _prefs.setBool(_keyProfileComplete, profileComplete),
      if (lastScreen != null) _prefs.setString(_keyLastScreen, lastScreen),
      _prefs.setBool(_keyIsReturningUser, isReturningUser),
      if (profileComplete) _prefs.setString('cached_user_$userId', '1'),
    ]);
  }

  /// Update returning user status
  Future<void> setReturningUser(bool value) async {
    await _prefs.setBool(_keyIsReturningUser, value);
  }

  /// Update session when profile is completed
  Future<void> updateProfileComplete(bool value) async {
    await _prefs.setBool(_keyProfileComplete, value);
  }

  /// Update onboarding status
  Future<void> updateOnboardingComplete(bool value) async {
    await _prefs.setBool(_keyHasCompletedOnboarding, value);
  }

  /// Update last visited screen
  Future<void> updateLastScreen(String screen) async {
    await _prefs.setString(_keyLastScreen, screen);
  }

  /// Update last login timestamp
  Future<void> updateLastVisit() async {
    await _prefs.setString(_keyLastLogin, DateTime.now().toIso8601String());
  }

  /// Get current session data
  Future<Map<String, dynamic>?> getSession() async {
    final userId = _prefs.getString(_keyUserId);

    if (userId == null) return null;

    return {
      'user_id': userId,
      'last_login': _prefs.getString(_keyLastLogin),
      'has_completed_onboarding':
          _prefs.getBool(_keyHasCompletedOnboarding) ?? false,
      'last_screen': _prefs.getString(_keyLastScreen),
      'profile_complete': _prefs.getBool(_keyProfileComplete) ?? false,
    };
  }

  /// Get user ID from session
  Future<String?> getUserId() async {
    return _prefs.getString(_keyUserId);
  }

  /// Check if user is returning (has logged in before)
  Future<bool> isReturningUser() async {
    return _prefs.getBool(_keyIsReturningUser) ?? false;
  }

  /// Check if profile marked as complete
  Future<bool> isProfileComplete() async {
    return _prefs.getBool(_keyProfileComplete) ?? false;
  }

  /// Get last visited screen
  Future<String?> getLastScreen() async {
    return _prefs.getString(_keyLastScreen);
  }

  /// Clear session on logout
  Future<void> clearSession() async {
    _memoryCachedUsers.clear();
    await Future.wait([
      _prefs.remove(_keyUserId),
      _prefs.remove(_keyLastLogin),
      _prefs.remove(_keyHasCompletedOnboarding),
      _prefs.remove(_keyLastScreen),
      _prefs.remove(_keyProfileComplete),
    ]);
  }

  /// Mark user as cached
  Future<void> setUserCached(String uid) async {
    _memoryCachedUsers.add(uid);
    await _prefs.setString('cached_user_$uid', '1');
  }

  /// Check if user is cached
  bool isUserCached(String uid) {
    return _memoryCachedUsers.contains(uid) ||
        _prefs.containsKey('cached_user_$uid');
  }

  Future<void> clearAll() async {
    _memoryCachedUsers.clear();
    await _prefs.clear();
  }
}
