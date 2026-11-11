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
          _chatNotificationMessages.clear();
          _processedMessageIds.clear();
        }
      });
    }

    // 6. Check Initial User (in case stream doesn't emit immediately or we missed it)
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser != null) {
      registerForUser(currentUser.uid);
    }
  }

  /// Called when user logs in.
  ///
  /// Engagement notifications (relationship requests, bookings, hosting,
  /// events, elections, trust) are delivered server-side via FCM by Cloud
  /// Functions (`functions/lib/engagement_notifications.js`), so they reach the
  /// user even when the app is closed. The client only needs a valid token.
  Future<void> registerForUser(
    String userId, {
    bool userInitiated = false,
  }) async {
    // Respect an explicit opt-out: automatic (app start / sign-in) registration
    // must not silently re-enable notifications the user turned off. Only the
    // settings toggle (userInitiated) may turn them back on.
    if (!userInitiated) {
      try {
        final privateDoc = await _firestore
            .collection('user_private')
            .doc(userId)
            .get();
        if (privateDoc.data()?['notificationsEnabled'] == false) {
          debugPrint(
            'PushNotificationService: Notifications disabled by user; skipping registration.',
          );
          return;
        }
      } catch (e) {
        debugPrint('PushNotificationService: Could not read opt-out state: $e');
      }
    }

    bool granted = false;
    try {
      granted = await requestPermission();
    } catch (e) {
      debugPrint('Error requesting notification permission: $e');
    }

    // Register the token after the permission prompt resolves: on iOS the
    // APNs token (required for an FCM token) only exists once permission has
    // been handled, so registering concurrently could silently save nothing.
    try {
      await registerFCMToken(userId);
    } catch (e) {
      debugPrint('Error registering FCM token: $e');
    }

    if (granted) {
      try {
        await subscribeToTopics(userId);
      } catch (e) {
        debugPrint('Error subscribing to topics: $e');
      }
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

    return settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;
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

    final bool isAiAgentSender =
        data['senderId']?.toString() == 'diaspora_ai_agent';
    if (!isAiAgentSender &&
        (rawType == 'dsp_transfer' ||
            rawType == 'points_update' ||
            msgType == 'dsp_transfer' ||
            msgType == 'points_update')) {
      debugPrint(
        '🔕 [PushNotificationService] Skipping DSP transfer/reward foreground notification (handled by backend or silenced)',
      );
      return;
    }

    // City-topic "new event" broadcasts also reach the organizer; don't
    // announce someone's own event back to them.
    if (rawType == 'event_new' && data['creatorId'] != null) {
      String? me = currentUserIdOverride ?? _activeUserId;
      try {
        me ??= FirebaseAuth.instance.currentUser?.uid;
      } catch (_) {}
      if (me != null && data['creatorId'].toString() == me) return;
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
        case 'voice_call':
          body = 'Voice call';
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
        msgType == 'voice_call' ||
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
      'voice_call',
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
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        // On iOS/macOS an FCM token can only be minted once APNs has issued
        // its device token, which may lag a moment behind the permission
        // prompt. Wait for it instead of failing silently.
        if (!kIsWeb && (Platform.isIOS || Platform.isMacOS)) {
          final apnsToken = await _fcm.getAPNSToken();
          if (apnsToken == null) {
            await Future<void>.delayed(Duration(seconds: 2 * (attempt + 1)));
            continue;
          }
        }
        final token = await _fcm.getToken(
          vapidKey: kIsWeb ? _webVapidKey : null,
        );
        if (token != null) {
          debugPrint(
            'PushNotificationService: Obtained FCM token, saving to Firestore...',
          );
          await _saveTokenToFirestore(userId, token);
          return;
        }
        debugPrint('PushNotificationService: FCM token was null');
      } catch (e) {
        debugPrint('PushNotificationService: Failed to get FCM token: $e');
      }
      await Future<void>.delayed(Duration(seconds: 2 * (attempt + 1)));
    }
  }

  /// Save token to Firestore
  Future<void> _saveTokenToFirestore(String userId, String token) async {
    await _firestore.collection('user_private').doc(userId).set({
      'fcmToken': token,
      'fcmTokenUpdatedAt': FieldValue.serverTimestamp(),
      'fcmTokenRevoked': false,
      'fcmPlatform': kIsWeb ? 'web' : Platform.operatingSystem,
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

    // Server-provided deep link (engagement notifications set this explicitly).
    final explicitRoute = data['route']?.toString().trim();
    if (explicitRoute != null &&
        explicitRoute.startsWith('/') &&
        !explicitRoute.startsWith('//')) {
      return explicitRoute;
    }

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
    } else if (type == 'proximity_reward') {
      if (data['userId'] != null && data['userId'].toString().isNotEmpty) {
        return '/profile/${data['userId']}';
      }
      return '/dsp/points';
    } else if (type == 'grassroots_gathering_reward') {
      if (data['eventId'] != null && data['eventId'].toString().isNotEmpty) {
        return '/events/${data['eventId']}';
      }
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
            type == 'hosting_interest' ||
            type == 'hosting_request_new') &&
        data['requestId'] != null) {
      return '/hosting/request/${data['requestId']}';
    } else if (type == 'hosting_session_chat' && data['chatId'] != null) {
      return '/chats/${data['chatId']}';
    } else if (type == 'hosting_session') {
      return '/communities';

      // ── Travel / Peer Bookings ──────────────────────────────────────
    } else if ((type == 'travel_booking_request' ||
            type == 'travel_booking_confirmed' ||
            type == 'travel_booking_declined' ||
            type == 'travel_booking_cancelled' ||
            type == 'travel_booking_completed' ||
            type == 'travel_trip_reminder') &&
        data['chatId'] != null &&
        data['chatId'].toString().isNotEmpty) {
      return '/chats/${data['chatId']}';
    } else if (type == 'travel_booking_request' ||
        type == 'travel_booking_confirmed' ||
        type == 'travel_booking_declined' ||
        type == 'travel_booking_cancelled' ||
        type == 'travel_booking_completed' ||
        type == 'travel_trip_reminder') {
      return '/dsp/travel/stays';

      // ── Events ──────────────────────────────────────────────────────
    } else if ((type == 'event_new' ||
            type == 'event_update' ||
            type == 'event_cancelled' ||
            type == 'event_new_attendee' ||
            type == 'event_checkin' ||
            type == 'eventNew' ||
            type == 'eventUpdate' ||
            type == 'eventCancelled') &&
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
      final communityId = data['communityId']?.toString();
      if (communityId != null && communityId.isNotEmpty) {
        return '/communities/$communityId';
      }
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
        type == 'trust_qr_connected' ||
        type == 'referral_joined' ||
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
}
