import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:isar/isar.dart';
import 'package:diaspora_nearby/core/services/database_service.dart';
import 'package:diaspora_nearby/features/chat/models/chat.dart';
import 'package:diaspora_nearby/features/chat/models/message.dart';
import 'package:diaspora_nearby/features/shared/data/local/entities/chat_entity.dart';

class ChatLocalService {
  final Isar? _isar;

  ChatLocalService() : _isar = DatabaseService().isar;

  Stream<List<Chat>> watchUserChats() {
    if (_isar == null) return const Stream.empty();
    return _isar!.chatEntitys
        .where()
        .watch(fireImmediately: true)
        .map((entities) {
          final chats = entities.map(_mapEntityToModel).toList();
          // Sort locally by Pinned Top -> Normal -> Pinned Bottom
          chats.sort((a, b) {
            if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
            if (a.isPinnedBottom != b.isPinnedBottom) return a.isPinnedBottom ? 1 : -1;
            return b.updatedAt.compareTo(a.updatedAt);
          });
          return chats;
        });
  }

  Future<void> saveChat(Chat chat) async {
    if (_isar == null) return;
    
    // Preserve existing cached messages
    String? existingCache;
    final existing = await _isar!.chatEntitys
      .filter()
      .firestoreIdEqualTo(chat.id)
      .findFirst();
      
    if (existing != null) {
      existingCache = existing.cachedMessagesJson;
    }
    
    final entity = _mapModelToEntity(chat);
    entity.cachedMessagesJson = existingCache;
    if (existing != null) {
      entity.id = existing.id; // Preserve Local ID
    }
    
    await _isar!.writeTxn(() async {
      await _isar!.chatEntitys.put(entity);
    });
  }

  Future<void> deleteChat(String chatId) async {
    if (_isar == null) return;
    await _isar!.writeTxn(() async {
      await _isar!.chatEntitys
          .filter()
          .firestoreIdEqualTo(chatId)
          .deleteAll();
    });
  }

  Future<void> clearAllChats() async {
    if (_isar == null) return;
    await _isar!.writeTxn(() async {
      await _isar!.chatEntitys.clear();
    });
    debugPrint('🧹 Local Chat cache cleared');
  }

  Future<void> saveMessages(String chatId, List<Message> messages) async {
    if (_isar == null) return;
    try {
      // Limit to last 100 messages
      final msgsToCache = messages.length > 100
          ? messages.sublist(messages.length - 100)
          : messages;

      final jsonStr = jsonEncode(msgsToCache.map((m) => m.toJson()).toList());

      await _isar!.writeTxn(() async {
        final chat = await _isar!.chatEntitys
            .filter()
            .firestoreIdEqualTo(chatId)
            .findFirst();
        if (chat != null) {
          chat.cachedMessagesJson = jsonStr;
          await _isar!.chatEntitys.put(chat);
        }
      });
    } catch (e) {
      debugPrint('Error saving messages locally: $e');
    }
  }

  Future<List<Message>> getCachedMessages(String chatId) async {
    if (_isar == null) return [];
    final chatEnt = await _isar!.chatEntitys
        .filter()
        .firestoreIdEqualTo(chatId)
        .findFirst();

    if (chatEnt?.cachedMessagesJson != null) {
      try {
        final List<dynamic> list = jsonDecode(chatEnt!.cachedMessagesJson!);
        final messages = list.map((e) => Message.fromJson(e)).toList();
        messages.sort((a, b) => b.timestamp.compareTo(a.timestamp));
        return messages;
      } catch (e) {
        debugPrint('Error reading Isar cached messages: $e');
      }
    }
    return [];
  }

  Future<List<Chat>> getAllChats() async {
    if (_isar == null) return [];
    final localChats = await _isar!.chatEntitys
        .where()
        .findAll();

    if (localChats.isNotEmpty) {
      final chats = localChats.map(_mapEntityToModel).toList();
      chats.sort((a, b) {
        if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
        if (a.isPinnedBottom != b.isPinnedBottom) return a.isPinnedBottom ? 1 : -1;
        return b.updatedAt.compareTo(a.updatedAt);
      });
      return chats;
    }
    return [];
  }

  Future<Chat?> getChat(String chatId) async {
    if (_isar == null) return null;
    final local = await _isar!.chatEntitys
        .filter()
        .firestoreIdEqualTo(chatId)
        .findFirst();

    if (local != null) {
      return _mapEntityToModel(local);
    }
    return null;
  }

  // Mappers
  Chat _mapEntityToModel(ChatEntity entity) {
    return Chat(
      id: entity.firestoreId,
      communityId: entity.communityId,
      name: entity.name,
      type: entity.type,
      photoUrl: entity.photoUrl,
      participants: entity.participants?.toList() ?? [],
      lastMessage: entity.lastMessage != null
          ? LastMessage(
              id: entity.lastMessage!.id ?? '',
              content: entity.lastMessage!.content ?? '',
              senderId: entity.lastMessage!.senderId ?? '',
              senderName: entity.lastMessage!.senderName ?? '',
              timestamp: entity.lastMessage!.timestamp ?? 0,
              type: entity.lastMessage!.type ?? 'text',
              status: entity.lastMessage!.status ?? 'sent',
            )
          : null,
      unreadCount: entity.unreadCount,
      updatedAt: entity.updatedAt,
      createdAt: entity.createdAt,
      isPinned: entity.isPinned,
      isPinnedBottom: entity.isPinnedBottom,
      isMuted: entity.isMuted,
      admins: entity.admins?.toList() ?? [],
      createdBy: entity.createdBy,
      description: entity.description,
      eventId: entity.eventId,
    );
  }

  ChatEntity _mapModelToEntity(Chat chat) {
    final entity = ChatEntity()
      ..firestoreId = chat.id
      ..communityId = chat.communityId
      ..name = chat.name
      ..type = chat.type
      ..photoUrl = chat.photoUrl
      ..participants = chat.participants
      ..unreadCount = chat.unreadCount
      ..updatedAt = chat.updatedAt
      ..createdAt = chat.createdAt
      ..isPinned = chat.isPinned
      ..isPinnedBottom = chat.isPinnedBottom
      ..isMuted = chat.isMuted
      ..admins = chat.admins
      ..createdBy = chat.createdBy
      ..description = chat.description
      ..eventId = chat.eventId;

    if (chat.lastMessage != null) {
      entity.lastMessage = LastMessageEntity()
        ..id = chat.lastMessage!.id
        ..content = chat.lastMessage!.content
        ..senderId = chat.lastMessage!.senderId
        ..senderName = chat.lastMessage!.senderName
        ..timestamp = chat.lastMessage!.timestamp
        ..type = chat.lastMessage!.type
        ..status = chat.lastMessage!.status;
    }

    return entity;
  }
}
