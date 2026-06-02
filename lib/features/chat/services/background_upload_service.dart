import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:workmanager/workmanager.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:diaspora_nearby/firebase_options.dart';

const String backgroundUploadTask = "backgroundUploadTask";

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    debugPrint('BackgroundUploadService: Executing task: $taskName');
    if (taskName == backgroundUploadTask && inputData != null) {
      try {
        if (Firebase.apps.isEmpty) {
          await Firebase.initializeApp(
            options: DefaultFirebaseOptions.currentPlatform,
          );
        }

        final chatId = inputData['chatId'] as String;
        final messageId = inputData['messageId'] as String;
        final filePath = inputData['filePath'] as String;
        final type = inputData['type'] as String;
        final fileName = inputData['fileName'] as String;

        // Prevent double-upload if already handled by foreground
        final docRef = FirebaseFirestore.instance
            .collection('chats')
            .doc(chatId)
            .collection('messages')
            .doc(messageId);

        final docSnap = await docRef.get();
        if (docSnap.exists) {
          final status = docSnap.data()?['status'];
          if (status == 'sent' || status == 'delivered' || status == 'read') {
            debugPrint(
              'BackgroundUploadService: Message $messageId already sent. Skipping.',
            );
            return Future.value(true);
          }
        }

        final file = File(filePath);
        if (!file.existsSync()) {
          debugPrint(
            'BackgroundUploadService: File not found: $filePath (OS might have cleared cache)',
          );
          return Future.value(false);
        }

        final folder = type == 'image'
            ? 'chat_images'
            : type == 'video'
            ? 'chat_videos'
            : type == 'voice'
            ? 'chat_voices'
            : type == 'audio_file'
            ? 'chat_audio'
            : 'chat_documents';

        final storageRef = FirebaseStorage.instance.ref().child(
          '$folder/$chatId/$fileName',
        );

        String mimeType = 'application/octet-stream';
        if (type == 'image') {
          mimeType = 'image/jpeg';
        } else if (type == 'video') {
          mimeType = 'video/mp4';
        } else if (type == 'voice' || type == 'audio_file') {
          if (fileName.endsWith('.m4a'))
            mimeType = 'audio/mp4';
          else if (fileName.endsWith('.mp3'))
            mimeType = 'audio/mpeg';
          else if (fileName.endsWith('.aac'))
            mimeType = 'audio/aac';
          else if (fileName.endsWith('.wav'))
            mimeType = 'audio/wav';
          else
            mimeType = 'audio/mpeg';
        }

        final storageMetadata = SettableMetadata(
          contentType: mimeType,
          cacheControl: 'public, max-age=31536000',
        );

        debugPrint('BackgroundUploadService: Starting upload for $fileName');
        final uploadTask = await storageRef.putFile(file, storageMetadata);
        final downloadUrl = await uploadTask.ref.getDownloadURL();

        debugPrint('BackgroundUploadService: Upload successful: $downloadUrl');

        final updateData = <String, dynamic>{'status': 'sent'};

        if (type == 'image') {
          updateData['imageUrl'] = downloadUrl;
        } else if (type == 'video' ||
            type == 'voice' ||
            type == 'audio_file' ||
            type == 'document') {
          updateData['documentUrl'] = downloadUrl;
        }

        // Set with merge in case the placeholder was already written
        await docRef.set(updateData, SetOptions(merge: true));

        // Update the chat lastMessage
        final chatDoc = await FirebaseFirestore.instance
            .collection('chats')
            .doc(chatId)
            .get();
        if (chatDoc.exists) {
          final chatData = chatDoc.data()!;
          final lastMessage = chatData['lastMessage'];
          if (lastMessage != null && lastMessage['id'] == messageId) {
            await FirebaseFirestore.instance
                .collection('chats')
                .doc(chatId)
                .set({
                  'lastMessage': {'status': 'sent'},
                }, SetOptions(merge: true));
          }
        }

        debugPrint('BackgroundUploadService: Firestore updated successfully');
        return Future.value(true);
      } catch (e) {
        debugPrint('BackgroundUploadService Error: $e');
        return Future.value(false);
      }
    }
    return Future.value(true);
  });
}

class BackgroundUploadService {
  static Future<void> initialize() async {
    if (kIsWeb) return;
    try {
      await Workmanager().initialize(callbackDispatcher, isInDebugMode: false);
    } catch (e) {
      debugPrint('Error initializing Workmanager: $e');
    }
  }

  static Future<void> enqueueUpload({
    required String chatId,
    required String messageId,
    required String filePath,
    required String type,
    required String fileName,
  }) async {
    if (kIsWeb) return;
    try {
      await Workmanager().registerOneOffTask(
        messageId,
        backgroundUploadTask,
        inputData: {
          'chatId': chatId,
          'messageId': messageId,
          'filePath': filePath,
          'type': type,
          'fileName': fileName,
        },
        constraints: Constraints(networkType: NetworkType.connected),
        backoffPolicy: BackoffPolicy.exponential,
        backoffPolicyDelay: const Duration(seconds: 10),
      );
      debugPrint('BackgroundUploadService: Task enqueued for $messageId');
    } catch (e) {
      debugPrint('Error enqueuing upload: $e');
    }
  }

  static Future<void> cancelUpload(String messageId) async {
    if (kIsWeb) return;
    try {
      await Workmanager().cancelByUniqueName(messageId);
    } catch (e) {
      debugPrint('Error cancelling upload task: $e');
    }
  }
}
