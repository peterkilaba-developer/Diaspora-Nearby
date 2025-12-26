import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:diaspora_nearby/router.dart';

// Provider for the service
final pushNotificationServiceProvider = Provider<PushNotificationService>((ref) {
  return PushNotificationService(ref);
});

class PushNotificationService {
  final Ref _ref;
  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  PushNotificationService(this._ref);

  /// Initialize notifications (call once on app start)
  Future<void> initialize() async {
    // 1. Initialize Local Notifications
    await _initializeLocalNotifications();

    // 3. Setup Message Handlers
    _setupMessageHandlers();
    
    // 4. Listen for token refreshes
    _fcm.onTokenRefresh.listen((newToken) {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        _saveTokenToFirestore(user.uid, newToken);
      }
    });
  }
  
  /// Called when user logs in
  Future<void> registerForUser(String userId) async {
    final granted = await requestPermission();
    if (granted) {
      await registerFCMToken(userId);
      await subscribeToTopics(userId);
    }
  }

  /// Request notification permission
  Future<bool> requestPermission() async {
    final settings = await _fcm.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );
    
    return settings.authorizationStatus == AuthorizationStatus.authorized;
  }

  /// Initialize local notifications for foreground display
  Future<void> _initializeLocalNotifications() async {
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false, 
      requestBadgePermission: false, 
      requestSoundPermission: false,
    );

    const settings = InitializationSettings(android: androidSettings, iOS: iosSettings);

    await _localNotifications.initialize(
      settings,
      onDidReceiveNotificationResponse: (response) {
        _handleNotificationTap(response.payload);
      },
    );
    
    // Create channel for Android
    if (Platform.isAndroid) {
      final channel = const AndroidNotificationChannel(
        'high_importance_channel', // id
        'High Importance Notifications', // title
        description: 'This channel is used for important notifications.', // description
        importance: Importance.max,
      );
      
      await _localNotifications
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(channel);
    }
  }

  /// Setup FCM message handlers
  void _setupMessageHandlers() {
    // Keep track of recently processed message IDs to prevent duplicates
    final Set<String> processedMessageIds = {};

    // Foreground Message
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      final messageId = message.messageId;
      if (messageId != null) {
        if (processedMessageIds.contains(messageId)) {
          return;
        }
        processedMessageIds.add(messageId);
        // Keep set size manageable
        if (processedMessageIds.length > 20) processedMessageIds.clear();
      }

      final notification = message.notification;
      final android = message.notification?.android;

      // Show local notification if notification data exists
      if (notification != null && android != null) {
        _localNotifications.show(
          notification.hashCode,
          notification.title,
          notification.body,
          NotificationDetails(
            android: AndroidNotificationDetails(
              'high_importance_channel',
              'High Importance Notifications',
              icon: '@mipmap/ic_launcher',
              priority: Priority.high,
              importance: Importance.max,
            ),
          ),
          payload: _encodePayload(message.data),
        );
      }
    });

    // Message Opened App (Background -> Foreground)
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      _handleNotificationTap(_encodePayload(message.data));
    });
    
    // Initial Message (Terminated -> Foreground)
    _fcm.getInitialMessage().then((RemoteMessage? message) {
      if (message != null) {
        _handleNotificationTap(_encodePayload(message.data));
      }
    });
  }

  /// Register FCM token and save to Firestore
  Future<void> registerFCMToken(String userId) async {
    try {
      final token = await _fcm.getToken();
      if (token != null) {
        await _saveTokenToFirestore(userId, token);
      }
    } catch (e) {
      // Failed to get token
    }
  }

  /// Save token to Firestore
  Future<void> _saveTokenToFirestore(String userId, String token) async {
    await _firestore.collection('users').doc(userId).update({
      'fcmToken': token,
      'fcmTokenUpdatedAt': FieldValue.serverTimestamp(),
      'notificationsEnabled': true,
    });
  }

  /// Subscribe to relevant topics
  Future<void> subscribeToTopics(String userId) async {
    try {
      final userDoc = await _firestore.collection('users').doc(userId).get();
      if (!userDoc.exists) return;
      
      final data = userDoc.data()!;
      final topics = <String>['all_users'];
      
      // Home Country Topic
      if (data['homeCountryCode'] != null) {
        final countryCode = data['homeCountryCode'].toString().toLowerCase();
        topics.add('country_$countryCode');
      }
      
      // Host City Topic
      if (data['hostCity'] != null) {
        final city = data['hostCity'].toString().toLowerCase()
            .replaceAll(RegExp(r'\s+'), '_')
            .replaceAll(RegExp(r'[^a-z0-9_]'), '');
        topics.add('city_$city');
      }
      
      // Save topics to Firestore
      await _firestore.collection('users').doc(userId).update({
        'fcmTopics': topics,
        'fcmTopicsUpdatedAt': FieldValue.serverTimestamp(),
      });
      
      // Also subscribe via FCM SDK for client-side messaging optimization
      for (final topic in topics) {
         await _fcm.subscribeToTopic(topic);
      }
      
    } catch (e) {
      // Error subscribing to topics
    }
  }
  
  /// Disable notifications
  Future<void> disableNotifications(String userId) async {
    try {
      await _fcm.deleteToken();
      
      await _firestore.collection('users').doc(userId).update({
        'fcmToken': null,
        'notificationsEnabled': false,
        'fcmTokenUpdatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      // Error disabling notifications
    }
  }
  
  /// Handle Notification Payload for Navigation
  void _handleNotificationTap(String? payload) {
    if (payload == null) return;
    
    try {
      final data = jsonDecode(payload) as Map<String, dynamic>;
      final type = data['type'];
      final router = _ref.read(routerProvider);
      
      if (type == 'direct_message' && data['chatId'] != null) {
        router.push('/chats/${data['chatId']}');
      } else if (type == 'event_reminder' && data['eventId'] != null) {
        router.push('/events/${data['eventId']}');
      } else if (type == 'money_transfer') {
        router.push('/notifications');
      } else if (type == 'group_mention' && data['chatId'] != null) {
         router.push('/chats/${data['chatId']}');
      } else {
         router.push('/notifications');
      }
    } catch (e) {
      // Error parsing notification payload
    }
  }
  
  String _encodePayload(Map<String, dynamic> data) {
    return jsonEncode(data);
  }
}
