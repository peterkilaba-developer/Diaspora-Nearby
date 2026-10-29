import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:diaspora_nearby/features/profile/models/profile_data.dart';
import 'package:diaspora_nearby/features/profile/widgets/user_profile_form.dart';
import 'package:diaspora_nearby/features/profile/repository/profile_repository.dart';
import 'package:diaspora_nearby/features/shared/models/location.dart';
import 'package:diaspora_nearby/core/utils/location_utils.dart';
import 'package:diaspora_nearby/features/shared/utils/app_snackbar.dart';
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
    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
      child: Container(
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
                  final uid = updated.uid!;
                  final profileRepo = ref.read(profileRepositoryProvider);
                  final commService = ref.read(communityServiceProvider);
                  final chatRepo = ref.read(chatRepositoryProvider);
                  final profileNotifier = ref.read(
                    userProfileProvider.notifier,
                  );

                  final bool hostChanged =
                      updated.hostLocation.placeId !=
                          profile.hostLocation.placeId ||
                      updated.hostLocation.formattedAddress !=
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

                  ProfileData provisionalProfile = updated.copyWith(
                    profileImage: newImage != null
                        ? newImage.path
                        : updated.profileImage,
                  );

                  if (hostChanged) {
                    final oldLoc = profile.hostLocation;
                    final pastLoc = PastLocation(
                      location: oldLoc,
                      until: DateTime.now().toIso8601String(),
                    );
                    final List<PastLocation> updatedPastList = List.from(
                      provisionalProfile.pastLocations ?? [],
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
                    provisionalProfile = provisionalProfile.copyWith(
                      pastLocations: updatedPastList,
                    );
                  }

                  // [PERF] Optimistically update caches & state and pop modal in 0ms
                  profileRepo.cacheProfile(uid, provisionalProfile);
                  profileNotifier.updateProfile(provisionalProfile);

                  if (context.mounted) {
                    AppSnackbar.success(context, 'Profile completed!');
                    Navigator.pop(context, true);
                  }

                  unawaited(() async {
                    try {
                      ProfileData finalProfile = provisionalProfile;
                      if (newImage != null) {
                        final imageUrl = await profileRepo.uploadProfileImage(
                          uid,
                          newImage,
                        );
                        finalProfile = finalProfile.copyWith(
                          profileImage: imageUrl,
                        );
                      }

                      await profileRepo.saveUserProfile(uid, finalProfile);

                      final Set<String> joinedCommunityIds = {
                        ...?profile.communityMemberships,
                        ...?finalProfile.communityMemberships,
                      };
                      bool communitiesUpdated = false;

                      if (hostChanged) {
                        try {
                          final hostCommIds = await commService
                              .createCommunitiesAndChats(finalProfile);
                          if (hostCommIds.isNotEmpty) {
                            joinedCommunityIds.addAll(hostCommIds);
                            communitiesUpdated = true;
                          }
                        } catch (e) {
                          debugPrint(
                            'Error syncing host communities in modal: $e',
                          );
                        }
                      }

                      if (finalProfile.pastLocations != null) {
                        try {
                          final homeCode =
                              (finalProfile.homeCountryCode ??
                                      profile.homeCountryCode ??
                                      finalProfile.homeLocation.countryCode ??
                                      'XX')
                                  .trim()
                                  .toUpperCase();

                          final pastFutures = <Future<List<String>>>[];
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
                                    (addr.isNotEmpty &&
                                        addr == oldHostAddress));

                            if ((wasAlreadyInPast || isJustArchivedOldHost) &&
                                joinedCommunityIds.contains(
                                  expectedCityCommId,
                                )) {
                              continue;
                            }

                            pastFutures.add(
                              commService.ensureCommunitiesForLocationHierarchy(
                                location: locationParsed,
                                locationType: 'host',
                                userId: uid,
                                homeCountryCode: homeCode,
                                hostCountryCode: locationParsed.countryCode,
                                syncToUserProfile: true,
                                userName: finalProfile.fullName,
                              ),
                            );
                          }

                          if (pastFutures.isNotEmpty) {
                            final pastResults = await Future.wait(pastFutures);
                            for (final pastCommIds in pastResults) {
                              if (pastCommIds.isNotEmpty) {
                                joinedCommunityIds.addAll(pastCommIds);
                                communitiesUpdated = true;
                              }
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
                        profileRepo.invalidateProfileCache(uid);
                        ref.invalidate(communityHierarchyProvider);
                        await chatRepo.refreshChatsFromServer();
                      }

                      profileRepo.cacheProfile(uid, finalProfile);
                      profileNotifier.updateProfile(finalProfile);
                    } catch (e) {
                      debugPrint('Error saving profile in modal: $e');
                    }
                  }());
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
