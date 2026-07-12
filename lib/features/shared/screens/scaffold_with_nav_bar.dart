import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../radio/screens/mini_player.dart';
import '../widgets/diaspora_app_bar.dart';
import 'package:diaspora_nearby/features/profile/repository/profile_repository.dart';

import 'package:diaspora_nearby/features/discovery/providers/global_search_provider.dart';
import 'package:diaspora_nearby/core/providers/view_mode_provider.dart';
import 'package:diaspora_nearby/core/services/location_update_service.dart';
import 'package:diaspora_nearby/features/auth/repository/auth_repository.dart';
import 'package:diaspora_nearby/features/dsp/services/points_service.dart';
import 'package:flutter/foundation.dart'; // [NEW] kIsWeb
import 'package:flutter_background_service/flutter_background_service.dart'; // [NEW]
import 'package:diaspora_nearby/core/services/background_location_service.dart'; // [NEW]
import 'package:diaspora_nearby/core/services/proximity_service.dart'; // [NEW]
import 'package:permission_handler/permission_handler.dart'; // [NEW]
// [NEW]
import 'package:diaspora_nearby/features/shared/widgets/confetti_overlay.dart'; // [NEW]
import 'package:diaspora_nearby/features/shared/screens/share_invite_screen.dart';
import 'package:diaspora_nearby/features/dsp/services/exploration_registry.dart';
import 'package:diaspora_nearby/features/dsp/widgets/exploration_tracker.dart';
import 'package:diaspora_nearby/features/chat/services/audio_playback_service.dart';

class ScaffoldWithNavBar extends ConsumerStatefulWidget {
  final StatefulNavigationShell navigationShell;

  const ScaffoldWithNavBar({super.key, required this.navigationShell});

  @override
  ConsumerState<ScaffoldWithNavBar> createState() => _ScaffoldWithNavBarState();
}

