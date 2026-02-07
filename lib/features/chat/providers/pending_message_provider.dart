import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:diaspora_nearby/features/chat/models/message.dart';

class PendingMessagesNotifier extends Notifier<Map<String, List<Message>>> {
  @override
  Map<String, List<Message>> build() {
    return {};
  }

  void addMessage(String chatId, Message message) {
    final current = state;
    final messages = current[chatId] ?? [];

    state = {
      ...current,
      chatId: [...messages, message],
    };
  }

  void removeMessage(String chatId, String tempId) {
    final current = state;
    if (!current.containsKey(chatId)) return;

    final messages = current[chatId]!.where((m) => m.id != tempId).toList();
    if (messages.isEmpty) {
      final newState = Map<String, List<Message>>.from(current);
      newState.remove(chatId);
      state = newState;
    } else {
      state = {...current, chatId: messages};
    }
  }

  void updateMessageStatus(String chatId, String tempId, String status) {
    final current = state;
    if (!current.containsKey(chatId)) return;

    final messages = current[chatId]!.map((m) {
      if (m.id == tempId) {
        return m.copyWith(status: status);
      }
      return m;
    }).toList();

    state = {...current, chatId: messages};
  }
}

final pendingMessagesProvider =
    NotifierProvider<PendingMessagesNotifier, Map<String, List<Message>>>(
      PendingMessagesNotifier.new,
    );
