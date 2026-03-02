import 'package:universal_io/io.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/message.dart';

import 'package:diaspora_nearby/features/dsp/services/points_service.dart';

// Provider definition
final chatMessagingServiceProvider = Provider<ChatMessagingService>((ref) {
  return ChatMessagingService(
    pointsService: ref.read(pointsServiceProvider),
  );
});

class ChatMessagingService {
  final FirebaseStorage _storage;
  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final PointsService _pointsService;

  // [FIX] Cache sender profile to avoid fetching on every message
  Map<String, dynamic>? _cachedSenderData;
  String? _cachedSenderUid;
  int _cachedSenderTimestamp = 0;

  ChatMessagingService({
    FirebaseStorage? storage,
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    required PointsService pointsService,
  }) : _storage = storage ?? FirebaseStorage.instance,
       _firestore = firestore ?? FirebaseFirestore.instance,
       _auth = auth ?? FirebaseAuth.instance,
       _pointsService = pointsService;

  String? get currentUserId => _auth.currentUser?.uid;

  /// Get sender data with caching (5-minute TTL)
  Future<Map<String, dynamic>?> _getSenderData() async {
    final uid = currentUserId;
    if (uid == null) return null;

    final now = DateTime.now().millisecondsSinceEpoch;
    // Use cache if same user and less than 5 minutes old
    if (_cachedSenderData != null &&
        _cachedSenderUid == uid &&
        (now - _cachedSenderTimestamp) < 300000) {
      return _cachedSenderData;
    }

    final userDoc = await _firestore.collection('users').doc(uid).get();
    _cachedSenderData = userDoc.data();
    _cachedSenderUid = uid;
    _cachedSenderTimestamp = now;
    return _cachedSenderData;
  }

  /// Firestore collection helpers
  CollectionReference<Map<String, dynamic>> get _chatsCol =>
      _firestore.collection('chats');
  CollectionReference<Map<String, dynamic>> _messagesCol(String chatId) =>
      _chatsCol.doc(chatId).collection('messages');
  CollectionReference<Map<String, dynamic>> _userChatsCol(String uid) =>
      _firestore.collection('users').doc(uid).collection('userChats');

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

    // Use cached sender data to avoid Firestore fetch on every message
    final userData = await _getSenderData();

    final firstName = userData?['firstName'] as String? ?? '';
    final lastName = userData?['lastName'] as String? ?? '';
    final profileImage = userData?['profileImage'] as String?;
    final hostCountryCode = userData?['hostCountryCode'] as String?;
    final homeCountryCode = userData?['homeCountryCode'] as String?;

    final fullName = '$firstName $lastName'.trim();
    final senderName =
        senderNameOverride ?? (fullName.isNotEmpty ? fullName : 'Someone');

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
      'mentions': ?mentions,
      'richContent': ?richContent,
      'metadata': ?metadata, // [NEW]
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
      final newMsgRef = _messagesCol(chatId).doc();

      final lastMessageData = {
        'id': newMsgRef.id,
        'content': content,
        'timestamp': now,
        'senderId': senderIdOverride ?? currentUserId,
        'senderName': senderName,
        'type': type,
        'status': 'sent',
        if (metadata != null) 'metadata': metadata,
      };

      // Determine participants for the chat document
      var targetParticipants = participants;

      // If participants are missing, try to reconstruct from Firestore
      if (targetParticipants == null || targetParticipants.isEmpty) {
        debugPrint('⚠️ Participants missing. Fetching from Firestore chat doc...');
        final chatDoc = await _chatsCol.doc(chatId).get();
        if (chatDoc.exists) {
          final chatData = chatDoc.data()!;
          targetParticipants = List<String>.from(
            chatData['participants'] ?? [],
          );
        }
      }

      // If STILL missing, reconstruct from userChats subcollections
      if (targetParticipants == null || targetParticipants.isEmpty) {
        debugPrint('🔄 Self-healing: Reconstructing participants...');
        targetParticipants = [currentUserId!];
        try {
          final chatDoc = await _chatsCol.doc(chatId).get();
          final createdBy = chatDoc.data()?['createdBy'] as String?;
          if (createdBy != null && createdBy != currentUserId) {
            targetParticipants.add(createdBy);
          }
          final adminId = chatDoc.data()?['adminId'] as String?;
          if (adminId != null && !targetParticipants.contains(adminId)) {
            targetParticipants.add(adminId);
          }
        } catch (e) {
          debugPrint('⚠️ Could not reconstruct participants: $e');
        }
      }

      // Build chat doc update
      final chatDocUpdate = <String, dynamic>{
        'lastMessage': lastMessageData,
        'updatedAt': now,
      };
      
      if (targetParticipants != null && targetParticipants.isNotEmpty) {
        chatDocUpdate['participants'] = targetParticipants;
      }
      
