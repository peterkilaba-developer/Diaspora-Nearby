import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:diaspora_nearby/features/auth/repository/auth_repository.dart';
import 'package:diaspora_nearby/features/profile/repository/profile_repository.dart';
import 'package:diaspora_nearby/features/chat/repository/report_repository.dart';
import 'package:diaspora_nearby/models/profile_data.dart';
import 'package:cached_network_image/cached_network_image.dart';

class BlockedUsersScreen extends ConsumerStatefulWidget {
  const BlockedUsersScreen({super.key});

  @override
  ConsumerState<BlockedUsersScreen> createState() => _BlockedUsersScreenState();
}

class _BlockedUsersScreenState extends ConsumerState<BlockedUsersScreen> {
  @override
  Widget build(BuildContext context) {
    final userProfileAsync = ref.watch(userProfileProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Blocked Accounts'),
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: userProfileAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(child: Text('Error: $err')),
        data: (profile) {
          final blockedIds = profile?.blockedUsers ?? [];

          if (blockedIds.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(LucideIcons.shieldCheck, size: 64, color: Colors.grey.shade400),
                  const SizedBox(height: 16),
                  Text(
                    'No blocked accounts',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: Colors.grey.shade600,
                        ),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            itemCount: blockedIds.length,
            itemBuilder: (context, index) {
              final userId = blockedIds[index];
              return _BlockedUserTile(userId: userId);
            },
          );
        },
      ),
    );
  }
}

class _BlockedUserTile extends ConsumerWidget {
  final String userId;
  const _BlockedUserTile({required this.userId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // We fetch the blocked user's profile individually
    // In a real app with many blocked users, we might want a bulk fetch or cache
    final profileFutureBefore = ref.read(profileRepositoryProvider).getUserProfile(userId);
    
    // Use FutureBuilder since we don't have a specific provider family for "any user profile" set up easily without boilerplate,
    // although `profileRepositoryProvider` has `getUserProfile`.
    // Better to use FutureBuilder here for simplicity.
    
    return FutureBuilder<ProfileData?>(
      future: profileFutureBefore,
      builder: (context, snapshot) {
        if (!snapshot.hasData && snapshot.connectionState != ConnectionState.done) {
             // Loading state (skeleton or spinner)
             return const ListTile(
               leading: CircleAvatar(backgroundColor: Colors.black12),
               title: SizedBox(width: 100, height: 16, child: DecoratedBox(decoration: BoxDecoration(color: Colors.black12))),
             );
        }

        final user = snapshot.data;
        final name = user != null ? '${user.firstName} ${user.lastName}' : 'Unknown User';
        final photoUrl = user?.profileImage;

        return ListTile(
          leading: CircleAvatar(
            backgroundImage: photoUrl != null && photoUrl.isNotEmpty
                ? CachedNetworkImageProvider(photoUrl)
                : null,
            child: (photoUrl == null || photoUrl.isEmpty)
                ? const Icon(LucideIcons.user)
                : null,
          ),
          title: Text(name),
          subtitle: Text(userId, style: const TextStyle(fontSize: 10, color: Colors.grey)), // Debug/Info
          trailing: OutlinedButton(
            onPressed: () async {
               final currentUserId = ref.read(authRepositoryProvider).currentUser?.uid;
               if (currentUserId != null) {
                 await ref.read(reportRepositoryProvider).unblockUser(currentUserId, userId);
                 if (context.mounted) {
                   ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('User unblocked')));
                 }
               }
            },
            child: const Text('Unblock'),
          ),
        );
      },
    );
  }
}
