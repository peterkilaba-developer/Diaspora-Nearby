import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/foundation.dart';
import 'dart:convert';

class MentionMonitorService {
  static final MentionMonitorService _instance =
      MentionMonitorService._internal();
  factory MentionMonitorService() => _instance;
  MentionMonitorService._internal();

  late final FirebaseFirestore _firestore;
  late final FirebaseAuth _auth;
  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  StreamSubscription? _subscription;
  bool _isInitialized = false;

  Future<void> initialize() async {
    if (_isInitialized) return;

    _firestore = FirebaseFirestore.instance;
    _auth = FirebaseAuth.instance;

    _startListening();
    _isInitialized = true;
    debugPrint('✅ MentionMonitorService initialized');
  }

  void _startListening() {
    _auth.authStateChanges().listen((user) {
      _subscription?.cancel();
      if (user != null) {
        debugPrint(
          '🎧 MentionMonitorService: Listening for mentions for ${user.uid}',
        );
        _listenToUserChats(user.uid);
      }
    });
  }

  void _listenToUserChats(String userId) {
    final userChatsRef = _firestore
        .collection('users')
        .doc(userId)
        .collection('userChats');

    // Listen for changes to userChats
    _subscription = userChatsRef.snapshots().listen((snapshot) {
      for (final change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.modified ||
            change.type == DocumentChangeType.added) {
          _checkAndNotify(change.doc, userId);
        }
      }
    });
  }

  Future<void> _checkAndNotify(
    DocumentSnapshot<Map<String, dynamic>> doc,
    String userId,
  ) async {
    try {
      if (!doc.exists) return;
      final data = doc.data();
      if (data == null) return;

      final chatId = doc.id;

      // key fields
      final unreadCount = data['unreadCount'];

      bool hasUnread = false;
      if (unreadCount is int && unreadCount > 0) hasUnread = true;
      if (unreadCount is double && unreadCount > 0) hasUnread = true;

      if (!hasUnread) return;

      final lastMessage = data['lastMessage'];
      if (lastMessage is! Map) return;

      final messageData = Map<String, dynamic>.from(lastMessage);
      final rawMentions = messageData['mentions'];

      bool isMentioned = false;

      // Check Map format {uid: true}
      if (rawMentions is Map) {
        if (rawMentions.containsKey(userId)) isMentioned = true;
      }
      // Check List format [uid]
      else if (rawMentions is List) {
        if (rawMentions.contains(userId)) isMentioned = true;
      }

      if (isMentioned) {
        final senderName =
            (messageData['senderName']?.toString().trim().isNotEmpty ?? false)
            ? messageData['senderName']
            : 'Someone';
        final content =
            (messageData['content']?.toString().trim().isNotEmpty ?? false)
            ? messageData['content']
            : 'Sent a message';

        // Fetch Chat Name for "Mention in [Community Name]"
        String chatName = 'Chat';
        try {
          final chatDoc = await _firestore
              .collection('chats')
              .doc(chatId)
              .get();
          if (chatDoc.exists) {
            chatName = chatDoc.data()?['name']?.toString() ?? 'Chat';
          }
        } catch (e) {
          debugPrint('Error fetching chat name: $e');
        }

        debugPrint(
          '🔔 MentionMonitorService: TRIGGERING LOCAL NOTIFICATION for $chatId',
        );

        String cleanContent = content
            .toString()
            .replaceAll('You were mentioned: ', '')
            .trim();

        await _showNotification(
          id: chatId.hashCode,
          title: 'Mention in $chatName',
          body: '@$senderName mentioned you: $cleanContent',
          payload: jsonEncode({
            'type': 'group_mention',
            'route': '/chat/$chatId',
            'chatId': chatId,
          }),
        );
      }
    } catch (e) {
      debugPrint('⚠️ MentionMonitorService error: $e');
    }
  }

  Future<void> _showNotification({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    const AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
          'high_importance_channel',
          'High Importance Notifications',
          channelDescription:
              'This channel is used for important notifications.',
          importance: Importance.max,
          priority: Priority.high,
          showWhen: true,
        );
    const NotificationDetails platformChannelSpecifics = NotificationDetails(
      android: androidPlatformChannelSpecifics,
    );

    await _notificationsPlugin.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: platformChannelSpecifics,
      payload: payload,
    );
  }
}
