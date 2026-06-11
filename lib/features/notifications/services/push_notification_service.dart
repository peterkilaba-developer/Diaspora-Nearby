import 'dart:convert';
import 'dart:async';
import 'package:universal_io/io.dart';
import 'package:diaspora_nearby/core/utils/web_notification.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:diaspora_nearby/router.dart';
import 'package:diaspora_nearby/features/auth/repository/auth_repository.dart';
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

/// VAPID key for Firebase Cloud Messaging on web (Web Push certificate).
const String _webVapidKey =
    'BHlX_J3pa7h4dW0HFlGRwmXQps5IAW5hE8O-r_FL8M-erofy_m4fYg92wld7O_f8Iyv3ZSxbSoOuu80qlin45Xs';

class PushNotificationService {
  final Ref _ref;
  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  bool _isInitialized = false;
  StreamSubscription<QuerySnapshot>?
  _relationshipSubscription; // Listener for requests
  StreamSubscription<QuerySnapshot>?
  _acceptedSentRequestsSubscription; // Listener for accepted sent requests
  StreamSubscription<QuerySnapshot>?
  _proxyRequestSubscription; // Listener for proxy requests
  StreamSubscription<QuerySnapshot>?
  _hostingInterestSubscription; // Listener for hosting interest
  StreamSubscription<QuerySnapshot>?
  _hostingSelectionSubscription; // Listener for host selection
  StreamSubscription<QuerySnapshot>?
  _sessionStatusSubscription; // Listener for session status changes

  // ── New feature listeners ──────────────────────────────────────────
  StreamSubscription<QuerySnapshot>?
  _bookingRequestSubscription; // Listener for peer booking requests
  StreamSubscription<QuerySnapshot>?
  _bookingStatusSubscription; // Listener for booking status changes
  StreamSubscription<QuerySnapshot>?
  _eventSubscription; // Listener for event changes
  StreamSubscription<QuerySnapshot>?
  _electionSubscription; // Listener for new elections
  StreamSubscription<QuerySnapshot>?
  _marketplaceInquirySubscription; // Listener for marketplace inquiries
  StreamSubscription<QuerySnapshot>?
  _realEstateInquirySubscription; // Listener for real estate inquiries
  StreamSubscription<QuerySnapshot>?
  _trustVerificationSubscription; // Listener for trust verifications
  StreamSubscription<QuerySnapshot>?
  _trustVouchSubscription; // Listener for trust vouches
  StreamSubscription<QuerySnapshot>?
  _fullTrustSubscription; // Listener for full trust stakes

  // Track processed messages for client-side listener too
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

    // 5. Start listening for accepted sent requests (to notify sender)
    _listenForAcceptedSentRequests(userId);

    // 6. Start listening for proxy requests
    _listenForProxyRequests(userId);

    // 7. Start listening for hosting interest notifications
    _listenForHostingInterest(userId);

    // 8. Start listening for host selection notifications
    _listenForHostSelection(userId);

    // 9. Start listening for session status changes
    _listenForSessionStatusChanges(userId);

    // 10. Start listening for peer booking requests (travel)
    _listenForBookingRequests(userId);

    // 11. Start listening for booking status changes (travel)
    _listenForBookingStatusChanges(userId);

    // 12. Start listening for event changes (cancelled/updated)
    _listenForEventChanges(userId);

    // 13. Start listening for new elections
    _listenForElections(userId);

    // 14. Start listening for marketplace inquiries
    _listenForMarketplaceInquiries(userId);

    // 15. Start listening for real estate inquiries
    _listenForRealEstateInquiries(userId);

    // 16. Start listening for trust verifications
    _listenForTrustVerifications(userId);

    // 17. Start listening for trust vouches
    _listenForTrustVouches(userId);

    // 18. Start listening for full trust stakes
    _listenForFullTrustStakes(userId);
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
      settings: settings,
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
      _bookingRequestSubscription?.cancel();
      _bookingStatusSubscription?.cancel();
      _eventSubscription?.cancel();
      _electionSubscription?.cancel();
      _marketplaceInquirySubscription?.cancel();
      _realEstateInquirySubscription?.cancel();
      _trustVerificationSubscription?.cancel();
      _trustVouchSubscription?.cancel();
      _fullTrustSubscription?.cancel();

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
      String? title = notification?.title;
      String? body = notification?.body;
      String? imageUrl = kIsWeb
          ? null
          : notification?.android?.imageUrl;

      // Centralized logic to match ChatCard display exactly
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
            if (!kIsWeb) imageUrl ??= data['imageUrl'];
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

