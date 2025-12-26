import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:diaspora_nearby/features/shared/widgets/diaspora_app_bar.dart';
import 'package:diaspora_nearby/features/home/repository/home_repository.dart';
import 'package:diaspora_nearby/models/profile_data.dart';
import 'package:diaspora_nearby/features/shared/widgets/user_card.dart';
import 'package:diaspora_nearby/providers/view_mode_provider.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {


  @override
  Widget build(BuildContext context) {
    final homeRepo = ref.watch(homeRepositoryProvider);
    final viewMode = ref.watch(nearbyViewModeProvider);
    final isGlobal = viewMode == ViewMode.global;

    // Use Ref to check view mode directly from provider, as ScaffoldWithNavBar controls the toggle
    // However, if we need local state for non-global things, we can keep stateful
    // But for the View Mode, we should just watch the provider since shell updates it
    
    // Note: Since ScaffoldWithNavBar handles the Scaffold and AppBar, we just return the body content here.
    return FutureBuilder<List<ProfileData>>(
        future: homeRepo.getNearbyUsers(isGlobal: isGlobal),
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
              child: Text(isGlobal 
                 ? 'No users found globally.' 
                 : 'No users from your home country found nearby.'),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            itemCount: users.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              return UserCardView(
                user: users[index],
                onNameTap: () => context.push('/profile/${users[index].uid}'),
                onChatTap: () => context.push('/chat/direct/${users[index].uid}'),
              );
            },
          );
        },
    );
  }
}

