import 'package:universal_io/io.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:share_plus/share_plus.dart';
import 'package:diaspora_nearby/core/services/google_places_service.dart';
import 'package:diaspora_nearby/core/utils/location_utils.dart';
import 'package:diaspora_nearby/features/profile/models/profile_data.dart';
import 'package:diaspora_nearby/features/shared/models/location.dart'
    as loc_model;
import 'package:diaspora_nearby/features/shared/models/google_places_models.dart';
import '../repository/profile_repository.dart';
import 'package:diaspora_nearby/features/auth/repository/auth_repository.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:diaspora_nearby/features/community/services/community_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:diaspora_nearby/features/auth/services/session_service.dart';
import 'package:diaspora_nearby/features/dsp/services/points_service.dart';
import 'package:diaspora_nearby/features/dsp/providers/referral_provider.dart';
import 'package:diaspora_nearby/features/dsp/repository/points_repository.dart'; // [NEW]
import 'package:diaspora_nearby/features/dsp/widgets/exploration_tracker.dart'; // [NEW] Share reward toast
import 'package:diaspora_nearby/features/chat/services/chamber_service.dart';

// googlePlacesServiceProvider moved to lib/services/google_places_service.dart

import '../widgets/profile_setup_location_step.dart';
import '../widgets/profile_setup_details_step.dart';

/// Setup step enum matching React's SetupStep type
enum SetupStep { location, profile }

class ProfileSetupScreen extends ConsumerStatefulWidget {
  const ProfileSetupScreen({super.key});

  @override
  ConsumerState<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends ConsumerState<ProfileSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _referralCodeController = TextEditingController(); // [NEW]

  // Current step in the flow
  SetupStep _currentStep = SetupStep.location;

  // Locations
  loc_model.UserLocation? _homeLocation;
  loc_model.UserLocation? _hostLocation;
  CurrentLocation? _currentLocation;

  // Profile Photo
  XFile? _profileImage;

  // UI State
  bool _isSubmitting = false;
  bool _showCurrentLocationName = true;

  // Places Search
  List<AutocompletePrediction> _homePredictions = [];
  final _homeSearchController = TextEditingController();

  // Focus tracking for hiding decorations
  final _homeFocusNode = FocusNode();

  // Address Components (for accurate parsing)
  List<AddressComponent>? _homeComponents;
  List<AddressComponent>? _hostComponents;

