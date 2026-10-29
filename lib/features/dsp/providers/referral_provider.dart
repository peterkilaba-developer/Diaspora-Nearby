import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Key for persisting the referral code across app restarts.
const _kReferralCodeKey = 'dn_pending_referral_code';

/// Stores a referral code captured from a deep link or search parameter
/// before the user has completed their profile.
/// The code is persisted to SharedPreferences so it survives app restarts.
class PendingReferralCodeNotifier extends Notifier<String?> {
  static String? _cachedCode;
  static bool _loaded = false;

  @override
  String? build() {
    if (!_loaded) {
      unawaited(_loadFromPrefs());
    }
    return _cachedCode;
  }

  Future<String?> getOrLoad() async {
    if (_cachedCode != null && _cachedCode!.isNotEmpty) {
      return _cachedCode;
    }
    if (!_loaded) {
      await _loadFromPrefs();
    }
    return _cachedCode;
  }

  Future<void> _loadFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_kReferralCodeKey);
    _loaded = true;
    if (saved != null && saved.isNotEmpty) {
      _cachedCode = saved;
      state = saved;
    }
  }

  Future<void> set(String? code) async {
    _cachedCode = (code != null && code.isNotEmpty) ? code : null;
    _loaded = true;
    state = _cachedCode;
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
