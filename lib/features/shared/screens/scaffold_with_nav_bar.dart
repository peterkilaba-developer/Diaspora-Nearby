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

class ScaffoldWithNavBar extends ConsumerStatefulWidget {
  final StatefulNavigationShell navigationShell;

  const ScaffoldWithNavBar({
    super.key,
    required this.navigationShell,
  });

  @override
  ConsumerState<ScaffoldWithNavBar> createState() => _ScaffoldWithNavBarState();
}

class _ScaffoldWithNavBarState extends ConsumerState<ScaffoldWithNavBar> {

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
      onToggleView = () => ref.read(nearbyViewModeProvider.notifier).toggleView();
    } else if (currentScreen == 'events') {
      final eventsMode = ref.watch(eventsViewModeProvider);
      isGlobalView = eventsMode == ViewMode.global;
      onToggleView = () => ref.read(eventsViewModeProvider.notifier).toggleView();
    } else if (currentScreen == 'communities') {
       final communitiesMode = ref.watch(communitiesViewModeProvider);
       isGlobalView = communitiesMode == ViewMode.global;
       onToggleView = () => ref.read(communitiesViewModeProvider.notifier).toggleView();
    } else if (currentScreen == 'radio') {
       final radioMode = ref.watch(radioViewModeProvider);
       isGlobalView = radioMode == ViewMode.global;
       onToggleView = () => ref.read(radioViewModeProvider.notifier).toggleView();
    } else if (currentScreen == 'chats') {
       final chatsMode = ref.watch(chatsViewModeProvider);
       isGlobalView = chatsMode == ViewMode.global;
       onToggleView = () => ref.read(chatsViewModeProvider.notifier).toggleView();
    }

    return Scaffold(
      resizeToAvoidBottomInset: false, // Prevent nav bar from moving up
      appBar: DiasporaAppBar(
        currentScreen: currentScreen,
        searchQuery: searchQuery,
        onSearchChange: _handleSearchChange,
        onSearchClear: _handleSearchClear,
        homeCountry: homeCountry,
        isGlobalView: isGlobalView,
        onToggleView: onToggleView,
        showSearchField: true,
      ),
      body: widget.navigationShell,
      floatingActionButton: FloatingActionButton(
        onPressed: () {
         SharingService.instance.shareToWhatsApp("Join me on Diaspora Nearby! Check it out: https://diasporanearby.com");
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


