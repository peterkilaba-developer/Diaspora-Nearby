import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:math' as math;
import 'dart:ui';

class ProximityService {
  final FirebaseFirestore _firestore;
  final FlutterLocalNotificationsPlugin _notificationsPlugin;
  final SharedPreferences? _prefs;

  ProximityService({
    FirebaseFirestore? firestore,
    FlutterLocalNotificationsPlugin? notificationsPlugin,
    SharedPreferences? prefs,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _notificationsPlugin =
           notificationsPlugin ?? FlutterLocalNotificationsPlugin(),
       _prefs = prefs;

  Future<void> checkAndNotify(String userId) async {
    // [REFACTORED] Proximity logic has moved to Firebase Cloud Functions.
    // This method is now a no-op to avoid redundant Firestore reads and battery drain.
    // The background service still calls LocationUpdateService which triggers the Cloud Function.
    debugPrint('📍 [PROXIMITY] Local check skipped. Relying on Cloud Functions.');
  }

  // [DEPRECATED] Helper for PushNotificationService to check deduplication
  // No longer needed as server handles deduplication via proximity_history.
  Future<bool> hasRecentlyNotified(String userId) async {
    return false; 
  }
}

