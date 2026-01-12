import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart'; // [NEW]
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:math' as math;
import 'dart:ui'; 


class ProximityService {
  final FirebaseFirestore _firestore;
  final FirebaseDatabase _rtdb; // [NEW]
  final FlutterLocalNotificationsPlugin _notificationsPlugin;
  final SharedPreferences? _prefs;

  ProximityService({
    FirebaseFirestore? firestore,
    FirebaseDatabase? rtdb, // [NEW]
    FlutterLocalNotificationsPlugin? notificationsPlugin,
    SharedPreferences? prefs,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _rtdb = rtdb ?? FirebaseDatabase.instance, // [NEW]
        _notificationsPlugin = notificationsPlugin ?? FlutterLocalNotificationsPlugin(),
        _prefs = prefs;

  Future<void> checkAndNotify(String userId) async {
    // [USER REQUEST] Re-enabled proximity checks
    try {
      // 0. Cooldown Check
      final prefs = _prefs ?? await SharedPreferences.getInstance();
      const kLastNotificationKey = 'last_proximity_notification_time';
      final lastTimeMs = prefs.getInt(kLastNotificationKey) ?? 0;
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final diff = nowMs - lastTimeMs;

      // [UPDATED] Cooldown strictly set to 30 minutes to prevent spamming the user
      // Even if background service runs often, we don't want to notify about the same people constantly.
      if (diff < 30 * 60 * 1000) { 
        debugPrint('📍 [PROXIMITY] Check skipped due to cooldown (${(diff / 60000).toStringAsFixed(1)} min elapsed).');
        return; 
      }
      
      debugPrint('📍 [PROXIMITY] Starting check for $userId...');

      // 1. Get current user data
      final userDoc = await _firestore.collection('users').doc(userId).get();
      if (!userDoc.exists) return;

      final userData = userDoc.data();
      if (userData == null) return;
      
      final homeCountryCode = userData['homeCountryCode'] as String?;
      if (homeCountryCode == null) return;

      // Location for distance calc
      final myLoc = userData['currentLocation'] as Map<String, dynamic>?;
      final myLat = (myLoc?['geometry']?['location']?['lat'] as num?)?.toDouble();
      final myLng = (myLoc?['geometry']?['location']?['lng'] as num?)?.toDouble();

      if (myLat == null || myLng == null) return;

      // 2. Query compatriots
      final snapshot = await _firestore.collection('users')
          .where('homeCountryCode', isEqualTo: homeCountryCode)
          .limit(50) 
          .get();

      debugPrint('📍 [PROXIMITY] Found ${snapshot.docs.length} users with homeCountryCode: $homeCountryCode');

      final List<Map<String, dynamic>> closeUsers = [];

      for (var doc in snapshot.docs) {
        if (doc.id == userId) continue;

        final data = doc.data();
        final theirLoc = data['currentLocation'] as Map<String, dynamic>?;
        final theirLat = (theirLoc?['geometry']?['location']?['lat'] as num?)?.toDouble();
        final theirLng = (theirLoc?['geometry']?['location']?['lng'] as num?)?.toDouble();

        if (theirLat != null && theirLng != null) {
          final double distance = _calculateSimpleDistance(myLat, myLng, theirLat, theirLng);
          debugPrint('📍 [PROXIMITY] Checking user ${data['firstName']}: Distance = ${distance.toStringAsFixed(2)} miles');
          
          // [UPDATED] Radius increased to 999 miles
          if (distance <= 999.0) { 
             // [DEBUG] Disabling Chat History check for now to ensure detection works
             // final hasChat = await _hasChatHistory(userId, doc.id);
             // if (hasChat) {
             //    debugPrint('📍 [PROXIMITY] Skipping ${data['firstName']} (Chat history exists)');
             //    continue;
             // }
             
             closeUsers.add(data);
          }
        }
      }

      if (closeUsers.isNotEmpty) {
        final first = closeUsers.first;
        final name = first['firstName'] ?? 'Someone';
        final country = first['homeCountry'] ?? 'your home country';

        debugPrint('Proximity: Found new nearby compatriot: $name');

        // Create Channel to ensure it exists
        const AndroidNotificationChannel channel = AndroidNotificationChannel(
          'high_importance_channel',
          'High Importance Notifications',
          description: 'This channel is used for important notifications.',
          importance: Importance.max,
        );

        await _notificationsPlugin
            .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
            ?.createNotificationChannel(channel);

        // Active Notification
        const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
          'high_importance_channel', 
          'High Importance Notifications',
          channelDescription: 'This channel is used for important notifications.',
          importance: Importance.max,
          priority: Priority.high,
          ticker: 'Compatriot Nearby',
          color: Color(0xFF4CAF50),
          // [FIX] Removed largeIcon
        );

        const NotificationDetails details = NotificationDetails(android: androidDetails);

        await _notificationsPlugin.show(
          777,
          'Diaspora Nearby',
          '$name from $country is nearby. Connect now!',
          details,
          payload: jsonEncode({
            'type': 'nearby_compatriot',
            'userId': first['uid'] ?? first['id'] ?? '', 
          }),
        );

        // Update Cooldown
        await prefs.setInt(kLastNotificationKey, nowMs);
      }
    } catch (e) {
      debugPrint('Error in proximity check: $e');
    }
  }

  // [NEW] Helper to check RTDB for chat history
  Future<bool> _hasChatHistory(String myId, String otherId) async {
    try {
      // 1. Get my chats
      final myChatsSnapshot = await _rtdb.ref('userChats/$myId').get();
      if (!myChatsSnapshot.exists) return false;

      final myChats = myChatsSnapshot.value as Map;
      
      // 2. Iterate and check participants
      for (final chatId in myChats.keys) {
         final chatSnapshot = await _rtdb.ref('chats/$chatId').get();
         if (chatSnapshot.exists) {
            final chatData = chatSnapshot.value as Map;
            final participants = chatData['participants'];
            
            // Check if both users are participants
            if (participants is List) {
               if (participants.contains(myId) && participants.contains(otherId)) {
                  // Define myChatMeta correctly within scope
                  final myChatMeta = myChats[chatId];
                  
                  // Only block if messages have actually been sent (lastMessage exists)
                  if (myChatMeta is Map && myChatMeta['lastMessage'] != null) {
                      return true;
                  }
                  
                  // If chat exists but no messages, allow notification
                  return false;
               }
            }
         }
      }
    } catch (e) {
       debugPrint('Error checking chat history: $e');
    }
    return false;
  }

  // Simple Euclidean distance approximation for small distances (miles)
  double _calculateSimpleDistance(double lat1, double lon1, double lat2, double lon2) {
    const double milesPerDegreeLat = 69.0;
    final double milesPerDegreeLon = 69.0 * 0.96; // Approximation for mid-latitudes

    final double dLat = (lat2 - lat1).abs() * milesPerDegreeLat;
    final double dLon = (lon2 - lon1).abs() * milesPerDegreeLon;

    // sqrt(a^2 + b^2)
    return math.sqrt(dLat * dLat + dLon * dLon);
  }
}
