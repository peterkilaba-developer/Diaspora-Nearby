import 'dart:async';
import 'package:cloud_functions/cloud_functions.dart';
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
import 'package:diaspora_nearby/features/dsp/services/points_service.dart';
import 'package:diaspora_nearby/features/shared/widgets/confetti_overlay.dart';
import 'package:diaspora_nearby/features/dsp/widgets/exploration_tracker.dart';
import 'package:diaspora_nearby/core/providers/global_feature_provider.dart';
import 'package:diaspora_nearby/features/profile/repository/profile_repository.dart';
import 'package:diaspora_nearby/features/profile/models/profile_data.dart';

final userChatsStreamProvider = StreamProvider<List<Chat>>((ref) {
  final authState = ref.watch(authStateProvider);
  final chatRepo = ref.watch(chatRepositoryProvider);
  final userId = authState.value?.uid;

  if (userId == null) {
    return const Stream.empty();
  }

  return chatRepo.subscribeToUserChats(userId: userId);
});

final discoverableChatsProvider = FutureProvider.family<List<Chat>, String>((
  ref,
  query,
) {
  final chatRepo = ref.watch(chatRepositoryProvider);
  return chatRepo.searchDiscoverableChats(query);
});

class ChatsListScreen extends ConsumerStatefulWidget {
  const ChatsListScreen({super.key});

  @override
  ConsumerState<ChatsListScreen> createState() => _ChatsListScreenState();
}

class _ChatsListScreenState extends ConsumerState<ChatsListScreen> {
  static const String diasporaAiAgentUid = 'diaspora_ai_agent';
  static const String _legacyFounderUid = 'yJ2REewPGWZQyS3zhisK1KziJJD3';
  static final Set<String> _ensuredAiAgentChatForUids = <String>{};
  static final Map<String, String> _resolvedAiAgentChatIdByUid =
      <String, String>{};

  static String _resolveNativeGreeting(ProfileData? profile) {
    final code = (profile?.homeCountryCode ?? '').trim().toUpperCase();
    switch (code) {
      case 'TZ':
      case 'KE':
        return 'Karibu sana';
      case 'UG':
        return 'Karibu / Tukusanyukidde';
      case 'RW':
        return 'Murakaza neza';
      case 'NG':
        return 'Nnọọ • E kaabo • Barka da zuwa';
      case 'GH':
        return 'Akwaaba';
      case 'ET':
        return 'እንኳን ደህና መጡ (Enkwan dehan metahu)';
      case 'ZA':
      case 'ZW':
        return 'Siyakwamukela';
      case 'FR':
      case 'SN':
      case 'CI':
      case 'CD':
      case 'CM':
      case 'HT':
        return 'Bienvenue';
      case 'EG':
      case 'MA':
      case 'DZ':
      case 'SA':
      case 'AE':
      case 'SD':
        return 'مرحباً بك (Marhaban)';
      case 'CN':
      case 'TW':
        return '欢迎 (Huānyíng)';
      case 'IN':
        return 'नमस्ते (Namaste)';
      case 'ES':
      case 'MX':
      case 'CO':
      case 'AR':
        return '¡Bienvenido/a';
      case 'BR':
      case 'PT':
      case 'AO':
      case 'MZ':
        return 'Bem-vindo(a)';
      case 'DE':
        return 'Herzlich willkommen';
      default:
        return 'Karibu • Welcome • Bienvenue';
    }
  }

