import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:diaspora_nearby/features/chat/models/chat.dart';
import 'package:diaspora_nearby/features/chat/models/message.dart';
import 'package:diaspora_nearby/features/chat/repository/chat_repository.dart';
import 'package:diaspora_nearby/features/profile/models/profile_data.dart';
import 'package:diaspora_nearby/features/profile/repository/profile_repository.dart';
import 'package:diaspora_nearby/features/auth/repository/auth_repository.dart';
import 'package:diaspora_nearby/features/community/repository/community_repository.dart'; // [NEW]
import 'package:diaspora_nearby/features/community/models/community_data.dart'; // [NEW]

final communityDetailsProvider = FutureProvider.family<Community?, String>((
  ref,
  communityId,
) {
  return ref.read(communityRepositoryProvider).getCommunity(communityId);
});

/// Provider for messages stream
final messagesStreamProvider = StreamProvider.family<List<Message>, String>((
  ref,
  chatId,
) {
  final chatRepo = ref.watch(chatRepositoryProvider);
  final userProfileAsync = ref.watch(userProfileProvider);

  return chatRepo.subscribeToMessages(chatId).map((messages) {
    // Filter blocked users
    final blocked = userProfileAsync.value?.blockedUsers ?? [];
    if (blocked.isEmpty) return messages;

    return messages.where((m) => !blocked.contains(m.senderId)).toList();
  });
});

/// Provider for single chat
final chatProvider = FutureProvider.family<Chat?, String>((ref, chatId) async {
  final chatRepo = ref.watch(chatRepositoryProvider);
  return chatRepo.getChat(chatId);
});

/// Provider for chat display name
final chatDisplayNameProvider = FutureProvider.family<String, String>((
  ref,
  chatId,
) async {
  final chatRepo = ref.watch(chatRepositoryProvider);
  final chat = await chatRepo.getChat(chatId);
  if (chat == null) return 'Chat';
  return chatRepo.getDisplayNameForChat(chat);
});

/// Provider for other user's profile in direct chats
final chatScreenUserProfileProvider = FutureProvider.family<ProfileData?, Chat>(
  (ref, chat) async {
    if (!chat.isDirect) return null;

    // Get the other participant's ID
    final currentUserId = ref.watch(authStateProvider).value?.uid;
    if (currentUserId == null) return null;

    final otherUserId = chat.participants.firstWhere(
      (id) => id != currentUserId,
      orElse: () => '',
    );

    if (otherUserId.isEmpty) return null;

    final profileRepo = ref.watch(profileRepositoryProvider);
    return profileRepo.getUserProfile(otherUserId);
  },
);
