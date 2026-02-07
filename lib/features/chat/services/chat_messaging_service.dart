import 'package:universal_io/io.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/message.dart';

import 'package:diaspora_nearby/features/dsp/services/points_service.dart'; // [NEW]

// Provider definition
final chatMessagingServiceProvider = Provider<ChatMessagingService>((ref) {
  return ChatMessagingService(
    pointsService: ref.read(pointsServiceProvider), // [NEW]
  );
});

class ChatMessagingService {
  final FirebaseDatabase _rtdb;
  final FirebaseStorage _storage;
  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final PointsService _pointsService; // [NEW]

  ChatMessagingService({
    FirebaseDatabase? rtdb,
    FirebaseStorage? storage,
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    required PointsService pointsService, // [NEW]
  }) : _rtdb = rtdb ?? FirebaseDatabase.instance,
       _storage = storage ?? FirebaseStorage.instance,
       _firestore = firestore ?? FirebaseFirestore.instance,
       _auth = auth ?? FirebaseAuth.instance,
       _pointsService = pointsService;

  String? get currentUserId => _auth.currentUser?.uid;

  // ============================================
  // TEXT MESSAGING
  // ============================================

  Future<Message?> sendTextMessage(
    String chatId,
    String content, {
    String? replyToMessageId,
    String? senderIdOverride,
    String? senderNameOverride,
    String? senderImageOverride,

    List<String>? participants,
    List<String>? mentions,
    String? richContent,
    String? replyToSenderId, // [NEW] Notification target for replies
    String type = 'text',
    Map<String, dynamic>? metadata,
  }) async {
    if (currentUserId == null) return null;

    final now = DateTime.now().millisecondsSinceEpoch;

    // Fetch sender data (could be cached or passed in, but fetching ensures freshness)
    final userDoc = await _firestore
        .collection('users')
        .doc(currentUserId)
        .get();
    final userData = userDoc.data();

    final firstName = userData?['firstName'] as String? ?? '';
    final lastName = userData?['lastName'] as String? ?? '';
    final profileImage = userData?['profileImage'] as String?;
    final hostCountryCode = userData?['hostCountryCode'] as String?;
    final homeCountryCode = userData?['homeCountryCode'] as String?;

    final fullName = '$firstName $lastName'.trim();
    final senderName = senderNameOverride ?? (fullName.isNotEmpty ? fullName : 'Someone');

    final messageData = {
      'senderId': senderIdOverride ?? currentUserId,
      'senderName': senderName,
      'senderImage': senderImageOverride ?? profileImage,
      'senderHostCountryCode': hostCountryCode,
      'senderHomeCountryCode': homeCountryCode,
      'content': content, 

      'type': type, // [FIX] Use passed type (default 'text')
      'timestamp': now,
      'status': 'sent',
      'status': 'sent',
      if (mentions != null) 'mentions': mentions,
      if (richContent != null) 'richContent': richContent,
      if (richContent != null) 'richContent': richContent,
      if (metadata != null) 'metadata': metadata, // [NEW]
    };

    if (replyToMessageId != null) {
      messageData['replyTo'] = replyToMessageId;
    }

    if (senderIdOverride != null) {
      messageData['adminId'] = currentUserId;
      messageData['adminImage'] = profileImage;
    }

    // ...

    try {
      final messagesRef = _rtdb.ref('chats/$chatId/messages');
      final newMessageRef = messagesRef.push();

      await newMessageRef.set(messageData);

      // We still use cleanContent for the general chat lastMessage if possible,
      // but for userChats (notifications) we might need raw.
      // Actually, let's use raw for everything to be safe and consistent.

      await _rtdb.ref('chats/$chatId/lastMessage').set({
        'id': newMessageRef.key, // [NEW] Save Message ID
        'content': content,
        'timestamp': now,
        'senderId': senderIdOverride ?? currentUserId,
        'senderName': senderName,
        'type': type,
        'status': 'sent',
        if (metadata != null) 'metadata': metadata, // [NEW]
      });
      await _rtdb.ref('chats/$chatId/updatedAt').set(now);

      var targetParticipants = participants;
      debugPrint(
        '📤 sendTextMessage: Initial participants: $targetParticipants',
      );

      if (targetParticipants == null || targetParticipants.isEmpty) {
        debugPrint('⚠️ Participants missing. Fetching from RTDB...');
        final chatSnapshot = await _rtdb.ref('chats/$chatId').get();
        if (chatSnapshot.exists && chatSnapshot.value is Map) {
          final chatData = Map<String, dynamic>.from(chatSnapshot.value as Map);
          final rawParticipants = chatData['participants'];
          if (rawParticipants is List) {
            targetParticipants = rawParticipants
                .map((e) => e.toString())
                .toList();
          } else if (rawParticipants is Map) {
            if (rawParticipants.isEmpty) {
              targetParticipants = [];
            } else {
              final firstVal = rawParticipants.values.first;
              if (firstVal is bool || (firstVal is num && firstVal == 1)) {
                targetParticipants = rawParticipants.keys
                    .map((e) => e.toString())
                    .toList();
              } else {
                targetParticipants = rawParticipants.values
                    .map((e) => e.toString())
                    .toList();
              }
            }
          } else {
            targetParticipants = [];
          }
          debugPrint('✅ Fetched participants: $targetParticipants');
        } else {
          debugPrint('❌ Failed to fetch chat data for participant fallback.');
        }
      }

      final Set<String> allTargets = {};
      if (targetParticipants != null) allTargets.addAll(targetParticipants);

      // [NEW] Explicitly add mentioned users to targets to ensure they get notifications
      // even if not in the loaded participants list (optimistic/community chats)
      if (mentions != null) {
        allTargets.addAll(mentions);
      }

      // [NEW] Explicitly add reply target
      if (replyToSenderId != null) {
        allTargets.add(replyToSenderId);
      }

      if (senderIdOverride != null) {
        allTargets.add(senderIdOverride);
      } else if (currentUserId != null)
        allTargets.add(currentUserId!);

      debugPrint('🎯 [DEBUG] sendTextMessage: Targets: $allTargets');
      if (mentions != null) {
        debugPrint('🎯 [DEBUG] sendTextMessage: Mentions: $mentions');
      }

      for (final userId in allTargets) {
        try {
          // [FIX] REVISED: Use standard 'text' type to ensure delivery (like DMs)
          // We removed the 'You were mentioned:' prefix here to handle it purely in MentionMonitorService
          // and avoid double prefixes or dirty data in the chat list.
          String userSpecificContent = content;

          // [NEW] Customize notification/preview text for DSP transfers
          if (type == 'dsp_transfer') {
            final isSender = userId == (senderIdOverride ?? currentUserId);
            final userData = userDoc.data();
            final firstName = userData?['firstName'] as String? ?? '';
            final lastName = userData?['lastName'] as String? ?? '';
            final senderName =
                senderNameOverride ?? '$firstName $lastName'.trim();

            final amount = metadata?['amount'] ?? 0;
            final baseText = isSender
                ? 'You sent $amount DSP'
                : 'You received $amount DSP from $senderName';

            // If there is a caption (and it's not the fallback text we used in ChatScreen)
            // Note: userSpecificContent currently holds the 'content' passed from ChatScreen.
            // In ChatScreen we passed `caption ?? ''`.
            // So if caption is empty, content is empty.
            // [FIX] User requested to show ONLY system message in chat card, not caption
            userSpecificContent = baseText;
          }

          final messageType = type; // Use actual type

          debugPrint('   -> Updating userChats/$userId/$chatId');

          await _rtdb.ref('userChats/$userId/$chatId').update({
            'chatId': chatId, // [NEW] Store chatId explicitly for listeners
            'lastMessage': {
              'id': newMessageRef.key, // [FIX] ID required for deduplication
              'content': userSpecificContent,
              'timestamp': now,
              'senderId': senderIdOverride ?? currentUserId,
              'senderName': senderName,
              'type': messageType,
              'status': 'sent',
              if (mentions != null) 'mentions': mentions,
              if (metadata != null) 'metadata': metadata, // [NEW]
            },
            'updatedAt': now,
            'isDeleted': null, // [NEW] Revive chat if deleted
            if (userId != currentUserId)
              'unreadCount': ServerValue.increment(1),
          });
          debugPrint('   -> [SUCCESS] Updated userChats for $userId');
        } catch (e) {
          debugPrint('❌ Error updating userChat for $userId: $e');
        }
      }

      // [NEW] Track Engagement Reward
      // Fire and forget, don't await blocking return
      if (senderIdOverride == null) {
        // Only reward real user actions, not system sends
        _pointsService.trackMessageSent(currentUserId!);
      }

      // Convert RTDB data to Message object
      return Message.fromRTDB(newMessageRef.key!, chatId, messageData);
    } catch (e) {
      debugPrint('Error sending text message: $e');
      return null;
    }
  }

