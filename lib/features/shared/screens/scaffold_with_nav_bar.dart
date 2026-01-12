import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../radio/screens/mini_player.dart';
import '../widgets/diaspora_app_bar.dart';
import 'package:diaspora_nearby/features/profile/repository/profile_repository.dart';
import 'package:diaspora_nearby/data/countries.dart' as country_data;
import 'package:diaspora_nearby/providers/global_search_provider.dart';
import 'package:diaspora_nearby/providers/view_mode_provider.dart';
import 'package:diaspora_nearby/services/sharing_service.dart';
import 'package:diaspora_nearby/services/location_update_service.dart';
import 'package:diaspora_nearby/features/auth/repository/auth_repository.dart';
import 'package:diaspora_nearby/features/dsp/services/points_service.dart';
import 'package:flutter/foundation.dart'; // [NEW] kIsWeb
import 'package:flutter_background_service/flutter_background_service.dart'; // [NEW]
import 'package:diaspora_nearby/services/background_location_service.dart'; // [NEW]
import 'package:diaspora_nearby/services/proximity_service.dart'; // [NEW]
import 'package:permission_handler/permission_handler.dart'; // [NEW]
import 'package:firebase_auth/firebase_auth.dart'; // [NEW]
import 'package:diaspora_nearby/features/shared/widgets/confetti_overlay.dart'; // [NEW]
import 'package:diaspora_nearby/features/shared/screens/share_invite_screen.dart';

class ScaffoldWithNavBar extends ConsumerStatefulWidget {
  final StatefulNavigationShell navigationShell;

  const ScaffoldWithNavBar({
    super.key,
    required this.navigationShell,
  });

  @override
  ConsumerState<ScaffoldWithNavBar> createState() => _ScaffoldWithNavBarState();
}

class _ScaffoldWithNavBarState extends ConsumerState<ScaffoldWithNavBar> with WidgetsBindingObserver {
  
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _updateLocation();
    _trackDailyPoints();
    WidgetsBinding.instance.addPostFrameCallback((_) {
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
       print('Shell: Background Service status: isRunning=$isRunning'); 

       if (!isRunning) {
          if (await Permission.location.isGranted) {
            print('Shell: Permission granted. Initializing and starting service...');

            await BackgroundLocationService.initializeService();

            if (await service.isRunning()) {
              print('Shell: Service started successfully during initialization.'); 
            } else {
              print('Shell: Starting service manually...'); 
              await service.startService();
            }
          } else {
            print('Shell: Skipping background service start: Permission not granted yet.'); 
          }
       } else {
         print('Shell: Service is already running.'); 
       }
       
       // [DEBUG] Trigger Foreground Proximity Check
       final user = ref.read(authRepositoryProvider).currentUser;
       if (user != null) {
         print('Shell: Triggering FOREGROUND Proximity Check...');
         await ProximityService().checkAndNotify(user.uid);
       }

     } catch (e) {
       print('Error starting background service from Shell: $e'); 
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
      _updateLocation();
      _trackDailyPoints(); // Check again on resume (e.g. new day)
      // Re-check background service state on resume
      _ensureBackgroundService();
    }
  }

  Future<void> _updateLocation() async {
    final user = ref.read(authRepositoryProvider).currentUser;
    if (user != null) {
      await LocationUpdateService().updateCurrentLocation(user.uid);
    }
  }

  Future<void> _trackDailyPoints() async {
    final user = ref.read(authRepositoryProvider).currentUser;
    if (user != null) {
      await ref.read(pointsServiceProvider).trackDailyOpen(user.uid);
    }
  }

