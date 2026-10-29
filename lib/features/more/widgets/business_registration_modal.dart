import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:go_router/go_router.dart';
import 'package:universal_io/io.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:diaspora_nearby/features/profile/repository/profile_repository.dart';
import 'package:diaspora_nearby/features/auth/repository/auth_repository.dart';
import 'package:diaspora_nearby/core/services/google_places_service.dart';
import 'package:diaspora_nearby/features/shared/models/google_places_models.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:diaspora_nearby/features/organization/repository/organization_repository.dart';
import 'package:diaspora_nearby/features/community/repository/community_repository.dart';
import 'package:diaspora_nearby/theme/app_theme.dart';

class BusinessRegistrationModal extends ConsumerStatefulWidget {
  final String? communityId; // [NEW] optional community context
  const BusinessRegistrationModal({super.key, this.communityId});

  @override
  ConsumerState<BusinessRegistrationModal> createState() =>
      _BusinessRegistrationModalState();
}

class _BusinessRegistrationModalState
    extends ConsumerState<BusinessRegistrationModal> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descController = TextEditingController();
  final _phoneController = TextEditingController();
  final _websiteController = TextEditingController();
  final _locationController = TextEditingController();

  XFile? _logoImage;
  Future<String?>? _logoUploadFuture;
  final ImagePicker _picker = ImagePicker();
  bool _logoError = false;

  // Location state
  List<AutocompletePrediction> _predictions = [];
  bool _showPredictions = false;
  double? _locationLat;
  double? _locationLng;
  String? _locationCity;
  String? _locationState;
  String? _locationCountry;
  bool _isLocating = false;

  // Name predictions
  List<AutocompletePrediction> _namePredictions = [];
  bool _showNamePredictions = false;
  Map<String, dynamic>? _selectedRichData;

  Future<void> _pickImage() async {
    final picked = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 85,
    );
    if (picked != null) {
      setState(() => _logoImage = picked);
      final user = ref.read(authRepositoryProvider).currentUser;
      if (user != null) {
        _logoUploadFuture = _uploadLogoInBackground(user.uid, picked);
      }
    }
  }

  Future<String?> _uploadLogoInBackground(String uid, XFile file) async {
    try {
      final storageRef = FirebaseStorage.instance
          .ref()
          .child('profile_photos')
          .child(uid)
          .child('business_logos')
          .child('${DateTime.now().millisecondsSinceEpoch}.jpg');

      final metadata = SettableMetadata(
        cacheControl: 'public, max-age=31536000',
        contentType: 'image/jpeg',
      );
      if (kIsWeb) {
        final bytes = await file.readAsBytes();
        await storageRef.putData(bytes, metadata);
      } else {
        await storageRef.putFile(File(file.path), metadata);
      }
      return await storageRef.getDownloadURL();
    } catch (e) {
      debugPrint('Background logo upload error: $e');
      return null;
    }
  }

  String? _selectedOrgType;
  final _orgTypes = [
    'Business Organization (BO)',
    'Diaspora Organization (DO)',
    'Political Organization (PO)',
    'Faith Organization (FO)',
    'Non Governmental Organization (NGO)',
    'Non-Profit Organization (NPO)',
    'Government Organization (GO)',
  ];

  void _updateTitleOptions(String orgType) {
    setState(() {
      _titleOptions =
          _orgTypeTitles[orgType] ??
          ['Super Admin', 'Admin', 'Director', 'Leader'];
      // Default to first option
      if (_titleOptions.isNotEmpty) {
        _selectedTitle = _titleOptions.first;
      } else {
        _selectedTitle = null;
      }
    });
  }

  final _orgTypeTitles = {
    'Business Organization (BO)': [
      'Chief Executive Officer (CEO)',
      'Managing Director',
      'President',
      'Founder',
      'Owner',
      'General Manager',
      'Director',
    ],
    'Diaspora Organization (DO)': [
      'President',
      'Chairman',
      'Chairperson',
      'Community Leader',
      'Coordinator',
      'Secretary',
      'Director',
    ],
    'Political Organization (PO)': [
      'Party Leader',
      'Chairman',
      'Secretary General',
      'President',
      'Spokesperson',
      'Director',
    ],
    'Faith Organization (FO)': [
      'Reverend',
      'Pastor',
      'Minister',
      'Bishop',
      'Priest',
      'Sheikh',
      'Imam',
      'Rabbi',
      'Deacon',
      'Prophet',
      'Apostle',
      'Leader',
    ],
    'Non Governmental Organization (NGO)': [
      'Executive Director',
      'Country Director',
      'Founder',
      'Program Director',
      'Coordinator',
      'Director',
    ],
    'Non-Profit Organization (NPO)': [
      'Executive Director',
      'President',
      'Founder',
      'Board Chair',
      'Program Director',
      'Coordinator',
      'Director',
    ],
    'Government Organization (GO)': [
      'Ambassador',
      'Consular',
      'High Commissioner',
      'Minister',
      'Director General',
      'Governor',
      'Mayor',
      'Commissioner',
    ],
  };

  /* Default fallback titles */
  List<String> _titleOptions = [
    'Super Admin',
    'Admin',
    'Director',
    'Manager',
    'Leader',
  ];
  String? _selectedTitle;

  final bool _isLoading = false;

  void _onLocationChanged(String input) async {
    if (input.isEmpty) {
      setState(() {
        _predictions = [];
        _showPredictions = false;
      });
      return;
    }

    final places = ref.read(googlePlacesServiceProvider);
    final results = await places.autocomplete(input);
    if (mounted) {
      setState(() {
        _predictions = results;
        _showPredictions = results.isNotEmpty;
      });
    }
  }

  Future<void> _selectPlace(AutocompletePrediction prediction) async {
    // Optimistically update text field and close prediction list in 0ms
    setState(() {
      _locationController.text = prediction.fullText;
      _predictions = [];
      _showPredictions = false;
    });

    final places = ref.read(googlePlacesServiceProvider);
    final response = await places.getPlaceDetails(prediction.placeId);
    final place = response?.place;

    if (place != null && mounted) {
      _populateLocation(place, prediction.fullText);
    }
  }

  void _populateLocation(Place place, String? fullAddress) {
    if (!mounted) return;

    String? city, state, country;
    final components = place.addressComponents ?? [];

    for (final component in components) {
      final types = component.types;
      if (types.contains('locality')) {
        city = component.name;
      } else if (types.contains('administrative_area_level_1')) {
        state = component.name;
      } else if (types.contains('country')) {
        country = component.name;
      }
    }

    setState(() {
      _locationController.text = fullAddress ?? place.address ?? '';
      _locationLat = place.latLng?.lat;
      _locationLng = place.latLng?.lng;
      _locationCity = city;
      _locationState = state;
      _locationCountry = country;
      _predictions = [];
      _showPredictions = false;
    });
  }

  // Verification Lock Flags
  bool _isVerifiedBusiness = false; // If true, a business was selected from API
  bool _isNameLocked = false;
  bool _isLocationLocked = false;
  bool _isPhoneLocked = false;
  bool _isWebsiteLocked = false;

  void _onNameChanged(String input) async {
    if (_isVerifiedBusiness) return; // Prevent search if locked

    if (input.isEmpty) {
      setState(() {
        _namePredictions = [];
        _showNamePredictions = false;
      });
      return;
    }

    final places = ref.read(googlePlacesServiceProvider);
    // Use VENUES filter to strictly exclude cities/regions
    final results = await places.autocomplete(
      input,
      filter: PlaceTypeFilter.VENUES,
    );
    if (mounted) {
      setState(() {
        _namePredictions = results;
        _showNamePredictions = results.isNotEmpty;
      });
    }
  }

  void _resetSelection() {
    setState(() {
      _isVerifiedBusiness = false;
      _isNameLocked = false;
      _isLocationLocked = false;
      _isPhoneLocked = false;
      _isWebsiteLocked = false;
      _selectedRichData = null;

      _nameController.clear();
      _phoneController.clear();
      _websiteController.clear();
      _locationController.clear();
      _selectedOrgType = null;
      _locationLat = null;
      _locationLng = null;
    });
  }

  Future<void> _selectBusiness(AutocompletePrediction prediction) async {
    // Optimistically update business name and hide predictions in 0ms
    setState(() {
      _isVerifiedBusiness = true;
      _nameController.text = prediction.primaryText;
      _isNameLocked = true;
      _namePredictions = [];
      _showNamePredictions = false;
      if (prediction.secondaryText.isNotEmpty) {
        _locationController.text = prediction.secondaryText;
      }
    });

    final places = ref.read(googlePlacesServiceProvider);
    final response = await places.getPlaceDetails(prediction.placeId);
    final place = response?.place;

    if (place != null && mounted) {
      // Map Google Place types to our Org Types
      final googleTypes = place.types ?? [];
      String? matchedType;

      if (googleTypes.contains(PlaceType.RESTAURANT) ||
          googleTypes.contains(PlaceType.STORE) ||
          googleTypes.contains(PlaceType.CAFE) ||
          googleTypes.contains(PlaceType.BANK) ||
          googleTypes.contains(PlaceType.POST_OFFICE)) {
        matchedType = 'Business Organization (BO)';
      } else if (googleTypes.contains(PlaceType.CHURCH) ||
          googleTypes.contains(PlaceType.HINDU_TEMPLE) ||
          googleTypes.contains(PlaceType.MOSQUE) ||
          googleTypes.contains(PlaceType.SYNAGOGUE)) {
        matchedType = 'Faith Organization (FO)';
      } else if (googleTypes.contains(PlaceType.CITY_HALL) ||
          googleTypes.contains(PlaceType.LOCAL_GOVERNMENT_OFFICE) ||
          googleTypes.contains(PlaceType.COURTHOUSE)) {
        matchedType = 'Government Organization (GO)';
      }

      setState(() {
        // Also populate phone if available
        if (place.phoneNumber != null) {
          _phoneController.text = place.phoneNumber!;
          _isPhoneLocked = true;
        }

        // Populate website if available
        if (place.websiteUri != null) {
          _websiteController.text = place.websiteUri.toString();
          _isWebsiteLocked = true;
        }

        // Set matched type if found
        if (matchedType != null) {
          _selectedOrgType = matchedType;
          _updateTitleOptions(matchedType);
        }

        // Capture Rich Data
        _selectedRichData = {
          if (place.rating != null) 'rating': place.rating,
          if (place.userRatingsTotal != null)
            'userRatingsTotal': place.userRatingsTotal,
          if (place.openingHours != null) 'openingHours': place.openingHours,
          if (place.photoMetadatas != null) 'photos': place.photoMetadatas,
          if (place.priceLevel != null) 'priceLevel': place.priceLevel,
          if (place.editorialSummary != null)
            'editorialSummary': place.editorialSummary,
        };

        // Smart Description Population
        if (place.editorialSummary != null &&
            place.editorialSummary!.isNotEmpty) {
          _descController.text = place.editorialSummary!;
        } else {
          final type = matchedType != null
              ? matchedType.split(' (').first
              : (prediction.secondaryText.isNotEmpty
                    ? prediction.secondaryText
                    : 'Organization');

          String location = 'Area';
          final components = place.addressComponents ?? [];
          for (final c in components) {
            if (c.types.contains('locality')) location = c.name;
          }
          if (location == 'Area') {
            location = place.address?.split(',').first ?? 'Area';
          }

          _descController.text = 'A $type in $location.';
        }
      });

      // Auto-populate location from the business place
      _populateLocation(place, prediction.fullText);
      setState(() {
        _isLocationLocked = true;
      });
    }
  }

  Future<void> _useCurrentLocation() async {
    setState(() => _isLocating = true);
    try {
      bool serviceEnabled;
      LocationPermission permission;

      serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) throw Exception('Location services are disabled.');

      permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          throw Exception('Location permissions are denied');
        }
      }

      if (permission == LocationPermission.deniedForever) {
        throw Exception('Location permissions are permanently denied');
      }

      final position =
          await Geolocator.getLastKnownPosition() ??
          await Geolocator.getCurrentPosition();

      if (mounted) {
        setState(() {
          _locationLat = position.latitude;
          _locationLng = position.longitude;
        });
      }

      final placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );

      if (placemarks.isNotEmpty && mounted) {
        final pm = placemarks.first;
        final address = [
          if (pm.street != null && pm.street!.isNotEmpty) pm.street,
          if (pm.locality != null && pm.locality!.isNotEmpty) pm.locality,
          if (pm.administrativeArea != null &&
              pm.administrativeArea!.isNotEmpty)
            pm.administrativeArea,
          if (pm.country != null && pm.country!.isNotEmpty) pm.country,
        ].join(', ');

        setState(() {
          _locationController.text = address;
          _locationCity = pm.locality;
          _locationState = pm.administrativeArea;
          _locationCountry = pm.country;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error getting location: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLocating = false);
    }
  }

  void _showError(String title, String message) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: AlertDialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 24),
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submit() async {
    // Validate logo first
    if (_logoImage == null) {
      setState(() => _logoError = true);
    }
    final formValid = _formKey.currentState!.validate();
    if (_logoImage == null || !formValid) return;

    final user = ref.read(authRepositoryProvider).currentUser;
    if (user == null) {
      _showError('Error', 'User not logged in');
      return;
    }

    // Check organization limit (Max 2)
    final orgRepo = ref.read(organizationRepositoryProvider);
    final orgsCount =
        (ref.read(userOrganizationsProvider).value ??
                orgRepo.getCachedUserOrganizations(user.uid) ??
                const [])
            .length;
    if (orgsCount >= 2) {
      _showError(
        'Limit Reached',
        'You can only manage a maximum of 2 organizations. Please remove or deactivate an existing one to register a new organization.',
      );
      return;
    }

    if (_locationLat == null || _locationLng == null) {
      _showError(
        'Location Required',
        'Please select a valid address from the suggestions.',
      );
      return;
    }

    final profileRepo = ref.read(profileRepositoryProvider);
    final userProfile =
        ref.read(userProfileProvider).value ??
        profileRepo.getCachedProfile(user.uid);
    final homeCountryCode = userProfile?.homeCountryCode;

    final businessName = _nameController.text.trim();
    final description = _descController.text.trim();
    final phone = _phoneController.text.trim();
    final organizationType = _selectedOrgType!;
    final website = _websiteController.text.trim();
    final locationAddress = _locationController.text.trim();
    final locationLat = _locationLat;
    final locationLng = _locationLng;
    final locationCity = _locationCity;
    final locationState = _locationState;
    final locationCountry = _locationCountry;
    final creatorTitle = _selectedTitle;
    final richData = _selectedRichData;
    final communityId = widget.communityId;
    final pickedLogo = _logoImage!;
    final uploadFuture =
        _logoUploadFuture ?? _uploadLogoInBackground(user.uid, pickedLogo);
    final router = GoRouter.of(context);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    // Wait briefly if logo upload is already done, otherwise proceed with background persistence
    String? logoUrl;
    try {
      logoUrl = await uploadFuture.timeout(
        const Duration(milliseconds: 50),
        onTimeout: () => null,
      );
    } catch (_) {}

    // Submit registration (creates org doc ref id synchronously in submitBusinessRegistration)
    // To navigate in 0ms, we run the full registration in background if upload is still in flight,
    // or await submitBusinessRegistration directly. Let's check:
    try {
      if (logoUrl != null) {
        final orgId = await profileRepo.submitBusinessRegistration(
          uid: user.uid,
          businessName: businessName,
          description: description,
          phone: phone,
          organizationType: organizationType,
          website: website,
          logoUrl: logoUrl,
          locationAddress: locationAddress,
          locationLat: locationLat,
          locationLng: locationLng,
          locationCity: locationCity,
          locationState: locationState,
          locationCountry: locationCountry,
          homeCountryCode: homeCountryCode,
          creatorTitle: creatorTitle,
          richData: richData,
          communityId: communityId,
        );
        orgRepo.cacheOrganization(orgId, {
          'id': orgId,
          'name': businessName,
          'businessName': businessName,
          'description': description,
          'phone': phone,
          'type': organizationType,
          'website': website,
          'profileImage': logoUrl,
          'superAdminId': user.uid,
          'admins': [user.uid],
          'pendingAdmins': <String>[],
          'status': 'active',
          'locationAddress': locationAddress,
          'city': locationCity,
          'state': locationState,
          'country': locationCountry,
          'homeCountryCode': homeCountryCode,
          if (creatorTitle != null) 'adminTitles': {user.uid: creatorTitle},
          'communityId': ?communityId,
        });
        ref.invalidate(userOrganizationsProvider);
        if (mounted) {
          navigator.pop();
          router.push('/organization/manage?orgId=$orgId');
          messenger.showSnackBar(
            const SnackBar(
              content: Text(
                'Organization created successfully! Invite a second admin to activate.',
              ),
            ),
          );
        }
      } else {
        // Pop immediately and finish logo upload + registration in background!
        navigator.pop();
        messenger.showSnackBar(
          const SnackBar(
            content: Text(
              'Organization created successfully! Invite a second admin to activate.',
            ),
          ),
        );
        unawaited(
          () async {
            final finalLogoUrl = await uploadFuture;
            final orgId = await profileRepo.submitBusinessRegistration(
              uid: user.uid,
              businessName: businessName,
              description: description,
              phone: phone,
              organizationType: organizationType,
              website: website,
              logoUrl: finalLogoUrl,
              locationAddress: locationAddress,
              locationLat: locationLat,
              locationLng: locationLng,
              locationCity: locationCity,
              locationState: locationState,
              locationCountry: locationCountry,
              homeCountryCode: homeCountryCode,
              creatorTitle: creatorTitle,
              richData: richData,
              communityId: communityId,
            );
            orgRepo.cacheOrganization(orgId, {
              'id': orgId,
              'name': businessName,
              'businessName': businessName,
              'description': description,
              'phone': phone,
              'type': organizationType,
              'website': website,
              'profileImage': finalLogoUrl,
              'superAdminId': user.uid,
              'admins': [user.uid],
              'pendingAdmins': <String>[],
              'status': 'active',
              'locationAddress': locationAddress,
              'city': locationCity,
              'state': locationState,
              'country': locationCountry,
              'homeCountryCode': homeCountryCode,
              if (creatorTitle != null) 'adminTitles': {user.uid: creatorTitle},
              'communityId': ?communityId,
            });
            ref.invalidate(userOrganizationsProvider);
            router.push('/organization/manage?orgId=$orgId');
          }(),
        );
      }
    } catch (e) {
      debugPrint('Submission error: $e');
      if (mounted) {
        _showError('Submission Failed', '$e');
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    _phoneController.dispose();
    _websiteController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  InputDecoration _borderlessDecoration(
    BuildContext context, {
    required String labelText,
    required Widget prefixIcon,
    Widget? suffixIcon,
    bool locked = false,
  }) {
    return InputDecoration(
      labelText: labelText,
      prefixIcon: prefixIcon,
      suffixIcon: suffixIcon,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      filled: true,
      fillColor: locked
          ? Colors.green.withValues(alpha: 0.05)
          : AppTheme.elevationColor(context, 2),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        bottom:
            MediaQuery.of(context).viewInsets.bottom +
            MediaQuery.of(context).padding.bottom +
            24,
        left: 16,
        right: 16,
        top: 16,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),

          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(LucideIcons.building2, color: Colors.blue),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Organization Registration',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'Register your organization',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
              if (_isVerifiedBusiness)
                IconButton(
                  onPressed: _resetSelection,
                  icon: const Icon(LucideIcons.rotateCcw, color: Colors.red),
                  tooltip: 'Reset Selection',
                ),
            ],
          ),

          const SizedBox(height: 24),

          Flexible(
            child: SingleChildScrollView(
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                    // Logo Picker moved inside scrollable form to avoid overlap
                    Center(
                      child: GestureDetector(
                        onTap: () {
                          setState(() => _logoError = false);
                          _pickImage();
                        },
                        child: Stack(
                          children: [
                            Container(
                              decoration: const BoxDecoration(
                                color: Color(0x14888888),
                                shape: BoxShape.circle,
                              ),
                              child: CircleAvatar(
                                radius: 40,
                                backgroundColor: Colors.grey.shade200,
                                backgroundImage: _logoImage != null
                                    ? (kIsWeb
                                          ? NetworkImage(_logoImage!.path)
                                          : FileImage(File(_logoImage!.path))
                                                as ImageProvider)
                                    : null,
                                child: _logoImage == null
                                    ? Icon(
                                        LucideIcons.image,
                                        size: 30,
                                        color: _logoError
                                            ? Colors.red
                                            : Colors.grey,
                                      )
                                    : null,
                              ),
                            ),
                            Positioned(
                              bottom: 0,
                              right: 0,
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: const BoxDecoration(
                                  color: Colors.blue,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  LucideIcons.camera,
                                  size: 14,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Center(
                      child: Text(
                        _logoError ? 'Logo is required *' : 'Upload Logo *',
                        style: TextStyle(
                          fontSize: 12,
                          color: _logoError ? Colors.red : Colors.grey,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextFormField(
                          controller: _nameController,
                          textCapitalization: TextCapitalization.words,
                          onChanged: _onNameChanged,
                          readOnly: _isNameLocked,
                          decoration: _borderlessDecoration(
                            context,
                            labelText: 'Business / Organization Name',
                            prefixIcon: const Icon(
                              LucideIcons.building2,
                              size: 18,
                            ),
                            suffixIcon: _isNameLocked
                                ? const Icon(
                                    LucideIcons.lock,
                                    size: 16,
                                    color: Colors.green,
                                  )
                                : null,
                            locked: _isNameLocked,
                          ),
                          validator: (v) =>
                              v?.isEmpty == true ? 'Required' : null,
                        ),
                        if (_showNamePredictions && _namePredictions.isNotEmpty)
                          Container(
                            margin: const EdgeInsets.only(top: 4),
                            constraints: const BoxConstraints(maxHeight: 150),
                            decoration: BoxDecoration(
                              color: Theme.of(context).cardColor,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: ListView.builder(
                              shrinkWrap: true,
                              itemCount: _namePredictions.length,
                              itemBuilder: (context, index) {
                                final p = _namePredictions[index];
                                return ListTile(
                                  dense: true,
                                  leading: const Icon(
                                    LucideIcons.search,
                                    size: 16,
                                  ),
                                  title: Text(
                                    p.primaryText,
                                    style: const TextStyle(fontSize: 14),
                                  ),
                                  subtitle: p.secondaryText.isNotEmpty
                                      ? Text(
                                          p.secondaryText,
                                          style: const TextStyle(fontSize: 11),
                                        )
                                      : null,
                                  onTap: () => _selectBusiness(p),
                                );
                              },
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _descController,
                      maxLines: 3,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: _borderlessDecoration(
                        context,
                        labelText: 'Description',
                        prefixIcon: const Icon(LucideIcons.alignLeft, size: 18),
                      ),
                      validator: (v) => v?.isEmpty == true ? 'Required' : null,
                    ),
                    const SizedBox(height: 16),

                    // Location Autocomplete Field
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextFormField(
                          controller: _locationController,
                          onChanged: _onLocationChanged,
                          textCapitalization: TextCapitalization.sentences,
                          readOnly: _isLocationLocked,
                          decoration: _borderlessDecoration(
                            context,
                            labelText: 'City / Location',
                            prefixIcon: const Icon(
                              LucideIcons.mapPin,
                              size: 18,
                            ),
                            locked: _isLocationLocked,
                            suffixIcon: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (_isLocationLocked)
                                  const Padding(
                                    padding: EdgeInsets.only(right: 8.0),
                                    child: Icon(
                                      LucideIcons.lock,
                                      color: Colors.green,
                                      size: 16,
                                    ),
                                  )
                                else if (_locationLat != null)
                                  const Icon(
                                    LucideIcons.checkCircle,
                                    color: Colors.green,
                                    size: 18,
                                  ),
                                if (!_isLocationLocked)
                                  IconButton(
                                    icon: _isLocating
                                        ? const SizedBox(
                                            width: 16,
                                            height: 16,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          )
                                        : const Icon(
                                            LucideIcons.locate,
                                            size: 18,
                                          ),
                                    onPressed: _isLocating
                                        ? null
                                        : _useCurrentLocation,
                                    tooltip: 'Use current location',
                                  ),
                              ],
                            ),
                          ),
                          validator: (v) =>
                              v?.isEmpty == true ? 'Required' : null,
                        ),
                        if (_showPredictions &&
                            _predictions.isNotEmpty &&
                            !_isLocationLocked)
                          Container(
                            margin: const EdgeInsets.only(top: 4),
                            constraints: const BoxConstraints(maxHeight: 150),
                            decoration: BoxDecoration(
                              color: Theme.of(context).cardColor,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: ListView.builder(
                              shrinkWrap: true,
                              itemCount: _predictions.length,
                              itemBuilder: (context, index) {
                                final p = _predictions[index];
                                return ListTile(
                                  dense: true,
                                  leading: const Icon(
                                    LucideIcons.mapPin,
                                    size: 16,
                                  ),
                                  title: Text(
                                    p.fullText,
                                    style: const TextStyle(fontSize: 14),
                                  ),
                                  onTap: () => _selectPlace(p),
                                );
                              },
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    TextFormField(
                      controller: _phoneController,
                      readOnly: _isPhoneLocked,
                      decoration: _borderlessDecoration(
                        context,
                        labelText: 'Business Phone',
                        prefixIcon: const Icon(LucideIcons.phone, size: 18),
                        suffixIcon: _isPhoneLocked
                            ? const Icon(
                                LucideIcons.lock,
                                size: 16,
                                color: Colors.green,
                              )
                            : null,
                        locked: _isPhoneLocked,
                      ),
                      keyboardType: TextInputType.phone,
                      validator: (v) => v?.isEmpty == true ? 'Required' : null,
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      initialValue: _selectedOrgType,
                      isExpanded: true,
                      decoration: _borderlessDecoration(
                        context,
                        labelText: 'Organization Type',
                        prefixIcon: const Icon(LucideIcons.briefcase, size: 18),
                      ),
                      items: _orgTypes
                          .map(
                            (type) => DropdownMenuItem(
                              value: type,
                              child: Text(
                                type,
                                style: const TextStyle(fontSize: 14),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (val) {
                        setState(() {
                          _selectedOrgType = val;
                          if (val != null) _updateTitleOptions(val);
                        });
                      },
                      validator: (v) => v == null ? 'Required' : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _websiteController,
                      readOnly: _isWebsiteLocked,
                      decoration: _borderlessDecoration(
                        context,
                        labelText: 'Website URL (optional)',
                        prefixIcon: const Icon(LucideIcons.globe, size: 18),
                        suffixIcon: _isWebsiteLocked
                            ? const Icon(
                                LucideIcons.lock,
                                size: 16,
                                color: Colors.green,
                              )
                            : null,
                        locked: _isWebsiteLocked,
                      ),
                      keyboardType: TextInputType.url,
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      initialValue: _selectedTitle,
                      isExpanded: true,
                      decoration: _borderlessDecoration(
                        context,
                        labelText: 'Your Title',
                        prefixIcon: const Icon(
                          LucideIcons.badgeCheck,
                          size: 18,
                        ),
                      ),
                      items: _titleOptions
                          .map(
                            (title) => DropdownMenuItem(
                              value: title,
                              child: Text(title),
                            ),
                          )
                          .toList(),
                      onChanged: (val) {
                        if (val != null) setState(() => _selectedTitle = val);
                      },
                      validator: (v) => v == null ? 'Required' : null,
                    ),
                    const SizedBox(height: 24),

                    // Community Exclusivity Info Card
                    if (widget.communityId != null)
                      Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Theme.of(
                            context,
                          ).colorScheme.primaryContainer.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              LucideIcons.shield,
                              color: Theme.of(context).colorScheme.primary,
                              size: 20,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Community Exclusive',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'This organization will be exclusively associated with ${ref.read(communityProvider(widget.communityId!)).value?.name ?? 'this community'}. Only community members will be able to discover and interact with it.',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurface
                                          .withValues(alpha: 0.7),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _submit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'Submit Application',
                          style: TextStyle(color: Colors.white, fontSize: 16),
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
