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
import 'package:diaspora_nearby/services/google_places_service.dart';
import 'package:diaspora_nearby/features/chat/providers/chat_identity_provider.dart';
import 'package:diaspora_nearby/models/google_places_models.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:diaspora_nearby/features/organization/repository/organization_repository.dart';

class BusinessRegistrationModal extends ConsumerStatefulWidget {
  const BusinessRegistrationModal({super.key});

  @override
  ConsumerState<BusinessRegistrationModal> createState() => _BusinessRegistrationModalState();
}

class _BusinessRegistrationModalState extends ConsumerState<BusinessRegistrationModal> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descController = TextEditingController();
  final _phoneController = TextEditingController();
  final _websiteController = TextEditingController();
  final _locationController = TextEditingController();
  
  XFile? _logoImage;
  final ImagePicker _picker = ImagePicker();

  // Location state
  List<AutocompletePrediction> _predictions = [];
  bool _showPredictions = false;
  double? _locationLat;
  double? _locationLng;
  String? _locationCity;
  String? _locationState;
  String? _locationCountry;

  // Name predictions
  List<AutocompletePrediction> _namePredictions = [];
  bool _showNamePredictions = false;
  Map<String, dynamic>? _selectedRichData;

  Future<void> _pickImage() async {
    final picked = await _picker.pickImage(source: ImageSource.gallery, maxWidth: 1024, maxHeight: 1024, imageQuality: 85);
    if (picked != null) {
      setState(() => _logoImage = picked);
    }
  }
  
  String? _selectedOrgType;
  final _orgTypes = [
    'Business Organization (BO)',
    'Diaspora Organization (DO)',
    'Political Organization (PO)',
    'Faith Organization (FO)',
    'Non Governmental Organization (NGO)',
    'Government Organization (GO)',
  ];

  void _updateTitleOptions(String orgType) {
    setState(() {
      _titleOptions = _orgTypeTitles[orgType] ?? ['Super Admin', 'Admin', 'Director', 'Leader'];
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
      'Chief Executive Officer (CEO)', 'Managing Director', 'President', 'Founder', 'Owner', 'General Manager', 'Director'
    ],
    'Diaspora Organization (DO)': [
      'President', 'Chairman', 'Chairperson', 'Community Leader', 'Coordinator', 'Secretary', 'Director'
    ],
    'Political Organization (PO)': [
      'Party Leader', 'Chairman', 'Secretary General', 'President', 'Spokesperson', 'Director'
    ],
    'Faith Organization (FO)': [
      'Reverend', 'Pastor', 'Minister', 'Bishop', 'Priest', 'Sheikh', 'Imam', 'Rabbi', 'Deacon', 'Prophet', 'Apostle', 'Leader'
    ],
    'Non Governmental Organization (NGO)': [
      'Executive Director', 'Country Director', 'Founder', 'Program Director', 'Coordinator', 'Director'
    ],
    'Government Organization (GO)': [
      'Ambassador', 'Consular', 'High Commissioner', 'Minister', 'Director General', 'Governor', 'Mayor', 'Commissioner'
    ],
  };

  /* Default fallback titles */
  List<String> _titleOptions = ['Super Admin', 'Admin', 'Director', 'Manager', 'Leader'];
  String? _selectedTitle;
  
  bool _isLoading = false;

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
    final results = await places.autocomplete(input, filter: PlaceTypeFilter.VENUES);
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
    final places = ref.read(googlePlacesServiceProvider);
    final response = await places.getPlaceDetails(prediction.placeId);
    final place = response?.place;

    if (place != null) {
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
        _isVerifiedBusiness = true;
        
        _nameController.text = prediction.primaryText;
        _isNameLocked = true;

        _namePredictions = [];
        _showNamePredictions = false;
        
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
           if (place.userRatingsTotal != null) 'userRatingsTotal': place.userRatingsTotal,
           if (place.openingHours != null) 'openingHours': place.openingHours,
           if (place.photoMetadatas != null) 'photos': place.photoMetadatas,
           if (place.priceLevel != null) 'priceLevel': place.priceLevel,
           if (place.editorialSummary != null) 'editorialSummary': place.editorialSummary,
        };
        
        // Smart Description Population
        if (place.editorialSummary != null && place.editorialSummary!.isNotEmpty) {
           _descController.text = place.editorialSummary!;
        } else {
           // Fallback format: "A [Type] in [City]"
           final type = matchedType != null 
              ? matchedType.split(' (').first 
              : (prediction.secondaryText.isNotEmpty ? prediction.secondaryText : 'Organization');
           
           // Use city from location population or full address roughly
           String location = 'Area';
             final components = place.addressComponents ?? [];
             for (final c in components) {
               if (c.types.contains('locality')) location = c.name;
             }
             if (location == 'Area') {
                // Try from address
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
    setState(() => _isLoading = true);
    try {
      bool serviceEnabled;
      LocationPermission permission;

      serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) throw Exception('Location services are disabled.');

      permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) throw Exception('Location permissions are denied');
      }
      
      if (permission == LocationPermission.deniedForever) {
        throw Exception('Location permissions are permanently denied');
      }

      final position = await Geolocator.getCurrentPosition();
      final placemarks = await placemarkFromCoordinates(position.latitude, position.longitude);
      
      if (placemarks.isNotEmpty && mounted) {
        final pm = placemarks.first;
        final address = [
          if (pm.street != null) pm.street,
          if (pm.locality != null) pm.locality,
          if (pm.administrativeArea != null) pm.administrativeArea,
          if (pm.country != null) pm.country,
        ].join(', ');

        setState(() {
          _locationController.text = address;
          _locationLat = position.latitude;
          _locationLng = position.longitude;
          _locationCity = pm.locality;
          _locationState = pm.administrativeArea;
          _locationCountry = pm.country;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error getting location: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    
    // Check organization limit (Max 2)
    final orgsCount = ref.read(userOrganizationsProvider).value?.length ?? 0;
    if (orgsCount >= 2) {
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Limit Reached'),
            content: const Text('You can only manage a maximum of 2 organizations. Please remove or deactivate an existing one to register a new organization.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK')),
            ],
          ),
        );
      }
      return;
    }

    setState(() => _isLoading = true);

    try {
      final user = ref.read(authRepositoryProvider).currentUser;
      if (user == null) {
         throw Exception('User not logged in');
      }

      String? logoUrl;
      if (_logoImage != null) {
         try {
           final storageRef = FirebaseStorage.instance
            .ref()
            .child('profile_photos')
            .child(user.uid)
            .child('business_logos')
            .child('${DateTime.now().millisecondsSinceEpoch}.jpg');
            
           final metadata = SettableMetadata(cacheControl: 'public, max-age=31536000', contentType: 'image/jpeg');
           if (kIsWeb) {
             final bytes = await _logoImage!.readAsBytes();
             await storageRef.putData(bytes, metadata);
           } else {
             await storageRef.putFile(File(_logoImage!.path), metadata);
           }
           logoUrl = await storageRef.getDownloadURL();
         } catch (e) {
            debugPrint('Logo upload error: $e');
            if (mounted) {
               ScaffoldMessenger.of(context).showSnackBar(
                 SnackBar(content: Text('Failed to upload logo: $e'), backgroundColor: Colors.red),
               );
            }
            setState(() => _isLoading = false);
            return; 
         }
      }

      String orgId;
      try {
        // Validation for actual address/place
        if (_locationLat == null || _locationLng == null) {
          throw Exception('Please select a valid address from the suggestions.');
        }

        // Get user's home country code for filtering
        final userProfile = ref.read(userProfileProvider).value;
        final homeCountryCode = userProfile?.homeCountryCode;

        orgId = await ref.read(profileRepositoryProvider).submitBusinessRegistration(
          uid: user.uid,
          businessName: _nameController.text.trim(),
          description: _descController.text.trim(),
          phone: _phoneController.text.trim(),
          organizationType: _selectedOrgType!,
          website: _websiteController.text.trim(),
          logoUrl: logoUrl,
          locationAddress: _locationController.text.trim(),
          locationLat: _locationLat,
          locationLng: _locationLng,
          locationCity: _locationCity,
          locationState: _locationState,
          locationCountry: _locationCountry,
          homeCountryCode: homeCountryCode,
          creatorTitle: _selectedTitle,
          richData: _selectedRichData, // Pass Rich Data
        );
      } catch (e) {
         debugPrint('Registration Submit Error: $e');
         if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Error creating organization: $e'), backgroundColor: Colors.red),
            );
         }
         setState(() => _isLoading = false);
         return;
      }

        if (mounted) {
          // 1. Refresh the organizations list provider
          ref.invalidate(userOrganizationsProvider);
          
          // 2. Capture router before popping
          final router = GoRouter.of(context);
          
          // 3. Close modal
          Navigator.pop(context);
          
          // 4. Navigate to Manage Page (Matched correctly now due to router.dart fix)
          router.push('/organization/manage?orgId=$orgId');

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Organization created successfully! Invite a second admin to activate.')),
          );
        }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Submission failed: $e'), backgroundColor: Colors.red),
        );
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

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + MediaQuery.of(context).padding.bottom + 24,
        left: 16, right: 16, top: 16
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
              width: 40, height: 4,
              decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
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
                      Text('Organization Registration', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      Text('Register your organization', style: TextStyle(fontSize: 12, color: Colors.grey)),
                    ],
                  ),
                ),
                if (_isVerifiedBusiness)
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
                        onTap: _pickImage,
                        child: Stack(
                          children: [
                             CircleAvatar(
                               radius: 40,
                               backgroundColor: Colors.grey.shade200,
                               backgroundImage: _logoImage != null 
                                 ? (kIsWeb ? NetworkImage(_logoImage!.path) : FileImage(File(_logoImage!.path)) as ImageProvider)
                                 : null,
                               child: _logoImage == null 
                                  ? const Icon(LucideIcons.image, size: 30, color: Colors.grey)
                                  : null,
                             ),
                             Positioned(
                               bottom: 0, right: 0,
                               child: Container(
                                 padding: const EdgeInsets.all(4),
                                 decoration: const BoxDecoration(
                                   color: Colors.blue,
                                   shape: BoxShape.circle,
                                 ),
                                 child: const Icon(LucideIcons.camera, size: 14, color: Colors.white),
                               ),
                             ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Center(child: Text('Upload Logo', style: TextStyle(fontSize: 12, color: Colors.grey))),
                    const SizedBox(height: 24),

                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TextFormField(
                            controller: _nameController,
                            textCapitalization: TextCapitalization.words,
                            onChanged: _onNameChanged,
                            readOnly: _isNameLocked,
                            decoration: InputDecoration(
                              labelText: 'Business / Organization Name',
                              prefixIcon: const Icon(LucideIcons.building2, size: 18),
                              border: const OutlineInputBorder(),
                              suffixIcon: _isNameLocked 
                                ? const Icon(LucideIcons.lock, size: 16, color: Colors.green)
                                : null,
                              filled: _isNameLocked,
                              fillColor: _isNameLocked ? Colors.green.withOpacity(0.05) : null,
                            ),
                            validator: (v) => v?.isEmpty == true ? 'Required' : null,
                          ),
                          if (_showNamePredictions && _namePredictions.isNotEmpty)
                            Container(
                              margin: const EdgeInsets.only(top: 4),
                              constraints: const BoxConstraints(maxHeight: 150),
                              decoration: BoxDecoration(
                                color: Theme.of(context).cardColor,
                                border: Border.all(color: Theme.of(context).dividerColor),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: ListView.builder(
                                shrinkWrap: true,
                                itemCount: _namePredictions.length,
                                itemBuilder: (context, index) {
                                  final p = _namePredictions[index];
                                  return ListTile(
                                    dense: true,
                                    leading: const Icon(LucideIcons.search, size: 16),
                                    title: Text(p.primaryText, style: const TextStyle(fontSize: 14)),
                                    subtitle: p.secondaryText.isNotEmpty ? Text(p.secondaryText, style: const TextStyle(fontSize: 11)) : null,
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
                      decoration: const InputDecoration(
                        labelText: 'Description',
                        prefixIcon: Icon(LucideIcons.alignLeft, size: 18),
                        border: OutlineInputBorder(),
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
                            decoration: InputDecoration(
                              labelText: 'City / Location',
                              prefixIcon: const Icon(LucideIcons.mapPin, size: 18),
                              border: const OutlineInputBorder(),
                              suffixIcon: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (_isLocationLocked)
                                    const Padding(
                                      padding: EdgeInsets.only(right: 8.0),
                                      child: Icon(LucideIcons.lock, color: Colors.green, size: 16),
                                    )
                                  else if (_locationLat != null)
                                    const Icon(LucideIcons.checkCircle, color: Colors.green, size: 18),
                                    
                                  if (!_isLocationLocked)
                                    IconButton(
                                      icon: const Icon(LucideIcons.locate, size: 18),
                                      onPressed: _useCurrentLocation,
                                      tooltip: 'Use current location',
                                    ),
                                ],
                              ),
                              filled: _isLocationLocked,
                              fillColor: _isLocationLocked ? Colors.green.withOpacity(0.05) : null,
                            ),
                            validator: (v) => v?.isEmpty == true ? 'Required' : null,
                          ),
                          if (_showPredictions && _predictions.isNotEmpty && !_isLocationLocked)
                            Container(
                              margin: const EdgeInsets.only(top: 4),
                              constraints: const BoxConstraints(maxHeight: 150),
                              decoration: BoxDecoration(
                                color: Theme.of(context).cardColor,
                                border: Border.all(color: Theme.of(context).dividerColor),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: ListView.builder(
                                shrinkWrap: true,
                                itemCount: _predictions.length,
                                itemBuilder: (context, index) {
                                  final p = _predictions[index];
                                  return ListTile(
                                    dense: true,
                                    leading: const Icon(LucideIcons.mapPin, size: 16),
                                    title: Text(p.fullText, style: const TextStyle(fontSize: 14)),
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
                      decoration: InputDecoration(
                        labelText: 'Business Phone',
                        prefixIcon: const Icon(LucideIcons.phone, size: 18),
                        border: const OutlineInputBorder(),
                        suffixIcon: _isPhoneLocked 
                          ? const Icon(LucideIcons.lock, size: 16, color: Colors.green)
                          : null,
                        filled: _isPhoneLocked,
                        fillColor: _isPhoneLocked ? Colors.green.withOpacity(0.05) : null,
                      ),
                       keyboardType: TextInputType.phone,
                       validator: (v) => v?.isEmpty == true ? 'Required' : null,
                    ),
                    const SizedBox(height: 16),
                     DropdownButtonFormField<String>(
                       value: _selectedOrgType,
                       isExpanded: true,
                       decoration: const InputDecoration(
                         labelText: 'Organization Type',
                         prefixIcon: Icon(LucideIcons.briefcase, size: 18),
                         border: OutlineInputBorder(),
                       ),
                       items: _orgTypes.map((type) => DropdownMenuItem(
                         value: type,
                         child: Text(
                           type,
                           style: const TextStyle(fontSize: 14),
                           overflow: TextOverflow.ellipsis,
                         ),
                       )).toList(),
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
                       decoration: InputDecoration(
                         labelText: 'Website URL (optional)',
                         prefixIcon: const Icon(LucideIcons.globe, size: 18),
                         border: const OutlineInputBorder(),
                         suffixIcon: _isWebsiteLocked 
                          ? const Icon(LucideIcons.lock, size: 16, color: Colors.green)
                          : null,
                         filled: _isWebsiteLocked,
                         fillColor: _isWebsiteLocked ? Colors.green.withOpacity(0.05) : null,
                       ),
                       keyboardType: TextInputType.url,
                     ),
                    const SizedBox(height: 16),
                     DropdownButtonFormField<String>(
                       value: _selectedTitle,
                       isExpanded: true,
                       decoration: const InputDecoration(
                         labelText: 'Your Title',
                         prefixIcon: Icon(LucideIcons.badgeCheck, size: 18),
                         border: OutlineInputBorder(),
                       ),
                       items: _titleOptions.map((title) => DropdownMenuItem(
                         value: title,
                         child: Text(title),
                       )).toList(),
                       onChanged: (val) {
                         if (val != null) setState(() => _selectedTitle = val);
                       },
                       validator: (v) => v == null ? 'Required' : null,
                     ),
                    const SizedBox(height: 24),
                    
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _submit,
                        style: ElevatedButton.styleFrom(
                           backgroundColor: Colors.blue,
                           padding: const EdgeInsets.symmetric(vertical: 16),
                           shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: _isLoading 
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Text('Submit Application', style: TextStyle(color: Colors.white, fontSize: 16)),
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