  // [NEW] Track navigation actions
  Future<void> _trackExploration(String actionId) async {
    final user = ref.read(authRepositoryProvider).currentUser;
    if (user != null) {
      final rewarded = await ref.read(pointsServiceProvider).trackExplorationReward(user.uid, actionId);
      if (rewarded) {
        // Trigger Confetti
        confettiOverlayKey.currentState?.play();
        
        // Show Toast/SnackBar (Use a safe context or scaffold messenger)
        if (mounted) {
           ScaffoldMessenger.of(context).showSnackBar(
             const SnackBar(
               content: Text('🎉 +1 DSP Earned for exploring!'),
               backgroundColor: Colors.green,
               duration: Duration(seconds: 2),
               behavior: SnackBarBehavior.floating,
             ),
           );
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
    if (index == 0) _trackExploration('explore_tab_chats');
    if (index == 1) _trackExploration('explore_tab_nearby');
    if (index == 2) _trackExploration('explore_tab_events');

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
    final homeCountry = homeCountryCode != null
        ? country_data.getCountryByCode(homeCountryCode)?.name
        : null;

    // View Mode Logic localized per screen
    bool isGlobalView = false;
    VoidCallback? onToggleView;

    if (currentScreen == 'nearby') {
      final nearbyMode = ref.watch(nearbyViewModeProvider);
      isGlobalView = nearbyMode == ViewMode.global;
      onToggleView = () {
          _trackExploration('action_toggle_view_nearby'); // [NEW]
          ref.read(nearbyViewModeProvider.notifier).toggleView();
      };
    } else if (currentScreen == 'events') {
      final eventsMode = ref.watch(eventsViewModeProvider);
      isGlobalView = eventsMode == ViewMode.global;
      onToggleView = () {
         _trackExploration('action_toggle_view_events'); // [NEW]
         ref.read(eventsViewModeProvider.notifier).toggleView();
      };
    } else if (currentScreen == 'communities') {
       final communitiesMode = ref.watch(communitiesViewModeProvider);
       isGlobalView = communitiesMode == ViewMode.global;
       onToggleView = () {
          _trackExploration('action_toggle_view_communities'); // [NEW]
          ref.read(communitiesViewModeProvider.notifier).toggleView();
       };
    } else if (currentScreen == 'radio') {
       final radioMode = ref.watch(radioViewModeProvider);
       isGlobalView = radioMode == ViewMode.global;
       onToggleView = () {
          _trackExploration('action_toggle_view_radio'); // [NEW]
          ref.read(radioViewModeProvider.notifier).toggleView();
       };
    } else if (currentScreen == 'chats') {
       final chatsMode = ref.watch(chatsViewModeProvider);
       isGlobalView = chatsMode == ViewMode.global;
       onToggleView = () {
          _trackExploration('action_toggle_view_chats'); // [NEW]
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
          _trackExploration('action_invite_friends'); // [NEW]
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
              if (currentScreen == 'radio')
                const MiniPlayer(),
              Theme(
                data: Theme.of(context).copyWith(
                   navigationBarTheme: isUnselected ? NavigationBarThemeData(
                     indicatorColor: Colors.transparent, // Hide pill
                     iconTheme: validIconTheme(context, false), // Force unselected icons
                     labelTextStyle: validLabelStyle(context, false), // Force unselected text
                   ) : null
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
        }
      ),
    );
  }

  // Helpers to force unselected state
  MaterialStateProperty<IconThemeData?> validIconTheme(BuildContext context, bool selected) {
     return MaterialStateProperty.resolveWith((states) {
        if (states.contains(MaterialState.selected)) {
           // Return unselected style even if selected
           return IconThemeData(
             color: Theme.of(context).colorScheme.onSurfaceVariant,
             size: 24
           );
        }
        return IconThemeData(
             color: Theme.of(context).colorScheme.onSurfaceVariant,
             size: 24
        );
     });
  }
  
  MaterialStateProperty<TextStyle?> validLabelStyle(BuildContext context, bool selected) {
     return MaterialStateProperty.resolveWith((states) {
        return TextStyle(
           color: Theme.of(context).colorScheme.onSurfaceVariant,
           fontWeight: FontWeight.w500,
           fontSize: 12
        );
     });
  }
}


