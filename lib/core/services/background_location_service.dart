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
  static const String _notificationChannelId = 'diaspora_location_channel';
  static final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  static Future<void> initializeService() async {
    if (_isInitialized) {
      // No-log: Already initialized
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
    await _notificationsPlugin.initialize(initializationSettings);

    // [FIX] Explicitly create the Notification Channel with HIGH importance
    const String newChannelId = 'diaspora_location_v2';
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      newChannelId,
      'Background Service',
      description: 'Used for background location updates',
      importance: Importance.high, // Set to high to ensure service validity
    );

    if (defaultTargetPlatform == TargetPlatform.android) {
      await _notificationsPlugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(channel);
    }

    // Configure Service
    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: onStart,
        autoStart: true,
        isForegroundMode: true,
        notificationChannelId: newChannelId,
        initialNotificationTitle: 'Diaspora Nearby',
        initialNotificationContent: 'Background location active',
        foregroundServiceNotificationId: 888,
      ),
      iosConfiguration: IosConfiguration(
        autoStart: false,
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

    // No-log: Started

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
      final AndroidInitializationSettings initializationSettingsAndroid =
          const AndroidInitializationSettings('@mipmap/ic_launcher');
      final InitializationSettings initializationSettings =
          InitializationSettings(android: initializationSettingsAndroid);
      await _notificationsPlugin.initialize(initializationSettings);

      // [DEBUG] Explicit startup log
      // No-log start logic

      // [DEBUG] Run immediately after 5 seconds to verify logic without waiting
      Future.delayed(const Duration(seconds: 5), () async {
        // No-log immediate check
        try {
          final user = FirebaseAuth.instance.currentUser;
          if (user != null) {
            await LocationUpdateService().updateCurrentLocation(user.uid);
          } else {
            // No-log
          }
        } catch (e) {
          debugPrint('ðŸ“ [BACKGROUND] Immediate check failed: $e');
        }
      });

      // Start location updates
      // [UPDATED] Switch from Timer to Stream for reliable background updates
      // User requested 10 miles (approx 16093 meters)
      const int distanceFilterMeters = 16093;

      late LocationSettings locationSettings;

      if (defaultTargetPlatform == TargetPlatform.android) {
        locationSettings = AndroidSettings(
          accuracy: LocationAccuracy.medium,
          distanceFilter: distanceFilterMeters,
          forceLocationManager: true,
          // Optional: configuration for battery usage vs latency
        );
      } else if (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS) {
        locationSettings = AppleSettings(
          accuracy: LocationAccuracy.medium,
          activityType: ActivityType.automotiveNavigation, // Good for driving
          distanceFilter: distanceFilterMeters,
          pauseLocationUpdatesAutomatically:
              false, // CRITICAL: Stop iOS from killing the stream
          showBackgroundLocationIndicator: false,
        );
      } else {
        locationSettings = const LocationSettings(
          accuracy: LocationAccuracy.medium,
          distanceFilter: distanceFilterMeters, // 10 miles
        );
      }

      // No-log

      Geolocator.getPositionStream(locationSettings: locationSettings).listen(
        (Position? position) async {
          // No-log
          await _performBackgroundCheck(service);
        },
        onError: (e) {
          debugPrint('📍 [BACKGROUND] Stream Error: $e');
        },
      );
    } catch (e) {
      debugPrint('CRITICAL: Error in background service onStart: $e');
    }
  }

  // [NEW] Helper to perform the actual update and check
  static Future<void> _performBackgroundCheck(ServiceInstance service) async {
    try {
      if (service is AndroidServiceInstance) {
        if (await service.isForegroundService()) {
          service.setForegroundNotificationInfo(
            title: 'Diaspora Nearby',
            content: 'Active in background (Location Updated)',
          );
        }
      }

      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        debugPrint('Background: Updating location for ${user.uid}');
        // Update location in DB
        await LocationUpdateService().updateCurrentLocation(user.uid);
      } else {
        debugPrint('No user logged in, skipping background location update.');
      }
    } catch (e) {
      debugPrint('Error in background check: $e');
    }
  }
}
