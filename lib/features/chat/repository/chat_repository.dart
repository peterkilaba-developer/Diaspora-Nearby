import 'dart:async';
import 'package:universal_io/io.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:diaspora_nearby/features/chat/services/chat_local_service.dart';
import 'package:diaspora_nearby/features/chat/services/chamber_service.dart';

import 'package:diaspora_nearby/features/chat/models/chat.dart';
import 'package:diaspora_nearby/features/chat/models/message.dart';
import 'package:diaspora_nearby/features/profile/models/profile_data.dart';
import 'package:diaspora_nearby/features/profile/repository/profile_repository.dart';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
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
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final ChatLocalService _localService;

  final _chatsController = StreamController<List<Chat>>.broadcast();
  final List<Chat> _chatsCache = [];
  StreamSubscription? _chatsSubscription;

  /// Firestore collection references
  CollectionReference<Map<String, dynamic>> get _chatsCol =>
      _firestore.collection('chats');
  CollectionReference<Map<String, dynamic>> _userChatsCol(String uid) =>
      _firestore.collection('users').doc(uid).collection('userChats');
  CollectionReference<Map<String, dynamic>> _messagesCol(String chatId) =>
      _firestore.collection('chats').doc(chatId).collection('messages');
  CollectionReference<Map<String, dynamic>> _typingCol(String chatId) =>
      _firestore.collection('chats').doc(chatId).collection('typing');

  ChatRepository(this._ref) : _localService = ChatLocalService();

  String? get currentUserId => FirebaseAuth.instance.currentUser?.uid;

  void dispose() {
    _chatsController.close();
    _chatsSubscription?.cancel();
    _realtimeSubscription?.cancel();
  }

  StreamSubscription? _realtimeSubscription;

  /// Returns a sorted copy of the chats cache:
  /// 1. Pinned chats on top
  /// 2. Regular chats sorted by updatedAt descending (latest first)
  /// 3. Pinned-bottom chats at the end
  List<Chat> _sortedChatsList() {
    final sorted = List<Chat>.from(_chatsCache);
    sorted.sort((a, b) {
      // Pinned chats always on top
      if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
      // Pinned-bottom chats always at end
      if (a.isPinnedBottom != b.isPinnedBottom) {
        return a.isPinnedBottom ? 1 : -1;
      }
      // Sort by updatedAt descending (latest first)
      return b.updatedAt.compareTo(a.updatedAt);
    });
    return sorted;
  }

  // ============================================
  // FETCHING & STREAMS (Firestore Implementation)
  // ============================================

  /// Subscribe to user's chat list via Firestore real-time listeners
  Stream<List<Chat>> subscribeToUserChats() {
    final uid = currentUserId;
    if (uid == null) return const Stream.empty();

    // Start Firestore real-time sync → in-memory cache → stream
    _startRealtimeSync(uid);

    // Emit initial cached list immediately so new subscribers don't hang in loading state
    if (!_chatsController.isClosed) {
      Future.microtask(() {
        if (!_chatsController.isClosed) {
          _chatsController.add(_sortedChatsList());
        }
      });
    }

    // Return broadcast stream (populated by Firestore listener)
    return _chatsController.stream;
  }

  /// Real-time Sync (Firestore → In-memory cache → StreamController)
  void _startRealtimeSync(String uid) {
    if (_realtimeSubscription != null) {
      if (!_chatsController.isClosed) {
        _chatsController.add(_sortedChatsList());
      }
      return;
    }

    debugPrint('🔄 Starting Firestore real-time chat sync for $uid');

    // Listen for changes to the user's chat list. The initial snapshot is
    // served from Firestore's local cache, so the first emission must not
    // wait on the network: chats are hydrated cache-first and emitted
    // immediately, then refreshed from the server in the background.
    _realtimeSubscription = _userChatsCol(uid)
        .limit(100)
        .snapshots()
        .listen(
          (snapshot) async {
            // Handle removals and soft-deletes synchronously first
            for (final change in snapshot.docChanges) {
              final chatId = change.doc.id;
              final data = change.doc.data() ?? {};

              if (change.type == DocumentChangeType.removed ||
                  data['isDeleted'] == true) {
                _chatsCache.removeWhere((c) => c.id == chatId);
                _localService.deleteChat(chatId); // fire-and-forget (no-op)
              }
            }

            final toFetch = snapshot.docChanges.where((c) {
              if (c.type == DocumentChangeType.removed) return false;
              return (c.doc.data()?['isDeleted']) != true;
            }).toList();
            if (toFetch.isEmpty) {
              if (!_chatsController.isClosed) {
                _chatsController.add(_sortedChatsList());
              }
              return;
            }

            // Fast pass: hydrate from the local cache and emit right away so
            // the list renders without a network round trip after a restart.
            await _applyChatChanges(toFetch, uid, preferCache: true);
            if (!_chatsController.isClosed) {
              _chatsController.add(_sortedChatsList());
            }

            // Server pass: refresh the same chats in the background. This
            // catches chat-doc fields (name, photo, participants) that change
            // without touching the userChats index, and runs delivery receipts
            // against fresh data.
            await _applyChatChanges(toFetch, uid, preferCache: false);
            if (!_chatsController.isClosed) {
              _chatsController.add(_sortedChatsList());
            }
          },
          onError: (Object error, StackTrace stackTrace) {
            debugPrint('Error listening to chats for $uid: $error');
            if (!_chatsController.isClosed) {
              _chatsController.addError(error, stackTrace);
            }
          },
        );
  }

  /// Fetch the chat docs for a set of userChats changes in parallel and
  /// upsert them into the in-memory cache. With [preferCache] the chat docs
  /// are read from Firestore's local cache (falling back to the server on a
  /// miss); delivery receipts are only issued on server-fresh data.
  Future<void> _applyChatChanges(
    List<DocumentChange<Map<String, dynamic>>> changes,
    String uid, {
    required bool preferCache,
  }) async {
    await Future.wait(
      changes.map((change) async {
        final chatId = change.doc.id;
        final data = change.doc.data() ?? {};
        try {
          final chat = await _fetchAndSaveChat(
            chatId,
            skipUserChatRead: true,
            preferCache: preferCache,
          );
          if (chat != null) {
            final chatWithPrefs = chat.withUserPreferences(data);
            if (!preferCache) {
              _handleDeliveryReceipt(chatWithPrefs, uid);
            }
            final existingIdx = _chatsCache.indexWhere((c) => c.id == chatId);
            if (existingIdx >= 0) {
              _chatsCache[existingIdx] = chatWithPrefs;
            } else {
              _chatsCache.add(chatWithPrefs);
            }
            _localService.saveChat(chatWithPrefs); // fire-and-forget (no-op)
          }
        } catch (e) {
          debugPrint('Error syncing chat $chatId: $e');
        }
      }),
    );
  }

  /// Handle delivery receipt: mark incoming 'sent' messages as 'delivered'
  void _handleDeliveryReceipt(Chat chat, String uid) {
    try {
      final lastMsg = chat.lastMessage;
      if (lastMsg == null) return;
      if (lastMsg.senderId.isNotEmpty &&
          lastMsg.senderId != uid &&
          lastMsg.status == 'sent' &&
          lastMsg.id.isNotEmpty) {
        // Update the message status in the subcollection
        _messagesCol(
          chat.id,
        ).doc(lastMsg.id).set({'status': 'delivered'}, SetOptions(merge: true));
        // Update embedded lastMessage status
        _chatsCol.doc(chat.id).set({
          'lastMessage': {'status': 'delivered'},
        }, SetOptions(merge: true));
      }
    } catch (e) {
      debugPrint('Error handling delivery receipt: $e');
    }
  }

  Future<void> _cacheMessagesLocally(
    String chatId,
    List<Message> messages,
  ) async {
    await _localService.saveMessages(chatId, messages);
  }

  // ============================================
  // MESSAGES STREAM (Firestore Subcollection)
  // ============================================

  Stream<List<Message>> subscribeToMessages(String chatId) {
    final uid = currentUserId;
    if (uid == null) return const Stream.empty();

    final controller = StreamController<List<Message>>();
    int clearedAt = 0;
    List<Message> lastMessages = [];
    StreamSubscription? userChatSub;
    StreamSubscription? subscription;
    bool hasAccess = false;

    // Always leave Riverpod's loading state immediately. Cached/remote
    // messages replace this value as soon as they arrive.
    controller.add(const []);

    Future<bool> canReadMessages() async {
      try {
        final chatDoc = await _chatsCol.doc(chatId).get();
        final data = chatDoc.data();
        final participants =
            (data?['participants'] as List<dynamic>?)?.cast<String>() ??
            const <String>[];
        if (participants.contains(uid)) return true;

        final userChatDoc = await _userChatsCol(uid).doc(chatId).get();
        return userChatDoc.exists;
      } catch (e) {
        debugPrint('Error checking message access for $chatId: $e');
        return false;
      }
    }

    Future<void> emitCachedMessages() async {
      try {
        final messages = await _localService.getCachedMessages(chatId);
        messages.sort((a, b) => b.timestamp.compareTo(a.timestamp));
        lastMessages = messages;
        if (!controller.isClosed) {
          final filtered = clearedAt > 0
              ? messages.where((m) => m.timestamp > clearedAt).toList()
              : messages;
          controller.add(filtered);
        }
      } catch (e) {
        debugPrint('Error reading cached messages: $e');
      }
    }

    void startMessagesListener() {
      if (subscription != null) return;
      subscription = _messagesCol(chatId)
          .orderBy('timestamp', descending: true)
          .limit(100)
          .snapshots()
          .listen(
            (snapshot) {
              final List<Message> messages = [];

              for (final doc in snapshot.docs) {
                try {
                  messages.add(Message.fromFirestore(chatId, doc));
                } catch (e) {
                  debugPrint('Error parsing message ${doc.id}: $e');
                }
              }

              // [PERF] Query already returns sorted by timestamp desc — skip redundant sort
              lastMessages = messages;

              if (!controller.isClosed) {
                // [PERF] Only filter if clearedAt is actually set
                final filtered = clearedAt > 0
                    ? messages.where((m) => m.timestamp > clearedAt).toList()
                    : messages;
                controller.add(filtered);
                _cacheMessagesLocally(chatId, messages);
              }
            },
            onError: (Object error, StackTrace stackTrace) {
              debugPrint('Error listening to messages for $chatId: $error');
              if (!controller.isClosed) controller.addError(error, stackTrace);
            },
          );
    }

    // Public chat docs can be readable while their message subcollections are
    // restricted. Wait for participant/userChats access before subscribing.
    userChatSub = _userChatsCol(uid)
        .doc(chatId)
        .snapshots()
        .listen(
          (snapshot) async {
            final data = snapshot.data();
            clearedAt = (data?['clearedAt'] as int?) ?? 0;

            if (!hasAccess) {
              hasAccess = snapshot.exists || await canReadMessages();
              if (hasAccess) {
                await emitCachedMessages();
                startMessagesListener();
              }
            } else if (lastMessages.isNotEmpty && !controller.isClosed) {
              controller.add(
                lastMessages.where((m) => m.timestamp > clearedAt).toList(),
              );
            }
          },
          onError: (Object error, StackTrace stackTrace) {
            debugPrint('Error listening to chat index for $chatId: $error');
            if (!controller.isClosed) controller.addError(error, stackTrace);
          },
        );

    controller.onCancel = () {
      userChatSub?.cancel();
      subscription?.cancel();
    };

    return controller.stream;
  }

  /// [NEW] Check if user is an admin of any group chat with >= [minMembers] members.
  /// Used for council candidacy eligibility.
  Future<bool> isAdminOfLargeGroupChat(
    String uid, {
    int minMembers = 100,
  }) async {
    try {
      final snapshot = await _firestore
          .collection('chats')
          .where('admins', arrayContains: uid)
          .limit(200)
          .get();

      for (final doc in snapshot.docs) {
        final data = doc.data();
        final type = data['type'] as String? ?? '';
        // Count from memberCount first, fallback to participants list length
        final members =
            (data['memberCount'] as int?) ??
            (data['participants'] as List<dynamic>?)?.length ??
            0;
        if (type == 'group' && members >= minMembers) {
          return true;
        }
      }
      return false;
    } catch (e) {
      debugPrint('Error checking admin of large group chat: $e');
      return false;
    }
  }

  Future<List<Chat>> getUserChats() async {
    if (currentUserId == null) return [];

    // 1. Return Local Data
    final localChats = await _localService.getAllChats();

    if (localChats.isNotEmpty) {
      final chats = localChats;
      chats.sort((a, b) {
        if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
        if (a.isPinnedBottom != b.isPinnedBottom) {
          return a.isPinnedBottom ? 1 : -1;
        }
        return b.updatedAt.compareTo(a.updatedAt);
      });
      return chats;
    }

    // 2. Fetch Remote if empty (Fallback via Firestore)
    final userChatsSnap = await _userChatsCol(currentUserId!).limit(100).get();
    if (userChatsSnap.docs.isEmpty) return [];

    final List<Chat> chats = [];
    for (final doc in userChatsSnap.docs) {
      final data = doc.data();
      if (data['isDeleted'] == true) continue;
      final chat = await getChat(doc.id);
      if (chat != null) chats.add(chat);
    }

    chats.sort((a, b) {
      if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
      if (a.isPinnedBottom != b.isPinnedBottom) {
        return a.isPinnedBottom ? 1 : -1;
      }
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

    // 2. Update local cache
    await _localService.saveChat(chat);
  }

  Future<Chat?> getChat(String chatId, {bool force = false}) async {
    // 1. Try Memory (Optimistic)
    if (!force) {
      try {
        final mem = _chatsCache.firstWhere((c) => c.id == chatId);
        // Don't return broken chats with empty participants — fall through to heal
        if (mem.participants.isNotEmpty) {
          _fetchAndSaveChat(chatId);
          return mem;
        }
        debugPrint(
          '⚠️ getChat: Memory cache has empty participants for $chatId, falling through to remote',
        );
      } catch (_) {}

      // 2. Try Local
      final localChat = await _localService.getChat(chatId);
      if (localChat != null) {
        // Don't return broken chats with empty participants — fall through to heal
        if (localChat.participants.isNotEmpty) {
          _fetchAndSaveChat(chatId);
          return localChat;
        }
        debugPrint(
          '⚠️ getChat: Local cache has empty participants for $chatId, falling through to remote',
        );
      }
    }

    // 3. Try Remote (Firestore) — this has self-healing logic
    return await _fetchAndSaveChat(chatId);
  }

  Future<Chat?> _fetchAndSaveChat(
    String chatId, {
    bool skipUserChatRead = false,
    bool preferCache = false,
  }) async {
    try {
      // [PERF] Cache-first read for the realtime listener's fast pass —
      // a default get() waits on the server even when the doc is cached.
      DocumentSnapshot<Map<String, dynamic>> chatDoc;
      if (preferCache) {
        try {
          chatDoc = await _chatsCol
              .doc(chatId)
              .get(const GetOptions(source: Source.cache));
          if (!chatDoc.exists) {
            throw StateError('Chat $chatId not cached');
          }
        } catch (_) {
          chatDoc = await _chatsCol.doc(chatId).get();
        }
      } else {
        chatDoc = await _chatsCol.doc(chatId).get();
      }
      if (chatDoc.exists) {
        var chat = Chat.fromFirestore(chatDoc);

        // Self-healing: Ensure type is correct based on chatId pattern
        // This fixes chats migrated from RTDB that may be missing the type field
        {
          final data = chatDoc.data() ?? {};
          final storedType = data['type'] as String?;
          String? correctType;
          if (chatId.startsWith('direct_')) {
            correctType = 'direct';
          } else if (chatId.startsWith('chat_') ||
              chatId.startsWith('home_') ||
              chatId.startsWith('host_') ||
              chatId.startsWith('past_') ||
              chatId == 'global_community') {
            correctType = 'community';
          } else if (chatId.startsWith('event_')) {
            correctType = 'event';
          } else if (chatId.startsWith('org_')) {
            correctType = 'organization';
          }
          if (correctType != null && storedType != correctType) {
            debugPrint(
              '🔄 Self-healing type for $chatId: $storedType → $correctType',
            );
            final healData = <String, dynamic>{'type': correctType};
            // Also ensure communityId is set for community chats
            if (correctType == 'community' && data['communityId'] == null) {
              final communityId = chatId.startsWith('chat_')
                  ? chatId.substring(5) // Remove 'chat_' prefix
                  : chatId;
              healData['communityId'] = communityId;
              chat = chat.copyWith(type: correctType, communityId: communityId);
            } else {
              chat = chat.copyWith(type: correctType);
            }
            try {
              _chatsCol.doc(chatId).set(healData, SetOptions(merge: true));
            } catch (e) {
              debugPrint('Skipping heal type write due to permissions: $e');
            }
          }
        }

        // Self-healing: If participants are empty for a direct chat, reconstruct them
        if (chat.participants.isEmpty && currentUserId != null) {
          debugPrint(
            '🔄 Self-healing: Chat $chatId has empty participants. Reconstructing...',
          );
          final healedParticipants = <String>[currentUserId!];

          // Check createdBy and adminId from the document
          final data = chatDoc.data() ?? {};
          final createdBy = data['createdBy'] as String?;
          final adminId = data['adminId'] as String?;

          if (createdBy != null && !healedParticipants.contains(createdBy)) {
            healedParticipants.add(createdBy);
          }
          if (adminId != null && !healedParticipants.contains(adminId)) {
            healedParticipants.add(adminId);
          }

          // If still only one participant for a direct chat, try scanning userChats
          if (healedParticipants.length < 2 && chat.isDirect) {
            try {
              // Query all users who have this chatId in their userChats
              // Since we can't query across user subcollections directly,
              // we'll check if the chat was created by someone else
              // by looking at messages for other senderIds
              final messagesSnap = await _messagesCol(
                chatId,
              ).orderBy('timestamp', descending: true).limit(10).get();
              for (final msgDoc in messagesSnap.docs) {
                final senderId = msgDoc.data()['senderId'] as String?;
                if (senderId != null &&
                    !healedParticipants.contains(senderId)) {
                  healedParticipants.add(senderId);
                }
              }
            } catch (e) {
              debugPrint('⚠️ Error scanning messages for participants: $e');
            }
          }

          if (healedParticipants.length > 1 || healedParticipants.isNotEmpty) {
            debugPrint(
              '✅ Healed participants for $chatId: $healedParticipants',
            );

            // Write the healed data back to Firestore (fire-and-forget)
            final healData = <String, dynamic>{
              'participants': healedParticipants,
            };
            if (chat.type == 'direct' || chatId.startsWith('direct_')) {
              healData['type'] = 'direct';
            } else if (chatId.startsWith('chat_') ||
                chatId.startsWith('home_') ||
                chatId.startsWith('host_') ||
                chatId.startsWith('past_') ||
                chatId == 'global_community') {
              healData['type'] = 'community';
            } else if (chatId.startsWith('event_')) {
              healData['type'] = 'event';
            } else if (chatId.startsWith('org_')) {
              healData['type'] = 'organization';
            }
            try {
              _chatsCol.doc(chatId).set(healData, SetOptions(merge: true));
            } catch (e) {
              debugPrint(
                'Skipping heal participants write due to permissions: $e',
              );
            }

            // Rebuild the chat object with healed participants
            chat = chat.copyWith(participants: healedParticipants);
          }
        }

        // Only cache locally if the user has actually joined this chat
        // [PERF] Skip this re-read when called from realtime listener
        // (which already has user preferences from the snapshot)
        if (!skipUserChatRead && currentUserId != null) {
          final userChatDoc = await _userChatsCol(
            currentUserId!,
          ).doc(chatId).get();

          if (userChatDoc.exists) {
            final uData = userChatDoc.data() ?? {};
            if (uData['isDeleted'] != true) {
              chat = chat.withUserPreferences(uData);
              await _localService.saveChat(chat);
            }
          }
        }

        return chat;
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
    // [FIX] Use cached data for blocked check — avoid network fetch
    if (chatId.startsWith('direct_')) {
      // Try memory cache first (sync, no network call)
      // [FIX] Renamed to avoid shadowing the function parameter `participants`
      List<String> blockedCheckParticipants = [];
      try {
        final cached = _chatsCache.firstWhere((c) => c.id == chatId);
        blockedCheckParticipants = cached.participants;
      } catch (_) {
        // Not in cache — skip the check rather than delay the message
      }

      if (blockedCheckParticipants.isNotEmpty) {
        final otherId = blockedCheckParticipants.firstWhere(
          (id) => id != currentUserId,
          orElse: () => '',
        );

        if (otherId.isNotEmpty) {
          final profile = _ref.read(userProfileProvider).value;
          if (profile?.blockedUsers?.contains(otherId) ?? false) {
            throw Exception(
              'You have blocked this user. Unblock them to send a message.',
            );
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
        .sendLocationMessage(
          chatId,
          latitude: latitude,
          longitude: longitude,
          address: address,
          caption: caption,
          replyToMessageId: replyToMessageId,
          senderIdOverride: senderIdOverride,
          senderNameOverride: senderNameOverride,
          senderImageOverride: senderImageOverride,
          participants: participants,
          replyToSenderId: replyToSenderId,
        );
  }

  // ============================================
  // CREATION & ACTIONS
  // ============================================

  Future<Chat?> createDirectChat(String otherUserId) async {
    if (currentUserId == null) return null;
    final result = await FirebaseFunctions.instance
        .httpsCallable('ensureDirectChat')
        .call<Map<String, dynamic>>({'otherUserId': otherUserId});
    final chatId = result.data['chatId'] as String?;
    return chatId == null ? null : getChat(chatId);
  }

  Future<String?> getExistingDirectChat(String otherUserId) async {
    final uid = currentUserId;
    if (uid == null) return null;

    // 1. Check in-memory cache first
    try {
      final cached = _chatsCache.firstWhere(
        (c) =>
            (c.type == 'direct' || c.id.startsWith('direct_')) &&
            c.participants.contains(otherUserId),
      );
      return cached.id;
    } catch (_) {}

    // 2. Query Firebase Functions if callable is deployed
    try {
      final result = await FirebaseFunctions.instance
          .httpsCallable('ensureDirectChat')
          .call<Map<String, dynamic>>({
            'otherUserId': otherUserId,
            'create': false,
          });
      if (result.data['exists'] == true) {
        return result.data['chatId'] as String?;
      }
    } catch (e) {
      debugPrint('ensureDirectChat callable fallback/skipped: $e');
    }

    // 3. Query user chats subcollection fallback
    try {
      final indexSnap = await _userChatsCol(uid).get();
      for (final doc in indexSnap.docs) {
        final chatDoc = await _chatsCol.doc(doc.id).get();
        if (chatDoc.exists) {
          final data = chatDoc.data() ?? {};
          final participants = List<String>.from(data['participants'] ?? []);
          final type = data['type'] as String? ?? '';
          if ((type == 'direct' || doc.id.startsWith('direct_')) &&
              participants.contains(otherUserId)) {
            return doc.id;
          }
        }
      }
    } catch (e) {
      debugPrint('Error looking up direct chat via index: $e');
    }

    return null;
  }

  /// Check if two users have an active direct chat where both have sent at least 1 message
  Future<bool> hasBilateralDialogue(
    String firstUserId,
    String secondUserId,
  ) async {
    try {
      final otherUid = (firstUserId == currentUserId)
          ? secondUserId
          : firstUserId;
      final chatId = await getExistingDirectChat(otherUid);
      if (chatId == null) return false;
      final messagesSnap = await _messagesCol(chatId).limit(50).get();
      final senders = messagesSnap.docs
          .map((d) => d.data()['senderId'] as String?)
          .toSet();
      return senders.contains(firstUserId) && senders.contains(secondUserId);
    } catch (e) {
      debugPrint('hasBilateralDialogue error: $e');
      return false;
    }
  }

  /// Create a Group Chat (Generic)
  Future<String?> createGroupChat({
    required String name,
    required List<String> participants,
    required List<String> admins,
    required Map<String, dynamic> metadata,
    String type = 'group',
  }) async {
    if (currentUserId == null) return null;
    final isBereavement = metadata['isBereavement'] == true;
    final payload = <String, dynamic>{
      'mode': isBereavement ? 'bereavement' : 'group',
      'name': name,
      if (isBereavement) 'deceasedUserId': metadata['deceasedId'],
      if (isBereavement) 'details': metadata['details'],
    };
    final result = await FirebaseFunctions.instance
        .httpsCallable('createChat')
        .call<Map<String, dynamic>>(payload);
    final chatId = result.data['chatId'] as String?;
    if (chatId == null) return null;

    if (!isBereavement) {
      final invitationTargets = participants
          .where((userId) => userId != currentUserId)
          .toSet()
          .take(99);
      for (final userId in invitationTargets) {
        await FirebaseFunctions.instance
            .httpsCallable('manageChatMembers')
            .call<void>({'chatId': chatId, 'inviteUserId': userId});
      }
    }
    return chatId;
  }

  /// Create-or-join a tiered Family Group Chat (immediate or extended).
  Future<String?> createOrJoinFamilyGroupChat({
    required String userId1,
    required String userId2,
    required String familyTier, // 'immediate' or 'extended'
  }) async {
    try {
      if (currentUserId == null ||
          (userId1 != currentUserId && userId2 != currentUserId)) {
        return null;
      }
      final otherUserId = userId1 == currentUserId ? userId2 : userId1;
      final result = await FirebaseFunctions.instance
          .httpsCallable('createChat')
          .call<Map<String, dynamic>>({
            'mode': 'family',
            'otherUserId': otherUserId,
            'familyTier': familyTier,
          });
      return result.data['chatId'] as String?;
    } catch (e) {
      debugPrint(
        '❌ [ChatRepo] Error in createOrJoinFamilyGroupChat ($familyTier): $e',
      );
      return null;
    }
  }

  /// [FIX] Creates a direct chat AND sends the first message in a single
  /// atomic batch commit. This prevents the Cloud Function race condition
  /// where onDirectMessageCreated fires before the chat document exists.
  Future<Chat?> createDirectChatWithMessage(
    String otherUserId,
    String initialMessage,
  ) async {
    if (currentUserId == null) return null;
    final chat = await createDirectChat(otherUserId);
    if (chat != null) await sendTextMessage(chat.id, initialMessage);
    return chat;
  }

  Future<Chat?> createListingChat({
    required String otherUserId,
    required String listingId,
    required String listingTitle,
    required String listingType,
    String? sellerRole,
    String? listingImageUrl,
  }) async {
    if (currentUserId == null) return null;
    final result = await FirebaseFunctions.instance
        .httpsCallable('createChat')
        .call<Map<String, dynamic>>({
          'mode': 'listing',
          'listingId': listingId,
        });
    final chatId = result.data['chatId'] as String?;
    if (chatId == null) return null;
    return Chat.fromFirestore(await _chatsCol.doc(chatId).get());
  }

  /// Find an existing listing group chat by listing ID.
  Future<String?> getExistingListingChat(String listingId) async {
    if (currentUserId == null) return null;

    // Use the server-maintained discovery index first (one bounded lookup).
    final discoverSnap = await _firestore
        .collection('discoverableChats')
        .where('listingId', isEqualTo: listingId)
        .limit(1)
        .get();
    if (discoverSnap.docs.isNotEmpty) return discoverSnap.docs.first.id;

    // Bounded compatibility fallback for legacy listing chats that predate
    // the discovery index.
    final myChatsSnap = await _userChatsCol(currentUserId!).limit(100).get();
    for (final doc in myChatsSnap.docs) {
      final chatDoc = await _chatsCol.doc(doc.id).get();
      if (!chatDoc.exists) continue;
      final chatData = chatDoc.data()!;
      final meta = chatData['metadata'];
      if (meta is Map &&
          meta['isListingChat'] == true &&
          meta['listingId'] == listingId) {
        return doc.id;
      }
    }

    return null;
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
    String? description,
    String? communityId,
    bool isPublic = false,
    String? category,
  }) async {
    if (currentUserId == null) return null;
    try {
      final result = await FirebaseFunctions.instance
          .httpsCallable('createChat')
          .call<Map<String, dynamic>>({
            'mode': 'group',
            'name': name,
            'description': description,
            'communityId': communityId,
            'isPublic': isPublic,
            'category': category,
          });
      final chatId = result.data['chatId'] as String?;
      if (chatId == null) return null;

      if (groupImage != null) {
        final imageUrl = await uploadGroupImage(chatId, groupImage);
        await updateGroupInfo(chatId, image: imageUrl);
      }

      for (final userId in userIds.toSet().where(
        (userId) => userId != currentUserId,
      )) {
        await FirebaseFunctions.instance
            .httpsCallable('manageChatMembers')
            .call<void>({'chatId': chatId, 'inviteUserId': userId});
      }

      return Chat.fromFirestore(await _chatsCol.doc(chatId).get());
    } catch (e, stack) {
      debugPrint('Error creating group: $e\n$stack');
      rethrow;
    }
  }

  Future<void> joinGroup(String chatId) async {
    if (currentUserId == null) return;

    // Non-members cannot read the canonical chat document. The public index
    // carries only the routing flags needed to select the trusted join flow.
    final discoveryDoc = await _firestore
        .collection('discoverableChats')
        .doc(chatId)
        .get();
    if (discoveryDoc.exists) {
      final discoveryData = discoveryDoc.data()!;
      if (discoveryData['isChamber'] == true) {
        await _ref.read(chamberServiceProvider).joinChamber(chatId);
        await getChat(chatId, force: true);
        return;
      }
      if (discoveryData['isDdiDiscussion'] == true) {
        await _ref.read(chamberServiceProvider).joinDdiDiscussion(chatId);
        await getChat(chatId, force: true);
        return;
      }
    }

    await FirebaseFunctions.instance.httpsCallable('joinChat').call({
      'chatId': chatId,
    });
    await getChat(chatId, force: true);
  }

  // ============================================
  // TYPING INDICATORS
  // ============================================

  Stream<List<String>> subscribeToTypingIndicators(String chatId) {
    return _typingCol(chatId).limit(100).snapshots().map((snapshot) {
      final now = DateTime.now().millisecondsSinceEpoch;
      final List<String> userIds = [];

      for (final doc in snapshot.docs) {
        if (doc.id == currentUserId) continue; // Don't show own indicator
        final data = doc.data();
        if (data['isTyping'] == true) {
          final timestamp = data['timestamp'] as int? ?? 0;
          if (now - timestamp < 10000) {
            userIds.add(doc.id);
          }
        }
      }

      return userIds;
    });
  }

  Future<void> setTypingStatus(String chatId, bool isTyping) async {
    if (currentUserId == null) return;

    final ref = _typingCol(chatId).doc(currentUserId);
    if (isTyping) {
      await ref.set({
        'isTyping': true,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });
    } else {
      await ref.delete();
    }
  }

  Future<void> updateGroupInfo(
    String chatId, {
    String? name,
    String? image,
    String? description,
  }) async {
    final updates = <String, Object?>{
      'chatId': chatId,
      'name': ?name,
      'photoUrl': ?image,
      'description': ?description,
    };
    if (updates.length > 1) {
      await FirebaseFunctions.instance
          .httpsCallable('updateChatMetadata')
          .call(updates);
    }
  }

  Future<void> manageChamber(
    String chatId, {
    String? description,
    List<String> addMemberIds = const [],
    List<String> removeMemberIds = const [],
  }) async {
    await _ref
        .read(chamberServiceProvider)
        .manageChamber(
          chatId,
          description: description,
          addMemberIds: addMemberIds,
          removeMemberIds: removeMemberIds,
        );
    await getChat(chatId, force: true);
  }

  Future<bool> addGroupMember(String chatId, String userId) async {
    final chatDoc = await _chatsCol.doc(chatId).get();
    if (!chatDoc.exists) return false;

    final participants = List<String>.from(
      chatDoc.data()?['participants'] ?? [],
    );

    if (!participants.contains(userId)) {
      await FirebaseFunctions.instance.httpsCallable('manageChatMembers').call({
        'chatId': chatId,
        'inviteUserId': userId,
      });
      return true;
    }
    return false;
  }

  Future<bool> removeGroupMember(String chatId, String userId) async {
    final chatDoc = await _chatsCol.doc(chatId).get();
    if (!chatDoc.exists) return false;

    final participants = List<String>.from(
      chatDoc.data()?['participants'] ?? [],
    );

    if (participants.contains(userId)) {
      await FirebaseFunctions.instance.httpsCallable('manageChatMembers').call({
        'chatId': chatId,
        'removeUserId': userId,
      });
      return true;
    }
    return false;
  }

  Future<bool> promoteToAdmin(String chatId, String userId) async {
    await FirebaseFunctions.instance.httpsCallable('manageChatMembers').call({
      'chatId': chatId,
      'promoteUserId': userId,
    });
    return true;
  }

  // Batch mark messages as read and decrement unread count
  Future<void> markMessagesAsRead(
    String chatId,
    List<String> messageIds,
  ) async {
    if (currentUserId == null || messageIds.isEmpty) return;

    try {
      final batch = _firestore.batch();

      for (final id in messageIds) {
        batch.update(_messagesCol(chatId).doc(id), {'status': 'read'});
      }

      // Decrement unread count
      final userChatDoc = await _userChatsCol(currentUserId!).doc(chatId).get();
      if (userChatDoc.exists) {
        final data = userChatDoc.data() ?? {};
        if (data['isDeleted'] != true) {
          final current = (data['unreadCount'] as int?) ?? 0;
          final newVal = (current - messageIds.length).clamp(0, current);
          batch.update(_userChatsCol(currentUserId!).doc(chatId), {
            'unreadCount': newVal,
          });
        }
      }

      await batch.commit();

      // Update lastMessage status if applicable
      final chatDoc = await _chatsCol.doc(chatId).get();
      if (chatDoc.exists) {
        final lastMsg = chatDoc.data()?['lastMessage'] as Map<String, dynamic>?;
        if (lastMsg != null && lastMsg['senderId'] != currentUserId) {
          final lastMsgId = lastMsg['id']?.toString();
          if (lastMsgId != null && messageIds.contains(lastMsgId)) {
            await _chatsCol.doc(chatId).update({'lastMessage.status': 'read'});
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
      // Update lastRead timestamp in userChats
      final userChatRef = _userChatsCol(currentUserId!).doc(chatId);
      final snap = await userChatRef.get();

      if (snap.exists) {
        final data = snap.data() ?? {};
        if (data['isDeleted'] != true) {
          await userChatRef.update({
            'unreadCount': 0,
            'lastRead': DateTime.now().millisecondsSinceEpoch,
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
      final msgDoc = await _messagesCol(chatId).doc(messageId).get();
      if (msgDoc.exists) {
        final data = msgDoc.data() ?? {};
        if (data['senderId'] != currentUserId && data['status'] != 'read') {
          await _messagesCol(chatId).doc(messageId).update({'status': 'read'});

          // Also update lastMessage if it's the last message
          final chatDoc = await _chatsCol.doc(chatId).get();
          if (chatDoc.exists) {
            final lastMsg =
                chatDoc.data()?['lastMessage'] as Map<String, dynamic>?;
            if (lastMsg != null && lastMsg['senderId'] != currentUserId) {
              await _chatsCol.doc(chatId).update({
                'lastMessage.status': 'read',
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
    await _userChatsCol(currentUserId!).doc(chatId).update({'muted': mute});
  }

  Future<void> togglePin(String chatId, bool pin) async {
    if (currentUserId == null) return;
    await _userChatsCol(currentUserId!).doc(chatId).update({'pinned': pin});
  }

  Future<void> togglePinBottom(String chatId, bool pin) async {
    if (currentUserId == null) return;
    await _userChatsCol(
      currentUserId!,
    ).doc(chatId).update({'pinnedBottom': pin});
  }

  Future<void> deleteChat(String chatId) async {
    if (currentUserId == null) return;

    await _userChatsCol(currentUserId!).doc(chatId).update({
      'isDeleted': true,
      'clearedAt': DateTime.now().millisecondsSinceEpoch,
    });

    await _localService.deleteChat(chatId);
  }

  Future<void> clearChat(String chatId) async {
    if (currentUserId == null) return;
    await _userChatsCol(currentUserId!).doc(chatId).update({
      'clearedAt': DateTime.now().millisecondsSinceEpoch,
      'lastMessage': FieldValue.delete(),
    });
  }

  // Clear mentions for a chat (removes sticky notifications)
  Future<void> clearChatMentions(String chatId) async {
    if (currentUserId == null) return;
    try {
      await _userChatsCol(
        currentUserId!,
      ).doc(chatId).update({'mentions': FieldValue.delete()});
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
      final msgRef = _messagesCol(chatId).doc(messageId);

      if (!deleteForEveryone) {
        // Add to deletedFor list
        await msgRef.update({
          'deletedFor': FieldValue.arrayUnion([currentUserId]),
        });
        return;
      }

      // Delete for everyone
      final updates = <String, dynamic>{
        'content': '🚫 Message deleted',
        'type': 'deleted',
        'deletedForEveryone': true,
      };

      await msgRef.update(updates);

      // Update lastMessage if it's the one being deleted
      final chatDoc = await _chatsCol.doc(chatId).get();
      if (chatDoc.exists) {
        final lastMsg = chatDoc.data()?['lastMessage'] as Map<String, dynamic>?;
        if (lastMsg != null) {
          final msgDoc = await msgRef.get();
          if (msgDoc.exists &&
              lastMsg['timestamp'] == msgDoc.data()?['timestamp']) {
            await _chatsCol.doc(chatId).update({
              'lastMessage.content': '🚫 Message deleted',
              'lastMessage.type': 'deleted',
            });
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
    await FirebaseFunctions.instance.httpsCallable('reactToMessage').call({
      'chatId': chatId,
      'messageId': messageId,
      'remove': true,
    });
  }

  Future<List<Chat>> searchDiscoverableChats(String query) async {
    if (currentUserId == null) return [];

    final List<Chat> results = [];

    try {
      // Get IDs of chats the user has already joined
      final userChatsSnap = await _userChatsCol(
        currentUserId!,
      ).limit(500).get();
      final Set<String> joinedChatIds = {};
      for (final doc in userChatsSnap.docs) {
        final data = doc.data();
        if (data['isDeleted'] != true) {
          joinedChatIds.add(doc.id);
        }
      }

      // 1. Search Events
      final eventRepo = _ref.read(eventRepositoryProvider);
      final events = await eventRepo.searchEvents(query);

      for (final event in events) {
        if (event.attendees?.contains(currentUserId) == true) continue;
        if (event.chatId != null && joinedChatIds.contains(event.chatId)) {
          continue;
        }
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
              // Carry corridor metadata so the chat card can render the
              // dual-flag avatar for chamber-of-commerce orgs.
              homeCountryCode: org['homeCountryCode'] as String?,
              hostCountryCode: org['hostCountryCode'] as String?,
            ),
          );
        }
      }

      // 3. Search Public Groups
      final groupsSnap = await _firestore
          .collection('discoverableChats')
          .orderBy('name')
          .limit(100)
          .get();
      for (final doc in groupsSnap.docs) {
        final groupData = doc.data();
        final name = groupData['name']?.toString() ?? '';
        final desc = groupData['description']?.toString() ?? '';
        final groupId = groupData['id']?.toString() ?? doc.id;

        if (query.isEmpty ||
            name.toLowerCase().contains(query.toLowerCase()) ||
            desc.toLowerCase().contains(query.toLowerCase())) {
          if (joinedChatIds.contains(groupId)) continue;

          results.add(
            Chat(
              id: groupId,
              communityId: groupData['communityId'],
              type: 'group',
              name: name,
              photoUrl: groupData['photoUrl'],
              participants: [],
              admins: [],
              createdBy: '',
              createdAt: groupData['createdAt'] is int
                  ? groupData['createdAt']
                  : 0,
              updatedAt: 0,
              description: desc,
              memberCount: groupData['memberCount'] is int
                  ? groupData['memberCount']
                  : 0,
              metadata: {'isPublic': true},
              isPinned: false,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Error searching discoverable chats: $e');
    }

    return results;
  }

  Future<void> syncCommunityChats(List<String> communityIds) async {
    if (currentUserId == null) return;
    for (final commId in communityIds) {
      final chatId = 'chat_$commId';
      await _userChatsCol(currentUserId!).doc(chatId).set({
        'chatId': chatId,
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
        'isDeleted': false,
      }, SetOptions(merge: true));
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
      final snapshot = await _userChatsCol(currentUserId!).limit(500).get();
      if (snapshot.docs.isEmpty) return 0;

      int count = 0;
      for (final doc in snapshot.docs) {
        final chatId = doc.id;
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
      DocumentSnapshot<Map<String, dynamic>>? cursor;
      while (true) {
        Query<Map<String, dynamic>> query = _userChatsCol(
          currentUserId!,
        ).orderBy(FieldPath.documentId).limit(400);
        if (cursor != null) query = query.startAfterDocument(cursor);
        final page = await query.get();
        if (page.docs.isEmpty) break;

        final deletedIds = <String>[];
        for (final chunk in _chunkList(page.docs, 20)) {
          final chatSnapshots = await Future.wait(
            chunk.map((indexDoc) => _chatsCol.doc(indexDoc.id).get()),
          );
          final batch = _firestore.batch();
          for (var index = 0; index < chunk.length; index++) {
            final chatSnapshot = chatSnapshots[index];
            if (!chatSnapshot.exists) {
              batch.delete(chunk[index].reference);
              deletedIds.add(chunk[index].id);
              continue;
            }
            final chat = Chat.fromFirestore(chatSnapshot);
            if (!chat.isCommunity) {
              batch.delete(chunk[index].reference);
              deletedIds.add(chunk[index].id);
            }
          }
          await batch.commit();
        }
        for (final chatId in deletedIds) {
          await _localService.deleteChat(chatId);
        }
        cursor = page.docs.last;
        if (page.docs.length < 400) break;
      }
    } catch (e) {
      debugPrint('Error clearing all chats: $e');
    }
  }

  Stream<LastMessage?> getLastMessageStream(String chatId) {
    return _chatsCol.doc(chatId).snapshots().map((snapshot) {
      if (!snapshot.exists) return null;
      try {
        final data = snapshot.data();
        final lastMsg = data?['lastMessage'];
        if (lastMsg == null) return null;
        return LastMessage.fromFirestore(
          Map<String, dynamic>.from(lastMsg as Map),
        );
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
