import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:diaspora_nearby/features/home/repository/home_repository.dart';
import 'package:diaspora_nearby/features/profile/models/profile_data.dart';
import 'package:diaspora_nearby/features/shared/widgets/user_card.dart';
import 'package:diaspora_nearby/core/providers/view_mode_provider.dart';
import 'package:diaspora_nearby/features/discovery/providers/global_search_provider.dart';
import 'package:diaspora_nearby/features/profile/repository/profile_repository.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:diaspora_nearby/theme/app_theme.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

// [PERF FIX] Removed duplicate _ensureBackgroundService() — already handled by
// ScaffoldWithNavBar, which is the parent of this screen. Running it in both
// caused two parallel background service initializations racing each other.
class _HomeScreenState extends ConsumerState<HomeScreen> {
  @override
  Widget build(BuildContext context) {
    final searchQuery = ref.watch(globalSearchProvider);
    final userProfileAsync = ref.watch(userProfileProvider);
    final viewMode = ref.watch(nearbyViewModeProvider);
    final isGlobal = viewMode == ViewMode.global;

    // [PERF] If searching, use a separate FutureProvider for search results.
    // Otherwise, use the cached nearbyUsersProvider.
    if (searchQuery.isNotEmpty) {
      return _buildSearchResults(searchQuery);
    }

    // [PERF FIX] Use cached AsyncNotifierProvider instead of FutureBuilder.
    // This prevents re-fetching 200+ Firestore docs on every widget rebuild
    // (tab switch, app resume, provider notification, etc.)
    final nearbyAsync = ref.watch(nearbyUsersProvider);

    return nearbyAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(child: Text('Error: $error')),
      data: (users) {
        if (users.isEmpty) {
          if (isGlobal) {
            return const Center(child: Text('No global users found.'));
          }

          // Local empty state
          final homeCountry =
              userProfileAsync.value?.homeCountry ?? 'your home country';

          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32.0),
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
                    style: const TextStyle(fontSize: 16, color: Colors.grey),
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
                  FilledButton.icon(
                    onPressed: () {
                      ref.read(nearbyViewModeProvider.notifier).setGlobal();
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
              ),
            ),
          );
        }

        // [PERF] Pull-to-refresh support — lets users force a data refresh
        return RefreshIndicator(
          onRefresh: () => ref.read(nearbyUsersProvider.notifier).refresh(),
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            itemCount: users.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              return UserCardView(
                user: users[index],
                searchQuery: searchQuery,
                onNameTap: () => context.push(
                  '/profile/${users[index].uid}',
                  extra: {'distance': users[index].distance},
                ),
                onChatTap: () =>
                    context.push('/chat/direct/${users[index].uid}'),
              );
            },
          ),
        );
      },
    );
  }

  /// [PERF] Search results as a separate widget to avoid polluting
  /// the cached nearby users provider
  Widget _buildSearchResults(String searchQuery) {
    final homeRepo = ref.watch(homeRepositoryProvider);

    return FutureBuilder<List<ProfileData>>(
      key: ValueKey('search_$searchQuery'),
      future: homeRepo.searchUsers(searchQuery),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        final users = snapshot.data ?? [];
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
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            return UserCardView(
              user: users[index],
              searchQuery: searchQuery,
              onNameTap: () => context.push(
                '/profile/${users[index].uid}',
                extra: {'distance': users[index].distance},
              ),
              onChatTap: () =>
                  context.push('/chat/direct/${users[index].uid}'),
            );
          },
        );
      },
    );
  }
}
