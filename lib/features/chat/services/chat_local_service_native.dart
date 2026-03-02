import 'package:diaspora_nearby/features/chat/models/chat.dart';
import 'package:diaspora_nearby/features/chat/models/message.dart';

/// Local chat cache service.
///
/// Previously powered by Isar. Now a no-op — Firestore's built-in offline
/// persistence handles all local caching automatically.
class ChatLocalService {
  ChatLocalService();

  Stream<List<Chat>> watchUserChats() {
    return const Stream.empty();
  }

  Future<void> saveChat(Chat chat) async {}

  Future<void> deleteChat(String chatId) async {}

  Future<void> clearAllChats() async {}

  Future<void> saveMessages(String chatId, List<Message> messages) async {}

  Future<List<Message>> getCachedMessages(String chatId) async {
    return [];
  }

  Future<List<Chat>> getAllChats() async {
    return [];
  }

  Future<Chat?> getChat(String chatId) async {
    return null;
  }
}
