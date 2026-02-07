import 'package:image_picker/image_picker.dart';
import 'package:universal_io/io.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:go_router/go_router.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:diaspora_nearby/features/auth/repository/auth_repository.dart';
import 'package:diaspora_nearby/features/profile/repository/profile_repository.dart';
import 'package:diaspora_nearby/models/profile_data.dart';
import 'package:diaspora_nearby/models/location.dart';
import 'package:diaspora_nearby/features/community/repository/community_repository.dart';
import 'package:diaspora_nearby/features/organization/repository/organization_repository.dart';
import 'package:diaspora_nearby/features/events/repository/event_repository.dart';
import 'package:diaspora_nearby/features/community/models/community_data.dart' as comm_model;
import 'package:diaspora_nearby/models/event_data.dart' as event_model;
import 'package:diaspora_nearby/models/chat.dart';
import 'package:diaspora_nearby/features/chat/repository/chat_repository.dart';
import 'package:diaspora_nearby/services/community_service.dart';
import 'package:diaspora_nearby/utils/location_utils.dart'; // For LocationParsed if needed

import '../widgets/user_profile_view.dart';
import '../widgets/user_profile_editor.dart';

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

class _UserProfileScreenState extends ConsumerState<UserProfileScreen> with WidgetsBindingObserver {
  // Data Fetching State
  late Future<List<Chat>> _groupsFuture;
  late Future<List<Map<String, dynamic>>> _orgsFuture;
  late Stream<List<event_model.Event>> _eventsStream;
  // REMOVED: late Future<ProfileData?> _profileFuture;
  
  // New State
  ProfileData? _profile;
  bool _isLoadingProfile = true;
  String? _errorMessage;

  // UI State
  bool _showPermissionWarning = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshProfile();
    _checkLocationPermission();
  }

  Future<void> _refreshProfile() async {
    setState(() {
      _isLoadingProfile = true;
      _errorMessage = null;
    });

    // Initialize side-futures
    _groupsFuture = ref.read(chatRepositoryProvider).getUserChats().then((chats) => chats.where((c) => c.isGroup).toList());
    _orgsFuture = ref.read(organizationRepositoryProvider).getUserOrganizations(widget.userId);
    _eventsStream = ref.read(eventRepositoryProvider).getJoinedEvents(widget.userId);

    try {
      final profile = await ref.read(profileRepositoryProvider).getUserProfile(widget.userId);
      if (mounted) {
        setState(() {
          _profile = profile;
          _isLoadingProfile = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _isLoadingProfile = false;
        });
      }
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
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
      if (mounted) setState(() => _showPermissionWarning = true);
    } else {
      if (mounted && _showPermissionWarning) setState(() => _showPermissionWarning = false);
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
    if (permission == LocationPermission.whileInUse || permission == LocationPermission.always) {
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
         final url = await ref.read(profileRepositoryProvider).uploadProfileImage(user.uid, newImage);
         profileToSave = updatedProfile.copyWith(profileImage: url);
      }

      // 2. Logic to sync communities if Host Location Changed
      if (profileToSave.hostLocation.placeId != currentProfile.hostLocation.placeId || 
          profileToSave.hostLocation.formattedAddress != currentProfile.hostLocation.formattedAddress) {
         
         // 1. Archive Old Location to Past Locations
         final oldLoc = currentProfile.hostLocation;
         final pastLoc = PastLocation(
            location: oldLoc,
            until: DateTime.now().toIso8601String(),
         );

         final List<PastLocation> updatedPastList = List.from(profileToSave.pastLocations ?? []);
         updatedPastList.add(pastLoc);
         
         // Update the profile object so step 3 (below) picks it up for community sync
         profileToSave = profileToSave.copyWith(pastLocations: updatedPastList);

         // 2. Logic to sync communities for New Host Location
         try {
             // [UPDATED] Do NOT remove user from old Host communities.
             // Per requirements: "User should never be removed from community... maintain membership."
             
             // CRITICAL: Use the robust "New User" logic to create/join communities and sync chats.
             // This handles Global, Home, and Host hierarchies appropriately.
             await CommunityService().createCommunitiesAndChats(
                profileToSave,
                onFirstMember: onFirstMember,
             );
         } catch (e) {
           debugPrint('Error syncing host communities: $e');
         }
      }


      if (profileToSave.pastLocations != null) {
          try {
             final commService = CommunityService();
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

      print('UserProfileScreen: Saving profile...'); // [DEBUG]
      await ref.read(profileRepositoryProvider).saveUserProfile(user.uid, profileToSave);
      print('UserProfileScreen: Profile saved to repository.'); // [DEBUG]
      
      if (mounted) {
         setState(() {
            _profile = profileToSave;
         });

         // Update global provider safely
         ref.read(userProfileProvider.notifier).updateProfile(profileToSave);
         _refreshProfile(); // [NEW] Refresh data dependencies
         
         ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profile updated successfully!')));
         
         if (newCommunityNames.isNotEmpty) {
            Future.delayed(const Duration(milliseconds: 500), () {
              if (mounted) {
                showDialog(
                  context: context,
                  builder: (ctx) => Dialog(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(LucideIcons.partyPopper, size: 40, color: Colors.amber),
                          ),
                          const SizedBox(height: 24),
                          const Text(
                            'Congratulations!',
                            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'You are the first member of ${newCommunityNames.join(", ")}!\n\nKnow someone who lives here? Invite them to join!',
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 16, color: Colors.grey, height: 1.4),
                          ),
                          const SizedBox(height: 32),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: () {
                                Navigator.pop(ctx);
                                Share.share('Join me in ${newCommunityNames.first} on DiasporaNearby!');
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
      print('UserProfileScreen: Error saving profile: $e\n$stack'); // [DEBUG]
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error saving profile: $e')));
      rethrow; // Editor needs to know it failed
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
           UserProfileView(
              profile: _profile!,
              isSelf: isSelf,
              isEnforced: widget.isEnforced,
              distanceKm: () {
                if (isSelf) return 0.0;
                if (widget.initialDistance != null) return widget.initialDistance;
                
                final currentUserProfile = ref.watch(userProfileProvider).value;
                if (_profile?.currentLocation != null && currentUserProfile?.currentLocation != null) {
                  try {
                    return Geolocator.distanceBetween(
                      currentUserProfile!.currentLocation!.geometry.location.lat,
                      currentUserProfile.currentLocation!.geometry.location.lng,
                      _profile!.currentLocation!.geometry.location.lat,
                      _profile!.currentLocation!.geometry.location.lng,
                    ) / 1000.0;
                  } catch (e) {
                    debugPrint('Error calculating distance: $e');
                  }
                }
                return _profile?.distance;
              }(),
              onEdit: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => UserProfileEditor(
                      initialProfile: _profile!,
                      onSave: _saveProfile,
                    ),
                  ),
                );
              },
              groupsFuture: _groupsFuture,
              orgsFuture: _orgsFuture,
              eventsStream: _eventsStream,
            ),
        
        if (_showPermissionWarning)
          Container(
            color: Colors.black54,
            child: Center(
              child: Card(
                color: Colors.red.shade700,
                margin: const EdgeInsets.symmetric(horizontal: 32),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(LucideIcons.mapPinOff, color: Colors.white, size: 48),
                      const SizedBox(height: 16),
                      const Text('Location Required', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      const Text('This app requires location permission to function.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white70)),
                      const SizedBox(height: 24),
                      ElevatedButton(
                        onPressed: _openSettings,
                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF9CAF88), foregroundColor: Colors.white),
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
