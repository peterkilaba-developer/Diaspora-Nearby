import 'dart:async';
import 'dart:ui';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:diaspora_nearby/firebase_options.dart';
import 'package:diaspora_nearby/services/location_update_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:diaspora_nearby/services/proximity_service.dart'; 
import 'package:diaspora_nearby/services/mention_monitor_service.dart'; // [NEW]

@pragma('vm:entry-point')
class BackgroundLocationService {
  static bool _isInitialized = false;
  static const String _notificationChannelId = 'diaspora_location_channel';
  static final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();

  static Future<void> initializeService() async {
    if (_isInitialized) {
      debugPrint('BackgroundLocationService: Already initialized, skipping.');
      return;
    }

    final service = FlutterBackgroundService();

    // Initialize Local Notifications Plugin
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const InitializationSettings initializationSettings = InitializationSettings(
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
      importance: Importance.low, // [UPDATED] Low importance to prevent popping up
    );

    final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

    if (defaultTargetPlatform == TargetPlatform.android) {
        await flutterLocalNotificationsPlugin
            .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
            ?.createNotificationChannel(channel);
    }
    
    // Configure Service
    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: onStart,
        autoStart: true, 
        isForegroundMode: true,
        notificationChannelId: newChannelId, // Use the high importance channel
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

    debugPrint('📍 [BACKGROUND] BackgroundLocationService started (Release Mode).');

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
      final InitializationSettings initializationSettings = InitializationSettings(
        android: initializationSettingsAndroid,
      );
      await _notificationsPlugin.initialize(initializationSettings);

      // [DEBUG] Explicit startup log
      debugPrint('📍 [BACKGROUND] Service Started. Scheduling immediate check...');

      // [DEBUG] Run immediately after 5 seconds to verify logic without waiting
      Future.delayed(const Duration(seconds: 5), () async {
         debugPrint('📍 [BACKGROUND] Running IMMEDIATE initial check...');
         try {
           final user = FirebaseAuth.instance.currentUser;
           if (user != null) {
              await LocationUpdateService().updateCurrentLocation(user.uid);
              await ProximityService().checkAndNotify(user.uid);
           } else {
              debugPrint('📍 [BACKGROUND] No user for immediate check.');
           }
         } catch(e) {
            debugPrint('📍 [BACKGROUND] Immediate check failed: $e');
         }
      });

      // Start location updates
      // [UPDATED] Interval: 15 minutes for Release to improve proximity responsiveness
      final duration = kDebugMode ? const Duration(minutes: 1) : const Duration(minutes: 15);
      Timer.periodic(duration, (timer) async {
        try {
          if (service is AndroidServiceInstance) {
            if (await service.isForegroundService()) {
              service.setForegroundNotificationInfo(
                title: 'Diaspora Nearby',
                content: 'Active in background',
              );
            }
          }

          final user = FirebaseAuth.instance.currentUser;
          if (user != null) {
            debugPrint('Background: Updating location for ${user.uid}');
            await LocationUpdateService().updateCurrentLocation(user.uid);
            
            // [NEW] Delegate to ProximityService
            await ProximityService().checkAndNotify(user.uid);
          } else {
            debugPrint('No user logged in, skipping background location update.');
          }
        } catch (e) {
          debugPrint('Error in background timer loop: $e');
        }
      });
    } catch (e) {
      debugPrint('CRITICAL: Error in background service onStart: $e');
    }
  }
}

