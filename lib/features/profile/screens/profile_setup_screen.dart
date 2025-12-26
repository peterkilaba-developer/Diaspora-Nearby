import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:diaspora_nearby/services/google_places_service.dart';
import 'package:diaspora_nearby/utils/location_utils.dart';
import 'package:diaspora_nearby/models/profile_data.dart';
import 'package:diaspora_nearby/models/location.dart' as loc_model;
import 'package:flutter_google_places_sdk/flutter_google_places_sdk.dart';
import '../repository/profile_repository.dart';
import 'package:diaspora_nearby/features/auth/repository/auth_repository.dart';
import 'package:diaspora_nearby/router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:diaspora_nearby/services/community_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:diaspora_nearby/config/env.dart';
import 'package:diaspora_nearby/services/session_service.dart';

// googlePlacesServiceProvider moved to lib/services/google_places_service.dart

/// Setup step enum matching React's SetupStep type
enum SetupStep { home, host, profile }

/// Auto-capitalize first letter formatter
class CapitalizeFirstLetterFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.isEmpty) return newValue;
    return TextEditingValue(
      text: newValue.text[0].toUpperCase() + newValue.text.substring(1),
      selection: newValue.selection,
    );
  }
}

class ProfileSetupScreen extends ConsumerStatefulWidget {
  const ProfileSetupScreen({super.key});

  @override
  ConsumerState<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends ConsumerState<ProfileSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();

  
  // Current step in the flow
  SetupStep _currentStep = SetupStep.home;
  
  // Locations
  loc_model.UserLocation? _homeLocation;
  loc_model.UserLocation? _hostLocation;
  CurrentLocation? _currentLocation;
  
  // Profile Photo
  File? _profileImage;
  
