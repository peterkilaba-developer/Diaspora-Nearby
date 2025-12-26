import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final sessionServiceProvider = Provider<SessionService>((ref) => SessionService());

class SessionService {
  // Storage keys
  static const String _keyUserId = 'session_user_id';
  static const String _keyLastLogin = 'session_last_login';
  static const String _keyHasCompletedOnboarding = 'session_completed_onboarding';
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
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyUserId, userId);
    await prefs.setString(_keyLastLogin, DateTime.now().toIso8601String());
    await prefs.setBool(_keyHasCompletedOnboarding, hasCompletedOnboarding);
    await prefs.setBool(_keyProfileComplete, profileComplete);
    if (lastScreen != null) {
      await prefs.setString(_keyLastScreen, lastScreen);
    }
    // Set returning user status
    await prefs.setBool(_keyIsReturningUser, isReturningUser);
  }

  /// Update returning user status
  Future<void> setReturningUser(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyIsReturningUser, value);
  }

  /// Update session when profile is completed
  Future<void> updateProfileComplete(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyProfileComplete, value);
  }

  /// Update onboarding status
  Future<void> updateOnboardingComplete(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyHasCompletedOnboarding, value);
  }

  /// Update last visited screen
  Future<void> updateLastScreen(String screen) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyLastScreen, screen);
  }

  /// Update last login timestamp
  Future<void> updateLastVisit() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyLastLogin, DateTime.now().toIso8601String());
  }

  /// Get current session data
  Future<Map<String, dynamic>?> getSession() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString(_keyUserId);
    
    if (userId == null) return null;
    
    return {
      'user_id': userId,
      'last_login': prefs.getString(_keyLastLogin),
      'has_completed_onboarding': prefs.getBool(_keyHasCompletedOnboarding) ?? false,
      'last_screen': prefs.getString(_keyLastScreen),
      'profile_complete': prefs.getBool(_keyProfileComplete) ?? false,
    };
  }

  /// Get user ID from session
  Future<String?> getUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyUserId);
  }

  /// Check if user is returning (has logged in before)
  Future<bool> isReturningUser() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyIsReturningUser) ?? false;
  }

  /// Check if profile marked as complete
  Future<bool> isProfileComplete() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyProfileComplete) ?? false;
  }

  /// Get last visited screen
  Future<String?> getLastScreen() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyLastScreen);
  }

  /// Clear session on logout
  Future<void> clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyUserId);
    await prefs.remove(_keyLastLogin);
    await prefs.remove(_keyHasCompletedOnboarding);
    await prefs.remove(_keyLastScreen);
    await prefs.remove(_keyProfileComplete);
    // Keep _keyIsReturningUser to maintain returning user status across logins
  }

  /// Clear all session data including returning user flag (for testing/reset)
  Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }
}