  Future<void> sendGroupInvitation(
    String groupId,
    String groupName,
    List<String> invitedUserIds,
  ) async {
    if (currentUserId == null) return;

    final userDoc =
        await _firestore.collection('users').doc(currentUserId).get();
    final userData = userDoc.data();
    final senderName =
        '${userData?['firstName'] ?? ''} ${userData?['lastName'] ?? ''}'.trim();
    // Req: "[sender full] invites you to join group: [group name]"
    final content = '$senderName invites you to join group: $groupName';

    final now = DateTime.now().millisecondsSinceEpoch;

    for (final userId in invitedUserIds) {
      try {
        await _rtdb.ref('userChats/$userId/$groupId').update({
          'chatId': groupId, // [NEW] Store chatId
          'lastMessage': {
            'content': content,
            'timestamp': now,
            'senderId': currentUserId,
            'senderName': senderName.isNotEmpty ? senderName : 'Someone',
            'type': 'group_invitation',
            'status': 'sent',
            'metadata': {
              'inviterId': currentUserId,
              'inviterName': senderName,
              'groupName': groupName,
            },
          },
          'updatedAt': now,
          'unreadCount': ServerValue.increment(1),
          'isDeleted': null,
        });
      } catch (e) {
        debugPrint('Error sending invitation to $userId: $e');
      }
    }
  }

