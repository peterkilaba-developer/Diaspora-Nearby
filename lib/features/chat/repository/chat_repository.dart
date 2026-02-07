import 'dart:async';
import 'package:universal_io/io.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart' hide Transaction;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:diaspora_nearby/features/chat/services/chat_local_service.dart';

// Corrected Internal Imports
import 'package:diaspora_nearby/features/chat/models/chat.dart';
import 'package:diaspora_nearby/features/chat/models/message.dart';
import 'package:diaspora_nearby/features/profile/models/profile_data.dart';
import 'package:diaspora_nearby/features/profile/repository/profile_repository.dart';
// import 'package:diaspora_nearby/core/services/local_cache_service.dart'; // Deprecated
// Deprecated
// import 'package:isar/isar.dart';
// import 'package:diaspora_nearby/core/services/database_service.dart';
// import 'package:diaspora_nearby/features/shared/data/local/entities/chat_entity.dart';

// If user_provider is wrong, we'll try to find it or remove if unused.
// found 'features\chat\providers\chat_identity_provider.dart' but not core.
// The code uses `ref.read(userProvider)?.uid`. I need to find where `userProvider` is defined.
// search result showed 'models\profile_data.dart' but not provider.
// I will comment out userProvider import and usage for now and assume `FirebaseAuth` or passed `uid`.
// Actually, `ChatRepository` usually takes `Ref`.
// Let's assume `currentUserId` getter needs to use `FirebaseAuth.instance.currentUser?.uid` if provider missing.

import 'package:firebase_auth/firebase_auth.dart';
import '../services/chat_messaging_service.dart';
import 'package:diaspora_nearby/features/events/repository/event_repository.dart';
import 'package:diaspora_nearby/features/organization/repository/organization_repository.dart';

final chatRepositoryProvider = Provider<ChatRepository>(
  (ref) => ChatRepository(ref),
);

final typingIndicatorsProvider = StreamProvider.family<List<String>, String>((
  ref,
  chatId,
) {
  final chatRepo = ref.watch(chatRepositoryProvider);
  return chatRepo.subscribeToTypingIndicators(chatId);
});

class ChatRepository {
  final Ref _ref;
  final FirebaseDatabase _rtdb = FirebaseDatabase.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final ChatLocalService _localService;

  final _chatsController = StreamController<List<Chat>>.broadcast();
  final List<Chat> _chatsCache = [];
  StreamSubscription? _chatsSubscription;

  ChatRepository(this._ref) : _localService = ChatLocalService() {
    // Persistence moved to main.dart to avoid race conditions
  }

  // Getter for current user ID
  String? get currentUserId => FirebaseAuth.instance.currentUser?.uid;

  void dispose() {
    _chatsController.close();
    // Duplicate removed
    _chatsSubscription?.cancel();
    _realtimeSubscription?.cancel(); // [NEW]
  }

  // [NEW] Persistent subscription for Isar sync
  StreamSubscription? _realtimeSubscription;

  // ============================================
  // FETCHING & STREAMS
  // ============================================

  // ============================================
  // FETCHING & STREAMS (Isar Implementation)
  // ============================================

  Stream<List<Chat>> subscribeToUserChats() {
    if (currentUserId == null) return const Stream.empty();
    final uid = currentUserId!;

    // 1. Start Sync (Fire and Forget) - Mostly for Isar population
    // 1. Start Sync (Real-time Listener)
    // Replaces one-time _syncUserChats with persistent listener
    _startRealtimeSync(uid);

    // 2. Watch Data Source
    // WEB: Fallback to RTDB or handle differently if needed
    // For now, we return empty stream on web if not using local service for watching
    // But ChatLocalService handles web stub returning empty stream.
    // However, we might want a real implementation for Web using RTDB listeners?
    // The original code returned local stream.
    // Let's rely on _localService.watchUserChats() which returns empty on web.
    // On Web, we might want to implement a direct RTDB/Firestore watcher here if local db is missing?
    // Original code: if (_isar == null) ... return Stream.empty();
    // So effectively Web had empty history list? That seems wrong for a PWA.
    // But let's replicate original behavior for now (Isar isolation) and fix functionalities later.
    if (kIsWeb) {
       // Existing web behavior was "no local persistence", so watching local entities returned nothing.
       // But we probably want to watch RTDB 'userChats' instead?
       // For this refactor, I will stick to exact behavior: delegate to service.
       return _localService.watchUserChats();
    }
    return _localService.watchUserChats();
  }

  // [NEW] Real-time Sync (RTDB -> Isar)
  // [NEW] Real-time Sync (RTDB -> Isar)
  void _startRealtimeSync(String uid) {
    if (_realtimeSubscription != null) return; // Already listening

    debugPrint('ðŸ”„ Starting real-time chat sync for $uid');

    // [FIX] Initial Sync for fast population
    // Run this in background to populating cache immediately while listener connects
    _syncUserChats(uid);

    final userChatsRef = _rtdb.ref('userChats/$uid');

    // Helper to process a single chat update
    Future<void> processChatUpdate(
      String chatId,
      Map<dynamic, dynamic> data,
    ) async {
      try {
        // 1. Check metadata
        if (data['isDeleted'] == true) {
          await _localService.deleteChat(chatId);
          return;
        }

        // 2. Fetch full chat data (fetch fresh to ensure consistency)
        // Optimization: If we only have unreadCount update, we could just update the entity.
        // But 'chats/id' might have changed too (lastMessage).
        final chatSnapshot = await _rtdb.ref('chats/$chatId').get();
        if (chatSnapshot.exists && chatSnapshot.value is Map) {
          final chatData = Map<String, dynamic>.from(chatSnapshot.value as Map);

          // Merge specifics
          chatData['pinned'] = data['pinned'];
          chatData['pinnedBottom'] = data['pinnedBottom'];
          chatData['muted'] = data['muted'];
          chatData['unreadCount'] = data['unreadCount'];

          // Prefer user-specific lastMessage/updatedAt if present
          if (data['lastMessage'] != null) {
            chatData['lastMessage'] = data['lastMessage'];
          }
          if (data['updatedAt'] != null) {
            chatData['updatedAt'] = data['updatedAt'];
          }

          // [NEW] Delivery Receipt Logic
          try {
            final lastMsg = chatData['lastMessage'];
            if (lastMsg is Map) {
              final senderId = lastMsg['senderId'];
              final status = lastMsg['status'];
              final msgId = lastMsg['id'];

              // If message is from someone else, and status is 'sent', mark as 'delivered'
              if (senderId != null &&
                  senderId != uid &&
                  status == 'sent' &&
                  msgId != null &&
                  msgId.toString().isNotEmpty) {
                final String mId = msgId.toString();
                // 1. Update specific message
                _rtdb
                    .ref('chats/$chatId/messages/$mId/status')
                    .set('delivered');

                // 2. Update chat lastMessage (global)
                _rtdb.ref('chats/$chatId/lastMessage/status').set('delivered');

                // 3. Update Sender's view explicitly
                _rtdb
                    .ref('userChats/$senderId/$chatId/lastMessage/status')
                    .set('delivered');
              }
            }
          } catch (e) {
            debugPrint('Error handling delivery receipt: $e');
          }

          final chat = Chat.fromRTDB(chatId, chatData);
          await _localService.saveChat(chat);
        }
      } catch (e) {
        debugPrint('Error syncing chat $chatId: $e');
      }
    }

    // Listen for CHANGES (Optimized)
    // We used to listen to onValue (all data), which caused N writes for 1 update.
    _realtimeSubscription = userChatsRef.onChildChanged.listen((event) {
      if (event.snapshot.key != null && event.snapshot.value != null) {
        processChatUpdate(event.snapshot.key!, event.snapshot.value as Map);
      }
    });
    // Listen for ADDITIONS (New chats)
    // Note: onChildAdded fires for EXISTING initial children too?
    // Yes, onChildAdded iterates all existing children on connect.
    // Also listen for ADDED children (new chats)
    // [FIX] Add safe check for null/type before casting
    userChatsRef.onChildAdded.listen((event) {
      if (event.snapshot.key != null && event.snapshot.value is Map) {
        processChatUpdate(event.snapshot.key!, event.snapshot.value as Map);
      }
    });



    // Listen for REMOVALS
    userChatsRef.onChildRemoved.listen((event) {
      if (event.snapshot.key != null) {
        final chatId = event.snapshot.key!;
        _localService.deleteChat(chatId);
      }
    });
  }

