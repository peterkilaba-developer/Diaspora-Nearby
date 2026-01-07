import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_app_check/firebase_app_check.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'router.dart';
import 'theme/app_theme.dart';
import 'firebase_options.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:diaspora_nearby/providers/theme_provider.dart';
import 'package:diaspora_nearby/services/local_cache_service.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:diaspora_nearby/services/push_notification_service.dart';
import 'package:diaspora_nearby/features/auth/repository/auth_repository.dart';
import 'package:diaspora_nearby/services/background_location_service.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Initialize Firebase only if not already initialized (prevents duplicate-app error)
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    }
  } catch (e) {
    // Ignore duplicate app errors (common during hot restart)
    if (e.toString().contains('duplicate-app') || e.toString().contains('already exists')) {
      debugPrint('Firebase already initialized in background handler');
    } else {
      rethrow;
    }
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Local Cache initialization
  final sharedPreferences = await SharedPreferences.getInstance();
  LocalCacheService.init(sharedPreferences);

  // Initialize Push Notifications
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(sharedPreferences),
    ],
  );
  try {
    try {
      if (Firebase.apps.isEmpty) { 
        await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform); 
      }
    } catch (e) {
      if (e.toString().contains('duplicate-app') || e.toString().contains('already exists')) {
        debugPrint('Firebase already initialized: $e');
      } else {
        rethrow;
      }
    }
    
    // Web App Check
    try {
      await FirebaseAppCheck.instance.activate(
        webProvider: ReCaptchaV3Provider('6LcBv5EqAAAAADzV3g87x4u8f-xL0-G6Y5-xL0-G'),
        androidProvider: kReleaseMode ? AndroidProvider.playIntegrity : AndroidProvider.debug,
        appleProvider: AppleProvider.deviceCheck,
      );
    } catch (e) {
      debugPrint('Firebase App Check Init Error: $e');
    }

    // Initialize Push Notifications via Provider (Don't await to prevent blocking)
    container.read(pushNotificationServiceProvider).initialize().catchError((e) {
      debugPrint('Push Notification Init Failed: $e');
    });

    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  } catch (e) {
    debugPrint('Firebase Init Error: $e');
  }

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const MyApp(),
    ),
  );
}

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeProvider);
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: 'Diaspora Nearby',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      routerConfig: router,
    );
  }
}