  Future<Message?> forwardMessage(
    String targetChatId,
    Message originalMessage, {
    String? senderIdOverride,
    String? senderNameOverride,
    String? senderImageOverride,
    List<String>? participants,
  }) async {
    if (currentUserId == null) return null;

    final now = DateTime.now().millisecondsSinceEpoch;

    // Fetch sender data
    final userDoc = await _firestore
        .collection('users')
        .doc(currentUserId)
        .get();
    final userData = userDoc.data();

    final firstName = userData?['firstName'] as String? ?? '';
    final lastName = userData?['lastName'] as String? ?? '';
    final profileImage = userData?['profileImage'] as String?;
    final hostCountryCode = userData?['hostCountryCode'] as String?;
    final homeCountryCode = userData?['homeCountryCode'] as String?;

    final messageData = {
      'senderId': senderIdOverride ?? currentUserId,
      'senderName': senderNameOverride ?? '$firstName $lastName'.trim(),
      'senderImage': senderImageOverride ?? profileImage,
      'senderHostCountryCode': hostCountryCode,
      'senderHomeCountryCode': homeCountryCode,
      'content': originalMessage.content,
      'type': originalMessage.type,
      'timestamp': now,
      'status': 'sent',
      'forwarded': true,
      'originalSenderId':
          originalMessage.originalSenderId ?? originalMessage.senderId,
      'originalSenderName':
          originalMessage.originalSenderName ?? originalMessage.senderName,
      'originalSenderImage':
          originalMessage.originalSenderImage ?? originalMessage.senderImage,
      'originalSenderHostCountryCode':
          originalMessage.originalSenderHostCountryCode ??
          originalMessage.senderHostCountryCode,
      'originalSenderHomeCountryCode':
          originalMessage.originalSenderHomeCountryCode ??
          originalMessage.senderHomeCountryCode,
      'originalTimestamp':
          originalMessage.originalTimestamp ?? originalMessage.timestamp,
    };

    // Copy media fields
    if (originalMessage.imageUrl != null) {
      messageData['imageUrl'] = originalMessage.imageUrl;
    }
    if (originalMessage.documentUrl != null) {
      messageData['documentUrl'] = originalMessage.documentUrl;
    }
    if (originalMessage.documentName != null) {
      messageData['documentName'] = originalMessage.documentName;
    }
    if (originalMessage.documentSize != null) {
      messageData['documentSize'] = originalMessage.documentSize;
    }
    if (originalMessage.audioDuration != null) {
      messageData['audioDuration'] = originalMessage.audioDuration;
    }
    if (originalMessage.location != null) {
      messageData['location'] = {
        'latitude': originalMessage.location!.lat,
        'longitude': originalMessage.location!.lng,
        'address': originalMessage.location!.address,
      };
    }

    if (senderIdOverride != null) {
      messageData['adminId'] = currentUserId;
      messageData['adminImage'] = profileImage;
    }

    try {
      final messagesRef = _rtdb.ref('chats/$targetChatId/messages');
      final newMessageRef = messagesRef.push();

      await newMessageRef.set(messageData);

      // Update lastMessage
      String lastMessageContent = originalMessage.content;
      if (lastMessageContent.isEmpty) {
        lastMessageContent = _getMessageTypeLabel(originalMessage.type);
      }

      await _rtdb.ref('chats/$targetChatId/lastMessage').set({
        'id': newMessageRef.key, // [NEW] ID
        'content': lastMessageContent,
        'timestamp': now,
        'senderId': senderIdOverride ?? currentUserId,
        'senderName': senderNameOverride ?? '$firstName $lastName'.trim(),
        'type': originalMessage.type,
        'status': 'sent',
      });
      await _rtdb.ref('chats/$targetChatId/updatedAt').set(now);

      var targetParticipants = participants;
      if (targetParticipants == null || targetParticipants.isEmpty) {
        final chatSnapshot = await _rtdb.ref('chats/$targetChatId').get();
        if (chatSnapshot.exists && chatSnapshot.value != null) {
          final chatData = Map<String, dynamic>.from(chatSnapshot.value as Map);
          targetParticipants = List<String>.from(
            chatData['participants'] ?? [],
          );
        }
      }

      if (targetParticipants != null) {
        for (final userId in targetParticipants) {
          try {
            await _rtdb.ref('userChats/$userId/$targetChatId').update({
              'lastMessage': {
                'id': newMessageRef.key, // [NEW] ID
                'content': lastMessageContent,
                'timestamp': now,
                'senderId': senderIdOverride ?? currentUserId,
                'senderName':
                    senderNameOverride ?? '$firstName $lastName'.trim(),
                'type': originalMessage.type,
                'status': 'sent',
              },
              'updatedAt': now,
              'isDeleted': null, // [NEW] Revive chat
              if (userId != currentUserId)
                'unreadCount': ServerValue.increment(1),
            });
          } catch (e) {
            debugPrint('Error updating userChat for $userId: $e');
          }
        }
      }

      return Message.fromRTDB(newMessageRef.key!, targetChatId, messageData);
    } catch (e) {
      debugPrint('Error forwarding message: $e');
      return null;
    }
  }

