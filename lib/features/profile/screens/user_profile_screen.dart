import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:go_router/go_router.dart';
import 'package:diaspora_nearby/theme/app_theme.dart';

import 'package:diaspora_nearby/features/auth/repository/auth_repository.dart';
import 'package:diaspora_nearby/features/profile/repository/profile_repository.dart';
import 'package:diaspora_nearby/features/profile/models/profile_data.dart';
import 'package:diaspora_nearby/features/shared/models/location.dart';
import 'package:diaspora_nearby/features/community/services/community_service.dart';
import 'package:diaspora_nearby/features/community/viewmodels/community_hierarchy_viewmodel.dart';
import 'package:diaspora_nearby/features/chat/repository/chat_repository.dart';
import 'package:diaspora_nearby/features/trust/services/trust_service.dart';
import 'package:diaspora_nearby/features/dsp/repository/points_repository.dart';
import 'package:diaspora_nearby/core/utils/location_utils.dart';
import 'package:diaspora_nearby/features/dsp/services/points_service.dart';
import 'package:diaspora_nearby/features/dsp/widgets/exploration_tracker.dart';
import 'package:diaspora_nearby/features/dsp/services/exploration_registry.dart';

import '../widgets/user_profile_view.dart';
import '../widgets/user_profile_editor.dart';
import '../widgets/complete_profile_modal.dart';

class UserProfileScreen extends ConsumerStatefulWidget {
  final String userId;
  final bool isEnforced;
  final double? initialDistance;

  const UserProfileScreen({
    super.key,
    required this.userId,
    this.isEnforced = false,
    this.initialDistance,
  });

  @override
  ConsumerState<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends ConsumerState<UserProfileScreen>
    with WidgetsBindingObserver {
  ProfileData? _profile;
  bool _isLoadingProfile = true;
  String? _errorMessage;

  // UI State
  bool _showPermissionWarning = false;
  bool _isEditing = false;
  List<String>? _initialHighlightFields;
  String? _src;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    final currentUserId = ref.read(authRepositoryProvider).currentUser?.uid;

    // [PERF] Seed profile synchronously from memory cache so the screen renders
    // on frame 0 without a full-screen loading spinner.
    final cachedProfile =
        (currentUserId == widget.userId
            ? ref.read(userProfileProvider).value
            : null) ??
        ref.read(profileRepositoryProvider).getCachedProfile(widget.userId);
    if (cachedProfile != null) {
      _profile = cachedProfile;
      _isLoadingProfile = false;
    }

    // [PERF] Pre-warm own referral code in the background so Share buttons open in 0ms
    if (currentUserId != null && currentUserId == widget.userId) {
      unawaited(ref.read(pointsRepositoryProvider).getReferralCode(currentUserId));
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final state = GoRouterState.of(context);
      final edit = state.uri.queryParameters['edit'] == 'true';
      final highlightStr = state.uri.queryParameters['highlight'];
      final src = state.uri.queryParameters['src'];

      if (src != null) {
        setState(() => _src = src);
      }

      if (edit) {
        setState(() {
          _isEditing = true;
          if (highlightStr != null) {
            _initialHighlightFields = highlightStr
                .split(',')
                .map((e) => e.trim())
                .toList();
          }
        });
      }

      _handleIncomingAction();
    });

