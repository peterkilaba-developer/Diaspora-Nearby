import 'package:diaspora_nearby/features/chat/models/chat.dart';
import 'package:diaspora_nearby/features/chat/models/message.dart';

class ChatLocalService {
  ChatLocalService();

  Stream<List<Chat>> watchUserChats() {
    return const Stream.empty();
  }

  Future<void> saveChat(Chat chat) async {}

  Future<void> deleteChat(String chatId) async {}

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