  String _getMessageTypeLabel(String type) {
    switch (type) {
      case 'image':
        return 'Photo';
      case 'video':
        return 'Video';
      case 'audio':
        return 'Voice message';
      case 'audio_file':
        return 'Audio';
      case 'location':
        return 'Location';
      case 'document':
        return 'Document';
      default:
        return 'Forwarded message';
    }
  }

  // ============================================
  // MEDIA MESSAGING
  // ============================================

  Future<Message?> sendImageMessage(
    String chatId,
    XFile imageFile, {
    String? caption,
    String? replyToMessageId,
    void Function(Message confirmedMessage)? onConfirmed,
    void Function(String error)? onError,
    String? senderIdOverride,
    String? senderNameOverride,
    String? senderImageOverride,
    List<String>? participants,
    String? replyToSenderId,
    Map<String, dynamic>? metadata, // [NEW]
  }) async {
    if (currentUserId == null) return null;

    final now = DateTime.now().millisecondsSinceEpoch;
    final tempId = 'pending_${now}_$currentUserId';

    final userDoc = await _firestore
        .collection('users')
        .doc(currentUserId)
        .get();
    final userData = userDoc.data();
    final firstName = userData?['firstName'] as String? ?? '';
    final lastName = userData?['lastName'] as String? ?? '';
    final profileImage = userData?['profileImage'] as String?;

    final optimisticMessage = Message(
      id: tempId,
      chatId: chatId,
      senderId: senderIdOverride ?? currentUserId!,
      senderName: senderNameOverride ?? '$firstName $lastName'.trim(),
      senderImage: senderImageOverride ?? profileImage,
      content: caption?.trim() ?? '',
      type: 'image',
      imageUrl: imageFile.path,
      timestamp: now,
      status: 'sending',
      replyTo: replyToMessageId,
      adminId: senderIdOverride != null ? currentUserId : null,
      adminImage: senderIdOverride != null ? profileImage : null,
      metadata: metadata, // [NEW]
    );

    await _uploadMediaAsync(
      chatId: chatId,
      file: imageFile,
      type: 'image',
      caption: caption,
      now: now,
      metadata: metadata, // [NEW]
      senderData: userData,
      replyToMessageId: replyToMessageId,
      tempId: tempId,
      onConfirmed: onConfirmed,
      onError: onError,
      senderIdOverride: senderIdOverride,
      senderNameOverride: senderNameOverride,
      senderImageOverride: senderImageOverride,
      participants: participants,
      replyToSenderId: replyToSenderId,
    );

    return optimisticMessage;
  }

  Future<Message?> sendVideoMessage(
    String chatId,
    XFile videoFile, {
    String? caption,
    String? replyToMessageId,
    void Function(Message confirmedMessage)? onConfirmed,
    void Function(String error)? onError,
    String? senderIdOverride,
    String? senderNameOverride,
    String? senderImageOverride,
    List<String>? participants,
    String? replyToSenderId,
    Map<String, dynamic>? metadata, // [NEW]
  }) async {
    if (currentUserId == null) throw Exception('User not logged in');
    final now = DateTime.now().millisecondsSinceEpoch;
    final tempId = 'pending_video_${now}_$currentUserId';

    final userDoc = await _firestore
        .collection('users')
        .doc(currentUserId)
        .get();
    final userData = userDoc.data();
    final firstName = userData?['firstName'] as String? ?? '';
    final lastName = userData?['lastName'] as String? ?? '';
    final profileImage = userData?['profileImage'] as String?;

    final optimisticMessage = Message(
      id: tempId,
      chatId: chatId,
      senderId: senderIdOverride ?? currentUserId!,
      senderName: senderNameOverride ?? '$firstName $lastName'.trim(),
      senderImage: senderImageOverride ?? profileImage,
      content: caption?.trim() ?? '',
      type: 'video',
      documentUrl: videoFile.path, // Temporary mapping
      timestamp: now,
      status: 'sending',
      replyTo: replyToMessageId,
      adminId: senderIdOverride != null ? currentUserId : null,
      adminImage: senderIdOverride != null ? profileImage : null,
      metadata: metadata, // [NEW]
    );

    await _uploadMediaAsync(
      chatId: chatId,
      file: videoFile,
      type: 'video',
      caption: caption,
      now: now,
      metadata: metadata, // [NEW]
      senderData: userData,
      replyToMessageId: replyToMessageId,
      tempId: tempId,
      onConfirmed: onConfirmed,
      onError: onError,
      senderIdOverride: senderIdOverride,
      senderNameOverride: senderNameOverride,
      senderImageOverride: senderImageOverride,
      participants: participants,
      replyToSenderId: replyToSenderId,
    );

    return optimisticMessage;
  }

