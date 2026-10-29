import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:diaspora_nearby/features/auth/repository/auth_repository.dart';
import 'package:diaspora_nearby/features/profile/repository/profile_repository.dart';
import 'package:diaspora_nearby/features/chat/repository/report_repository.dart';
import 'package:diaspora_nearby/features/profile/models/profile_data.dart';
import 'package:diaspora_nearby/theme/app_theme.dart';
import 'package:cached_network_image/cached_network_image.dart';

class BlockedUsersScreen extends ConsumerStatefulWidget {
  const BlockedUsersScreen({super.key});

  @override
  ConsumerState<BlockedUsersScreen> createState() => _BlockedUsersScreenState();
}

class _BlockedUsersScreenState extends ConsumerState<BlockedUsersScreen> {
  final Set<String> _optimisticallyUnblockedIds = {};

  @override
  void initState() {
    super.initState();
    final uid = ref.read(authRepositoryProvider).currentUser?.uid;
    if (uid != null) {
      final profile =
          ref.read(userProfileProvider).value ??
          ref.read(profileRepositoryProvider).getCachedProfile(uid);
      final blocked = profile?.blockedUsers ?? const [];
      if (blocked.isNotEmpty) {
        unawaited(ref.read(profileRepositoryProvider).getProfiles(blocked));
      }
    }
  }

  void _handleUnblock(ProfileData? currentProfile, String targetUserId) {
    final currentUserId = ref.read(authRepositoryProvider).currentUser?.uid;
    if (currentUserId == null) return;

    setState(() {
      _optimisticallyUnblockedIds.add(targetUserId);
    });

    if (currentProfile != null) {
      final updatedBlocked = List<String>.from(
        currentProfile.blockedUsers ?? const [],
      )..remove(targetUserId);
      final updatedProfile = currentProfile.copyWith(
        blockedUsers: updatedBlocked,
      );
      ref.read(userProfileProvider.notifier).updateProfile(updatedProfile);
      ref
          .read(profileRepositoryProvider)
          .cacheProfile(currentUserId, updatedProfile);
    }

    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('User unblocked')));
    }

    unawaited(
      ref
          .read(reportRepositoryProvider)
          .unblockUser(currentUserId, targetUserId)
          .catchError((Object e) {
            if (mounted) {
              setState(() {
                _optimisticallyUnblockedIds.remove(targetUserId);
              });
              if (currentProfile != null) {
                ref
                    .read(userProfileProvider.notifier)
                    .updateProfile(currentProfile);
                ref
                    .read(profileRepositoryProvider)
                    .cacheProfile(currentUserId, currentProfile);
              }
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Error unblocking user: $e')),
              );
            }
          }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = ref.watch(authRepositoryProvider).currentUser?.uid;
    final cachedProfile = currentUserId != null
        ? ref.read(profileRepositoryProvider).getCachedProfile(currentUserId)
        : null;
    final userProfileAsync = ref.watch(userProfileProvider);
    final profile = userProfileAsync.value ?? cachedProfile;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Blocked Accounts'),
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: profile == null && userProfileAsync.isLoading
          ? const Center(child: CircularProgressIndicator())
          : Builder(
              builder: (context) {
                final blockedIds = (profile?.blockedUsers ?? const <String>[])
                    .where((id) => !_optimisticallyUnblockedIds.contains(id))
                    .toList();

                if (blockedIds.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          LucideIcons.shieldCheck,
                          size: 64,
                          color: Colors.grey.shade400,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No blocked accounts',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  padding: EdgeInsets.only(
                    bottom: MediaQuery.of(context).padding.bottom + 16,
                  ),
                  itemCount: blockedIds.length,
                  itemBuilder: (context, index) {
                    final userId = blockedIds[index];
                    return _BlockedUserTile(
                      userId: userId,
                      onUnblock: () => _handleUnblock(profile, userId),
                    );
                  },
                );
              },
            ),
    );
  }
}

class _BlockedUserTile extends ConsumerStatefulWidget {
  final String userId;
  final VoidCallback onUnblock;
  const _BlockedUserTile({required this.userId, required this.onUnblock});

  @override
  ConsumerState<_BlockedUserTile> createState() => _BlockedUserTileState();
}

class _BlockedUserTileState extends ConsumerState<_BlockedUserTile> {
  late Future<ProfileData?> _profileFuture;

  @override
  void initState() {
    super.initState();
    _profileFuture = ref
        .read(profileRepositoryProvider)
        .getUserProfile(widget.userId);
  }

  @override
  void didUpdateWidget(covariant _BlockedUserTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userId != widget.userId) {
      _profileFuture = ref
          .read(profileRepositoryProvider)
          .getUserProfile(widget.userId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cachedUser = ref
        .read(profileRepositoryProvider)
        .getCachedProfile(widget.userId);

    return FutureBuilder<ProfileData?>(
      initialData: cachedUser,
      future: _profileFuture,
      builder: (context, snapshot) {
        final user = snapshot.data ?? cachedUser;
        if (user == null && snapshot.connectionState != ConnectionState.done) {
          return const ListTile(
            leading: CircleAvatar(backgroundColor: Colors.black12),
            title: SizedBox(
              width: 100,
              height: 16,
              child: DecoratedBox(
                decoration: BoxDecoration(color: Colors.black12),
              ),
            ),
          );
        }

        final name = user != null
            ? '${user.firstName} ${user.lastName}'
            : 'Unknown User';
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
          subtitle: Text(
            widget.userId,
            style: const TextStyle(fontSize: 10, color: Colors.grey),
          ),
          trailing: TextButton(
            style: TextButton.styleFrom(
              backgroundColor: AppTheme.elevationColor(context, 2),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: widget.onUnblock,
            child: const Text('Unblock'),
          ),
        );
      },
    );
  }
}
