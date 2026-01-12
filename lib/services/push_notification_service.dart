import 'dart:convert';
import 'package:universal_io/io.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:diaspora_nearby/router.dart';
import 'package:diaspora_nearby/features/auth/repository/auth_repository.dart';
import 'package:diaspora_nearby/features/home/repository/home_repository.dart';
import 'package:flutter/foundation.dart';

// Provider for the service
final pushNotificationServiceProvider = Provider<PushNotificationService>((ref) {
  return PushNotificationService(ref);
});

// Holds the pending route to navigate to after authentication
// Holds the pending route
class PendingNavigationNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void setRoute(String? route) => state = route;
  void clear() => state = null;
}

final pendingNavigationProvider = NotifierProvider<PendingNavigationNotifier, String?>(PendingNavigationNotifier.new);

class PushNotificationService {
  final Ref _ref;
  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  bool _isInitialized = false;

  PushNotificationService(this._ref);

  /// Initialize notifications (call once on app start)
  Future<void> initialize() async {
    if (_isInitialized) {
      debugPrint('PushNotificationService: Already initialized, skipping.');
      return;
    }
    _isInitialized = true;
    
    // 1. Initialize Local Notifications
    if (!kIsWeb) {
      await _initializeLocalNotifications();
    }

    // 3. Setup Message Handlers
    _setupMessageHandlers();
    
    // 4. Listen for token refreshes
    _fcm.onTokenRefresh.listen((newToken) {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        debugPrint('PushNotificationService: Token refresh for ${user.uid}');
        _saveTokenToFirestore(user.uid, newToken);
      }
    });

    // 5. Listen to Auth State Changes
    _ref.read(authRepositoryProvider).authStateChanges.listen((user) {
      if (user != null) {
        debugPrint('PushNotificationService: User signed in (${user.uid}), registering notifications...');
        registerForUser(user.uid);
        
        // Handle Pending Navigation
        final pendingRoute = _ref.read(pendingNavigationProvider);
        if (pendingRoute != null) {
          debugPrint('PushNotificationService: Navigating to pending route: $pendingRoute');
          _ref.read(routerProvider).push(pendingRoute);
          _ref.read(pendingNavigationProvider.notifier).clear();
        }
      } else {
        debugPrint('PushNotificationService: User signed out.');
      }
    });
    