  Future<Message?> sendAudioMessage(
    String chatId,
    XFile audioFile, {
    int? durationSeconds,
    String? caption,
    String? replyToMessageId,
    void Function(Message confirmedMessage)? onConfirmed,
    void Function(String error)? onError,
    String? senderIdOverride,
    String? senderNameOverride,
    String? senderImageOverride,
    List<String>? participants,
    String messageType = 'audio',
    String? replyToSenderId,
    Map<String, dynamic>? metadata, // [NEW]
  }) async {
    if (currentUserId == null) return null;
    final now = DateTime.now().millisecondsSinceEpoch;
    final tempId = 'pending_voice_${now}_$currentUserId';

    final userDoc = await _firestore
        .collection('users')
        .doc(currentUserId)
        .get();
    final userData = userDoc.data();
    final firstName = userData?['firstName'] as String? ?? '';
    final lastName = userData?['lastName'] as String? ?? '';
    final profileImage = userData?['profileImage'] as String?;

    final optimisticMessage = Message(
      id: tempId,
      chatId: chatId,
      senderId: senderIdOverride ?? currentUserId!,
      senderName: senderNameOverride ?? '$firstName $lastName'.trim(),
      senderImage: senderImageOverride ?? profileImage,
      content: caption?.trim() ?? '',
      type: messageType, // Use dynamic type
      documentUrl: audioFile.path,
      audioDuration: durationSeconds,
      timestamp: now,
      status: 'sending',
      replyTo: replyToMessageId,
      adminId: senderIdOverride != null ? currentUserId : null,
      adminImage: senderIdOverride != null ? profileImage : null,
      metadata: metadata, // [NEW]
    );

    await _uploadMediaAsync(
      chatId: chatId,
      file: audioFile,
      type: messageType, // Use dynamic type
      caption: caption,
      now: now,
      metadata: metadata, // [NEW]
      senderData: userData,
      duration: durationSeconds,
      replyToMessageId: replyToMessageId,
      tempId: tempId,
      onConfirmed: onConfirmed,
      onError: onError,
      senderIdOverride: senderIdOverride,
      senderNameOverride: senderNameOverride,
      senderImageOverride: senderImageOverride,
      participants: participants,
      replyToSenderId: replyToSenderId,
    );

    return optimisticMessage;
  }

  Future<Message?> sendAudioFileMessage(
    String chatId,
    XFile audioFile, {
    String? caption,
    String? replyToMessageId,
    String? senderIdOverride,
    String? senderNameOverride,
    String? senderImageOverride,
    List<String>? participants,
    String? replyToSenderId,
    Map<String, dynamic>? metadata, // [NEW]
  }) async {
    return sendAudioMessage(
      chatId,
      audioFile,
      caption: caption,
      replyToMessageId: replyToMessageId,
      senderIdOverride: senderIdOverride,
      senderNameOverride: senderNameOverride,
      senderImageOverride: senderImageOverride,
      participants: participants,
      messageType: 'audio_file',
      replyToSenderId: replyToSenderId,
      metadata: metadata, // [NEW]
    );
  }

  Future<Message?> sendDocumentMessage(
    String chatId,
    XFile file, {
    String? caption,
    String? replyToMessageId,
    void Function(Message confirmedMessage)? onConfirmed,
    void Function(String error)? onError,
    String? senderIdOverride,
    String? senderNameOverride,
    String? senderImageOverride,
    List<String>? participants,
    String? replyToSenderId,
    Map<String, dynamic>? metadata, // [NEW]
  }) async {
    if (currentUserId == null) throw Exception('User not logged in');
    final now = DateTime.now().millisecondsSinceEpoch;
    final tempId = 'pending_doc_${now}_$currentUserId';

    final userDoc = await _firestore
        .collection('users')
        .doc(currentUserId)
        .get();
    final userData = userDoc.data();
    final firstName = userData?['firstName'] as String? ?? '';
    final lastName = userData?['lastName'] as String? ?? '';
    final profileImage = userData?['profileImage'] as String?;

    final optimisticMessage = Message(
      id: tempId,
      chatId: chatId,
      senderId: senderIdOverride ?? currentUserId!,
      senderName: senderNameOverride ?? '$firstName $lastName'.trim(),
      senderImage: senderImageOverride ?? profileImage,
      content: caption?.trim() ?? '',
      type: 'document',
      documentUrl: file.path,
      timestamp: now,
      status: 'sending',
      replyTo: replyToMessageId,
      adminId: senderIdOverride != null ? currentUserId : null,
      adminImage: senderIdOverride != null ? profileImage : null,
      metadata: metadata, // [NEW]
    );

    await _uploadMediaAsync(
      chatId: chatId,
      file: file,
      type: 'document',
      caption: caption,
      now: now,
      metadata: metadata, // [NEW]

      senderData: userData,
      replyToMessageId: replyToMessageId,
      tempId: tempId,
      onConfirmed: onConfirmed,
      onError: onError,
      senderIdOverride: senderIdOverride,
      senderNameOverride: senderNameOverride,
      senderImageOverride: senderImageOverride,

      participants: participants,
      replyToSenderId: replyToSenderId,
    );

    return optimisticMessage;
  }

