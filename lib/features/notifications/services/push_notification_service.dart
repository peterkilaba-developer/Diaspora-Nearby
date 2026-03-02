import 'dart:convert';
import 'dart:async';
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
import 'package:http/http.dart' as http; // [NEW]
import 'package:path_provider/path_provider.dart'; // [NEW]
import 'package:diaspora_nearby/features/notifications/models/notification_item.dart';
import 'package:diaspora_nearby/features/notifications/repository/notifications_repository.dart';

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
  StreamSubscription<QuerySnapshot>?
  _acceptedSentRequestsSubscription; // [NEW] Listener for accepted sent requests
  StreamSubscription<QuerySnapshot>?
  _proxyRequestSubscription; // [NEW] Listener for proxy requests
  StreamSubscription<QuerySnapshot>?
  _hostingInterestSubscription; // Listener for hosting interest
  StreamSubscription<QuerySnapshot>?
  _hostingSelectionSubscription; // Listener for host selection
  StreamSubscription<QuerySnapshot>?
  _sessionStatusSubscription; // Listener for session status changes

  // [NEW] Track processed messages for client-side listener too
  final Set<String> _processedMessageIds = {};

  PushNotificationService(this._ref);

  /// The currently authenticated user's ID (or null).
  String? get _activeUserId =>
      _ref.read(authRepositoryProvider).currentUser?.uid;

  /// Persist a notification to Firestore so it appears in the Notifications hub.
  Future<void> _persistNotification({
    required NotificationType type,
    required String title,
    required String body,
    Map<String, dynamic> payload = const {},
    bool actionRequired = false,
    String? dedupKey,
  }) async {
    final userId = _activeUserId;
    if (userId == null) return;

    final item = NotificationItem(
      id: '', // Firestore auto-generates
      type: type,
      title: title,
      body: body,
      payload: payload,
      actionRequired: actionRequired,
      createdAt: DateTime.now(),
    );

    final repo = _ref.read(notificationsRepositoryProvider);

    if (dedupKey != null) {
      await repo.addIfNotDuplicate(
        userId: userId,
        dedupKey: dedupKey,
        item: item,
      );
    } else {
      await repo.addNotification(userId, item);
    }
  }

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

    // [MIGRATED] RTDB listener removed - using Server FCM for push notifications
    debugPrint(
      'PushNotificationService: UserChats listener disabled (Using Server FCM)',
    );
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
      final messageId =
          lastMessage['id']?.toString() ?? '${timestamp}_$senderId';
      if (_processedMessageIds.contains(messageId)) {
        debugPrint('Skipping duplicate notification for $messageId');
        return;
      }
      _processedMessageIds.add(messageId);
      if (_processedMessageIds.length > 50) _processedMessageIds.clear();

      String title =
          (lastMessage['senderName']?.toString().trim().isNotEmpty ?? false)
          ? lastMessage['senderName']
          : 'New Message';
      String body = (content?.toString().trim().isNotEmpty ?? false)
          ? content
          : 'Sent a message';
      String? imageUrl;

      // [FIX] Safety net: If type is missing but content indicates location
      if (type == null &&
          content != null &&
          content.toString().startsWith('Location')) {
        body = 'Location message';
      }

      // [STANDARDIZED TEXT MAPPING] - Matches ChatCard/Modal Icons
      // LucideIcons.image -> Photo
      // LucideIcons.video -> Video
      // LucideIcons.mic -> Voice
      // LucideIcons.music -> Audio
      // LucideIcons.fileText -> Doc
      // LucideIcons.mapPin -> Location
      // LucideIcons.coins -> Transfer
      if (type != null) {
        switch (type) {
          case 'audio':
            body = 'Voice message';
            break;
          case 'audio_file':
            body = 'Audio message';
            break;
          case 'image':
            body = 'Photo message';
            imageUrl = lastMessage['imageUrl'];
            break;
          case 'video':
            body = 'Video message';
            break;
          case 'location':
            body = 'Location message';
            break;
          case 'document':
            body = 'Document message';
            break;
          case 'dsp_transfer':
          case 'points_update':
            // [REMOVED] Skip local notification for DSP transfers and automated rewards
            // Cloud Function onPointsTransactionCreated handles this to prevent duplicates
            // Simply skip showing notification and return early
            debugPrint(
              '🔕 [PushNotificationService] Skipping DSP transfer/reward notification (handled by backend or silenced)',
            );
            return;
          case 'money-transfer':
            body = 'Money transfer';
            break;
          case 'system':
            // Check for hosting request system messages
            final metadata = lastMessage['metadata'];
            if (metadata is Map) {
              final systemType = metadata['systemType'];
              if (systemType == 'hosting_request') {
                final travelerName = metadata['travelerName'] ?? 'A traveler';
                final communityName = metadata['communityName'] ?? 'your community';
                title = 'Hosting Request';
                body = '$travelerName is looking for a host in $communityName. Tap to view.';
              } else if (systemType == 'hosting_arrangement') {
                title = 'Hosting Confirmed';
                body = content ?? 'A hosting arrangement has been made.';
              }
            }
            break;
          case 'group_invitation':
            // handled by type check or fallback
            break;
        }
      }

      if (type == 'group_invitation') {
        body = content ?? 'You have a new group invitation';
      }

      // Check if chat is muted before showing notification
      final isMuted = await _isChatMuted(userId, data['chatId'] ?? chatId);
      if (isMuted) {
        debugPrint(
          '🔕 [PushNotificationService] Skipping notification for muted chat: $chatId',
        );
        return;
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

    // 5. [NEW] Start listening for accepted sent requests (to notify sender)
    _listenForAcceptedSentRequests(userId);

    // 6. [NEW] Start listening for proxy requests
    _listenForProxyRequests(userId);

    // 7. Start listening for hosting interest notifications
    _listenForHostingInterest(userId);

    // 8. [NEW] Start listening for host selection notifications
    _listenForHostSelection(userId);

    // 9. [NEW] Start listening for session status changes
    _listenForSessionStatusChanges(userId);

    // 10. Start listening for User Chats changes (Local Notification trigger)
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
      _acceptedSentRequestsSubscription?.cancel();
      _proxyRequestSubscription?.cancel();
      _hostingInterestSubscription?.cancel();
      _hostingSelectionSubscription?.cancel();
      _sessionStatusSubscription?.cancel();
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
      final internalId =
          data['id']?.toString() ?? data['messageId']?.toString();
      final effectiveId = internalId ?? messageId;

      if (effectiveId != null) {
        // [FIX] Deduplicate ONLY if it's a rich message (has type).
        // If type is missing (generic), we DO NOT mark as processed so that the RTDB listener
        // (which has better data) can pick it up and "upgrade" the notification.
        if (data['type'] != null &&
            _processedMessageIds.contains(effectiveId)) {
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
              body = 'Sent a voice message';
              break;
            case 'audio_file':
              body = 'Sent an audio file';
              break;
            case 'image':
              body = 'Photo message';
              imageUrl ??= data['imageUrl'];
              break;
            case 'video':
              body = 'Video message';
              break;
            case 'location':
              body = 'Sent a location';
              break;
            case 'document':
              body = 'Sent a document';
              break;
            case 'dsp_transfer':
            case 'points_update':
              // [REMOVED] Skip local notification for DSP transfers and rewards
              // Cloud Function onPointsTransactionCreated handles this to prevent duplicates
              debugPrint(
                '🔕 [PushNotificationService] Skipping DSP transfer/reward foreground notification (handled by backend or silenced)',
              );
              return;
            case 'money-transfer':
              body = 'Money transfer';
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
          body = msgContent.trim().isNotEmpty ? msgContent : 'Sent a message';
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
          body =
              data['content'] ??
              data['body'] ??
              'You have a new group invitation';
          // Use specific method to match original behavior or just let it fall through if payload matches
          // We can just set title/body here and let the fallthrough handle it,
          // BUT we need to ensure payload is correct for navigation.
          // The fallthrough uses `_encodePayload(message.data)`.
          // If message.data has 'chatId', it works.
        }

        // Check mute status
        final currentUserId = FirebaseAuth.instance.currentUser?.uid;
        final chatId = data['chatId'];
        if (currentUserId != null && chatId != null) {
          final isMuted = await _isChatMuted(currentUserId, chatId);
          if (isMuted) {
            debugPrint(
              '🔕 [PushNotificationService] Skipping FCM notification for muted chat: $chatId',
            );
            return;
          }
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

    debugPrint('🔔 [TAP] Notification tapped. Payload: $payload');

    try {
      final data = jsonDecode(payload) as Map<String, dynamic>;
      final type = data['type'];

      debugPrint('🔔 [TAP] Parsed type: $type');

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
        targetRoute =
            '/profile/${data['fromUserId']}?requestId=${data['requestId'] ?? ''}&action=review';
      } else if (type == 'relationship_accepted' && data['chatId'] != null) {
        targetRoute = '/chats/${data['chatId']}';
      } else if (type == 'group_invitation' && data['chatId'] != null) {
        targetRoute = '/chats/${data['chatId']}/info';
      } else if (type == 'proxy_request') {
        targetRoute = '/dsp/emergency-fund';
      } else if ((type == 'hosting_interest_chat' || type == 'hosting_interest') &&
          data['requestId'] != null) {
        targetRoute = '/notifications';
      } else if (type == 'hosting_session_chat' && data['chatId'] != null) {
        targetRoute = '/chats/${data['chatId']}';
      } else if (type == 'hosting_session') {
        targetRoute = '/communities';
      } else {
        targetRoute = '/notifications';
      }

      debugPrint('🔔 [TAP] Target route: $targetRoute');

      final currentUser = _ref.read(authRepositoryProvider).currentUser;
      if (currentUser == null) {
        debugPrint(
          '🔔 [TAP] User not logged in, queueing route: $targetRoute',
        );
        _ref.read(pendingNavigationProvider.notifier).setRoute(targetRoute);
      } else {
        debugPrint('🔔 [TAP] Navigating now to: $targetRoute');
        try {
          router.push(targetRoute);
          debugPrint('🔔 [TAP] router.push succeeded');
        } catch (routerError) {
          debugPrint('❌ [TAP] router.push failed: $routerError — trying router.go');
          try {
            router.go(targetRoute);
          } catch (goError) {
            debugPrint('❌ [TAP] router.go also failed: $goError');
          }
        }
      }
    } catch (e) {
      debugPrint('❌ [TAP] Error parsing notification payload: $e');
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

    // Persist to Notifications hub
    await _persistNotification(
      type: NotificationType.relationshipRequest,
      title: 'New Relationship Request',
      body: '$fromName wants to add you as their $relType',
      payload: {
        'fromUserId': fromUserId ?? '',
        'requestId': requestId,
      },
      actionRequired: true,
      dedupKey: 'relationship_$requestId',
    );
  }

  /// [NEW] Listen for when our sent relationship requests get accepted
  /// Shows a notification to the sender and directs them to the new DM chat
  void _listenForAcceptedSentRequests(String userId) {
    debugPrint(
      '🔔 [PushNotificationService] Starting accepted sent requests listener for user: $userId',
    );
    _acceptedSentRequestsSubscription?.cancel();

    // Track already-known accepted request IDs to avoid notifying on initial load
    final Set<String> knownAcceptedIds = {};
    bool isFirstLoad = true;

    _acceptedSentRequestsSubscription = _firestore
        .collection('relationship_requests')
        .where('fromUserId', isEqualTo: userId)
        .where('status', isEqualTo: 'accepted')
        .snapshots()
        .listen(
          (snapshot) {
            if (isFirstLoad) {
              // On first load, record all existing accepted requests without notifying
              for (final doc in snapshot.docs) {
                knownAcceptedIds.add(doc.id);
              }
              isFirstLoad = false;
              debugPrint(
                '🔔 [PushNotificationService] Accepted requests initial load: ${knownAcceptedIds.length} existing',
              );
              return;
            }

            for (final change in snapshot.docChanges) {
              if (change.type == DocumentChangeType.added ||
                  change.type == DocumentChangeType.modified) {
                final docId = change.doc.id;
                if (knownAcceptedIds.contains(docId)) continue;
                knownAcceptedIds.add(docId);

                final data = change.doc.data();
                if (data == null) continue;

                final toUserName = data['toUserName'] ?? 'Someone';
                final chatId = data['chatId'] as String?;
                final relType = data['relationshipType'] ?? 'connection';

                debugPrint(
                  '🔔 [PushNotificationService] Relationship accepted! $toUserName accepted as $relType. ChatId: $chatId',
                );

                _showAcceptedNotification(
                  toUserName,
                  relType,
                  chatId,
                  docId,
                );
              }
            }
          },
          onError: (e) {
            debugPrint(
              '❌ [PushNotificationService] Error in accepted requests listener: $e',
            );
          },
        );
  }

  Future<void> _showAcceptedNotification(
    String toUserName,
    String relType,
    String? chatId,
    String requestId,
  ) async {
    debugPrint(
      '🔔 [PushNotificationService] Showing acceptance notification for: $toUserName',
    );
    const androidDetails = AndroidNotificationDetails(
      'high_importance_channel',
      'High Importance Notifications',
      importance: Importance.max,
      priority: Priority.high,
    );
    const details = NotificationDetails(android: androidDetails);

    await _localNotifications.show(
      'accepted_$requestId'.hashCode,
      'Relationship Accepted!',
      '$toUserName accepted your $relType request. Tap to start chatting!',
      details,
      payload: jsonEncode({
        'type': 'relationship_accepted',
        'chatId': chatId,
        'requestId': requestId,
      }),
    );

    // Persist to Notifications hub
    await _persistNotification(
      type: NotificationType.relationshipAccepted,
      title: 'Relationship Accepted!',
      body: '$toUserName accepted your $relType request. Tap to start chatting!',
      payload: {
        'chatId': chatId ?? '',
        'requestId': requestId,
      },
      dedupKey: 'accepted_$requestId',
    );
  }

  /// [NEW] Listen for incoming proxy requests (emergency fund)
  void _listenForProxyRequests(String userId) {
    debugPrint(
      '🔔 [PushNotificationService] Starting proxy request listener for user: $userId',
    );
    _proxyRequestSubscription?.cancel();

    final Set<String> knownProxyRequestIds = {};
    bool isFirstLoad = true;

    _proxyRequestSubscription = _firestore
        .collection('proxy_requests')
        .where('toUserId', isEqualTo: userId)
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .listen(
          (snapshot) {
            if (isFirstLoad) {
              for (final doc in snapshot.docs) {
                knownProxyRequestIds.add(doc.id);
              }
              isFirstLoad = false;
              debugPrint(
                '🔔 [PushNotificationService] Proxy requests initial load: ${knownProxyRequestIds.length} existing',
              );
              return;
            }

            for (final change in snapshot.docChanges) {
              if (change.type == DocumentChangeType.added) {
                final docId = change.doc.id;
                if (knownProxyRequestIds.contains(docId)) continue;
                knownProxyRequestIds.add(docId);

                final data = change.doc.data();
                if (data == null) continue;

                final fromName = data['fromUserName'] ?? 'Someone';

                debugPrint(
                  '🔔 [PushNotificationService] New proxy request from: $fromName',
                );

                _showProxyRequestNotification(fromName, docId);
              }
            }
          },
          onError: (e) {
            debugPrint(
              '❌ [PushNotificationService] Error in proxy request listener: $e',
            );
          },
        );
  }

/// Listen for hosting requests where the current user is the traveler.
/// When a new host shows interest, show a local notification.
void _listenForHostingInterest(String userId) {
  debugPrint(
    '🔔 [PushNotificationService] Starting hosting interest listener for user: $userId',
  );
  _hostingInterestSubscription?.cancel();

  // Track known interested host IDs per request to detect new additions
  final Map<String, Set<String>> knownInterestIds = {};
  bool isFirstLoad = true;

  _hostingInterestSubscription = _firestore
      .collection('hosting_requests')
      .where('travelerId', isEqualTo: userId)
      .where('status', isEqualTo: 'pending')
      .snapshots()
      .listen(
        (snapshot) {
          if (isFirstLoad) {
            // On first load, just record counts without notifying
            for (final doc in snapshot.docs) {
              final data = doc.data();
              final ids = (data['interestedHostIds'] as List<dynamic>?) ?? [];
              knownInterestIds[doc.id] = ids.map((e) => e.toString()).toSet();
            }
            isFirstLoad = false;
            debugPrint(
              '🔔 [PushNotificationService] Hosting interest initial load: ${knownInterestIds.length} requests tracked',
            );
            return;
          }

          for (final change in snapshot.docChanges) {
            if (change.type == DocumentChangeType.modified) {
              final doc = change.doc;
              final data = doc.data();
              if (data == null) continue;

              final ids = (data['interestedHostIds'] as List<dynamic>?) ?? [];
              final currentIds = ids.map((e) => e.toString()).toSet();
              final previousIds = knownInterestIds[doc.id] ?? <String>{};

              // Find newly added host IDs
              final newHostIds = currentIds.difference(previousIds);

              if (newHostIds.isNotEmpty) {
                // New interest detected!
                final communityName = data['communityName'] as String? ?? 'a community';
                final newHostId = newHostIds.last; // The latest host who showed interest

                debugPrint(
                  '🔔 [PushNotificationService] New hosting interest from $newHostId for request ${doc.id}',
                );

                _showHostingInterestNotification(
                  communityName: communityName,
                  requestId: doc.id,
                  hostId: newHostId,
                  interestedCount: currentIds.length,
                );
              }

              knownInterestIds[doc.id] = currentIds;
            } else if (change.type == DocumentChangeType.added) {
              final addedData = change.doc.data();
              if (addedData != null) {
                final ids = (addedData['interestedHostIds'] as List<dynamic>?) ?? [];
                knownInterestIds[change.doc.id] = ids.map((e) => e.toString()).toSet();
              }
            }
          }
        },
        onError: (e) {
          debugPrint(
            '❌ [PushNotificationService] Error in hosting interest listener: $e',
          );
        },
      );
}

Future<void> _showHostingInterestNotification({
  required String communityName,
  required String requestId,
  required String hostId,
  int interestedCount = 1,
}) async {
  debugPrint(
    '🔔 [PushNotificationService] Showing hosting interest notification for request: $requestId, host: $hostId',
  );

  // Look up the host's name from their profile
  // Note: 'fullName' is a computed getter, not stored in Firestore.
  // The actual stored fields are 'firstName' and 'lastName'.
  String hostName = 'A host';
  try {
    final userDoc = await _firestore.collection('users').doc(hostId).get();
    if (userDoc.exists) {
      final data = userDoc.data();
      final first = data?['firstName'] as String? ?? '';
      final last = data?['lastName'] as String? ?? '';
      final combined = '$first $last'.trim();
      if (combined.isNotEmpty) {
        hostName = combined;
      }
    }
  } catch (e) {
    debugPrint('❌ [PushNotificationService] Error looking up host name: $e');
  }

  final titleText = '$hostName wants to host you!';
  final bodyText = interestedCount > 1
      ? '$hostName and ${interestedCount - 1} other${interestedCount > 2 ? 's' : ''} want to host you in $communityName! Tap to review.'
      : '$hostName wants to host you in $communityName! Tap to review.';

  await _showRichNotification(
    id: 'hosting_interest_${requestId}_$hostId'.hashCode,
    title: titleText,
    body: bodyText,
    payload: jsonEncode({
      'type': 'hosting_interest',
      'requestId': requestId,
      'hostId': hostId,
      'hostName': hostName,
    }),
  );

  // Persist to Notifications hub
  await _persistNotification(
    type: NotificationType.hostingInterest,
    title: titleText,
    body: bodyText,
    payload: {
      'requestId': requestId,
      'hostId': hostId,
      'hostName': hostName,
    },
    actionRequired: true,
    dedupKey: 'hosting_interest_${requestId}_$hostId',
  );
}

  Future<void> _showProxyRequestNotification(
    String fromName,
    String requestId,
  ) async {
    const androidDetails = AndroidNotificationDetails(
      'high_importance_channel',
      'High Importance Notifications',
      importance: Importance.max,
      priority: Priority.high,
    );
    const details = NotificationDetails(android: androidDetails);

    await _localNotifications.show(
      'proxy_$requestId'.hashCode,
      'Proxy Request',
      '$fromName wants you to be their emergency fund proxy. Tap to respond.',
      details,
      payload: jsonEncode({
        'type': 'proxy_request',
        'requestId': requestId,
      }),
    );

    // Persist to Notifications hub
    await _persistNotification(
      type: NotificationType.proxyRequest,
      title: 'Proxy Request',
      body: '$fromName wants you to be their emergency fund proxy. Tap to respond.',
      payload: {'requestId': requestId},
      actionRequired: true,
      dedupKey: 'proxy_$requestId',
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
      debugPrint('Error showing local notification: $e');
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

  // [MIGRATED] Helper to check if a chat is muted (Firestore)
  Future<bool> _isChatMuted(String userId, String chatId) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('userChats')
          .doc(chatId)
          .get();
      if (doc.exists && doc.data()?['muted'] == true) {
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('Error checking mute status: $e');
      return false;
    }
  }

  // =========================================================================
  // [NEW] Hosting Session Notifications
  // =========================================================================

  /// Listen for new hosting sessions where the current user is the host.
  /// When a traveler selects this user as their host, show a notification.
  void _listenForHostSelection(String userId) {
    debugPrint(
      '🔔 [PushNotificationService] Starting host selection listener for user: $userId',
    );
    _hostingSelectionSubscription?.cancel();

    final Set<String> knownSessionIds = {};
    bool isFirstLoad = true;

    _hostingSelectionSubscription = _firestore
        .collection('hosting_sessions')
        .where('hostId', isEqualTo: userId)
        .snapshots()
        .listen(
          (snapshot) {
            if (isFirstLoad) {
              // Record existing sessions without notifying
              for (final doc in snapshot.docs) {
                knownSessionIds.add(doc.id);
              }
              isFirstLoad = false;
              debugPrint(
                '🔔 [PushNotificationService] Host selection initial load: ${knownSessionIds.length} sessions tracked',
              );
              return;
            }

            for (final change in snapshot.docChanges) {
              if (change.type == DocumentChangeType.added &&
                  !knownSessionIds.contains(change.doc.id)) {
                final data = change.doc.data();
                if (data == null) continue;

                knownSessionIds.add(change.doc.id);

                final travelerName = data['travelerName'] as String? ?? 'A traveler';
                final communityName = data['communityName'] as String? ?? 'a community';
                final chatId = data['chatId'] as String?;

                debugPrint(
                  '🔔 [PushNotificationService] Host selected! Traveler: $travelerName, session: ${change.doc.id}',
                );

                _showRichNotification(
                  id: 'host_selected_${change.doc.id}'.hashCode,
                  title: 'You\'ve Been Selected as Host!',
                  body: '$travelerName chose you as their host in $communityName. '
                      'Tap to view the arrangement details.',
                  payload: jsonEncode({
                    'type': chatId != null ? 'hosting_session_chat' : 'hosting_session',
                    'chatId': chatId,
                    'sessionId': change.doc.id,
                    'travelerId': data['travelerId'],
                  }),
                );

                // Persist to Notifications hub
                _persistNotification(
                  type: NotificationType.hostingSelected,
                  title: 'You\'ve Been Selected as Host!',
                  body: '$travelerName chose you as their host in $communityName. '
                      'Tap to view the arrangement details.',
                  payload: {
                    'chatId': chatId,
                    'sessionId': change.doc.id,
                    'travelerId': data['travelerId'] as String? ?? '',
                  },
                  actionRequired: true,
                  dedupKey: 'host_selected_${change.doc.id}',
                );
              }
            }
          },
          onError: (e) {
            debugPrint(
              '❌ [PushNotificationService] Error in host selection listener: $e',
            );
          },
        );
  }

  /// Listen for hosting session status changes.
  /// Notifies the other party about check-in, end-stay requests, and settlement.
  void _listenForSessionStatusChanges(String userId) {
    debugPrint(
      '🔔 [PushNotificationService] Starting session status listener for user: $userId',
    );
    _sessionStatusSubscription?.cancel();

    // Track known statuses to detect changes
    final Map<String, String> knownStatuses = {};
    bool isFirstLoad = true;

    // We need two queries: one for traveler, one for host
    // Using a combined approach with both subscriptions
    _sessionStatusSubscription = _firestore
        .collection('hosting_sessions')
        .where('status', whereIn: ['confirmed', 'active', 'end_requested', 'ended'])
        .snapshots()
        .listen(
          (snapshot) {
            for (final change in snapshot.docChanges) {
              final data = change.doc.data();
              if (data == null) continue;

              final travelerId = data['travelerId'] as String?;
              final hostId = data['hostId'] as String?;

              // Only process sessions where the current user is a participant
              if (travelerId != userId && hostId != userId) continue;

              final currentStatus = data['status'] as String? ?? 'unknown';
              final previousStatus = knownStatuses[change.doc.id];

              if (isFirstLoad || change.type == DocumentChangeType.added) {
                knownStatuses[change.doc.id] = currentStatus;
                continue;
              }

              // Only notify on actual status changes
              if (previousStatus == currentStatus) continue;
              knownStatuses[change.doc.id] = currentStatus;

              final travelerName = data['travelerName'] as String? ?? 'Traveler';
              final hostName = data['hostName'] as String? ?? 'Host';
              final communityName = data['communityName'] as String? ?? 'the community';
              final endRequestedBy = data['endRequestedBy'] as String?;
              final chatId = data['chatId'] as String?;
              final isHost = userId == hostId;
              final otherPartyName = isHost ? travelerName : hostName;

              String? title;
              String? body;

              switch (currentStatus) {
                case 'active':
                  // Check-in happened
                  if (previousStatus == 'confirmed') {
                    title = 'Check-in Confirmed!';
                    body = 'Hosting session with $otherPartyName in $communityName is now active.';
                  }
                  break;

                case 'end_requested':
                  // One party requested to end
                  if (endRequestedBy != null && endRequestedBy != userId) {
                    title = 'End Stay Requested';
                    body = '$otherPartyName has requested to end the hosting session in $communityName. '
                        'Please confirm to complete the session.';
                  }
                  break;

                case 'ended':
                  title = 'Stay Ended';
                  body = 'Your hosting session with $otherPartyName in $communityName has ended.';
                  break;

                case 'settled':
                  title = 'Session Complete';
                  body = isHost
                      ? 'Your hosting of $travelerName in $communityName is complete!'
                      : 'Your stay with $hostName in $communityName is complete!';
                  break;
              }

              if (title != null && body != null) {
                debugPrint(
                  '🔔 [PushNotificationService] Session status change: ${change.doc.id} -> $currentStatus',
                );

                _showRichNotification(
                  id: 'session_${change.doc.id}_$currentStatus'.hashCode,
                  title: title,
                  body: body,
                  payload: jsonEncode({
                    'type': chatId != null ? 'hosting_session_chat' : 'hosting_session',
                    'chatId': chatId,
                    'sessionId': change.doc.id,
                  }),
                );

                // Persist to Notifications hub
                _persistNotification(
                  type: NotificationType.hostingSessionEvent,
                  title: title,
                  body: body,
                  payload: {
                    'chatId': chatId,
                    'sessionId': change.doc.id,
                    'status': currentStatus,
                  },
                  actionRequired: currentStatus == 'end_requested',
                  dedupKey: 'session_${change.doc.id}_$currentStatus',
                );
              }
            }

            if (isFirstLoad) isFirstLoad = false;
          },
          onError: (e) {
            debugPrint(
              '❌ [PushNotificationService] Error in session status listener: $e',
            );
          },
        );
  }
}
