import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:diaspora_nearby/core/data/countries.dart'; // [NEW] For getCountryByCode
import 'package:go_router/go_router.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:diaspora_nearby/features/community/models/community_data.dart';
import 'package:diaspora_nearby/features/chat/utils/community_chat_utils.dart';
import 'package:diaspora_nearby/features/profile/models/profile_data.dart';
import 'package:diaspora_nearby/features/shared/widgets/user_card.dart';
import 'package:diaspora_nearby/features/auth/repository/auth_repository.dart';
import 'package:diaspora_nearby/features/profile/repository/profile_repository.dart';
import 'package:diaspora_nearby/core/utils/location_utils.dart';
import 'package:diaspora_nearby/features/dsp/services/points_service.dart';
import 'package:diaspora_nearby/features/shared/widgets/confetti_overlay.dart';
// [NEW]
import 'package:diaspora_nearby/features/dsp/widgets/exploration_tracker.dart'; // [NEW]
import 'package:diaspora_nearby/features/community/widgets/share_community_dialog.dart'; // [NEW]

class CommunityMembersScreen extends ConsumerStatefulWidget {
  final String communityId;
  final Community community;

  const CommunityMembersScreen({
    super.key,
    required this.communityId,
    required this.community,
  });

  @override
  ConsumerState<CommunityMembersScreen> createState() =>
      _CommunityMembersScreenState();
}

