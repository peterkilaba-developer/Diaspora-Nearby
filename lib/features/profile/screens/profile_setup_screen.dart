import 'dart:async';
import 'dart:ui';
import 'package:universal_io/io.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
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

  // Current step in the flow
  SetupStep _currentStep = SetupStep.home;

  // Locations
  loc_model.UserLocation? _homeLocation;
  loc_model.UserLocation? _hostLocation;
  CurrentLocation? _currentLocation;

  // Profile Photo
  XFile? _profileImage;
  String? _uploadedProfileImageUrl;
  Future<String?>? _imageUploadFuture;

  // UI State
  final bool _isSubmitting = false;
  bool _showCurrentLocationName = true;

  // Places Search (isolated per step to prevent cross-step leakage)
  List<AutocompletePrediction> _homePredictions = [];
  List<AutocompletePrediction> _hostPredictions = [];
  Timer? _homeSearchDebounce;
  Timer? _hostSearchDebounce;
  int _homeSearchSeq = 0;
  int _hostSearchSeq = 0;
  final _homeSearchController = TextEditingController();
  final _hostSearchController = TextEditingController();

  // Focus tracking for hiding decorations
  final _homeFocusNode = FocusNode();
  final _hostFocusNode = FocusNode();

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

    // Preload pending referral code captured from clicked invite link
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(ref.read(pendingReferralCodeProvider.notifier).getOrLoad());
    });
  }

  void _onNameChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _homeSearchDebounce?.cancel();
    _hostSearchDebounce?.cancel();
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
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (mounted) {
          await showDialog(
            context: context,
            barrierDismissible: false,
            builder: (context) => BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: AlertDialog(
                insetPadding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 24,
                ),
                title: const Text('Location Required'),
                content: const Text(
                  'We need your location to connect you with nearby diaspora members. This is required to complete signup.',
                ),
                actions: [
                  TextButton(
                    onPressed: () {
                      Navigator.pop(context);
                      Geolocator.openAppSettings();
                      _requestLocationPermission();
                    },
                    child: const Text('Open Settings'),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      _requestLocationPermission();
                    },
                    child: const Text('Grant Permission'),
                  ),
                ],
              ),
            ),
          );
        }
        return;
      }

      if (permission == LocationPermission.whileInUse ||
          permission == LocationPermission.always) {
        // [PERF] Try instant last known position first (0ms) so _currentLocation is ready immediately
        final lastKnown = await Geolocator.getLastKnownPosition();
        if (lastKnown != null && mounted) {
          setState(() {
            _currentLocation = CurrentLocation(
              formattedAddress: '${lastKnown.latitude}, ${lastKnown.longitude}',
              placeId: '',
              geometry: loc_model.UserLocationGeometry(
                location: loc_model.UserLocationCoordinates(
                  lat: lastKnown.latitude,
                  lng: lastKnown.longitude,
                ),
              ),
              timestamp: DateTime.now().millisecondsSinceEpoch,
            );
          });
        }

        // Refresh position & reverse geocode in background
        final position =
            lastKnown ??
            await Geolocator.getCurrentPosition(
              locationSettings: const LocationSettings(
                accuracy: LocationAccuracy.medium,
              ),
            );

        final places = ref.read(googlePlacesServiceProvider);
        final locationData = await places.reverseGeocode(
          position.latitude,
          position.longitude,
        );

        if (!mounted) return;
        if (locationData != null) {
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
          });
        } else {
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
    }
  }

  void _onSearchChanged(String input, bool isHome) {
    final trimmed = input.trim();
    if (isHome) {
      _homeSearchDebounce?.cancel();
      final seq = ++_homeSearchSeq;
      if (trimmed.isEmpty) {
        setState(() {
          _homePredictions = [];
          _homeLocation = null;
        });
        return;
      }
      if (_homeLocation != null &&
          trimmed != _homeLocation!.formattedAddress.trim()) {
        setState(() => _homeLocation = null);
      }
      _homeSearchDebounce = Timer(const Duration(milliseconds: 80), () async {
        if (!mounted ||
            _currentStep != SetupStep.home ||
            seq != _homeSearchSeq) {
          return;
        }
        final places = ref.read(googlePlacesServiceProvider);
        final results = await places.autocomplete(trimmed);
        if (!mounted ||
            _currentStep != SetupStep.home ||
            seq != _homeSearchSeq ||
            _homeSearchController.text.trim().isEmpty) {
          return;
        }
        setState(() {
          _homePredictions = results;
        });
      });
    } else {
      _hostSearchDebounce?.cancel();
      final seq = ++_hostSearchSeq;
      if (trimmed.isEmpty) {
        setState(() {
          _hostPredictions = [];
          _hostLocation = null;
        });
        return;
      }
      if (_hostLocation != null &&
          trimmed != _hostLocation!.formattedAddress.trim()) {
        setState(() => _hostLocation = null);
      }
      _hostSearchDebounce = Timer(const Duration(milliseconds: 80), () async {
        if (!mounted ||
            _currentStep != SetupStep.host ||
            seq != _hostSearchSeq) {
          return;
        }
        final places = ref.read(googlePlacesServiceProvider);
        final results = await places.autocomplete(trimmed);
        if (!mounted ||
            _currentStep != SetupStep.host ||
            seq != _hostSearchSeq ||
            _hostSearchController.text.trim().isEmpty) {
          return;
        }
        setState(() {
          _hostPredictions = results;
        });
      });
    }
  }

  Future<void> _selectPlace(String placeId, bool isHome) async {
    final predictionsList = isHome ? _homePredictions : _hostPredictions;
    final tappedPrediction = predictionsList
        .where((p) => p.placeId == placeId)
        .firstOrNull;
    final optimisticText = tappedPrediction != null
        ? (tappedPrediction.fullText.isNotEmpty
              ? tappedPrediction.fullText
              : tappedPrediction.primaryText)
        : null;

    if (isHome) {
      _homeSearchDebounce?.cancel();
      _homeSearchSeq++;
      setState(() {
        _homePredictions = [];
        if (optimisticText != null && optimisticText.isNotEmpty) {
          _homeSearchController.text = optimisticText;
          _homeLocation = loc_model.UserLocation(
            formattedAddress: optimisticText,
            placeId: placeId,
            city: tappedPrediction?.primaryText,
          );
        }
      });
      _homeFocusNode.unfocus();
    } else {
      _hostSearchDebounce?.cancel();
      _hostSearchSeq++;
      setState(() {
        _hostPredictions = [];
        if (optimisticText != null && optimisticText.isNotEmpty) {
          _hostSearchController.text = optimisticText;
        }
      });
      _hostFocusNode.unfocus();
    }

    final places = ref.read(googlePlacesServiceProvider);

    if (isHome) {
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
            formattedAddress: place.address ?? optimisticText ?? '',
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
    } else {
      // [PERF] Fetch place details and verify GPS in parallel
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
            formattedAddress: place.address ?? optimisticText ?? '',
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
          await _verifySelectedHostLocation(loc, components);
        }
      }
    }
  }

  Future<void> _verifySelectedHostLocation(
    loc_model.UserLocation selected,
    List<AddressComponent> components,
  ) async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        _showErrorDialog(
          'Location Required',
          'We need your GPS location to verify you are currently in this city.',
        );
        return;
      }

      double? currentLat;
      double? currentLng;

      if (_currentLocation != null) {
        currentLat = _currentLocation!.geometry.location.lat;
        currentLng = _currentLocation!.geometry.location.lng;
      } else {
        final lastKnown = await Geolocator.getLastKnownPosition();
        final position =
            lastKnown ??
            await Geolocator.getCurrentPosition(
              locationSettings: const LocationSettings(
                accuracy: LocationAccuracy.medium,
              ),
            );
        currentLat = position.latitude;
        currentLng = position.longitude;
      }

      double? targetLat = selected.geometry?.location.lat;
      double? targetLng = selected.geometry?.location.lng;

      if (targetLat == null || targetLng == null) {
        _showErrorDialog(
          'Verification Failed',
          'Could not determine coordinates of selected city.',
        );
        return;
      }

      final distanceKm = calculateDistance(
        currentLat,
        currentLng,
        targetLat,
        targetLng,
      );

      const double maxDistanceKm = 50.0;

      if (distanceKm > maxDistanceKm) {
        _showErrorDialog(
          'Location Mismatch',
          'You are ${distanceKm.round()}km away from ${selected.city}. You must be physically located in your host city to select it.',
        );

        setState(() {
          _hostPredictions = [];
          _hostLocation = null;
          _hostSearchController.clear();
        });
        return;
      }

      if (mounted) {
        setState(() {
          _hostPredictions = [];
          _hostLocation = selected;
          _hostComponents = components;
          _hostSearchController.text = selected.formattedAddress;
        });
      }
    } catch (e) {
      debugPrint('Verification error: $e');
      _showErrorDialog('Error', 'Could not verify location: $e');
    }
  }

  void _goToNextStep() {
    _homeSearchDebounce?.cancel();
    _hostSearchDebounce?.cancel();
    _homeSearchSeq++;
    _hostSearchSeq++;
    _homeFocusNode.unfocus();
    setState(() {
      _homePredictions = [];
      _hostPredictions = [];
      _currentStep = SetupStep.host;
    });
  }

  void _goBack() {
    _homeSearchDebounce?.cancel();
    _hostSearchDebounce?.cancel();
    _homeSearchSeq++;
    _hostSearchSeq++;
    FocusScope.of(context).unfocus();
    if (_currentStep == SetupStep.home) {
      context.go('/permissions?review=1');
    } else if (_currentStep == SetupStep.host) {
      setState(() {
        _homePredictions = [];
        _hostPredictions = [];
        _currentStep = SetupStep.home;
      });
    } else if (_currentStep == SetupStep.profile) {
      setState(() {
        _homePredictions = [];
        _hostPredictions = [];
        _currentStep = SetupStep.host;
      });
    }
  }

  /// Pick profile image from camera or gallery and pre-upload in the background
  Future<void> _pickImage() async {
    final picker = ImagePicker();

    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: SafeArea(
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
          _uploadedProfileImageUrl = null;
        });

        // [PERF] Start uploading the photo immediately in the background
        // so it is already uploaded by the time the user finishes typing their name!
        final user = ref.read(authRepositoryProvider).currentUser;
        if (user != null) {
          _imageUploadFuture = _uploadProfileImage(user.uid).then((url) {
            if (url != null && url.isNotEmpty) {
              _uploadedProfileImageUrl = url;
            }
            return url;
          });
        }
      }
    } catch (e) {
      debugPrint('Error picking image: $e');
    }
  }

  /// Upload profile image to Firebase Storage
  Future<String?> _uploadProfileImage(String userId) async {
    final storageRef = FirebaseStorage.instance
        .ref()
        .child('profile_photos')
        .child(userId)
        .child('profile.jpg');

    if (_profileImage == null) {
      try {
        return await storageRef.getDownloadURL();
      } catch (_) {
        return null;
      }
    }

    try {
      UploadTask uploadTask;
      final metadata = SettableMetadata(contentType: 'image/jpeg');

      if (kIsWeb) {
        final bytes = await _profileImage!.readAsBytes();
        uploadTask = storageRef.putData(bytes, metadata);
      } else {
        final file = File(_profileImage!.path);
        if (!await file.exists()) {
          try {
            final existingUrl = await storageRef.getDownloadURL();
            if (existingUrl.isNotEmpty) return existingUrl;
          } catch (_) {}
          throw Exception('Selected photo file is no longer available.');
        }
        uploadTask = storageRef.putFile(file, metadata);
      }
      final snapshot = await uploadTask;
      final downloadUrl = await snapshot.ref.getDownloadURL();
      return downloadUrl;
    } catch (e) {
      debugPrint('Error uploading image: $e');
      try {
        final existingUrl = await storageRef.getDownloadURL();
        if (existingUrl.isNotEmpty) {
          return existingUrl;
        }
      } catch (_) {}
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

    final user = ref.read(authRepositoryProvider).currentUser;
    if (user == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('No user found')));
      return;
    }

    // 1. Parse Locations synchronously
    LocationParsed? homeParsed = parseLocationComponents(
      _homeLocation!.formattedAddress,
      _homeComponents ?? [],
    );
    LocationParsed? hostParsed = parseLocationComponents(
      _hostLocation!.formattedAddress,
      _hostComponents ?? [],
    );

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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not parse location details. Please try selecting the location again.',
          ),
        ),
      );
      return;
    }

    // Compute provisional community IDs synchronously so router sees non-empty memberships immediately
    final expectedCommunityIds = <String>{
      generateCommunityId(
        locationType: 'home',
        type: 'country',
        location: homeParsed,
        homeCountryCode: homeParsed.countryCode,
      ),
      generateCommunityId(
        locationType: 'host',
        type: 'country',
        location: hostParsed,
        homeCountryCode: homeParsed.countryCode,
      ),
      if (hostParsed.city != null && hostParsed.city!.isNotEmpty)
        generateCommunityId(
          locationType: 'host',
          type: 'city',
          location: hostParsed,
          homeCountryCode: homeParsed.countryCode,
        ),
    }.where((id) => id.isNotEmpty).toList();

    final provisionalImageUrl = _uploadedProfileImageUrl ?? _profileImage!.path;
    final firstName = _firstNameController.text.trim();
    final lastName = _lastNameController.text.trim();
    final pendingReferralCode = (ref.read(pendingReferralCodeProvider) ?? '')
        .trim();
    final referralNotifier = ref.read(pendingReferralCodeProvider.notifier);

    final provisionalProfile = ProfileData(
      uid: user.uid,
      firstName: firstName,
      lastName: lastName,
      phone: user.phoneNumber ?? '',
      profileImage: provisionalImageUrl,
      homeLocation: _homeLocation!,
      hostLocation: _hostLocation!,
      homeCountryCode: homeParsed.countryCode,
      hostCountryCode: hostParsed.countryCode,
      homeCountry: homeParsed.country,
      hostCountry: hostParsed.country,
      currentLocation: _currentLocation,
      communityMemberships: expectedCommunityIds,
      isBanned: false,
      advertReportCount: 0,
      yearsInHostCountry: null,
      showCurrentLocationName: _showCurrentLocationName,
    );

    final profileRepo = ref.read(profileRepositoryProvider);
    final profileNotifier = ref.read(userProfileProvider.notifier);
    final sessionService = ref.read(sessionServiceProvider);
    final communityService = ref.read(communityServiceProvider);
    final pointsService = ref.read(pointsServiceProvider);

    // [PERF] Update caches, session flags, and navigate in 0ms on frame 0!
    profileRepo.cacheProfile(user.uid, provisionalProfile);
    profileNotifier.updateProfile(provisionalProfile);
    unawaited(sessionService.updateProfileComplete(true));
    unawaited(sessionService.setReturningUser(true));

    if (context.mounted) {
      context.go('/nearby');
    }

    // Complete image upload, Firestore save, community creation, and points initialization in the background
    unawaited(() async {
      try {
        final referralCode = pendingReferralCode.isNotEmpty
            ? pendingReferralCode
            : ((await referralNotifier.getOrLoad()) ?? '').trim();
        if (referralCode.isNotEmpty) {
          unawaited(referralNotifier.set(null));
        }

        String finalImageUrl = _uploadedProfileImageUrl ?? '';
        if (finalImageUrl.isEmpty) {
          final uploaded = await (_imageUploadFuture ??
              _uploadProfileImage(user.uid));
          if (uploaded != null && uploaded.isNotEmpty) {
            finalImageUrl = uploaded;
          }
        }

        final profileToSave = provisionalProfile.copyWith(
          profileImage: finalImageUrl.isNotEmpty
              ? finalImageUrl
              : provisionalImageUrl,
        );

        await profileRepo.saveUserProfile(user.uid, profileToSave);

        List<String> createdCommunityIds = expectedCommunityIds;
        try {
          final ids = await communityService.createCommunitiesAndChats(
            profileToSave,
          );
          if (ids.isNotEmpty) {
            createdCommunityIds = ids;
          }
        } catch (e) {
          debugPrint('Background community creation error: $e');
        }

        final completeProfile = profileToSave.copyWith(
          communityMemberships: createdCommunityIds,
        );
        profileRepo.cacheProfile(user.uid, completeProfile);
        profileNotifier.updateProfile(completeProfile);

        // Run points initialization (which also creates the user's single signup referral code) and referral processing in parallel
        await Future.wait([
          pointsService.initializeUserPoints(user.uid).catchError((Object e) {
            debugPrint('Error initializing points: $e');
          }),
          if (referralCode.isNotEmpty)
            pointsService
                .processReferral(referralCode, user.uid)
                .then<void>((_) {})
                .catchError((Object e) {
                  debugPrint('Error processing referral: $e');
                }),
        ]);
      } catch (e) {
        debugPrint('Error completing background profile setup: $e');
      }
    }());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft),
          onPressed: _goBack,
        ),
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
          predictions: _homePredictions,
          selectedLocation: _homeLocation,
          onSearchChanged: (v) => _onSearchChanged(v, true),
          onSelectPlace: (id) => _selectPlace(id, true),
          onNext: _goToNextStep,
          onBack: _goBack,
        );
      case SetupStep.host:
        return ProfileSetupHostStep(
          searchController: _hostSearchController,
          focusNode: _hostFocusNode,
          predictions: _hostPredictions,
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
          onLocationToggleChanged: (v) =>
              setState(() => _showCurrentLocationName = v),
        );
    }
  }

  void _showErrorDialog(String title, String content) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: AlertDialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 24),
          title: Text(title),
          content: Text(content),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      ),
    );
  }
}