  static String buildLocalAiAgentWelcomeText(ProfileData? profile) {
    final firstName = (profile?.firstName ?? '').trim();
    final greeting = _resolveNativeGreeting(profile);
    final namePart = firstName.isNotEmpty ? ', $firstName' : '';
    return '$greeting$namePart!\n\n'
        'I am Diaspora AI Agent, your 24/7 personal concierge on Diaspora Nearby.\n\n'
        'Any Language: Speak to me in English, Kiswahili, Français, العربية, Español, 中文, हिन्दी, Yoruba, Igbo, Hausa, Amharic, or any language you prefer.\n\n'
        'Here is what I can do for you right here in chat:\n'
        '• Flights, Hotels & Car Rentals: Search live flights, hotels, stays & peer car rentals or list your own car/stay.\n'
        '• Jobs & Marketplace: Find jobs, products, services & real estate — or tell me the details and I\'ll generate an instant Publish button right in chat.\n'
        '• Diaspora Utilities: Ask me anything about Nearby Discovery, Live Homeland Radio, Ubuntu Emergency Fund, DDI Loans, or \$DIASPORA.\n\n'
        'What can I help you find or post today?';
  }

  static List<Map<String, dynamic>> buildLocalWelcomeAiActions() {
    return <Map<String, dynamic>>[
      <String, dynamic>{
        'id': 'welcome_flights',
        'type': 'navigate',
        'label': 'Search Flights',
        'route': '/dsp/travel/flights',
        'icon': 'flight',
      },
      <String, dynamic>{
        'id': 'welcome_hotels',
        'type': 'navigate',
        'label': 'Find Hotels',
        'route': '/dsp/travel/hotels',
        'icon': 'hotel',
      },
      <String, dynamic>{
        'id': 'welcome_cars',
        'type': 'navigate',
        'label': 'Car Rentals',
        'route': '/dsp/travel/car-rental',
        'icon': 'car',
      },
      <String, dynamic>{
        'id': 'welcome_jobs',
        'type': 'navigate',
        'label': 'Browse Jobs',
        'route': '/marketplace?type=job',
        'icon': 'briefcase',
      },
      <String, dynamic>{
        'id': 'welcome_post_job',
        'type': 'prompt',
        'label': 'Post a Job in Chat',
        'prompt': 'I want to post a job listing.',
        'icon': 'plus',
      },
      <String, dynamic>{
        'id': 'welcome_nearby',
        'type': 'navigate',
        'label': 'Explore Nearby',
        'route': '/nearby',
        'icon': 'compass',
      },
    ];
  }

  Chat _buildSyntheticAiAgentChat(String currentUid, ProfileData? profile) {
    final resolvedChatId =
        _resolvedAiAgentChatIdByUid[currentUid] ?? 'ai_agent_$currentUid';
    final welcomeText = buildLocalAiAgentWelcomeText(profile);
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    return Chat(
      id: resolvedChatId,
      type: 'direct',
      name: 'Diaspora AI Agent',
      photoUrl: 'https://diasporanearby.com/icons/Icon-512.png',
      participants: <String>[currentUid, diasporaAiAgentUid],
      createdAt: nowMs,
      updatedAt: nowMs,
      unreadCount: 1,
      metadata: const <String, dynamic>{'isAiAgent': true},
      lastMessage: LastMessage(
        id: 'welcome_from_ai_agent',
        content: welcomeText,
        timestamp: nowMs,
        senderId: diasporaAiAgentUid,
        senderName: 'Diaspora AI Agent',
        type: 'text',
        status: 'sent',
        metadata: <String, dynamic>{
          'isAiAgent': true,
          'aiActions': buildLocalWelcomeAiActions(),
        },
      ),
    );
  }