class _CommunityMembersScreenState
    extends ConsumerState<CommunityMembersScreen> {
  @override
  void initState() {
    super.initState();
    _trackExploration(); // [NEW]
  }

  // [NEW] Track reward
  Future<void> _trackExploration() async {
    final user = ref.read(authRepositoryProvider).currentUser;
    if (user != null) {
      final rewarded = await ref
          .read(pointsServiceProvider)
          .trackExplorationReward(user.uid, 'open_my_community');
      if (rewarded && mounted) {
        confettiOverlayKey.currentState?.play();
        showExplorationRewardToast(
          context,
          message: 'Visited your community',
          points: 100,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(LucideIcons.x, size: 22),
          onPressed: () => context.pop(),
        ),
        titleSpacing: 0,
        title: Row(
          children: [
            CommunityChatUtils.getCommunityAvatar(
              context: context,
              type: widget.community.type,
              locationType: widget.community.locationType,
              homeCountryCode: widget.community.homeCountryCode,
              hostCountryCode: widget.community.hostCountryCode,
              communityId: widget.community.id,
              profileImage: widget.community.profileImage,
              size: 32,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                widget.community.name,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.share2, size: 20),
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) =>
                    ShareCommunityDialog(community: widget.community),
              );
            },
          ),
          const SizedBox(width: 8),
        ],
      ),

      body: SafeArea(
        child: FutureBuilder<List<ProfileData>>(
          // Fetch members from Firestore
          future: _fetchMembers(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(child: Text('Error: ${snapshot.error}'));
            }

            final members = snapshot.data ?? [];
            final currentUser = ref.watch(authRepositoryProvider).currentUser;

            // [FIX] Check if current user is actually a member of this community
            final currentProfile = ref.watch(userProfileProvider).value;
            final isMember =
                currentProfile?.communityMemberships?.contains(
                  widget.communityId,
                ) ??
                false;

            // Consolidate "Empty" and "Single self member" into First Member state
            // Only show "first member" celebration if user IS a member
            final isFirstMember =
                isMember &&
                (members.isEmpty ||
                    (members.length == 1 &&
                        members.first.uid == currentUser?.uid));

            // [FIX] If NOT a member and no members found, show neutral empty state
            final isEmptyForNonMember = !isMember && members.isEmpty;

            if (isEmptyForNonMember) {
              return Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(32.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest
                              .withValues(alpha: 0.5),
                          shape: BoxShape.rectangle,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Icon(
                          LucideIcons.users,
                          size: 48,
                          color: Theme.of(context).hintColor,
                        ),
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        'No Members Yet',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'This community doesn\'t have any members yet.\nKnow someone who belongs here? Invite them!',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.grey,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 32),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: () {
                            showDialog(
                              context: context,
                              builder: (context) => ShareCommunityDialog(
                                community: widget.community,
                              ),
                            );
                          },
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 14,
                            ),
                          ),
                          icon: const Icon(LucideIcons.share2),
                          label: const Text('Invite Friends'),
                        ),
                      ),
                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              );
            }

            if (isFirstMember) {
              // Derive contextual names
              final homeCountryName =
                  getCountryByCode(
                    widget.community.homeCountryCode ?? '',
                  )?.name ??
                  'Home';

              String locationName = widget.community.name; // Fallback

              // Try to extract location name (e.g. "London") from community name
              // Logic: Strip " Community" suffix to get the location name
              String cleanName = widget.community.name;
              if (cleanName.toLowerCase().endsWith(' community')) {
                cleanName = cleanName
                    .substring(0, cleanName.length - 10)
                    .trim();
              }
              locationName = cleanName;

              // Special case: If it's a home country community, the name might be "Kenya Community"
              // But if locationType is 'home', we just use the country name.

              String message = 'You are the first member of this community!';

              if (widget.community.locationType == 'home') {
                message =
                    'You are the first member of the $homeCountryName community!';
              } else if (widget.community.locationType == 'host' ||
                  widget.community.locationType == 'past') {
                // If the cleaned name is already the country name (e.g. Country Level community for Host),
                // simplify the message to avoid "Tanzania community for Tanzania"
                if (locationName.toLowerCase() ==
                    homeCountryName.toLowerCase()) {
                  message =
                      'You are the first member of the $homeCountryName community!';
                } else {
                  message =
                      'You are the first member of the $homeCountryName community for $locationName';
                }
              }

              return Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(32.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        // [FIX] Restored Container
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: Theme.of(
                            context,
                          ).colorScheme.primaryContainer.withValues(alpha: 0.3),
                          shape: BoxShape.rectangle,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Icon(
                          LucideIcons.partyPopper,
                          size: 48,
                          color: Colors.amber,
                        ),
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        'Congratulations!',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '$message\n\nKnow someone who lives here? Invite them to join!',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 16,
                          color: Colors.grey,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 32),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: () {
                            showDialog(
                              context: context,
                              builder: (context) => ShareCommunityDialog(
                                community: widget.community,
                              ),
                            );
                          },
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 14,
                            ),
                          ),
                          icon: const Icon(LucideIcons.share2),
                          label: const Text('Invite Friends'),
                        ),
                      ),
                      const SizedBox(
                        height: 40,
                      ), // Extra space to push it slightly up from true center
                    ],
                  ),
                ),
              );
            }

            return ListView.separated(
              padding: EdgeInsets.only(
                left: 8,
                right: 8,
                top: 12,
                bottom: MediaQuery.of(context).padding.bottom + 24,
              ),
              itemCount: members.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final member = members[index];
                return UserCardView(
                  user: member,
                  distanceKm: member.distance,
                  onNameTap: () => context.push(
                    '/profile/${member.uid}',
                    extra: {'distance': member.distance},
                  ),
                  onChatTap: (member.uid == currentUser?.uid)
                      ? null
                      : () => context.push('/chat/direct/${member.uid}'),
                );
              },
            );
          },
        ),
      ),
    );
  }

  Future<List<ProfileData>> _fetchMembers() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('communityMemberships', arrayContains: widget.communityId)
          .limit(50)
          .get();

      final currentUserProfile = ref.read(userProfileProvider).value;
      // Viewer's location: prefer live `currentLocation`, fall back to
      // `hostLocation` (set at signup). Without this fallback every distance
      // collapses to null → the UI used to render that as "1 km away".
      final currentLat =
          currentUserProfile?.currentLocation?.geometry.location.lat ??
          currentUserProfile?.hostLocation.geometry?.location.lat;
      final currentLng =
          currentUserProfile?.currentLocation?.geometry.location.lng ??
          currentUserProfile?.hostLocation.geometry?.location.lng;

      final List<ProfileData> members = [];
      for (final doc in snapshot.docs) {
        try {
          final data = doc.data();
          final profile = ProfileData.fromJson(data);
          profile.uid = doc.id;

          // Calculate distance
          double? dist;
          if (currentLat != null && currentLng != null) {
            // Priority: 1. member.currentLocation, 2. member.hostLocation
            final targetLat =
                profile.currentLocation?.geometry.location.lat ??
                profile.hostLocation.geometry?.location.lat;
            final targetLng =
                profile.currentLocation?.geometry.location.lng ??
                profile.hostLocation.geometry?.location.lng;

            if (targetLat != null && targetLng != null) {
              dist = calculateDistance(
                currentLat,
                currentLng,
                targetLat,
                targetLng,
              );
            }
          }

          members.add(profile.copyWith(distance: dist));
        } catch (docErr) {
          debugPrint('Error parsing member ${doc.id}: $docErr');
        }
      }

      // Sort by distance (closest first)
      members.sort((a, b) {
        final dA = a.distance ?? double.infinity;
        final dB = b.distance ?? double.infinity;
        return dA.compareTo(dB);
      });

      // [FIX] Self-Correction for "First Member" scenario involving index lag.
      if (members.isEmpty) {
        final currentUserData = ref.read(userProfileProvider).value;
        // If provider has data and confirms membership, assume we are the first member
        if (currentUserData != null &&
            currentUserData.communityMemberships != null &&
            currentUserData.communityMemberships!.contains(
              widget.communityId,
            )) {
          return [currentUserData];
        }
      }

      return members;
    } catch (e) {
      debugPrint('Error fetching members: $e');
      return [];
    }
  }
}
