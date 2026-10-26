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
  // Data Fetching State

  // REMOVED: late Future<ProfileData?> _profileFuture;

  // New State
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

    // [NEW] Parse query parameters early
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
    });

    // [PERF] Seed profile synchronously from memory cache so the screen renders
    // on frame 0 without a full-screen loading spinner.
    final currentUserId = ref.read(authRepositoryProvider).currentUser?.uid;
    final cachedProfile =
        (currentUserId == widget.userId
            ? ref.read(userProfileProvider).value
            : null) ??
        ref.read(profileRepositoryProvider).getCachedProfile(widget.userId);
    if (cachedProfile != null) {
      _profile = cachedProfile;
      _isLoadingProfile = false;
    }

    _refreshProfile(showLoading: _profile == null);
    _checkLocationPermission();
    _handleIncomingAction();
    _refreshTrustData();
  }

  Future<void> _handleIncomingAction() async {
    // Give a small delay for profile to load and state to settle
    await Future.delayed(const Duration(milliseconds: 800));
    if (!mounted) return;

    final state = GoRouterState.of(context);
    final src = state.uri.queryParameters['src'];
    final handshakeToken = state.uri.queryParameters['qrToken'];
    final user = ref.read(authRepositoryProvider).currentUser;

    if (src == 'qr' &&
        handshakeToken != null &&
        user != null &&
        widget.userId != user.uid) {
      final currentProfile = ref.read(userProfileProvider).value;
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
        final currentProfile = ref.read(userProfileProvider).value;
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
        _refreshProfile(); // Refresh to show the connection section
      }
    } on IncompleteProfileException catch (e) {
      if (!mounted) return;

      if (e.isOwnProfile) {
        debugPrint(
          'UserProfileScreen: OWN profile incomplete for QR connection. Showing modal.',
        );
        final success = await _showCompleteProfileModal(e.missingFields);
        if (success == true) {
          // Re-trigger connection after profile update
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

    // Fetch latest profile data to ensure modal has current state
    final latestProfile = await ref
        .read(profileRepositoryProvider)
        .getUserProfile(user.uid);

    if (!mounted) return false;

    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => CompleteProfileModal(
        profile: latestProfile ?? _profile!, // Ensure we have a profile
        missingFields: missingFields,
        onNavigateToFullEdit: () {
          // Alternative to modal: Navigate to full page with highlights
          Navigator.pop(context, false);
          setState(() {
            _isEditing = true;
            _initialHighlightFields = missingFields;
          });
        },
      ),
    );
  }

  /// Refresh profile data from Firestore.
  ///
  /// [showLoading] – when `false` the existing profile data stays visible
  /// while we fetch in the background (used after save to avoid flashing a
  /// loading spinner and to prevent timeout errors from overwriting the
  /// already-known good profile).
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
      debugPrint(
        '🔍 [ProfileScreen] _refreshProfile called for userId="${widget.userId}" (showLoading=$showLoading, forceServer=$forceServer)',
      );
      final profile = await ref
          .read(profileRepositoryProvider)
          .getUserProfile(widget.userId, forceServer: forceServer);
      debugPrint(
        '🔍 [ProfileScreen] _refreshProfile result → '
        'firstName="${profile?.firstName}", lastName="${profile?.lastName}", '
        'profileImage="${profile?.profileImage.isNotEmpty == true ? "SET" : "EMPTY"}", '
        'homeCity="${profile?.homeLocation.city}", '
        'hostCity="${profile?.hostLocation.city}"',
      );
      if (mounted) {
        setState(() {
          _profile = profile;
          _isLoadingProfile = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading profile: $e');
      if (mounted) {
        // [FIX] If we already have profile data (e.g. after a save), don't
        // overwrite it with an error — the profile was just saved successfully
        // and only the background refresh failed (timeout / network).
        if (_profile != null && !showLoading) {
          debugPrint(
            '📋 [ProfileScreen] Background refresh failed but using existing profile data',
          );
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

  /// Background trust recalculation to ensure milestone genesis IDs are current
  Future<void> _refreshTrustData() async {
    final user = ref.read(authRepositoryProvider).currentUser;
    // Only recalculate for own profile view
    if (user == null || user.uid != widget.userId) return;

    try {
      debugPrint(
        '🔄 [Profile] Triggering background trust recalculation for ${user.uid}',
      );
      await ref.read(trustServiceProvider).updateTrustForUser(user.uid);
      debugPrint('✅ [Profile] Trust recalculation complete');
    } catch (e) {
      debugPrint('⚠️ [Profile] Trust recalculation failed: $e');
    }
  }

  @override
  void didUpdateWidget(UserProfileScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userId != widget.userId) {
      _refreshProfile();
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
    // FocusScope.of(context).unfocus(); // Handled by Editor
    // setState(() => _isSaving = true); // Handled by Editor
    try {
      final user = ref.read(authRepositoryProvider).currentUser;
      if (user == null) throw Exception("User not logged in");

      final currentProfile = _profile; // Use local state
      if (currentProfile == null) throw Exception("Profile not loaded");

      // Track newly created communities where user is the first member
      final Set<String> newCommunityNames = {};
      void onFirstMember(String name) => newCommunityNames.add(name);

      ProfileData profileToSave = updatedProfile;

      // Snapshot counts before any mutations for DSP reward detection.
      // formPastCount = what the user submitted (original + manually added).
      // originalPastCount = what was in Firestore before this save.
      // The diff isolates explicit user additions from the auto-archive step below.
      final originalPastCount = currentProfile.pastLocations?.length ?? 0;
      final formPastCount = updatedProfile.pastLocations?.length ?? 0;
      final hasManualPastLocationAddition = formPastCount > originalPastCount;

      // 1. Upload Image if changed
      if (newImage != null) {
        final url = await ref
            .read(profileRepositoryProvider)
            .uploadProfileImage(user.uid, newImage);
        profileToSave = updatedProfile.copyWith(profileImage: url);
      }

      final bool hostChanged =
          profileToSave.hostLocation.placeId !=
              currentProfile.hostLocation.placeId ||
          profileToSave.hostLocation.formattedAddress !=
              currentProfile.hostLocation.formattedAddress;

      // Snapshot existing past placeIds and formatted addresses BEFORE archiving old host
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

      // If Host Location Changed, archive Old Location to Past Locations first
      if (hostChanged) {
        final oldLoc = currentProfile.hostLocation;
        final pastLoc = PastLocation(
          location: oldLoc,
          until: DateTime.now().toIso8601String(),
        );

        final List<PastLocation> updatedPastList = List.from(
          profileToSave.pastLocations ?? [],
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

        profileToSave = profileToSave.copyWith(pastLocations: updatedPastList);
      }

      // 2. Save profile to Firestore FIRST so Cloud Functions (provisionSignupCommunities,
      // ensureCommunity, ensureSignupChamber) read the updated name, hostLocation,
      // and hostCountryCode from users/{uid}.
      debugPrint('UserProfileScreen: Saving profile...');
      await ref
          .read(profileRepositoryProvider)
          .saveUserProfile(user.uid, profileToSave);

      final Set<String> joinedCommunityIds = {
        ...?currentProfile.communityMemberships,
        ...?profileToSave.communityMemberships,
      };
      bool communitiesUpdated = false;

      // 3. Sync communities for New Host Location if Host Location Changed
      if (hostChanged) {
        try {
          // Do NOT remove user from old Host communities.
          // Per requirements: "User should never be removed from community... maintain membership."
          final hostCommIds = await ref
              .read(communityServiceProvider)
              .createCommunitiesAndChats(
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

      // 4. Sync communities for newly added "Also lived in" (past) locations
      if (profileToSave.pastLocations != null) {
        try {
          final commService = ref.read(communityServiceProvider);
          final homeCode =
              (profileToSave.homeCountryCode ??
                      currentProfile.homeCountryCode ??
                      profileToSave.homeLocation.countryCode ??
                      'XX')
                  .trim()
                  .toUpperCase();

          for (final pl in profileToSave.pastLocations!) {
            if (pl.location.city == null || pl.location.city!.trim().isEmpty) {
              continue; // Skip incomplete locations
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

            // Compute expected city community ID to check if user is already a member
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

            // Only skip if it was already in pastLocations (or is the just-archived old host)
            // AND the user is already a member of its city community.
            if ((wasAlreadyInPast || isJustArchivedOldHost) &&
                joinedCommunityIds.contains(expectedCityCommId)) {
              continue;
            }

            // Treat past locations as Host locations (same community ID)
            // so users join the standard Host community & chat for that location.
            final pastCommIds = await commService
                .ensureCommunitiesForLocationHierarchy(
                  location: locationParsed,
                  locationType: 'host',
                  userId: user.uid,
                  homeCountryCode: homeCode,
                  hostCountryCode: locationParsed.countryCode,
                  syncToUserProfile: true,
                  onFirstMember: onFirstMember,
                  userName: profileToSave.fullName,
                );
            if (pastCommIds.isNotEmpty) {
              joinedCommunityIds.addAll(pastCommIds);
              communitiesUpdated = true;
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
        ref.read(profileRepositoryProvider).invalidateProfileCache(user.uid);
        ref.invalidate(communityHierarchyProvider);
        await ref.read(chatRepositoryProvider).refreshChatsFromServer();
      }

      // [NEW] Update Trust Score (Fire and forget or await)
      // Await is better here so user sees immediate feedback if we show trust score on profile
      await ref.read(trustServiceProvider).updateTrustForUser(user.uid);

      // DSP distribution for location-change events (once per user per event type).
      // Run both checks in parallel so they don't compound save latency.
      try {
        final pointsService = ref.read(pointsServiceProvider);

        final dspFutures = <Future<void>>[];
        if (hostChanged) {
          dspFutures.add(pointsService.trackHostLocationMove(user.uid));
        }
        if (hasManualPastLocationAddition) {
          dspFutures.add(pointsService.trackAlsoLivedInAdded(user.uid));
        }
        if (dspFutures.isNotEmpty) await Future.wait(dspFutures);
      } catch (e) {
        debugPrint('Location DSP reward failed: $e');
      }

      debugPrint('UserProfileScreen: Profile saved to repository.'); // [DEBUG]

      if (mounted) {
        setState(() {
          _profile = profileToSave;
          _isEditing = false; // Return to view mode after save
        });

        // Update global provider safely
        ref.read(userProfileProvider.notifier).updateProfile(profileToSave);
        _refreshProfile(
          showLoading: false,
          forceServer: true,
        ); // [FIX] Don't show loading spinner or error on post-save refresh

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile updated successfully!')),
        );

        if (newCommunityNames.isNotEmpty) {
          Future.delayed(const Duration(milliseconds: 500), () {
            if (mounted) {
              showDialog(
                context: context,
                builder: (ctx) => Dialog(
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
                            color: Theme.of(context)
                                .colorScheme
                                .primaryContainer
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
                            onPressed: () async {
                              Navigator.pop(ctx);

                              final user = ref
                                  .read(authRepositoryProvider)
                                  .currentUser;
                              String shareUrl =
                                  'https://diasporanearby.com/invite';

                              if (user != null) {
                                try {
                                  String? code = await ref
                                      .read(pointsRepositoryProvider)
                                      .getReferralCode(user.uid);
                                  if (code == null) {
                                    // profileToSave is the latest profile we just saved
                                    final countryCode =
                                        profileToSave.homeCountryCode ?? 'US';
                                    code = await ref
                                        .read(pointsRepositoryProvider)
                                        .generateReferralCode(
                                          user.uid,
                                          profileToSave.firstName,
                                          countryCode,
                                        );
                                  }
                                  shareUrl = '$shareUrl?code=$code';
                                } catch (e) {
                                  debugPrint('Error getting referral code: $e');
                                }
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
              );
            }
          });
        }
      }
    } catch (e, stack) {
      debugPrint(
        'UserProfileScreen: Error saving profile: $e\n$stack',
      ); // [DEBUG]
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error saving profile: $e')));
      }
      rethrow; // Editor needs to know it failed
    }
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
