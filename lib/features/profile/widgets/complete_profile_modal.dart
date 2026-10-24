import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:diaspora_nearby/features/profile/models/profile_data.dart';
import 'package:diaspora_nearby/features/profile/widgets/user_profile_form.dart';
import 'package:diaspora_nearby/features/profile/repository/profile_repository.dart';
import 'package:diaspora_nearby/features/shared/models/location.dart';
import 'package:diaspora_nearby/core/utils/location_utils.dart';
import 'package:diaspora_nearby/features/community/services/community_service.dart';
import 'package:diaspora_nearby/features/community/viewmodels/community_hierarchy_viewmodel.dart';
import 'package:diaspora_nearby/features/chat/repository/chat_repository.dart';

class CompleteProfileModal extends ConsumerWidget {
  final ProfileData profile;
  final List<String> missingFields;
  final VoidCallback? onNavigateToFullEdit;

  const CompleteProfileModal({
    super.key,
    required this.profile,
    required this.missingFields,
    this.onNavigateToFullEdit,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        left: 20,
        right: 20,
        top: 20,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(LucideIcons.userPlus, color: Colors.orange),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Complete Your Profile',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ),
              if (onNavigateToFullEdit != null)
                TextButton.icon(
                  onPressed: onNavigateToFullEdit,
                  icon: const Icon(LucideIcons.externalLink, size: 14),
                  label: const Text(
                    'Full Edit',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              IconButton(
                icon: const Icon(LucideIcons.x),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'A few more details are needed before you can connect via QR. This helps maintain a high trust environment.',
            style: TextStyle(color: Colors.grey, fontSize: 13),
          ),
          const SizedBox(height: 24),
          Flexible(
            child: UserProfileForm(
              initialProfile: profile,
              highlightFields: missingFields,
              submitLabel: 'Save & Continue Connection',
              showUserCard: false,
              isFinishProfile: true,
              onSave: (updated, newImage) async {
                try {
                  final uid = updated.uid!;
                  String imageUrl = updated.profileImage;
                  if (newImage != null) {
                    imageUrl = await ref
                        .read(profileRepositoryProvider)
                        .uploadProfileImage(uid, newImage);
                  }

                  ProfileData finalProfile = updated.copyWith(
                    profileImage: imageUrl,
                  );

                  final bool hostChanged =
                      finalProfile.hostLocation.placeId !=
                          profile.hostLocation.placeId ||
                      finalProfile.hostLocation.formattedAddress !=
                          profile.hostLocation.formattedAddress;

                  final existingPastPlaceIds =
                      profile.pastLocations
                          ?.map((pl) => pl.location.placeId.trim())
                          .where((id) => id.isNotEmpty)
                          .toSet() ??
                      <String>{};
                  final existingPastAddresses =
                      profile.pastLocations
                          ?.map(
                            (pl) => pl.location.formattedAddress
                                .trim()
                                .toLowerCase(),
                          )
                          .where((addr) => addr.isNotEmpty)
                          .toSet() ??
                      <String>{};
                  final oldHostPlaceId = profile.hostLocation.placeId.trim();
                  final oldHostAddress = profile.hostLocation.formattedAddress
                      .trim()
                      .toLowerCase();

                  if (hostChanged) {
                    final oldLoc = profile.hostLocation;
                    final pastLoc = PastLocation(
                      location: oldLoc,
                      until: DateTime.now().toIso8601String(),
                    );
                    final List<PastLocation> updatedPastList = List.from(
                      finalProfile.pastLocations ?? [],
                    );
                    final alreadyInPast = updatedPastList.any(
                      (pl) =>
                          (oldHostPlaceId.isNotEmpty &&
                              pl.location.placeId.trim() == oldHostPlaceId) ||
                          (oldHostAddress.isNotEmpty &&
                              pl.location.formattedAddress
                                      .trim()
                                      .toLowerCase() ==
                                  oldHostAddress),
                    );
                    if (!alreadyInPast) {
                      updatedPastList.add(pastLoc);
                    }
                    finalProfile = finalProfile.copyWith(
                      pastLocations: updatedPastList,
                    );
                  }

                  await ref
                      .read(profileRepositoryProvider)
                      .saveUserProfile(uid, finalProfile);

                  final Set<String> joinedCommunityIds = {
                    ...?profile.communityMemberships,
                    ...?finalProfile.communityMemberships,
                  };
                  bool communitiesUpdated = false;

                  if (hostChanged) {
                    try {
                      final hostCommIds = await ref
                          .read(communityServiceProvider)
                          .createCommunitiesAndChats(finalProfile);
                      if (hostCommIds.isNotEmpty) {
                        joinedCommunityIds.addAll(hostCommIds);
                        communitiesUpdated = true;
                      }
                    } catch (e) {
                      debugPrint('Error syncing host communities in modal: $e');
                    }
                  }

                  if (finalProfile.pastLocations != null) {
                    try {
                      final commService = ref.read(communityServiceProvider);
                      final homeCode =
                          (finalProfile.homeCountryCode ??
                                  profile.homeCountryCode ??
                                  finalProfile.homeLocation.countryCode ??
                                  'XX')
                              .trim()
                              .toUpperCase();

                      for (final pl in finalProfile.pastLocations!) {
                        if (pl.location.city == null ||
                            pl.location.city!.trim().isEmpty) {
                          continue;
                        }
                        final pid = pl.location.placeId.trim();
                        final addr = pl.location.formattedAddress
                            .trim()
                            .toLowerCase();

                        final locationParsed = LocationParsed(
                          city: pl.location.city,
                          state: pl.location.state,
                          country: pl.location.country ?? '',
                          countryCode: (pl.location.countryCode ?? 'XX')
                              .trim()
                              .toUpperCase(),
                          placeId: pl.location.placeId,
                        );

                        final expectedCityCommId = generateCommunityId(
                          locationType: 'host',
                          type: 'city',
                          location: locationParsed,
                          homeCountryCode: homeCode,
                        );

                        final wasAlreadyInPast =
                            (pid.isNotEmpty &&
                                existingPastPlaceIds.contains(pid)) ||
                            (addr.isNotEmpty &&
                                existingPastAddresses.contains(addr));
                        final isJustArchivedOldHost =
                            hostChanged &&
                            ((pid.isNotEmpty && pid == oldHostPlaceId) ||
                                (addr.isNotEmpty && addr == oldHostAddress));

                        if ((wasAlreadyInPast || isJustArchivedOldHost) &&
                            joinedCommunityIds.contains(expectedCityCommId)) {
                          continue;
                        }

                        final pastCommIds = await commService
                            .ensureCommunitiesForLocationHierarchy(
                              location: locationParsed,
                              locationType: 'host',
                              userId: uid,
                              homeCountryCode: homeCode,
                              hostCountryCode: locationParsed.countryCode,
                              syncToUserProfile: true,
                              userName: finalProfile.fullName,
                            );
                        if (pastCommIds.isNotEmpty) {
                          joinedCommunityIds.addAll(pastCommIds);
                          communitiesUpdated = true;
                        }
                      }
                    } catch (e) {
                      debugPrint(
                        'Error syncing past location communities in modal: $e',
                      );
                    }
                  }

                  if (communitiesUpdated) {
                    finalProfile = finalProfile.copyWith(
                      communityMemberships: joinedCommunityIds.toList(),
                    );
                    ref
                        .read(profileRepositoryProvider)
                        .invalidateProfileCache(uid);
                    ref.invalidate(communityHierarchyProvider);
                    await ref
                        .read(chatRepositoryProvider)
                        .refreshChatsFromServer();
                  }

                  ref
                      .read(userProfileProvider.notifier)
                      .updateProfile(finalProfile);

                  if (context.mounted) {
                    Navigator.pop(context, true);
                  }
                } catch (e) {
                  debugPrint('Error saving profile in modal: $e');
                  rethrow;
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}