  void _ensureAiAgentDirectChatIfMissing(String? currentUid, List<Chat> chats) {
    if (currentUid == null ||
        currentUid.isEmpty ||
        currentUid == diasporaAiAgentUid ||
        _ensuredAiAgentChatForUids.contains(currentUid)) {
      return;
    }
    final existingAiChat = chats.cast<Chat?>().firstWhere(
      (chat) =>
          chat != null &&
          chat.isDirect &&
          (chat.participants.contains(diasporaAiAgentUid) ||
              chat.getOtherParticipantId(currentUid) == diasporaAiAgentUid ||
              chat.metadata?['isAiAgent'] == true),
      orElse: () => null,
    );
    if (existingAiChat != null) {
      _ensuredAiAgentChatForUids.add(currentUid);
      _resolvedAiAgentChatIdByUid[currentUid] = existingAiChat.id;
      return;
    }
    _ensuredAiAgentChatForUids.add(currentUid);
    FirebaseFunctions.instance
        .httpsCallable('ensureDirectChat')
        .call<Map<String, dynamic>>({
          'otherUserId': diasporaAiAgentUid,
          'isAiAgentWelcome': true,
        })
        .then((res) {
          final chatId = res.data['chatId']?.toString();
          if (chatId != null && chatId.isNotEmpty) {
            _resolvedAiAgentChatIdByUid[currentUid] = chatId;
            if (mounted) {
              ref
                  .read(chatRepositoryProvider)
                  .removeChatFromCache('ai_agent_$currentUid');
              setState(() {});
            }
          }
        })
        .catchError((Object _) {});
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

  Widget _buildGlobalDiscoverableList(
    BuildContext context,
    ThemeData theme,
    List<Chat> allResults,
    String searchQuery,
  ) {
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
            onTap: () {
              // Navigate immediately in 0ms
              if (chat.type == 'event') {
                if (chat.eventId != null) {
                  context.push('/events/${chat.eventId}');
                }
              } else if (chat.type == 'organization') {
                context.push('/organization/${chat.communityId}');
              } else if (chat.type == 'community' || chat.isCommunity) {
                context.push('/communities/${chat.communityId}');
              } else if (chat.type == 'group') {
                context.push('/chats/${chat.id}');
              }

              // Track Discovery Click in background
              final user = ref.read(authRepositoryProvider).currentUser;
              if (user != null) {
                final actionId = 'action_discover_chat_${chat.id}';
                unawaited(
                  ref
                      .read(pointsServiceProvider)
                      .trackExplorationReward(user.uid, actionId)
                      .then((rewarded) {
                        if (rewarded && context.mounted) {
                          confettiOverlayKey.currentState?.play();
                          showExplorationRewardToast(
                            context,
                            message: 'Discovered ${chat.name}',
                            points: 100,
                          );
                        }
                      }),
                );
              }
            },
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chatsAsync = ref.watch(userChatsStreamProvider);
    final searchQuery = ref.watch(globalSearchProvider);
    final chatsMode = ref.watch(chatsViewModeProvider);

    // GLOBAL SEARCH MODE
    if (chatsMode == ViewMode.global) {
      final discoverableAsync = ref.watch(
        discoverableChatsProvider(searchQuery),
      );

      return discoverableAsync.when(
        skipLoadingOnReload: true,
        skipLoadingOnRefresh: true,
        loading: () {
          final cachedDiscoverable = ref
              .read(chatRepositoryProvider)
              .filterDiscoverableChatsSync(searchQuery);
          if (cachedDiscoverable != null) {
            return _buildGlobalDiscoverableList(
              context,
              theme,
              cachedDiscoverable,
              searchQuery,
            );
          }
          return const SkeletonList(skeleton: ChatCardSkeleton());
        },
        error: (error, stack) =>
            const Center(child: Text('Error searching chats')),
        data: (allResults) => _buildGlobalDiscoverableList(
          context,
          theme,
          allResults,
          searchQuery,
        ),
      );
    }

    // HOME MODE (My Chats)
    final cachedChats = ref.read(chatRepositoryProvider).cachedChats;
    if (chatsAsync.isLoading && cachedChats.isNotEmpty) {
      return _buildHomeChatsList(context, theme, cachedChats, searchQuery);
    }

    return chatsAsync.when(
      skipLoadingOnReload: true,
      skipLoadingOnRefresh: true,
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
      data: (chats) => _buildHomeChatsList(context, theme, chats, searchQuery),
    );
  }

  Widget _buildHomeChatsList(
    BuildContext context,
    ThemeData theme,
    List<Chat> chats,
    String searchQuery,
  ) {
    final currentUid = ref.read(authRepositoryProvider).currentUser?.uid;
    final currentUserProfile = ref.watch(userProfileProvider).value;
    _ensureAiAgentDirectChatIfMissing(currentUid, chats);
    final visibleChats = chats.where((chat) {
      if (chat.isDirect &&
          chat.lastMessage?.id == 'welcome_from_founder' &&
          (chat.participants.contains(_legacyFounderUid) ||
              (currentUid != null &&
                  chat.getOtherParticipantId(currentUid) ==
                      _legacyFounderUid))) {
        return false;
      }
      return true;
    }).toList();
    if (currentUid != null && currentUid.isNotEmpty) {
      bool isAiChat(Chat chat) =>
          chat.isDirect &&
          (chat.id.startsWith('ai_agent_') ||
              chat.participants.contains(diasporaAiAgentUid) ||
              chat.getOtherParticipantId(currentUid) == diasporaAiAgentUid ||
              chat.metadata?['isAiAgent'] == true);

      final aiChats = visibleChats.where(isAiChat).toList();
      if (aiChats.isEmpty) {
        final syntheticAiChat = _buildSyntheticAiAgentChat(
          currentUid,
          currentUserProfile,
        );
        ref
            .read(chatRepositoryProvider)
            .upsertChatInCache(syntheticAiChat, notify: false);
        visibleChats.insert(0, syntheticAiChat);
      } else if (aiChats.length > 1) {
        // Keep the canonical Firestore chat (non-synthetic) or the newest one, and drop duplicates
        final canonicalAiChat = aiChats.firstWhere(
          (c) => !c.id.startsWith('ai_agent_'),
          orElse: () => aiChats.first,
        );
        for (final dup in aiChats) {
          if (dup.id != canonicalAiChat.id) {
            visibleChats.removeWhere((c) => c.id == dup.id);
            if (dup.id.startsWith('ai_agent_')) {
              ref
                  .read(chatRepositoryProvider)
                  .removeChatFromCache(dup.id, notify: false);
            }
          }
        }
      }
    }
    if (currentUid != null) {
      for (final chat in visibleChats) {
        if (chat.isDirect) {
          final otherId = chat.getOtherParticipantId(currentUid);
          if (otherId != null &&
              otherId.isNotEmpty &&
              otherId != diasporaAiAgentUid) {
            ref.read(chatPartnerProvider(otherId));
          }
        }
      }
    }

    final isGlobalUnlocked = ref.watch(isGlobalUnlockedSyncProvider);
    final baseChats = isGlobalUnlocked
        ? visibleChats
        : visibleChats
              .where(
                (chat) =>
                    chat.id != 'global_community' &&
                    chat.id != 'chat_global_community' &&
                    chat.locationType != 'global' &&
                    chat.type != 'global' &&
                    !chat.name.toLowerCase().contains('global community'),
              )
              .toList();

    final filteredChats =
        (searchQuery.isEmpty
              ? List<Chat>.from(baseChats)
              : baseChats.where((chat) {
                  final query = searchQuery.toLowerCase();
                  final nameMatch = chat.name.toLowerCase().contains(query);
                  final messageMatch =
                      chat.lastMessage?.content.toLowerCase().contains(query) ??
                      false;
                  return nameMatch || messageMatch;
                }).toList())
          ..sort(ChatRepository.compareChatsByLatest);

    if (filteredChats.isEmpty) {
      return RefreshIndicator(
        onRefresh: () async {
          await ref.read(chatRepositoryProvider).refreshChatsFromServer();
          await _syncCommunities();
        },
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: _buildEmptyState(theme, chats.isEmpty),
            ),
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async {
        await _syncCommunities();
        await ref.read(chatRepositoryProvider).refreshChatsFromServer();
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
