import 'package:flutter/material.dart';
import 'package:diaspora_nearby/core/data/countries.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:diaspora_nearby/features/radio/repository/radio_repository.dart';
import 'package:diaspora_nearby/features/radio/providers/radio_provider.dart';
import 'package:diaspora_nearby/features/radio/models/radio_station.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:diaspora_nearby/features/dsp/services/exploration_registry.dart';
import 'package:diaspora_nearby/features/dsp/services/points_service.dart';
import 'package:diaspora_nearby/features/dsp/widgets/exploration_tracker.dart';
import 'package:diaspora_nearby/features/auth/repository/auth_repository.dart';
import 'package:diaspora_nearby/features/profile/repository/profile_repository.dart';
import 'package:diaspora_nearby/features/discovery/providers/global_search_provider.dart';
import 'package:diaspora_nearby/features/shared/ui/glass_container.dart';
import 'package:diaspora_nearby/core/providers/view_mode_provider.dart';
import 'package:diaspora_nearby/features/shared/utils/search_highlight_utils.dart';
import 'package:diaspora_nearby/features/shared/widgets/confetti_overlay.dart';

// --- Providers ---
final stationsByCountryProvider =
    FutureProvider.family<List<RadioStation>, String>((ref, countryCode) async {
      final repo = ref.watch(radioRepositoryProvider);
      return repo.getStationsByCountry(countryCode);
    });

final topStationsProvider = FutureProvider<List<RadioStation>>((ref) async {
  final repo = ref.watch(radioRepositoryProvider);
  return repo.getTopStations();
});

// [NEW] Global Search Provider
final globalSearchStationsProvider =
    FutureProvider.family<List<RadioStation>, String>((ref, query) async {
      final repo = ref.watch(radioRepositoryProvider);
      if (query.trim().isEmpty) return [];
      return repo.searchStations(query);
    });

// --- UI ---

class RadioScreen extends ConsumerStatefulWidget {
  const RadioScreen({super.key});

  @override
  ConsumerState<RadioScreen> createState() => _RadioScreenState();
}

