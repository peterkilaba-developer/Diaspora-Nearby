import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:diaspora_nearby/core/data/world_languages.dart';
import 'package:diaspora_nearby/core/localization/app_localizations.dart';
import 'package:diaspora_nearby/core/providers/theme_provider.dart';

class TranslationRevisionNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void bump() {
    state = state + 1;
  }
}

final translationRevisionProvider =
    NotifierProvider<TranslationRevisionNotifier, int>(
      TranslationRevisionNotifier.new,
    );

class AppLocaleNotifier extends Notifier<String> {
  static const String _langKey = 'app_language_code';

  @override
  String build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    AppLocalizations.bindPersistence(
      prefs: prefs,
      onCacheUpdated: () {
        Future.microtask(() {
          try {
            ref.read(translationRevisionProvider.notifier).bump();
          } catch (_) {}
        });
      },
    );

    final savedCode = prefs.getString(_langKey);
    if (savedCode != null && savedCode.trim().isNotEmpty) {
      final resolved = getWorldLanguageByCode(savedCode).code;
      AppLocalizations.loadPersistedLanguageCache(resolved);
      if (resolved != 'en') {
        unawaited(AppLocalizations.preloadCoreVocabulary(resolved));
      }
      return resolved;
    }
    return 'en';
  }

  void setLanguage(String code, {String? uid}) {
    final resolved = getWorldLanguageByCode(code).code;
    AppLocalizations.loadPersistedLanguageCache(resolved);
    if (resolved != 'en') {
      unawaited(AppLocalizations.preloadCoreVocabulary(resolved));
    }
    if (state != resolved) {
      state = resolved;
    } else {
      ref.read(translationRevisionProvider.notifier).bump();
    }

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
