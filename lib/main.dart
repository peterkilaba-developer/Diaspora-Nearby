import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:diaspora_nearby/features/shared/widgets/confetti_overlay.dart';
import 'package:diaspora_nearby/features/sharing/services/share_receiver_service.dart';
import 'package:diaspora_nearby/core/initialization/app_bootstrap.dart'; // [NEW] Bootstrap import
import 'package:google_fonts/google_fonts.dart'; // [PERF] For disabling runtime fetching

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:diaspora_nearby/firebase_options.dart';
import 'package:diaspora_nearby/features/notifications/services/push_notification_service.dart';
import 'package:diaspora_nearby/core/providers/theme_provider.dart';
import 'package:diaspora_nearby/theme/app_theme.dart';
import 'package:diaspora_nearby/router.dart';
import 'dart:async';
import 'dart:convert';

import 'package:firebase_crashlytics/firebase_crashlytics.dart';

import 'package:flutter_stripe/flutter_stripe.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Initialize Firebase only if not already initialized
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
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
    String? msgType = data['type'];
    String msgContent = (data['content'] ?? data['body'] ?? '') as String;
    String? senderName = data['senderName']?.toString();
    // Default title is sender name, can be overridden (e.g. for System messages)
    title = (senderName?.trim().isNotEmpty ?? false)
        ? senderName
        : 'New Message';

    if (msgType != null) {
      switch (msgType) {
        case 'audio':
          body = msgContent.isEmpty ? 'Voice message' : msgContent;
          break;
        case 'audio_file':
          body = msgContent.isEmpty ? 'Audio file' : msgContent;
          break;
        case 'image':
          body = msgContent.isEmpty ? 'Photo' : msgContent;
          break;
        case 'video':
          body = msgContent.isEmpty ? 'Video' : msgContent;
          break;
        case 'location':
          if (msgContent.isEmpty ||
              msgContent == 'Location' ||
              msgContent == 'Location') {
            body = 'Location';
          } else {
            body = msgContent;
          }
          break;
        case 'document':
          body = msgContent.isEmpty ? 'Document' : msgContent;
          break;
        case 'dsp_transfer':
          title = 'Diaspora Nearby';
          body = 'Transfer';
          break;
        case 'money-transfer':
          body = 'Money transfer';
          break;
        case 'relationship_request':
          title = 'New Relationship Request';
          final fromName = data['fromUserName'] ?? 'Someone';
          final relType = data['relationshipType'] ?? 'relative';
          body = '$fromName wants to add you as their $relType';
          break;
        case 'text':
        case 'chat':
        default:
          body = msgContent.isEmpty ? 'Sent a message' : msgContent;
          break;
      }
    }

    if (body == null || body.trim().isEmpty) {
      body = msgContent.trim().isNotEmpty ? msgContent : 'Sent a message';
    }

    if (title != null) {
      try {
        final flutterLocalNotificationsPlugin =
            FlutterLocalNotificationsPlugin();
        const androidSettings = AndroidInitializationSettings(
          '@mipmap/ic_launcher',
        );
        const settings = InitializationSettings(android: androidSettings);
        await flutterLocalNotificationsPlugin.initialize(settings: settings);

        await flutterLocalNotificationsPlugin.show(
          id: message.hashCode,
          title: title,
          body: body,
          notificationDetails: const NotificationDetails(
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
  runZonedGuarded<Future<void>>(
    () async {
      // [NEW] Centralized Initialization
      await AppBootstrap.init();

      // Fonts are not currently bundled as app assets, so runtime fetching must
      // remain enabled on every platform to avoid repeated GoogleFonts errors.
      try {
        // ignore: deprecated_member_use
        GoogleFonts.config.allowRuntimeFetching = true;
      } catch (_) {
        // GoogleFonts config may not be available on all platforms
      }

      // Initialize Stripe (non-blocking — not supported on web)
      // Key is injected at build time: --dart-define=STRIPE_PUBLISHABLE_KEY=pk_live_...
      try {
        const stripeKey = String.fromEnvironment(
          'STRIPE_PUBLISHABLE_KEY',
          defaultValue:
              'pk_test_51SCn3gI1F9UMWfaWdPiGbCBhcv2jpHOC06TrLhU2iHS5GxslRN4ltU4Chqc0rhTo7aW01BzxOjoXEPcCN7bafrlJ00jxw3bQsJ',
        );
        Stripe.publishableKey = stripeKey;
        await Stripe.instance.applySettings();
        debugPrint(
          '▶ Stripe initialized ✓ (live=${stripeKey.startsWith("pk_live")})',
        );
      } catch (e) {
        debugPrint('▶ Stripe init skipped: $e');
      }

      // Initialize Providers requiring SharedPreferences
      final sharedPreferences = await SharedPreferences.getInstance();

      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(sharedPreferences),
        ],
      );

      // Initialize Push Notifications (Provider-dependent)
      try {
        container.read(pushNotificationServiceProvider).initialize().catchError(
          (e) {
            debugPrint('Push Notification Init Failed: $e');
          },
        );
        FirebaseMessaging.onBackgroundMessage(
          _firebaseMessagingBackgroundHandler,
        );
      } catch (e) {
        debugPrint('Push Notification Setup Error: $e');
      }

      runApp(
        UncontrolledProviderScope(container: container, child: const MyApp()),
      );
    },
    (error, stack) {
      if (!kIsWeb) {
        FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      } else {
        debugPrint('Web Error: $error');
        debugPrint('Stack Trace: $stack');
      }
    },
  );
}

class MyApp extends ConsumerStatefulWidget {
  const MyApp({super.key});

  @override
  ConsumerState<MyApp> createState() => _MyAppState();
}

class _MyAppState extends ConsumerState<MyApp> {
  @override
  void initState() {
    super.initState();
    // Initialize Share Receiver
    // Post-frame callback to ensure providers are ready?
    // Usually safe in initState for event listeners.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(shareReceiverServiceProvider).initialize();
    });
  }

  @override
  void dispose() {
    // We can't easily dispose the service here as it's a Provider,
    // but the provider itself will be disposed if the container is.
    // However, for manual cleanup if needed:
    // ref.read(shareReceiverServiceProvider).dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
