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
import 'package:diaspora_nearby/features/profile/repository/profile_repository.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http; // [NEW]
import 'package:path_provider/path_provider.dart'; // [NEW]
import 'package:diaspora_nearby/features/notifications/models/notification_item.dart';
import 'package:diaspora_nearby/features/notifications/repository/notifications_repository.dart';

/// Represents a single message line inside a grouped chat push notification container.
class ChatNotificationLine {
  final String? messageId;
  final String senderName;
  final String? senderId;
  final String text;
  final DateTime timestamp;

  const ChatNotificationLine({
    this.messageId,
    required this.senderName,
    this.senderId,
    required this.text,
    required this.timestamp,
  });
}

/// Tracks which chat conversation is currently open and visible to the user
/// so foreground push notifications and local mention monitors do not interrupt
/// an active conversation.
class ActiveChatTracker {
  ActiveChatTracker._();
  static final ActiveChatTracker instance = ActiveChatTracker._();

  String? _activeChatId;
  String? _activePartnerUserId;
  AppLifecycleState _lifecycleState = AppLifecycleState.resumed;

  String? get activeChatId => _activeChatId;
  String? get activePartnerUserId => _activePartnerUserId;
  AppLifecycleState get lifecycleState => _lifecycleState;

  void setActiveChat({String? chatId, String? partnerUserId}) {
    _activeChatId = (chatId != null && chatId.trim().isNotEmpty)
        ? chatId.trim()
        : null;
    _activePartnerUserId =
        (partnerUserId != null && partnerUserId.trim().isNotEmpty)
        ? partnerUserId.trim()
        : null;
  }

  void clearActiveChat({String? chatId, String? partnerUserId}) {
    if (chatId == null && partnerUserId == null) {
      _activeChatId = null;
      _activePartnerUserId = null;
      return;
    }
    final matchesChat = chatId != null && _activeChatId == chatId.trim();
    final matchesPartner =
        partnerUserId != null && _activePartnerUserId == partnerUserId.trim();
    if (matchesChat || matchesPartner) {
      _activeChatId = null;
      _activePartnerUserId = null;
    }
  }

  void setLifecycleState(AppLifecycleState state) {
    _lifecycleState = state;
  }

  bool get isAppInForeground =>
      _lifecycleState == AppLifecycleState.resumed ||
      _lifecycleState == AppLifecycleState.inactive;

