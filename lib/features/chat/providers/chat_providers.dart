import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:diaspora_nearby/features/chat/models/chat.dart';
import 'package:diaspora_nearby/features/chat/models/message.dart';
import 'package:diaspora_nearby/features/chat/repository/chat_repository.dart';
import 'package:diaspora_nearby/features/profile/models/profile_data.dart';
import 'package:diaspora_nearby/features/profile/repository/profile_repository.dart';
import 'package:diaspora_nearby/features/auth/repository/auth_repository.dart';
import 'package:diaspora_nearby/features/community/repository/community_repository.dart';
import 'package:diaspora_nearby/features/community/models/community_data.dart';

final communityDetailsProvider = FutureProvider.family<Community?, String>((
  ref,
  communityId,
) {
  ref.keepAlive();
  final commRepo = ref.read(communityRepositoryProvider);
  final cached = commRepo.getCachedCommunity(communityId);
  if (cached != null) {
    unawaited(commRepo.getCommunity(communityId));
    return SynchronousFuture<Community?>(cached);
  }
  return commRepo.getCommunity(communityId);
});

/// Provider for messages stream
final messagesStreamProvider = StreamProvider.family<List<Message>, String>((
  ref,
  chatId,
) {
  ref.keepAlive();
  final chatRepo = ref.watch(chatRepositoryProvider);
  final userProfileAsync = ref.watch(userProfileProvider);

  return chatRepo.subscribeToMessages(chatId).map((messages) {
    final blocked = userProfileAsync.value?.blockedUsers ?? [];
    if (blocked.isEmpty) return messages;

    return messages.where((m) => !blocked.contains(m.senderId)).toList();
  });
});

/// Provider for single chat
final chatProvider = FutureProvider.family<Chat?, String>((ref, chatId) {
  ref.keepAlive();
  final chatRepo = ref.watch(chatRepositoryProvider);
  final cached = chatRepo.getCachedChat(chatId);
  if (cached != null) {
    unawaited(chatRepo.getChat(chatId));
    return SynchronousFuture<Chat?>(cached);
  }
  return chatRepo.getChat(chatId);
});

/// Provider for chat display name
final chatDisplayNameProvider = FutureProvider.family<String, String>((
  ref,
  chatId,
) {
  ref.keepAlive();
  final chatRepo = ref.watch(chatRepositoryProvider);
  final cached = chatRepo.getCachedChat(chatId);
  if (cached != null) {
    if (cached.isDirect && chatRepo.currentUserId != null) {
      final otherId = cached.getOtherParticipantId(chatRepo.currentUserId!);
      if (otherId != null && otherId.isNotEmpty) {
        final cachedProfile = ref
            .read(profileRepositoryProvider)
            .getCachedProfile(otherId);
        if (cachedProfile != null) {
          final fullName =
              '${cachedProfile.firstName} ${cachedProfile.lastName}'.trim();
          if (fullName.isNotEmpty) {
            return SynchronousFuture<String>(fullName);
          }
        }
      }
    } else if (cached.name.isNotEmpty) {
      return SynchronousFuture<String>(cached.name);
    }
  }
  return () async {
    final chat = cached ?? await chatRepo.getChat(chatId);
    if (chat == null) return 'Chat';
    return chatRepo.getDisplayNameForChat(chat);
  }();
});

/// Provider for other user's profile in direct chats
final chatScreenUserProfileProvider = FutureProvider.family<ProfileData?, Chat>(
  (ref, chat) {
    ref.keepAlive();
    if (!chat.isDirect) return SynchronousFuture<ProfileData?>(null);

    final currentUserId = ref.watch(authStateProvider).value?.uid;
    if (currentUserId == null) return SynchronousFuture<ProfileData?>(null);

    final otherUserId = chat.participants.firstWhere(
      (id) => id != currentUserId,
      orElse: () => '',
    );

    if (otherUserId.isEmpty) return SynchronousFuture<ProfileData?>(null);

    final profileRepo = ref.watch(profileRepositoryProvider);
    final cached = profileRepo.getCachedProfile(otherUserId);
    if (cached != null) {
      return SynchronousFuture<ProfileData?>(cached);
    }
    return profileRepo.getUserProfile(otherUserId);
  },
);
