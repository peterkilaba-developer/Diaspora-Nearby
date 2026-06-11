import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:diaspora_nearby/features/chat/models/chat.dart';
import 'package:diaspora_nearby/features/chat/repository/chat_repository.dart';
import 'package:diaspora_nearby/features/chat/widgets/chat_card.dart';
import 'package:diaspora_nearby/features/community/repository/community_repository.dart';
import 'package:diaspora_nearby/features/auth/repository/auth_repository.dart';
import 'package:diaspora_nearby/features/discovery/providers/global_search_provider.dart';
import 'package:diaspora_nearby/features/shared/ui/skeleton_loader.dart';
import 'package:diaspora_nearby/core/providers/view_mode_provider.dart';
import 'package:diaspora_nearby/features/dsp/services/points_service.dart'; // [NEW]
import 'package:diaspora_nearby/features/shared/widgets/confetti_overlay.dart'; // [NEW]
import 'package:diaspora_nearby/features/dsp/widgets/exploration_tracker.dart'; // [NEW]

final userChatsStreamProvider = StreamProvider<List<Chat>>((ref) {
  final authState = ref.watch(authStateProvider);
  final chatRepo = ref.watch(chatRepositoryProvider);

  // If user is not authenticated, return empty stream
  if (authState.value == null) {
    return const Stream.empty();
  }

  return chatRepo.subscribeToUserChats();
});

class ChatsListScreen extends ConsumerStatefulWidget {
  const ChatsListScreen({super.key});

  @override
  ConsumerState<ChatsListScreen> createState() => _ChatsListScreenState();
}

class _ChatsListScreenState extends ConsumerState<ChatsListScreen> {
  @override
  void initState() {
    super.initState();
    // Sync communities on startup - REMOVED to prevent refresh loop
    // _syncCommunities() writes to DB -> triggers stream -> rebuilds UI -> loop/flash
  }

  Future<void> _syncCommunities() async {
    try {
      final currentUserId = ref.read(authRepositoryProvider).currentUser?.uid;
      if (currentUserId == null) return;

      final communityRepo = ref.read(communityRepositoryProvider);
      final chatRepo = ref.read(chatRepositoryProvider);

      final communities = await communityRepo.getUserCommunities(currentUserId);
      if (communities.isNotEmpty) {
        await chatRepo.syncCommunityChats(
          communities.map((c) => c.id).toList(),
        );
      }
    } catch (e) {
      debugPrint('Error syncing communities: $e');
    }
  }

  // [PERF] Removed _precacheChatAvatars — CachedNetworkImage already handles
  // caching internally. Calling precacheImage on every stream emit was redundant.

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chatsAsync = ref.watch(userChatsStreamProvider);
    final searchQuery = ref.watch(globalSearchProvider);
    final chatsMode = ref.watch(chatsViewModeProvider);

