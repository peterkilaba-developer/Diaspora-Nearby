import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import 'package:go_router/go_router.dart';
import 'package:diaspora_nearby/features/discovery/services/discovery_service.dart';
import 'package:diaspora_nearby/features/shared/widgets/user_card.dart';
import 'package:diaspora_nearby/features/profile/models/profile_data.dart';
import 'package:diaspora_nearby/features/auth/repository/auth_repository.dart';
import 'package:diaspora_nearby/features/profile/repository/profile_repository.dart';
import 'package:diaspora_nearby/features/chat/screens/chats_list_screen.dart';
import 'package:diaspora_nearby/features/dsp/services/exploration_registry.dart';
import 'package:diaspora_nearby/features/dsp/services/points_service.dart';
import 'package:diaspora_nearby/features/dsp/widgets/exploration_tracker.dart';

// Providers

final nearbyUsersStreamProvider = StreamProvider<List<ProfileData>>((ref) {
  final profileRepo = ref.read(profileRepositoryProvider);
  return DiscoveryService().getUsersNearby().map((users) {
    return users
        .map((json) {
          final profile = ProfileData.fromJson(json);
          if (profile.uid != null && profile.uid!.isNotEmpty) {
            profileRepo.cacheProfile(profile.uid!, profile);
          }
          return profile;
        })
        .toList(growable: false);
  });
});

class DiscoveryScreen extends ConsumerStatefulWidget {
  const DiscoveryScreen({super.key});

  @override
  ConsumerState<DiscoveryScreen> createState() => _DiscoveryScreenState();
}

class _DiscoveryScreenState extends ConsumerState<DiscoveryScreen> {
  @override
  void initState() {
    super.initState();
    unawaited(_trackExploration());
  }

  Future<void> _trackExploration() async {
    final user = ref.read(authRepositoryProvider).currentUser;
    if (user != null) {
      final rewarded = await ref
          .read(pointsServiceProvider)
          .trackExplorationReward(user.uid, ExplorationAction.discoveryExplore);
      if (rewarded && mounted) {
        showExplorationRewardToast(context);
      }
    }
  }

  Widget _buildResults(
    BuildContext context,
    List<ProfileData> rawUsers,
    Set<String> activeChatUserIds,
    String homeCountry,
  ) {
    final users = rawUsers
        .where((user) => !activeChatUserIds.contains(user.uid))
        .toList();

    if (users.isEmpty) {
      final allConnected = rawUsers.isNotEmpty && activeChatUserIds.isNotEmpty;

      if (allConnected) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  LucideIcons.messagesSquare,
                  size: 48,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 16),
                const Text(
                  'All Nearby Members Connected',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'You are already in active chats with all nearby community members in your area.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Theme.of(context).hintColor),
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(side: BorderSide.none),
                  onPressed: () => context.go('/chats'),
                  icon: const Icon(LucideIcons.messageSquare, size: 18),
                  label: const Text('View Active Chats'),
                ),
              ],
            ),
          ),
        );
      }

      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.location_off_outlined,
                size: 48,
                color: Colors.grey,
              ),
              const SizedBox(height: 16),
              Text(
                'There are no other community members from $homeCountry nearby',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 15),
              ),
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: () {
                  ref.invalidate(nearbyUsersStreamProvider);
                },
                icon: const Icon(LucideIcons.refreshCw, size: 16),
                label: const Text('Refresh Location'),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(8),
      itemCount: users.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final user = users[index];
        return UserCardView(
          user: user,
          onNameTap: () => context.push('/profile/${user.uid}'),
          onChatTap: () => context.push('/chat/direct/${user.uid}'),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final nearbyUsersAsync = ref.watch(nearbyUsersStreamProvider);
    final userProfileAsync = ref.watch(userProfileProvider);
    final chatsAsync = ref.watch(userChatsStreamProvider);
    final currentUser = ref.watch(authRepositoryProvider).currentUser;

    final homeCountry =
        userProfileAsync.value?.homeCountry ?? 'your home country';

    final Set<String> activeChatUserIds = {};
    if (currentUser != null && chatsAsync.value != null) {
      for (final chat in chatsAsync.value!) {
        if (chat.isDirect) {
          final otherId = chat.getOtherParticipantId(currentUser.uid);
          if (otherId != null && otherId.isNotEmpty) {
            activeChatUserIds.add(otherId);
          }
        }
      }
    }

    return Column(
      children: [
        Expanded(
          child: nearbyUsersAsync.when(
            skipLoadingOnRefresh: true,
            skipLoadingOnReload: true,
            data: (rawUsers) => _buildResults(
              context,
              rawUsers,
              activeChatUserIds,
              homeCountry,
            ),
            loading: () {
              final cachedRaw = DiscoveryService().cachedNearbyUsers;
              if (cachedRaw != null) {
                final parsed = cachedRaw
                    .map(ProfileData.fromJson)
                    .toList(growable: false);
                return _buildResults(
                  context,
                  parsed,
                  activeChatUserIds,
                  homeCountry,
                );
              }
              return const Center(child: CircularProgressIndicator());
            },
            error: (err, stack) => Center(child: Text('Error: $err')),
          ),
        ),
      ],
    );
  }
}
