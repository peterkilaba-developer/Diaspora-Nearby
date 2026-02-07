import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:diaspora_nearby/features/home/repository/home_repository.dart';
import 'package:diaspora_nearby/features/profile/models/profile_data.dart';
import 'package:diaspora_nearby/features/shared/widgets/user_card.dart';
import 'package:diaspora_nearby/core/providers/view_mode_provider.dart';
import 'package:diaspora_nearby/features/discovery/providers/global_search_provider.dart';
import 'package:diaspora_nearby/features/profile/repository/profile_repository.dart'; // [NEW] For userProfileProvider
import 'package:lucide_icons/lucide_icons.dart'; // [NEW] For icons
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:diaspora_nearby/core/services/background_location_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:diaspora_nearby/core/services/proximity_service.dart';
import 'package:diaspora_nearby/theme/app_theme.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ensureBackgroundService();
    });
  }

  Future<void> _ensureBackgroundService() async {
    if (kIsWeb) return;
    try {
      // [DEBUG] Reduced delay
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted) return;

      final service = FlutterBackgroundService();
      final isRunning = await service.isRunning();
      print(
        'HomeScreen: Background Service status: isRunning=$isRunning',
      ); // Changed to print

      if (!isRunning) {
        if (await Permission.location.isGranted) {
          print(
            'HomeScreen: Permission granted. Initializing and starting service...',
          ); // Changed to print

          await BackgroundLocationService.initializeService();

          if (await service.isRunning()) {
            print(
              'HomeScreen: Service started successfully during initialization.',
            ); // Changed to print
          } else {
            print(
              'HomeScreen: Starting service manually...',
            ); // Changed to print
            await service.startService();
          }
        } else {
          print(
            'HomeScreen: Skipping background service start: Permission not granted yet.',
          ); // Changed to print
        }
      } else {
        print('HomeScreen: Service is already running.'); // Changed to print
      }

      // [DEBUG] Trigger Foreground Proximity Check to verify logic works
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        print('HomeScreen: Triggering FOREGROUND Proximity Check...');
        await ProximityService().checkAndNotify(user.uid);
      }
    } catch (e) {
      print(
        'Error starting background service from Home: $e',
      ); // Changed to print
    }
  }

  @override
  Widget build(BuildContext context) {
    final homeRepo = ref.watch(homeRepositoryProvider);
    final viewMode = ref.watch(nearbyViewModeProvider);
    final searchQuery = ref.watch(globalSearchProvider);
    final userProfileAsync = ref.watch(userProfileProvider);

    final isGlobal = viewMode == ViewMode.global;

    return FutureBuilder<List<ProfileData>>(
      key: ValueKey(
        '${isGlobal}_$searchQuery',
      ), // Force rebuild on search or view change
      future: searchQuery.isNotEmpty
          ? homeRepo.searchUsers(searchQuery)
          : homeRepo.getNearbyUsers(isGlobal: isGlobal),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        final users = snapshot.data ?? [];
        if (users.isEmpty) {
          if (isGlobal) {
            return const Center(child: Text('No global users found.'));
          }

          // Local empty state
          // Retrieve home country for message
          final homeCountry =
              userProfileAsync.value?.homeCountry ?? 'your home country';
          // Default range logic (matches backend default usually, e.g. 5000km or similar, but user prompt says "999 Mile/ 1398 km")
          // We'll use the user's requested specific text for now.
          const rangeText = '999 Mile/ 1398 km';

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
                      ref.read(nearbyViewModeProvider.notifier).state =
                          ViewMode.global;
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
              onChatTap: () => context.push('/chat/direct/${users[index].uid}'),
            );
          },
        );
      },
    );
  }
}
