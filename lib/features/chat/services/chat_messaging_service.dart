import 'dart:async';
import 'package:universal_io/io.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../models/message.dart';

import 'package:diaspora_nearby/features/dsp/services/points_service.dart';
import 'package:diaspora_nearby/features/profile/repository/profile_repository.dart';

final chatMessagingServiceProvider = Provider<ChatMessagingService>((ref) {
  return ChatMessagingService(
    pointsService: ref.read(pointsServiceProvider),
    ref: ref,
  );
});

class ChatMessagingService {
  final FirebaseStorage _storage;
  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  // ignore: unused_field
  final PointsService _pointsService;
  final Ref? _ref;

  Map<String, dynamic>? _cachedSenderData;
  String? _cachedSenderUid;
  int _cachedSenderTimestamp = 0;

  ChatMessagingService({
    FirebaseStorage? storage,
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    required PointsService pointsService,
    Ref? ref,
  }) : _storage = storage ?? FirebaseStorage.instance,
       _firestore = firestore ?? FirebaseFirestore.instance,
       _auth = auth ?? FirebaseAuth.instance,
       _pointsService = pointsService,
       _ref = ref;

  String? get currentUserId => _auth.currentUser?.uid;

  /// Synchronous lookup of sender profile data for 0ms optimistic message creation.
  Map<String, dynamic>? getSenderDataSync() {
    final uid = currentUserId;
    if (uid == null) return null;

    final now = DateTime.now().millisecondsSinceEpoch;
    if (_cachedSenderData != null &&
        _cachedSenderUid == uid &&
        (now - _cachedSenderTimestamp) < 300000) {
      return _cachedSenderData;
    }

    try {
      final profile =
          _ref?.read(userProfileProvider).value ??
          _ref?.read(profileRepositoryProvider).getCachedProfile(uid);
      if (profile != null && profile.firstName.isNotEmpty) {
        _cachedSenderData = {
          'firstName': profile.firstName,
          'lastName': profile.lastName,
          'profileImage': profile.profileImage,
          'hostCountryCode': profile.hostCountryCode,
          'homeCountryCode': profile.homeCountryCode,
        };
        _cachedSenderUid = uid;
        _cachedSenderTimestamp = now;
        return _cachedSenderData;
      }
    } catch (_) {}

    return _cachedSenderData;
  }