  // Legacy one-time sync (kept for reference or manual triggers, but _startRealtimeSync covers it)
  Future<void> _syncUserChats(String uid) async {
    try {
      final userChatsRef = _rtdb.ref('userChats/$uid');
      // One-time fetch to sync current state
      final snapshot = await userChatsRef.get();
      if (!snapshot.exists || snapshot.value == null) return;

      final data = snapshot.value as Map;
      final chatIds = data.keys.map((e) => e.toString()).toList();

      for (final chatId in chatIds) {
        // Fetch latest chat data from RTDB
        final chatSnapshot = await _rtdb.ref('chats/$chatId').get();
        if (chatSnapshot.exists) {
          final chatData = Map<String, dynamic>.from(chatSnapshot.value as Map);

          // Merge user specifics
          final rawSpecifics = data[chatId];
          if (rawSpecifics is Map) {
            // [NEW] Check for Soft Delete
            if (rawSpecifics['isDeleted'] == true) {
              await _localService.deleteChat(chatId);
              continue;
            }

            chatData['pinned'] = rawSpecifics['pinned'];
            chatData['pinnedBottom'] = rawSpecifics['pinnedBottom'];
            // Duplicates removed
            chatData['muted'] = rawSpecifics['muted'];
            chatData['unreadCount'] =
                rawSpecifics['unreadCount']; // [NEW] Merge unread count
            // Update lastMessage if newer in userChats (common pattern)
            if (rawSpecifics['lastMessage'] != null) {
              chatData['lastMessage'] = rawSpecifics['lastMessage'];
            }
            if (rawSpecifics['updatedAt'] != null) {
              chatData['updatedAt'] = rawSpecifics['updatedAt'];
            }
          }

          final chat = Chat.fromRTDB(chatId, chatData);
          await _localService.saveChat(chat);
        }
      }
    } catch (e) {
      debugPrint('Error syncing chats: $e');
    }
  }

  Future<void> _cacheChatLocally(Chat chat) async {
    await _localService.saveChat(chat);
  }

  Future<void> _cacheMessagesLocally(
    String chatId,
    List<Message> messages,
  ) async {
    await _localService.saveMessages(chatId, messages);
  }

  // ============================================
  // MESSAGES STREAM
  // ============================================

  Stream<List<Message>> subscribeToMessages(String chatId) {
    if (currentUserId == null) return const Stream.empty();

    final controller = StreamController<List<Message>>();
    int clearedAt = 0;
    List<Message> lastMessages = [];

    // 1. Emit cached messages immediately (filtered)
    // Note: We might optimize by caching 'clearedAt' too, but for now fetch fresh or assume 0 until loaded
    // To avoid showing cleared messages briefly, we could try to fetch clearedAt first?
    // But streams are async. Let's just emit.

    // 1. Emit cached messages immediately (filtered)
    // 1. Emit cached messages immediately (filtered)
    // Execute async without awaiting to not block stream return
    () async {
      try {
        final messages = await _localService.getCachedMessages(chatId);
        messages.sort((a, b) => b.timestamp.compareTo(a.timestamp));
        lastMessages = messages;
        if (!controller.isClosed) {
           controller.add(messages);
        }
      } catch (e) {
        debugPrint('Error reading Isar cached messages: $e');
      }
    }();

    // 2. Listen to ClearedAt timestamp
    final clearedAtSub = _rtdb
        .ref('userChats/$currentUserId/$chatId/clearedAt')
        .onValue
        .listen((event) {
          final val = event.snapshot.value;
          clearedAt = (val is int) ? val : 0;

          // Re-filter and emit if we have messages
          if (lastMessages.isNotEmpty && !controller.isClosed) {
            controller.add(
              lastMessages.where((m) => m.timestamp > clearedAt).toList(),
            );
          }
        });

    // 3. Listen to RTDB Messages
    final messagesRef = _rtdb.ref('chats/$chatId/messages');
    final query = messagesRef.orderByChild('timestamp').limitToLast(100);

    final subscription = query.onValue.listen((event) {
      if (!event.snapshot.exists) {
        lastMessages = [];
        if (!controller.isClosed) controller.add([]);
        return;
      }

      final data = event.snapshot.value as Map;
      final List<Message> messages = [];

      data.forEach((key, value) {
        if (value is Map) {
          try {
            messages.add(
              Message.fromRTDB(
                key.toString(),
                chatId,
                Map<String, dynamic>.from(value),
              ),
            );
          } catch (e) {
            debugPrint('Error parsing message $key: $e');
          }
        }
      });

      // Sort newest first
      messages.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      lastMessages = messages;

      if (!controller.isClosed) {
        // Filter by clearedAt
        controller.add(messages.where((m) => m.timestamp > clearedAt).toList());

        // Update cache (cache ALL, filtering is display-side logic typically,
        // to avoid re-downloading if user un-clears? No, clear is perm for user.
        // But cache is global? LocalCacheService is local.
        // We can cache all.
        // Update cache (cache ALL, filtering is display-side logic)
        _cacheMessagesLocally(chatId, messages);
      }
    });

    controller.onCancel = () {
      clearedAtSub.cancel();
      subscription.cancel();
    };

    return controller.stream;
  }