class _RadioScreenState extends ConsumerState<RadioScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    // [NEW] Track Radio Exploration
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref
          .read(pointsServiceProvider)
          .trackExplorationReward(
            ref.read(authRepositoryProvider).currentUser?.uid ?? '',
            ExplorationAction.radioExplore,
          )
          .then((rewarded) {
            if (rewarded && mounted) {
              confettiOverlayKey.currentState?.play();
              showExplorationRewardToast(
                context,
                message: 'Tuned into Radio',
                points: 100,
              );
            }
          });
    });

    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (_tabController.index != _currentIndex) {
        setState(() {
          _currentIndex = _tabController.index;
        });
      }
    });

    // Reset selected country when entering the screen (Transient behavior)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(selectedCountryProvider.notifier).setCountry(null);
    });

    // Reset Global View when changing tabs
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        if (_tabController.index != 0) {
          ref.read(radioViewModeProvider.notifier).setHome();
        }
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Widget _buildTabItem(int index, Widget icon, Alignment alignment) {
    // Standard Tab Item without border (handled by AnimatedBuilder now)
    return Tab(
      child: Align(
        alignment: alignment,
        child: Container(child: icon),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 1. Providers
    final userProfile = ref.watch(userProfileProvider).value;
    final homeCountryCode = userProfile?.homeCountryCode ?? 'US'; // Default
    final selectedCountryCode =
        ref.watch(selectedCountryProvider) ?? homeCountryCode;

    // 2. View Mode & Search
    final radioViewMode = ref.watch(radioViewModeProvider);
    final isGlobalView = radioViewMode == ViewMode.global;

    // Auto-switch to Main Tab when toggling to Global Mode
    ref.listen(radioViewModeProvider, (previous, next) {
      if (next == ViewMode.global) {
        _tabController.animateTo(0);
      }
    });

    final searchQuery = ref
        .watch(globalSearchProvider)
        .toLowerCase(); // From AppBar

    // 3. Country Data
    final country = getCountryByCode(selectedCountryCode);
    final countryFlag = country?.flag ?? '';

    // 4. Handle Search State (Show Country List)
    if (searchQuery.isNotEmpty) {
      final matchingCountries = countries
          .where((c) => c.name.toLowerCase().contains(searchQuery))
          .toList();

      return Container(
        color: Colors.transparent, // Ensures background is visible
        child: ListView.builder(
          itemCount: matchingCountries.length,
          itemBuilder: (context, index) {
            final c = matchingCountries[index];
            return ListTile(
              leading: Text(c.flag, style: const TextStyle(fontSize: 24)),
              title: Text(c.name),
              onTap: () {
                // 1. Dismiss Keyboard immediately
                FocusManager.instance.primaryFocus?.unfocus();

                // 2. Select Country
                ref.read(selectedCountryProvider.notifier).setCountry(c.code);
                // 3. Switch to Home View to see it
                ref.read(radioViewModeProvider.notifier).setHome();
                // 4. Clear Search
                ref.read(globalSearchProvider.notifier).clear();
                // 5. Switch to first tab to show results
                _tabController.animateTo(0);
              },
            );
          },
        ),
      );
    }

    // 5. Handle Tabbed View (Default)
    return Scaffold(
      body: Column(
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(
                  horizontal: 26,
                ), // Align with inner SearchBar icons (Adjusted to 26px)
                child: Stack(
                  alignment: Alignment.bottomLeft,
                  children: [
                    // 1. The TabBar itself
                    TabBar(
                      dividerColor: Colors.transparent,
                      indicatorColor: Colors.transparent, // Remove underlining
                      controller: _tabController,
                      labelPadding: EdgeInsets
                          .zero, // Remove internal label padding to ensure alignment works
                      tabs: [
                        // Tab 1: Dynamic (Global Globe vs Country Flag) - Aligned Left (Logo)
                        _buildTabItem(
                          0,
                          isGlobalView
                              ? const Icon(LucideIcons.globe)
                              : Text(
                                  countryFlag,
                                  style: const TextStyle(fontSize: 24),
                                ),
                          Alignment.centerLeft,
                        ),

                        // Tab 2: Recent - Aligned Center
                        _buildTabItem(
                          1,
                          const Icon(LucideIcons.clock),
                          Alignment.center,
                        ),

                        // Tab 3: Saved - Aligned Right (Search/End)
                        _buildTabItem(
                          2,
                          const Icon(LucideIcons.heart),
                          Alignment.centerRight,
                        ),
                      ],
                    ),

                    // 2. Custom Animated Indicator
                    AnimatedBuilder(
                      animation: _tabController.animation!,
                      builder: (context, child) {
                        // Calculate Position
                        // Available width inside padding = constraints.maxWidth - 52
                        final double availableWidth = constraints.maxWidth - 52;
                        final double iconWidth =
                            24.0; // Approximation of icon width

                        // Positions (relative to the inner padding area)
                        final double pos0 = 0;
                        final double pos1 =
                            (availableWidth / 2) - (iconWidth / 2);
                        final double pos2 = availableWidth - iconWidth;

                        double currentLeft = 0;
                        final double value = _tabController.animation!.value;

                        if (value <= 1.0) {
                          // Interpolate between 0 and 1
                          currentLeft = pos0 + (pos1 - pos0) * value;
                        } else {
                          // Interpolate between 1 and 2
                          currentLeft = pos1 + (pos2 - pos1) * (value - 1.0);
                        }

                        return Positioned(
                          left: currentLeft,
                          bottom:
                              8, // Raised to be 2px below centered icon (approx)
                          child: Container(
                            width: iconWidth,
                            height: 2,
                            color: Theme.of(
                              context,
                            ).colorScheme.primary.withValues(alpha: 0.5),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              );
            },
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              // physics: const NeverScrollableScrollPhysics(), // Removed to allow swiping
              children: [
                // Tab 1 Content: Global OR Country
                isGlobalView
                    ? _StationList(
                        // If searching, use search provider. Else top stations.
                        provider: searchQuery.isNotEmpty
                            ? ref.watch(
                                globalSearchStationsProvider(searchQuery),
                              )
                            : ref.watch(topStationsProvider),
                        emptyMessage: searchQuery.isNotEmpty
                            ? 'No stations found for "$searchQuery"'
                            : 'No global stations found',
                        // Disable client-side filtering if using server-side search results?
                        // Actually, leaving it enabled doubles the safety but might hide things if casing is weird.
                        // Ideally, we skip client filter if logic in _StationList knows it's already filtered.
                        // Passing a flag 'isAlreadyFiltered' would be cleaner.
                        isAlreadyFiltered: searchQuery.isNotEmpty,
                      )
                    : _StationList(
                        provider: ref.watch(
                          stationsByCountryProvider(selectedCountryCode),
                        ),
                        emptyMessage:
                            'No stations found for $selectedCountryCode',
                      ),

                // Recent Tab
                _StationList(
                  provider: ref.watch(recentStationsProvider),
                  emptyMessage: 'No recent stations',
                ),

                // Saved Tab
                _StationList(
                  provider: ref.watch(favoriteStationsProvider),
                  emptyMessage: 'No saved stations',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StationList extends ConsumerWidget {
  final AsyncValue<List<RadioStation>> provider;
  final String emptyMessage;
  final bool isAlreadyFiltered; // [NEW]

  const _StationList({
    required this.provider,
    required this.emptyMessage,
    this.isAlreadyFiltered = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final searchQuery = ref.watch(globalSearchProvider);

    return provider.when(
      data: (stations) {
        final filteredStations = (isAlreadyFiltered || searchQuery.isEmpty)
            ? stations
            : stations.where((station) {
                final query = searchQuery.toLowerCase();
                return station.name.toLowerCase().contains(query) ||
                    station.country.toLowerCase().contains(query) ||
                    station.tags.toLowerCase().contains(query) ||
                    station.countrycode.toLowerCase().contains(query);
              }).toList();

        if (filteredStations.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.radio,
                  size: 48,
                  color: Theme.of(context).disabledColor,
                ),
                const SizedBox(height: 16),
                Text(
                  searchQuery.isNotEmpty
                      ? 'No stations match your search'
                      : emptyMessage,
                  style: TextStyle(color: Theme.of(context).hintColor),
                ),
              ],
            ),
          );
        }
        return ListView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          itemCount: filteredStations.length,
          padding: const EdgeInsets.only(
            bottom: 100,
            left: 8,
            right: 8,
          ), // Space for MiniPlayer + Horizontal Padding
          itemBuilder: (context, index) {
            final station = filteredStations[index];
            return RadioStationCard(station: station, searchQuery: searchQuery);
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, stack) => Center(child: Text('Error: $err')),
    );
  }
}

class RadioStationCard extends ConsumerWidget {
  final RadioStation station;
  final String? searchQuery;

  const RadioStationCard({super.key, required this.station, this.searchQuery});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final radioState = ref.watch(radioProvider);
    final isPlaying =
        radioState.currentStation?.stationuuid == station.stationuuid &&
        radioState.isPlaying;
    final isLoading =
        radioState.currentStation?.stationuuid == station.stationuuid &&
        radioState.isLoading;

    final favoriteStations =
        ref.watch(favoriteStationsProvider).asData?.value ?? [];
    final isFavorite = favoriteStations.any(
      (s) => s.stationuuid == station.stationuuid,
    );

    // Standardize Country Name
    // API returns full names like "The United Republic of Tanzania", we want "Tanzania"
    final countryObj = getCountryByCode(station.countrycode);
    final standardizedCountry = countryObj?.name ?? station.country;
    final flag = countryObj?.flag ?? 'ðŸŒ';

    return GlassContainer(
      color: Theme.of(
        context,
      ).scaffoldBackgroundColor, // Use scaffold bg for cards
      margin: const EdgeInsets.symmetric(
        horizontal: 0,
        vertical: 1,
      ), // Gap 2px (1 top + 1 bottom)
      padding: EdgeInsets.zero,
      child: ListTile(
        horizontalTitleGap: 8, // Reduce gap to 8px
        contentPadding: const EdgeInsets.only(
          left: 8,
          right: 6,
          top: 2,
          bottom: 2,
        ), // Right padding reduced to 6px
        leading: Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            color: Theme.of(
              context,
            ).inputDecorationTheme.fillColor, // Use theme fill
            shape: BoxShape.circle,
            image:
                (station.favicon.isNotEmpty &&
                    station.favicon.startsWith('http'))
                ? DecorationImage(
                    image: NetworkImage(station.favicon),
                    fit: BoxFit.cover,
                  )
                : null,
          ),
          child: station.favicon.isEmpty
              ? Icon(
                  Icons.radio,
                  color: Theme.of(
                    context,
                  ).iconTheme.color?.withValues(alpha: 0.5),
                )
              : null,
        ),
        title: SearchHighlightUtils.highlightText(
          station.name,
          searchQuery,
          theme
              .textTheme
              .bodyLarge, // Adjust style as needed based on ListTile defaults
          context,
        ),
        subtitle: Row(
          children: [
            Text('$flag ', style: const TextStyle(fontSize: 12)),
            Flexible(
              child: SearchHighlightUtils.highlightText(
                standardizedCountry,
                searchQuery,
                theme.textTheme.bodySmall?.copyWith(
                  color: theme.textTheme.bodySmall?.color?.withValues(
                    alpha: 0.7,
                  ),
                ),
                context,
              ),
            ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isLoading)
              SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Theme.of(context).colorScheme.secondary,
                ),
              )
            else if (isPlaying)
              // Animated bars when playing (wrapped in IconButton for exact position match)
              IconButton(
                icon: AnimatedBars(
                  color: Theme.of(context).colorScheme.secondary,
                  size: 24,
                ),
                onPressed: () => ref.read(radioProvider.notifier).stop(),
              )
            else
              IconButton(
                icon: const Icon(LucideIcons.playCircle),
                onPressed: () {
                  // [NEW] Track Play
                  final user = ref.read(authRepositoryProvider).currentUser;
                  if (user != null) {
                    ref
                        .read(pointsServiceProvider)
                        .trackExplorationReward(user.uid, 'action_radio_play');
                  }
                  ref.read(radioProvider.notifier).playStation(station);
                },
              ),
            IconButton(
              icon: Icon(
                LucideIcons.heart,
                size: 20,
                color: isFavorite
                    ? Theme.of(context).colorScheme.primary
                    : null,
              ),
              onPressed: () async {
                final user = ref.read(authStateProvider).value;
                if (user != null) {
                  // [NEW] Track Favorite
                  ref
                      .read(pointsServiceProvider)
                      .trackExplorationReward(
                        user.uid,
                        'action_radio_favorite',
                        points: 100,
                      );
                  await ref
                      .read(radioRepositoryProvider)
                      .toggleFavorite(user.uid, station);
                  ref.invalidate(favoriteStationsProvider);
                }
              },
            ),
          ],
        ),
        onTap: () {
          if (isPlaying) {
            ref.read(radioProvider.notifier).stop();
          } else {
            // [NEW] Track Play tap
            final user = ref.read(authRepositoryProvider).currentUser;
            if (user != null) {
              ref
                  .read(pointsServiceProvider)
                  .trackExplorationReward(user.uid, 'action_radio_play');
            }
            ref.read(radioProvider.notifier).playStation(station);
          }
        },
      ),
    );
  }
}

/// Animated bars widget for playing indicator
class AnimatedBars extends StatefulWidget {
  final Color color;
  final double size;

  const AnimatedBars({super.key, required this.color, this.size = 24});

  @override
  State<AnimatedBars> createState() => _AnimatedBarsState();
}

class _AnimatedBarsState extends State<AnimatedBars>
    with TickerProviderStateMixin {
  late List<AnimationController> _controllers;
  late List<Animation<double>> _animations;

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(3, (index) {
      return AnimationController(
        vsync: this,
        duration: Duration(milliseconds: 300 + (index * 100)),
      )..repeat(reverse: true);
    });

    _animations = _controllers.map((controller) {
      return Tween<double>(
        begin: 0.3,
        end: 1.0,
      ).animate(CurvedAnimation(parent: controller, curve: Curves.easeInOut));
    }).toList();
  }

  @override
  void dispose() {
    for (var controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(3, (index) {
          return AnimatedBuilder(
            animation: _animations[index],
            builder: (context, child) {
              return Container(
                width: 4,
                height: widget.size * 0.6 * _animations[index].value,
                margin: const EdgeInsets.symmetric(horizontal: 1),
                decoration: BoxDecoration(
                  color: widget.color,
                  borderRadius: BorderRadius.circular(2),
                ),
              );
            },
          );
        }),
      ),
    );
  }
}