      // Ensure type is set
      if (chatId.startsWith('direct_')) {
        chatDocUpdate['type'] = 'direct';
      } else if (chatId.startsWith('chat_') ||
          chatId.startsWith('home_') ||
          chatId.startsWith('host_') ||
          chatId.startsWith('past_') ||
          chatId == 'global_community') {
        chatDocUpdate['type'] = 'community';
      } else if (chatId.startsWith('event_')) {
        chatDocUpdate['type'] = 'event';
      } else if (chatId.startsWith('org_')) {
        chatDocUpdate['type'] = 'organization';
      }

      // [FIX] Use WriteBatch — all writes in a single network round-trip
      final batch = _firestore.batch();

      // 1. Write the message document
      batch.set(newMsgRef, messageData);

      // 2. Update the chat document
      batch.set(_chatsCol.doc(chatId), chatDocUpdate, SetOptions(merge: true));

      // 3. Update all participant userChats
      final Set<String> allTargets = {};
      if (targetParticipants != null) allTargets.addAll(targetParticipants);
      if (mentions != null) allTargets.addAll(mentions);
      if (replyToSenderId != null) allTargets.add(replyToSenderId);
      if (senderIdOverride != null) {
        allTargets.add(senderIdOverride);
      } else if (currentUserId != null) {
        allTargets.add(currentUserId!);
      }

      for (final userId in allTargets) {
        String userSpecificContent = content;

        if (type == 'dsp_transfer') {
          final isSender = userId == (senderIdOverride ?? currentUserId);
          final amount = metadata?['amount'] ?? 0;
          userSpecificContent = isSender
              ? 'You sent $amount DSP'
              : 'You received $amount DSP from $senderName';
        }

        final userChatUpdates = <String, dynamic>{
          'chatId': chatId,
          'lastMessage': {
            'id': newMsgRef.id,
            'content': userSpecificContent,
            'timestamp': now,
            'senderId': senderIdOverride ?? currentUserId,
            'senderName': senderName,
            'type': type,
            'status': 'sent',
            if (mentions != null) 'mentions': mentions,
            if (metadata != null) 'metadata': metadata,
          },
          'updatedAt': now,
          'isDeleted': false,
        };

        if (userId != currentUserId) {
          userChatUpdates['unreadCount'] = FieldValue.increment(1);
        }

        batch.set(
          _userChatsCol(userId).doc(chatId),
          userChatUpdates,
          SetOptions(merge: true),
        );
      }

      // Single network round-trip for ALL writes
      await batch.commit();

      debugPrint('✅ Message sent via batch commit (${allTargets.length} targets)');

      // Track Engagement Rewards (fire-and-forget)
      _triggerPointRewards(
        chatId: chatId,
        senderIdOverride: senderIdOverride,
        participants: allTargets,
      );