  Future<List<Chat>> getUserChats() async {
    if (currentUserId == null) return [];

    // 1. Return Local Isar Data
    final localChats = await _localService.getAllChats();

    if (localChats.isNotEmpty) {
      final chats = localChats;
      // Sort: Pinned Top -> Normal -> Pinned Bottom
      chats.sort((a, b) {
        if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
        if (a.isPinnedBottom != b.isPinnedBottom) return a.isPinnedBottom ? 1 : -1;
        return b.updatedAt.compareTo(a.updatedAt);
      });
      return chats;
    }

    // 2. Fetch Remote if empty (Fallback)
    // Note: subscription usually handles this, but for one-off calls:
    final snapshot = await _rtdb.ref('userChats/$currentUserId').get();
    if (!snapshot.exists || snapshot.value == null || snapshot.value is! Map) return [];

    final data = snapshot.value as Map;
    final List<Chat> chats = [];
    for (final key in data.keys) {
      // [NEW] Check soft delete
      if (data[key] is Map && data[key]['isDeleted'] == true) continue;

      final chat = await getChat(key.toString());
      if (chat != null) chats.add(chat);
    }

    // Sort: Pinned Top -> Normal -> Pinned Bottom
    chats.sort((a, b) {
      if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
      if (a.isPinnedBottom != b.isPinnedBottom) return a.isPinnedBottom ? 1 : -1;
      return b.updatedAt.compareTo(a.updatedAt);
    });

    // [NEW] Filter out blocked users
    final profile = _ref.read(userProfileProvider).value;
    final blockedUsers = profile?.blockedUsers ?? [];
    
    if (blockedUsers.isNotEmpty) {
      chats.removeWhere((chat) {
        if (chat.type == 'direct') {
          final otherId = chat.participants.firstWhere(
            (id) => id != currentUserId,
            orElse: () => '',
          );
          return blockedUsers.contains(otherId);
        }
        return false;
      });
    }

    return chats;
  }

  Future<void> updateChatLocally(Chat chat) async {
    // 1. Update Memory Cache
    final index = _chatsCache.indexWhere((c) => c.id == chat.id);
    if (index != -1) {
      _chatsCache[index] = chat;
    } else {
      _chatsCache.add(chat);
    }

    // 2. Update Isar
    await _localService.saveChat(chat);
  }

  Future<Chat?> getChat(String chatId, {bool force = false}) async {
    // 1. Try Memory (Optimistic)
    if (!force) {
      try {
        final mem = _chatsCache.firstWhere((c) => c.id == chatId);
        // Background refresh if memory found
        _fetchAndSaveChat(chatId);
        return mem;
      } catch (_) {}

      // 1. Try Local
      final localChat = await _localService.getChat(chatId);
      if (localChat != null) {
        // Background refresh if local found
        _fetchAndSaveChat(chatId);
        return localChat;
      }
    }

    // 3. Try Remote (RTDB)
    return await _fetchAndSaveChat(chatId);
  }

  Future<Chat?> _fetchAndSaveChat(String chatId) async {
    try {
      final snapshot = await _rtdb.ref('chats/$chatId').get();
      if (snapshot.exists && snapshot.value != null) {
        if (snapshot.value is Map) {
          final data = Map<String, dynamic>.from(snapshot.value as Map);
          final chat = Chat.fromRTDB(chatId, data);

          // [FIX] ONLY cache locally if the user has actually joined this chat.
          // Otherwise, just viewing a preview (getChat) will add it to the local DB,
          // and getUserChats checks local DB, so it appears as if joined.
          if (currentUserId != null) {
             final userChatSnap = await _rtdb.ref('userChats/$currentUserId/$chatId').get();
             
             // Check if joined AND not softly deleted
             bool shouldCache = false;
             if (userChatSnap.exists && userChatSnap.value is Map) {
                final uData = userChatSnap.value as Map;
                if (uData['isDeleted'] != true) {
                  shouldCache = true;
                }
             }

             if (shouldCache) {
               await _localService.saveChat(chat);
             }
          }

          return chat;
        }
      }
    } catch (e) {
      debugPrint('Error fetching chat $chatId: $e');
    }
    return null;
  }

  // ============================================
  // MESSAGING OPERATIONS
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
    // [NEW] Check for Blocked Status (Sender -> Recipient)
    // Only for direct chats
    if (chatId.startsWith('direct_')) {
      final chat = await getChat(chatId);
      if (chat != null && chat.participants.isNotEmpty) {
        final otherId = chat.participants.firstWhere(
          (id) => id != currentUserId,
          orElse: () => '',
        );
        
        if (otherId.isNotEmpty) {
          final profile = _ref.read(userProfileProvider).value;
          if (profile?.blockedUsers?.contains(otherId) ?? false) {
             throw Exception('You have blocked this user. Unblock them to send a message.');
          }
        }
      }
    }

