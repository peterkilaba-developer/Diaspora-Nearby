import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../models/message.dart';

// Provider definition
final chatMessagingServiceProvider = Provider<ChatMessagingService>((ref) => ChatMessagingService());

class ChatMessagingService {
  final FirebaseDatabase _rtdb;
  final FirebaseStorage _storage;
  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  ChatMessagingService({
    FirebaseDatabase? rtdb,
    FirebaseStorage? storage,
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  })  : _rtdb = rtdb ?? FirebaseDatabase.instance,
        _storage = storage ?? FirebaseStorage.instance,
        _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

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
  }) async {
    if (currentUserId == null) return null;

    final now = DateTime.now().millisecondsSinceEpoch;
    
    // Fetch sender data (could be cached or passed in, but fetching ensures freshness)
    final userDoc = await _firestore.collection('users').doc(currentUserId).get();
    final userData = userDoc.data();
    
    final firstName = userData?['firstName'] as String? ?? '';
    final lastName = userData?['lastName'] as String? ?? '';
    final profileImage = userData?['profileImage'] as String?;
    final hostCountryCode = userData?['hostCountryCode'] as String?;
    final homeCountryCode = userData?['homeCountryCode'] as String?;


    

    final messageData = {
      'senderId': senderIdOverride ?? currentUserId,
      'senderName': senderNameOverride ?? '${firstName} ${lastName}'.trim(),
      'senderImage': senderImageOverride ?? profileImage,
      'senderHostCountryCode': hostCountryCode,
      'senderHomeCountryCode': homeCountryCode,
      'content': content, // [FIX] Revert to raw content to trigger backend notifications
 
      'type': 'text',
      'timestamp': now,
      'status': 'sent',

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
        'content': content,
        'timestamp': now,
        'senderId': senderIdOverride ?? currentUserId,
        'senderName': senderNameOverride ?? '$firstName $lastName'.trim(),
        'type': 'text',
        'status': 'sent',
      });
      await _rtdb.ref('chats/$chatId/updatedAt').set(now);

      var targetParticipants = participants;
      if (targetParticipants == null || targetParticipants.isEmpty) {
          final chatSnapshot = await _rtdb.ref('chats/$chatId').get();
          if (chatSnapshot.exists && chatSnapshot.value != null) {
            final chatData = Map<String, dynamic>.from(chatSnapshot.value as Map);
            targetParticipants = List<String>.from(chatData['participants'] ?? []);
          }
      }

      final Set<String> allTargets = {};
      if (targetParticipants != null) allTargets.addAll(targetParticipants);

      if (senderIdOverride != null) allTargets.add(senderIdOverride);
      else if (currentUserId != null) allTargets.add(currentUserId!);

      for (final userId in allTargets) {
          try {
             String userSpecificContent = content;


             await _rtdb.ref('userChats/$userId/$chatId').update({
               'lastMessage': {
                 'content': userSpecificContent,
                 'timestamp': now,
                 'senderId': senderIdOverride ?? currentUserId,
                 'senderName': senderNameOverride ?? '$firstName $lastName'.trim(),
                 'type': 'text',
                 'status': 'sent',
                },
               'updatedAt': now,
               'unreadCount': ServerValue.increment(1), // [NEW] Increment unread count
             });
          } catch (e) {
             debugPrint('Error updating userChat for $userId: $e');
          }
      }

      // Convert RTDB data to Message object
      return Message.fromRTDB(newMessageRef.key!, chatId, messageData);

    } catch (e) {
      debugPrint('Error sending text message: $e');
      return null;
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
    final userDoc = await _firestore.collection('users').doc(currentUserId).get();
    final userData = userDoc.data();
    
    final firstName = userData?['firstName'] as String? ?? '';
    final lastName = userData?['lastName'] as String? ?? '';
    final profileImage = userData?['profileImage'] as String?;
    final hostCountryCode = userData?['hostCountryCode'] as String?;
    final homeCountryCode = userData?['homeCountryCode'] as String?;

    final messageData = {
      'senderId': senderIdOverride ?? currentUserId,
      'senderName': senderNameOverride ?? '${firstName} ${lastName}'.trim(),
      'senderImage': senderImageOverride ?? profileImage,
      'senderHostCountryCode': hostCountryCode,
      'senderHomeCountryCode': homeCountryCode,
      'content': originalMessage.content,
      'type': originalMessage.type,
      'timestamp': now,
      'status': 'sent',
      'forwarded': true,
      'originalSenderId': originalMessage.originalSenderId ?? originalMessage.senderId,
      'originalSenderName': originalMessage.originalSenderName ?? originalMessage.senderName,
      'originalSenderImage': originalMessage.originalSenderImage ?? originalMessage.senderImage,
      'originalSenderHostCountryCode': originalMessage.originalSenderHostCountryCode ?? originalMessage.senderHostCountryCode,
      'originalSenderHomeCountryCode': originalMessage.originalSenderHomeCountryCode ?? originalMessage.senderHomeCountryCode,
      'originalTimestamp': originalMessage.originalTimestamp ?? originalMessage.timestamp,
    };
    
    // Copy media fields
    if (originalMessage.imageUrl != null) messageData['imageUrl'] = originalMessage.imageUrl;
    if (originalMessage.documentUrl != null) messageData['documentUrl'] = originalMessage.documentUrl;
    if (originalMessage.documentName != null) messageData['documentName'] = originalMessage.documentName;
    if (originalMessage.documentSize != null) messageData['documentSize'] = originalMessage.documentSize;
    if (originalMessage.audioDuration != null) messageData['audioDuration'] = originalMessage.audioDuration;
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
            targetParticipants = List<String>.from(chatData['participants'] ?? []);
          }
      }

      if (targetParticipants != null) {
        for (final userId in targetParticipants) {
          try {
             await _rtdb.ref('userChats/$userId/$targetChatId').update({
               'lastMessage': {
                 'content': lastMessageContent,
                 'timestamp': now,
                 'senderId': senderIdOverride ?? currentUserId,
                 'senderName': senderNameOverride ?? '$firstName $lastName'.trim(),
                 'type': originalMessage.type,
                 'status': 'sent',
               },
               'updatedAt': now,
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
      case 'image': return '📷 Photo';
      case 'video': return '📹 Video';
      case 'audio': return '🎤 Voice message';
      case 'audio_file': return '🎵 Audio';
      case 'location': return '📍 Location';
      case 'document': return '📄 Document';
      default: return 'Forwarded message';
    }
  }

  // ============================================
  // MEDIA MESSAGING
  // ============================================

  Future<Message?> sendImageMessage(
    String chatId, 
    String imagePath, {
    String? caption,
    String? replyToMessageId,
    void Function(Message confirmedMessage)? onConfirmed,
    void Function(String error)? onError,
    String? senderIdOverride,
    String? senderNameOverride,
    String? senderImageOverride,
    List<String>? participants, 
  }) async {
    if (currentUserId == null) return null;

    final now = DateTime.now().millisecondsSinceEpoch;
    final tempId = 'pending_${now}_$currentUserId';

    final userDoc = await _firestore.collection('users').doc(currentUserId).get();
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
      imageUrl: 'file://$imagePath', 
      timestamp: now,
      status: 'sending',
      replyTo: replyToMessageId,
      adminId: senderIdOverride != null ? currentUserId : null,
      adminImage: senderIdOverride != null ? profileImage : null,
    );

    _uploadMediaAsync(
      chatId: chatId,
      file: File(imagePath),
      type: 'image',
      caption: caption,
      now: now,
      senderData: userData,
      replyToMessageId: replyToMessageId,
      tempId: tempId,
      onConfirmed: onConfirmed,
      onError: onError,
      senderIdOverride: senderIdOverride,
      senderNameOverride: senderNameOverride,
      senderImageOverride: senderImageOverride,
      participants: participants,
    );

    return optimisticMessage;
  }

  Future<Message?> sendVideoMessage(
    String chatId,
    String videoPath, {
    String? caption,
    String? replyToMessageId,
    void Function(Message confirmedMessage)? onConfirmed,
    void Function(String error)? onError,
    String? senderIdOverride,
    String? senderNameOverride,
    String? senderImageOverride,
    List<String>? participants,
  }) async {
    if (currentUserId == null) throw Exception('User not logged in');
    final now = DateTime.now().millisecondsSinceEpoch;
    final tempId = 'pending_video_${now}_$currentUserId';

    final userDoc = await _firestore.collection('users').doc(currentUserId).get();
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
      documentUrl: 'file://$videoPath', // Temporary mapping
      timestamp: now,
      status: 'sending',
      replyTo: replyToMessageId,
      adminId: senderIdOverride != null ? currentUserId : null,
      adminImage: senderIdOverride != null ? profileImage : null,
    );

    _uploadMediaAsync(
      chatId: chatId,
      file: File(videoPath), 
      type: 'video',
      caption: caption,
      now: now,
      senderData: userData,
      replyToMessageId: replyToMessageId,
      tempId: tempId,
      onConfirmed: onConfirmed,
      onError: onError,
      senderIdOverride: senderIdOverride,
      senderNameOverride: senderNameOverride,
      senderImageOverride: senderImageOverride,
      participants: participants,
    );

    return optimisticMessage;
  }

  Future<Message?> sendAudioMessage(
    String chatId, 
    String audioPath, {
    int? durationSeconds,
    String? caption,
    String? replyToMessageId,
    void Function(Message confirmedMessage)? onConfirmed,
    void Function(String error)? onError,
    String? senderIdOverride,
    String? senderNameOverride,
    String? senderImageOverride,
    List<String>? participants,
    String messageType = 'audio', // [NEW] Allow override
  }) async {
    if (currentUserId == null) return null;
    final now = DateTime.now().millisecondsSinceEpoch;
    final tempId = 'pending_voice_${now}_$currentUserId';

    final userDoc = await _firestore.collection('users').doc(currentUserId).get();
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
      documentUrl: 'file://$audioPath', 
      audioDuration: durationSeconds,
      timestamp: now,
      status: 'sending',
      replyTo: replyToMessageId,
      adminId: senderIdOverride != null ? currentUserId : null,
      adminImage: senderIdOverride != null ? profileImage : null,
    );

    _uploadMediaAsync(
      chatId: chatId,
      file: File(audioPath),
      type: messageType, // Use dynamic type
      caption: caption,
      now: now,
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
    );
    
    return optimisticMessage;
  }
  
  Future<Message?> sendAudioFileMessage(
    String chatId, 
    String audioPath, {
    String? caption,
    String? replyToMessageId,
    String? senderIdOverride,
    String? senderNameOverride,
    String? senderImageOverride,
    List<String>? participants,
  }) async {
    return sendAudioMessage(
      chatId, 
      audioPath, 
      caption: caption,
      replyToMessageId: replyToMessageId,
      senderIdOverride: senderIdOverride,
      senderNameOverride: senderNameOverride,
      senderImageOverride: senderImageOverride,
      participants: participants,
      messageType: 'audio_file', // [NEW] Specify type
    );
  }

  Future<Message?> sendDocumentMessage(
    String chatId,
    String filePath, {
    String? caption,
    String? replyToMessageId,
    void Function(Message confirmedMessage)? onConfirmed,
    void Function(String error)? onError,
    String? senderIdOverride,
    String? senderNameOverride,
    String? senderImageOverride,
    List<String>? participants,
  }) async {
    if (currentUserId == null) throw Exception('User not logged in');
    final now = DateTime.now().millisecondsSinceEpoch;
    final tempId = 'pending_doc_${now}_$currentUserId';

    final userDoc = await _firestore.collection('users').doc(currentUserId).get();
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
      documentUrl: 'file://$filePath',
      timestamp: now,
      status: 'sending',
      replyTo: replyToMessageId,
      adminId: senderIdOverride != null ? currentUserId : null,
      adminImage: senderIdOverride != null ? profileImage : null,
    );

    _uploadMediaAsync(
      chatId: chatId,
      file: File(filePath),
      type: 'document',
      caption: caption,
      now: now,
      senderData: userData,
      replyToMessageId: replyToMessageId,
      tempId: tempId,
      onConfirmed: onConfirmed,
      onError: onError,
      senderIdOverride: senderIdOverride,
      senderNameOverride: senderNameOverride,
      senderImageOverride: senderImageOverride,
      participants: participants,
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
  }) async {
    if (currentUserId == null) return null;
    final now = DateTime.now().millisecondsSinceEpoch;
    
    final userDoc = await _firestore.collection('users').doc(currentUserId).get();
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
        'address': address
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
      if (senderIdOverride != null) userIdsToUpdate.add(senderIdOverride);
      else if (currentUserId != null) userIdsToUpdate.add(currentUserId!);
      
      for (final userId in userIdsToUpdate) {
         try {
           await _rtdb.ref('userChats/$userId/$chatId').update({
             'lastMessage': lastMessageData, 
             'updatedAt': now, 
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
    required File file,
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
  }) async {
    try {
      final folder = type == 'image' ? 'chat_images' : 
                     type == 'video' ? 'chat_videos' :
                     (type == 'audio' || type == 'audio_file') ? 'chat_voices' : 'chat_documents';
      String ext;
      if (type == 'image') {
        ext = '.jpg';
      } else if (type == 'video') {
        ext = '.mp4';
      } else if (type == 'audio' || type == 'audio_file') {
        final path = file.path;
        final dotIndex = path.lastIndexOf('.');
        if (dotIndex != -1 && dotIndex < path.length - 1) {
          ext = path.substring(dotIndex); // Includes the dot, e.g., ".mp3"
        } else {
          ext = '.m4a';
        }
      } else {
        ext = '_${file.uri.pathSegments.last}';
      }
                  
      final fileName = '${now}_${type}$ext';
      final storageRef = _storage.ref().child('$folder/$chatId/$fileName');
      
      debugPrint('🚀 Starting media upload: $fileName to path: $folder/$chatId/$fileName');
      
      final uploadTask = await storageRef.putFile(
        file,
        SettableMetadata(contentType: type == 'video' ? 'video/mp4' : 
                                    (type == 'audio' || type == 'audio_file') ? 'audio/mpeg' : 
                                    type == 'image' ? 'image/jpeg' : null),
      );
      final derivedUrl = await uploadTask.ref.getDownloadURL();
      
      debugPrint('✅ Upload successful. URL: $derivedUrl');

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
        'status': 'sent',
      };
      
      if (type == 'image') messageData['imageUrl'] = derivedUrl;
      else if (type == 'video') messageData['documentUrl'] = derivedUrl;
      else if (type == 'audio' || type == 'audio_file') {
         messageData['documentUrl'] = derivedUrl;
         if (duration != null) messageData['audioDuration'] = duration;
      }
      else if (type == 'document') {
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
      String icon = type == 'image' ? '📷 Photo' :
                    type == 'video' ? '📹 Video' :
                    type == 'audio' ? '🎤 Voice message' : 
                    type == 'audio_file' ? '🎵 Audio' : '📄 Document';

      await _rtdb.ref('chats/$chatId/lastMessage').set({
        'content': caption?.isNotEmpty == true ? caption : icon,
        'timestamp': now,
        'senderId': senderIdOverride ?? currentUserId,
        'senderName': senderNameOverride ?? '$firstName $lastName'.trim(),
        'type': type,
        'status': 'sent',
      });
      await _rtdb.ref('chats/$chatId/updatedAt').set(now);

      final userIdsToUpdate = Set<String>.from(participants ?? []);
      if (senderIdOverride != null) userIdsToUpdate.add(senderIdOverride);
      else if (currentUserId != null) userIdsToUpdate.add(currentUserId!);
      
      for (final userId in userIdsToUpdate) {
         try {
           await _rtdb.ref('userChats/$userId/$chatId').update({
             'lastMessage': {
                'content': caption?.isNotEmpty == true ? caption : icon,
                'timestamp': now,
                'senderId': senderIdOverride ?? currentUserId,
                'senderName': senderNameOverride ?? '$firstName $lastName'.trim(),
                'type': type,
                'status': 'sent',
             }, 
             'updatedAt': now, 
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
    }
  }


}
