import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

final pendingPhoneServiceProvider = Provider<PendingPhoneService>((ref) {
  return PendingPhoneService();
});

class PendingPhoneService {
  static const _key = 'pending_phone_number';

  Future<void> save(String e164Number) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, e164Number);
  }

  Future<String?> read() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_key);
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