    _refreshProfile(showLoading: _profile == null);
    _checkLocationPermission();
    _refreshTrustData();
  }

  Future<void> _handleIncomingAction() async {
    if (!mounted) return;

    final state = GoRouterState.of(context);
    final src = state.uri.queryParameters['src'];
    final handshakeToken = state.uri.queryParameters['qrToken'];
    final user = ref.read(authRepositoryProvider).currentUser;

    if (src == 'qr' &&
        handshakeToken != null &&
        user != null &&
        widget.userId != user.uid) {
      final currentProfile =
          ref.read(userProfileProvider).value ??
          ref.read(profileRepositoryProvider).getCachedProfile(user.uid);
      if (currentProfile == null) return;

      // Check if already connected to avoid duplicate logic
      if (_profile?.firstQrConnection?.otherUid == user.uid ||
          currentProfile.firstQrConnection?.otherUid == widget.userId) {
        debugPrint(
          'UserProfileScreen: Already connected via QR, skipping auto-exchange.',
        );
        return;
      }

      debugPrint(
        'UserProfileScreen: Detected incoming QR link. Triggering connection.',
      );
      _triggerQRConnection(user.uid, widget.userId, handshakeToken);
    }
  }

  Future<void> _triggerQRConnection(
    String fromUid,
    String toUid,
    String handshakeToken,
  ) async {
    try {
      String? locationAddress;
      try {
        final currentProfile =
            ref.read(userProfileProvider).value ??
            ref.read(profileRepositoryProvider).getCachedProfile(fromUid);
        if (currentProfile != null) {
          final host = currentProfile.hostLocation;
          final city = host.city?.trim();
          final country = host.country?.trim();
          final state = host.state?.trim();
          if (city != null && city.isNotEmpty) {
            locationAddress = state != null && state.isNotEmpty
                ? '$city, $state${country != null && country.isNotEmpty ? ', $country' : ''}'
                : (country != null && country.isNotEmpty
                      ? '$city, $country'
                      : city);
          }
        }
      } catch (_) {}

      await ref
          .read(trustServiceProvider)
          .performQRExchange(
            fromUid: fromUid,
            toUid: toUid,
            handshakeToken: handshakeToken,
            locationAddress: locationAddress,
          );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('In-Person Connection Verified! 1,000 DSP Earned.'),
            backgroundColor: Colors.green,
          ),
        );
        _refreshProfile(showLoading: false);
      }
    } on IncompleteProfileException catch (e) {
      if (!mounted) return;

      if (e.isOwnProfile) {
        debugPrint(
          'UserProfileScreen: OWN profile incomplete for QR connection. Showing modal.',
        );
        final success = await _showCompleteProfileModal(e.missingFields);
        if (success == true) {
          _triggerQRConnection(fromUid, toUid, handshakeToken);
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'The other user needs to complete their profile. Missing: ${e.missingFields.join(', ')}',
            ),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      debugPrint('Error in auto-QR connection: $e');
    }
  }

  Future<bool?> _showCompleteProfileModal(List<String> missingFields) async {
    final user = ref.read(authRepositoryProvider).currentUser;
    if (user == null) return false;

    // [PERF] Read cached profile synchronously so modal opens in 0ms
    final latestProfile =
        ref.read(userProfileProvider).value ??
        ref.read(profileRepositoryProvider).getCachedProfile(user.uid) ??
        _profile;
    if (latestProfile == null) return false;

    if (!mounted) return false;

    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => CompleteProfileModal(
        profile: latestProfile,
        missingFields: missingFields,
        onNavigateToFullEdit: () {
          Navigator.pop(context, false);
          setState(() {
            _isEditing = true;
            _initialHighlightFields = missingFields;
          });
        },
      ),
    );
  }

  Future<void> _refreshProfile({
    bool showLoading = true,
    bool forceServer = false,
  }) async {
    if (showLoading) {
      setState(() {
        _isLoadingProfile = true;
        _errorMessage = null;
      });
    }

    try {
      final profile = await ref
          .read(profileRepositoryProvider)
          .getUserProfile(widget.userId, forceServer: forceServer);
      if (mounted) {
        setState(() {
          _profile = profile;
          _isLoadingProfile = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading profile: $e');
      if (mounted) {
        if (_profile != null && !showLoading) {
          setState(() => _isLoadingProfile = false);
        } else {
          setState(() {
            _errorMessage = e.toString();
            _isLoadingProfile = false;
          });
        }
      }
    }
  }

  Future<void> _refreshTrustData() async {
    final user = ref.read(authRepositoryProvider).currentUser;
    if (user == null || user.uid != widget.userId) return;

    try {
      await ref.read(trustServiceProvider).updateTrustForUser(user.uid);
    } catch (e) {
      debugPrint('⚠️ [Profile] Trust recalculation failed: $e');
    }
  }

  @override
  void didUpdateWidget(UserProfileScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userId != widget.userId) {
      final cached = ref
          .read(profileRepositoryProvider)
          .getCachedProfile(widget.userId);
      if (cached != null) {
        _profile = cached;
        _isLoadingProfile = false;
      }
      _refreshProfile(showLoading: _profile == null);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _checkLocationPermission() async {
    final permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      if (mounted) setState(() => _showPermissionWarning = true);
    } else {
      if (mounted && _showPermissionWarning) {
        setState(() => _showPermissionWarning = false);
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkLocationPermission();
      if (widget.isEnforced) {
        _checkAndNavigate();
      }
    }
  }

  Future<void> _checkAndNavigate() async {
    final permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.whileInUse ||
        permission == LocationPermission.always) {
      if (mounted) context.go('/nearby');
    }
  }

  Future<void> _openSettings() async {
    await Geolocator.openAppSettings();
  }

  Future<void> _saveProfile(ProfileData updatedProfile, XFile? newImage) async {
    final user = ref.read(authRepositoryProvider).currentUser;
    if (user == null) throw Exception("User not logged in");

    final currentProfile = _profile;
    if (currentProfile == null) throw Exception("Profile not loaded");

    final originalPastCount = currentProfile.pastLocations?.length ?? 0;
    final formPastCount = updatedProfile.pastLocations?.length ?? 0;
    final hasManualPastLocationAddition = formPastCount > originalPastCount;

    final bool hostChanged =
        updatedProfile.hostLocation.placeId !=
            currentProfile.hostLocation.placeId ||
        updatedProfile.hostLocation.formattedAddress !=
            currentProfile.hostLocation.formattedAddress;

    final existingPastPlaceIds =
        currentProfile.pastLocations
            ?.map((pl) => pl.location.placeId.trim())
            .where((id) => id.isNotEmpty)
            .toSet() ??
        <String>{};
    final existingPastAddresses =
        currentProfile.pastLocations
            ?.map((pl) => pl.location.formattedAddress.trim().toLowerCase())
            .where((addr) => addr.isNotEmpty)
            .toSet() ??
        <String>{};
    final oldHostPlaceId = currentProfile.hostLocation.placeId.trim();
    final oldHostAddress = currentProfile.hostLocation.formattedAddress
        .trim()
        .toLowerCase();

    ProfileData provisionalProfile = updatedProfile.copyWith(
      profileImage: newImage != null
          ? newImage.path
          : updatedProfile.profileImage,
    );

    if (hostChanged) {
      final oldLoc = currentProfile.hostLocation;
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
                pl.location.formattedAddress.trim().toLowerCase() ==
                    oldHostAddress),
      );
      if (!alreadyInPast) {
        updatedPastList.add(pastLoc);
      }

      provisionalProfile = provisionalProfile.copyWith(
        pastLocations: updatedPastList,
      );
    }

    final profileRepo = ref.read(profileRepositoryProvider);
    final profileNotifier = ref.read(userProfileProvider.notifier);
    final commService = ref.read(communityServiceProvider);
    final chatRepo = ref.read(chatRepositoryProvider);
    final trustService = ref.read(trustServiceProvider);
    final pointsService = ref.read(pointsServiceProvider);
    final pointsRepo = ref.read(pointsRepositoryProvider);

    // [PERF] Optimistically update UI & caches and exit edit mode on frame 0 (0ms)!
    if (mounted) {
      setState(() {
        _profile = provisionalProfile;
        _isEditing = false;
      });
      profileRepo.cacheProfile(user.uid, provisionalProfile);
      profileNotifier.updateProfile(provisionalProfile);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile updated successfully!')),
      );
    }

    // Complete upload, Firestore save, community sync, trust & DSP updates in the background
    unawaited(() async {
      try {
        final Set<String> newCommunityNames = {};
        void onFirstMember(String name) => newCommunityNames.add(name);

        ProfileData profileToSave = provisionalProfile;
        if (newImage != null) {
          final url = await profileRepo.uploadProfileImage(user.uid, newImage);
          profileToSave = provisionalProfile.copyWith(profileImage: url);
        }

        await profileRepo.saveUserProfile(user.uid, profileToSave);

        final Set<String> joinedCommunityIds = {
          ...?currentProfile.communityMemberships,
          ...?profileToSave.communityMemberships,
        };
        bool communitiesUpdated = false;

        if (hostChanged) {
          try {
            final hostCommIds = await commService.createCommunitiesAndChats(
              profileToSave,
              onFirstMember: onFirstMember,
            );
            if (hostCommIds.isNotEmpty) {
              joinedCommunityIds.addAll(hostCommIds);
              communitiesUpdated = true;
            }
          } catch (e) {
            debugPrint('Error syncing host communities: $e');
          }
        }

        if (profileToSave.pastLocations != null) {
          try {
            final homeCode =
                (profileToSave.homeCountryCode ??
                        currentProfile.homeCountryCode ??
                        profileToSave.homeLocation.countryCode ??
                        'XX')
                    .trim()
                    .toUpperCase();

            final pastFutures = <Future<List<String>>>[];
            for (final pl in profileToSave.pastLocations!) {
              if (pl.location.city == null ||
                  pl.location.city!.trim().isEmpty) {
                continue;
              }

              final pid = pl.location.placeId.trim();
              final addr = pl.location.formattedAddress.trim().toLowerCase();

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
                  (pid.isNotEmpty && existingPastPlaceIds.contains(pid)) ||
                  (addr.isNotEmpty && existingPastAddresses.contains(addr));
              final isJustArchivedOldHost =
                  hostChanged &&
                  ((pid.isNotEmpty && pid == oldHostPlaceId) ||
                      (addr.isNotEmpty && addr == oldHostAddress));

              if ((wasAlreadyInPast || isJustArchivedOldHost) &&
                  joinedCommunityIds.contains(expectedCityCommId)) {
                continue;
              }

              pastFutures.add(
                commService.ensureCommunitiesForLocationHierarchy(
                  location: locationParsed,
                  locationType: 'host',
                  userId: user.uid,
                  homeCountryCode: homeCode,
                  hostCountryCode: locationParsed.countryCode,
                  syncToUserProfile: true,
                  onFirstMember: onFirstMember,
                  userName: profileToSave.fullName,
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
            debugPrint('Error syncing past location communities: $e');
          }
        }

        if (communitiesUpdated) {
          profileToSave = profileToSave.copyWith(
            communityMemberships: joinedCommunityIds.toList(),
          );
          profileRepo.invalidateProfileCache(user.uid);
          if (mounted) {
            ref.invalidate(communityHierarchyProvider);
          }
          await chatRepo.refreshChatsFromServer();
        }

        profileRepo.cacheProfile(user.uid, profileToSave);
        profileNotifier.updateProfile(profileToSave);
        if (mounted) {
          setState(() => _profile = profileToSave);
        }

        // Run trust score update and DSP location rewards in parallel
        await Future.wait([
          trustService.updateTrustForUser(user.uid).catchError((Object e) {
            debugPrint('Trust update error: $e');
          }),
          if (hostChanged)
            pointsService.trackHostLocationMove(user.uid).catchError((
              Object e,
            ) {
              debugPrint('Location DSP reward failed: $e');
            }),
          if (hasManualPastLocationAddition)
            pointsService.trackAlsoLivedInAdded(user.uid).catchError((
              Object e,
            ) {
              debugPrint('Location DSP reward failed: $e');
            }),
        ]);

        if (newCommunityNames.isNotEmpty && mounted) {
          showDialog(
            context: context,
            builder: (ctx) => BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Dialog(
                insetPadding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 24,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 32,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(
                          AppTheme.pageHorizontalPadding,
                        ),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primaryContainer
                              .withValues(alpha: 0.3),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          LucideIcons.partyPopper,
                          size: 40,
                          color: Colors.amber,
                        ),
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        'Congratulations!',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'You are the first member of ${newCommunityNames.join(", ")}!\n\nKnow someone who lives here? Invite them to join!',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 16,
                          color: Colors.grey,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 32),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: () {
                            Navigator.pop(ctx);

                            String shareUrl =
                                'https://diasporanearby.com/invite';
                            final cachedCode = pointsRepo.getCachedReferralCode(
                              user.uid,
                            );
                            if (cachedCode != null && cachedCode.isNotEmpty) {
                              shareUrl = '$shareUrl?code=$cachedCode';
                            } else {
                              unawaited(
                                pointsRepo.getReferralCode(user.uid),
                              );
                            }

                            SharePlus.instance.share(
                              ShareParams(
                                text:
                                    'Join me in ${newCommunityNames.first} on Diaspora Nearby! \n\n$shareUrl',
                                subject: 'Diaspora Nearby',
                              ),
                            );
                          },
                          icon: const Icon(LucideIcons.share2),
                          label: const Text('Invite Friends'),
                        ),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('Maybe Later'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }
      } catch (e, stack) {
        debugPrint('UserProfileScreen: Error saving profile: $e\n$stack');
      }
    }());
  }

  Future<void> _trackExploration(String actionId) async {
    final user = ref.read(authRepositoryProvider).currentUser;
    if (user != null) {
      final rewarded = await ref
          .read(pointsServiceProvider)
          .trackExplorationReward(user.uid, actionId);
      if (rewarded && mounted) {
        showExplorationRewardToast(context);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authRepositoryProvider).currentUser;
    final isSelf = user?.uid == widget.userId;

    return Stack(
      children: [
        if (_isLoadingProfile)
          const Scaffold(body: Center(child: CircularProgressIndicator()))
        else if (_errorMessage != null)
          Scaffold(body: Center(child: Text('Error: $_errorMessage')))
        else if (_profile == null)
          const Scaffold(body: Center(child: Text('User not found')))
        else
          PopScope(
            canPop: !_isEditing,
            onPopInvokedWithResult: (didPop, _) {
              if (didPop) return;
              if (_isEditing) {
                setState(() => _isEditing = false);
              }
            },
            child: _isEditing
                ? UserProfileEditor(
                    key: const ValueKey('profile_editor'),
                    initialProfile: _profile!,
                    onSave: _saveProfile,
                    onCancel: () => setState(() => _isEditing = false),
                    highlightFields: _initialHighlightFields,
                  )
                : UserProfileView(
                    key: const ValueKey('profile_view'),
                    profile: _profile!,
                    isSelf: isSelf,
                    isEnforced: widget.isEnforced,
                    onEdit: () {
                      _trackExploration(ExplorationAction.profileEdit);
                      setState(() => _isEditing = true);
                    },
                    onShowCompleteProfile: (missingFields) {
                      return _showCompleteProfileModal(missingFields);
                    },
                    src: _src,
                    distanceKm: () {
                      if (isSelf) return 0.0;
                      final currentUserProfile = ref
                          .watch(userProfileProvider)
                          .value;
                      final liveTargetProfile =
                          ref
                              .watch(userProfileByIdProvider(widget.userId))
                              .value ??
                          _profile;
                      return calculateProfileDistanceKm(
                        currentUserProfile,
                        liveTargetProfile,
                        fallbackDistanceKm: widget.initialDistance,
                      );
                    }(),
                    onRefresh: _refreshProfile,
                  ),
          ),

        if (_showPermissionWarning)
          Container(
            color: Colors.black54,
            child: Center(
              child: Card(
                color: Colors.red.shade700,
                margin: const EdgeInsets.symmetric(
                  horizontal: AppTheme.pageHorizontalPadding * 2,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(AppTheme.pageHorizontalPadding),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        LucideIcons.mapPinOff,
                        color: Colors.white,
                        size: 48,
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Location Required',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'This app requires location permission to function.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white70),
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton(
                        onPressed: _openSettings,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Theme.of(
                            context,
                          ).colorScheme.primary,
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('Enable Location Permission'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