      return Message.fromFirestoreData(newMsgRef.id, chatId, messageData);
    } catch (e, stack) {
      debugPrint('❌ Error sending text message: $e');
      debugPrint('Stack trace: $stack');
      rethrow;
    }
  }

  Future<void> sendGroupInvitation(
    String groupId,
    String groupName,
    List<String> invitedUserIds,
  ) async {
    if (currentUserId == null) return;

    final userData = await _getSenderData();
    final senderName =
        '${userData?['firstName'] ?? ''} ${userData?['lastName'] ?? ''}'.trim();
    // Req: "[sender full] invites you to join group: [group name]"
    final content = '$senderName invites you to join group: $groupName';

    final now = DateTime.now().millisecondsSinceEpoch;

    for (final userId in invitedUserIds) {
      try {
        await _userChatsCol(userId).doc(groupId).set({
          'chatId': groupId,
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
          'unreadCount': FieldValue.increment(1),
          'isDeleted': false,
        }, SetOptions(merge: true));
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

    // Use cached sender data
    final userData = await _getSenderData();

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
      final newMsgRef = _messagesCol(targetChatId).doc();
      await newMsgRef.set(messageData);

      // Update lastMessage
      String lastMessageContent = originalMessage.content;
      if (lastMessageContent.isEmpty) {
        lastMessageContent = _getMessageTypeLabel(originalMessage.type);
      }

      final lastMessageData = {
        'id': newMsgRef.id,
        'content': lastMessageContent,
        'timestamp': now,
        'senderId': senderIdOverride ?? currentUserId,
        'senderName': senderNameOverride ?? '$firstName $lastName'.trim(),
        'type': originalMessage.type,
        'status': 'sent',
      };

      await _chatsCol.doc(targetChatId).set({
        'lastMessage': lastMessageData,
        'updatedAt': now,
      }, SetOptions(merge: true));

      var targetParticipants = participants;
      if (targetParticipants == null || targetParticipants.isEmpty) {
        final chatDoc = await _chatsCol.doc(targetChatId).get();
        if (chatDoc.exists) {
          targetParticipants = List<String>.from(
            chatDoc.data()?['participants'] ?? [],
          );
        }
      }

      if (targetParticipants != null) {
        for (final userId in targetParticipants) {
          try {
            final userChatUpdates = <String, dynamic>{
              'lastMessage': lastMessageData,
              'updatedAt': now,
              'isDeleted': false,
            };
            if (userId != currentUserId) {
              userChatUpdates['unreadCount'] = FieldValue.increment(1);
            }
            await _userChatsCol(userId).doc(targetChatId).set(
              userChatUpdates,
              SetOptions(merge: true),
            );
          } catch (e) {
            debugPrint('Error updating userChat for $userId: $e');
          }
        }
      }

      return Message.fromFirestoreData(newMsgRef.id, targetChatId, messageData);
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

    final userData = await _getSenderData();
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

    final userData = await _getSenderData();
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

    final userData = await _getSenderData();
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

    final userData = await _getSenderData();
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

    final userData = await _getSenderData();
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
      final newMsgRef = _messagesCol(chatId).doc();
      await newMsgRef.set(messageData);

      final lastMessageData = {
        'id': newMsgRef.id,
        'content': 'Location',
        'timestamp': now,
        'senderId': senderIdOverride ?? currentUserId,
        'senderName': senderNameOverride ?? '$firstName $lastName'.trim(),
        'type': 'location',
        'status': 'sent',
      };

      await _chatsCol.doc(chatId).set({
        'lastMessage': lastMessageData,
        'updatedAt': now,
      }, SetOptions(merge: true));

      final userIdsToUpdate = Set<String>.from(participants ?? []);
      if (senderIdOverride != null) {
        userIdsToUpdate.add(senderIdOverride);
      } else if (currentUserId != null)
        userIdsToUpdate.add(currentUserId!);

      for (final userId in userIdsToUpdate) {
        try {
          final userChatUpdates = <String, dynamic>{
            'lastMessage': lastMessageData,
            'updatedAt': now,
            'isDeleted': false,
          };
          if (userId != currentUserId) {
            userChatUpdates['unreadCount'] = FieldValue.increment(1);
          }
          await _userChatsCol(userId).doc(chatId).set(
            userChatUpdates,
            SetOptions(merge: true),
          );
        } catch (e) {
          debugPrint('Error updating userChat for $userId: $e');
        }
      }

      return Message.fromFirestoreData(newMsgRef.id, chatId, messageData);
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
      } else if (type == 'video') {
        messageData['documentUrl'] = derivedUrl;
      } else if (type == 'audio' || type == 'audio_file') {
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
      if (replyToMessageId != null) {
        messageData['replyTo'] = replyToMessageId;
      }

      final newMsgRef = _messagesCol(chatId).doc();
      await newMsgRef.set(messageData);

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

      final lastMessageData = <String, dynamic>{
        'id': newMsgRef.id,
        'content': caption?.isNotEmpty == true ? caption : icon,
        'timestamp': now,
        'senderId': senderIdOverride ?? currentUserId,
        'senderName': senderNameOverride ?? '$firstName $lastName'.trim(),
        'type': type,
        'status': 'sent',
        if (metadata != null) 'metadata': metadata,
      };

      final chatDocMediaUpdate = <String, dynamic>{
        'lastMessage': lastMessageData,
        'updatedAt': now,
      };
      // Self-heal type from chatId pattern
      if (chatId.startsWith('direct_')) {
        chatDocMediaUpdate['type'] = 'direct';
      } else if (chatId.startsWith('chat_') ||
          chatId.startsWith('home_') ||
          chatId.startsWith('host_') ||
          chatId.startsWith('past_') ||
          chatId == 'global_community') {
        chatDocMediaUpdate['type'] = 'community';
      } else if (chatId.startsWith('event_')) {
        chatDocMediaUpdate['type'] = 'event';
      } else if (chatId.startsWith('org_')) {
        chatDocMediaUpdate['type'] = 'organization';
      }

      await _chatsCol.doc(chatId).set(chatDocMediaUpdate, SetOptions(merge: true));

      var targetParticipants = participants;
      debugPrint(
        '📤 _uploadMediaAsync: Initial participants: $targetParticipants',
      );

      if (targetParticipants == null || targetParticipants.isEmpty) {
        try {
          debugPrint('⚠️ Media participants missing. Fetching from Firestore...');
          final chatDoc = await _chatsCol.doc(chatId).get();
          if (chatDoc.exists) {
            targetParticipants = List<String>.from(
              chatDoc.data()?['participants'] ?? [],
            );
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
            '   -> Updating userChats for $userId with content: "$contentPreview"',
          );

          final userChatMediaData = <String, dynamic>{
            'lastMessage': <String, dynamic>{
              'id': newMsgRef.id,
              'content': contentPreview,
              'timestamp': now,
              'senderId': senderIdOverride ?? currentUserId,
              'senderName': senderNameOverride ?? '$firstName $lastName'.trim(),
              'type': type,
              'status': 'sent',
              if (metadata != null) 'metadata': metadata,
              if (type == 'image') 'imageUrl': derivedUrl,
              if (type == 'video') 'documentUrl': derivedUrl,
            },
            'updatedAt': now,
            'isDeleted': false,
          };

          if (userId != currentUserId) {
            userChatMediaData['unreadCount'] = FieldValue.increment(1);
          }

          await _userChatsCol(userId).doc(chatId).set(
            userChatMediaData,
            SetOptions(merge: true),
          );
        } catch (e) {
          debugPrint('Error updating userChat for $userId: $e');
        }
      }

      // Track Engagement Rewards (Media)
      _triggerPointRewards(
        chatId: chatId,
        senderIdOverride: senderIdOverride,
        participants: userIdsToUpdate,
      );

      if (onConfirmed != null) {
        onConfirmed(Message.fromFirestoreData(newMsgRef.id, chatId, messageData));
      }
    } catch (e, stack) {
      debugPrint('❌ Media upload failed: $e');
      debugPrint('Stack trace: $stack');
      if (onError != null) onError(e.toString());
      rethrow;
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

    // 1. Read current reactions, update, and write back
    final msgDoc = await _messagesCol(chatId).doc(messageId).get();
    final msgData = msgDoc.data() ?? {};
    
    // Parse existing reactions (stored as list of {emoji, userIds} maps)
    List<Map<String, dynamic>> reactionsList = [];
    if (msgData['reactions'] is List) {
      reactionsList = (msgData['reactions'] as List)
          .map((r) => Map<String, dynamic>.from(r as Map))
          .toList();
    }
    
    // Remove user from any existing reaction
    for (final r in reactionsList) {
      final userIds = List<String>.from(r['userIds'] ?? []);
      userIds.remove(currentUserId);
      r['userIds'] = userIds;
    }
    reactionsList.removeWhere((r) => (r['userIds'] as List).isEmpty);
    
    // Add user to the target emoji reaction
    final existingReaction = reactionsList.where((r) => r['emoji'] == emoji).firstOrNull;
    if (existingReaction != null) {
      (existingReaction['userIds'] as List).add(currentUserId!);
    } else {
      reactionsList.add({'emoji': emoji, 'userIds': [currentUserId]});
    }
    
    await _messagesCol(chatId).doc(messageId).set({
      'reactions': reactionsList,
    }, SetOptions(merge: true));

    // 2. Notify the message sender (if not self)
    if (messageSenderId != currentUserId) {
      final now = DateTime.now().millisecondsSinceEpoch;

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
      final reactionUpdate = <String, dynamic>{
        'lastMessage': {
          'content': 'Reacted $emoji to your message',
          'timestamp': now,
          'senderId': currentUserId,
          'senderName': senderName,
          'type': 'reaction',
          'status': 'sent',
        },
        'updatedAt': now,
        'unreadCount': FieldValue.increment(1),
      };

      await _userChatsCol(messageSenderId).doc(chatId).set(
        reactionUpdate,
        SetOptions(merge: true),
      );
    }
  }

  // ============================================
  // REWARDS HELPER
  // ============================================

  void _triggerPointRewards({
    required String chatId,
    required String? senderIdOverride,
    required Iterable<String>? participants,
  }) {
    if (senderIdOverride != null || currentUserId == null) return;

    // 1. Regular message reward (10 DSP, daily limit 100 handled in repo)
    _pointsService.trackMessageSent(currentUserId!);

    // 2. Specialized rewards (100 DSP)
    // Community IDs usually start with 'home_', 'host_', 'past_', 'chat_', or is 'global_community'
    final isCommunity =
        chatId.startsWith('chat_') ||
        chatId.startsWith('home_') ||
        chatId.startsWith('host_') ||
        chatId.startsWith('past_') ||
        chatId == 'global_community';

    if (isCommunity) {
      _pointsService.trackCommunityMessage(currentUserId!, chatId);
    } else if (chatId.startsWith('direct_')) {
      // DM reward (Unique per user pair)
      if (participants != null) {
        final targetUserId = participants.firstWhere(
          (uid) => uid != currentUserId,
          orElse: () => '',
        );
        if (targetUserId.isNotEmpty) {
          _pointsService.trackNewDM(currentUserId!, targetUserId);
        }
      }
    }
  }
}