      // Intercept Relationship Request messages
      if (data['type'] == 'relationship_request') {
        title = 'New Relationship Request';
        final fromName = data['fromUserName'] ?? 'Someone';
        final relType = data['relationshipType'] ?? 'relative';
        body = '$fromName wants to add you as their $relType';
      }

      // Handle Group Invitations
      if (data['type'] == 'group_invitation') {
        title = data['senderName'] ?? 'Someone';
        body =
            data['content'] ??
            data['body'] ??
            'You have a new group invitation';
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
        if (kIsWeb) {
          // Show browser Notification for foreground messages on web
          debugPrint(
            '🔔 [PushNotificationService] Web foreground message: $title — $body',
          );
          showWebNotification(
            title,
            body,
            tag: effectiveId ?? 'fcm-${DateTime.now().millisecondsSinceEpoch}',
          );
        } else {
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
      final token = await _fcm.getToken(
        vapidKey: kIsWeb ? _webVapidKey : null,
      );
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
    await _firestore.collection('users').doc(userId).set({
      'fcmToken': token,
      'fcmTokenUpdatedAt': FieldValue.serverTimestamp(),
      'notificationsEnabled': true,
    }, SetOptions(merge: true));
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
      } else if ((type == 'hosting_interest_chat' ||
              type == 'hosting_interest') &&
          data['requestId'] != null) {
        targetRoute = '/notifications';
      } else if (type == 'hosting_session_chat' && data['chatId'] != null) {
        targetRoute = '/chats/${data['chatId']}';
      } else if (type == 'hosting_session') {
        targetRoute = '/communities';

        // ── Travel / Peer Bookings ──────────────────────────────────────
      } else if ((type == 'travel_booking_request' ||
              type == 'travel_booking_confirmed' ||
              type == 'travel_booking_declined' ||
              type == 'travel_booking_cancelled' ||
              type == 'travel_trip_reminder') &&
          data['chatId'] != null) {
        targetRoute = '/chats/${data['chatId']}';
      } else if (type == 'travel_booking_request' ||
          type == 'travel_booking_confirmed' ||
          type == 'travel_booking_declined' ||
          type == 'travel_booking_cancelled' ||
          type == 'travel_trip_reminder') {
        targetRoute = '/dsp/travel/stays';

        // ── Events ──────────────────────────────────────────────────────
      } else if ((type == 'event_new' ||
              type == 'event_update' ||
              type == 'event_cancelled' ||
              type == 'event_new_attendee') &&
          data['eventId'] != null) {
        targetRoute = '/events/${data['eventId']}';
      } else if (type == 'event_new' ||
          type == 'event_update' ||
          type == 'event_cancelled') {
        targetRoute = '/events';

        // ── Governance / Elections ──────────────────────────────────────
      } else if (type == 'election_started' ||
          type == 'election_ending_soon' ||
          type == 'election_results') {
        final communityId = data['communityId'] as String?;
        if (communityId != null) {
          targetRoute = '/communities';
        } else {
          targetRoute = '/communities';
        }

        // ── Marketplace ─────────────────────────────────────────────────
      } else if (type == 'marketplace_inquiry' && data['listingId'] != null) {
        targetRoute = '/marketplace/listing/${data['listingId']}';
      } else if (type == 'marketplace_status_change' ||
          type == 'marketplace_price_drop') {
        final listingId = data['listingId'] as String?;
        if (listingId != null) {
          targetRoute = '/marketplace/listing/$listingId';
        } else {
          targetRoute = '/marketplace';
        }

        // ── Real Estate ─────────────────────────────────────────────────
      } else if (type == 'real_estate_inquiry' ||
          type == 'real_estate_match' ||
          type == 'real_estate_price_change' ||
          type == 'real_estate_status_change') {
        targetRoute = '/dsp/real-estate/buy';

        // ── Trust & Verification ────────────────────────────────────────
      } else if (type == 'trust_peer_verified' ||
          type == 'trust_peer_vouched' ||
          type == 'trust_full_trust_received' ||
          type == 'trust_milestone') {
        final fromUserId = data['fromUserId'] as String?;
        if (fromUserId != null) {
          targetRoute = '/profile/$fromUserId';
        } else {
          targetRoute = '/notifications';
        }

        // ── Community ───────────────────────────────────────────────────
      } else if (type == 'community_joined' || type == 'community_new_member') {
        targetRoute = '/communities';

        // ── Organization ────────────────────────────────────────────────
      } else if (type == 'org_invitation' || type == 'org_announcement') {
        targetRoute = '/notifications';

        // ── Emergency Fund ────────────────────────────────────────────
      } else if (type == 'emergency_fund_staked' ||
          type == 'emergency_fund_payment_success' ||
          type == 'emergency_fund_membership_active' ||
          type == 'emergency_fund_dsp_refunded') {
        targetRoute = '/dsp/emergency-fund';
      } else {
        targetRoute = '/notifications';
      }

      debugPrint('🔔 [TAP] Target route: $targetRoute');

      final currentUser = _ref.read(authRepositoryProvider).currentUser;
      if (currentUser == null) {
        debugPrint('🔔 [TAP] User not logged in, queueing route: $targetRoute');
        _ref.read(pendingNavigationProvider.notifier).setRoute(targetRoute);
      } else {
        debugPrint('🔔 [TAP] Navigating now to: $targetRoute');
        try {
          router.push(targetRoute);
          debugPrint('🔔 [TAP] router.push succeeded');
        } catch (routerError) {
          debugPrint(
            '❌ [TAP] router.push failed: $routerError — trying router.go',
          );
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

    // Show local notification (native only — not available on web)
    if (!kIsWeb) {
      try {
        const androidDetails = AndroidNotificationDetails(
          'high_importance_channel',
          'High Importance Notifications',
          importance: Importance.max,
          priority: Priority.high,
        );
        const details = NotificationDetails(android: androidDetails);

        await _localNotifications.show(
          id: requestId.hashCode,
          title: 'New Relationship Request',
          body: '$fromName wants to add you as their $relType',
          notificationDetails: details,
          payload: jsonEncode({
            'type': 'relationship_request',
            'fromUserId': fromUserId,
            'requestId': requestId,
            'action': 'review',
          }),
        );
      } catch (e) {
        debugPrint(
          '⚠️ [PushNotificationService] Local notification failed: $e',
        );
      }
    }

    // Persist to Notifications hub (always — works on all platforms)
    await _persistNotification(
      type: NotificationType.relationshipRequest,
      title: 'New Relationship Request',
      body: '$fromName wants to add you as their $relType',
      payload: {'fromUserId': fromUserId ?? '', 'requestId': requestId},
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

                _showAcceptedNotification(toUserName, relType, chatId, docId);
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

    // Show local notification (native only — not available on web)
    if (!kIsWeb) {
      try {
        const androidDetails = AndroidNotificationDetails(
          'high_importance_channel',
          'High Importance Notifications',
          importance: Importance.max,
          priority: Priority.high,
        );
        const details = NotificationDetails(android: androidDetails);

        await _localNotifications.show(
          id: 'accepted_$requestId'.hashCode,
          title: 'Relationship Accepted!',
          body:
              '$toUserName accepted your $relType request. Tap to start chatting!',
          notificationDetails: details,
          payload: jsonEncode({
            'type': 'relationship_accepted',
            'chatId': chatId,
            'requestId': requestId,
          }),
        );
      } catch (e) {
        debugPrint(
          '⚠️ [PushNotificationService] Local notification failed: $e',
        );
      }
    }

    // Persist to Notifications hub (always — works on all platforms)
    await _persistNotification(
      type: NotificationType.relationshipAccepted,
      title: 'Relationship Accepted!',
      body:
          '$toUserName accepted your $relType request. Tap to start chatting!',
      payload: {'chatId': chatId ?? '', 'requestId': requestId},
      actionRequired: true,
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
                  final communityName =
                      data['communityName'] as String? ?? 'a community';
                  final newHostId =
                      newHostIds.last; // The latest host who showed interest

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
                  final ids =
                      (addedData['interestedHostIds'] as List<dynamic>?) ?? [];
                  knownInterestIds[change.doc.id] = ids
                      .map((e) => e.toString())
                      .toSet();
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
      payload: {'requestId': requestId, 'hostId': hostId, 'hostName': hostName},
      actionRequired: true,
      dedupKey: 'hosting_interest_${requestId}_$hostId',
    );
  }

  Future<void> _showProxyRequestNotification(
    String fromName,
    String requestId,
  ) async {
    // Show local notification (native only — not available on web)
    if (!kIsWeb) {
      try {
        const androidDetails = AndroidNotificationDetails(
          'high_importance_channel',
          'High Importance Notifications',
          importance: Importance.max,
          priority: Priority.high,
        );
        const details = NotificationDetails(android: androidDetails);

        await _localNotifications.show(
          id: 'proxy_$requestId'.hashCode,
          title: 'Proxy Request',
          body:
              '$fromName wants you to be their emergency fund proxy. Tap to respond.',
          notificationDetails: details,
          payload: jsonEncode({
            'type': 'proxy_request',
            'requestId': requestId,
          }),
        );
      } catch (e) {
        debugPrint(
          '⚠️ [PushNotificationService] Local notification failed: $e',
        );
      }
    }

    // Persist to Notifications hub (always — works on all platforms)
    await _persistNotification(
      type: NotificationType.proxyRequest,
      title: 'Proxy Request',
      body:
          '$fromName wants you to be their emergency fund proxy. Tap to respond.',
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
        id: id,
        title: title,
        body: body,
        notificationDetails: platformChannelSpecifics,
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

                final travelerName =
                    data['travelerName'] as String? ?? 'A traveler';
                final communityName =
                    data['communityName'] as String? ?? 'a community';
                final chatId = data['chatId'] as String?;

                debugPrint(
                  '🔔 [PushNotificationService] Host selected! Traveler: $travelerName, session: ${change.doc.id}',
                );

                _showRichNotification(
                  id: 'host_selected_${change.doc.id}'.hashCode,
                  title: 'You\'ve Been Selected as Host!',
                  body:
                      '$travelerName chose you as their host in $communityName. '
                      'Tap to view the arrangement details.',
                  payload: jsonEncode({
                    'type': chatId != null
                        ? 'hosting_session_chat'
                        : 'hosting_session',
                    'chatId': chatId,
                    'sessionId': change.doc.id,
                    'travelerId': data['travelerId'],
                  }),
                );

                // Persist to Notifications hub
                _persistNotification(
                  type: NotificationType.hostingSelected,
                  title: 'You\'ve Been Selected as Host!',
                  body:
                      '$travelerName chose you as their host in $communityName. '
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
        .where(
          'status',
          whereIn: ['confirmed', 'active', 'end_requested', 'ended'],
        )
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

              final travelerName =
                  data['travelerName'] as String? ?? 'Traveler';
              final hostName = data['hostName'] as String? ?? 'Host';
              final communityName =
                  data['communityName'] as String? ?? 'the community';
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
                    body =
                        'Hosting session with $otherPartyName in $communityName is now active.';
                  }
                  break;

                case 'end_requested':
                  // One party requested to end
                  if (endRequestedBy != null && endRequestedBy != userId) {
                    title = 'End Stay Requested';
                    body =
                        '$otherPartyName has requested to end the hosting session in $communityName. '
                        'Please confirm to complete the session.';
                  }
                  break;

                case 'ended':
                  title = 'Stay Ended';
                  body =
                      'Your hosting session with $otherPartyName in $communityName has ended.';
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
                    'type': chatId != null
                        ? 'hosting_session_chat'
                        : 'hosting_session',
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

  // ═══════════════════════════════════════════════════════════════════════
  // TRAVEL / PEER BOOKING LISTENERS
  // ═══════════════════════════════════════════════════════════════════════

  /// Listen for new booking requests where the current user is the host
  void _listenForBookingRequests(String userId) {
    debugPrint(
      '🔔 [PushNotificationService] Starting booking request listener for user: $userId',
    );
    _bookingRequestSubscription?.cancel();

    final Set<String> knownBookingIds = {};
    bool isFirstLoad = true;

    _bookingRequestSubscription = _firestore
        .collection('peer_bookings')
        .where('hostId', isEqualTo: userId)
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .listen(
          (snapshot) {
            if (isFirstLoad) {
              for (final doc in snapshot.docs) {
                knownBookingIds.add(doc.id);
              }
              isFirstLoad = false;
              return;
            }

            for (final change in snapshot.docChanges) {
              if (change.type == DocumentChangeType.added) {
                final docId = change.doc.id;
                if (knownBookingIds.contains(docId)) continue;
                knownBookingIds.add(docId);

                final data = change.doc.data();
                if (data == null) continue;

                final guestName = data['guestName'] as String? ?? 'A guest';
                final listingTitle =
                    data['listingTitle'] as String? ?? 'your listing';
                final chatId = data['chatId'] as String?;

                _showRichNotification(
                  id: 'booking_request_$docId'.hashCode,
                  title: 'New Booking Request',
                  body: '$guestName wants to book $listingTitle',
                  payload: jsonEncode({
                    'type': 'travel_booking_request',
                    'bookingId': docId,
                    'chatId': chatId,
                  }),
                );

                _persistNotification(
                  type: NotificationType.travelBookingRequest,
                  title: 'New Booking Request',
                  body: '$guestName wants to book $listingTitle',
                  payload: {
                    'bookingId': docId,
                    'guestId': data['guestId'] ?? '',
                    'chatId': chatId ?? '',
                    'listingId': data['listingId'] ?? '',
                  },
                  actionRequired: true,
                  dedupKey: 'booking_request_$docId',
                );
              }
            }
          },
          onError: (e) {
            debugPrint(
              '❌ [PushNotificationService] Error in booking request listener: $e',
            );
          },
        );
  }

  /// Listen for booking status changes for bookings made by the current user
  void _listenForBookingStatusChanges(String userId) {
    debugPrint(
      '🔔 [PushNotificationService] Starting booking status listener for user: $userId',
    );
    _bookingStatusSubscription?.cancel();

    final Map<String, String> knownStatuses = {};
    bool isFirstLoad = true;

    _bookingStatusSubscription = _firestore
        .collection('peer_bookings')
        .where('guestId', isEqualTo: userId)
        .snapshots()
        .listen(
          (snapshot) {
            for (final change in snapshot.docChanges) {
              final data = change.doc.data();
              if (data == null) continue;

              final currentStatus = data['status'] as String? ?? 'pending';
              final previousStatus = knownStatuses[change.doc.id];

              if (isFirstLoad || change.type == DocumentChangeType.added) {
                knownStatuses[change.doc.id] = currentStatus;
                if (isFirstLoad) continue;
              }

              if (previousStatus == currentStatus) continue;
              knownStatuses[change.doc.id] = currentStatus;

              final hostName = data['hostName'] as String? ?? 'The host';
              final listingTitle =
                  data['listingTitle'] as String? ?? 'your booking';
              final chatId = data['chatId'] as String?;

              String? title;
              String? body;
              NotificationType? notifType;
              bool actionRequired = false;

              switch (currentStatus) {
                case 'confirmed':
                  title = 'Booking Confirmed!';
                  body = '$hostName confirmed your booking for $listingTitle';
                  notifType = NotificationType.travelBookingConfirmed;
                  break;
                case 'declined':
                  title = 'Booking Declined';
                  body = '$hostName declined your booking for $listingTitle';
                  notifType = NotificationType.travelBookingDeclined;
                  break;
                case 'cancelled':
                  title = 'Booking Cancelled';
                  body = 'Your booking for $listingTitle has been cancelled';
                  notifType = NotificationType.travelBookingCancelled;
                  break;
              }

              if (title != null && body != null && notifType != null) {
                _showRichNotification(
                  id: 'booking_status_${change.doc.id}_$currentStatus'.hashCode,
                  title: title,
                  body: body,
                  payload: jsonEncode({
                    'type': 'travel_booking_$currentStatus',
                    'bookingId': change.doc.id,
                    'chatId': chatId,
                  }),
                );

                _persistNotification(
                  type: notifType,
                  title: title,
                  body: body,
                  payload: {
                    'bookingId': change.doc.id,
                    'chatId': chatId ?? '',
                    'listingId': data['listingId'] ?? '',
                  },
                  actionRequired: actionRequired,
                  dedupKey: 'booking_${change.doc.id}_$currentStatus',
                );
              }
            }

            if (isFirstLoad) isFirstLoad = false;
          },
          onError: (e) {
            debugPrint(
              '❌ [PushNotificationService] Error in booking status listener: $e',
            );
          },
        );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // EVENT LISTENERS
  // ═══════════════════════════════════════════════════════════════════════

  /// Listen for events the user has joined where status changes (cancelled/updated)
  void _listenForEventChanges(String userId) {
    debugPrint(
      '🔔 [PushNotificationService] Starting event changes listener for user: $userId',
    );
    _eventSubscription?.cancel();

    final Map<String, Map<String, dynamic>> knownEventData = {};
    bool isFirstLoad = true;

    _eventSubscription = _firestore
        .collection('events')
        .where('participants', arrayContains: userId)
        .snapshots()
        .listen(
          (snapshot) {
            for (final change in snapshot.docChanges) {
              final data = change.doc.data();
              if (data == null) continue;

              final eventId = change.doc.id;
              final currentStatus = data['status'] as String? ?? 'active';
              final eventTitle = data['title'] as String? ?? 'An event';
              final organizerId = data['organizerId'] as String?;

              // Skip events the user organized (they know about their own changes)
              if (organizerId == userId) {
                knownEventData[eventId] = data;
                continue;
              }

              if (isFirstLoad || change.type == DocumentChangeType.added) {
                knownEventData[eventId] = data;
                if (isFirstLoad) continue;
                // For newly added events (not first load), this means the user
                // was added to a new event
                if (change.type == DocumentChangeType.added && !isFirstLoad) {
                  continue; // User joined themselves, no notification needed
                }
              }

              final previousData = knownEventData[eventId];
              final previousStatus =
                  previousData?['status'] as String? ?? 'active';
              knownEventData[eventId] = data;

              String? title;
              String? body;
              NotificationType? notifType;

              if (currentStatus == 'cancelled' &&
                  previousStatus != 'cancelled') {
                title = 'Event Cancelled';
                body = '"$eventTitle" has been cancelled by the organizer.';
                notifType = NotificationType.eventCancelled;
              } else if (change.type == DocumentChangeType.modified &&
                  currentStatus == previousStatus) {
                // Check for significant updates (time, location changes)
                final prevTime = previousData?['startTime'];
                final currTime = data['startTime'];
                final prevLocation = previousData?['location'];
                final currLocation = data['location'];

                if (prevTime != currTime || prevLocation != currLocation) {
                  title = 'Event Updated';
                  body =
                      '"$eventTitle" details have been updated. Check for changes.';
                  notifType = NotificationType.eventUpdate;
                }
              }

              if (title != null && body != null && notifType != null) {
                _showRichNotification(
                  id: 'event_${eventId}_$currentStatus'.hashCode,
                  title: title,
                  body: body,
                  payload: jsonEncode({
                    'type': notifType.name,
                    'eventId': eventId,
                  }),
                );

                _persistNotification(
                  type: notifType,
                  title: title,
                  body: body,
                  payload: {'eventId': eventId},
                  dedupKey:
                      'event_${eventId}_${currentStatus}_${DateTime.now().millisecondsSinceEpoch ~/ 60000}',
                );
              }
            }

            if (isFirstLoad) isFirstLoad = false;
          },
          onError: (e) {
            debugPrint(
              '❌ [PushNotificationService] Error in event listener: $e',
            );
          },
        );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // GOVERNANCE / ELECTION LISTENERS
  // ═══════════════════════════════════════════════════════════════════════

  /// Listen for new elections in communities the user belongs to
  void _listenForElections(String userId) {
    debugPrint(
      '🔔 [PushNotificationService] Starting election listener for user: $userId',
    );
    _electionSubscription?.cancel();

    final Set<String> knownElectionIds = {};
    bool isFirstLoad = true;

    _electionSubscription = _firestore
        .collection('governance')
        .where('status', isEqualTo: 'active')
        .snapshots()
        .listen(
          (snapshot) {
            if (isFirstLoad) {
              for (final doc in snapshot.docs) {
                knownElectionIds.add(doc.id);
              }
              isFirstLoad = false;
              return;
            }

            for (final change in snapshot.docChanges) {
              if (change.type == DocumentChangeType.added) {
                final docId = change.doc.id;
                if (knownElectionIds.contains(docId)) continue;
                knownElectionIds.add(docId);

                final data = change.doc.data();
                if (data == null) continue;

                final communityName =
                    data['communityName'] as String? ?? 'your community';
                final electionTitle =
                    data['title'] as String? ?? 'Leadership Election';

                _showRichNotification(
                  id: 'election_$docId'.hashCode,
                  title: 'Election Started',
                  body:
                      '$electionTitle has started in $communityName. Cast your vote!',
                  payload: jsonEncode({
                    'type': 'election_started',
                    'electionId': docId,
                    'communityId': data['communityId'] ?? '',
                  }),
                );

                _persistNotification(
                  type: NotificationType.electionStarted,
                  title: 'Election Started',
                  body:
                      '$electionTitle has started in $communityName. Cast your vote!',
                  payload: {
                    'electionId': docId,
                    'communityId': data['communityId'] ?? '',
                  },
                  actionRequired: true,
                  dedupKey: 'election_$docId',
                );
              }
            }
          },
          onError: (e) {
            debugPrint(
              '❌ [PushNotificationService] Error in election listener: $e',
            );
          },
        );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // MARKETPLACE LISTENERS
  // ═══════════════════════════════════════════════════════════════════════

  /// Listen for chat messages that reference the user's marketplace listings
  /// (acting as an "inquiry" notification)
  void _listenForMarketplaceInquiries(String userId) {
    debugPrint(
      '🔔 [PushNotificationService] Starting marketplace inquiry listener for user: $userId',
    );
    _marketplaceInquirySubscription?.cancel();

    final Set<String> knownInquiryIds = {};
    bool isFirstLoad = true;

    // Listen for chats where the user's listing is being discussed
    _marketplaceInquirySubscription = _firestore
        .collection('chats')
        .where('metadata.listingSellerId', isEqualTo: userId)
        .where('type', isEqualTo: 'marketplace')
        .snapshots()
        .listen(
          (snapshot) {
            if (isFirstLoad) {
              for (final doc in snapshot.docs) {
                knownInquiryIds.add(doc.id);
              }
              isFirstLoad = false;
              return;
            }

            for (final change in snapshot.docChanges) {
              if (change.type == DocumentChangeType.added) {
                final docId = change.doc.id;
                if (knownInquiryIds.contains(docId)) continue;
                knownInquiryIds.add(docId);

                final data = change.doc.data();
                if (data == null) continue;

                final metadata =
                    data['metadata'] as Map<String, dynamic>? ?? {};
                final listingTitle =
                    metadata['listingTitle'] as String? ?? 'your listing';
                final buyerName = metadata['buyerName'] as String? ?? 'Someone';
                final listingId = metadata['listingId'] as String?;

                _showRichNotification(
                  id: 'mkt_inquiry_$docId'.hashCode,
                  title: 'Marketplace Inquiry',
                  body: '$buyerName is interested in $listingTitle',
                  payload: jsonEncode({
                    'type': 'marketplace_inquiry',
                    'chatId': docId,
                    'listingId': listingId,
                  }),
                );

                _persistNotification(
                  type: NotificationType.marketplaceInquiry,
                  title: 'Marketplace Inquiry',
                  body: '$buyerName is interested in $listingTitle',
                  payload: {'chatId': docId, 'listingId': listingId ?? ''},
                  actionRequired: true,
                  dedupKey: 'mkt_inquiry_$docId',
                );
              }
            }
          },
          onError: (e) {
            debugPrint(
              '❌ [PushNotificationService] Error in marketplace inquiry listener: $e',
            );
          },
        );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // REAL ESTATE LISTENERS
  // ═══════════════════════════════════════════════════════════════════════

  /// Listen for inquiries on the user's real estate listings
  void _listenForRealEstateInquiries(String userId) {
    debugPrint(
      '🔔 [PushNotificationService] Starting real estate inquiry listener for user: $userId',
    );
    _realEstateInquirySubscription?.cancel();

    final Set<String> knownInquiryIds = {};
    bool isFirstLoad = true;

    _realEstateInquirySubscription = _firestore
        .collection('chats')
        .where('metadata.propertySellerId', isEqualTo: userId)
        .where('type', isEqualTo: 'real_estate')
        .snapshots()
        .listen(
          (snapshot) {
            if (isFirstLoad) {
              for (final doc in snapshot.docs) {
                knownInquiryIds.add(doc.id);
              }
              isFirstLoad = false;
              return;
            }

            for (final change in snapshot.docChanges) {
              if (change.type == DocumentChangeType.added) {
                final docId = change.doc.id;
                if (knownInquiryIds.contains(docId)) continue;
                knownInquiryIds.add(docId);

                final data = change.doc.data();
                if (data == null) continue;

                final metadata =
                    data['metadata'] as Map<String, dynamic>? ?? {};
                final propertyTitle =
                    metadata['propertyTitle'] as String? ?? 'your property';
                final buyerName = metadata['buyerName'] as String? ?? 'Someone';

                _showRichNotification(
                  id: 're_inquiry_$docId'.hashCode,
                  title: 'Property Inquiry',
                  body: '$buyerName is interested in $propertyTitle',
                  payload: jsonEncode({
                    'type': 'real_estate_inquiry',
                    'chatId': docId,
                  }),
                );

                _persistNotification(
                  type: NotificationType.realEstateInquiry,
                  title: 'Property Inquiry',
                  body: '$buyerName is interested in $propertyTitle',
                  payload: {'chatId': docId},
                  actionRequired: true,
                  dedupKey: 're_inquiry_$docId',
                );
              }
            }
          },
          onError: (e) {
            debugPrint(
              '❌ [PushNotificationService] Error in real estate inquiry listener: $e',
            );
          },
        );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // TRUST & VERIFICATION LISTENERS
  // ═══════════════════════════════════════════════════════════════════════

  /// Listen for when other users verify this user's identity
  void _listenForTrustVerifications(String userId) {
    debugPrint(
      '🔔 [PushNotificationService] Starting trust verification listener for user: $userId',
    );
    _trustVerificationSubscription?.cancel();

    final Set<String> knownVerificationIds = {};
    bool isFirstLoad = true;

    _trustVerificationSubscription = _firestore
        .collection('field_verifications')
        .where('verifiedUserId', isEqualTo: userId)
        .snapshots()
        .listen(
          (snapshot) {
            if (isFirstLoad) {
              for (final doc in snapshot.docs) {
                knownVerificationIds.add(doc.id);
              }
              isFirstLoad = false;
              return;
            }

            for (final change in snapshot.docChanges) {
              if (change.type == DocumentChangeType.added) {
                final docId = change.doc.id;
                if (knownVerificationIds.contains(docId)) continue;
                knownVerificationIds.add(docId);

                final data = change.doc.data();
                if (data == null) continue;

                final verifierName =
                    data['verifierName'] as String? ?? 'A peer';
                final verifierId = data['verifierId'] as String?;

                _showRichNotification(
                  id: 'trust_verify_$docId'.hashCode,
                  title: 'Identity Verified',
                  body:
                      '$verifierName has verified your identity. Your PoCT score increased!',
                  payload: jsonEncode({
                    'type': 'trust_peer_verified',
                    'fromUserId': verifierId,
                  }),
                );

                _persistNotification(
                  type: NotificationType.trustPeerVerified,
                  title: 'Identity Verified',
                  body:
                      '$verifierName has verified your identity. Your PoCT score increased!',
                  payload: {'fromUserId': verifierId ?? ''},
                  dedupKey: 'trust_verify_$docId',
                );
              }
            }
          },
          onError: (e) {
            debugPrint(
              '❌ [PushNotificationService] Error in trust verification listener: $e',
            );
          },
        );
  }

  /// Listen for when other users vouch for this user
  void _listenForTrustVouches(String userId) {
    debugPrint(
      '🔔 [PushNotificationService] Starting trust vouch listener for user: $userId',
    );
    _trustVouchSubscription?.cancel();

    final Set<String> knownVouchIds = {};
    bool isFirstLoad = true;

    _trustVouchSubscription = _firestore
        .collection('vouches')
        .where('vouchedUserId', isEqualTo: userId)
        .snapshots()
        .listen(
          (snapshot) {
            if (isFirstLoad) {
              for (final doc in snapshot.docs) {
                knownVouchIds.add(doc.id);
              }
              isFirstLoad = false;
              return;
            }

            for (final change in snapshot.docChanges) {
              if (change.type == DocumentChangeType.added) {
                final docId = change.doc.id;
                if (knownVouchIds.contains(docId)) continue;
                knownVouchIds.add(docId);

                final data = change.doc.data();
                if (data == null) continue;

                final voucherName = data['voucherName'] as String? ?? 'A peer';
                final voucherId = data['voucherId'] as String?;

                _showRichNotification(
                  id: 'trust_vouch_$docId'.hashCode,
                  title: 'Peer Vouch Received',
                  body:
                      '$voucherName vouched for you. Your trust in the community grows!',
                  payload: jsonEncode({
                    'type': 'trust_peer_vouched',
                    'fromUserId': voucherId,
                  }),
                );

                _persistNotification(
                  type: NotificationType.trustPeerVouched,
                  title: 'Peer Vouch Received',
                  body:
                      '$voucherName vouched for you. Your trust in the community grows!',
                  payload: {'fromUserId': voucherId ?? ''},
                  dedupKey: 'trust_vouch_$docId',
                );
              }
            }
          },
          onError: (e) {
            debugPrint(
              '❌ [PushNotificationService] Error in trust vouch listener: $e',
            );
          },
        );
  }

  /// Listen for when other users give this user full trust (staked 100 DSP)
  void _listenForFullTrustStakes(String userId) {
    debugPrint(
      '🔔 [PushNotificationService] Starting full trust stake listener for user: $userId',
    );
    _fullTrustSubscription?.cancel();

    final Set<String> knownFullTrustIds = {};
    bool isFirstLoad = true;

    _fullTrustSubscription = _firestore
        .collection('trust_ratings')
        .where('toUserId', isEqualTo: userId)
        .where('isFullTrust', isEqualTo: true)
        .snapshots()
        .listen(
          (snapshot) {
            if (isFirstLoad) {
              for (final doc in snapshot.docs) {
                knownFullTrustIds.add(doc.id);
              }
              isFirstLoad = false;
              return;
            }

            for (final change in snapshot.docChanges) {
              if (change.type == DocumentChangeType.added ||
                  change.type == DocumentChangeType.modified) {
                final docId = change.doc.id;
                if (knownFullTrustIds.contains(docId) &&
                    change.type == DocumentChangeType.added) {
                  continue;
                }
                knownFullTrustIds.add(docId);

                final data = change.doc.data();
                if (data == null) continue;

                // Only notify for full trust entries
                if (data['isFullTrust'] != true) continue;

                final stakerName = data['fromUserName'] as String? ?? 'A peer';
                final stakerId = data['fromUserId'] as String?;

                _showRichNotification(
                  id: 'full_trust_$docId'.hashCode,
                  title: 'Full Trust Received!',
                  body:
                      '$stakerName gave you full trust and staked 100 DSP on your reputation!',
                  payload: jsonEncode({
                    'type': 'trust_full_trust_received',
                    'fromUserId': stakerId,
                  }),
                );

                _persistNotification(
                  type: NotificationType.trustFullTrustReceived,
                  title: 'Full Trust Received!',
                  body:
                      '$stakerName gave you full trust and staked 100 DSP on your reputation!',
                  payload: {'fromUserId': stakerId ?? ''},
                  dedupKey: 'full_trust_$docId',
                );
              }
            }
          },
          onError: (e) {
            debugPrint(
              '❌ [PushNotificationService] Error in full trust stake listener: $e',
            );
          },
        );
  }
}