    return _ref
        .read(chatMessagingServiceProvider)
        .sendTextMessage(
          chatId,
          content,
          replyToMessageId: replyToMessageId,
          senderIdOverride: senderIdOverride,
          senderNameOverride: senderNameOverride,
          senderImageOverride: senderImageOverride,
          participants: participants,
          mentions: mentions,
          richContent: richContent,
          replyToSenderId: replyToSenderId,
          type: type,
          metadata: metadata,
        );
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
  }) {
    return _ref
        .read(chatMessagingServiceProvider)
        .sendImageMessage(
          chatId,
          imageFile,
          caption: caption,
          replyToMessageId: replyToMessageId,
          onConfirmed: onConfirmed,
          onError: onError,
          senderIdOverride: senderIdOverride,
          senderNameOverride: senderNameOverride,
          senderImageOverride: senderImageOverride,
          participants: participants,
          replyToSenderId: replyToSenderId,
        );
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
  }) {
    return _ref
        .read(chatMessagingServiceProvider)
        .sendVideoMessage(
          chatId,
          videoFile,
          caption: caption,
          replyToMessageId: replyToMessageId,
          onConfirmed: onConfirmed,
          onError: onError,
          senderIdOverride: senderIdOverride,
          senderNameOverride: senderNameOverride,
          senderImageOverride: senderImageOverride,
          participants: participants,
          replyToSenderId: replyToSenderId,
        );
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
    String? replyToSenderId,
  }) {
    return _ref
        .read(chatMessagingServiceProvider)
        .sendAudioMessage(
          chatId,
          audioFile,
          durationSeconds: durationSeconds,
          caption: caption,
          replyToMessageId: replyToMessageId,
          onConfirmed: onConfirmed,
          onError: onError,
          senderIdOverride: senderIdOverride,
          senderNameOverride: senderNameOverride,
          senderImageOverride: senderImageOverride,
          participants: participants,
          replyToSenderId: replyToSenderId,
        );
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
  }) {
    return _ref
        .read(chatMessagingServiceProvider)
        .sendAudioFileMessage(
          chatId,
          audioFile,
          caption: caption,
          replyToMessageId: replyToMessageId,
          senderIdOverride: senderIdOverride,
          senderNameOverride: senderNameOverride,
          senderImageOverride: senderImageOverride,
          participants: participants,
          replyToSenderId: replyToSenderId,
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
  }) {
    return _ref
        .read(chatMessagingServiceProvider)
        .sendDocumentMessage(
          chatId,
          file,
          caption: caption,
          replyToMessageId: replyToMessageId,
          onConfirmed: onConfirmed,
          onError: onError,
          senderIdOverride: senderIdOverride,
          senderNameOverride: senderNameOverride,
          senderImageOverride: senderImageOverride,
          participants: participants,
          replyToSenderId: replyToSenderId,
        );
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
  }) {
    return _ref
        .read(chatMessagingServiceProvider)
        .sendLocationMessage(
          chatId,
          latitude: latitude,
          longitude: longitude,
          address: address,
          replyToMessageId: replyToMessageId,
          senderIdOverride: senderIdOverride,
          senderNameOverride: senderNameOverride,
          senderImageOverride: senderImageOverride,
          participants: participants,
          replyToSenderId: replyToSenderId,
        );
  }

  Future<XFile?> _pickVideo(ImageSource source) async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickVideo(
      source: source,
      maxDuration: const Duration(minutes: 5),
    );
    return pickedFile;
  }

  // ============================================
  // CREATION & ACTIONS
  // ============================================

  Future<Chat?> createDirectChat(String otherUserId) async {
    if (currentUserId == null) return null;
    final existingId = await getExistingDirectChat(otherUserId);
    if (existingId != null) return getChat(existingId);

    final newChatKey = _rtdb.ref('chats').push().key;
    final chatId = 'direct_$newChatKey';
    final now = DateTime.now().millisecondsSinceEpoch;

    final chatData = {
      'id': chatId, // [FIX] Ensure ID is in data
      'type': 'direct',
      'participants': [currentUserId, otherUserId],
      'createdAt': now,
      'updatedAt': now,
      'createdBy': currentUserId,
      'adminId': currentUserId,
    };

    await _rtdb.ref('chats/$chatId').set(chatData);
    await _rtdb.ref('userChats/$currentUserId/$chatId').set({
      'updatedAt': now,
      'chatId': chatId,
    });
    await _rtdb.ref('userChats/$otherUserId/$chatId').set({
      'updatedAt': now,
      'chatId': chatId,
    });

    return Chat.fromRTDB(chatId, chatData);
  }

  Future<String?> getExistingDirectChat(String otherUserId) async {
    if (currentUserId == null) return null;
    final myChatsSnapshot = await _rtdb.ref('userChats/$currentUserId').get();
    if (!myChatsSnapshot.exists) return null;

    final myChatsData = myChatsSnapshot.value as Map;
    for (final chatId in myChatsData.keys) {
      final chatSnapshot = await _rtdb.ref('chats/$chatId').get();
      if (chatSnapshot.exists) {
        final chatData = chatSnapshot.value as Map;
        if (chatData['type'] == 'direct') {
          final rawParticipants = chatData['participants'];
          List<String> participants = [];

          if (rawParticipants is List) {
            participants = rawParticipants.map((e) => e.toString()).toList();
          } else if (rawParticipants is Map) {
            if (rawParticipants.isNotEmpty) {
              final firstVal = rawParticipants.values.first;
              if (firstVal is bool || (firstVal is num && firstVal == 1)) {
                participants = rawParticipants.keys
                    .map((e) => e.toString())
                    .toList();
              } else {
                participants = rawParticipants.values
                    .map((e) => e.toString())
                    .toList();
              }
            }
          }

          if (participants.contains(otherUserId) &&
              participants.contains(currentUserId)) {
            return chatId.toString();
          }
        }
      }
    }
    return null;
  }

  /// [NEW] Create a Group Chat (Generic)
  Future<String?> createGroupChat({
    required String name,
    required List<String> participants,
    required List<String> admins,
    required Map<String, dynamic> metadata,
    String type = 'group',
  }) async {
    if (currentUserId == null) return null;

    final newChatKey = _rtdb.ref('chats').push().key;
    final chatId = '${type}_$newChatKey';
    final now = DateTime.now().millisecondsSinceEpoch;

    // Ensure creator is in participants and admins
    final finalParticipants = {...participants, currentUserId!}.toList();
    final finalAdmins = {...admins, currentUserId!}.toList();

    final chatData = {
      'id': chatId,
      'type': type,
      'name': name,
      'participants': finalParticipants,
      'admins': finalAdmins,
      'createdAt': now,
      'updatedAt': now,
      'createdBy': currentUserId,
      'metadata': metadata,
      'memberCount': finalParticipants.length,
      'lastMessage': {
        'content': 'Group created',
        'timestamp': now,
        'type': 'system',
        'status': 'sent',
      },
    };

    await _rtdb.ref('chats/$chatId').set(chatData);

    // Fan-out to userChats
    final Map<String, dynamic> updates = {};
    for (final uid in finalParticipants) {
      updates['userChats/$uid/$chatId'] = {
        'chatId': chatId,
        'updatedAt': now,
        'lastRead': now, // Mark as read initially
        'addedAt': now,
      };
    }
    await _rtdb.ref().update(updates);

    return chatId;
  } /*
  }               }
            }
         }
     }
     return null;
  }

  */

  Future<Chat?> createDirectChatWithMessage(
    String otherUserId,
    String initialMessage,
  ) async {
    final chat = await createDirectChat(otherUserId);
    if (chat != null) await sendTextMessage(chat.id, initialMessage);
    return chat;
  }

  // Missing methods restoration
  Future<List<ProfileData>> getDirectChatFriends() async {
    return getChatContacts();
  }

  Future<List<ProfileData>> getContactsWithDMs() async {
    if (currentUserId == null) return [];
    try {
      // 1. Get all user chats
      final chats = await getUserChats();

      // 2. Filter for direct chats and extract other user IDs
      final contactIds = <String>{};
      for (final chat in chats) {
        if (chat.type == 'direct') {
          for (final uid in chat.participants) {
            if (uid != currentUserId) {
              contactIds.add(uid);
            }
          }
        }
      }

      if (contactIds.isEmpty) return [];

      // 3. Fetch profiles for these IDs
      // Firestore 'whereIn' is limited to 10. We'll fetch in batches or individually.
      // For simplicity in this context, let's fetch individually (or batches of 10 if we want optimization).
      // Given typical user contact list size, let's do batches of 10.

      final List<ProfileData> profiles = [];
      final chunks = _chunkList(contactIds.toList(), 10);

      for (final chunk in chunks) {
        final snapshot = await _firestore
            .collection('users')
            .where(FieldPath.documentId, whereIn: chunk)
            .get();

        profiles.addAll(
          snapshot.docs.map((d) => ProfileData.fromJson(d.data())).toList(),
        );
      }

      return profiles;
    } catch (e) {
      debugPrint('Error fetching DM contacts: $e');
      return [];
    }
  }

  List<List<T>> _chunkList<T>(List<T> list, int chunkSize) {
    List<List<T>> chunks = [];
    for (var i = 0; i < list.length; i += chunkSize) {
      chunks.add(
        list.sublist(
          i,
          i + chunkSize > list.length ? list.length : i + chunkSize,
        ),
      );
    }
    return chunks;
  }

  // Keeping the original getChatContacts for backward compatibility or changing it
  // The user requirement implies "for user to add members only show users who the user has DM with".
  // I will make getChatContacts call this new logic to be safe for this specific screen,
  // or I can just leave getChatContacts as is (random 20 users) and use the new one in the screen.
  // The plan said "Update getChatContacts to call repo.getContactsWithDMs() ... OR create new one".
  // I'll create `getContactsWithDMs` and use IT in the screen.
  // But I'll place it here replacing the primitive getChatContacts to keep the file clean if getChatContacts is not used elsewhere critical.
  // Let's just Add `getContactsWithDMs` and keep `getChatContacts` for now to avoid breaking other things.

  Future<List<ProfileData>> getChatContacts() async {
    return getContactsWithDMs(); // Redirecting existing calls to the new logic as requested implicitly
  }

  Future<String> uploadGroupImage(String chatId, XFile image) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final fileName = 'group_icon_$now.jpg';
    final storageRef = _storage.ref().child('groups/$chatId/$fileName');

    final metadata = SettableMetadata(cacheControl: 'public, max-age=31536000');
    if (kIsWeb) {
      final bytes = await image.readAsBytes();
      await storageRef.putData(bytes, metadata);
    } else {
      await storageRef.putFile(File(image.path), metadata);
    }
    return await storageRef.getDownloadURL();
  }

  Future<Chat?> createGroup(
    String name,
    List<String> userIds, {
    XFile? groupImage,
    String? description, // [NEW]
    String? communityId, // [NEW]
    bool isPublic = false, // [NEW]
  }) async {
    if (currentUserId == null) return null;
    final allParticipants = {...userIds, currentUserId!}.toList();
    final newChatRef = _rtdb.ref('chats').push();
    final chatId = 'group_${newChatRef.key}';
    final now = DateTime.now().millisecondsSinceEpoch;

    String? imageUrl;
    if (groupImage != null) {
      final fileName = 'group_icon_$now.jpg';
      final storageRef = _storage.ref().child('groups/$chatId/$fileName');

      final metadata = SettableMetadata(
        cacheControl: 'public, max-age=31536000',
      );
      if (kIsWeb) {
        final bytes = await groupImage.readAsBytes();
        await storageRef.putData(bytes, metadata);
      } else {
        await storageRef.putFile(File(groupImage.path), metadata);
      }
      imageUrl = await storageRef.getDownloadURL();
    }

    debugPrint('Creating group: $name with participants: $allParticipants');
    final chatData = {
      'id': chatId, // [FIX] Include ID
      'type': 'group',
      'name': name,
      'photoUrl': imageUrl,
      'participants': allParticipants,
      'createdAt': now,
      'updatedAt': now,
      'createdBy': currentUserId,
      'admins': [currentUserId],
      if (description != null && description.isNotEmpty)
        'description': description,
      if (communityId != null) 'communityId': communityId, // [NEW]
      if (isPublic) 'isPublic': true, // [NEW]
      'lastMessage': {
        'content': 'Group created',
        'timestamp': now,
        'type': 'system',
        'status': 'sent',
      },
    };

    try {
      // [FIX] Write to 'chats/$chatId' (prefixed), not newChatRef (unprefixed)
      await _rtdb.ref('chats/$chatId').set(chatData);
      debugPrint('Chat data set for $chatId');

      await _rtdb.ref('chats/$chatId/updatedAt').set(now);

      // Add to userChats for all participants
      for (final userId in allParticipants) {
        await _rtdb.ref('userChats/$userId/$chatId').set({
          'updatedAt': now,
          'chatId': chatId,
          'pinned': false,
          'lastRead': now,
        });
        debugPrint('Added userChat for $userId');
      }

      // [NEW] Index Public Groups for Discovery
      if (isPublic) {
        await _rtdb.ref('discoverableChats/groups/$chatId').set({
          'id': chatId,
          'name': name,
          'photoUrl': imageUrl,
          'description': description,
          'communityId': communityId,
          'createdAt': now,
          'memberCount': 1, // Start with 1 (creator)
        });
      }

      return Chat.fromRTDB(chatId, chatData);
    } catch (e, stack) {
      debugPrint('Error creating group: $e\n$stack');
      rethrow;
    }
  }

  Future<void> joinGroup(String chatId) async {
    if (currentUserId == null) return;
    
    // [SECURITY] Verify Group is Public
    final isPublicSnap = await _rtdb.ref('chats/$chatId/isPublic').get();
    if (isPublicSnap.value != true) {
      throw Exception('Cannot join private group without invitation');
    }
    
    // 1. Add to participants
    final chatRef = _rtdb.ref('chats/$chatId');
    await chatRef.runTransaction((data) {
       if (data == null) return Transaction.success(data);
       final chat = Map<String, dynamic>.from(data as Map);
       // Check if 'participants' is List or Map (legacy safety)
       List<String> participants = [];
       if (chat['participants'] is List) {
          participants = List<String>.from(chat['participants']);
       } else if (chat['participants'] is Map) {
          participants = (chat['participants'] as Map).keys.map((e) => e.toString()).toList();
       }
       
       if (!participants.contains(currentUserId)) {
         participants.add(currentUserId!);
         chat['participants'] = participants;
         chat['memberCount'] = participants.length; // Update internal count too
       }
       return Transaction.success(chat);
    });

    // 2. Add to userChats
    await _rtdb.ref('userChats/$currentUserId/$chatId').set({
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
      'chatId': chatId,
      'pinned': false,
       'lastRead': DateTime.now().millisecondsSinceEpoch,
    });
    
    // 3. Update discoverable count if public (Best Effort)
    try {
      final discRef = _rtdb.ref('discoverableChats/groups/$chatId/memberCount');
      await discRef.runTransaction((data) {
        if (data == null) return Transaction.success(data);
        return Transaction.success((data as int? ?? 0) + 1);
      });
    } catch (_) {}
  }

  // ============================================
  // TYPING INDICATORS
  // ============================================

  Stream<List<String>> subscribeToTypingIndicators(String chatId) {
    // 1. Listen to typing node
    return _rtdb.ref('chats/$chatId/typing').onValue.map((event) {
      if (!event.snapshot.exists || event.snapshot.value == null) return [];

      final data = event.snapshot.value as Map;
      final List<String> userIds = [];
      final now = DateTime.now().millisecondsSinceEpoch;

      data.forEach((key, value) {
        if (key != currentUserId) {
          // Don't show own indicator
          if (value is Map && value['isTyping'] == true) {
            // Check timestamp to avoid stuck indicators (> 10s old)
            final timestamp = value['timestamp'] as int? ?? 0;
            if (now - timestamp < 10000) {
              userIds.add(key.toString());
            }
          }
        }
      });

      return userIds;
    });
  }

  Future<void> setTypingStatus(String chatId, bool isTyping) async {
    if (currentUserId == null) return;

    final ref = _rtdb.ref('chats/$chatId/typing/$currentUserId');
    if (isTyping) {
      await ref.set({'isTyping': true, 'timestamp': ServerValue.timestamp});
      // Auto-remove on disconnect
      await ref.onDisconnect().remove();
    } else {
      await ref.remove();
    }
  }

  Future<void> updateGroupInfo(
    String chatId, {
    String? name,
    String? image,
    String? description,
  }) async {
    final updates = <String, Object?>{};
    if (name != null) updates['name'] = name;
    if (image != null) updates['photoUrl'] = image;
    if (description != null) updates['description'] = description;
    if (updates.isNotEmpty) await _rtdb.ref('chats/$chatId').update(updates);
  }

  Future<bool> addGroupMember(String chatId, String userId) async {
    final snapshot = await _rtdb.ref('chats/$chatId/participants').get();
    if (!snapshot.exists) return false;

    final rawParticipants = snapshot.value;
    List<String> currentList = [];

    if (rawParticipants is List) {
      currentList = rawParticipants.map((e) => e.toString()).toList();
    } else if (rawParticipants is Map) {
      if (rawParticipants.isNotEmpty) {
        final firstVal = rawParticipants.values.first;
        if (firstVal is bool || (firstVal is num && firstVal == 1)) {
          currentList = rawParticipants.keys.map((e) => e.toString()).toList();
        } else {
          currentList = rawParticipants.values
              .map((e) => e.toString())
              .toList();
        }
      }
    }

    if (!currentList.contains(userId)) {
      currentList.add(userId);
      await _rtdb.ref('chats/$chatId/participants').set(currentList);
      await _rtdb.ref('userChats/$userId/$chatId').set({
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
        'chatId': chatId,
      });
      return true;
    }
    return false;
  }

  Future<bool> removeGroupMember(String chatId, String userId) async {
    final snapshot = await _rtdb.ref('chats/$chatId/participants').get();
    if (!snapshot.exists) return false;
    final currentList = List<String>.from(snapshot.value as List? ?? []);
    if (currentList.contains(userId)) {
      currentList.remove(userId);
      await _rtdb.ref('chats/$chatId/participants').set(currentList);
      await _rtdb.ref('userChats/$userId/$chatId').remove();
      return true;
    }
    return false;
  }

  Future<bool> promoteToAdmin(String chatId, String userId) async {
    // implementation ...
    return true;
  }

  // Brace removed

  // [NEW] Batch mark messages as read and decrement unread count
  Future<void> markMessagesAsRead(
    String chatId,
    List<String> messageIds,
  ) async {
    if (currentUserId == null || messageIds.isEmpty) return;

    // 1. Mark individual messages as read (if they are incoming)
    final updates = <String, Object?>{};
    bool shouldUpdateLastMessage = false;

    // Filter to only mark messages sent by OTHERS
    // We can't easily check senderId here without fetching.
    // Optimization: Assume UI filters list to only include incoming messages.
    // UI Responsibility: Only pass IDs of messages NOT sent by current user.

    for (final id in messageIds) {
      updates['chats/$chatId/messages/$id/status'] = 'read';
    }

    if (updates.isEmpty) return;

    try {
      await _rtdb.ref().update(updates);

      // 2. Decrement unread count
      final userChatRef = _rtdb.ref('userChats/$currentUserId/$chatId');
      final chatSnap = await userChatRef.get();
      
      if (chatSnap.exists) {
        final chatData = chatSnap.value as Map?;
        final isDeleted = chatData?['isDeleted'] == true;
        
        // Only decrement if NOT deleted (i.e. currently in main list)
        if (!isDeleted) {
          final unreadRef = userChatRef.child('unreadCount');
          await unreadRef.runTransaction((currentData) {
            if (currentData == null) return Transaction.abort();
            final current = (currentData is int) ? currentData : 0;
            final newVal = current - messageIds.length;
            return Transaction.success(newVal < 0 ? 0 : newVal);
          });
        }
      }

      // 3. Update lastMessage status if applicable
      // Not perfect but helps sync
      final lastMsgSnap = await _rtdb.ref('chats/$chatId/lastMessage').get();
      if (lastMsgSnap.exists) {
        final lastMsg = Map<String, dynamic>.from(lastMsgSnap.value as Map);
        if (messageIds.contains(lastMsgSnap.key) ||
            messageIds.contains(lastMsg['id'])) {
          if (lastMsg['senderId'] != currentUserId) {
            await _rtdb.ref('chats/$chatId/lastMessage/status').set('read');
          }
        }
      }
    } catch (e) {
      debugPrint('Error batch marking read: $e');
    }
  }

  Future<void> markChatAsRead(String chatId) async {
    if (currentUserId == null) return;
    try {
      // 1. Update lastRead timestamp (Safe as it's a separate node)
      await _rtdb
          .ref('lastRead/$currentUserId/$chatId')
          .set(DateTime.now().millisecondsSinceEpoch);

      // 2. ONLY reset unread count if the chat IS in the user's active list.
      // We check if the node exists and is NOT deleted.
      final userChatRef = _rtdb.ref('userChats/$currentUserId/$chatId');
      final snap = await userChatRef.get();
      
      if (snap.exists) {
        final data = snap.value as Map?;
        final isDeleted = data?['isDeleted'] == true;
        
        // Only update if it's NOT deleted. If it's deleted, we don't want to "undelete" it
        // just by viewing it (e.g. from discovery).
        if (!isDeleted) {
          await userChatRef.update({
            'unreadCount': 0,
          });
        }
      }
    } catch (e) {
      debugPrint('Error marking chat as read: $e');
    }
  }

  Future<void> markMessageAsRead(String chatId, String messageId) async {
    if (currentUserId == null) return;
    try {
      final messageRef = _rtdb.ref('chats/$chatId/messages/$messageId');
      final snapshot = await messageRef.get();
      if (snapshot.exists) {
        final data = snapshot.value as Map;
        if (data['senderId'] != currentUserId && data['status'] != 'read') {
          await messageRef.update({'status': 'read'});

          // Also update in lastMessage if it's the last message
          final lastMsgSnap = await _rtdb
              .ref('chats/$chatId/lastMessage')
              .get();
          if (lastMsgSnap.exists) {
            final lastMsgData = lastMsgSnap.value as Map;
            // This is a bit rough but works for simple cases
            if (lastMsgData['senderId'] != currentUserId) {
              await _rtdb.ref('chats/$chatId/lastMessage').update({
                'status': 'read',
              });
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Error marking message as read: $e');
    }
  }

  Future<int> getUnreadCount(String chatId) async => 0; // Simplified

  Future<void> toggleMute(String chatId, bool mute) async {
    if (currentUserId == null) return;
    await _rtdb.ref('userChats/$currentUserId/$chatId/muted').set(mute);
  }

  Future<void> togglePin(String chatId, bool pin) async {
    if (currentUserId == null) return;
    await _rtdb.ref('userChats/$currentUserId/$chatId/pinned').set(pin);
  }

  Future<void> togglePinBottom(String chatId, bool pin) async {
    if (currentUserId == null) return;
    await _rtdb.ref('userChats/$currentUserId/$chatId/pinnedBottom').set(pin);
  }

  Future<void> deleteChat(String chatId) async {
    if (currentUserId == null) return;

    // Check if it's a DM or other type.
    // Ideally we should check type, but "Soft Delete" is safe for all types as "Hide from my list".
    // For groups, "Leave" is distinct. If user calls "Delete" on group without leaving, hiding is appropriate behavior.

    final updates = {
      'isDeleted': true,
      'clearedAt': DateTime.now().millisecondsSinceEpoch,
    };

    await _rtdb.ref('userChats/$currentUserId/$chatId').update(updates);

    // Clear local cache if needed, or update it
    await _localService.deleteChat(chatId);
  }

  Future<void> clearChat(String chatId) async {
    if (currentUserId == null) return;
    // Set clearedAt timestamp. Messages before this will be hidden.
    await _rtdb
        .ref('userChats/$currentUserId/$chatId/clearedAt')
        .set(DateTime.now().millisecondsSinceEpoch);
    // Also clear lastMessage display or set to empty
    await _rtdb.ref('userChats/$currentUserId/$chatId/lastMessage').remove();
  }

  // [NEW] Clear mentions for a chat (removes sticky notifications)
  Future<void> clearChatMentions(String chatId) async {
    if (currentUserId == null) return;
    try {
      // Remove the 'mentions' node which tracks unread mentions
      await _rtdb.ref('userChats/$currentUserId/$chatId/mentions').remove();
    } catch (e) {
      debugPrint('Error clearing mentions: $e');
    }
  }

  Future<void> leaveChat(String chatId) async => deleteChat(chatId);

  Future<void> deleteMessage(
    String chatId,
    String messageId, {
    bool deleteForEveryone = false,
  }) async {
    if (currentUserId == null) return;
    try {
      final updates = <String, dynamic>{
        'content': 'ðŸš« Message deleted',
        'type': 'deleted',
      };

      if (deleteForEveryone) {
        updates['deletedForEveryone'] = true;
      } else {
        // Add to deletedFor list
        final msgRef = _rtdb.ref(
          'chats/$chatId/messages/$messageId/deletedFor',
        );
        final snapshot = await msgRef.get();
        final list = List<String>.from(snapshot.value as List? ?? []);
        if (!list.contains(currentUserId)) {
          list.add(currentUserId!);
          await msgRef.set(list);
        }
        return; // Local delete handled
      }

      await _rtdb.ref('chats/$chatId/messages/$messageId').update(updates);

      // Update lastMessage if it's the one being deleted
      final lastMsgSnap = await _rtdb.ref('chats/$chatId/lastMessage').get();
      if (lastMsgSnap.exists) {
        final lastMsgData = lastMsgSnap.value as Map;
        // Note: RTDB doesn't easily store message ID in lastMessage,
        // but we can check timestamp or just always update if it matches content
        if (lastMsgData['timestamp'] != null) {
          // We'll fetch the actual message to check ID
          final msgSnap = await _rtdb
              .ref('chats/$chatId/messages/$messageId')
              .get();
          final msgData = msgSnap.value as Map;
          if (lastMsgData['timestamp'] == msgData['timestamp']) {
            await _rtdb.ref('chats/$chatId/lastMessage').update(updates);

            // Also update for all participants
            final chatSnap = await _rtdb.ref('chats/$chatId').get();
            if (chatSnap.exists) {
              final chatData = chatSnap.value as Map;

              final rawParticipants = chatData['participants'];
              List<String> participants = [];
              if (rawParticipants is List) {
                participants = rawParticipants
                    .map((e) => e.toString())
                    .toList();
              } else if (rawParticipants is Map) {
                if (rawParticipants.isNotEmpty) {
                  final firstVal = rawParticipants.values.first;
                  if (firstVal is bool || (firstVal is num && firstVal == 1)) {
                    participants = rawParticipants.keys
                        .map((e) => e.toString())
                        .toList();
                  } else {
                    participants = rawParticipants.values
                        .map((e) => e.toString())
                        .toList();
                  }
                }
              }

              for (final uid in participants) {
                await _rtdb
                    .ref('userChats/$uid/$chatId/lastMessage')
                    .update(updates);
              }
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Error deleting message: $e');
    }
  }

  Future<void> forwardMessage(
    Message message,
    List<String> targetChatIds, {
    String? senderIdOverride,
    String? senderNameOverride,
    String? senderImageOverride,
  }) async {
    for (final chatId in targetChatIds) {
      await _ref
          .read(chatMessagingServiceProvider)
          .forwardMessage(
            chatId,
            message,
            senderIdOverride: senderIdOverride,
            senderNameOverride: senderNameOverride,
            senderImageOverride: senderImageOverride,
          );
    }
  }

  Future<void> addReaction(
    String chatId,
    String messageId,
    String emoji,
    String messageSenderId,
  ) async {
    return _ref
        .read(chatMessagingServiceProvider)
        .sendReaction(
          chatId: chatId,
          messageId: messageId,
          emoji: emoji,
          messageSenderId: messageSenderId,
        );
  }

  Future<void> removeReaction(
    String chatId,
    String messageId,
    String emoji,
  ) async {
    if (currentUserId == null) return;
    await _rtdb
        .ref('chats/$chatId/messages/$messageId/reactions/$currentUserId')
        .remove();
  }

  Future<List<Chat>> searchDiscoverableChats(String query) async {
    if (currentUserId == null) return [];

    final List<Chat> results = [];

    try {
      // [NEW] Get IDs of chats the user has already joined
      final userChatsSnap = await _rtdb.ref('userChats/$currentUserId').get();
      final Set<String> joinedChatIds = {};
      if (userChatsSnap.exists) {
        final value = userChatsSnap.value;
        if (value is Map) {
          value.forEach((key, val) {
            // ONLY skip if NOT deleted
            if (val is Map && val['isDeleted'] == true) {
              // It's deleted/left, so it SHOULD be discoverable again
            } else {
              joinedChatIds.add(key.toString());
            }
          });
        } else if (value is List) {
          // Fallback for list representation (index-based)
          for (int i = 0; i < value.length; i++) {
            final item = value[i];
            if (item is Map) {
              if (item['isDeleted'] != true) {
                joinedChatIds.add(item['chatId']?.toString() ?? i.toString());
              }
            } else if (item != null) {
              joinedChatIds.add(item.toString());
            }
          }
        }
      }

      // 1. Search Events
      final eventRepo = _ref.read(eventRepositoryProvider);
      final events = await eventRepo.searchEvents(query);

      for (final event in events) {
        // Filter: User is NOT already an attendee OR has it in their chat list
        if (event.attendees?.contains(currentUserId) == true) continue;
        if (event.chatId != null && joinedChatIds.contains(event.chatId)) continue;
        if (event.chatId == null) continue;

        results.add(
          Chat(
            id: event.chatId!, 
            communityId: '',
            type: 'event',
            name: event.title,
            photoUrl: event.imageUrl,
            participants: [],
            admins: [],
            createdBy: event.creatorId,
            createdAt: DateTime.now().millisecondsSinceEpoch, 
            updatedAt: DateTime.now().millisecondsSinceEpoch,
            eventId: event.id,
            memberCount: event.attendeeCount,
          ),
        );
      }

      // 2. Search Organizations
      final orgRepo = _ref.read(organizationRepositoryProvider);
      final orgs = await orgRepo.searchOrganizations(query);

      for (final org in orgs) {
        final orgId = org['id'];
        final admins = List<String>.from(org['admins'] ?? []);
        final followers = List<String>.from(org['followers'] ?? []);
        final chatId = org['chatId'] as String?;

        // Filter: User is NOT an admin/participant AND NOT a follower AND NOT in userChats
        if (admins.contains(currentUserId) || 
            followers.contains(currentUserId) ||
            (chatId != null && joinedChatIds.contains(chatId))) {
          continue;
        }

        if (chatId != null) {
          results.add(
            Chat(
              id: chatId,
              type: 'organization',
              name: org['businessName'] ?? org['name'] ?? 'Organization',
              photoUrl: org['logoUrl'] ?? org['profileImage'],
              participants: [],
              admins: admins,
              createdBy: org['superAdminId'] ?? '',
              createdAt: 0,
              updatedAt: 0,
              communityId: orgId,
            ),
          );
        }
      }

      // [NEW] 3. Search Public Groups
      final groupsSnap = await _rtdb.ref('discoverableChats/groups').get();
      if (groupsSnap.exists && groupsSnap.value is Map) {
        final groupsData = groupsSnap.value as Map;
        groupsData.forEach((key, value) {
          final groupStr = value is Map ? value : {};
          final name = groupStr['name']?.toString() ?? '';
          final desc = groupStr['description']?.toString() ?? '';
          final groupId = groupStr['id']?.toString() ?? key.toString();
          
          if (query.isEmpty || 
              name.toLowerCase().contains(query.toLowerCase()) || 
              desc.toLowerCase().contains(query.toLowerCase())) {
            
            // Filter: Hide if already in userChats
            if (joinedChatIds.contains(groupId)) return;
            
             results.add(
              Chat(
                id: groupId,
                communityId: groupStr['communityId'],
                type: 'group',
                name: name,
                photoUrl: groupStr['photoUrl'],
                participants: [],
                admins: [], 
                createdBy: '',
                createdAt: groupStr['createdAt'] is int ? groupStr['createdAt'] : 0,
                updatedAt: 0,
                description: desc,
                memberCount: groupStr['memberCount'] is int ? groupStr['memberCount'] : 0,
                metadata: {'isPublic': true}, 
                isPinned: false,
              ),
            );
          }
        });
      }

    } catch (e) {
      debugPrint('Error searching discoverable chats: $e');
    }

    return results;
  }

  Future<void> syncCommunityChats(List<String> communityIds) async {
    // Implementation...
    if (currentUserId == null) return;
    for (final commId in communityIds) {
      // [FIX] Use consistent prefix 'chat_' to match CommunityService
      final chatId = 'chat_$commId';
      await _rtdb.ref('userChats/$currentUserId/$chatId').update({
        'chatId': chatId,
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
        'isDeleted': false, // [NEW] Ensure it's visible if it was previously left
      });
    }
  }

  Future<String> getDisplayNameForChat(Chat chat) async {
    if (currentUserId == null) return chat.name;
    if (chat.isDirect) {
      final otherId = chat.getOtherParticipantId(currentUserId!);
      if (otherId == null) return chat.name;
      try {
        final doc = await _firestore.collection('users').doc(otherId).get();
        if (doc.exists) {
          final data = doc.data();
          return '${data?['firstName']} ${data?['lastName']}'.trim();
        }
      } catch (e) {
        /* ignore */
      }
    }
    return chat.name;
  }

  Future<int> getDeletableChatsCount() async {
    if (currentUserId == null) return 0;
    try {
      final snapshot = await _rtdb.ref('userChats/$currentUserId').get();
      if (!snapshot.exists) return 0;

      final data = snapshot.value as Map;
      int count = 0;

      // We must check each chat's TYPE to be sure it's not a community.
      // ID prefix is unreliable.
      for (final key in data.keys) {
        final chatId = key.toString();
        // Skip obvious ones first for performance
        if (chatId.startsWith('community_')) continue;

        final chat = await getChat(chatId);
        if (chat != null && !chat.isCommunity) {
          count++;
        }
      }
      return count;
    } catch (e) {
      debugPrint('Error counting deletable chats: $e');
      return 0;
    }
  }

  Future<void> clearAllChats() async {
    if (currentUserId == null) return;
    try {
      final snapshot = await _rtdb.ref('userChats/$currentUserId').get();
      if (!snapshot.exists) return;

      final data = snapshot.value as Map;

      for (final key in data.keys) {
        final chatId = key.toString();

        // Skip obvious prefix
        if (chatId.startsWith('community_')) continue;

        // Fetch to check type
        final chat = await getChat(chatId);

        // Only delete if verified NOT a community chat
        if (chat != null && !chat.isCommunity) {
          // We remove from userChats and LocalCache
          await _rtdb.ref('userChats/$currentUserId/$chatId').remove();
          await _localService.deleteChat(chatId);
        }
      }
    } catch (e) {
      debugPrint('Error clearing all chats: $e');
    }
  }

  Stream<LastMessage?> getLastMessageStream(String chatId) {
    return _rtdb.ref().child('chats/$chatId/lastMessage').onValue.map((event) {
      if (event.snapshot.value == null) return null;
      try {
        final data = Map<String, dynamic>.from(event.snapshot.value as Map);
        return LastMessage.fromRTDB(data);
      } catch (e) {
        return null;
      }
    });
  }
}

final chatLastMessageStreamProvider =
    StreamProvider.family<LastMessage?, String>((ref, chatId) {
      return ref.watch(chatRepositoryProvider).getLastMessageStream(chatId);
    });
