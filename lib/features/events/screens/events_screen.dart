import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:lucide_icons/lucide_icons.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';

import 'package:diaspora_nearby/features/auth/repository/auth_repository.dart';
import 'package:diaspora_nearby/features/events/repository/event_repository.dart';
import 'package:diaspora_nearby/features/profile/repository/profile_repository.dart';
import 'package:diaspora_nearby/features/events/models/event_data.dart';
import 'package:diaspora_nearby/features/discovery/providers/global_search_provider.dart';
import 'package:diaspora_nearby/core/providers/view_mode_provider.dart';
import 'package:diaspora_nearby/features/events/widgets/event_card.dart';
import 'package:diaspora_nearby/features/dsp/services/points_service.dart'; // [NEW]
import 'package:diaspora_nearby/features/dsp/widgets/exploration_tracker.dart'; // [NEW]


class EventsScreen extends ConsumerStatefulWidget {
  const EventsScreen({super.key});

  @override
  ConsumerState<EventsScreen> createState() => _EventsScreenState();
}

class _EventsScreenState extends ConsumerState<EventsScreen> {
  // State
  Position? _currentPosition;

  @override
  void initState() {
    super.initState();
    _getCurrentLocation();
  }

  Future<void> _getCurrentLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        return;
      }

      final position = await Geolocator.getCurrentPosition();
      if (mounted) {
        setState(() {
          _currentPosition = position;
        });
      }
    } catch (e) {
      // Ignored
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Auth & User Profile
    final user = ref.watch(authStateProvider).value;
    final userProfileAsync = ref.watch(userProfileProvider);
    final userProfile = userProfileAsync.value;

    final eventRepo = ref.watch(eventRepositoryProvider);
    final searchQuery = ref.watch(globalSearchProvider);

    // View Mode from localized provider
    final viewMode = ref.watch(eventsViewModeProvider);
    final isGlobalViewMode = viewMode == ViewMode.global;

    // User Home Country Code
    final userHomeCountryCode = userProfile?.homeCountryCode;

    // Repo Logic:
    // 1. Home View: isGlobal=false, homeCountryCode=userHomeCountryCode
    // 2. Global View: isGlobal=true, homeCountryCode=null (Fetch all, filter locally to EXCLUDE home)

    final bool repoIsGlobal = isGlobalViewMode;
    final String? repoCountryCode = isGlobalViewMode
        ? null
        : userHomeCountryCode;

    if (user == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,

      // AppBar is handled by ScaffoldWithNavBar, so we just build the body.
      // IF this screen is nested in ScaffoldWithNavBar, it provides the AppBar logic.
      // However, if we need custom AppBar behavior inside the tab, we might need nested Navigator or just body content.
      // Based on `ScaffoldWithNavBar` analysis, it has a global AppBar that reflects `currentScreen == 'events'`.
      // It sets `showSearchField: true` for Chats, etc.
      // User requested "app bar with search bar" for Events too.
      // In `ScaffoldWithNavBar`, `showSearchField: currentScreen != 'events'` was present in previous code? No, let's verify.
      // In `ScaffoldWithNavBar.dart` viewed earlier: `showSearchField: currentScreen != 'events'` at line 127.
      // This disables search for Events screen in the MAIN app bar.
      // This means we might need to rely on the MAIN app bar update to enable search, OR build our own here.
      // But `ScaffoldWithNavBar` wraps this. If we build another Scaffold/AppBar here, we get double AppBars.
      // Ideally, we should update `ScaffoldWithNavBar` to ENABLE search for Events, and handle logic here.
      // But we can't easily change `ScaffoldWithNavBar` from here.
      // ACTUALLY, the user said "Remove location and all categories tabs container and replace with app bar with search bar".
      // If `ScaffoldWithNavBar` disables the search bar for 'events', we should probably enable it there.
      // But let's assume `ScaffoldWithNavBar` controls the top area.
      // Wait, if `ScaffoldWithNavBar` has `showSearchField: currentScreen != 'events'`, then currently there is NO search bar for events.
      // I WILL NEED TO UPDATE `ScaffoldWithNavBar` to remove that restriction.
      // For now, I will build the body assuming the search term comes from `globalSearchProvider`.
      body: StreamBuilder<List<Event>>(
        stream: eventRepo.getEvents(
          isGlobal: repoIsGlobal,
          homeCountryCode: repoCountryCode,
          currentUserId: user.uid,
          userCommunityMemberships: userProfile?.communityMemberships ?? [],
        ),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          final allEvents = snapshot.data ?? [];

          // Filter Logic
          final filteredEvents = allEvents.where((event) {
            // 1. View Mode Strict Filtering
            if (isGlobalViewMode) {
              // Global View: Show all events (unfiltered)
              // Previously we excluded local events, but user wants unfiltered.
            } else {
              // Home View: is already filtered by Repo to only match homeCountryCode.
              // Double check just in case repo returns stray data?
              if (userHomeCountryCode != null &&
                  event.homeCountryCode != userHomeCountryCode) {
                return false;
              }
            }

            // 2. Search Filter
            final query = searchQuery.toLowerCase();
            if (query.isEmpty) return true;

            return event.title.toLowerCase().contains(query) ||
                event.description.toLowerCase().contains(query) ||
                event.location.toLowerCase().contains(query);
          }).toList();

          if (filteredEvents.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    LucideIcons.calendar,
                    size: 64,
                    color: Theme.of(context).disabledColor,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    searchQuery.isNotEmpty
                        ? 'No events match "$searchQuery".'
                        : (isGlobalViewMode
                              ? 'No global community events found.'
                              : (userHomeCountryCode != null
                                    ? 'No community events found for $userHomeCountryCode.'
                                    : 'No local community events found.')),
                    style: TextStyle(color: Theme.of(context).hintColor),
                  ),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () async {
              setState(() {});
            },
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
              itemCount: filteredEvents.length,
              separatorBuilder: (_, __) => const SizedBox(height: 16),
              itemBuilder: (context, index) {
                final event = filteredEvents[index];
                final isAttending =
                    event.attendees?.contains(user.uid) ?? false;
                final isInterested =
                    event.interested?.contains(user.uid) ?? false;
                final isCreator = event.creatorId == user.uid;

                return EventCard(
                  event: event,
                  isAttending: isAttending,
                  isInterested: isInterested,
                  isCreator: isCreator,
                  userLocation: _currentPosition,
                  searchQuery: searchQuery, // Pass the search query
                  onEditTap: () {
                    context.push('/events/edit/${event.id}', extra: event);
                  },
                  onInterestToggle: () async {
                    try {
                      final shouldAdd = !isInterested;
                      await eventRepo.toggleInterest(
                        event.id,
                        user.uid,
                        shouldAdd,
                      );

                      // [NEW] Track Interest
                      if (shouldAdd) {
                        // Only reward for showing interest, not removing
                        ref
                            .read(pointsServiceProvider)
                            .trackExplorationReward(
                              user.uid,
                              'action_event_interest',
                            )
                            .then((rewarded) {
                          if (rewarded && mounted) {
                            showExplorationRewardToast(context, message: 'Interested in Event');
                          }
                        });
                      }

                      setState(() {});
                    } catch (e) {
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(SnackBar(content: Text('Error: $e')));
                    }
                  },
                );
              },
            ),
          );
        },
      ),
    );
  }
}
