import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:audio_session/audio_session.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:diaspora_nearby/core/services/database_service.dart';
import 'package:diaspora_nearby/features/chat/services/mention_monitor_service.dart';
import 'package:diaspora_nearby/firebase_options.dart';

/// Centralizes all application initialization logic.
/// Enforces strict ordering to prevent race conditions.
class AppBootstrap {
  static Future<void> init() async {
    // 1. Core Framework Init
    WidgetsFlutterBinding.ensureInitialized();

    // 2. Firebase & Critical Infrastructure
    await _initFirebase();

    // 3. Audio & Media Services
    await _initAudio();

    // 4. Local Storage & Cache
    await _initStorage();

    // 5. Feature Services
    await _initServices();
  }

  static Future<void> _initFirebase() async {
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
      }

      // [CRITICAL] Persistence MUST be enabled immediately after init
      if (!kIsWeb) {
        try {
          FirebaseDatabase.instance.setPersistenceEnabled(true);
          FirebaseDatabase.instance.setPersistenceCacheSizeBytes(
            100000000,
          ); // 100MB
          debugPrint('âœ… AppBootstrap: Firebase Persistence Enabled');
        } catch (e) {
          debugPrint('âš ï¸ AppBootstrap: Persistence Init Warning: $e');
        }

        // Crashlytics for non-web
        FlutterError.onError =
            FirebaseCrashlytics.instance.recordFlutterFatalError;
      }

      // App Check
      try {
        await FirebaseAppCheck.instance.activate(
          webProvider: ReCaptchaV3Provider(
            '6LcBv5EqAAAAADzV3g87x4u8f-xL0-G6Y5-xL0-G',
          ),
          androidProvider: kReleaseMode
              ? AndroidProvider.playIntegrity
              : AndroidProvider.debug,
          appleProvider: AppleProvider.deviceCheck,
        );
      } catch (e) {
        debugPrint('⚠️ AppBootstrap: App Check Init Error: $e');
      }
    } catch (e) {
      debugPrint('❌ AppBootstrap: Firebase Fatal Error: $e');
      rethrow; // Fatal
    }
  }

  static Future<void> _initAudio() async {
    if (kIsWeb) return; // [FIX] JustAudioBackground not supported on web
    try {
      await JustAudioBackground.init(
        androidNotificationChannelId: 'com.diasporanearby.audio',
        androidNotificationChannelName: 'Radio Playback',
        androidNotificationOngoing: true,
      );

      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.music());
    } catch (e) {
      debugPrint('⚠️ AppBootstrap: Audio Init Warning: $e');
    }
  }

  static Future<void> _initStorage() async {
    // Shared preferences is used by SessionService via provider
    // final sharedPreferences = await SharedPreferences.getInstance(); 
    // LocalCacheService.init(sharedPreferences); 
    await DatabaseService().init();
  }

  static Future<void> _initServices() async {
    // Services that need to start listening immediately
    await MentionMonitorService().initialize();
  }
}
