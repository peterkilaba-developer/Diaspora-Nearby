import 'dart:async';
import 'dart:ui';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:diaspora_nearby/firebase_options.dart';
import 'package:diaspora_nearby/services/location_update_service.dart';

class BackgroundLocationService {
  static bool _isInitialized = false;

  static Future<void> initializeService() async {
    if (_isInitialized) {
      debugPrint('BackgroundLocationService: Already initialized, skipping.');
      return;
    }

    final service = FlutterBackgroundService();

    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: onStart,
        autoStart: false, 
        isForegroundMode: false, // [CRITICAL] Start as background to bypass strict OS timer
        notificationChannelId: 'foreground_service_channel',
        initialNotificationTitle: 'Diaspora Nearby',
        initialNotificationContent: 'Initializing service...',
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
  static void onStart(ServiceInstance service) {
    if (service is AndroidServiceInstance) {
      // [CRITICAL] Manual promotion: we start as background and then "request" foreground status.
      // This is allowed while the app is in the foreground (User is on Nearby page).
      service.setAsForegroundService();
      service.setForegroundNotificationInfo(
        title: 'Diaspora Nearby',
        content: 'Background location active',
      );
    }

    try {
      DartPluginRegistrant.ensureInitialized();
      WidgetsFlutterBinding.ensureInitialized();

      // Initialize Firebase (AFTER promotion attempt)
      _initFirebaseAndWork(service);
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

      // Start location updates
      Timer.periodic(const Duration(minutes: 15), (timer) async {
        try {
          if (service is AndroidServiceInstance) {
            if (await service.isForegroundService()) {
              service.setForegroundNotificationInfo(
                title: 'Diaspora Nearby',
                content: 'Updated location at ${DateTime.now()}',
              );
            }
          }

          final user = FirebaseAuth.instance.currentUser;
          if (user != null) {
            debugPrint('Background: Updating location for ${user.uid}');
            await LocationUpdateService().updateCurrentLocation(user.uid);
            
            // [NEW] Trigger proximity check after location update
            await _checkAndNotifyNearby(service, user.uid);
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

  static Future<void> _checkAndNotifyNearby(ServiceInstance service, String userId) async {
    try {
      final firestore = FirebaseFirestore.instance;
      
      // 1. Get current user data
      final userDoc = await firestore.collection('users').doc(userId).get();
      if (!userDoc.exists) return;
      
      final userData = userDoc.data()!;
      final homeCountryCode = userData['homeCountryCode'] as String?;
      if (homeCountryCode == null) return;

      // Location for distance calc
      final myLoc = userData['currentLocation'] as Map<String, dynamic>?;
      final myLat = (myLoc?['geometry']?['location']?['lat'] as num?)?.toDouble();
      final myLng = (myLoc?['geometry']?['location']?['lng'] as num?)?.toDouble();
      
      if (myLat == null || myLng == null) return;

      // 2. Query compatriots
      final snapshot = await firestore.collection('users')
          .where('homeCountryCode', isEqualTo: homeCountryCode)
          .limit(50) // Small limit for background efficiency
          .get();

      final List<Map<String, dynamic>> closeUsers = [];
      
      for (var doc in snapshot.docs) {
        if (doc.id == userId) continue;
        
        final data = doc.data();
        final theirLoc = data['currentLocation'] as Map<String, dynamic>?;
        final theirLat = (theirLoc?['geometry']?['location']?['lat'] as num?)?.toDouble();
        final theirLng = (theirLoc?['geometry']?['location']?['lng'] as num?)?.toDouble();
        
        if (theirLat != null && theirLng != null) {
          // Simplified distance calc (Haversine or similar already used in app)
          // We can use a basic calc or just a rough box check for efficiency
          // But for consistency, we should ideally use the same formula.
          // Since we can't easily import the util here without ensuring it's isolate-safe,
          // we'll use a simple approximation for 10 miles.
          
          final double distance = _calculateSimpleDistance(myLat, myLng, theirLat, theirLng);
          if (distance <= 10.0) { // 10 miles
            closeUsers.add(data);
          }
        }
      }

      if (closeUsers.isNotEmpty) {
        final first = closeUsers.first;
        final name = first['firstName'] ?? 'Someone';
        final country = first['homeCountry'] ?? 'your home country';

        debugPrint('Background: Found nearby compatriot: $name');

        // Note: For background notifications in iOS/Android, we use setForegroundNotificationInfo 
        // OR the push notification service. Here, we can trigger the native notification.
        if (service is AndroidServiceInstance) {
          service.setForegroundNotificationInfo(
            title: 'Diaspora Nearby',
            content: '$name from $country is nearby!',
          );
        }
      }
    } catch (e) {
      debugPrint('Error in background proximity check: $e');
    }
  }

  // Simple Euclidean distance approximation for small distances (miles)
  static double _calculateSimpleDistance(double lat1, double lon1, double lat2, double lon2) {
    const double milesPerDegreeLat = 69.0;
    final double milesPerDegreeLon = 69.0 * 0.96; // Approximation for mid-latitudes
    
    final double dLat = (lat2 - lat1).abs() * milesPerDegreeLat;
    final double dLon = (lon2 - lon1).abs() * milesPerDegreeLon;
    
    // sqrt(a^2 + b^2)
    return math.sqrt(dLat * dLat + dLon * dLon);
  }
}