  Future<Message?> sendLocationMessage(
    String chatId, {
    required double latitude,
    required double longitude,
    String? address,
    String? replyToMessageId,
    String? senderIdOverride,
    String? senderNameOverride,
    String? senderImageOverride,
    List<String>? participants,
    String? replyToSenderId,
  }) async {
    if (currentUserId == null) return null;
    final now = DateTime.now().millisecondsSinceEpoch;

    final userDoc = await _firestore
        .collection('users')
        .doc(currentUserId)
        .get();
    final userData = userDoc.data();
    final firstName = userData?['firstName'] as String? ?? '';
    final lastName = userData?['lastName'] as String? ?? '';
    final profileImage = userData?['profileImage'] as String?;
    final hostCountryCode = userData?['hostCountryCode'] as String?;
    final homeCountryCode = userData?['homeCountryCode'] as String?;

    final messageData = <String, dynamic>{
      'senderId': senderIdOverride ?? currentUserId,
      'senderName': senderNameOverride ?? '$firstName $lastName'.trim(),
      'senderImage': senderImageOverride ?? profileImage,
      'senderHostCountryCode': hostCountryCode,
      'senderHomeCountryCode': homeCountryCode,
      'content': address ?? 'Location',
      'type': 'location',
      'location': {
        'latitude': latitude,
        'longitude': longitude,
        'address': address,
      },
      'timestamp': now,
      'status': 'sent',
    };

    if (replyToMessageId != null) messageData['replyTo'] = replyToMessageId;
    if (senderIdOverride != null) {
      messageData['adminId'] = currentUserId;
      messageData['adminImage'] = profileImage;
    }

    try {
      final messagesRef = _rtdb.ref('chats/$chatId/messages');
      final newMessageRef = messagesRef.push();
      await newMessageRef.set(messageData);

      final lastMessageData = {
        'id': newMessageRef.key, // [NEW] ID
        'content': '📍 Location',
        'timestamp': now,
        'senderId': senderIdOverride ?? currentUserId,
        'senderName': senderNameOverride ?? '$firstName $lastName'.trim(),
        'type': 'location',
        'status': 'sent',
      };

      await _rtdb.ref('chats/$chatId/lastMessage').set(lastMessageData);
      await _rtdb.ref('chats/$chatId/updatedAt').set(now);

      final userIdsToUpdate = Set<String>.from(participants ?? []);
      if (senderIdOverride != null) {
        userIdsToUpdate.add(senderIdOverride);
      } else if (currentUserId != null)
        userIdsToUpdate.add(currentUserId!);

      for (final userId in userIdsToUpdate) {
        try {
          await _rtdb.ref('userChats/$userId/$chatId').update({
            'lastMessage': lastMessageData,
            'updatedAt': now,
            'isDeleted': null, // [NEW] Revive chat
            if (userId != currentUserId)
              'unreadCount': ServerValue.increment(1),
          });
        } catch (e) {
          debugPrint('Error updating userChat for $userId: $e');
        }
      }

      return Message.fromRTDB(newMessageRef.key!, chatId, messageData);
    } catch (e) {
      debugPrint('Error sending location message: $e');
      return null;
    }
  }

