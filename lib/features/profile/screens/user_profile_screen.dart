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

    _refreshProfile();
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
    final user = ref.read(authRepositoryProvider).currentUser;

    if (src == 'qr' && user != null && widget.userId != user.uid) {
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
      _triggerQRConnection(user.uid, widget.userId);
    }
  }

  Future<void> _triggerQRConnection(String fromUid, String toUid) async {
    try {
      // Show a brief loading indicator or overlay if needed, but performQRExchange handles logic
      await ref
          .read(trustServiceProvider)
          .performQRExchange(
            fromUid: fromUid,
            toUid: toUid,
            // locationAddress is null here as we don't want to block on geocoding for deep links
            // TrustService can handle null or we can try a quick fetch if critical.
          );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('In-Person Connection Verified! 100 DSP Earned.'),
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
          _triggerQRConnection(fromUid, toUid);
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
  Future<void> _refreshProfile({bool showLoading = true}) async {
    if (showLoading) {
      setState(() {
        _isLoadingProfile = true;
        _errorMessage = null;
      });
    }

    try {
      debugPrint('🔍 [ProfileScreen] _refreshProfile called for userId="${widget.userId}" (showLoading=$showLoading)');
      final profile = await ref
          .read(profileRepositoryProvider)
          .getUserProfile(widget.userId);
      debugPrint('🔍 [ProfileScreen] _refreshProfile result → '
          'firstName="${profile?.firstName}", lastName="${profile?.lastName}", '
          'profileImage="${profile?.profileImage.isNotEmpty == true ? "SET" : "EMPTY"}", '
          'homeCity="${profile?.homeLocation.city}", '
          'hostCity="${profile?.hostLocation.city}"');
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
          debugPrint('📋 [ProfileScreen] Background refresh failed but using existing profile data');
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
      debugPrint('🔄 [Profile] Triggering background trust recalculation for ${user.uid}');
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

      // 1. Upload Image if changed
      if (newImage != null) {
        final url = await ref
            .read(profileRepositoryProvider)
            .uploadProfileImage(user.uid, newImage);
        profileToSave = updatedProfile.copyWith(profileImage: url);
      }

      // 2. Logic to sync communities if Host Location Changed
      if (profileToSave.hostLocation.placeId !=
              currentProfile.hostLocation.placeId ||
          profileToSave.hostLocation.formattedAddress !=
              currentProfile.hostLocation.formattedAddress) {
        // 1. Archive Old Location to Past Locations
        final oldLoc = currentProfile.hostLocation;
        final pastLoc = PastLocation(
          location: oldLoc,
          until: DateTime.now().toIso8601String(),
        );

        final List<PastLocation> updatedPastList = List.from(
          profileToSave.pastLocations ?? [],
        );
        updatedPastList.add(pastLoc);

        // Update the profile object so step 3 (below) picks it up for community sync
        profileToSave = profileToSave.copyWith(pastLocations: updatedPastList);

        // 2. Logic to sync communities for New Host Location
        try {
          // [UPDATED] Do NOT remove user from old Host communities.
          // Per requirements: "User should never be removed from community... maintain membership."

          // CRITICAL: Use the robust "New User" logic to create/join communities and sync chats.
          // This handles Global, Home, and Host hierarchies appropriately.
          await ref.read(communityServiceProvider).createCommunitiesAndChats(
            profileToSave,
            onFirstMember: onFirstMember,
          );
        } catch (e) {
          debugPrint('Error syncing host communities: $e');
        }
      }

      if (profileToSave.pastLocations != null) {
        try {
          final commService = ref.read(communityServiceProvider);
          for (final pl in profileToSave.pastLocations!) {
            if (pl.location.city == null) continue; // Skip incomplete locations

            // Ensure robust parsing before sync (Standard New User Method)
            final locationParsed = LocationParsed(
              city: pl.location.city,
              state: pl.location.state,
              country: pl.location.country ?? '',
              countryCode: pl.location.countryCode ?? 'XX',
              placeId: pl.location.placeId, // [NEW] Pass Place ID
            );

            // [CORRECTION] Treat past locations as Host locations (same community ID)
            // This ensures users join the standard Host community for that location.
            await commService.ensureCommunitiesForLocationHierarchy(
              location: locationParsed,
              locationType: 'host',
              userId: user.uid,
              homeCountryCode: currentProfile.homeCountryCode ?? 'XX',
              // The "host country" context for this hierarchy is the location's own country
              hostCountryCode: locationParsed.countryCode,
              syncToUserProfile: true, // Auto-sync to profile memberships
              onFirstMember: onFirstMember,
            );
          }
        } catch (e) {
          debugPrint('Error syncing past location communities: $e');
        }
      }

      debugPrint('UserProfileScreen: Saving profile...'); // [DEBUG]
      await ref
          .read(profileRepositoryProvider)
          .saveUserProfile(user.uid, profileToSave);

      // [NEW] Update Trust Score (Fire and forget or await)
      // Await is better here so user sees immediate feedback if we show trust score on profile
      await ref.read(trustServiceProvider).updateTrustForUser(user.uid);

      debugPrint('UserProfileScreen: Profile saved to repository.'); // [DEBUG]

      if (mounted) {
        setState(() {
          _profile = profileToSave;
          _isEditing = false; // Return to view mode after save
        });

        // Update global provider safely
        ref.read(userProfileProvider.notifier).updateProfile(profileToSave);
        _refreshProfile(showLoading: false); // [FIX] Don't show loading spinner or error on post-save refresh

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
                              String shareUrl = 'https://diasporanearby.com/invite';

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
                      if (_profile?.currentLocation != null &&
                          currentUserProfile?.currentLocation != null) {
                        try {
                          return Geolocator.distanceBetween(
                                currentUserProfile!
                                    .currentLocation!
                                    .geometry
                                    .location
                                    .lat,
                                currentUserProfile
                                    .currentLocation!
                                    .geometry
                                    .location
                                    .lng,
                                _profile!
                                    .currentLocation!
                                    .geometry
                                    .location
                                    .lat,
                                _profile!
                                    .currentLocation!
                                    .geometry
                                    .location
                                    .lng,
                              ) /
                              1000.0;
                        } catch (e) {
                          debugPrint('Error calculating distance: $e');
                        }
                      }
                      return null;
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
