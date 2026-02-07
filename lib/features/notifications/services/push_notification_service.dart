import 'dart:convert';
import 'dart:async';
import 'package:universal_io/io.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_database/firebase_database.dart'; // [NEW]
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:diaspora_nearby/router.dart';
import 'package:diaspora_nearby/features/auth/repository/auth_repository.dart';
import 'package:diaspora_nearby/features/home/repository/home_repository.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http; // [NEW]
import 'package:path_provider/path_provider.dart'; // [NEW]
// Provider for the service
final pushNotificationServiceProvider = Provider<PushNotificationService>((
  ref,
) {
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

final pendingNavigationProvider =
    NotifierProvider<PendingNavigationNotifier, String?>(
      PendingNavigationNotifier.new,
    );

class PushNotificationService {
  final Ref _ref;
  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  bool _isInitialized = false;
  StreamSubscription<QuerySnapshot>?
  _relationshipSubscription; // [NEW] Listener for requests
  
  // [NEW] Track processed messages for client-side listener too
  final Set<String> _processedMessageIds = {};

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
        debugPrint(
          'PushNotificationService: User signed in (${user.uid}), registering notifications...',
        );
        registerForUser(user.uid);

        // Handle Pending Navigation
        final pendingRoute = _ref.read(pendingNavigationProvider);
        if (pendingRoute != null) {
          debugPrint(
            'PushNotificationService: Navigating to pending route: $pendingRoute',
          );
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

  /// Start listening to user chats for local notifications regarding incoming messages
  /// (Fallback for when Backend doesn't send FCM)
  void _startUserChatsListener(String userId) {
    _processUserChatUpdateSubs?.cancel();
    _processUserChatAddedSubs?.cancel();

    debugPrint('🔔 [DISABLED] RTDB UserChats Listener for $userId (Using Server FCM)');
    /*
    final userChatsRef = FirebaseDatabase.instance.ref('userChats/$userId');

    _processUserChatUpdateSubs = userChatsRef.onChildChanged.listen((event) {
      if (event.snapshot.value != null) {
        _processUserChatUpdate(
          event.snapshot.value as Map,
          userId,
          event.snapshot.key!,
        );
      }
    });

    _processUserChatAddedSubs = userChatsRef.onChildAdded.listen((event) {
      if (event.snapshot.value != null) {
        _processUserChatUpdate(
          event.snapshot.value as Map,
          userId,
          event.snapshot.key!,
        );
      }
    });
    */
  }

  StreamSubscription? _processUserChatUpdateSubs;
  StreamSubscription? _processUserChatAddedSubs;

  Future<void> _processUserChatUpdate(
    Map data,
    String userId,
    String chatId,
  ) async {
    try {
      final lastMessage = data['lastMessage'];
      if (lastMessage == null || lastMessage is! Map) return;

      final senderId = lastMessage['senderId'];
      final type = lastMessage['type'];
      final content = lastMessage['content'];
      final timestamp = lastMessage['timestamp'] as int?;

      // 1. Ignore own messages
      if (senderId == userId) return;

      // 2. Ignore old messages (older than 30 seconds) used during initial sync
      if (timestamp != null) {
        final diff = DateTime.now().millisecondsSinceEpoch - timestamp;
        if (diff > 30000) return;
      }

      // 3. Deduplicate against FCM messages (if any)
      final messageId = lastMessage['id']?.toString() ?? '${timestamp}_$senderId';
      if (_processedMessageIds.contains(messageId)) {
        debugPrint('Skipping duplicate notification for $messageId');
        return;
      }
      _processedMessageIds.add(messageId);
      if (_processedMessageIds.length > 50) _processedMessageIds.clear();

      String title = (lastMessage['senderName']?.toString().trim().isNotEmpty ?? false) 
          ? lastMessage['senderName'] 
          : 'New Message';
      String body = (content?.toString().trim().isNotEmpty ?? false) 
          ? content 
          : 'Sent a message';
      String? imageUrl;

      // [FIX] Safety net: If type is missing but content indicates location
      if (type == null && content != null && content.toString().startsWith('📍')) {
        body = '📍 Location message';
      }

      // [STANDARDIZED TEXT MAPPING] - Matches ChatCard/Modal Icons
      // LucideIcons.image -> 📷
      // LucideIcons.video -> 🎥
      // LucideIcons.mic -> 🎤
      // LucideIcons.music -> 🎵
      // LucideIcons.fileText -> 📄
      // LucideIcons.mapPin -> 📍
      // LucideIcons.coins -> 🪙
      if (type != null) {
        switch (type) {
          case 'audio':
            body = '🎤 Voice message';
            break;
          case 'audio_file':
            body = '🎵 Audio message';
            break;
          case 'image':
            body = '📷 Photo message';
            imageUrl = lastMessage['imageUrl']; 
            break;
          case 'video':
            body = '🎥 Video message';
            break;
          case 'location':
            body = '📍 Location message';
            break;
          case 'document':
            body = '📄 Document message';
            break;
          case 'dsp_transfer':
          case 'points_update':
            // [REMOVED] Skip local notification for DSP transfers and automated rewards
            // Cloud Function onPointsTransactionCreated handles this to prevent duplicates
            // Simply skip showing notification and return early
            debugPrint('🔕 [PushNotificationService] Skipping DSP transfer/reward notification (handled by backend or silenced)');
            return;
             case 'money-transfer':
            body = '💵 Money transfer';
            break;
          case 'group_invitation':
             // handled by type check or fallback
             break;
        }
      }

      if (type == 'group_invitation') {
         body = content ?? 'You have a new group invitation';
      }

      await _showRichNotification(
        id: messageId.hashCode,
        title: title,
        body: body,
        payload: jsonEncode({
          'type': type ?? 'chat',
          'chatId': data['chatId'] ?? chatId, // Use passed chatId
          'senderId': senderId,
        }),
        imageUrl: imageUrl, 
      );

    } catch (e) {
      debugPrint('Error processing user chat update: $e');
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

    // 4. Start listening for Relationship Requests
    _listenForRelationshipRequests(userId);

    // 5. Start listening for User Chats changes (Local Notification trigger)
    _startUserChatsListener(userId);
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
    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    const settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

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
        description:
            'This channel is used for important notifications.', // description
        importance: Importance.max,
      );

      await _localNotifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(channel);
    }
  }

  /// Disable notifications
  Future<void> disableNotifications(String userId) async {
    try {
      await _fcm.deleteToken();
      _relationshipSubscription?.cancel();
      _processUserChatUpdateSubs?.cancel();
      _processUserChatAddedSubs?.cancel();

      await _firestore.collection('users').doc(userId).update({
        'fcmToken': null,
        'notificationsEnabled': false,
        'fcmTokenUpdatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      // Error disabling notifications
    }
  }

  /// Setup FCM message handlers
  void _setupMessageHandlers() {
    // Foreground Message
    FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
      final messageId = message.messageId;
      final data = message.data;

      // [FIX] Deduplicate using internal ID if available, otherwise FCM ID
      final internalId = data['id']?.toString() ?? data['messageId']?.toString();
      final effectiveId = internalId ?? messageId;

      if (effectiveId != null) {
        // [FIX] Deduplicate ONLY if it's a rich message (has type). 
        // If type is missing (generic), we DO NOT mark as processed so that the RTDB listener
        // (which has better data) can pick it up and "upgrade" the notification.
        if (data['type'] != null && _processedMessageIds.contains(effectiveId)) {
          return;
        }
        
        // Only block future notifications if this one is rich enough
        if (data['type'] != null) {
          _processedMessageIds.add(effectiveId);
          if (_processedMessageIds.length > 50) _processedMessageIds.clear();
        }
      }

      final notification = message.notification;
      // final android = message.notification?.android; // Unused
      
      // Show local notification if notification data exists OR if it's a data-only message we recognize
      if (!kIsWeb) {
        String? title = notification?.title;
        String? body = notification?.body;
        String? imageUrl = notification
            ?.android
            ?.imageUrl; // Try getting from notification payload first

        // [FIX] Centralized logic to match ChatCard display exactly
        String? msgType = data['type'];
        String msgContent = (data['content'] ?? data['body'] ?? '') as String;

        // Apply strict formatting based on message type
        if (msgType != null) {
          switch (msgType) {
            case 'audio':
              body = '🎤 sent a voice message';
              break;
            case 'audio_file':
              body = '🎵 sent an audio file';
              break;
            case 'image':
              body = '📷 Photo message';
              imageUrl ??= data['imageUrl'];
              break;
            case 'video':
              body = '🎥 Video message';
              break;
            case 'location':
              body = '📍 sent a location';
              break;
            case 'document':
              body = '📄 sent a document';
              break;
            case 'dsp_transfer':
            case 'points_update':
              // [REMOVED] Skip local notification for DSP transfers and rewards
              // Cloud Function onPointsTransactionCreated handles this to prevent duplicates
              debugPrint('🔕 [PushNotificationService] Skipping DSP transfer/reward foreground notification (handled by backend or silenced)');
              return;
            case 'money-transfer':
              body = '💵 Money transfer';
              break;
          }
        }

        // Fallback for Data-Only Messages or Text/Chat Types
        if (title?.trim().isEmpty ?? true) {
          title = data['senderName']?.toString().trim().isNotEmpty == true 
              ? data['senderName'] 
              : 'New Message';
        }
        
        if (body?.trim().isEmpty ?? true) {
          body = msgContent.trim().isNotEmpty 
              ? msgContent 
              : 'Sent a message';
        }

      
        // [NEW] Intercept Relationship Request messages
        // (Kept separate as it was not in the modification request list)
        if (data['type'] == 'relationship_request') {
          title = 'New Relationship Request';
          final fromName = data['fromUserName'] ?? 'Someone';
          final relType = data['relationshipType'] ?? 'relative';
          body = '$fromName wants to add you as their $relType';
        }

        // [NEW] Handle Group Invitations (Migrated from RTDB listener)
        if (data['type'] == 'group_invitation') {
          title = data['senderName'] ?? 'Someone';
          body = data['content'] ?? data['body'] ?? 'You have a new group invitation';
          // Use specific method to match original behavior or just let it fall through if payload matches
          // We can just set title/body here and let the fallthrough handle it, 
          // BUT we need to ensure payload is correct for navigation. 
          // The fallthrough uses `_encodePayload(message.data)`.
          // If message.data has 'chatId', it works.
        }


        if (title != null && body != null) {
          _showRichNotification(
            id: notification?.hashCode ?? DateTime.now().millisecond,
            title: title,
            body: body,
            payload: _encodePayload(message.data),
            imageUrl: imageUrl,
          );
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
        debugPrint(
          'PushNotificationService: Obtained FCM token, saving to Firestore...',
        );
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
        final city = data['hostCity']
            .toString()
            .toLowerCase()
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



  /// Handle Notification Payload for Navigation
  void _handleNotificationTap(String? payload) {
    if (payload == null) return;

    try {
      final data = jsonDecode(payload) as Map<String, dynamic>;
      final type = data['type'];
      final router = _ref.read(routerProvider);

      String? targetRoute;
      if ((type == 'direct_message' ||
              type == 'chat_message' ||
              type == 'group_mention' ||
              type == 'dsp_transfer') &&
          data['chatId'] != null) {
        targetRoute = '/chats/${data['chatId']}';
      } else if (type == 'event_reminder' && data['eventId'] != null) {
        targetRoute = '/events/${data['eventId']}';
      } else if (type == 'money_transfer' ||
          type == 'money-transfer' ||
          type == 'points_update') {
        targetRoute = '/dsp/points';
      } else if (type == 'nearby_compatriot' && data['userId'] != null) {
        targetRoute = '/profile/${data['userId']}';
      } else if (type == 'relationship_request' && data['fromUserId'] != null) {
        // [NEW] Open Sender's profile with query params to trigger dialog
        targetRoute =
            '/profile/${data['fromUserId']}?requestId=${data['requestId'] ?? ''}&action=review';
      } else if (type == 'group_invitation' && data['chatId'] != null) {
        targetRoute = '/chats/${data['chatId']}/info';
      } else {
        targetRoute = '/notifications';
      }

      final currentUser = _ref.read(authRepositoryProvider).currentUser;
      if (currentUser == null) {
        debugPrint(
          'PushNotificationService: User not logged in, queueing route: $targetRoute',
        );
        _ref.read(pendingNavigationProvider.notifier).setRoute(targetRoute);
        // We might also want to ensure we are on auth screen, but Router redirect handles that.
      } else {
        router.push(targetRoute);
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
        final closeCompatriots = nearbyCompatriots
            .where((u) => (u.distance ?? 999999) <= 999)
            .toList();

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
                  largeIcon: DrawableResourceAndroidBitmap(
                    'ic_launcher_foreground',
                  ),
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

  /// [NEW] Listen for incoming relationship requests and trigger local notification
  void _listenForRelationshipRequests(String userId) {
    debugPrint(
      '🔔 [PushNotificationService] Starting relationship request listener for user: $userId',
    );
    _relationshipSubscription?.cancel();

    _relationshipSubscription = _firestore
        .collection('relationship_requests')
        .where('toUserId', isEqualTo: userId)
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .listen(
          (snapshot) {
            debugPrint(
              '🔔 [PushNotificationService] Relationship Listener Update:',
            );
            debugPrint('   - Listening for toUserId: $userId');
            debugPrint('   - Snapshot docs count: ${snapshot.docs.length}');
            debugPrint('   - DocChanges count: ${snapshot.docChanges.length}');

            for (final change in snapshot.docChanges) {
              if (change.type == DocumentChangeType.added) {
                final data = change.doc.data();
                if (data != null) {
                  debugPrint(
                    '🔔 [PushNotificationService] New relationship request detected: ${change.doc.id}',
                  );
                  // Ensure it's a new request by checking timestamp if needed,
                  // but 'added' to a 'pending' query usually means new or initial load.
                  // To avoid notifying on initial load of old pending requests,
                  // we can check if the timestamp is very recent (e.g. last 1 minute),
                  // OR just rely on the fact that the user might want to know about pending requests they missed.
                  // Let's notify.

                  final fromName = data['fromUserName'] ?? 'Someone';
                  final relType = data['relationshipType'] ?? 'relative';
                  final requestId = change.doc.id;
                  final fromUserId = data['fromUserId'];

                  _showRelationshipNotification(
                    fromName,
                    relType,
                    fromUserId,
                    requestId,
                  );
                }
              }
            }
          },
          onError: (e) {
            debugPrint(
              '❌ [PushNotificationService] Error in relationship listener: $e',
            );
          },
        );
  }

  Future<void> _showRelationshipNotification(
    String fromName,
    String relType,
    String? fromUserId,
    String requestId,
  ) async {
    debugPrint(
      '🔔 [PushNotificationService] Showing local notification for request: $requestId',
    );
    const androidDetails = AndroidNotificationDetails(
      'high_importance_channel',
      'High Importance Notifications',
      importance: Importance.max,
      priority: Priority.high,
    );
    const details = NotificationDetails(android: androidDetails);

    await _localNotifications.show(
      requestId.hashCode,
      'New Relationship Request',
      '$fromName wants to add you as their $relType',
      details,
      payload: jsonEncode({
        'type': 'relationship_request',
        'fromUserId': fromUserId,
        'requestId': requestId,
        'action': 'review',
      }),
    );
  }

  // [NEW] Helper to show nice notifications with optional image
  Future<void> _showRichNotification({
    required int id,
    required String title,
    required String body,
    required String payload,
    String? imageUrl,
  }) async {
    try {
      BigPictureStyleInformation? bigPictureStyleInformation;

      if (imageUrl != null) {
        try {
          final String largeIconPath = await _downloadAndSaveFile(
            imageUrl,
            'largeIcon',
          );
          final String bigPicturePath = await _downloadAndSaveFile(
            imageUrl,
            'bigPicture',
          );

          bigPictureStyleInformation = BigPictureStyleInformation(
            FilePathAndroidBitmap(bigPicturePath),
            largeIcon: FilePathAndroidBitmap(largeIconPath),
            contentTitle: title,
            htmlFormatContentTitle: true,
            summaryText: body,
            htmlFormatSummaryText: true,
          );
        } catch (e) {
          debugPrint('Error downloading notification image: $e');
          // Fallback to no image
        }
      }

      final AndroidNotificationDetails androidPlatformChannelSpecifics =
          AndroidNotificationDetails(
            'high_importance_channel',
            'High Importance Notifications',
            importance: Importance.max,
            priority: Priority.high,
            styleInformation: bigPictureStyleInformation,
          );

      final NotificationDetails platformChannelSpecifics = NotificationDetails(
        android: androidPlatformChannelSpecifics,
        iOS:
            const DarwinNotificationDetails(), // iOS handles images via service extension usually
      );

      await _localNotifications.show(
        id,
        title,
        body,
        platformChannelSpecifics,
        payload: payload,
      );
    } catch (e) {
      debugPrint('Error showing rich notification: $e');
    }
  }

  Future<String> _downloadAndSaveFile(String url, String fileName) async {
    final Directory directory = await getApplicationDocumentsDirectory();
    final String filePath = '${directory.path}/$fileName';
    final http.Response response = await http.get(Uri.parse(url));
    final File file = File(filePath);
    await file.writeAsBytes(response.bodyBytes);
    return filePath;
  }
}