    // GLOBAL SEARCH MODE
    if (chatsMode == ViewMode.global) {
      // Show all or filtered based on query

      return FutureBuilder<List<Chat>>(
        future: ref
            .read(chatRepositoryProvider)
            .searchDiscoverableChats(searchQuery),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const SkeletonList(skeleton: ChatCardSkeleton());
          }
          if (snapshot.hasError) {
            return const Center(child: Text('Error searching chats'));
          }

          final allResults = snapshot.data ?? [];
          // Filter to show ONLY Organization and Event chats in Global mode
          final results = allResults
              .where(
                (chat) =>
                    chat.type == 'organization' ||
                    chat.type == 'event' ||
                    chat.type == 'group',
              )
              .toList();

          if (results.isEmpty) {
            return _buildEmptyState(
              theme,
              false,
              isGlobal: true,
              hasQuery: searchQuery.isNotEmpty,
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            itemCount: results.length,
            itemBuilder: (context, index) {
              final chat = results[index];
              return RepaintBoundary(
                child: ChatCard(
                chat: chat,
                searchQuery: searchQuery,
                onTap: () async {
                  // [NEW] Track Discovery Click
                  final user = ref.read(authRepositoryProvider).currentUser;
                  if (user != null) {
                    final actionId = 'action_discover_chat_${chat.id}';
                    final rewarded = await ref
                        .read(pointsServiceProvider)
                        .trackExplorationReward(user.uid, actionId);
                    if (rewarded && context.mounted) {
                      confettiOverlayKey.currentState?.play();
                      showExplorationRewardToast(
                        context,
                        message: 'Discovered ${chat.name}',
                        points: 100,
                      );
                    }
                  }

                  // Navigate to entity details instead of chat screen
                  if (chat.type == 'event') {
                    // Ensure we pass eventId if available, otherwise we might have issues if chat.eventId is null
                    if (chat.eventId != null) {
                      if (context.mounted) {
                        context.push('/events/${chat.eventId}');
                      }
                    }
                  } else if (chat.type == 'organization') {
                    // We used communityId to store orgId in searchDiscoverableChats
                    if (context.mounted) {
                      context.push('/organization/${chat.communityId}');
                    }
                  } else if (chat.type == 'community' || chat.isCommunity) {
                    if (context.mounted) {
                      // Navigate to community detail page for discovery/joining
                      context.push('/communities/${chat.communityId}');
                    }
                  } else if (chat.type == 'group') {
                    // [NEW]
                    if (context.mounted) {
                      // For public groups, go to chat. ChatScreen should handle non-member view (Join button).
                      context.push('/chats/${chat.id}');
                    }
                  }
                },
              ),
              );
            },
          );
        },
      );
    }

    // HOME MODE (My Chats)
    return chatsAsync.when(
      loading: () => const SkeletonList(skeleton: ChatCardSkeleton()),
      error: (error, stack) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              LucideIcons.alertCircle,
              size: 48,
              color: theme.colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text('Error loading chats', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => ref.invalidate(userChatsStreamProvider),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
      data: (chats) {
        // Pre-warm partner profiles so DM cards render with names on first paint.
        // keepAlive() on chatPartnerProvider ensures these are fetched only once
        // per app session, not re-fetched on every tab switch.
        final currentUid = ref.read(authRepositoryProvider).currentUser?.uid;
        if (currentUid != null) {
          for (final chat in chats) {
            if (chat.isDirect) {
              final otherId = chat.getOtherParticipantId(currentUid);
              if (otherId != null && otherId.isNotEmpty) {
                ref.read(chatPartnerProvider(otherId));
              }
            }
          }
        }

        final filteredChats = searchQuery.isEmpty
            ? chats
            : chats.where((chat) {
                final query = searchQuery.toLowerCase();
                final nameMatch = chat.name.toLowerCase().contains(query);
                final messageMatch =
                    chat.lastMessage?.content.toLowerCase().contains(query) ??
                    false;
                return nameMatch || messageMatch;
              }).toList();

        if (filteredChats.isEmpty) {
          return _buildEmptyState(theme, chats.isEmpty);
        }

        return RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(userChatsStreamProvider);
            await _syncCommunities();
          },
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            itemCount: filteredChats.length,
            itemBuilder: (context, index) {
              final chat = filteredChats[index];
              return RepaintBoundary(
                child: ChatCard(
                  key: ValueKey(chat.id),
                  chat: chat,
                  searchQuery: searchQuery.isNotEmpty ? searchQuery : null,
                  onTap: () => context.push('/chats/${chat.id}'),
                ),
              );
            },
          ),
        );
      },
    );
    // ... (rest of build)
  }

  Widget _buildEmptyState(
    ThemeData theme,
    bool noChats, {
    bool isGlobal = false,
    bool hasQuery = false,
  }) {
    String title;
    String subtitle;

    if (isGlobal) {
      if (!hasQuery) {
        title = 'Search Global Chats';
        subtitle = 'Find Events and Organizations to join';
      } else {
        title = 'No results found';
        subtitle = 'Try a different search term';
      }
    } else {
      if (noChats) {
        title = 'No conversations yet';
        subtitle = 'Start a conversation by tapping the + button';
      } else {
        title = 'No chats found';
        subtitle = 'Try a different search term';
      }
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              noChats ? LucideIcons.messageCircle : LucideIcons.search,
              size: 64,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: theme.textTheme.titleLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
