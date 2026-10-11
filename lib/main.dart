import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:diaspora_nearby/features/shared/widgets/confetti_overlay.dart';
import 'package:diaspora_nearby/features/sharing/services/share_receiver_service.dart';
import 'package:diaspora_nearby/core/initialization/app_bootstrap.dart'; // [NEW] Bootstrap import

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:diaspora_nearby/config/app_environment.dart';
import 'package:diaspora_nearby/config/environment_firebase_options.dart';
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
        options: EnvironmentFirebaseOptions.currentPlatform,
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
  // Keep a plain `flutter run` on the production Firebase/app environment.
  // Explicit dev and staging runs still use main_dev.dart/main_staging.dart.
  await runDiasporaApp(environment: AppEnvironment.production);
}

Future<void> runDiasporaApp({AppEnvironment? environment}) async {
  if (environment != null) {
    AppEnvironmentConfig.configure(environment);
  }
  WidgetsFlutterBinding.ensureInitialized();

  return runZonedGuarded<Future<void>>(
    () async {
      AppEnvironmentConfig.logStartup();
      // Paint a native Flutter shell immediately. Firebase, preferences, and
      // provider wiring finish inside the bootstrap host instead of extending
      // the platform launch screen with a blank frame.
      runApp(const _BootstrapHost());
    },
    (error, stack) {
      if (!kIsWeb && Firebase.apps.isNotEmpty) {
        unawaited(
          FirebaseCrashlytics.instance.recordError(error, stack, fatal: true),
        );
      } else {
        debugPrint('Web Error: $error');
        debugPrint('Stack Trace: $stack');
      }
    },
  );
}

class _BootstrapHost extends StatefulWidget {
  const _BootstrapHost();

  @override
  State<_BootstrapHost> createState() => _BootstrapHostState();
}

class _BootstrapHostState extends State<_BootstrapHost> {
  late Future<ProviderContainer> _initialization;
  ProviderContainer? _container;

  @override
  void initState() {
    super.initState();
    _initialization = _initialize();
  }

  Future<ProviderContainer> _initialize() async {
    await AppBootstrap.init();

    // Stripe settings do not hold the application route.
    try {
      const stripeKey = String.fromEnvironment(
        'STRIPE_PUBLISHABLE_KEY',
        defaultValue: '',
      );
      if (stripeKey.isNotEmpty) {
        Stripe.publishableKey = stripeKey;
        unawaited(Stripe.instance.applySettings());
      } else if (AppEnvironmentConfig.isProduction) {
        debugPrint('▶ Stripe disabled: publishable key was not injected');
      }
    } catch (error) {
      debugPrint('▶ Stripe init skipped: $error');
    }

    final preferences = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
    );
    _container = container;

    try {
      unawaited(
        container
            .read(pushNotificationServiceProvider)
            .initialize()
            .catchError(
              (Object error) =>
                  debugPrint('Push Notification Init Failed: $error'),
            ),
      );
      FirebaseMessaging.onBackgroundMessage(
        _firebaseMessagingBackgroundHandler,
      );
    } catch (error) {
      debugPrint('Push Notification Setup Error: $error');
    }
    return container;
  }

  @override
  void dispose() {
    _container?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<ProviderContainer>(
      future: _initialization,
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          return UncontrolledProviderScope(
            container: snapshot.requireData,
            child: const MyApp(),
          );
        }
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          home: Scaffold(
            body: Center(
              child: snapshot.hasError
                  ? ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 480),
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.cloud_off_outlined, size: 48),
                            const SizedBox(height: 16),
                            const Text(
                              'Diaspora Nearby could not start securely.',
                              textAlign: TextAlign.center,
                            ),
                            if (snapshot.error != null) ...[
                              const SizedBox(height: 8),
                              Text(
                                '${snapshot.error}',
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.error,
                                  fontSize: 12,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                            const SizedBox(height: 16),
                            FilledButton(
                              onPressed: () {
                                _container?.dispose();
                                _container = null;
                                setState(() => _initialization = _initialize());
                              },
                              child: const Text('Retry'),
                            ),
                          ],
                        ),
                      ),
                    )
                  : const Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 16),
                        Text('Loading Diaspora Nearby…'),
                      ],
                    ),
            ),
          ),
        );
      },
    );
  }
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
      title: AppEnvironmentConfig.appTitle,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      routerConfig: router,
      builder: (context, child) {
        final app = ConfettiOverlay(
          key: confettiOverlayKey,
          child: child ?? const SizedBox(),
        );
        if (AppEnvironmentConfig.isProduction) {
          return app;
        }
        return Banner(
          message: AppEnvironmentConfig.bannerLabel,
          location: BannerLocation.topStart,
          child: app,
        );
      },
    );
  }
}