  @override
  void initState() {
    super.initState();
    // Request location permission at start
    _requestLocationPermission();

    // Track name changes for button visibility
    _firstNameController.addListener(_onNameChanged);
    _lastNameController.addListener(_onNameChanged);

    // [NEW] Check for pending referral code from deep link
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final pendingCode = ref.read(pendingReferralCodeProvider);
      if (pendingCode != null && pendingCode.isNotEmpty) {
        debugPrint('ProfileSetup: Auto-filling referral code: $pendingCode');
        _referralCodeController.text = pendingCode;
        // Optionally clear it here so it doesn't persist across fresh attempts
        // if user backs out, but usually better to clear on submit success.
      }
    });
  }

  void _onNameChanged() {
    // Trigger rebuild to update button visibility
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _firstNameController.removeListener(_onNameChanged);
    _lastNameController.removeListener(_onNameChanged);
    _homeFocusNode.dispose();
    _homeSearchController.dispose();
    _firstNameController.dispose();
    _lastNameController.dispose();
    _referralCodeController.dispose(); // [NEW]

    super.dispose();
  }

  void _useFallbackLocation() {
    final fallbackLoc = loc_model.UserLocation(
      formattedAddress: 'Unknown Location (GPS Failed)',
      placeId: 'fallback',
      city: 'Unknown City',
      country: 'Global',
      countryCode: 'XX',
      geometry: loc_model.UserLocationGeometry(
        location: loc_model.UserLocationCoordinates(lat: 0.0, lng: 0.0),
      ),
    );

    setState(() {
      _currentLocation = CurrentLocation(
        formattedAddress: '0.0, 0.0',
        placeId: '',
        geometry: loc_model.UserLocationGeometry(
          location: loc_model.UserLocationCoordinates(lat: 0.0, lng: 0.0),
        ),
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );
      _hostLocation = fallbackLoc;
    });
  }

  /// Request location permission for distance calculations
  Future<void> _requestLocationPermission({bool isRetry = false}) async {
    try {
      LocationPermission permission;

      if (kIsWeb) {
        // [FIX] Safari WebKit doesn't reliably support permissions.query for geolocation.
        // Calling checkPermission() throws an exception, instantly failing the flow.
        // By skipping checkPermission on web, we effectively allow getCurrentPosition to natively prompt.
        permission = LocationPermission.always;
      } else {
        permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied) {
          permission = await Geolocator.requestPermission();
        }

        if (permission == LocationPermission.denied ||
            permission == LocationPermission.deniedForever) {
          // Enforce Permission: Show dialog and retry
          if (mounted) {
            await showDialog(
              context: context,
              barrierDismissible: false,
              builder: (context) => AlertDialog(
                title: const Text('Location Required'),
                content: const Text(
                  'We need your location to connect you with nearby diaspora members. This is required to complete signup. If you cannot provide GPS access, you will be assigned a default location that you can change later.',
                ),
                actions: [
                  TextButton(
                    onPressed: () {
                      Navigator.pop(context);
                      // Use a fallback location so they can proceed!
                      _useFallbackLocation();
                    },
                    child: const Text('Skip & Use Default'),
                  ),
                  TextButton(
                    onPressed: () {
                      Navigator.pop(context);
                      Geolocator.openAppSettings();
                    },
                    child: const Text('Open Settings'),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      _requestLocationPermission(isRetry: true); // Retry
                    },
                    child: const Text('Try Again'),
                  ),
                ],
              ),
            );
          }
          return; // Don't proceed without permission
        }
      }

      if (permission == LocationPermission.whileInUse ||
          permission == LocationPermission.always) {
        // Get current position with timeout to prevent infinite hang
        final position =
            await Geolocator.getCurrentPosition(
              locationSettings: const LocationSettings(
                accuracy: LocationAccuracy.medium,
              ),
            ).timeout(
              const Duration(seconds: 15),
              onTimeout: () {
                throw Exception(
                  'Location request timed out. Please ensure you have GPS signal.',
                );
              },
            );

        debugPrint(
          'Ã°ÂŸÂ“Â  GPS position: ${position.latitude}, ${position.longitude}',
        );

        // Ã°ÂŸÂ”Â¥ CRITICAL: Reverse geocode to get city, state, countryCode
        final places = ref.read(googlePlacesServiceProvider);
        final locationData = await places
            .reverseGeocode(position.latitude, position.longitude)
            .timeout(
              const Duration(seconds: 10),
              onTimeout: () {
                throw Exception('Reverse geocoding timed out.');
              },
            );

        if (locationData != null) {
          final loc = loc_model.UserLocation(
            formattedAddress:
                locationData['formattedAddress'] ??
                '${position.latitude}, ${position.longitude}',
            placeId: locationData['placeId'] ?? '',
            city: locationData['city'],
            state: locationData['state'],
            country: locationData['country'],
            countryCode: locationData['countryCode'],
            geometry: loc_model.UserLocationGeometry(
              location: loc_model.UserLocationCoordinates(
                lat: position.latitude,
                lng: position.longitude,
              ),
            ),
          );

          setState(() {
            _currentLocation = CurrentLocation(
              formattedAddress:
                  locationData['formattedAddress'] ??
                  '${position.latitude}, ${position.longitude}',
              placeId: locationData['placeId'] ?? '',
              geometry: loc_model.UserLocationGeometry(
                location: loc_model.UserLocationCoordinates(
                  lat: position.latitude,
                  lng: position.longitude,
                ),
              ),
              city: locationData['city'],
              state: locationData['state'],
              countryCode: locationData['countryCode'],
              timestamp: DateTime.now().millisecondsSinceEpoch,
            );
            _hostLocation = loc;
            _hostComponents = (locationData['addressComponents'] as List?)
                ?.cast<AddressComponent>();
          });
        } else {
          // Fallback
          final fallbackLoc = loc_model.UserLocation(
            formattedAddress: '${position.latitude}, ${position.longitude}',
            placeId: '',
            city: 'Unknown City',
            country: 'Global',
            countryCode: 'XX',
            geometry: loc_model.UserLocationGeometry(
              location: loc_model.UserLocationCoordinates(
                lat: position.latitude,
                lng: position.longitude,
              ),
            ),
          );

          setState(() {
            _currentLocation = CurrentLocation(
              formattedAddress: '${position.latitude}, ${position.longitude}',
              placeId: '',
              geometry: loc_model.UserLocationGeometry(
                location: loc_model.UserLocationCoordinates(
                  lat: position.latitude,
                  lng: position.longitude,
                ),
              ),
              timestamp: DateTime.now().millisecondsSinceEpoch,
            );
            _hostLocation = fallbackLoc; // CRITICAL: Was missing previously!
          });
        }
      }
    } catch (e) {
      debugPrint('Location error: $e');
      if (mounted) {
        // Automatically fallback so they aren't blocked from signing up
        _useFallbackLocation();

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Using default location (GPS failed). Update it in profile later.',
            ),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 4),
          ),
        );
      }
    } finally {
      // cleanup complete
    }
  }

  void _onHomeSearchChanged(String input) async {
    if (input.isEmpty) {
      setState(() => _homePredictions = []);
      return;
    }

    final places = ref.read(googlePlacesServiceProvider);
    final results = await places.autocomplete(input);
    if (mounted) {
      setState(() {
        _homePredictions = results;
      });
    }
  }

  Future<void> _selectHomePlace(String placeId) async {
    final places = ref.read(googlePlacesServiceProvider);
    final response = await places.getPlaceDetails(placeId);
    final place = response?.place;

    if (place != null && mounted) {
      final components = place.addressComponents ?? [];
      final parsedLoc = parseLocationComponents(
        place.address ?? '',
        components,
      );

      if (parsedLoc != null) {
        final loc = loc_model.UserLocation(
          formattedAddress: place.address ?? '',
          placeId: place.id ?? placeId,
          city: parsedLoc.city,
          state: parsedLoc.state,
          country: parsedLoc.country,
          countryCode: parsedLoc.countryCode,
          geometry: place.latLng != null
              ? loc_model.UserLocationGeometry(
                  location: loc_model.UserLocationCoordinates(
                    lat: place.latLng!.lat,
                    lng: place.latLng!.lng,
                  ),
                )
              : null,
        );

        setState(() {
          _homePredictions = [];
          _homeLocation = loc;
          _homeComponents = components;
          _homeSearchController.text = loc.formattedAddress;
        });
      }
    }
  }

  void _goToNextStep() {
    setState(() {
      _currentStep = SetupStep.profile;
    });
  }

  void _goBack() {
    if (_currentStep == SetupStep.profile) {
      setState(() => _currentStep = SetupStep.location);
    }
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();

    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(LucideIcons.camera),
              title: const Text('Take Photo'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(LucideIcons.image),
              title: const Text('Choose from Gallery'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );

    if (source == null) return;

    try {
      final pickedFile = await picker.pickImage(
        source: source,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );

      if (pickedFile != null) {
        setState(() {
          _profileImage = pickedFile;
        });
      }
    } catch (e) {
      debugPrint('Error picking image: $e');
    }
  }

  /// Upload profile image to Firebase Storage
  Future<String?> _uploadProfileImage(String userId) async {
    if (_profileImage == null) {
      debugPrint('Ã¢ÂšÂ Ã¯Â¸Â No profile image to upload');
      return null;
    }

    try {
      debugPrint('Ã°ÂŸÂ“Â¸ Uploading profile image for user: $userId');
      debugPrint('Ã°ÂŸÂ“Â¸ File path: ${_profileImage!.path}');

      final storageRef = FirebaseStorage.instance
          .ref()
          .child('profile_photos')
          .child(userId)
          .child('profile.jpg');

      UploadTask uploadTask;
      final metadata = SettableMetadata(contentType: 'image/jpeg');

      if (kIsWeb) {
        final bytes = await _profileImage!.readAsBytes();
        uploadTask = storageRef.putData(bytes, metadata);
      } else {
        uploadTask = storageRef.putFile(File(_profileImage!.path), metadata);
      }
      final snapshot = await uploadTask;
      debugPrint(
        'Ã°ÂŸÂ“Â¸ Upload complete. Bytes transferred: ${snapshot.bytesTransferred}',
      );

      final downloadUrl = await snapshot.ref.getDownloadURL();
      debugPrint('Ã°ÂŸÂ“Â¸ Download URL: $downloadUrl');

      return downloadUrl;
    } catch (e, stack) {
      debugPrint('Ã¢ÂÂŒ Error uploading image: $e');
      debugPrint('Ã¢ÂÂŒ Stack trace: $stack');
      return null;
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_profileImage == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please add a profile photo'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    if (_homeLocation == null || _hostLocation == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select both locations')),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final user = ref.read(authRepositoryProvider).currentUser;
      if (user == null) throw Exception('No user found');

      // 1. Parse Locations to get codes
      LocationParsed? homeParsed = parseLocationComponents(
        _homeLocation!.formattedAddress,
        _homeComponents ?? [],
      );
      LocationParsed? hostParsed = parseLocationComponents(
        _hostLocation!.formattedAddress,
        _hostComponents ?? [],
      );

      // Fallback: If parsing failed (e.g. auto-detected location has no components map), use the direct fields
      if (hostParsed == null &&
          _hostLocation!.countryCode != null &&
          _hostLocation!.country != null) {
        hostParsed = LocationParsed(
          city: _hostLocation!.city,
          state: _hostLocation!.state,
          country: _hostLocation!.country!,
          countryCode: _hostLocation!.countryCode!,
          placeId: _hostLocation!.placeId,
        );
      }

      if (homeParsed == null &&
          _homeLocation!.countryCode != null &&
          _homeLocation!.country != null) {
        homeParsed = LocationParsed(
          city: _homeLocation!.city,
          state: _homeLocation!.state,
          country: _homeLocation!.country!,
          countryCode: _homeLocation!.countryCode!,
          placeId: _homeLocation!.placeId,
        );
      }

      if (homeParsed == null || hostParsed == null) {
        throw Exception(
          'Could not parse location details. Please try selecting the location again.',
        );
      }

      // 2. Upload profile image (if selected)
      String profileImageUrl = '';
      if (_profileImage != null) {
        final url = await _uploadProfileImage(user.uid);
        if (url != null) profileImageUrl = url;
      }

      // 3. Create Profile Data
      final profile = ProfileData(
        uid: user.uid,
        firstName: _firstNameController.text.trim(),
        lastName: _lastNameController.text.trim(),
        phone: user.phoneNumber ?? '',
        profileImage: profileImageUrl,
        homeLocation: _homeLocation!,
        hostLocation: _hostLocation!,
        homeCountryCode: homeParsed.countryCode,
        hostCountryCode: hostParsed.countryCode,
        homeCountry: homeParsed.country,
        hostCountry: hostParsed.country,
        currentLocation: _currentLocation,
        isBanned: false,
        advertReportCount: 0,

        yearsInHostCountry: null,
        showCurrentLocationName: _showCurrentLocationName,
      );

      // 4. Save to Firestore
      await ref
          .read(profileRepositoryProvider)
          .saveUserProfile(user.uid, profile);

      // 4.5 Create Communities & Chats (Critical Step)
      // UPDATED: Moved BEFORE points initialization to ensure community documents exist
      // when Cloud Functions distribute treasury points during awardPoints calls
      List<String> createdCommunityIds = [];
      final Set<String> newCommunityNames = {};
      void onFirstMember(String name) => newCommunityNames.add(name);

      try {
        createdCommunityIds = await CommunityService()
            .createCommunitiesAndChats(profile, onFirstMember: onFirstMember);
        await ref.read(chamberServiceProvider).ensureSignupChamber();
      } catch (e) {
        // If this fails, we must NOT proceed.
        // We report error and let user retry (submit button will re-enable).
        throw Exception('Failed to join communities: $e. Please try again.');
      }

      // 5. Initialize Points System & Process Referral
      // UPDATED: Moved AFTER community creation to ensure parent documents exist
      try {
        final pointsService = ref.read(pointsServiceProvider);

        // Initialize user points (now that communities exist)
        await pointsService.initializeUserPoints(user.uid);

        // Process referral if code was provided
        final referralCode = _referralCodeController.text.trim();
        String? referrerId;

        if (referralCode.isNotEmpty) {
          try {
            // [UPDATED] Capture referrerId for immediate relationship connection
            referrerId = await pointsService.processReferral(
              referralCode,
              user.uid,
            );
            debugPrint('Referral processed. Referrer ID: $referrerId');
          } catch (e) {
            debugPrint('Error processing referral: $e');
          }
        }

        // Relationships are added by users on their own time from the DM chat
        // "Show More" menu — no automatic prompting during signup.

        // Generate referral code for this new user
        await pointsService.generateReferralCode(
          user.uid,
          profile.firstName,
          homeParsed.countryCode,
        );
      } catch (e) {
        debugPrint('Error initializing points: $e');
        // Don't fail signup if points initialization fails
      }

      // 6. Invalidate profile provider and navigate
      // CRITICAL: We must update the local profile with the new memberships
      // BEFORE updating the provider, otherwise the router will see empty memberships
      // and redirect back to setup.
      final completeProfile = ProfileData(
        uid: profile.uid,
        firstName: profile.firstName,
        lastName: profile.lastName,
        phone: profile.phone,
        profileImage: profile.profileImage,
        homeLocation: profile.homeLocation,
        hostLocation: profile.hostLocation,
        homeCountryCode: profile.homeCountryCode,
        hostCountryCode: profile.hostCountryCode,
        homeCountry: profile.homeCountry,
        hostCountry: profile.hostCountry,
        currentLocation: profile.currentLocation,
        communityMemberships:
            createdCommunityIds, // <--- INJECT MEMBERSHIPS HERE
        isBanned: profile.isBanned,
        advertReportCount: profile.advertReportCount,
        yearsInHostCountry: profile.yearsInHostCountry,
        showCurrentLocationName: profile.showCurrentLocationName,
      );

      // 6. Update profile provider
      ref.read(userProfileProvider.notifier).updateProfile(completeProfile);

      // 7. Mark session as complete (CRITICAL for router fallback)
      await ref.read(sessionServiceProvider).updateProfileComplete(true);

      // Mark as returning user for future sessions (so next time they go to Chats)
      await ref.read(sessionServiceProvider).setReturningUser(true);

      if (!context.mounted) return;
      if (newCommunityNames.isNotEmpty) {
        await showDialog(
          // ignore: use_build_context_synchronously
          context: context,
          builder: (ctx) => Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(ctx).size.height * 0.7,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Theme.of(
                            ctx,
                          ).colorScheme.primaryContainer.withValues(alpha: 0.3),
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
                        'You are the first member of these ${newCommunityNames.length} communities!\n',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 16,
                          color: Colors.grey,
                          height: 1.4,
                        ),
                      ),
                      // List communities as chips for readability
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        alignment: WrapAlignment.center,
                        children: newCommunityNames
                            .map(
                              (name) => Chip(
                                label: Text(
                                  name,
                                  style: const TextStyle(fontSize: 12),
                                ),
                                visualDensity: VisualDensity.compact,
                              ),
                            )
                            .toList(),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Know someone who lives here?\nInvite them and earn 1,000 DSP! 🎁',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 32),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: () async {
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
                                  final countryCode =
                                      _hostLocation?.countryCode ?? 'US';
                                  code = await ref
                                      .read(pointsRepositoryProvider)
                                      .generateReferralCode(
                                        user.uid,
                                        _firstNameController.text,
                                        countryCode,
                                      );
                                }
                                shareUrl = '$shareUrl?code=$code';
                              } catch (e) {
                                debugPrint('Error getting referral code: $e');
                              }
                            }

                            await SharePlus.instance.share(
                              ShareParams(
                                text:
                                    'Join me in ${newCommunityNames.first} on Diaspora Nearby! \n\n$shareUrl',
                                subject: 'Diaspora Nearby',
                              ),
                            );

                            // Award DSP for sharing
                            if (user != null) {
                              try {
                                // Share reward — deprecated tracking functions
                                // (actual DSP is awarded via referral signup when recipient signs up)
                                if (ctx.mounted) {
                                  showExplorationRewardToast(
                                    ctx,
                                    message:
                                        'Share sent! 🎉 You\'ll earn 1,000 DSP when they sign up.',
                                    points: 1000,
                                  );
                                }
                              } catch (e) {
                                debugPrint('Error awarding share DSP: $e');
                              }
                            }

                            // Dismiss dialog AFTER share sheet completes
                            if (ctx.mounted) Navigator.pop(ctx);
                          },
                          icon: const Icon(LucideIcons.share2),
                          label: const Text(
                            'Invite Friends  •  Earn 1,000 DSP',
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('Maybe Later'),
                      ),
                    ],
                  ),
                ), // SingleChildScrollView
              ), // ConstrainedBox
            ),
          ),
        );
      }
      // Clear pending referral code on success
      ref.read(pendingReferralCodeProvider.notifier).set(null);

      if (context.mounted) {
        // ignore: use_build_context_synchronously
        context.go('/nearby'); // First time users land on Nearby to explore
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        leading: _currentStep != SetupStep.location
            ? IconButton(
                icon: const Icon(LucideIcons.arrowLeft),
                onPressed: _goBack,
              )
            : null,
        title: Text(_getStepTitle()),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Progress indicator
            LinearProgressIndicator(
              value: _getProgress(),
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
              valueColor: AlwaysStoppedAnimation(theme.colorScheme.primary),
            ),

            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 24,
                ),
                child: Form(key: _formKey, child: _buildCurrentStep(theme)),
              ),
            ),

            // No bottom button - inline buttons are used in each step
          ],
        ),
      ),
    );
  }

  String _getStepTitle() {
    switch (_currentStep) {
      case SetupStep.location:
        return 'Set Locations';
      case SetupStep.profile:
        return 'Complete your profile';
    }
  }

  double _getProgress() {
    switch (_currentStep) {
      case SetupStep.location:
        return 0.5;
      case SetupStep.profile:
        return 1.0;
    }
  }

  Widget _buildCurrentStep(ThemeData theme) {
    switch (_currentStep) {
      case SetupStep.location:
        return ProfileSetupLocationStep(
          homeSearchController: _homeSearchController,
          homeFocusNode: _homeFocusNode,
          homePredictions: _homePredictions,
          homeLocation: _homeLocation,
          hostLocation: _hostLocation,
          onHomeSearchChanged: _onHomeSearchChanged,
          onHomeSelectPlace: _selectHomePlace,
          onNext: _goToNextStep,
          onRetryHostLocation: () => _requestLocationPermission(isRetry: true),
        );
      case SetupStep.profile:
        return ProfileSetupDetailsStep(
          firstNameController: _firstNameController,
          lastNameController: _lastNameController,
          profileImage: _profileImage,
          homeLocation: _homeLocation,
          hostLocation: _hostLocation,
          onPickImage: _pickImage,
          onSubmit: _submit,
          isSubmitting: _isSubmitting,
          showLocation: _showCurrentLocationName,
          onLocationToggleChanged: (v) =>
              setState(() => _showCurrentLocationName = v),
          referralCodeController: _referralCodeController, // [NEW]
        );
    }
  }

  void _showErrorDialog(String title, String content) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}