  // UI State
  bool _isSubmitting = false;
  bool _isRequestingLocation = false;
  
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
            _hostLocation = loc;
            _hostComponents = components;
            _hostSearchController.text = loc.formattedAddress;
          }
        });
      }
    }
  }

  void _goToNextStep() {
    if (_currentStep == SetupStep.home && _homeLocation != null) {
      setState(() => _currentStep = SetupStep.host);
    }
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
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 80,
      );
      
      if (pickedFile != null) {
        setState(() {
          _profileImage = File(pickedFile.path);
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
      
      final uploadTask = await storageRef.putFile(_profileImage!);
      debugPrint('ð¸ Upload complete. Bytes transferred: ${uploadTask.bytesTransferred}');
      
      final downloadUrl = await storageRef.getDownloadURL();
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
      final homeParsed = parseLocationComponents(_homeLocation!.formattedAddress, _homeComponents ?? []);
      final hostParsed = parseLocationComponents(_hostLocation!.formattedAddress, _hostComponents ?? []);

      if (homeParsed == null || hostParsed == null) {
        throw Exception('Could not parse location');
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
      );

      // 4. Save to Firestore
      await ref.read(profileRepositoryProvider).saveUserProfile(user.uid, profile);

      // 5. Create Communities & Chats (Critical Step)
      // We do this BEFORE invalidating/navigating to ensure it succeeds
      List<String> createdCommunityIds = [];
      try {
        createdCommunityIds = await CommunityService().createCommunitiesAndChats(profile);
      } catch (e) {
        // If this fails, we must NOT proceed.
        // We report error and let user retry (submit button will re-enable).
        throw Exception('Failed to join communities: $e. Please try again.');
        return;
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
      );

      // 6. Update profile provider
      ref.read(userProfileProvider.notifier).updateProfile(completeProfile);

      // 7. Mark session as complete (CRITICAL for router fallback)
      await ref.read(sessionServiceProvider).updateProfileComplete(true);
      
      // Mark as returning user for future sessions (so next time they go to Chats)
      await ref.read(sessionServiceProvider).setReturningUser(true);
      
      if (mounted) {
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
        return _buildHomeStep(theme);
      case SetupStep.host:
        return _buildHostStep(theme);
      case SetupStep.profile:
        return _buildProfileStep(theme);
    }
  }

  Widget _buildHomeStep(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Always show icon and description
        const Icon(LucideIcons.home, size: 64, color: Colors.orange),
        const SizedBox(height: 16),
        Text(
          'Where are you from?',
          style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          'This helps us connect you with others from your home country',
          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 32),
        
        TextFormField(
          controller: _homeSearchController,
          focusNode: _homeFocusNode,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            hintText: 'Search your hometown',
            prefixIcon: const Icon(LucideIcons.search),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            filled: true,
          ),
          onChanged: (v) => _onSearchChanged(v, true),
        ),
        
        if (_predictions.isNotEmpty)
          _buildSuggestionsList(true),
        
        // Inline selection button (only show when input has text and location selected)
        if (_homeLocation != null && _predictions.isEmpty && _homeSearchController.text.isNotEmpty) ...[
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: _goToNextStep,
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.green,
              side: const BorderSide(color: Colors.green, width: 2),
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(LucideIcons.check, size: 20),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    _homeLocation!.formattedAddress,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(LucideIcons.arrowRight, size: 20),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildHostStep(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Always show icon and description
        const Icon(LucideIcons.mapPin, size: 64, color: Colors.blue),
        const SizedBox(height: 16),
        Text(
          'Where do you live now?',
          style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          'This helps you find nearby people from your home country',
          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 32),
        
        TextFormField(
          controller: _hostSearchController,
          focusNode: _hostFocusNode,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            hintText: 'Search your current city',
            prefixIcon: const Icon(LucideIcons.search),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            filled: true,
          ),
          onChanged: (v) => _onSearchChanged(v, false),
        ),
        
        if (_predictions.isNotEmpty)
          _buildSuggestionsList(false),
        
        // Inline selection button (only show when input has text and location selected)
        if (_hostLocation != null && _predictions.isEmpty && _hostSearchController.text.isNotEmpty) ...[
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: () => setState(() => _currentStep = SetupStep.profile),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.green,
              side: const BorderSide(color: Colors.green, width: 2),
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(LucideIcons.check, size: 20),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    _hostLocation!.formattedAddress,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(LucideIcons.arrowRight, size: 20),
              ],
            ),
          ),
        ],
        
        // Back button
        const SizedBox(height: 16),
        TextButton.icon(
          onPressed: () => setState(() => _currentStep = SetupStep.home),
          icon: const Icon(LucideIcons.arrowLeft, size: 18),
          label: const Text('Back to Home Location'),
          style: TextButton.styleFrom(
            foregroundColor: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _buildProfileStep(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Profile Photo
        Center(
          child: GestureDetector(
            onTap: _pickImage,
            child: Stack(
              children: [
                CircleAvatar(
                  radius: 60,
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                  backgroundImage: _profileImage != null ? FileImage(_profileImage!) : null,
                  child: _profileImage == null
                    ? Icon(LucideIcons.user, size: 48, color: theme.colorScheme.onSurfaceVariant)
                    : null,
                ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(LucideIcons.camera, size: 20, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Tap to add photo',
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 32),
        
        // Name Fields with auto-capitalize
        TextFormField(
          controller: _firstNameController,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            labelText: 'First Name',
            prefixIcon: const Icon(LucideIcons.user),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            filled: true,
          ),
          inputFormatters: [CapitalizeFirstLetterFormatter()],
          validator: (v) => v?.isEmpty == true ? 'Required' : null,
        ),
        const SizedBox(height: 16),
        
        TextFormField(
          controller: _lastNameController,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            labelText: 'Last Name',
            prefixIcon: const Icon(LucideIcons.user),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            filled: true,
          ),
          inputFormatters: [CapitalizeFirstLetterFormatter()],
          validator: (v) => v?.isEmpty == true ? 'Required' : null,
        ),
        
        const SizedBox(height: 16),


        
        const SizedBox(height: 24),
        
        // Location summary
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  children: [
                    const Icon(LucideIcons.home, size: 20, color: Colors.orange),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _homeLocation?.formattedAddress ?? 'Home not set',
                        style: theme.textTheme.bodySmall,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(LucideIcons.mapPin, size: 20, color: Colors.blue),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _hostLocation?.formattedAddress ?? 'Current location not set',
                        style: theme.textTheme.bodySmall,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        
        // Inline Complete button - only shows when names and photo are filled
        if (_firstNameController.text.trim().isNotEmpty && 
            _lastNameController.text.trim().isNotEmpty && 
            _profileImage != null) ...[
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _isSubmitting ? null : _submit,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: _isSubmitting
                ? const SizedBox(
                    height: 24,
                    width: 24,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                  )
                : const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(LucideIcons.check, size: 20),
                      SizedBox(width: 8),
                      Text(
                        'Complete Setup',
                        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                      ),
                    ],
                  ),
          ),
        ],
        
        // Back button
        const SizedBox(height: 16),
        TextButton.icon(
          onPressed: () => setState(() => _currentStep = SetupStep.host),
          icon: const Icon(LucideIcons.arrowLeft, size: 18),
          label: const Text('Back to Current Location'),
          style: TextButton.styleFrom(
            foregroundColor: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _buildBottomButton(ThemeData theme) {
    // Determine if we should show selected location
    final showHomeSelection = _currentStep == SetupStep.home && _homeLocation != null;
    final showHostSelection = _currentStep == SetupStep.host && _hostLocation != null;
    final selectedAddress = showHomeSelection 
        ? _homeLocation!.formattedAddress 
        : showHostSelection 
            ? _hostLocation!.formattedAddress 
            : null;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 56,
          child: ElevatedButton(
            onPressed: _getButtonAction(),
            style: ElevatedButton.styleFrom(
              backgroundColor: selectedAddress != null 
                  ? Colors.green 
                  : theme.colorScheme.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: _isSubmitting
                ? const CircularProgressIndicator(color: Colors.white)
                : selectedAddress != null
                    ? Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(LucideIcons.check, size: 20),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              selectedAddress,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Icon(LucideIcons.arrowRight, size: 20),
                        ],
                      )
                    : Text(_getButtonText()),
          ),
        ),
      ),
    );
  }

  String _getButtonText() {
    switch (_currentStep) {
      case SetupStep.home:
        return 'Next';
      case SetupStep.host:
        return 'Next';
      case SetupStep.profile:
        return 'Complete Setup';
    }
  }

  VoidCallback? _getButtonAction() {
    switch (_currentStep) {
      case SetupStep.home:
        return _homeLocation != null ? _goToNextStep : null;
      case SetupStep.host:
        return _hostLocation != null ? () => setState(() => _currentStep = SetupStep.profile) : null;
      case SetupStep.profile:
        return _isSubmitting ? null : _submit;
    }
  }

  Widget _buildSuggestionsList(bool isHome) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      constraints: const BoxConstraints(maxHeight: 200),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListView.builder(
        shrinkWrap: true,
        itemCount: _predictions.length,
        itemBuilder: (context, index) {
          final p = _predictions[index];
          return ListTile(
            leading: const Icon(LucideIcons.mapPin),
            title: Text(p.fullText),
            onTap: () => _selectPlace(p.placeId, isHome),
          );
        },
      ),
    );
  }
}

class ParsedLocation {
  final String formattedAddress;
  final String? countryCode;
  final String? country;
  final String? city;
  final String? state;

  ParsedLocation({
    required this.formattedAddress,
    this.countryCode,
    this.country,
    this.city,
    this.state,
  });
}

ParsedLocation? parseLocationComponents(String formattedAddress, List<AddressComponent> components) {
  String? countryCode;
  String? country;
  String? city;
  String? state;

  for (final component in components) {
    final types = component.types;
    if (types.contains('country')) {
      country = component.name;
      countryCode = component.shortName;
    } else if (types.contains('locality')) {
      city = component.name;
    } else if (types.contains('administrative_area_level_1')) {
      state = component.name;
    }
  }

  return ParsedLocation(
    formattedAddress: formattedAddress,
    countryCode: countryCode,
    country: country,
    city: city,
    state: state,
  );
}