  bool isActivelyInChat({String? chatId, String? senderId}) {
    if (!isAppInForeground) return false;

    final normalizedChatId = chatId?.trim();
    final normalizedSenderId = senderId?.trim();

    if (_activeChatId != null &&
        normalizedChatId != null &&
        normalizedChatId.isNotEmpty) {
      return _activeChatId == normalizedChatId;
    }

    if (_activePartnerUserId != null &&
        normalizedSenderId != null &&
        normalizedSenderId.isNotEmpty) {
      return _activePartnerUserId == normalizedSenderId;
    }

    return false;
  }
}

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
  final Ref? _ref;
  final FirebaseMessaging? _injectedFcm;
  final FlutterLocalNotificationsPlugin _localNotifications;
  final FirebaseFirestore? _injectedFirestore;

  FirebaseMessaging get _fcm => _injectedFcm ?? FirebaseMessaging.instance;
  FirebaseFirestore get _firestore =>
      _injectedFirestore ?? FirebaseFirestore.instance;

  static final Map<String, bool> _mutedChatCache = {};

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
  _travelerSessionStatusSubscription; // Traveler-side session listener
  StreamSubscription<QuerySnapshot>?
  _hostSessionStatusSubscription; // Host-side session listener

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
  _trustVerificationSubscription; // Listener for trust verifications
  StreamSubscription<QuerySnapshot>?
  _trustVouchSubscription; // Listener for trust vouches

  // Track processed messages for client-side listener too
  final Set<String> _processedMessageIds = {};

  // Per-chat buffered notification messages so multiple incoming messages
  // from the same conversation are stacked inside a single push notification container.
  final Map<String, List<ChatNotificationLine>> _chatNotificationMessages = {};

  PushNotificationService(
    this._ref, {
    FirebaseMessaging? fcm,
    FlutterLocalNotificationsPlugin? localNotifications,
    FirebaseFirestore? firestore,
  }) : _injectedFcm = fcm,
       _localNotifications =
           localNotifications ?? FlutterLocalNotificationsPlugin(),
       _injectedFirestore = firestore;

  /// Deterministic 31-bit positive integer ID for a chat notification container.
  static int chatNotificationId(String chatKey) {
    var hash = 0x811c9dc5;
    for (var i = 0; i < chatKey.length; i++) {
      hash ^= chatKey.codeUnitAt(i);
      hash = (hash * 0x01000193) & 0x7fffffff;
    }
    return hash == 0 ? 1 : hash;
  }

  /// Register which chat (and/or direct-chat partner user) the user is actively viewing.
  /// Automatically clears any buffered notification lines and dismisses existing
  /// system-tray notifications for that chat.
  Future<void> setActiveChat({String? chatId, String? partnerUserId}) async {
    ActiveChatTracker.instance.setActiveChat(
      chatId: chatId,
      partnerUserId: partnerUserId,
    );
    if (chatId != null && chatId.trim().isNotEmpty) {
      await clearChatNotifications(chatId.trim());
    }
    if (partnerUserId != null && partnerUserId.trim().isNotEmpty) {
      await clearChatNotifications('user_${partnerUserId.trim()}');
    }
  }

  /// Clear active chat state when the user leaves the chat screen.
  void clearActiveChat({String? chatId, String? partnerUserId}) {
    ActiveChatTracker.instance.clearActiveChat(
      chatId: chatId,
      partnerUserId: partnerUserId,
    );
  }

  /// Update the foreground/background lifecycle state for active chat suppression.
  void setLifecycleState(AppLifecycleState state) {
    ActiveChatTracker.instance.setLifecycleState(state);
  }

  /// Returns true if the user is actively chatting in [chatId] or with [senderId]
  /// while the app is in the foreground.
  bool isActivelyInChat({String? chatId, String? senderId}) {
    try {
      final bindingState = WidgetsBinding.instance.lifecycleState;
      if (bindingState != null &&
          bindingState != AppLifecycleState.resumed &&
          bindingState != AppLifecycleState.inactive) {
        return false;
      }
    } catch (_) {}

    if (ActiveChatTracker.instance.isActivelyInChat(
      chatId: chatId,
      senderId: senderId,
    )) {
      return true;
    }

    try {
      final ref = _ref;
      if (ref != null && ActiveChatTracker.instance.isAppInForeground) {
        final uri = ref.read(routerProvider).routeInformationProvider.value.uri;
        final path = uri.path;
        if (chatId != null &&
            chatId.trim().isNotEmpty &&
            path == '/chats/${chatId.trim()}') {
          return true;
        }
        if (senderId != null &&
            senderId.trim().isNotEmpty &&
            path == '/chat/direct/${senderId.trim()}') {
          return true;
        }
      }
    } catch (_) {}

    return false;
  }

  /// Clears buffered notification messages for [chatKey] and cancels its active
  /// notification container in the system tray.
  Future<void> clearChatNotifications(String chatKey) async {
    final trimmed = chatKey.trim();
    if (trimmed.isEmpty) return;
    _chatNotificationMessages.remove(trimmed);
    if (!kIsWeb) {
      final id = chatNotificationId(trimmed);
      final tag = 'chat_$trimmed';
      try {
        await _localNotifications.cancel(id: id, tag: tag);
        await _localNotifications.cancel(id: id);
        await _localNotifications.cancel(id: 0, tag: tag);
      } catch (_) {}
    }
  }

  /// Read-only view of buffered notification lines for [chatKey] (useful for testing).
  List<ChatNotificationLine> getBufferedChatMessages(String chatKey) {
    return List<ChatNotificationLine>.unmodifiable(
      _chatNotificationMessages[chatKey.trim()] ??
          const <ChatNotificationLine>[],
    );
  }

  /// The currently authenticated user's ID (or null).
  String? get _activeUserId {
    try {
      return _ref?.read(authRepositoryProvider).currentUser?.uid;
    } catch (_) {
      return null;
    }
  }

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

    final ref = _ref;
    if (ref == null) return;
    final repo = ref.read(notificationsRepositoryProvider);

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
    final ref = _ref;
    if (ref != null) {
      ref.read(authRepositoryProvider).authStateChanges.listen((user) {
        if (user != null) {
          debugPrint(
            'PushNotificationService: User signed in (${user.uid}), registering notifications...',
          );
          registerForUser(user.uid);

          // Handle Pending Navigation
          final pendingRoute = ref.read(pendingNavigationProvider);
          if (pendingRoute != null) {
            debugPrint(
              'PushNotificationService: Navigating to pending route: $pendingRoute',
            );
            ref.read(routerProvider).push(pendingRoute);
            ref.read(pendingNavigationProvider.notifier).clear();
          }
        } else {
          debugPrint('PushNotificationService: User signed out.');
          _cancelAllSubscriptions();
        }
      });
    }

    // 6. Check Initial User (in case stream doesn't emit immediately or we missed it)
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser != null) {
      registerForUser(currentUser.uid);
    }
  }

  /// Called when user logs in
  Future<void> registerForUser(String userId) async {
    // Start Firestore listeners immediately on frame 0 without blocking on FCM/permission prompts
    _listenForRelationshipRequests(userId);
    _listenForAcceptedSentRequests(userId);
    _listenForProxyRequests(userId);
    _listenForHostingInterest(userId);
    _listenForHostSelection(userId);
    _listenForSessionStatusChanges(userId);
    _listenForBookingRequests(userId);
    _listenForBookingStatusChanges(userId);
    _listenForEventChanges(userId);
    _listenForElections(userId);
    _listenForTrustVerifications(userId);
    _listenForTrustVouches(userId);

    // Run FCM token registration and permission + topic subscription concurrently
    await Future.wait([
      registerFCMToken(userId).catchError((Object e) {
        debugPrint('Error registering FCM token: $e');
      }),
      () async {
        try {
          final granted = await requestPermission();
          if (granted) {
            await subscribeToTopics(userId);
          }
        } catch (e) {
          debugPrint('Error subscribing to topics: $e');
        }
      }(),
    ]);
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
    _cancelAllSubscriptions();
    try {
      await Future.wait([
        _fcm.deleteToken(),
        _firestore.collection('user_private').doc(userId).set({
          'fcmToken': null,
          'notificationsEnabled': false,
          'fcmTokenUpdatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true)),
      ]);
    } catch (e) {
      // Error disabling notifications
    }
  }

  /// Cancels all active Firestore notification subscriptions
  void _cancelAllSubscriptions() {
    _relationshipSubscription?.cancel();
    _relationshipSubscription = null;
    _acceptedSentRequestsSubscription?.cancel();
    _acceptedSentRequestsSubscription = null;
    _proxyRequestSubscription?.cancel();
    _proxyRequestSubscription = null;
    _hostingInterestSubscription?.cancel();
    _hostingInterestSubscription = null;
    _hostingSelectionSubscription?.cancel();
    _hostingSelectionSubscription = null;
    _travelerSessionStatusSubscription?.cancel();
    _travelerSessionStatusSubscription = null;
    _hostSessionStatusSubscription?.cancel();
    _hostSessionStatusSubscription = null;
    _bookingRequestSubscription?.cancel();
    _bookingRequestSubscription = null;
    _bookingStatusSubscription?.cancel();
    _bookingStatusSubscription = null;
    _eventSubscription?.cancel();
    _eventSubscription = null;
    _electionSubscription?.cancel();
    _electionSubscription = null;
    _trustVerificationSubscription?.cancel();
    _trustVerificationSubscription = null;
    _trustVouchSubscription?.cancel();
    _trustVouchSubscription = null;
  }

  /// Setup FCM message handlers
  void _setupMessageHandlers() {
    // Foreground Message
    FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
      final notification = message.notification;
      await handleIncomingMessage(
        messageId: message.messageId,
        notificationTitle: notification?.title,
        notificationBody: notification?.body,
        imageUrl: kIsWeb ? null : notification?.android?.imageUrl,
        data: message.data,
      );
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

  /// Processes an incoming foreground push message.
  ///
  /// 1. Suppresses notifications when the user is actively chatting with that
  ///    peer / in that chat.
  /// 2. Accumulates multiple unread messages from the same chat/sender into a
  ///    single push notification container (`id` + `tag` per chat) instead of
  ///    spawning separate notification containers.
  Future<void> handleIncomingMessage({
    String? messageId,
    String? notificationTitle,
    String? notificationBody,
    String? imageUrl,
    required Map<String, dynamic> data,
    String? currentUserIdOverride,
  }) async {
    // [FIX] Deduplicate using internal ID if available, otherwise FCM ID
    final internalId = data['id']?.toString() ?? data['messageId']?.toString();
    final effectiveId = internalId ?? messageId;

    if (effectiveId != null) {
      // [FIX] Deduplicate ONLY if it's a rich message (has type).
      if (data['type'] != null && _processedMessageIds.contains(effectiveId)) {
        return;
      }

      // Only block future notifications if this one is rich enough
      if (data['type'] != null) {
        _processedMessageIds.add(effectiveId);
        if (_processedMessageIds.length > 50) _processedMessageIds.clear();
      }
    }

    String? title = notificationTitle;
    String? body = notificationBody;
    String? resolvedImageUrl = kIsWeb ? null : imageUrl;

    // Centralized logic to match ChatCard display exactly
    final String? rawType = data['type']?.toString();
    final String? messageSubType = data['messageType']?.toString();
    final String? msgType = messageSubType ?? rawType;
    final String msgContent = (data['content'] ?? data['body'] ?? '')
        .toString();

    if (rawType == 'dsp_transfer' ||
        rawType == 'points_update' ||
        msgType == 'dsp_transfer' ||
        msgType == 'points_update') {
      debugPrint(
        '🔕 [PushNotificationService] Skipping DSP transfer/reward foreground notification (handled by backend or silenced)',
      );
      return;
    }

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
          if (!kIsWeb) resolvedImageUrl ??= data['imageUrl']?.toString();
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
        case 'money-transfer':
          body = 'Money transfer';
          break;
      }
    }

    // Fallback for Data-Only Messages or Text/Chat Types
    if (title?.trim().isEmpty ?? true) {
      title = data['senderName']?.toString().trim().isNotEmpty == true
          ? data['senderName'].toString().trim()
          : 'New Message';
    }

    String singleLineText = msgContent.trim().isNotEmpty
        ? msgContent.trim()
        : (body?.trim().isNotEmpty == true ? body!.trim() : 'Sent a message');
    if (msgType == 'audio' ||
        msgType == 'audio_file' ||
        msgType == 'image' ||
        msgType == 'video' ||
        msgType == 'location' ||
        msgType == 'document' ||
        msgType == 'money-transfer') {
      if (msgContent.trim().isEmpty && body != null && body.trim().isNotEmpty) {
        singleLineText = body.trim();
      }
    }

    if (body?.trim().isEmpty ?? true) {
      body = singleLineText;
    }

    // Intercept Relationship Request messages
    if (rawType == 'relationship_request') {
      title = 'New Relationship Request';
      final fromName = data['fromUserName'] ?? 'Someone';
      final relType = data['relationshipType'] ?? 'relative';
      body = '$fromName wants to add you as their $relType';
    }

    // Handle Group Invitations
    if (rawType == 'group_invitation') {
      title = data['senderName']?.toString() ?? 'Someone';
      body =
          (data['content'] ?? data['body'] ?? 'You have a new group invitation')
              .toString();
    }

    final String? chatId = data['chatId']?.toString().trim();
    final String? senderId = (data['senderId'] ?? data['userId'])
        ?.toString()
        .trim();

    const chatNotificationTypes = <String>{
      'chat_message',
      'direct_message',
      'group_mention',
      'chat_reaction',
      'text',
      'chat',
      'image',
      'video',
      'audio',
      'audio_file',
      'location',
      'document',
      'money-transfer',
    };

    final bool isChatNotification =
        (rawType == null || chatNotificationTypes.contains(rawType)) &&
        ((chatId != null && chatId.isNotEmpty) ||
            (senderId != null &&
                senderId.isNotEmpty &&
                rawType != null &&
                chatNotificationTypes.contains(rawType)));

    // [FIX 1] Suppress push notification when user is actively chatting with
    // the sender / viewing this conversation in the foreground.
    if (isChatNotification &&
        isActivelyInChat(chatId: chatId, senderId: senderId)) {
      debugPrint(
        '🔕 [PushNotificationService] Skipping notification for active chat: ${chatId ?? senderId}',
      );
      if (chatId != null && chatId.isNotEmpty) {
        await clearChatNotifications(chatId);
      }
      return;
    }

    // Check mute status
    String? currentUserId = currentUserIdOverride ?? _activeUserId;
    if (currentUserId == null) {
      try {
        currentUserId = FirebaseAuth.instance.currentUser?.uid;
      } catch (_) {}
    }
    if (currentUserId != null && chatId != null && chatId.isNotEmpty) {
      final isMuted = await _isChatMuted(currentUserId, chatId);
      if (isMuted) {
        debugPrint(
          '🔕 [PushNotificationService] Skipping FCM notification for muted chat: $chatId',
        );
        return;
      }
    }

    // [FIX 2] Group multiple messages from the same chat/sender into a single
    // push notification container instead of showing multiple containers.
    if (isChatNotification && title != null) {
      final containerKey = (chatId != null && chatId.isNotEmpty)
          ? chatId
          : 'user_${senderId!}';
      final lines = _appendChatNotificationMessage(
        containerKey: containerKey,
        messageId: effectiveId,
        senderName: title,
        senderId: senderId,
        text: singleLineText,
        rawUnreadLinesJson: data['unreadLines']?.toString(),
      );
      final combinedBody = lines.map((m) => m.text).join('\n');
      final notificationTag = 'chat_$containerKey';
      final notificationId = chatNotificationId(containerKey);

      if (kIsWeb) {
        debugPrint(
          '🔔 [PushNotificationService] Web foreground chat message ($notificationTag): $title — $combinedBody',
        );
        showWebNotification(title, combinedBody, tag: notificationTag);
      } else {
        await _showGroupedChatNotification(
          id: notificationId,
          tag: notificationTag,
          title: title,
          lines: lines,
          payload: _encodePayload(data),
          imageUrl: resolvedImageUrl,
        );
      }
      return;
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
        await _showRichNotification(
          id:
              (effectiveId ?? notificationTitle)?.hashCode ??
              DateTime.now().millisecond,
          title: title,
          body: body,
          payload: _encodePayload(data),
          imageUrl: resolvedImageUrl,
        );
      }
    }
  }

  /// Register FCM token and save to Firestore
  Future<void> registerFCMToken(String userId) async {
    try {
      final token = await _fcm.getToken(vapidKey: kIsWeb ? _webVapidKey : null);
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
    await _firestore.collection('user_private').doc(userId).set({
      'fcmToken': token,
      'fcmTokenUpdatedAt': FieldValue.serverTimestamp(),
      'notificationsEnabled': true,
    }, SetOptions(merge: true));
  }

  /// Subscribe to relevant topics
  Future<void> subscribeToTopics(String userId) async {
    try {
      String? homeCountryCode;
      String? hostCity;

      final cachedProfile = _ref
          ?.read(profileRepositoryProvider)
          .getCachedProfile(userId);
      if (cachedProfile != null) {
        homeCountryCode = cachedProfile.homeCountryCode;
        hostCity = cachedProfile.hostLocation.city;
      } else {
        final userDoc = await _firestore.collection('users').doc(userId).get();
        if (!userDoc.exists) return;
        final data = userDoc.data()!;
        homeCountryCode = data['homeCountryCode']?.toString();
        hostCity =
            data['hostCity']?.toString() ??
            (data['hostLocation'] is Map
                ? (data['hostLocation'] as Map)['city']?.toString()
                : null);
      }

      final topics = <String>['all_users'];

      // Home Country Topic
      if (homeCountryCode != null && homeCountryCode.isNotEmpty) {
        final countryCode = homeCountryCode.toLowerCase();
        topics.add('country_$countryCode');
      }

      // Host City Topic
      if (hostCity != null && hostCity.isNotEmpty) {
        final city = hostCity
            .toLowerCase()
            .replaceAll(RegExp(r'\s+'), '_')
            .replaceAll(RegExp(r'[^a-z0-9_]'), '');
        if (city.isNotEmpty) {
          topics.add('city_$city');
        }
      }

      // Save topics to Firestore and subscribe via FCM SDK concurrently
      await Future.wait([
        _firestore.collection('user_private').doc(userId).set({
          'fcmTopics': topics,
          'fcmTopicsUpdatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true)),
        if (!kIsWeb) ...topics.map((topic) => _fcm.subscribeToTopic(topic)),
      ]);
    } catch (e) {
      // Error subscribing to topics
    }
  }

  /// Resolves the target route for a notification payload map.
  @visibleForTesting
  static String resolveTargetRouteForData(Map<String, dynamic> data) {
    final type = data['type'];

    if ((type == 'direct_message' ||
            type == 'chat_message' ||
            type == 'group_mention' ||
            type == 'chat_reaction' ||
            type == 'dsp_transfer') &&
        data['chatId'] != null) {
      return '/chats/${data['chatId']}';
    } else if (type == 'event_reminder' && data['eventId'] != null) {
      return '/events/${data['eventId']}';
    } else if (type == 'money_transfer' ||
        type == 'money-transfer' ||
        type == 'points_update') {
      return '/dsp/points';
    } else if (type == 'nearby_compatriot' && data['userId'] != null) {
      return '/profile/${data['userId']}';
    } else if (type == 'relationship_request' && data['fromUserId'] != null) {
      return '/profile/${data['fromUserId']}?requestId=${data['requestId'] ?? ''}&action=review';
    } else if (type == 'relationship_accepted' && data['chatId'] != null) {
      return '/chats/${data['chatId']}';
    } else if (type == 'group_invitation' && data['chatId'] != null) {
      return '/chats/${data['chatId']}/info';
    } else if (type == 'proxy_request') {
      return '/dsp/emergency-fund';
    } else if ((type == 'hosting_interest_chat' ||
            type == 'hosting_interest') &&
        data['requestId'] != null) {
      return '/notifications';
    } else if (type == 'hosting_session_chat' && data['chatId'] != null) {
      return '/chats/${data['chatId']}';
    } else if (type == 'hosting_session') {
      return '/communities';

      // ── Travel / Peer Bookings ──────────────────────────────────────
    } else if ((type == 'travel_booking_request' ||
            type == 'travel_booking_confirmed' ||
            type == 'travel_booking_declined' ||
            type == 'travel_booking_cancelled' ||
            type == 'travel_trip_reminder') &&
        data['chatId'] != null) {
      return '/chats/${data['chatId']}';
    } else if (type == 'travel_booking_request' ||
        type == 'travel_booking_confirmed' ||
        type == 'travel_booking_declined' ||
        type == 'travel_booking_cancelled' ||
        type == 'travel_trip_reminder') {
      return '/dsp/travel/stays';

      // ── Events ──────────────────────────────────────────────────────
    } else if ((type == 'event_new' ||
            type == 'event_update' ||
            type == 'event_cancelled' ||
            type == 'event_new_attendee') &&
        data['eventId'] != null) {
      return '/events/${data['eventId']}';
    } else if (type == 'event_new' ||
        type == 'event_update' ||
        type == 'event_cancelled') {
      return '/events';

      // ── Governance / Elections ──────────────────────────────────────
    } else if (type == 'election_started' ||
        type == 'election_ending_soon' ||
        type == 'election_results') {
      return '/communities';

      // ── Marketplace ─────────────────────────────────────────────────
    } else if (type == 'marketplace_inquiry' && data['listingId'] != null) {
      return '/marketplace/listing/${data['listingId']}';
    } else if (type == 'marketplace_status_change' ||
        type == 'marketplace_price_drop') {
      final listingId = data['listingId'] as String?;
      if (listingId != null) {
        return '/marketplace/listing/$listingId';
      } else {
        return '/marketplace';
      }

      // ── Real Estate ─────────────────────────────────────────────────
    } else if (type == 'real_estate_inquiry' ||
        type == 'real_estate_match' ||
        type == 'real_estate_price_change' ||
        type == 'real_estate_status_change') {
      return '/dsp/real-estate/buy';

      // ── Trust & Verification ────────────────────────────────────────
    } else if (type == 'trust_peer_verified' ||
        type == 'trust_peer_vouched' ||
        type == 'trust_full_trust_received' ||
        type == 'trust_no_trust_received' ||
        type == 'trust_stake_consensus_agree' ||
        type == 'trust_stake_consensus_disagree' ||
        type == 'trust_milestone') {
      final fromUserId = (data['fromUserId'] ?? data['userId'])
          ?.toString()
          .trim();
      if (fromUserId != null && fromUserId.isNotEmpty) {
        return '/profile/$fromUserId';
      } else {
        return '/notifications';
      }

      // ── Community ───────────────────────────────────────────────────
    } else if (type == 'community_joined' || type == 'community_new_member') {
      return '/communities';

      // ── Organization ────────────────────────────────────────────────
    } else if (type == 'org_invitation' || type == 'org_announcement') {
      return '/notifications';

      // ── Emergency Fund ────────────────────────────────────────────
    } else if (type == 'emergency_fund_staked' ||
        type == 'emergency_fund_payment_success' ||
        type == 'emergency_fund_membership_active' ||
        type == 'emergency_fund_dsp_refunded') {
      return '/dsp/emergency-fund';
    } else {
      return '/notifications';
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

      final ref = _ref;
      if (ref == null) return;
      final router = ref.read(routerProvider);

      if (data['chatId'] != null) {
        unawaited(clearChatNotifications(data['chatId'].toString()));
      }

      final targetRoute = resolveTargetRouteForData(data);

      debugPrint('🔔 [TAP] Target route: $targetRoute');

      final currentUser = ref.read(authRepositoryProvider).currentUser;
      if (currentUser == null) {
        debugPrint('🔔 [TAP] User not logged in, queueing route: $targetRoute');
        ref.read(pendingNavigationProvider.notifier).setRoute(targetRoute);
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
        .limit(100)
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
        .limit(100)
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
        .limit(100)
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
        .limit(100)
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

    final hostName = await _lookupUserName(hostId, fallback: 'A host');

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

  /// Appends a message to the per-chat notification buffer and returns the
  /// ordered list of unread lines to render inside the single notification container.
  List<ChatNotificationLine> _appendChatNotificationMessage({
    required String containerKey,
    String? messageId,
    required String senderName,
    String? senderId,
    required String text,
    String? rawUnreadLinesJson,
  }) {
    final list = _chatNotificationMessages.putIfAbsent(
      containerKey,
      () => <ChatNotificationLine>[],
    );

    // If our in-memory buffer is empty (e.g. previous message(s) arrived while
    // the app was in the background) and the server provided unreadLines, seed
    // the earlier lines first so the foreground container includes all unread messages.
    if (list.isEmpty &&
        rawUnreadLinesJson != null &&
        rawUnreadLinesJson.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(rawUnreadLinesJson);
        if (decoded is List && decoded.length > 1) {
          final now = DateTime.now();
          for (var i = 0; i < decoded.length - 1; i++) {
            final lineText = decoded[i]?.toString().trim() ?? '';
            if (lineText.isNotEmpty) {
              list.add(
                ChatNotificationLine(
                  senderName: senderName,
                  senderId: senderId,
                  text: lineText,
                  timestamp: now.subtract(
                    Duration(seconds: decoded.length - i),
                  ),
                ),
              );
            }
          }
        }
      } catch (_) {}
    }

    if (messageId == null || !list.any((m) => m.messageId == messageId)) {
      list.add(
        ChatNotificationLine(
          messageId: messageId,
          senderName: senderName,
          senderId: senderId,
          text: text,
          timestamp: DateTime.now(),
        ),
      );
    }

    if (list.length > 7) {
      list.removeRange(0, list.length - 7);
    }

    return List<ChatNotificationLine>.unmodifiable(list);
  }

  /// Displays or updates the single notification container for a chat conversation,
  /// stacking all unread [lines] inside one notification card.
  Future<void> _showGroupedChatNotification({
    required int id,
    required String tag,
    required String title,
    required List<ChatNotificationLine> lines,
    required String payload,
    String? imageUrl,
  }) async {
    try {
      // Dismiss any native background FCM notification that was posted with id=0
      // and the same tag so we never have two separate containers in the tray.
      try {
        await _localNotifications.cancel(id: 0, tag: tag);
      } catch (_) {}

      StyleInformation? styleInformation;

      if (lines.length == 1 && imageUrl != null) {
        try {
          final String imagePath = await _downloadAndSaveFile(
            imageUrl,
            'notif_img_$id',
          );

          styleInformation = BigPictureStyleInformation(
            FilePathAndroidBitmap(imagePath),
            largeIcon: FilePathAndroidBitmap(imagePath),
            contentTitle: title,
            htmlFormatContentTitle: true,
            summaryText: lines.first.text,
            htmlFormatSummaryText: true,
          );
        } catch (e) {
          debugPrint('Error downloading notification image: $e');
        }
      }

      styleInformation ??= MessagingStyleInformation(
        Person(name: title, key: lines.last.senderId ?? tag),
        groupConversation: false,
        messages: lines
            .map(
              (line) => Message(
                line.text,
                line.timestamp,
                Person(
                  name: line.senderName.isNotEmpty ? line.senderName : title,
                  key: line.senderId ?? tag,
                ),
              ),
            )
            .toList(),
      );

      final combinedBody = lines.map((l) => l.text).join('\n');

      final AndroidNotificationDetails androidPlatformChannelSpecifics =
          AndroidNotificationDetails(
            'high_importance_channel',
            'High Importance Notifications',
            importance: Importance.max,
            priority: Priority.high,
            tag: tag,
            number: lines.length,
            subText: lines.length > 1 ? '${lines.length} messages' : null,
            styleInformation: styleInformation,
          );

      final NotificationDetails platformChannelSpecifics = NotificationDetails(
        android: androidPlatformChannelSpecifics,
        iOS: DarwinNotificationDetails(threadIdentifier: tag),
      );

      await _localNotifications.show(
        id: id,
        title: title,
        body: combinedBody,
        notificationDetails: platformChannelSpecifics,
        payload: payload,
      );
    } catch (e) {
      debugPrint('Error showing grouped chat notification: $e');
    }
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
          final String imagePath = await _downloadAndSaveFile(
            imageUrl,
            'notif_img_$id',
          );

          bigPictureStyleInformation = BigPictureStyleInformation(
            FilePathAndroidBitmap(imagePath),
            largeIcon: FilePathAndroidBitmap(imagePath),
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
    final key = '${userId}_$chatId';
    final cached = _mutedChatCache[key];
    if (cached != null) return cached;
    try {
      final doc = await _firestore
          .collection('users')
          .doc(userId)
          .collection('userChats')
          .doc(chatId)
          .get();
      final muted = doc.exists && doc.data()?['muted'] == true;
      _mutedChatCache[key] = muted;
      return muted;
    } catch (e) {
      debugPrint('Error checking mute status: $e');
      return false;
    }
  }

  /// Look up user's full name from their profile
  Future<String> _lookupUserName(
    String userId, {
    String fallback = 'A peer',
  }) async {
    final cachedProfile = _ref
        ?.read(profileRepositoryProvider)
        .getCachedProfile(userId);
    if (cachedProfile != null && cachedProfile.fullName.trim().isNotEmpty) {
      return cachedProfile.fullName.trim();
    }
    try {
      final userDoc = await _firestore.collection('users').doc(userId).get();
      if (userDoc.exists) {
        final data = userDoc.data();
        final first = data?['firstName'] as String? ?? '';
        final last = data?['lastName'] as String? ?? '';
        final combined = '$first $last'.trim();
        if (combined.isNotEmpty) {
          return combined;
        }
      }
    } catch (e) {
      debugPrint('❌ [PushNotificationService] Error looking up user name: $e');
    }
    return fallback;
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
        .limit(100)
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
    _travelerSessionStatusSubscription?.cancel();
    _hostSessionStatusSubscription?.cancel();

    // Track known statuses to detect changes
    final Map<String, String> knownStatuses = {};

    void handleSnapshot(QuerySnapshot<Map<String, dynamic>> snapshot) {
      for (final change in snapshot.docChanges) {
        final data = change.doc.data();
        if (data == null) continue;

        final travelerId = data['travelerId'] as String?;
        final hostId = data['hostId'] as String?;

        // Only process sessions where the current user is a participant
        if (travelerId != userId && hostId != userId) continue;

        final currentStatus = data['status'] as String? ?? 'unknown';
        final previousStatus = knownStatuses[change.doc.id];

        if (change.type == DocumentChangeType.added) {
          knownStatuses[change.doc.id] = currentStatus;
          continue;
        }

        // Only notify on actual status changes
        if (previousStatus == currentStatus) continue;
        knownStatuses[change.doc.id] = currentStatus;

        final travelerName = data['travelerName'] as String? ?? 'Traveler';
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

          case 'endRequested':
            // One party requested to end
            if (endRequestedBy != null && endRequestedBy != userId) {
              title = 'End Stay Requested';
              body =
                  '$otherPartyName has requested to end the hosting session in $communityName. '
                  'Please confirm to complete the session.';
            }
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
            actionRequired: currentStatus == 'endRequested',
            dedupKey: 'session_${change.doc.id}_$currentStatus',
          );
        }
      }
    }

    const activeStatuses = ['confirmed', 'active', 'endRequested', 'settled'];
    void onError(Object error) => debugPrint(
      '❌ [PushNotificationService] Error in session status listener: $error',
    );
    _travelerSessionStatusSubscription = _firestore
        .collection('hosting_sessions')
        .where('travelerId', isEqualTo: userId)
        .where('status', whereIn: activeStatuses)
        .limit(100)
        .snapshots()
        .listen(handleSnapshot, onError: onError);
    _hostSessionStatusSubscription = _firestore
        .collection('hosting_sessions')
        .where('hostId', isEqualTo: userId)
        .where('status', whereIn: activeStatuses)
        .limit(100)
        .snapshots()
        .listen(handleSnapshot, onError: onError);
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
        .limit(100)
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
        .limit(100)
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
        .where('attendees', arrayContains: userId)
        .limit(100)
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
        .limit(100)
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
        .where('toUserId', isEqualTo: userId)
        .limit(100)
        .snapshots()
        .listen(
          (snapshot) async {
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

                final verifierId = data['fromUserId'] as String?;
                final verifierName = verifierId != null
                    ? await _lookupUserName(verifierId, fallback: 'A peer')
                    : 'A peer';

                _showRichNotification(
                  id: 'trust_verify_$docId'.hashCode,
                  title: 'Identity Verified',
                  body:
                      '$verifierName has verified your identity. Your PCT score increased!',
                  payload: jsonEncode({
                    'type': 'trust_peer_verified',
                    'fromUserId': verifierId,
                  }),
                );

                _persistNotification(
                  type: NotificationType.trustPeerVerified,
                  title: 'Identity Verified',
                  body:
                      '$verifierName has verified your identity. Your PCT score increased!',
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
        .where('toUserId', isEqualTo: userId)
        .limit(100)
        .snapshots()
        .listen(
          (snapshot) async {
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

                final voucherId = data['fromUserId'] as String?;
                final voucherName = voucherId != null
                    ? await _lookupUserName(voucherId, fallback: 'A peer')
                    : 'A peer';

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
}
