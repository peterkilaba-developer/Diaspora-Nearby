import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:audio_session/audio_session.dart';

import 'package:diaspora_nearby/core/services/database_service.dart';
import 'package:diaspora_nearby/features/chat/services/mention_monitor_service.dart';
import 'package:diaspora_nearby/features/marketplace/utils/exchange_rate_service.dart';
import 'package:diaspora_nearby/config/environment_firebase_options.dart';

/// Centralizes all application initialization logic.
/// Enforces strict ordering to prevent race conditions.
class AppBootstrap {
  static Future<void> init() async {
    // 1. Core Framework Init
    WidgetsFlutterBinding.ensureInitialized();
    debugPrint('▶ AppBootstrap: [1/4] WidgetsBinding initialized');

    // 2. Firebase & Critical Infrastructure (must complete first)
    debugPrint('▶ AppBootstrap: [2/4] Initializing Firebase...');
    await _initFirebase();
    debugPrint('▶ AppBootstrap: [2/4] Firebase initialized ✓');

    // Optional subsystems must not delay first paint. They initialize in
    // parallel in the background and retain their existing fallbacks.
    unawaited(_initDeferred());
    debugPrint('▶ AppBootstrap: ✅ CRITICAL INIT COMPLETE');
  }

  static Future<void> _initDeferred() async {
    try {
      await Future.wait([
        _initAudio(),
        _initStorage(),
        _warmCredentials(),
        _initServices(),
      ]);
      debugPrint('▶ AppBootstrap: Deferred services ready');
    } catch (error, stack) {
      debugPrint('AppBootstrap: Deferred initialization failed: $error');
      if (!kIsWeb) {
        await FirebaseCrashlytics.instance.recordError(error, stack);
      }
    }
  }

  static Future<void> _initFirebase() async {
    try {
      if (Firebase.apps.isEmpty) {
        debugPrint('  → Firebase.initializeApp starting...');
        await Firebase.initializeApp(
          options: EnvironmentFirebaseOptions.currentPlatform,
        );
        debugPrint('  → Firebase.initializeApp done');
      }

      // [PERF] Firestore persistence on ALL platforms. On web this is
      // opt-in (IndexedDB) — without it every browser refresh re-fetches
      // all data from the network, which made reloads painfully slow.
      if (!kIsWeb) {
        // Crashlytics for non-web
        FlutterError.onError =
            FirebaseCrashlytics.instance.recordFlutterFatalError;
      }

      // App Check
      // Play Integrity works for apps distributed via Google Play (internal/closed/open/production).
      // Debug provider is used for local development builds.
      try {
        const appleDebugToken = String.fromEnvironment(
          'APP_CHECK_DEBUG_TOKEN',
          defaultValue: 'F559B1FA-0CAD-41EB-A83B-ECE2AFA4CDC3',
        );

        final activation = FirebaseAppCheck.instance.activate(
          providerWeb: ReCaptchaV3Provider(
            '6LcBv5EqAAAAADzV3g87x4u8f-xL0-G6Y5-xL0-G',
          ),
          providerAndroid: kReleaseMode
              ? const AndroidPlayIntegrityProvider()
              : const AndroidDebugProvider(),
          providerApple: appleDebugToken.isNotEmpty
              ? const AppleDebugProvider(debugToken: appleDebugToken)
              : const AppleDeviceCheckProvider(),
        );
        // [PERF] Don't block first paint on App Check activation/network handshakes.
        // Tokens are fetched lazily by the SDK once activation completes.
        unawaited(
          activation.catchError(
            (Object e) => debugPrint('AppBootstrap: App Check Init Error: $e'),
          ),
        );
        debugPrint('  → AppCheck.activate started (non-blocking)');
      } catch (e) {
        debugPrint('AppBootstrap: App Check Init Error: $e');
      }

      // Access Firestore only after App Check activation/token warm-up.
      try {
        FirebaseFirestore.instance.settings = const Settings(
          persistenceEnabled: true,
          cacheSizeBytes: 100000000, // 100MB
        );
        debugPrint('AppBootstrap: Firestore Persistence Configured');
      } catch (e) {
        debugPrint('AppBootstrap: Persistence Init Warning: $e');
      }
    } catch (e) {
      debugPrint('AppBootstrap: Firebase Fatal Error: $e');
      rethrow; // Fatal
    }
  }

  static Future<void> _warmCredentials() async {
    if (kIsWeb) return;
    final user = FirebaseAuth.instance.currentUser;
    await Future.wait([
      FirebaseAppCheck.instance
          .getToken(false)
          .timeout(const Duration(seconds: 15))
          .catchError((Object e) {
            debugPrint('AppBootstrap: App Check token warm-up failed: $e');
            return null;
          }),
      if (user != null)
        user
            .getIdToken(false)
            .timeout(const Duration(seconds: 15))
            .catchError((Object e) {
              debugPrint('AppBootstrap: Auth token warm-up failed: $e');
              return null;
            }),
    ]);
  }

  static Future<void> _initAudio() async {
    if (kIsWeb) return; // [FIX] JustAudioBackground not supported on web
    try {
      debugPrint('  → JustAudioBackground.init starting...');
      await JustAudioBackground.init(
        androidNotificationChannelId: 'com.diasporanearby.audio',
        androidNotificationChannelName: 'Radio Playback',
        androidNotificationOngoing: true,
      );
      debugPrint('  → JustAudioBackground.init done');

      debugPrint('  → AudioSession.configure starting...');
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.music());
      debugPrint('  → AudioSession.configure done');
    } catch (e) {
      debugPrint('AppBootstrap: Audio Init Warning: $e');
    }
  }

  static Future<void> _initStorage() async {
    debugPrint('  → DatabaseService.init starting...');
    await DatabaseService().init();
    debugPrint('  → DatabaseService.init done');
  }

  static Future<void> _initServices() async {
    // Services that need to start listening immediately
    debugPrint('  → MentionMonitorService.initialize starting...');
    await MentionMonitorService().initialize();
    debugPrint('  → MentionMonitorService.initialize done');

    // Live exchange rates (non-blocking, falls back to hardcoded)
    unawaited(
      ExchangeRateService.instance.initialize().catchError((Object e) {
        debugPrint('AppBootstrap: Exchange Rate Init Warning: $e');
      }),
    );
  }
}