  // Unified Upload Helper
  Future<void> _uploadMediaAsync({
    required String chatId,
    required XFile file,
    required String type,
    String? caption,
    required int now,
    Map<String, dynamic>? senderData,
    int? duration,
    String? replyToMessageId,
    required String tempId,
    void Function(Message confirmedMessage)? onConfirmed,
    void Function(String error)? onError,
    String? senderIdOverride,
    String? senderNameOverride,
    String? senderImageOverride,
    List<String>? participants,
    String? replyToSenderId,
    Map<String, dynamic>? metadata, // [NEW]
  }) async {
    try {
      final folder = type == 'image'
          ? 'chat_images'
          : type == 'video'
          ? 'chat_videos'
          : (type == 'audio' || type == 'audio_file')
          ? 'chat_voices'
          : 'chat_documents';
      String mimeType = 'application/octet-stream';
      String ext = '';
      if (type == 'image') {
        ext = '.jpg';
        mimeType = 'image/jpeg';
      } else if (type == 'video') {
        ext = '.mp4';
        mimeType = 'video/mp4';
      } else if (type == 'audio' || type == 'audio_file') {
        final path = file.path.toLowerCase();
        if (path.endsWith('.m4a')) {
          ext = '.m4a';
          mimeType = 'audio/mp4';
        } else if (path.endsWith('.mp3')) {
          ext = '.mp3';
          mimeType = 'audio/mpeg';
        } else if (path.endsWith('.aac')) {
          ext = '.aac';
          mimeType = 'audio/aac';
        } else if (path.endsWith('.wav')) {
          ext = '.wav';
          mimeType = 'audio/wav';
        } else {
          // Fallback
          final dotIndex = file.path.lastIndexOf('.');
          if (dotIndex != -1) {
            ext = file.path.substring(dotIndex);
          } else {
            ext = '.m4a';
          }
          mimeType = 'audio/mpeg';
        }
      } else {
        ext = '_${file.name}';
      }

      final fileName = '${now}_$type$ext';
      final storageRef = _storage.ref().child('$folder/$chatId/$fileName');

      debugPrint(
        '🚀 Starting media upload: $fileName ($mimeType) to path: $folder/$chatId/$fileName',
      );

      final storageMetadata = SettableMetadata(
        contentType: mimeType,
        cacheControl: 'public, max-age=31536000',
      );

      UploadTask uploadTask;
      if (kIsWeb) {
        final bytes = await file.readAsBytes();
        uploadTask = storageRef.putData(bytes, storageMetadata);
      } else {
        final ioFile = File(file.path);
        if (!ioFile.existsSync()) {
          throw Exception('File does not exist at path: ${file.path}');
        }
        debugPrint('📂 File exists, size: ${ioFile.lengthSync()} bytes');
        uploadTask = storageRef.putFile(ioFile, storageMetadata);
      }

      // Monitor progress
      uploadTask.snapshotEvents.listen(
        (event) {
          debugPrint(
            '⏳ Upload Progress: ${(event.bytesTransferred / event.totalBytes * 100).round()}%',
          );
        },
        onError: (e) {
          debugPrint('❌ Upload Stream Error: $e');
        },
      );

      final snapshot = await uploadTask;
      debugPrint('✅ Upload completed with state: ${snapshot.state}');
      final derivedUrl = await snapshot.ref.getDownloadURL();

      debugPrint('✅ Download URL retrieved: $derivedUrl');

      final firstName = senderData?['firstName'] as String? ?? '';
      final lastName = senderData?['lastName'] as String? ?? '';
      final profileImage = senderData?['profileImage'] as String?;
      final hostCountryCode = senderData?['hostCountryCode'] as String?;
      final homeCountryCode = senderData?['homeCountryCode'] as String?;

      final messageData = <String, dynamic>{
        'senderId': senderIdOverride ?? currentUserId,
        'senderName': senderNameOverride ?? '$firstName $lastName'.trim(),
        'senderImage': senderImageOverride ?? profileImage,
        'senderHostCountryCode': hostCountryCode,
        'senderHomeCountryCode': homeCountryCode,
        'content': caption?.trim() ?? '',
        'type': type,
        'timestamp': now,
        'metadata': metadata, // [NEW]
        'status': 'sent',
      };

      if (type == 'image') {
        messageData['imageUrl'] = derivedUrl;
      } else if (type == 'video')
        messageData['documentUrl'] = derivedUrl;
      else if (type == 'audio' || type == 'audio_file') {
        messageData['documentUrl'] = derivedUrl;
        if (duration != null) messageData['audioDuration'] = duration;
      } else if (type == 'document') {
        messageData['documentUrl'] = derivedUrl;
        messageData['documentName'] = fileName;
      }

      if (senderIdOverride != null) {
        messageData['adminId'] = currentUserId;
        messageData['adminImage'] = profileImage;
      }
      if (replyToMessageId != null) messageData['replyTo'] = replyToMessageId;

      final messagesRef = _rtdb.ref('chats/$chatId/messages');
      final newMessageRef = messagesRef.push();
      await newMessageRef.set(messageData);

      // Icon for last message
      String icon = type == 'image'
          ? 'Photo'
          : type == 'video'
          ? 'Video'
          : type == 'audio'
          ? 'Voice message'
          : type == 'audio_file'
          ? 'Audio'
          : 'Document';

      await _rtdb.ref('chats/$chatId/lastMessage').set({
        'id': newMessageRef.key, // [NEW] ID
        'content': caption?.isNotEmpty == true ? caption : icon,
        'timestamp': now,
        'senderId': senderIdOverride ?? currentUserId,
        'senderName': senderNameOverride ?? '$firstName $lastName'.trim(),
        'type': type,
        'status': 'sent',
        'metadata': metadata, // [NEW]
      });
      await _rtdb.ref('chats/$chatId/updatedAt').set(now);

      var targetParticipants = participants;
      debugPrint(
        '📤 _uploadMediaAsync: Initial participants: $targetParticipants',
      );

      if (targetParticipants == null || targetParticipants.isEmpty) {
        // Fallback: Fetch from chat data
        try {
          debugPrint('⚠️ Media participants missing. Fetching from RTDB...');
          final chatSnapshot = await _rtdb.ref('chats/$chatId').get();
          if (chatSnapshot.exists && chatSnapshot.value != null) {
            final chatData = Map<String, dynamic>.from(
              chatSnapshot.value as Map,
            );
            final rawParticipants = chatData['participants'];
            if (rawParticipants is List) {
              targetParticipants = rawParticipants
                  .map((e) => e.toString())
                  .toList();
            } else if (rawParticipants is Map) {
              if (rawParticipants.isEmpty) {
                targetParticipants = [];
              } else {
                final firstVal = rawParticipants.values.first;
                if (firstVal is bool || (firstVal is num && firstVal == 1)) {
                  targetParticipants = rawParticipants.keys
                      .map((e) => e.toString())
                      .toList();
                } else {
                  targetParticipants = rawParticipants.values
                      .map((e) => e.toString())
                      .toList();
                }
              }
            } else {
              targetParticipants = [];
            }
            debugPrint('✅ Fetched participants: $targetParticipants');
          }
        } catch (e) {
          debugPrint('❌ Error fetching participants fallback: $e');
        }
      }

      final userIdsToUpdate = Set<String>.from(targetParticipants ?? []);
      if (replyToSenderId != null) userIdsToUpdate.add(replyToSenderId);

      if (senderIdOverride != null) {
        userIdsToUpdate.add(senderIdOverride);
      } else if (currentUserId != null)
        userIdsToUpdate.add(currentUserId!);

      debugPrint('🎯 Updating userChats (media) for targets: $userIdsToUpdate');

      for (final userId in userIdsToUpdate) {
        try {
          final contentPreview = caption?.isNotEmpty == true ? caption : icon;
          debugPrint(
            '   -> Updating userChats/$userId/$chatId with content: "$contentPreview"',
          );

          await _rtdb.ref('userChats/$userId/$chatId').update({
            'lastMessage': {
              'id': newMessageRef.key, // [NEW] ID
              'content': contentPreview,
              'timestamp': now,
              'senderId': senderIdOverride ?? currentUserId,
              'senderName': senderNameOverride ?? '$firstName $lastName'.trim(),
              'type': type,
              'status': 'sent',
              'metadata': metadata, // [NEW]
              if (type == 'image')
                'imageUrl': derivedUrl, // [NEW] For Notification
              if (type == 'video')
                'documentUrl': derivedUrl, // [NEW] For Notification (Video URL)
            },
            'updatedAt': now,
            'isDeleted': null, // [NEW] Revive chat
            if (userId != currentUserId)
              'unreadCount': ServerValue.increment(1),
          });
        } catch (e) {
          debugPrint('Error updating userChat for $userId: $e');
        }
      }

      if (onConfirmed != null) {
        onConfirmed(Message.fromRTDB(newMessageRef.key!, chatId, messageData));
      }
    } catch (e, stack) {
      debugPrint('❌ Media upload failed: $e');
      debugPrint('Stack trace: $stack');
      if (onError != null) onError(e.toString());
      rethrow; // [FIX] Ensure caller knows upload failed
    }
  }

