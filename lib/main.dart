import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:diaspora_nearby/features/shared/widgets/confetti_overlay.dart';
import 'package:diaspora_nearby/features/sharing/services/share_receiver_service.dart';
import 'package:diaspora_nearby/core/initialization/app_bootstrap.dart';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:diaspora_nearby/config/app_environment.dart';
import 'package:diaspora_nearby/config/environment_firebase_options.dart';
import 'package:diaspora_nearby/features/notifications/services/push_notification_service.dart';
import 'package:diaspora_nearby/core/providers/locale_provider.dart';
import 'package:diaspora_nearby/core/providers/theme_provider.dart';
import 'package:diaspora_nearby/theme/app_theme.dart';
import 'package:diaspora_nearby/router.dart';
import 'dart:async';
import 'dart:convert';

import 'package:firebase_crashlytics/firebase_crashlytics.dart';

import 'package:flutter_stripe/flutter_stripe.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: EnvironmentFirebaseOptions.currentPlatform,
      );
    }
  } catch (e) {
    debugPrint('Firebase already initialized in background handler: $e');
  }

  if (message.notification == null) {
    final data = message.data;
    String? title;
    String? body;

    String? msgType = data['type'];
    String msgContent = (data['content'] ?? data['body'] ?? '') as String;
    String? senderName = data['senderName']?.toString();
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
          if (msgContent.isEmpty || msgContent == 'Location') {
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

        final chatId = data['chatId']?.toString();
        final senderId = data['senderId']?.toString();
        final containerKey = (chatId != null && chatId.trim().isNotEmpty)
            ? chatId.trim()
            : ((senderId != null && senderId.trim().isNotEmpty)
                  ? senderId.trim()
                  : null);

        final notificationId = containerKey != null
            ? PushNotificationService.chatNotificationId(containerKey)
            : message.hashCode;
        final notificationTag = containerKey != null
            ? 'chat_$containerKey'
            : null;

        StyleInformation? styleInfo;
        final rawUnreadLines = data['unreadLines'];
        if (rawUnreadLines != null) {
          try {
            final decoded = rawUnreadLines is String
                ? jsonDecode(rawUnreadLines)
                : rawUnreadLines;
            if (decoded is List && decoded.isNotEmpty) {
              final lines = decoded
                  .map((e) => e?.toString().trim() ?? '')
                  .where((e) => e.isNotEmpty)
                  .toList();
              if (lines.isNotEmpty) {
                body = lines.join('\n');
                final senderPerson = Person(name: title, key: containerKey);
                styleInfo = MessagingStyleInformation(
                  senderPerson,
                  conversationTitle: lines.length > 1
                      ? '$title (${lines.length} messages)'
                      : null,
                  groupConversation: false,
                  messages: lines
                      .map(
                        (line) => Message(line, DateTime.now(), senderPerson),
                      )
                      .toList(),
                );
              }
            }
          } catch (_) {}
        }

        await flutterLocalNotificationsPlugin.show(
          id: notificationId,
          title: title,
          body: body,
          notificationDetails: NotificationDetails(
            android: AndroidNotificationDetails(
              'high_importance_channel',
              'High Importance Notifications',
              icon: '@mipmap/ic_launcher',
              priority: Priority.high,
              importance: Importance.max,
              tag: notificationTag,
              groupKey: notificationTag,
              styleInformation: styleInfo,
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
      // [PERF] Pre-resolve Firebase, SharedPreferences, and permission cache
      // in parallel while native launch screen is visible so Flutter's first
      // rendered frame is the actual destination screen with 0 loading spinner.
      try {
        final container = await _bootstrapContainer();
        runApp(
          UncontrolledProviderScope(container: container, child: const MyApp()),
        );
      } catch (error) {
        runApp(_BootstrapHost(initialError: error));
      }
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

Future<ProviderContainer> _bootstrapContainer() async {
  final results = await Future.wait([
    SharedPreferences.getInstance(),
    AppBootstrap.init(),
    warmPermissionCache(),
  ]);
  final preferences = results[0] as SharedPreferences;

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

  final container = ProviderContainer(
    overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
  );

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
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  } catch (error) {
    debugPrint('Push Notification Setup Error: $error');
  }
  return container;
}

class _BootstrapHost extends StatefulWidget {
  final Object? initialError;
  const _BootstrapHost({this.initialError});

  @override
  State<_BootstrapHost> createState() => _BootstrapHostState();
}

class _BootstrapHostState extends State<_BootstrapHost> {
  Future<ProviderContainer>? _initialization;
  ProviderContainer? _container;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _error = widget.initialError;
    if (_error == null) {
      _initialization = _initialize();
    }
  }

  Future<ProviderContainer> _initialize() async {
    final container = await _bootstrapContainer();
    _container = container;
    return container;
  }

  @override
  void dispose() {
    _container?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_initialization == null && _error != null) {
      return _buildErrorApp(context, _error);
    }
    return FutureBuilder<ProviderContainer>(
      future: _initialization,
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          return UncontrolledProviderScope(
            container: snapshot.requireData,
            child: const MyApp(),
          );
        }
        return _buildErrorApp(context, snapshot.error);
      },
    );
  }

  Widget _buildErrorApp(BuildContext context, Object? error) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      home: Scaffold(
        body: Center(
          child: error != null
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
                        const SizedBox(height: 8),
                        Text(
                          '$error',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                            fontSize: 12,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: () {
                            _container?.dispose();
                            _container = null;
                            setState(() {
                              _error = null;
                              _initialization = _initialize();
                            });
                          },
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ),
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(shareReceiverServiceProvider).initialize();
    });
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeProvider);
    final currentLang = ref.watch(currentWorldLanguageProvider);
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: AppEnvironmentConfig.appTitle,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      routerConfig: router,
      builder: (context, child) {
        final app = Directionality(
          textDirection: currentLang.isRtl
              ? TextDirection.rtl
              : TextDirection.ltr,
          child: ConfettiOverlay(
            key: confettiOverlayKey,
            child: child ?? const SizedBox(),
          ),
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
