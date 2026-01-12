import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'dart:async';
import 'dart:convert';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

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
import 'package:diaspora_nearby/services/database_service.dart';
import 'package:diaspora_nearby/services/database_service.dart';
import 'package:diaspora_nearby/services/mention_monitor_service.dart';
import 'package:diaspora_nearby/features/shared/widgets/confetti_overlay.dart'; // [NEW]

import 'package:firebase_crashlytics/firebase_crashlytics.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Initialize Firebase only if not already initialized
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    }
  } catch (e) {
    debugPrint('Firebase already initialized in background handler: $e');
  }

  // Handle Data-only messages (Android doesn't show these automatically)
  if (message.notification == null) {
      final data = message.data;
      String? title;
      String? body;

      // Logic mirrors PushNotificationService foreground logic
      if (data['type'] == 'chat' || data['type'] == 'text' || data['type'] == 'image' || data['type'] == 'video') {
          title = data['senderName'] ?? 'New Message';
          body = data['content'] ?? data['body'] ?? 'Sent a message';
          
          if ((body == null || body.isEmpty) && data['type'] != 'text') {
              if (data['type'] == 'image') body = 'Photo';
              else if (data['type'] == 'video') body = 'Video';
          }
      } else if (data['type'] == 'dsp_transfer') {
           title = 'Diaspora Nearby';
           dynamic amountVal = data['amount'];
           // Try parsing metadata if amount is missing
           if (amountVal == null && data['metadata'] != null) {
              if (data['metadata'] is String) {
                 try {
                   final meta = jsonDecode(data['metadata']);
                   amountVal = meta['amount'];
                 } catch (_) {}
              } else if (data['metadata'] is Map) {
                 amountVal = data['metadata']['amount'];
              }
           }
           
           if (amountVal != null) {
             final senderName = data['senderName'] ?? 'Someone';
             body = 'You received $amountVal DSP from $senderName';
           }
      }

      if (title != null && body != null) {
          try {
             final flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
             const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
             const settings = InitializationSettings(android: androidSettings);
             await flutterLocalNotificationsPlugin.initialize(settings);
             
             await flutterLocalNotificationsPlugin.show(
              message.hashCode,
              title,
              body,
              const NotificationDetails(
                android: AndroidNotificationDetails(
                  'high_importance_channel',
                  'High Importance Notifications',
                  icon: '@mipmap/ic_launcher',
                  priority: Priority.high,
                  importance: Importance.max,
                ),
              ),
              payload: jsonEncode(message.data),
            );
          } catch (e) {
             debugPrint('Error showing background notification: $e');
          }
      }
  }
}

void main() async {
  runZonedGuarded<Future<void>>(() async {
    WidgetsFlutterBinding.ensureInitialized();
    
    // Local Cache initialization
    final sharedPreferences = await SharedPreferences.getInstance();
    LocalCacheService.init(sharedPreferences);
    await DatabaseService().init();

    // Initialize Push Notifications
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(sharedPreferences),
      ],
    );

    try {
      if (Firebase.apps.isEmpty) { 
        await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform); 
      }
      
      if (!kIsWeb) {
        // Pass all uncaught "fatal" errors from the framework to Crashlytics
        FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
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

      // Initialize Push Notifications
      container.read(pushNotificationServiceProvider).initialize().catchError((e) {
        debugPrint('Push Notification Init Failed: $e');
      });

      FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
      
      // [NEW] Initialize Mention Monitor Service (Foreground Listener)
      await MentionMonitorService().initialize();
    } catch (e) {
      debugPrint('Firebase Init Error: $e');
    }

    runApp(
      UncontrolledProviderScope(
        container: container,
        child: const MyApp(),
      ),
    );
  }, (error, stack) {
    if (!kIsWeb) {
      // Pass all uncaught asynchronous errors that aren't handled by the Flutter framework to Crashlytics
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
    } else {
      debugPrint('Web Error: $error');
      debugPrint('Stack Trace: $stack');
    }
  });
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
      builder: (context, child) {
        return ConfettiOverlay(
          key: confettiOverlayKey,
          child: child ?? const SizedBox(),
        );
      },
    );
  }
}