  // ============================================
  // REACTIONS (Notification Aware)
  // ============================================

  Future<void> sendReaction({
    required String chatId,
    required String messageId,
    required String emoji,
    required String messageSenderId, // TARGET for notification
  }) async {
    final currentUserId = _auth.currentUser?.uid;
    if (currentUserId == null) return;

    // 1. Add reaction to the message
    await _rtdb
        .ref('chats/$chatId/messages/$messageId/reactions/$currentUserId')
        .set(emoji);

    // 2. Notify the message sender (if not self)
    if (messageSenderId != currentUserId) {
      final now = DateTime.now().millisecondsSinceEpoch;

      // Fetch current user name for the notification text
      // Fetch current user name for the notification text
      // [FIX] Don't use _ref here, use firestore directly like sendTextMessage
      final userDoc = await _firestore
          .collection('users')
          .doc(currentUserId)
          .get();
      final userData = userDoc.data();
      final senderName = userData?['firstName'] as String? ?? 'Someone';

      debugPrint(
        '🔔 Triggering reaction notification for user: $messageSenderId',
      );

      // Update userChats for the message OWNER to trigger push notification
      await _rtdb.ref('userChats/$messageSenderId/$chatId').update({
        'lastMessage': {
          'content': 'Reacted $emoji to your message',
          'timestamp': now,
          'senderId': currentUserId,
          'senderName': senderName,
          'type': 'reaction', // Special type
          'status': 'sent',
        },
        'updatedAt': now,
        if (messageSenderId != currentUserId)
          'unreadCount': ServerValue.increment(1),
      });
    }
  }

  // ============================================
  // GROUP MANAGEMENT
  // ============================================

}
