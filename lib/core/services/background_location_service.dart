import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:diaspora_nearby/firebase_options.dart';
import 'package:diaspora_nearby/core/services/location_update_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:diaspora_nearby/features/chat/services/mention_monitor_service.dart'; // [NEW]
import 'package:geolocator/geolocator.dart'; // [NEW]

@pragma('vm:entry-point')
class BackgroundLocationService {
  static bool _isInitialized = false;
  static Position? cachedLastKnownPosition;
  static final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  static const String silentChannelId = 'diaspora_location_silent';
  static const String legacyChannelId = 'diaspora_location_v2';
  static const AndroidNotificationChannel backgroundServiceChannel =
      AndroidNotificationChannel(
        silentChannelId,
        'Background Service',
        description: 'Silent background location updates',
        importance: Importance.low,
        playSound: false,
        enableVibration: false,
        showBadge: false,
      );

  static Future<void> initializeService() async {
    if (_isInitialized) {
      return;
    }

    final service = FlutterBackgroundService();

    // Initialize Local Notifications Plugin
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const InitializationSettings initializationSettings =
        InitializationSettings(
          android: initializationSettingsAndroid,
          iOS: DarwinInitializationSettings(),
        );
    await _notificationsPlugin.initialize(settings: initializationSettings);

    if (defaultTargetPlatform == TargetPlatform.android) {
      final androidPlugin = _notificationsPlugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      // Remove legacy high-importance channel so Android does not retain sound/heads-up settings
      await androidPlugin?.deleteNotificationChannel(
        channelId: legacyChannelId,
      );
      await androidPlugin?.createNotificationChannel(backgroundServiceChannel);
    }

    // Configure Service
    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: onStart,
        autoStart: true,
        isForegroundMode: true,
        notificationChannelId: silentChannelId,
        initialNotificationTitle: 'Diaspora Nearby',
        initialNotificationContent: 'Background location active',
        foregroundServiceNotificationId: 888,
      ),
      iosConfiguration: IosConfiguration(
        autoStart: true,
        onForeground: onStart,
        onBackground: onIosBackground,
      ),
    );

    _isInitialized = true;
  }

  @pragma('vm:entry-point')
  static Future<bool> onIosBackground(ServiceInstance service) async {
    WidgetsFlutterBinding.ensureInitialized();
    DartPluginRegistrant.ensureInitialized();
    return true;
  }

  @pragma('vm:entry-point')
  static Future<void> onStart(ServiceInstance service) async {
    // [fix] Ensure bindings are initialized FIRST
    DartPluginRegistrant.ensureInitialized();
    WidgetsFlutterBinding.ensureInitialized();

    if (service is AndroidServiceInstance) {
      service.on('setAsForeground').listen((event) {
        service.setAsForegroundService();
      });
      service.on('setAsBackground').listen((event) {
        service.setAsBackgroundService();
      });
    }

    service.on('stopService').listen((event) {
      service.stopSelf();
    });

    try {
      // Initialize Firebase
      await _initFirebaseAndWork(service);

      // [NEW] Start Mention Monitor in Background Service Isolate
      await MentionMonitorService().initialize();
    } catch (e) {
      debugPrint('CRITICAL: Error in background service onStart: $e');
    }
  }

  static Future<void> _initFirebaseAndWork(ServiceInstance service) async {
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
      }

      // Re-init notifications inside the isolate
      const AndroidInitializationSettings initializationSettingsAndroid =
          AndroidInitializationSettings('@mipmap/ic_launcher');
      const InitializationSettings initializationSettings =
          InitializationSettings(android: initializationSettingsAndroid);
      await _notificationsPlugin.initialize(settings: initializationSettings);

      // [PERF] Run initial location check immediately without artificial 5s delay
      unawaited(() async {
        try {
          final user = FirebaseAuth.instance.currentUser;
          if (user != null) {
            await LocationUpdateService().updateCurrentLocation(user.uid);
          }
        } catch (e) {
          debugPrint('📍 [BACKGROUND] Immediate check failed: $e');
        }
      }());

      // Start location updates (15m distance filter + 3-min periodic heartbeat
      // so 100-ft / 10-min automatic proximity and 60-min Grassroots Gatherings
      // are continuously evaluated even while both devices sit stationary).
      const int distanceFilterMeters = 15;

      late LocationSettings locationSettings;

      if (defaultTargetPlatform == TargetPlatform.android) {
        locationSettings = AndroidSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: distanceFilterMeters,
          forceLocationManager: true,
        );
      } else if (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS) {
        locationSettings = AppleSettings(
          accuracy: LocationAccuracy.high,
          activityType: ActivityType.fitness,
          distanceFilter: distanceFilterMeters,
          pauseLocationUpdatesAutomatically: false,
          showBackgroundLocationIndicator: false,
        );
      } else {
        locationSettings = const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: distanceFilterMeters,
        );
      }

      Geolocator.getPositionStream(locationSettings: locationSettings).listen(
        (Position? position) async {
          if (position != null) {
            cachedLastKnownPosition = position;
          }
          await _performBackgroundCheck(service);
        },
        onError: (e) {
          debugPrint('📍 [BACKGROUND] Stream Error: $e');
        },
      );

      // Periodic 3-minute heartbeat so stationary devices sitting together
      // within 100 feet complete their 10-min and 60-min dwell windows.
      Timer.periodic(const Duration(minutes: 3), (_) async {
        await _performBackgroundCheck(service);
      });
    } catch (e) {
      debugPrint('CRITICAL: Error in background service onStart: $e');
    }
  }

  static Future<void> _performBackgroundCheck(ServiceInstance service) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        debugPrint('Background: Updating location for ${user.uid}');
        await LocationUpdateService().updateCurrentLocation(user.uid);
      } else {
        debugPrint('No user logged in, skipping background location update.');
      }
    } catch (e) {
      debugPrint('Error in background check: $e');
    }
  }
}