class _ScaffoldWithNavBarState extends ConsumerState<ScaffoldWithNavBar>
    with WidgetsBindingObserver {
  // [PERF FIX] Debounce resume actions — was running location update +
  // background service check + proximity check on EVERY resume (switching
  // apps, returning from notification, etc.). Now cooldown 5 minutes.
  DateTime? _lastResumeAction;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _updateLocation();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _triggerDailyCheckIn();
      _ensureBackgroundService();
    });
  }

  Future<void> _ensureBackgroundService() async {
    if (kIsWeb) return;
    try {
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted) return;

      final service = FlutterBackgroundService();
      final isRunning = await service.isRunning();
      // No-log: Background Service status

      if (!isRunning) {
        if (await Permission.location.isGranted) {
          // No-log: Permission granted

          await BackgroundLocationService.initializeService();

          if (await service.isRunning()) {
            // No-log: Service started
          } else {
            // No-log: Starting manually
            await service.startService();
          }
        } else {
          // No-log: Skipping
        }
      } else {
        // No-log: Already running
      }

      // [DEBUG] Trigger Foreground Proximity Check
      final user = ref.read(authRepositoryProvider).currentUser;
      if (user != null) {
        // No-log: Triggering proximity
        await ProximityService().checkAndNotify(user.uid);
      }
    } catch (e) {
      debugPrint('Error starting background service from Shell: $e');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // [PERF FIX] Debounce: only run resume actions at most once every 5 minutes.
      // Prevents hammering Firestore/GPS/network on rapid app switches.
      final now = DateTime.now();
      if (_lastResumeAction != null &&
          now.difference(_lastResumeAction!) < const Duration(minutes: 5)) {
        debugPrint('ScaffoldWithNavBar: resume debounced (< 5 min since last)');
        return;
      }
      _lastResumeAction = now;

      _updateLocation();
      _triggerDailyCheckIn();
      // Re-check background service state on resume
      _ensureBackgroundService();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      // STOP Chat Audio when backgrounded (prevents MediaCodec leakage/errors)
      try {
        ref.read(audioPlaybackServiceProvider).stopAll();
      } catch (e) {
        debugPrint('Error stopping chat audio on background: $e');
      }
    }
  }

  Future<void> _updateLocation() async {
    final user = ref.read(authRepositoryProvider).currentUser;
    if (user != null) {
      await LocationUpdateService().updateCurrentLocation(user.uid);
    }
  }

  void _triggerDailyCheckIn() {
    final user = ref.read(authRepositoryProvider).currentUser;
    if (user != null) {
      ref.read(pointsServiceProvider).trackDailyCheckIn(user.uid);
    }
  }

  // [NEW] Track navigation actions
  Future<void> _trackExploration(String actionId) async {
    final user = ref.read(authRepositoryProvider).currentUser;
    if (user != null) {
      final rewarded = await ref
          .read(pointsServiceProvider)
          .trackExplorationReward(user.uid, actionId);
      if (rewarded) {
        // Trigger Confetti
        confettiOverlayKey.currentState?.play();

        // Show Toast/SnackBar
        if (mounted) {
          showExplorationRewardToast(context);
        }
      }
    }
  }

  void _goBranch(int index) {
    // Clear search when switching tabs
    ref.read(globalSearchProvider.notifier).clear();

    // Reset view modes to default (Home) when switching tabs
    // This ensures that navigating away and back always restores the default filtered view
    ref.read(nearbyViewModeProvider.notifier).setHome();
    ref.read(eventsViewModeProvider.notifier).setHome();
    ref.read(communitiesViewModeProvider.notifier).setHome();
    ref.read(radioViewModeProvider.notifier).setHome();
    ref.read(chatsViewModeProvider.notifier).setHome();

    int branchToNavigate = index;
    if (index == 2) branchToNavigate = 4; // Events (Visual 2 -> Branch 4)
    if (index == 1) branchToNavigate = 2; // Nearby (Visual 1 -> Branch 2)
    // Chats (Visual 0 -> Branch 0) is default

    // [NEW] Track Tab Actions
    if (index == 0) _trackExploration(ExplorationAction.tabChats);
    if (index == 1) _trackExploration(ExplorationAction.tabNearby);
    if (index == 2) _trackExploration(ExplorationAction.tabEvents);

    widget.navigationShell.goBranch(
      branchToNavigate,
      initialLocation: branchToNavigate == widget.navigationShell.currentIndex,
    );
  }

  void _handleSearchChange(String query) {
    ref.read(globalSearchProvider.notifier).update(query);
  }

  void _handleSearchClear() {
    ref.read(globalSearchProvider.notifier).clear();
  }

  @override
  Widget build(BuildContext context) {
    // Optional: Sync URL search param if needed, but for now purely provider based.

    final searchQuery = ref.watch(globalSearchProvider);
    final currentIndex = widget.navigationShell.currentIndex;
    final location = GoRouterState.of(context).uri.path;

    // Detect current screen from route path
    String currentScreen;
    if (location.contains('/communities')) {
      currentScreen = 'communities';
    } else if (location.contains('/radio')) {
      currentScreen = 'radio';
    } else if (location.contains('/chats')) {
      currentScreen = 'chats';
    } else if (location.contains('/nearby')) {
      currentScreen = 'nearby';
    } else if (location.contains('/events')) {
      currentScreen = 'events';
    } else {
      // Fallback to branch index
      final screens = ['chats', 'communities', 'nearby', 'radio', 'events'];
      currentScreen = screens[currentIndex];
    }

    // Get User for home country
    final userProfile = ref.watch(userProfileProvider).value;
    final homeCountryCode = userProfile?.homeCountryCode;

    // View Mode Logic localized per screen
    bool isGlobalView = false;
    VoidCallback? onToggleView;

    if (currentScreen == 'nearby') {
      final nearbyMode = ref.watch(nearbyViewModeProvider);
      isGlobalView = nearbyMode == ViewMode.global;
      onToggleView = () {
        _trackExploration(ExplorationAction.toggleViewNearby); // [NEW]
        ref.read(nearbyViewModeProvider.notifier).toggleView();
      };
    } else if (currentScreen == 'events') {
      final eventsMode = ref.watch(eventsViewModeProvider);
      isGlobalView = eventsMode == ViewMode.global;
      onToggleView = () {
        _trackExploration(ExplorationAction.toggleViewEvents); // [NEW]
        ref.read(eventsViewModeProvider.notifier).toggleView();
      };
    } else if (currentScreen == 'communities') {
      final communitiesMode = ref.watch(communitiesViewModeProvider);
      isGlobalView = communitiesMode == ViewMode.global;
      onToggleView = () {
        _trackExploration(ExplorationAction.toggleViewCommunities); // [NEW]
        ref.read(communitiesViewModeProvider.notifier).toggleView();
      };
    } else if (currentScreen == 'radio') {
      final radioMode = ref.watch(radioViewModeProvider);
      isGlobalView = radioMode == ViewMode.global;
      onToggleView = () {
        _trackExploration(ExplorationAction.toggleViewRadio); // [NEW]
        ref.read(radioViewModeProvider.notifier).toggleView();
      };
    } else if (currentScreen == 'chats') {
      final chatsMode = ref.watch(chatsViewModeProvider);
      isGlobalView = chatsMode == ViewMode.global;
      onToggleView = () {
        _trackExploration(ExplorationAction.toggleViewChats); // [NEW]
        ref.read(chatsViewModeProvider.notifier).toggleView();
      };
    }

    return Scaffold(
      resizeToAvoidBottomInset: false, // Prevent nav bar from moving up
      appBar: DiasporaAppBar(
        currentScreen: currentScreen,
        searchQuery: searchQuery,
        onSearchChange: _handleSearchChange,
        onSearchClear: _handleSearchClear,
        homeCountryCode: homeCountryCode,
        isGlobalView: isGlobalView,
        onToggleView: onToggleView,
        showSearchField: true,
      ),
      body: widget.navigationShell,
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          _trackExploration(ExplorationAction.fabInvite); // [NEW]
          Navigator.of(context).push(
            MaterialPageRoute(builder: (context) => const ShareInviteScreen()),
          );
        },
        shape: const CircleBorder(),
        // Uses theme's floatingActionButtonTheme (accent color)
        child: const Icon(LucideIcons.share2, color: Colors.white),
      ),
      bottomNavigationBar: Builder(
        builder: (context) {
          // Determine visual index
          // 0 -> 0 (Chats)
          // 1 -> Unselected (Communities)
          // 2 -> 1 (Nearby)
          // 3 -> Unselected (Radio)
          // 4 -> 2 (Events)

          final isUnselected = currentIndex == 1 || currentIndex == 3;
          final visualIndex = isUnselected
              ? 0 // Dummy index, we will hide highlight via Theme
              : (currentIndex == 4 ? 2 : (currentIndex == 2 ? 1 : 0));

          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (currentScreen == 'radio') const MiniPlayer(),
              Theme(
                data: Theme.of(context).copyWith(
                  navigationBarTheme: isUnselected
                      ? NavigationBarThemeData(
                          indicatorColor: Colors.transparent, // Hide pill
                          iconTheme: validIconTheme(
                            context,
                            false,
                          ), // Force unselected icons
                          labelTextStyle: validLabelStyle(
                            context,
                            false,
                          ), // Force unselected text
                        )
                      : null,
                ),
                child: NavigationBar(
                  selectedIndex: visualIndex,
                  onDestinationSelected: _goBranch,
                  destinations: const [
                    NavigationDestination(
                      icon: Icon(LucideIcons.messageCircle),
                      label: 'Chats',
                    ),
                    NavigationDestination(
                      icon: Icon(LucideIcons.locateFixed),
                      label: 'Nearby',
                    ),
                    NavigationDestination(
                      icon: Icon(LucideIcons.calendar),
                      label: 'Events',
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // Helpers to force unselected state
  WidgetStateProperty<IconThemeData?> validIconTheme(
    BuildContext context,
    bool selected,
  ) {
    return WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.selected)) {
        // Return unselected style even if selected
        return IconThemeData(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          size: 24,
        );
      }
      return IconThemeData(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        size: 24,
      );
    });
  }

  WidgetStateProperty<TextStyle?> validLabelStyle(
    BuildContext context,
    bool selected,
  ) {
    return WidgetStateProperty.resolveWith((states) {
      return TextStyle(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        fontWeight: FontWeight.w500,
        fontSize: 12,
      );
    });
  }
}
