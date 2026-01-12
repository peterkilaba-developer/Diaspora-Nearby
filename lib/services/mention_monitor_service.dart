import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/foundation.dart';
import 'dart:convert';

class MentionMonitorService {
  static final MentionMonitorService _instance = MentionMonitorService._internal();
  factory MentionMonitorService() => _instance;
  MentionMonitorService._internal();

  final FirebaseDatabase _rtdb = FirebaseDatabase.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();
  
  StreamSubscription? _subscription;
  bool _isInitialized = false;

  Future<void> initialize() async {
    if (_isInitialized) return;
    
    // Note: LocalNotificationsPlugin is initialized in PushNotificationService (Main Isolate)
    // We rely on that initialization to handle onDidReceiveNotificationResponse.
    
    _startListening();
    _isInitialized = true;
    debugPrint('✅ MentionMonitorService initialized');
  }

  void _startListening() {
    _auth.authStateChanges().listen((user) {
      _subscription?.cancel();
      if (user != null) {
        debugPrint('🎧 MentionMonitorService: Listening for mentions for ${user.uid}');
        _listenToUserChats(user.uid);
      }
    });
  }

  void _listenToUserChats(String userId) {
    final ref = _rtdb.ref('userChats/$userId');
    
    // Listen for CHANGED children (updates to existing chats)
    _subscription = ref.onChildChanged.listen((event) {
        _checkAndNotify(event, userId);
    });
    
    // Also listen for ADDED children (new chats)
    ref.onChildAdded.listen((event) {
         _checkAndNotify(event, userId);
    });
  }

  Future<void> _checkAndNotify(DatabaseEvent event, String userId) async {
    try {
      if (!event.snapshot.exists || event.snapshot.value == null) return;
      
      final data = Map<String, dynamic>.from(event.snapshot.value as Map);
      final chatId = event.snapshot.key;
      
      // key fields
      final unreadCount = data['unreadCount'];
      
      // If unread count is 0, user likely just read it or it's not new.
      // However, for a *new* mention, unreadCount should be >= 1.
      // We can be strict: only notify if unreadCount > 0
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
         // Prevent duplicate notifications? 
         // RTDB onChildChanged fires once per update.
         // We might trigger multiple times if they spam updates, but usually ok.
         
         final senderName = messageData['senderName'] ?? 'Someone';
         final content = messageData['content'] ?? 'Sent a message';
         
         // Fetch Chat Name for "Mention in [Community Name]"
         String chatName = 'Chat'; // Default
         try {
           final chatSnapshot = await _rtdb.ref('chats/$chatId/name').get();
           if (chatSnapshot.exists && chatSnapshot.value != null) {
              chatName = chatSnapshot.value.toString();
           } else {
             // Fallback: Try to guess or use generic if name missing 
             // (e.g. DM might not have name, use Sender? But user asked for Community Name)
             // For DMs, usually name is null or empty in 'chats' node typically? 
             // Let's check type.
             // If generic, use "Mention in Chat"
           }
         } catch (e) {
           debugPrint('Error fetching chat name: $e');
         }

         debugPrint('🔔 MentionMonitorService: TRIGGERING LOCAL NOTIFICATION for $chatId');
         
         // Format: "@[user name] mentioned you: [content]"
         // Note: content usually is "@[my name] message..." already
         // So we format: "@$senderName mentioned you: $content"
         
         // Clean content of any legacy "You were mentioned: " prefix just in case
         String cleanContent = content.toString().replaceAll('You were mentioned: ', '').trim();
         
         await _showNotification(
             id: chatId.hashCode, // Unique ID per chat
             title: 'Mention in $chatName', 
             body: '@$senderName mentioned you: $cleanContent',
             // [FIX] Add 'type' so PushNotificationService routing works
             payload: jsonEncode({'type': 'group_mention', 'route': '/chat/$chatId', 'chatId': chatId}),
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
      'high_importance_channel', // [FIX] Use shared channel ID
      'High Importance Notifications', 
      channelDescription: 'This channel is used for important notifications.',
      importance: Importance.max,
      priority: Priority.high,
      showWhen: true,
    );
    const NotificationDetails platformChannelSpecifics =
        NotificationDetails(android: androidPlatformChannelSpecifics);
        
    await _notificationsPlugin.show(
      id,
      title,
      body,
      platformChannelSpecifics,
      payload: payload,
    );
  }
}
