import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:diaspora_nearby/features/home/repository/home_repository.dart';
import 'package:diaspora_nearby/features/profile/models/profile_data.dart';
import 'package:diaspora_nearby/features/shared/widgets/user_card.dart';
import 'package:diaspora_nearby/core/providers/view_mode_provider.dart';
import 'package:diaspora_nearby/features/discovery/providers/global_search_provider.dart';
import 'package:diaspora_nearby/features/profile/repository/profile_repository.dart';
import 'package:diaspora_nearby/features/auth/repository/auth_repository.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:diaspora_nearby/theme/app_theme.dart';

import 'package:diaspora_nearby/core/providers/global_feature_provider.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  List<ProfileData> _lastSearchResults = const [];

  @override
  Widget build(BuildContext context) {
    final searchQuery = ref.watch(globalSearchProvider);
    final userProfileAsync = ref.watch(userProfileProvider);
    final currentUid = ref.read(authRepositoryProvider).currentUser?.uid;
    final userProfile =
        userProfileAsync.value ??
        (currentUid != null
            ? ref.read(profileRepositoryProvider).getCachedProfile(currentUid)
            : null);
    final viewMode = ref.watch(nearbyViewModeProvider);
    final isGlobal = viewMode == ViewMode.global;

    if (searchQuery.isNotEmpty) {
      return _buildSearchResults(searchQuery);
    }

    final nearbyAsync = ref.watch(nearbyUsersProvider);
    final cachedForMode = NearbyUsersNotifier.getCachedForMode(viewMode);
    final users = nearbyAsync.value ?? cachedForMode;

    if (nearbyAsync.isLoading && users == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (nearbyAsync.hasError && users == null) {
      return Center(child: Text('Error: ${nearbyAsync.error}'));
    }

    final resolvedUsers = users ?? const <ProfileData>[];

    if (resolvedUsers.isEmpty) {
      if (isGlobal) {
        return RefreshIndicator(
          onRefresh: () => ref.read(nearbyUsersProvider.notifier).refresh(),
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight,
                ),
                child: const Center(child: Text('No global users found.')),
              ),
            ),
          ),
        );
      }

      // Local empty state
      final homeCountry = userProfile?.homeCountry ?? 'your home country';

      return RefreshIndicator(
        onRefresh: () => ref.read(nearbyUsersProvider.notifier).refresh(),
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppTheme.pageHorizontalPadding,
                    vertical: 24.0,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        LucideIcons.mapPinOff,
                        size: 48,
                        color: Colors.grey.shade400,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'There is no other community member from $homeCountry nearby..',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 16,
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Congratulations on being the first in this location!',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 24),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          side: BorderSide.none,
                          backgroundColor: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest
                              .withValues(alpha: 0.4),
                        ),
                        onPressed: () =>
                            ref.read(nearbyUsersProvider.notifier).refresh(),
                        icon: const Icon(LucideIcons.refreshCw, size: 16),
                        label: const Text('Refresh'),
                      ),
                      if (ref.watch(isGlobalUnlockedSyncProvider)) ...[
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          onPressed: () {
                            ref
                                .read(nearbyViewModeProvider.notifier)
                                .setGlobal();
                          },
                          icon: const Icon(LucideIcons.globe),
                          label: const Text('Switch to Global View'),
                          style: FilledButton.styleFrom(
                            backgroundColor: AppTheme.accent,
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppTheme.pageHorizontalPadding,
                              vertical: 12,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => ref.read(nearbyUsersProvider.notifier).refresh(),
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        itemCount: resolvedUsers.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          return UserCardView(
            user: resolvedUsers[index],
            searchQuery: searchQuery,
            onNameTap: () => context.push(
              '/profile/${resolvedUsers[index].uid}',
              extra: {'distance': resolvedUsers[index].distance},
            ),
            onChatTap: () =>
                context.push('/chat/direct/${resolvedUsers[index].uid}'),
          );
        },
      ),
    );
  }

  /// [PERF] Instant 0ms search seeded from local cache without keystroke spinner flashes
  Widget _buildSearchResults(String searchQuery) {
    final homeRepo = ref.watch(homeRepositoryProvider);
    final cachedMatches = homeRepo.searchCachedUsers(searchQuery);
    final initialSeed = cachedMatches.isNotEmpty
        ? cachedMatches
        : _lastSearchResults
              .where((u) {
                final q = searchQuery.toLowerCase();
                final name = '${u.firstName} ${u.lastName}'.toLowerCase();
                return name.contains(q);
              })
              .toList();

    return FutureBuilder<List<ProfileData>>(
      key: ValueKey('search_$searchQuery'),
      initialData: initialSeed.isNotEmpty ? initialSeed : null,
      future: homeRepo.searchUsers(searchQuery),
      builder: (context, snapshot) {
        if (snapshot.hasData &&
            snapshot.connectionState == ConnectionState.done) {
          _lastSearchResults = snapshot.data!;
        }

        final users = snapshot.data ?? initialSeed;
        if (snapshot.connectionState == ConnectionState.waiting &&
            users.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError && users.isEmpty) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        if (users.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  LucideIcons.searchX,
                  size: 48,
                  color: Colors.grey.shade400,
                ),
                const SizedBox(height: 16),
                Text(
                  'No results for "$searchQuery"',
                  style: const TextStyle(fontSize: 16, color: Colors.grey),
                ),
              ],
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          itemCount: users.length,
          separatorBuilder: (_, _) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            return UserCardView(
              user: users[index],
              searchQuery: searchQuery,
              onNameTap: () => context.push(
                '/profile/${users[index].uid}',
                extra: {'distance': users[index].distance},
              ),
              onChatTap: () => context.push('/chat/direct/${users[index].uid}'),
            );
          },
        );
      },
    );
  }
}