    // 6. Check Initial User (in case stream doesn't emit immediately or we missed it)
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser != null) {
       registerForUser(currentUser.uid);
    }
  }
  
  /// Called when user logs in
  Future<void> registerForUser(String userId) async {
    // 1. Always attempt to register token (Android doesn't strictly require permission for token)
    try {
      await registerFCMToken(userId);
    } catch (e) {
      debugPrint('Error registering FCM token: $e');
    }

    // 2. Request Permission and Subscribe
    final granted = await requestPermission();
    if (granted) {
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
      final data = message.data;

      // Show local notification if notification data exists OR if it's a data-only message we recognize
      if (!kIsWeb) {
        String? title = notification?.title;
        String? body = notification?.body;

        // Fallback for Data-Only Messages
        if (title == null && body == null) {
           // Try to construct from data
           if (data['type'] == 'chat' || data['type'] == 'text' || data['type'] == 'image' || data['type'] == 'video') {
              title = data['senderName'] ?? 'New Message';
              body = data['content'] ?? data['body'] ?? 'Sent a message';
              
              // Handle media labels if content is empty
              if ((body == null || body.isEmpty) && data['type'] != 'text') {
                 if (data['type'] == 'image') body = 'Photo';
                 else if (data['type'] == 'video') body = 'Video';
              }
           } else if (data['type'] == 'dsp_transfer') {
               title = 'Diaspora Nearby';
               // Body construction logic below will handle the rest
           }
        }

        // [NEW] Intercept DSP Transfer messages to show correct text
        if (data['type'] == 'dsp_transfer') {
           title = 'Diaspora Nearby'; // Force title
           dynamic amountVal = data['amount'];
           if (amountVal == null && data['metadata'] != null) {
              if (data['metadata'] is String) {
                 try {
                   final meta = jsonDecode(data['metadata']);
                   amountVal = meta['amount'];
                 } catch (_) {}
              } else if (data['metadata'] is Map) {
                 amountVal = data['metadata']['amount'];
              }
           }
           
           if (amountVal != null) {
             final senderName = data['senderName'] ?? notification?.title ?? 'Someone';
             body = 'You received $amountVal DSP from $senderName';
           }
        }

        if (title != null && body != null) {
          try {
             _localNotifications.show(
              notification?.hashCode ?? DateTime.now().millisecond,
              title,
              body,
              const NotificationDetails(
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
          } catch (e) {
            debugPrint('Error showing foreground notification: $e');
          }
        }
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
        debugPrint('PushNotificationService: Obtained FCM token, saving to Firestore...');
        await _saveTokenToFirestore(userId, token);
      } else {
        debugPrint('PushNotificationService: FCM token was null');
      }
    } catch (e) {
      debugPrint('PushNotificationService: Failed to get FCM token: $e');
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
      
      String? targetRoute;
      if (type == 'direct_message' && data['chatId'] != null) {
        targetRoute = '/chats/${data['chatId']}';
      } else if (type == 'event_reminder' && data['eventId'] != null) {
        targetRoute = '/events/${data['eventId']}';
      } else if (type == 'money_transfer') {
        targetRoute = '/notifications';
      } else if (type == 'dsp_transfer' && data['chatId'] != null) { // [NEW]
        targetRoute = '/chats/${data['chatId']}';
      } else if (type == 'group_mention' && data['chatId'] != null) {
        targetRoute = '/chats/${data['chatId']}';
      } else if (type == 'nearby_compatriot' && data['userId'] != null) {
        targetRoute = '/profile/${data['userId']}';
      } else {
        targetRoute = '/notifications';
      }

      if (targetRoute != null) {
        final currentUser = _ref.read(authRepositoryProvider).currentUser;
        if (currentUser == null) {
           debugPrint('PushNotificationService: User not logged in, queueing route: $targetRoute');
           _ref.read(pendingNavigationProvider.notifier).setRoute(targetRoute);
           // We might also want to ensure we are on auth screen, but Router redirect handles that.
        } else {
           router.push(targetRoute);
        }
      }
    } catch (e) {
      debugPrint('Error parsing notification payload: $e');
    }
  }
  
  String _encodePayload(Map<String, dynamic> data) {
    return jsonEncode(data);
  }

  /// Check for nearby compatriots and notify if any
  Future<void> checkAndNotifyNearbyCompatriots() async {
    try {
      final homeRepo = _ref.read(homeRepositoryProvider);
      final nearbyCompatriots = await homeRepo.getNearbyCompatriots();
      
      if (nearbyCompatriots.isNotEmpty) {
        // Filter for users strictly within 999 miles for notification
        final closeCompatriots = nearbyCompatriots.where((u) => (u.distance ?? 999999) <= 999).toList();
        
        if (closeCompatriots.isNotEmpty && !kIsWeb) {
          final compatriot = closeCompatriots.first;
          final name = compatriot.firstName;
          final homeCountry = compatriot.homeCountry ?? 'your home country';
          
          // Show local notification with safety guard
          try {
            await _localNotifications.show(
              compatriot.uid.hashCode,
              'Diaspora Nearby',
              '$name from $homeCountry is nearby. Connect now!',
              const NotificationDetails(
                android: AndroidNotificationDetails(
                  'high_importance_channel',
                  'High Importance Notifications',
                  icon: '@mipmap/ic_launcher',
                  largeIcon: const DrawableResourceAndroidBitmap('ic_launcher_foreground'),
                  priority: Priority.high,
                  importance: Importance.max,
                ),
              ),
              payload: _encodePayload({
                'type': 'nearby_compatriot',
                'userId': compatriot.uid,
              }),
            );
          } catch (e) {
            debugPrint('Error showing nearby compatriot notification: $e');
          }
        }
      }
    } catch (e) {
      debugPrint('Error checking nearby compatriots: $e');
    }
  }
}
