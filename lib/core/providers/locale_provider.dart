import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:diaspora_nearby/core/data/world_languages.dart';
import 'package:diaspora_nearby/core/providers/theme_provider.dart';

class AppLocaleNotifier extends Notifier<String> {
  static const String _langKey = 'app_language_code';

  @override
  String build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    final savedCode = prefs.getString(_langKey);
    if (savedCode != null && savedCode.trim().isNotEmpty) {
      return getWorldLanguageByCode(savedCode).code;
    }
    return 'en';
  }

  void setLanguage(String code, {String? uid}) {
    final resolved = getWorldLanguageByCode(code).code;
    if (state == resolved) return;
    state = resolved;

    final prefs = ref.read(sharedPreferencesProvider);
    unawaited(prefs.setString(_langKey, resolved));

    if (uid != null && uid.trim().isNotEmpty) {
      unawaited(
        FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .set({'preferredLanguage': resolved}, SetOptions(merge: true))
            .catchError((_) {}),
      );
    }
  }
}

final localeProvider = NotifierProvider<AppLocaleNotifier, String>(
  AppLocaleNotifier.new,
);

final currentWorldLanguageProvider = Provider<WorldLanguage>((ref) {
  final code = ref.watch(localeProvider);
  return getWorldLanguageByCode(code);
});
