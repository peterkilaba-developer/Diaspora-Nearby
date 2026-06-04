import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Key for persisting the referral code across app restarts.
const _kReferralCodeKey = 'dn_pending_referral_code';

/// Stores a referral code captured from a deep link or search parameter
/// before the user has completed their profile.
/// The code is persisted to SharedPreferences so it survives app restarts.
class PendingReferralCodeNotifier extends Notifier<String?> {
  @override
  String? build() {
    // Eagerly load from SharedPreferences on first access
    _loadFromPrefs();
    return null; // initial state; will be updated async
  }

  Future<void> _loadFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_kReferralCodeKey);
    if (saved != null && saved.isNotEmpty) {
      state = saved;
    }
  }

  Future<void> set(String? code) async {
    state = code;
    final prefs = await SharedPreferences.getInstance();
    if (code != null && code.isNotEmpty) {
      await prefs.setString(_kReferralCodeKey, code);
    } else {
      await prefs.remove(_kReferralCodeKey);
    }
  }
}

final pendingReferralCodeProvider =
    NotifierProvider<PendingReferralCodeNotifier, String?>(
      PendingReferralCodeNotifier.new,
    );
