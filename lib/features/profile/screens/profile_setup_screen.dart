import 'package:universal_io/io.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:share_plus/share_plus.dart';
import 'package:diaspora_nearby/services/google_places_service.dart';
import 'package:diaspora_nearby/utils/location_utils.dart';
import 'package:diaspora_nearby/models/profile_data.dart';
import 'package:diaspora_nearby/models/location.dart' as loc_model;
import 'package:diaspora_nearby/models/google_places_models.dart';
import '../repository/profile_repository.dart';
import 'package:diaspora_nearby/features/auth/repository/auth_repository.dart';
import 'package:diaspora_nearby/router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:diaspora_nearby/services/community_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:diaspora_nearby/config/env.dart';
import 'package:diaspora_nearby/services/session_service.dart';
import 'package:diaspora_nearby/features/dsp/services/points_service.dart';

// googlePlacesServiceProvider moved to lib/services/google_places_service.dart

import '../widgets/profile_setup_home_step.dart';
import '../widgets/profile_setup_host_step.dart';
import '../widgets/profile_setup_details_step.dart';

/// Setup step enum matching React's SetupStep type
enum SetupStep { home, host, profile }



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
  SetupStep _currentStep = SetupStep.home;
  
  // Locations
  loc_model.UserLocation? _homeLocation;
  loc_model.UserLocation? _hostLocation;
  CurrentLocation? _currentLocation;
  
  // Profile Photo
  XFile? _profileImage;
  
  // UI State
  bool _isSubmitting = false;
  bool _isRequestingLocation = false;
  bool _showCurrentLocationName = true;
  
  // Places Search
  List<AutocompletePrediction> _predictions = [];
  final _homeSearchController = TextEditingController();
  final _hostSearchController = TextEditingController();
  
  // Focus tracking for hiding decorations
  final _homeFocusNode = FocusNode();
  final _hostFocusNode = FocusNode();
  bool _isHomeFocused = false;
  bool _isHostFocused = false;
  
  // Address Components (for accurate parsing)
  List<AddressComponent>? _homeComponents;
  List<AddressComponent>? _hostComponents;

  @override
  void initState() {
    super.initState();
    // Request location permission at start
    _requestLocationPermission();
    
    // Track focus for hiding decorations
    _homeFocusNode.addListener(() {
      setState(() => _isHomeFocused = _homeFocusNode.hasFocus);
    });
    _hostFocusNode.addListener(() {
      setState(() => _isHostFocused = _hostFocusNode.hasFocus);
    });
    
    // Track name changes for button visibility
    _firstNameController.addListener(_onNameChanged);
    _lastNameController.addListener(_onNameChanged);

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
    _hostFocusNode.dispose();
    _homeSearchController.dispose();
    _hostSearchController.dispose();
    _firstNameController.dispose();
    _lastNameController.dispose();
    _referralCodeController.dispose(); // [NEW]

    super.dispose();
  }

  /// Request location permission for distance calculations
  Future<void> _requestLocationPermission() async {
    setState(() => _isRequestingLocation = true);
    
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        // Enforce Permission: Show dialog and retry
        if (mounted) {
           await showDialog(
             context: context,
             barrierDismissible: false,
             builder: (context) => AlertDialog(
               title: const Text('Location Required'),
               content: const Text('We need your location to connect you with nearby diaspora members. This is required to complete signup.'),
               actions: [
                 TextButton(
                   onPressed: () {
                     Navigator.pop(context);
                     Geolocator.openAppSettings(); // Guide user to settings if denied forever, or just retry
                     _requestLocationPermission(); // Recursive retry
                   },
                   child: const Text('Open Settings'),
                 ),
                 ElevatedButton(
                   onPressed: () {
                     Navigator.pop(context);
                     _requestLocationPermission(); // Retry
                   },
                   child: const Text('Grant Permission'),
                 ),
               ],
             ),
           );
        }
        return; // Don't proceed without permission
      }

      if (permission == LocationPermission.whileInUse || 
          permission == LocationPermission.always) {
        // Get current position
        final position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.medium,
        );
        
        debugPrint('ð GPS position: ${position.latitude}, ${position.longitude}');
        
        // ð¥ CRITICAL: Reverse geocode to get city, state, countryCode
        final places = ref.read(googlePlacesServiceProvider);
        final locationData = await places.reverseGeocode(
          position.latitude,
          position.longitude,
        );
        
        if (locationData != null) {
          setState(() {
            _currentLocation = CurrentLocation(
              formattedAddress: locationData['formattedAddress'] ?? '${position.latitude}, ${position.longitude}',
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
          });
        } else {
             // Fallback
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
          });
        }
      }
    } catch (e) {
      debugPrint('Location error: $e');
    } finally {
      if (mounted) setState(() => _isRequestingLocation = false);
    }
  }

  void _onSearchChanged(String input, bool isHome) async {
    if (input.isEmpty) {
      setState(() => _predictions = []);
      return;
    }
    
    final places = ref.read(googlePlacesServiceProvider);
    final results = await places.autocomplete(input);
    if (mounted) {
      setState(() {
        _predictions = results;
      });
    }
  }

  Future<void> _selectPlace(String placeId, bool isHome) async {
    final places = ref.read(googlePlacesServiceProvider);
    final response = await places.getPlaceDetails(placeId);
      final place = response?.place;
    
    if (place != null && mounted) {
      // Use shared utility for consistent parsing (UK constituent countries, etc.)
      final components = place.addressComponents ?? [];
      final parsedLoc = parseLocationComponents(place.address ?? '', components);
      
      if (parsedLoc != null) {
        final loc = loc_model.UserLocation(
          formattedAddress: place.address ?? '',
          placeId: place.id ?? placeId,
          city: parsedLoc.city,
          state: parsedLoc.state,
          country: parsedLoc.country,
          countryCode: parsedLoc.countryCode,
          geometry: place.latLng != null ? loc_model.UserLocationGeometry(
            location: loc_model.UserLocationCoordinates(
              lat: place.latLng!.lat,
              lng: place.latLng!.lng,
            ),
          ) : null,
        );

        setState(() {
          _predictions = [];
          
          if (isHome) {
            _homeLocation = loc;
            _homeComponents = components;
            _homeSearchController.text = loc.formattedAddress;
          } else {
             // For Host Location, Verify against GPS
             _verifySelectedHostLocation(loc, components);
          }
        });
      }
    }
  }

  Future<void> _verifySelectedHostLocation(loc_model.UserLocation selected, List<AddressComponent> components) async {
      try {
         // 1. Permission (Should be granted by now, but check)
         LocationPermission permission = await Geolocator.checkPermission();
         if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
             _showErrorDialog('Location Required', 'We need your GPS location to verify you are currently in this city.');
             return;
         }

         // 2. Get Current Position (Use cached if available and fresh, otherwise fetch)
         double? currentLat;
         double? currentLng;
         
         if (_currentLocation != null) {
            currentLat = _currentLocation!.geometry.location.lat;
            currentLng = _currentLocation!.geometry.location.lng;
            debugPrint('Using cached location for verification');
         } else {
            final position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.medium);
            currentLat = position.latitude;
            currentLng = position.longitude;
             debugPrint('Fetched fresh location for verification');
         }
         
         // 3. Calculate Distance
         // Selected Lat/Lng
         double? targetLat = selected.geometry?.location.lat;
         double? targetLng = selected.geometry?.location.lng;
         
         if (targetLat == null || targetLng == null) {
             // If autocomplete didn't give geometry, we must trust (or block). 
             // Usually it does. Let's warn.
             _showErrorDialog('Verification Failed', 'Could not determine coordinates of selected city.');
             return;
         }

         if (currentLat == null || currentLng == null) {
             _showErrorDialog('Location Error', 'Could not determine your current location.');
             return;
         }

         final distanceKm = calculateDistance(
             currentLat, currentLng, targetLat, targetLng
         );
         
         const double MAX_DISTANCE_KM = 50.0; // 50km radius leeway

         if (distanceKm > MAX_DISTANCE_KM) {
             _showErrorDialog(
                'Location Mismatch', 
                'You are ${distanceKm.round()}km away from ${selected.city}. You must be physically located in your host city to select it.'
             );
             
             // [NEW] Clear input so user can search again immediately
             setState(() {
               _predictions = [];
               _hostSearchController.clear();
             });
             return;
         }

         // Verification Success
         setState(() {
             _hostLocation = selected;
             _hostComponents = components;
             _hostSearchController.text = selected.formattedAddress;
         });

      } catch (e) {
          debugPrint('Verification error: $e');
          _showErrorDialog('Error', 'Could not verify location: $e');
      }
  }

  void _goToNextStep() {
      setState(() {
         // [NOTE] We do NOT auto-fill host location anymore based on pivot.
         // We might show the detected location as a hint in the UI, but we let user search.
         _currentStep = SetupStep.host;
      });
  }

  void _goBack() {
    if (_currentStep == SetupStep.host) {
      setState(() => _currentStep = SetupStep.home);
    } else if (_currentStep == SetupStep.profile) {
      setState(() => _currentStep = SetupStep.host);
    }
  }

  /// Pick profile image from camera or gallery
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
      debugPrint('â ï¸ No profile image to upload');
      return null;
    }

    try {
      debugPrint('ð¸ Uploading profile image for user: $userId');
      debugPrint('ð¸ File path: ${_profileImage!.path}');
      
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
      debugPrint('ð¸ Upload complete. Bytes transferred: ${snapshot.bytesTransferred}');
      
      final downloadUrl = await snapshot.ref.getDownloadURL();
      debugPrint('ð¸ Download URL: $downloadUrl');
      
      return downloadUrl;
    } catch (e, stack) {
      debugPrint('â Error uploading image: $e');
      debugPrint('â Stack trace: $stack');
      return null;
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
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
      LocationParsed? homeParsed = parseLocationComponents(_homeLocation!.formattedAddress, _homeComponents ?? []);
      LocationParsed? hostParsed = parseLocationComponents(_hostLocation!.formattedAddress, _hostComponents ?? []);

      // Fallback: If parsing failed (e.g. auto-detected location has no components map), use the direct fields
      if (hostParsed == null && _hostLocation!.countryCode != null && _hostLocation!.country != null) {
          hostParsed = LocationParsed(
             city: _hostLocation!.city,
             state: _hostLocation!.state,
             country: _hostLocation!.country!,
             countryCode: _hostLocation!.countryCode!,
             placeId: _hostLocation!.placeId
          );
      }
      
      if (homeParsed == null && _homeLocation!.countryCode != null && _homeLocation!.country != null) {
          homeParsed = LocationParsed(
             city: _homeLocation!.city,
             state: _homeLocation!.state,
             country: _homeLocation!.country!,
             countryCode: _homeLocation!.countryCode!,
             placeId: _homeLocation!.placeId
          );
      }

      if (homeParsed == null || hostParsed == null) {
        throw Exception('Could not parse location details. Please try selecting the location again.');
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
      await ref.read(profileRepositoryProvider).saveUserProfile(user.uid, profile);

      // 4.5 Initialize Points System & Process Referral
      try {
        final pointsService = ref.read(pointsServiceProvider);
        
        // Initialize user points
        await pointsService.initializeUserPoints(user.uid);
        
        // Process referral if code was provided
        final referralCode = _referralCodeController.text.trim();
        if (referralCode.isNotEmpty) {
           try {
              await pointsService.processReferral(referralCode, user.uid);
              debugPrint('Referral processed successfully: $referralCode');
           } catch (e) {
              // Log but don't fail signup (or should we show error? usually better to be silent on failure or just log)
              // User might typo. Maybe we should validate before submit? 
              // For now, let's just log. Better UX would be validation in the step itself, but processReferral does the awarding.
              debugPrint('Error processing referral: $e');
              // We could show a toast here later if critical.
           }
        }
        
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

      // 5. Create Communities & Chats (Critical Step)
      // We do this BEFORE invalidating/navigating to ensure it succeeds
      List<String> createdCommunityIds = [];
      final Set<String> newCommunityNames = {};
      void onFirstMember(String name) => newCommunityNames.add(name);

      try {
        createdCommunityIds = await CommunityService().createCommunitiesAndChats(
           profile,
           onFirstMember: onFirstMember,
        );
      } catch (e) {
        // If this fails, we must NOT proceed.
        // We report error and let user retry (submit button will re-enable).
        throw Exception('Failed to join communities: $e. Please try again.');
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
        communityMemberships: createdCommunityIds, // <--- INJECT MEMBERSHIPS HERE
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
      
      if (mounted) {
        if (newCommunityNames.isNotEmpty) {
           await showDialog(
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
        context.go('/nearby'); // First time users land on Nearby to explore
      }
      

      
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
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
        leading: _currentStep != SetupStep.home 
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
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 24),
                child: Form(
                  key: _formKey,
                  child: _buildCurrentStep(theme),
                ),
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
      case SetupStep.home:
        return 'Original Hometown';
      case SetupStep.host:
        return 'Current Location';
      case SetupStep.profile:
        return 'Complete your profile';
    }
  }

  double _getProgress() {
    switch (_currentStep) {
      case SetupStep.home:
        return 0.33;
      case SetupStep.host:
        return 0.66;
      case SetupStep.profile:
        return 1.0;
    }
  }

  Widget _buildCurrentStep(ThemeData theme) {
    switch (_currentStep) {
      case SetupStep.home:
        return ProfileSetupHomeStep(
          searchController: _homeSearchController,
          focusNode: _homeFocusNode,
          predictions: _predictions,
          selectedLocation: _homeLocation,
          onSearchChanged: (v) => _onSearchChanged(v, true),
          onSelectPlace: (id) => _selectPlace(id, true),
          onNext: _goToNextStep,
        );
      case SetupStep.host:
        return ProfileSetupHostStep(
          searchController: _hostSearchController,
          focusNode: _hostFocusNode,
          predictions: _predictions,
          selectedLocation: _hostLocation,
          onSearchChanged: (v) => _onSearchChanged(v, false),
          onSelectPlace: (id) => _selectPlace(id, false),
          onNext: () {
             if (_hostLocation != null) {
                setState(() => _currentStep = SetupStep.profile);
             }
          },
          onBack: _goBack,
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
          onLocationToggleChanged: (v) => setState(() => _showCurrentLocationName = v),
          referralCodeController: _referralCodeController, // [NEW]
        );
    }
  }

  Future<bool> _verifyHostLocation() async {
    // 0. Preliminary check
    if (_hostLocation == null) return false;
    final targetCountryCode = _hostLocation!.countryCode;
    if (targetCountryCode == null) return true; // Can't verify if no code, let pass or strict? Let pass for now.

    setState(() => _isRequestingLocation = true);

    try {
      // 1. Check/Request Permission
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
           _showErrorDialog('Location Permission Required', 'We need your location to verify you are physically in ${_hostLocation!.country}.');
           return false;
        }
      }
      if (permission == LocationPermission.deniedForever) {
         _showErrorDialog('Location Permission Required', 'Please enable location permissions in settings to verify you are physically in ${_hostLocation!.country}.');
         return false;
      }

      // 2. Get Current Position
      final position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.medium);
      
      // 3. Reverse Geocode to get Country Code
      // We accept `geocoding` package usage here or use our places service wrapper if available for consistency.
      // Since we don't have `geocoding` imported yet, we should use the existing `_requestLocationPermission` logic 
      // which uses `googlePlacesServiceProvider.reverseGeocode`.
      
      final places = ref.read(googlePlacesServiceProvider);
      final locationData = await places.reverseGeocode(position.latitude, position.longitude);
      
      if (locationData == null) {
         _showErrorDialog('Verification Failed', 'Could not determine your current location. Please try again.');
         return false;
      }

      final currentCountryCode = locationData['countryCode'] as String?;
      
      // 4. Compare
      if (currentCountryCode == null) {
         _showErrorDialog('Verification Warning', 'Could not determine your current country code.');
         return false; // Fail safe
      }

      final normalizedTarget = targetCountryCode.toUpperCase().replaceAll(RegExp(r'[^A-Z]'), '').substring(0, 2);
      final normalizedCurrent = currentCountryCode.toUpperCase().replaceAll(RegExp(r'[^A-Z]'), '').substring(0, 2);

      if (normalizedCurrent != normalizedTarget) {
        _showErrorDialog(
          'Verification Failed', 
          'You must be physically located in ${_hostLocation!.country ?? "the target country"} to select it as your host location.\n\nDetected: $currentCountryCode, Target: $targetCountryCode'
        );
        return false;
      }

      return true;

    } catch (e) {
      debugPrint('Verification error: $e');
      _showErrorDialog('Verification Error', 'An error occurred while verifying your location: $e');
      return false;
    } finally {
      if (mounted) setState(() => _isRequestingLocation = false);
    }
  }

  void _showErrorDialog(String title, String content) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
      ),
    );
}
}
