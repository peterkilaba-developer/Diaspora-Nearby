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
  final Map<String, Chat> _listingChatsCache = {};
  final Map<String, Future<Chat?>> _inFlightListingChats = {};
  final Map<String, List<Message>> _messagesCache = {};
  final Map<String, StreamController<List<Message>>> _messageStreamControllers =
      {};
  List<Chat>? _discoverableChatsCache;
  StreamSubscription? _chatsSubscription;
  StreamSubscription? _realtimeSubscription;
  String? _realtimeUid;

  /// [PERF] Synchronously access the sorted in-memory chat list
  List<Chat> get cachedChats => _sortedChatsList();

  /// [PERF] Synchronously access cached discoverable chats
  List<Chat>? get cachedDiscoverableChats => _discoverableChatsCache;

  /// [PERF] Filter cached discoverable chats synchronously in 0ms
  List<Chat>? filterDiscoverableChatsSync(String query) {
    final cached = _discoverableChatsCache;
    if (cached == null) return null;
    final trimmed = query.trim().toLowerCase();
    if (trimmed.isEmpty) return cached;
    return cached.where((chat) {
      final nameMatch = chat.name.toLowerCase().contains(trimmed);
      final descMatch =
          chat.description?.toLowerCase().contains(trimmed) ?? false;
      return nameMatch || descMatch;
    }).toList();
  }

  /// [PERF] Synchronously look up a chat in memory
  Chat? getCachedChat(String chatId) {
    try {
      final chat = _chatsCache.firstWhere((c) => c.id == chatId);
      if (chat.participants.isNotEmpty || !chat.isDirect) {
        return chat;
      }
    } catch (_) {}
    return null;
  }

  /// [PERF] Synchronously look up an existing direct chat with [otherUserId]
  Chat? getCachedDirectChatWith(String otherUserId) {
    try {
      return _chatsCache.firstWhere(
        (c) =>
            (c.type == 'direct' || c.id.startsWith('direct_')) &&
            c.participants.contains(otherUserId),
      );
    } catch (_) {
      return null;
    }
  }

  /// [PERF] Synchronously upsert a chat in memory cache and notify listeners
  void upsertChatInCache(Chat chat) {
    final idx = _chatsCache.indexWhere((c) => c.id == chat.id);
    if (idx >= 0) {
      _chatsCache[idx] = chat;
    } else {
      _chatsCache.add(chat);
    }
    if (!_chatsController.isClosed) {
      _chatsController.add(_sortedChatsList());
    }
  }

  /// [PERF] Synchronously look up a listing chat in memory by listingId
  Chat? getCachedListingChat(String listingId) {
    final uid = currentUserId;
    final directHit = _listingChatsCache[listingId];
    if (directHit != null &&
        (uid == null || directHit.participants.contains(uid))) {
      return directHit;
    }
    try {
      final chat = _chatsCache.firstWhere(
        (c) =>
            c.metadata?['isListingChat'] == true &&
            c.metadata?['listingId'] == listingId &&
            (uid == null || c.participants.contains(uid)),
      );
      _listingChatsCache[listingId] = chat;
      return chat;
    } catch (_) {}
    return null;
  }

  /// [PERF] Synchronously look up cached messages for a chat
  List<Message>? getCachedMessagesSync(String chatId) => _messagesCache[chatId];
  List<Message>? getCachedMessages(String chatId) => _messagesCache[chatId];

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
    _realtimeSubscription = null;
    _realtimeUid = null;
  }

  static int _effectiveSortTimestamp(Chat chat) {
    final lastMsgTs = chat.lastMessage?.timestamp ?? 0;
    if (lastMsgTs > 0) return lastMsgTs;
    if (chat.updatedAt > 0) return chat.updatedAt;
    return chat.createdAt;
  }

  static int compareChatsByLatest(Chat a, Chat b) {
    if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
    if (a.isPinnedBottom != b.isPinnedBottom) {
      return a.isPinnedBottom ? 1 : -1;
    }
    final aHasMsg = (a.lastMessage?.timestamp ?? 0) > 0;
    final bHasMsg = (b.lastMessage?.timestamp ?? 0) > 0;
    if (aHasMsg != bHasMsg) return aHasMsg ? -1 : 1;
    final cmp = _effectiveSortTimestamp(
      b,
    ).compareTo(_effectiveSortTimestamp(a));
    if (cmp != 0) return cmp;
    return b.updatedAt.compareTo(a.updatedAt);
  }

  List<Chat> _sortedChatsList() {
    final sorted = List<Chat>.from(_chatsCache);
    sorted.sort(compareChatsByLatest);
    return sorted;
  }

  // ============================================
  // FETCHING & STREAMS (Firestore Implementation)
  // ============================================

  /// Subscribe to user's chat list via Firestore real-time listeners.
  /// Emits `_chatsCache` synchronously on frame 0 via `Stream.multi` (`addSync`).
  Stream<List<Chat>> subscribeToUserChats({String? userId}) {
    final uid = userId ?? currentUserId;
    if (uid == null) return const Stream.empty();

    _startRealtimeSync(uid);

    return Stream<List<Chat>>.multi((controller) {
      if (_chatsCache.isNotEmpty) {
        controller.addSync(_sortedChatsList());
      }
      final sub = _chatsController.stream.listen(
        (chats) {
          if (!controller.isClosed) {
            controller.add(chats);
          }
        },
        onError: (Object e, StackTrace st) {
          if (!controller.isClosed) {
            controller.addError(e, st);
          }
        },
      );
      controller.onCancel = sub.cancel;
    }, isBroadcast: true);
  }

  /// Real-time Sync (Firestore → In-memory cache → StreamController)
  void _startRealtimeSync(String uid) {
    if (_realtimeSubscription != null && _realtimeUid == uid) {
      if (_chatsCache.isNotEmpty && !_chatsController.isClosed) {
        _chatsController.add(_sortedChatsList());
      }
      return;
    }

    _realtimeSubscription?.cancel();
    _realtimeSubscription = null;
    if (_realtimeUid != uid) {
      _chatsCache.clear();
    }
    _realtimeUid = uid;

    debugPrint('🔄 Starting Firestore real-time chat sync for $uid');

    _realtimeSubscription = _userChatsCol(uid)
        .limit(100)
        .snapshots()
        .listen(
          (snapshot) async {
            for (final change in snapshot.docChanges) {
              final chatId = change.doc.id;
              final data = change.doc.data() ?? {};

              if (change.type == DocumentChangeType.removed ||
                  data['isDeleted'] == true) {
                _chatsCache.removeWhere((c) => c.id == chatId);
                _localService.deleteChat(chatId);
              }
            }

            final toFetch = snapshot.docChanges.where((c) {
              if (c.type == DocumentChangeType.removed) return false;
              return (c.doc.data()?['isDeleted']) != true;
            }).toList();
            if (toFetch.isEmpty) {
              if (_chatsCache.isEmpty && snapshot.docs.isEmpty) {
                await _hydrateUserChatsFromServer(uid);
              }
              if (!_chatsController.isClosed) {
                _chatsController.add(_sortedChatsList());
              }
              return;
            }

            await _applyChatChanges(toFetch, uid, preferCache: true);
            if (!_chatsController.isClosed) {
              _chatsController.add(_sortedChatsList());
            }

            await _applyChatChanges(toFetch, uid, preferCache: false);
            if (!_chatsController.isClosed) {
              _chatsController.add(_sortedChatsList());
            }
          },
          onError: (Object error, StackTrace stackTrace) {
            debugPrint('Error listening to chats for $uid: $error');
            _realtimeSubscription?.cancel();
            _realtimeSubscription = null;
            if (!_chatsController.isClosed) {
              _chatsController.addError(error, stackTrace);
            }
          },
        );
  }

  Future<void> refreshChatsFromServer() async {
    final uid = currentUserId;
    if (uid == null) return;
    await _hydrateUserChatsFromServer(uid);
    if (!_chatsController.isClosed) {
      _chatsController.add(_sortedChatsList());
    }
  }

  Future<void> _hydrateUserChatsFromServer(String uid) async {
    try {
      var serverSnap = await _userChatsCol(
        uid,
      ).limit(100).get(const GetOptions(source: Source.server));

      if (serverSnap.docs.isEmpty) {
        final userDoc = await _firestore
            .collection('users')
            .doc(uid)
            .get(const GetOptions(source: Source.server));
        final memberships =
            (userDoc.data()?['communityMemberships'] as List<dynamic>?)
                ?.whereType<String>()
                .toList() ??
            const <String>[];
        if (memberships.isNotEmpty) {
          await syncCommunityChats(memberships);
          serverSnap = await _userChatsCol(
            uid,
          ).limit(100).get(const GetOptions(source: Source.server));
        }
      }

      final activeDocs = serverSnap.docs
          .where((doc) => doc.data()['isDeleted'] != true)
          .toList();
      await Future.wait(
        activeDocs.map((doc) async {
          final chatId = doc.id;
          final data = doc.data();
          try {
            final chat = await _fetchAndSaveChat(
              chatId,
              skipUserChatRead: true,
              preferCache: false,
            );
            if (chat != null) {
              final chatWithPrefs = chat.withUserPreferences(data);
              _handleDeliveryReceipt(chatWithPrefs, uid);
              final existingIdx = _chatsCache.indexWhere((c) => c.id == chatId);
              if (existingIdx >= 0) {
                _chatsCache[existingIdx] = chatWithPrefs;
              } else {
                _chatsCache.add(chatWithPrefs);
              }
            }
          } catch (e) {
            debugPrint('Error hydrating chat $chatId from server: $e');
          }
        }),
      );
    } catch (e) {
      debugPrint('Error hydrating userChats from server for $uid: $e');
    }
  }

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
            _localService.saveChat(chatWithPrefs);
          }
        } catch (e) {
          debugPrint('Error syncing chat $chatId: $e');
        }
      }),
    );
  }

  void _handleDeliveryReceipt(Chat chat, String uid) {
    try {
      final lastMsg = chat.lastMessage;
      if (lastMsg == null) return;
      if (lastMsg.senderId.isNotEmpty &&
          lastMsg.senderId != uid &&
          lastMsg.status == 'sent' &&
          lastMsg.id.isNotEmpty) {
        _messagesCol(
          chat.id,
        ).doc(lastMsg.id).set({'status': 'delivered'}, SetOptions(merge: true));
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

  void _emitMessagesUpdate(String chatId, List<Message> messages) {
    _messagesCache[chatId] = messages;
    final ctrl = _messageStreamControllers[chatId];
    if (ctrl != null && !ctrl.isClosed) {
      ctrl.add(List<Message>.unmodifiable(messages));
    }
  }

  Stream<List<Message>> subscribeToMessages(String chatId) {
    final uid = currentUserId;
    if (uid == null) return const Stream.empty();

    return Stream<List<Message>>.multi((multiController) {
      final initialCached = _messagesCache[chatId];
      if (initialCached != null) {
        multiController.addSync(initialCached);
      }

      final controller = StreamController<List<Message>>.broadcast();
      _messageStreamControllers[chatId] = controller;
      int clearedAt = 0;
      List<Message> lastMessages = _messagesCache[chatId] ?? [];
      StreamSubscription? userChatSub;
      StreamSubscription? subscription;

      final forwardSub = controller.stream.listen(
        (msgs) {
          if (!multiController.isClosed) {
            multiController.add(msgs);
          }
        },
        onError: (Object e, StackTrace st) {
          if (!multiController.isClosed) {
            multiController.addError(e, st);
          }
        },
      );

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

                lastMessages = messages;

                final filtered = clearedAt > 0
                    ? messages.where((m) => m.timestamp > clearedAt).toList()
                    : messages;
                _messagesCache[chatId] = filtered;

                if (!controller.isClosed) {
                  controller.add(filtered);
                  _cacheMessagesLocally(chatId, messages);
                }
              },
              onError: (Object error, StackTrace stackTrace) {
                debugPrint('Error listening to messages for $chatId: $error');
                if (!controller.isClosed) {
                  controller.add(const []);
                }
              },
            );
      }

      startMessagesListener();

      userChatSub = _userChatsCol(uid)
          .doc(chatId)
          .snapshots()
          .listen(
            (snapshot) {
              final data = snapshot.data();
              final newClearedAt = (data?['clearedAt'] as int?) ?? 0;
              if (newClearedAt != clearedAt) {
                clearedAt = newClearedAt;
                if (lastMessages.isNotEmpty && !controller.isClosed) {
                  final filtered = clearedAt > 0
                      ? lastMessages
                            .where((m) => m.timestamp > clearedAt)
                            .toList()
                      : lastMessages;
                  _messagesCache[chatId] = filtered;
                  controller.add(filtered);
                }
              }
            },
            onError: (Object error, StackTrace stackTrace) {
              debugPrint('Error listening to chat index for $chatId: $error');
            },
          );

      multiController.onCancel = () {
        forwardSub.cancel();
        userChatSub?.cancel();
        subscription?.cancel();
        if (_messageStreamControllers[chatId] == controller) {
          _messageStreamControllers.remove(chatId);
        }
        controller.close();
      };
    }, isBroadcast: true);
  }

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

    if (_chatsCache.isNotEmpty) {
      final chats = _sortedChatsList();
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

    final localChats = await _localService.getAllChats();

    if (localChats.isNotEmpty) {
      final chats = localChats;
      chats.sort(compareChatsByLatest);
      return chats;
    }

    final userChatsSnap = await _userChatsCol(currentUserId!).limit(100).get();
    if (userChatsSnap.docs.isEmpty) return [];

    final activeDocs = userChatsSnap.docs
        .where((doc) => doc.data()['isDeleted'] != true)
        .toList();
    final fetched = await Future.wait(activeDocs.map((doc) => getChat(doc.id)));
    final List<Chat> chats = fetched.whereType<Chat>().toList();

    chats.sort(compareChatsByLatest);

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
    final index = _chatsCache.indexWhere((c) => c.id == chat.id);
    if (index != -1) {
      _chatsCache[index] = chat;
    } else {
      _chatsCache.add(chat);
    }
    if (!_chatsController.isClosed) {
      _chatsController.add(_sortedChatsList());
    }

    await _localService.saveChat(chat);
  }

  Future<Chat?> getChat(String chatId, {bool force = false}) async {
    if (!force) {
      try {
        final mem = _chatsCache.firstWhere((c) => c.id == chatId);
        if (mem.participants.isNotEmpty || !mem.isDirect) {
          unawaited(_fetchAndSaveChat(chatId));
          return mem;
        }
        debugPrint(
          '⚠️ getChat: Memory cache has empty participants for $chatId, falling through to remote',
        );
      } catch (_) {}

      final localChat = await _localService.getChat(chatId);
      if (localChat != null) {
        if (localChat.participants.isNotEmpty || !localChat.isDirect) {
          unawaited(_fetchAndSaveChat(chatId));
          return localChat;
        }
        debugPrint(
          '⚠️ getChat: Local cache has empty participants for $chatId, falling through to remote',
        );
      }
    }

    return await _fetchAndSaveChat(chatId);
  }

  Future<Chat?> _fetchAndSaveChat(
    String chatId, {
    bool skipUserChatRead = false,
    bool preferCache = false,
  }) async {
    try {
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
            if (correctType == 'community' && data['communityId'] == null) {
              final communityId = chatId.startsWith('chat_')
                  ? chatId.substring(5)
                  : chatId;
              chat = chat.copyWith(type: correctType, communityId: communityId);
            } else {
              chat = chat.copyWith(type: correctType);
            }
          }
        }

        if (chat.participants.isEmpty && currentUserId != null) {
          final healedParticipants = <String>[currentUserId!];
          final data = chatDoc.data() ?? {};
          final createdBy = data['createdBy'] as String?;
          final adminId = data['adminId'] as String?;

          if (createdBy != null && !healedParticipants.contains(createdBy)) {
            healedParticipants.add(createdBy);
          }
          if (adminId != null && !healedParticipants.contains(adminId)) {
            healedParticipants.add(adminId);
          }

          if (healedParticipants.isNotEmpty) {
            chat = chat.copyWith(participants: healedParticipants);
          }
        }

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
    if (chatId.startsWith('direct_')) {
      List<String> blockedCheckParticipants = [];
      try {
        final cached = _chatsCache.firstWhere((c) => c.id == chatId);
        blockedCheckParticipants = cached.participants;
      } catch (_) {}

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
        )
        .then((msg) {
          if (msg != null) {
            _updateChatCacheWithMessage(chatId, msg);
          }
          return msg;
        });
  }

  void _updateChatCacheWithMessage(String chatId, Message msg) {
    final idx = _chatsCache.indexWhere((c) => c.id == chatId);
    if (idx >= 0) {
      final current = _chatsCache[idx];
      final lastMsg = LastMessage(
        id: msg.id,
        content: msg.content,
        timestamp: msg.timestamp,
        senderId: msg.senderId,
        senderName: msg.senderName,
        type: msg.type,
        status: msg.status ?? 'sent',
        mentions: msg.mentions,
        metadata: msg.metadata,
      );
      _chatsCache[idx] = current.copyWith(
        lastMessage: lastMsg,
        updatedAt: msg.timestamp,
        unreadCount: 0,
      );
      if (!_chatsController.isClosed) {
        _chatsController.add(_sortedChatsList());
      }
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
    final cached = getCachedDirectChatWith(otherUserId);
    if (cached != null) return cached;

    final result = await FirebaseFunctions.instance
        .httpsCallable('ensureDirectChat')
        .call<Map<String, dynamic>>({'otherUserId': otherUserId});
    final chatId = result.data['chatId'] as String?;
    return chatId == null ? null : getChat(chatId);
  }

  Future<String?> getExistingDirectChat(String otherUserId) async {
    final uid = currentUserId;
    if (uid == null) return null;

    // 1. Check in-memory cache first (0ms)
    final cached = getCachedDirectChatWith(otherUserId);
    if (cached != null) return cached.id;

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

    // 3. Query user chats subcollection fallback in parallel
    try {
      final indexSnap = await _userChatsCol(uid).limit(100).get();
      final chatDocs = await Future.wait(
        indexSnap.docs.map((doc) => _chatsCol.doc(doc.id).get()),
      );
      for (final chatDoc in chatDocs) {
        if (chatDoc.exists) {
          final data = chatDoc.data() ?? {};
          final participants = List<String>.from(data['participants'] ?? []);
          final type = data['type'] as String? ?? '';
          if ((type == 'direct' || chatDoc.id.startsWith('direct_')) &&
              participants.contains(otherUserId)) {
            return chatDoc.id;
          }
        }
      }
    } catch (e) {
      debugPrint('Error looking up direct chat via index: $e');
    }

    return null;
  }

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
      final results = await Future.wait([
        _messagesCol(
          chatId,
        ).where('senderId', isEqualTo: firstUserId).limit(20).get(),
        _messagesCol(
          chatId,
        ).where('senderId', isEqualTo: secondUserId).limit(20).get(),
      ]);
      bool hasActiveMsg(QuerySnapshot<Map<String, dynamic>> snap) {
        return snap.docs.any((doc) {
          final d = doc.data();
          return d['deletedForEveryone'] != true && d['isDeleted'] != true;
        });
      }

      return hasActiveMsg(results[0]) && hasActiveMsg(results[1]);
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
      unawaited(
        Future.wait(
          invitationTargets.map(
            (userId) => FirebaseFunctions.instance
                .httpsCallable('manageChatMembers')
                .call<void>({'chatId': chatId, 'inviteUserId': userId})
                .then<void>((_) {})
                .catchError((_) {}),
          ),
        ),
      );
    }
    return chatId;
  }

  Future<String?> createOrJoinFamilyGroupChat({
    required String userId1,
    required String userId2,
    required String familyTier,
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
    final uid = currentUserId;
    if (uid == null) return null;

    final cached = getCachedListingChat(listingId);
    if (cached != null) return cached;

    final existingFuture = _inFlightListingChats[listingId];
    if (existingFuture != null) return existingFuture;

    final future = _resolveOrCreateListingChat(
      uid: uid,
      listingId: listingId,
      sellerRole: sellerRole,
    );
    _inFlightListingChats[listingId] = future;
    try {
      return await future;
    } finally {
      _inFlightListingChats.remove(listingId);
    }
  }

  Future<Chat?> _resolveOrCreateListingChat({
    required String uid,
    required String listingId,
    String? sellerRole,
  }) async {
    try {
      final discoverSnap = await _firestore
          .collection('discoverableChats')
          .where('listingId', isEqualTo: listingId)
          .limit(1)
          .get();
      if (discoverSnap.docs.isNotEmpty) {
        final existingChatId = discoverSnap.docs.first.id;
        final existingDoc = await _chatsCol.doc(existingChatId).get();
        if (existingDoc.exists) {
          final existingChat = Chat.fromFirestore(existingDoc);
          if (existingChat.participants.contains(uid)) {
            _listingChatsCache[listingId] = existingChat;
            await updateChatLocally(existingChat);
            return existingChat;
          }
        }
      }
    } catch (_) {}

    final result = await FirebaseFunctions.instance
        .httpsCallable('createChat')
        .call<Map<String, dynamic>>({
          'mode': 'listing',
          'listingId': listingId,
          'sellerRole': ?sellerRole,
        });
    final chatId = result.data['chatId'] as String?;
    if (chatId == null) return null;
    final chatDoc = await _chatsCol.doc(chatId).get();
    if (!chatDoc.exists) return null;
    final chat = Chat.fromFirestore(chatDoc);
    _listingChatsCache[listingId] = chat;
    await updateChatLocally(chat);
    return chat;
  }

  Future<String?> getExistingListingChat(String listingId) async {
    if (currentUserId == null) return null;
    final cached = getCachedListingChat(listingId);
    if (cached != null) return cached.id;

    final discoverSnap = await _firestore
        .collection('discoverableChats')
        .where('listingId', isEqualTo: listingId)
        .limit(1)
        .get();
    if (discoverSnap.docs.isNotEmpty) return discoverSnap.docs.first.id;

    final myChatsSnap = await _userChatsCol(currentUserId!).limit(100).get();
    final chatDocs = await Future.wait(
      myChatsSnap.docs.map((doc) => _chatsCol.doc(doc.id).get()),
    );
    for (final chatDoc in chatDocs) {
      if (!chatDoc.exists) continue;
      final chatData = chatDoc.data()!;
      final meta = chatData['metadata'];
      if (meta is Map &&
          meta['isListingChat'] == true &&
          meta['listingId'] == listingId) {
        return chatDoc.id;
      }
    }

    return null;
  }

  Future<List<ProfileData>> getDirectChatFriends() async {
    return getChatContacts();
  }

  Future<List<ProfileData>> getContactsWithDMs() async {
    if (currentUserId == null) return [];
    try {
      final chats = await getUserChats();

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

      final profileRepo = _ref.read(profileRepositoryProvider);
      final List<ProfileData> profiles = [];
      final List<String> missingIds = [];

      for (final uid in contactIds) {
        final cached = profileRepo.getCachedProfile(uid);
        if (cached != null) {
          profiles.add(cached);
        } else {
          missingIds.add(uid);
        }
      }

      if (missingIds.isNotEmpty) {
        final chunks = _chunkList(missingIds, 10);
        final snapshots = await Future.wait(
          chunks.map(
            (chunk) => _firestore
                .collection('users')
                .where(FieldPath.documentId, whereIn: chunk)
                .get(),
          ),
        );
        for (final snapshot in snapshots) {
          for (final d in snapshot.docs) {
            final p = ProfileData.fromJson(d.data());
            p.uid = d.id;
            profileRepo.cacheProfile(d.id, p);
            profiles.add(p);
          }
        }
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

  Future<List<ProfileData>> getChatContacts() async {
    return getContactsWithDMs();
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

      final now = DateTime.now().millisecondsSinceEpoch;
      final optimisticChat = Chat(
        id: chatId,
        type: 'group',
        name: name,
        description: description,
        communityId: communityId ?? '',
        photoUrl: groupImage?.path,
        participants: [currentUserId!],
        admins: [currentUserId!],
        createdBy: currentUserId!,
        createdAt: now,
        updatedAt: now,
        memberCount: 1,
        metadata: {'isPublic': isPublic, 'category': ?category},
      );
      upsertChatInCache(optimisticChat);

      // Upload image and invite members in parallel in the background
      final inviteTargets = userIds
          .toSet()
          .where((userId) => userId != currentUserId)
          .toList();

      unawaited(() async {
        try {
          await Future.wait([
            if (groupImage != null)
              () async {
                final imageUrl = await uploadGroupImage(chatId, groupImage);
                await updateGroupInfo(chatId, image: imageUrl);
              }(),
            ...inviteTargets.map(
              (userId) => FirebaseFunctions.instance
                  .httpsCallable('manageChatMembers')
                  .call<void>({'chatId': chatId, 'inviteUserId': userId})
                  .then<void>((_) {})
                  .catchError((_) {}),
            ),
          ]);
          final freshDoc = await _chatsCol.doc(chatId).get();
          if (freshDoc.exists) {
            upsertChatInCache(Chat.fromFirestore(freshDoc));
          }
        } catch (e) {
          debugPrint('Background group setup warning: $e');
        }
      }());

      return optimisticChat;
    } catch (e, stack) {
      debugPrint('Error creating group: $e\n$stack');
      rethrow;
    }
  }

  Future<void> joinGroup(String chatId) async {
    final uid = currentUserId;
    if (uid == null) return;

    // Optimistically update in-memory cache so UI unlocks in 0ms
    final idx = _chatsCache.indexWhere((c) => c.id == chatId);
    if (idx >= 0) {
      final current = _chatsCache[idx];
      if (!current.participants.contains(uid)) {
        _chatsCache[idx] = current.copyWith(
          participants: [...current.participants, uid],
          memberCount: (current.memberCount ?? current.participants.length) + 1,
        );
        if (!_chatsController.isClosed) {
          _chatsController.add(_sortedChatsList());
        }
      }
    }

    final discoveryDoc = await _firestore
        .collection('discoverableChats')
        .doc(chatId)
        .get();
    if (discoveryDoc.exists) {
      final discoveryData = discoveryDoc.data()!;
      if (discoveryData['isChamber'] == true) {
        await _ref.read(chamberServiceProvider).joinChamber(chatId);
        unawaited(getChat(chatId, force: true));
        return;
      }
      if (discoveryData['isDdiDiscussion'] == true) {
        await _ref.read(chamberServiceProvider).joinDdiDiscussion(chatId);
        unawaited(getChat(chatId, force: true));
        return;
      }
    }

    await FirebaseFunctions.instance.httpsCallable('joinChat').call({
      'chatId': chatId,
    });
    unawaited(getChat(chatId, force: true));
  }

  // ============================================
  // TYPING INDICATORS
  // ============================================

  Stream<List<String>> subscribeToTypingIndicators(String chatId) {
    return _typingCol(chatId).limit(100).snapshots().map((snapshot) {
      final now = DateTime.now().millisecondsSinceEpoch;
      final List<String> userIds = [];

      for (final doc in snapshot.docs) {
        if (doc.id == currentUserId) continue;
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
    final idx = _chatsCache.indexWhere((c) => c.id == chatId);
    if (idx >= 0) {
      final current = _chatsCache[idx];
      _chatsCache[idx] = current.copyWith(
        name: name ?? current.name,
        photoUrl: image ?? current.photoUrl,
        description: description ?? current.description,
      );
      if (!_chatsController.isClosed) {
        _chatsController.add(_sortedChatsList());
      }
    }

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
    unawaited(getChat(chatId, force: true));
  }

  Future<bool> addGroupMember(String chatId, String userId) async {
    final cached = getCachedChat(chatId);
    List<String> participants;
    if (cached != null) {
      participants = cached.participants;
    } else {
      final chatDoc = await _chatsCol.doc(chatId).get();
      if (!chatDoc.exists) return false;
      participants = List<String>.from(chatDoc.data()?['participants'] ?? []);
    }

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
    final cached = getCachedChat(chatId);
    List<String> participants;
    if (cached != null) {
      participants = cached.participants;
    } else {
      final chatDoc = await _chatsCol.doc(chatId).get();
      if (!chatDoc.exists) return false;
      participants = List<String>.from(chatDoc.data()?['participants'] ?? []);
    }

    if (participants.contains(userId)) {
      if (cached != null) {
        upsertChatInCache(
          cached.copyWith(
            participants: cached.participants
                .where((id) => id != userId)
                .toList(),
          ),
        );
      }
      await FirebaseFunctions.instance.httpsCallable('manageChatMembers').call({
        'chatId': chatId,
        'removeUserId': userId,
      });
      return true;
    }
    return false;
  }

  Future<bool> promoteToAdmin(String chatId, String userId) async {
    final cached = getCachedChat(chatId);
    if (cached != null && !(cached.admins?.contains(userId) ?? false)) {
      upsertChatInCache(cached.copyWith(admins: [...?cached.admins, userId]));
    }
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

    final idx = _chatsCache.indexWhere((c) => c.id == chatId);
    if (idx >= 0 && _chatsCache[idx].unreadCount > 0) {
      final cur = _chatsCache[idx].unreadCount;
      final next = (cur - messageIds.length).clamp(0, cur);
      _chatsCache[idx] = _chatsCache[idx].copyWith(unreadCount: next);
      if (!_chatsController.isClosed) {
        _chatsController.add(_sortedChatsList());
      }
    }

    try {
      final docs = await Future.wait([
        _userChatsCol(currentUserId!).doc(chatId).get(),
        _chatsCol.doc(chatId).get(),
      ]);
      final userChatDoc = docs[0];
      final chatDoc = docs[1];

      final batch = _firestore.batch();

      for (final id in messageIds) {
        batch.update(_messagesCol(chatId).doc(id), {'status': 'read'});
      }

      if (userChatDoc.exists) {
        final data = userChatDoc.data() ?? {};
        if (data['isDeleted'] != true) {
          final current = (data['unreadCount'] as int?) ?? 0;
          final newVal = (current - messageIds.length).clamp(0, current);
          batch.update(_userChatsCol(currentUserId!).doc(chatId), {
            'unreadCount': newVal,
            if (newVal == 0) 'unreadNotificationLines': <String>[],
          });
        }
      }

      if (chatDoc.exists) {
        final lastMsg = chatDoc.data()?['lastMessage'] as Map<String, dynamic>?;
        if (lastMsg != null && lastMsg['senderId'] != currentUserId) {
          final lastMsgId = lastMsg['id']?.toString();
          if (lastMsgId != null && messageIds.contains(lastMsgId)) {
            batch.update(_chatsCol.doc(chatId), {'lastMessage.status': 'read'});
          }
        }
      }

      await batch.commit();
    } catch (e) {
      debugPrint('Error batch marking read: $e');
    }
  }

  Future<void> markChatAsRead(String chatId) async {
    if (currentUserId == null) return;
    final idx = _chatsCache.indexWhere((c) => c.id == chatId);
    if (idx >= 0 && _chatsCache[idx].unreadCount > 0) {
      _chatsCache[idx] = _chatsCache[idx].copyWith(unreadCount: 0);
      if (!_chatsController.isClosed) {
        _chatsController.add(_sortedChatsList());
      }
    }
    try {
      final userChatRef = _userChatsCol(currentUserId!).doc(chatId);
      final snap = await userChatRef.get();

      if (snap.exists) {
        final data = snap.data() ?? {};
        if (data['isDeleted'] != true) {
          await userChatRef.update({
            'unreadCount': 0,
            'unreadNotificationLines': <String>[],
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

  Future<int> getUnreadCount(String chatId) async => 0;

  Future<void> toggleMute(String chatId, bool mute) async {
    if (currentUserId == null) return;
    final idx = _chatsCache.indexWhere((c) => c.id == chatId);
    if (idx >= 0) {
      _chatsCache[idx] = _chatsCache[idx].copyWith(isMuted: mute);
      if (!_chatsController.isClosed) {
        _chatsController.add(_sortedChatsList());
      }
    }
    await _userChatsCol(currentUserId!).doc(chatId).update({'muted': mute});
  }

  Future<void> togglePin(String chatId, bool pin) async {
    if (currentUserId == null) return;
    final idx = _chatsCache.indexWhere((c) => c.id == chatId);
    if (idx >= 0) {
      _chatsCache[idx] = _chatsCache[idx].copyWith(
        isPinned: pin,
        isPinnedBottom: pin ? false : _chatsCache[idx].isPinnedBottom,
      );
      if (!_chatsController.isClosed) {
        _chatsController.add(_sortedChatsList());
      }
    }
    await _userChatsCol(
      currentUserId!,
    ).doc(chatId).update({'pinned': pin, if (pin) 'pinnedBottom': false});
  }

  Future<void> togglePinBottom(String chatId, bool pin) async {
    if (currentUserId == null) return;
    final idx = _chatsCache.indexWhere((c) => c.id == chatId);
    if (idx >= 0) {
      _chatsCache[idx] = _chatsCache[idx].copyWith(
        isPinnedBottom: pin,
        isPinned: pin ? false : _chatsCache[idx].isPinned,
      );
      if (!_chatsController.isClosed) {
        _chatsController.add(_sortedChatsList());
      }
    }
    await _userChatsCol(
      currentUserId!,
    ).doc(chatId).update({'pinnedBottom': pin, if (pin) 'pinned': false});
  }

  Future<void> deleteChat(String chatId) async {
    if (currentUserId == null) return;
    _chatsCache.removeWhere((c) => c.id == chatId);
    _messagesCache.remove(chatId);
    if (!_chatsController.isClosed) {
      _chatsController.add(_sortedChatsList());
    }

    await _userChatsCol(currentUserId!).doc(chatId).update({
      'isDeleted': true,
      'clearedAt': DateTime.now().millisecondsSinceEpoch,
    });

    await _localService.deleteChat(chatId);
  }

  Future<void> clearChat(String chatId) async {
    if (currentUserId == null) return;
    _emitMessagesUpdate(chatId, const []);
    await _userChatsCol(currentUserId!).doc(chatId).update({
      'clearedAt': DateTime.now().millisecondsSinceEpoch,
      'lastMessage': FieldValue.delete(),
    });
  }

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
    final cachedMsgs = _messagesCache[chatId];
    Message? targetMsg;
    if (cachedMsgs != null) {
      for (final m in cachedMsgs) {
        if (m.id == messageId) {
          targetMsg = m;
          break;
        }
      }
      final updated = cachedMsgs.map((m) {
        if (m.id != messageId) return m;
        if (!deleteForEveryone) {
          final nextDeletedFor = <String>{
            ...?m.deletedFor,
            currentUserId!,
          }.toList();
          return m.copyWith(deletedFor: nextDeletedFor);
        }
        return m.copyWith(
          content: '🚫 Message deleted',
          type: 'deleted',
          deletedForEveryone: true,
        );
      }).toList();
      _emitMessagesUpdate(chatId, updated);
    }
    try {
      final msgRef = _messagesCol(chatId).doc(messageId);

      if (!deleteForEveryone) {
        await msgRef.update({
          'deletedFor': FieldValue.arrayUnion([currentUserId]),
        });
        return;
      }

      final updates = <String, dynamic>{
        'content': '🚫 Message deleted',
        'type': 'deleted',
        'deletedForEveryone': true,
      };

      await msgRef.update(updates);

      final cachedChat = getCachedChat(chatId);
      if (cachedChat?.lastMessage?.id == messageId ||
          (targetMsg != null &&
              cachedChat?.lastMessage?.timestamp == targetMsg.timestamp)) {
        await _chatsCol.doc(chatId).update({
          'lastMessage.content': '🚫 Message deleted',
          'lastMessage.type': 'deleted',
        });
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
    final service = _ref.read(chatMessagingServiceProvider);
    await Future.wait(
      targetChatIds.map((chatId) async {
        final cachedChat = getCachedChat(chatId);
        final msg = await service.forwardMessage(
          chatId,
          message,
          senderIdOverride: senderIdOverride,
          senderNameOverride: senderNameOverride,
          senderImageOverride: senderImageOverride,
          participants: cachedChat?.participants,
        );
        if (msg != null) {
          _updateChatCacheWithMessage(chatId, msg);
        }
      }),
    );
  }

  void _optimisticReactionUpdate(
    String chatId,
    String messageId,
    String emoji, {
    required bool remove,
  }) {
    final uid = currentUserId;
    if (uid == null) return;
    final cachedMsgs = _messagesCache[chatId];
    if (cachedMsgs == null) return;

    final updated = cachedMsgs.map((m) {
      if (m.id != messageId) return m;
      final existing = List<MessageReaction>.from(m.reactions ?? const []);
      final cleaned = <MessageReaction>[];
      for (final r in existing) {
        final nextUsers = r.userIds.where((id) => id != uid).toList();
        if (nextUsers.isNotEmpty) {
          cleaned.add(MessageReaction(emoji: r.emoji, userIds: nextUsers));
        }
      }
      if (!remove) {
        final idx = cleaned.indexWhere((r) => r.emoji == emoji);
        if (idx >= 0) {
          cleaned[idx] = MessageReaction(
            emoji: emoji,
            userIds: [...cleaned[idx].userIds, uid],
          );
        } else {
          cleaned.add(MessageReaction(emoji: emoji, userIds: [uid]));
        }
      }
      return m.copyWith(reactions: cleaned);
    }).toList();

    _emitMessagesUpdate(chatId, updated);
  }

  Future<void> addReaction(
    String chatId,
    String messageId,
    String emoji,
    String messageSenderId,
  ) async {
    _optimisticReactionUpdate(chatId, messageId, emoji, remove: false);
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
    _optimisticReactionUpdate(chatId, messageId, emoji, remove: true);
    await FirebaseFunctions.instance.httpsCallable('reactToMessage').call({
      'chatId': chatId,
      'messageId': messageId,
      'remove': true,
    });
  }

  Future<List<Chat>> searchDiscoverableChats(String query) async {
    if (currentUserId == null) return [];

    // If we already cached the full discoverable list, filter in-memory immediately
    // and refresh in background if query is empty.
    if (_discoverableChatsCache != null && _discoverableChatsCache!.isNotEmpty) {
      unawaited(_refreshDiscoverableChatsCache(query));
      return filterDiscoverableChatsSync(query) ?? const [];
    }

    return _refreshDiscoverableChatsCache(query);
  }

  Future<List<Chat>> _refreshDiscoverableChatsCache(String query) async {
    if (currentUserId == null) return [];
    final List<Chat> allDiscoverable = [];

    try {
      final eventRepo = _ref.read(eventRepositoryProvider);
      final orgRepo = _ref.read(organizationRepositoryProvider);

      // Run all 4 queries in parallel via Future.wait
      final parallelResults = await Future.wait([
        _userChatsCol(currentUserId!).limit(500).get(),
        eventRepo.searchEvents(''),
        orgRepo.searchOrganizations(''),
        _firestore
            .collection('discoverableChats')
            .orderBy('name')
            .limit(100)
            .get(),
      ]);

      final userChatsSnap =
          parallelResults[0] as QuerySnapshot<Map<String, dynamic>>;
      final events = parallelResults[1] as List<dynamic>;
      final orgs = parallelResults[2] as List<Map<String, dynamic>>;
      final groupsSnap =
          parallelResults[3] as QuerySnapshot<Map<String, dynamic>>;

      final Set<String> joinedChatIds = {
        ..._chatsCache.map((c) => c.id),
      };
      for (final doc in userChatsSnap.docs) {
        final data = doc.data();
        if (data['isDeleted'] != true) {
          joinedChatIds.add(doc.id);
        }
      }

      // 1. Events
      for (final event in events) {
        if (event.attendees?.contains(currentUserId) == true) continue;
        if (event.chatId != null && joinedChatIds.contains(event.chatId)) {
          continue;
        }
        if (event.chatId == null) continue;

        allDiscoverable.add(
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

      // 2. Organizations
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
          allDiscoverable.add(
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
              homeCountryCode: org['homeCountryCode'] as String?,
              hostCountryCode: org['hostCountryCode'] as String?,
            ),
          );
        }
      }

      // 3. Public Groups
      for (final doc in groupsSnap.docs) {
        final groupData = doc.data();
        final name = groupData['name']?.toString() ?? '';
        final desc = groupData['description']?.toString() ?? '';
        final groupId = groupData['id']?.toString() ?? doc.id;

        if (joinedChatIds.contains(groupId)) continue;

        final resolvedType = groupId.startsWith('event_')
            ? 'event'
            : groupId.startsWith('org_')
            ? 'organization'
            : (groupData['type']?.toString() ?? 'group');

        allDiscoverable.add(
          Chat(
            id: groupId,
            communityId: groupData['communityId'],
            type: resolvedType,
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

      _discoverableChatsCache = allDiscoverable;
    } catch (e) {
      debugPrint('Error searching discoverable chats: $e');
    }

    return filterDiscoverableChatsSync(query) ?? allDiscoverable;
  }

  Future<void> syncCommunityChats(List<String> communityIds) async {
    if (currentUserId == null || communityIds.isEmpty) return;
    final batch = _firestore.batch();
    for (final commId in communityIds) {
      final chatId = 'chat_$commId';
      batch.set(_userChatsCol(currentUserId!).doc(chatId), {
        'chatId': chatId,
        'isDeleted': false,
      }, SetOptions(merge: true));
    }
    await batch.commit();
  }

  Future<String> getDisplayNameForChat(Chat chat) async {
    if (currentUserId == null) return chat.name;
    if (chat.isDirect) {
      final otherId = chat.getOtherParticipantId(currentUserId!);
      if (otherId == null || otherId.isEmpty) return chat.name;
      try {
        final profileRepo = _ref.read(profileRepositoryProvider);
        final cached = profileRepo.getCachedProfile(otherId);
        if (cached != null) {
          final name = '${cached.firstName} ${cached.lastName}'.trim();
          if (name.isNotEmpty) return name;
        }
        final profile = await profileRepo.getUserProfile(otherId);
        if (profile != null) {
          final name = '${profile.firstName} ${profile.lastName}'.trim();
          if (name.isNotEmpty) return name;
        }
      } catch (e) {
        /* ignore */
      }
    }
    return chat.name;
  }

  Future<int> getDeletableChatsCount() async {
    if (currentUserId == null) return 0;
    if (_chatsCache.isNotEmpty) {
      return _chatsCache
          .where((c) => !c.isCommunity && !c.id.startsWith('community_'))
          .length;
    }
    try {
      final snapshot = await _userChatsCol(currentUserId!).limit(500).get();
      if (snapshot.docs.isEmpty) return 0;

      final candidateDocs = snapshot.docs
          .where((doc) => !doc.id.startsWith('community_'))
          .toList();
      final chats = await Future.wait(
        candidateDocs.map((doc) => getChat(doc.id)),
      );
      return chats.whereType<Chat>().where((c) => !c.isCommunity).length;
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
        final parsed = LastMessage.fromFirestore(
          Map<String, dynamic>.from(lastMsg as Map),
        );
        final idx = _chatsCache.indexWhere((c) => c.id == chatId);
        if (idx >= 0) {
          final current = _chatsCache[idx];
          final currentTs = current.lastMessage?.timestamp ?? 0;
          if (parsed.timestamp > currentTs ||
              (parsed.timestamp == currentTs &&
                  parsed.content != current.lastMessage?.content)) {
            final newUpdatedAt = parsed.timestamp > current.updatedAt
                ? parsed.timestamp
                : current.updatedAt;
            _chatsCache[idx] = current.copyWith(
              lastMessage: parsed,
              updatedAt: newUpdatedAt,
            );
            if (!_chatsController.isClosed) {
              _chatsController.add(_sortedChatsList());
            }
          }
        }
        return parsed;
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
