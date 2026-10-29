import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:diaspora_nearby/core/data/countries.dart';
import 'package:go_router/go_router.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:diaspora_nearby/features/community/models/community_data.dart';
import 'package:diaspora_nearby/features/community/repository/community_repository.dart';
import 'package:diaspora_nearby/features/chat/utils/community_chat_utils.dart';
import 'package:diaspora_nearby/features/profile/models/profile_data.dart';
import 'package:diaspora_nearby/features/shared/widgets/user_card.dart';
import 'package:diaspora_nearby/features/auth/repository/auth_repository.dart';
import 'package:diaspora_nearby/features/profile/repository/profile_repository.dart';
import 'package:diaspora_nearby/core/utils/location_utils.dart';
import 'package:diaspora_nearby/features/dsp/services/points_service.dart';
import 'package:diaspora_nearby/features/shared/widgets/confetti_overlay.dart';
import 'package:diaspora_nearby/features/dsp/widgets/exploration_tracker.dart';
import 'package:diaspora_nearby/features/community/widgets/share_community_dialog.dart';
import 'package:diaspora_nearby/theme/app_theme.dart';

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
    unawaited(_trackExploration());
  }

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

  void _openShareDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: ShareCommunityDialog(community: widget.community),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final viewerHomeCountryCode = ref
        .watch(userProfileProvider)
        .value
        ?.homeCountryCode;
    final displayTitle = CommunityChatUtils.generateCommunityNameFromParts(
      name: widget.community.name,
      locationType: widget.community.locationType ?? '',
      id: widget.community.id,
      homeCountryCode: widget.community.homeCountryCode,
      hostCountryCode: widget.community.hostCountryCode,
      viewerHomeCountryCode: viewerHomeCountryCode,
    );

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
              viewerHomeCountryCode: viewerHomeCountryCode,
              communityId: widget.community.id,
              profileImage: widget.community.profileImage,
              size: 32,
            ),
            const SizedBox(width: 12),
            if (CommunityChatUtils.isBilateral(
              id: widget.community.id,
              locationType: widget.community.locationType,
            )) ...[
              const Icon(
                LucideIcons.heartHandshake,
                size: 16,
                color: AppTheme.accent,
              ),
              const SizedBox(width: 6),
            ],
            Expanded(
              child: Text(
                displayTitle,
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
            onPressed: () => _openShareDialog(context),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('users')
              .where('communityMemberships', arrayContains: widget.communityId)
              .limit(50)
              .snapshots(),
          builder: (context, snapshot) {
            final currentUser = ref.watch(authRepositoryProvider).currentUser;
            final currentProfile =
                ref.watch(userProfileProvider).value ??
                (currentUser != null
                    ? ref
                          .read(profileRepositoryProvider)
                          .getCachedProfile(currentUser.uid)
                    : null);
            final cachedMembers = ref
                .read(communityRepositoryProvider)
                .getCachedCommunityMembers(widget.communityId);

            if (snapshot.connectionState == ConnectionState.waiting &&
                !snapshot.hasData &&
                cachedMembers == null) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError && cachedMembers == null) {
              return Center(child: Text('Error: ${snapshot.error}'));
            }

            final List<ProfileData> members;
            if (snapshot.hasData) {
              members = _parseAndSortMembers(
                snapshot.data!.docs,
                currentProfile,
              );
              ref
                  .read(communityRepositoryProvider)
                  .cacheCommunityMembers(widget.communityId, members);
            } else {
              members = cachedMembers ?? const <ProfileData>[];
            }

            final isMember =
                currentProfile?.communityMemberships?.contains(
                  widget.communityId,
                ) ??
                false;

            final isFirstMember =
                isMember &&
                (members.isEmpty ||
                    (members.length == 1 &&
                        members.first.uid == currentUser?.uid));

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
                          onPressed: () => _openShareDialog(context),
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
              final homeCountryName =
                  getCountryByCode(
                    widget.community.homeCountryCode ?? '',
                  )?.name ??
                  'Home';

              String cleanName = widget.community.name;
              if (cleanName.toLowerCase().endsWith(' community')) {
                cleanName = cleanName
                    .substring(0, cleanName.length - 10)
                    .trim();
              }
              final String locationName = cleanName;

              String message = 'You are the first member of this community!';

              if (widget.community.locationType == 'home') {
                message =
                    'You are the first member of the $homeCountryName community!';
              } else if (widget.community.locationType == 'host' ||
                  widget.community.locationType == 'past') {
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
                          onPressed: () => _openShareDialog(context),
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

  List<ProfileData> _parseAndSortMembers(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    ProfileData? currentUserProfile,
  ) {
    try {
      final profileRepo = ref.read(profileRepositoryProvider);
      final List<ProfileData> members = [];
      for (final doc in docs) {
        try {
          final data = doc.data();
          final profile = ProfileData.fromJson(data);
          profile.uid = doc.id;
          profileRepo.cacheProfile(doc.id, profile);

          final dist = calculateProfileDistanceKm(currentUserProfile, profile);
          members.add(profile.copyWith(distance: dist));
        } catch (docErr) {
          debugPrint('Error parsing member ${doc.id}: $docErr');
        }
      }

      members.sort((a, b) {
        final dA = a.distance ?? double.infinity;
        final dB = b.distance ?? double.infinity;
        return dA.compareTo(dB);
      });

      if (members.isEmpty) {
        if (currentUserProfile != null &&
            currentUserProfile.communityMemberships != null &&
            currentUserProfile.communityMemberships!.contains(
              widget.communityId,
            )) {
          return [currentUserProfile.copyWith(distance: 0.0)];
        }
      }

      return members;
    } catch (e) {
      debugPrint('Error parsing members: $e');
      return [];
    }
  }
}