  /// Get sender data with caching (5-minute TTL)
  Future<Map<String, dynamic>?> _getSenderData() async {
    final syncData = getSenderDataSync();
    if (syncData != null) return syncData;

    final uid = currentUserId;
    if (uid == null) return null;

    final userDoc = await _firestore.collection('users').doc(uid).get();
    _cachedSenderData = userDoc.data();
    _cachedSenderUid = uid;
    _cachedSenderTimestamp = DateTime.now().millisecondsSinceEpoch;
    return _cachedSenderData;
  }

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
    String? replyToSenderId,
    String type = 'text',
    Map<String, dynamic>? metadata,
  }) async {
    if (currentUserId == null) return null;

    final now = DateTime.now().millisecondsSinceEpoch;
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
      'type': type,
      'timestamp': now,
      'status': 'sent',
      'mentions': ?mentions,
      'richContent': ?richContent,
      'metadata': ?metadata,
    };

    if (replyToMessageId != null) {
      messageData['replyTo'] = replyToMessageId;
    }

    if (senderIdOverride != null) {
      messageData['adminId'] = currentUserId;
      messageData['adminImage'] = profileImage;
    }

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
        'metadata': ?metadata,
      };

      var targetParticipants = participants;

      if (targetParticipants == null || targetParticipants.isEmpty) {
        final chatDoc = await _chatsCol.doc(chatId).get();
        if (chatDoc.exists) {
          final chatData = chatDoc.data()!;
          targetParticipants = List<String>.from(
            chatData['participants'] ?? [],
          );
          if (targetParticipants.isEmpty && currentUserId != null) {
            targetParticipants = [currentUserId!];
            final createdBy = chatData['createdBy'] as String?;
            if (createdBy != null && createdBy != currentUserId) {
              targetParticipants.add(createdBy);
            }
            final adminId = chatData['adminId'] as String?;
            if (adminId != null && !targetParticipants.contains(adminId)) {
              targetParticipants.add(adminId);
            }
          }
        }
      }

      targetParticipants ??= [currentUserId!];

      final chatDocUpdate = <String, dynamic>{
        'lastMessage': lastMessageData,
        'updatedAt': now,
      };

      final batch = _firestore.batch();
      batch.set(newMsgRef, messageData);
      batch.set(_chatsCol.doc(chatId), chatDocUpdate, SetOptions(merge: true));

      if (currentUserId != null) {
        final userChatUpdates = <String, dynamic>{
          'chatId': chatId,
          'lastMessage': {
            'id': newMsgRef.id,
            'content': content,
            'timestamp': now,
            'senderId': senderIdOverride ?? currentUserId,
            'senderName': senderName,
            'type': type,
            'status': 'sent',
            'mentions': ?mentions,
            'metadata': ?metadata,
          },
          'updatedAt': now,
          'isDeleted': false,
        };
        batch.set(
          _userChatsCol(currentUserId!).doc(chatId),
          userChatUpdates,
          SetOptions(merge: true),
        );
      }

      await batch.commit();

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
    if (currentUserId == null || invitedUserIds.isEmpty) return;

    await Future.wait(
      invitedUserIds.map((userId) async {
        try {
          await FirebaseFunctions.instance
              .httpsCallable('manageChatMembers')
              .call({'chatId': groupId, 'inviteUserId': userId});
        } catch (e) {
          debugPrint('Error sending invitation to $userId: $e');
        }
      }),
    );
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

      final batch = _firestore.batch();
      batch.set(newMsgRef, messageData);
      batch.set(_chatsCol.doc(targetChatId), {
        'lastMessage': lastMessageData,
        'updatedAt': now,
      }, SetOptions(merge: true));

      if (currentUserId != null) {
        batch.set(_userChatsCol(currentUserId!).doc(targetChatId), {
          'chatId': targetChatId,
          'lastMessage': lastMessageData,
          'updatedAt': now,
          'isDeleted': false,
        }, SetOptions(merge: true));
      }

      await batch.commit();

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
  // MEDIA MESSAGING (0ms Optimistic Return)
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
    Map<String, dynamic>? metadata,
  }) async {
    if (currentUserId == null) return null;

    final now = DateTime.now().millisecondsSinceEpoch;
    final tempId = 'pending_${now}_$currentUserId';

    final userData = getSenderDataSync();
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
      metadata: metadata,
    );

    unawaited(
      _uploadMediaAsync(
        chatId: chatId,
        file: imageFile,
        type: 'image',
        caption: caption,
        now: now,
        metadata: metadata,
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
      ),
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
    Map<String, dynamic>? metadata,
  }) async {
    if (currentUserId == null) throw Exception('User not logged in');
    final now = DateTime.now().millisecondsSinceEpoch;
    final tempId = 'pending_video_${now}_$currentUserId';

    final userData = getSenderDataSync();
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
      documentUrl: videoFile.path,
      timestamp: now,
      status: 'sending',
      replyTo: replyToMessageId,
      adminId: senderIdOverride != null ? currentUserId : null,
      adminImage: senderIdOverride != null ? profileImage : null,
      metadata: metadata,
    );

    unawaited(
      _uploadMediaAsync(
        chatId: chatId,
        file: videoFile,
        type: 'video',
        caption: caption,
        now: now,
        metadata: metadata,
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
      ),
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
    Map<String, dynamic>? metadata,
  }) async {
    if (currentUserId == null) return null;
    final now = DateTime.now().millisecondsSinceEpoch;
    final tempId = 'pending_voice_${now}_$currentUserId';

    final userData = getSenderDataSync();
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
      type: messageType,
      documentUrl: audioFile.path,
      audioDuration: durationSeconds,
      timestamp: now,
      status: 'sending',
      replyTo: replyToMessageId,
      adminId: senderIdOverride != null ? currentUserId : null,
      adminImage: senderIdOverride != null ? profileImage : null,
      metadata: metadata,
    );

    unawaited(
      _uploadMediaAsync(
        chatId: chatId,
        file: audioFile,
        type: messageType,
        caption: caption,
        now: now,
        metadata: metadata,
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
      ),
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
    Map<String, dynamic>? metadata,
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
      metadata: metadata,
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
    Map<String, dynamic>? metadata,
  }) async {
    if (currentUserId == null) throw Exception('User not logged in');
    final now = DateTime.now().millisecondsSinceEpoch;
    final tempId = 'pending_doc_${now}_$currentUserId';

    final userData = getSenderDataSync();
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
      metadata: metadata,
    );

    unawaited(
      _uploadMediaAsync(
        chatId: chatId,
        file: file,
        type: 'document',
        caption: caption,
        now: now,
        metadata: metadata,
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
      ),
    );

    return optimisticMessage;
  }

  Future<Message?> sendLocationMessage(
    String chatId, {
    required double latitude,
    required double longitude,
    String? address,
    String? caption,
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

    final messageContent = (caption != null && caption.trim().isNotEmpty)
        ? caption.trim()
        : (address ?? 'Location');

    final messageData = <String, dynamic>{
      'senderId': senderIdOverride ?? currentUserId,
      'senderName': senderNameOverride ?? '$firstName $lastName'.trim(),
      'senderImage': senderImageOverride ?? profileImage,
      'senderHostCountryCode': hostCountryCode,
      'senderHomeCountryCode': homeCountryCode,
      'content': messageContent,
      'type': 'location',
      'location': {'lat': latitude, 'lng': longitude, 'address': address},
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
      final lastMessageData = <String, dynamic>{
        'id': newMsgRef.id,
        'content': caption?.trim().isNotEmpty == true
            ? caption!.trim()
            : 'Location',
        'timestamp': now,
        'senderId': senderIdOverride ?? currentUserId,
        'senderName': senderNameOverride ?? '$firstName $lastName'.trim(),
        'type': 'location',
        'status': 'sent',
      };

      final batch = _firestore.batch();
      batch.set(newMsgRef, messageData);
      batch.set(_chatsCol.doc(chatId), {
        'lastMessage': lastMessageData,
        'updatedAt': now,
      }, SetOptions(merge: true));
      if (currentUserId != null) {
        batch.set(_userChatsCol(currentUserId!).doc(chatId), {
          'chatId': chatId,
          'lastMessage': lastMessageData,
          'updatedAt': now,
          'isDeleted': false,
        }, SetOptions(merge: true));
      }
      await batch.commit();

      return Message.fromFirestoreData(newMsgRef.id, chatId, messageData);
    } catch (e) {
      debugPrint('Error sending location message: $e');
      rethrow;
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
    Map<String, dynamic>? metadata,
  }) async {
    try {
      final resolvedSenderData = senderData ?? await _getSenderData();
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

      final storageMetadata = SettableMetadata(
        contentType: mimeType,
        cacheControl: 'public, max-age=31536000',
        customMetadata: {'ownerUid': ?currentUserId, 'chatId': chatId},
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
        uploadTask = storageRef.putFile(ioFile, storageMetadata);
      }

      final snapshot = await uploadTask;
      final derivedUrl = await snapshot.ref.getDownloadURL();

      final firstName = resolvedSenderData?['firstName'] as String? ?? '';
      final lastName = resolvedSenderData?['lastName'] as String? ?? '';
      final profileImage = resolvedSenderData?['profileImage'] as String?;
      final hostCountryCode =
          resolvedSenderData?['hostCountryCode'] as String?;
      final homeCountryCode =
          resolvedSenderData?['homeCountryCode'] as String?;

      final messageData = <String, dynamic>{
        'senderId': senderIdOverride ?? currentUserId,
        'senderName': senderNameOverride ?? '$firstName $lastName'.trim(),
        'senderImage': senderImageOverride ?? profileImage,
        'senderHostCountryCode': hostCountryCode,
        'senderHomeCountryCode': homeCountryCode,
        'content': caption?.trim() ?? '',
        'type': type,
        'timestamp': now,
        'metadata': ?metadata,
        'storagePath': storageRef.fullPath,
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
        'metadata': ?metadata,
      };

      final batch = _firestore.batch();
      batch.set(newMsgRef, messageData);
      batch.set(_chatsCol.doc(chatId), {
        'lastMessage': lastMessageData,
        'updatedAt': now,
      }, SetOptions(merge: true));
      if (currentUserId != null) {
        batch.set(_userChatsCol(currentUserId!).doc(chatId), {
          'chatId': chatId,
          'lastMessage': lastMessageData,
          'updatedAt': now,
          'isDeleted': false,
        }, SetOptions(merge: true));
      }
      await batch.commit();

      if (onConfirmed != null) {
        onConfirmed(
          Message.fromFirestoreData(newMsgRef.id, chatId, messageData),
        );
      }
    } catch (e, stack) {
      debugPrint('❌ Media upload failed: $e');
      debugPrint('Stack trace: $stack');
      if (onError != null) onError(e.toString());
    }
  }

  // ============================================
  // REACTIONS (Notification Aware)
  // ============================================

  Future<void> sendReaction({
    required String chatId,
    required String messageId,
    required String emoji,
    required String messageSenderId,
  }) async {
    final currentUserId = _auth.currentUser?.uid;
    if (currentUserId == null) return;

    await FirebaseFunctions.instance.httpsCallable('reactToMessage').call({
      'chatId': chatId,
      'messageId': messageId,
      'emoji': emoji,
    });
  }
}
