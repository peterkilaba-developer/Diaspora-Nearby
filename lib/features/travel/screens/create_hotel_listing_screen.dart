import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:diaspora_nearby/theme/app_theme.dart';
import 'package:diaspora_nearby/features/profile/repository/profile_repository.dart';
import 'package:diaspora_nearby/features/auth/repository/auth_repository.dart';
import 'package:diaspora_nearby/features/travel/models/peer_listing.dart';
import 'package:diaspora_nearby/features/travel/services/peer_listing_repository.dart';
import 'package:diaspora_nearby/core/services/google_places_service.dart';
import 'package:diaspora_nearby/core/utils/location_utils.dart';
import 'package:diaspora_nearby/features/shared/models/google_places_models.dart';
import 'package:diaspora_nearby/core/data/countries.dart' as country_data;
import 'package:diaspora_nearby/features/travel/screens/peer_listing_detail_screen.dart';

class CreateHotelListingScreen extends ConsumerStatefulWidget {
  final PeerListing? existing; // If editing

  const CreateHotelListingScreen({super.key, this.existing});

  @override
  ConsumerState<CreateHotelListingScreen> createState() =>
      _CreateHotelListingScreenState();
}

class _CreateHotelListingScreenState
    extends ConsumerState<CreateHotelListingScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleC = TextEditingController();
  final _descC = TextEditingController();
  final _priceC = TextEditingController();
  final _addressC = TextEditingController();
  final _cityC = TextEditingController();
  final _subLocalityC = TextEditingController();
  final _stateC = TextEditingController();
  final _countryC = TextEditingController();
  final _checkInTimeC = TextEditingController(text: '15:00');
  final _checkOutTimeC = TextEditingController(text: '11:00');

  // Google Places search
  final _searchC = TextEditingController();
  List<AutocompletePrediction> _predictions = [];
  bool _isSearching = false;
  bool _isFetchingDetails = false;
  double? _lat;
  double? _lng;
  String? _countryCode;

  String _hotelCategory = 'Hotel';
  int _starRating = 3;
  int _rooms = 1;
  int _maxGuests = 2;
  final List<String> _selectedAmenities = [];
  final List<XFile> _selectedImages = [];
  bool _isSaving = false;
  bool _isUploading = false;
  int _uploadedCount = 0;

  static const _hotelCategories = [
    'Hotel',
    'Boutique Hotel',
    'Resort',
    'Business Hotel',
    'Hostel',
    'Guest House',
    'Motel',
    'Bed & Breakfast',
  ];

  static const _allAmenities = [
    'Wi-Fi',
    'Restaurant',
    'Room Service',
    'Pool',
    'Spa',
    'Gym',
    'Bar / Lounge',
    'Parking',
    'Airport Shuttle',
    'Concierge',
    'AC',
    'Laundry',
    'Business Center',
    'Conference Room',
    'Pet Friendly',
    'Wheelchair Access',
  ];

  @override
  void initState() {
    super.initState();
    if (widget.existing != null) {
      _prefillFromExisting(widget.existing!);
    } else {
      _prefillFromProfile();
    }
  }

  void _prefillFromExisting(PeerListing l) {
    _titleC.text = l.title;
    _descC.text = l.description;
    _priceC.text = l.pricePerUnit.toStringAsFixed(0);
    _addressC.text = l.address ?? '';
    _cityC.text = l.locality ?? l.city ?? '';
    _subLocalityC.text = l.subLocality ?? '';
    _stateC.text = l.state ?? '';
    _countryC.text = l.country ?? '';
    _countryCode = l.countryCode;
    _hotelCategory = l.hotelCategory ?? 'Hotel';
    _starRating = l.starRating ?? 3;
    _rooms = l.beds ?? 1;
    _maxGuests = l.maxGuests ?? 2;
    _checkInTimeC.text = l.checkInTime ?? '15:00';
    _checkOutTimeC.text = l.checkOutTime ?? '11:00';
    _lat = l.lat;
    _lng = l.lng;
    if (l.amenities != null) _selectedAmenities.addAll(l.amenities!);
  }

  void _prefillFromProfile() {
    final profile = ref.read(userProfileProvider).value;
    if (profile == null) return;
    _cityC.text = profile.hostLocation.city ?? '';
    _stateC.text = profile.hostLocation.state ?? '';
    _countryC.text = profile.hostCountry ?? '';
    _countryCode = profile.hostCountryCode;
  }

  @override
  void dispose() {
    _titleC.dispose();
    _descC.dispose();
    _priceC.dispose();
    _addressC.dispose();
    _cityC.dispose();
    _subLocalityC.dispose();
    _stateC.dispose();
    _countryC.dispose();
    _checkInTimeC.dispose();
    _checkOutTimeC.dispose();
    _searchC.dispose();
    super.dispose();
  }

  // ─── Google Places Search ───────────────────────────────────────────

  Future<void> _onSearchChanged(String query) async {
    if (query.length < 3) {
      setState(() => _predictions = []);
      return;
    }

    setState(() => _isSearching = true);

    try {
      final service = ref.read(googlePlacesServiceProvider);
      final results = await service.autocomplete(
        query,
        filter: PlaceTypeFilter.ESTABLISHMENT,
      );

      if (!mounted) return;
      setState(() {
        _predictions = results;
        _isSearching = false;
      });
    } catch (e) {
      if (mounted) setState(() => _isSearching = false);
    }
  }

  Future<void> _onPlaceSelected(AutocompletePrediction prediction) async {
    setState(() {
      _predictions = [];
      _isFetchingDetails = true;
      _searchC.text = prediction.primaryText;
    });

    try {
      final service = ref.read(googlePlacesServiceProvider);
      final response = await service.getPlaceDetails(prediction.placeId);

      if (!mounted || response == null) {
        if (mounted) setState(() => _isFetchingDetails = false);
        return;
      }

      final place = response.place;

      // Auto-fill hotel name
      if (place.name != null && place.name!.isNotEmpty) {
        _titleC.text = place.name!;
      }

      // Auto-fill description from Google editorial summary
      if (place.editorialSummary != null &&
          place.editorialSummary!.isNotEmpty &&
          _descC.text.isEmpty) {
        _descC.text = place.editorialSummary!;
      }

      // Auto-fill address
      if (place.fullAddress != null) {
        _addressC.text = place.fullAddress!;
      }

      // Auto-fill coordinates
      if (place.latLng != null) {
        _lat = place.latLng!.lat;
        _lng = place.latLng!.lng;
      }

      // Auto-fill star rating from Google rating
      if (place.rating != null) {
        _starRating = place.rating!.round().clamp(1, 5);
      }

      // Parse address components for city, state, country
      if (place.addressComponents != null) {
        final parsed = parseLocationComponents(
          place.fullAddress ?? place.address ?? '',
          place.addressComponents!,
        );
        if (parsed != null) {
          _cityC.text = parsed.city ?? '';
          _stateC.text = parsed.state ?? '';
          _countryC.text = parsed.country;
          _countryCode = parsed.countryCode;

          // Try to extract neighborhood/sublocality
          for (final comp in place.addressComponents!) {
            if (comp.types.contains('sublocality') ||
                comp.types.contains('sublocality_level_1') ||
                comp.types.contains('neighborhood')) {
              _subLocalityC.text = comp.name;
              break;
            }
          }
        }
      }

      // Detect hotel category from Google types
      if (place.types != null) {
        if (place.types!.contains('lodging') ||
            place.types!.contains('hotel')) {
          // Keep default or detect from name
          final nameLower = (place.name ?? '').toLowerCase();
          if (nameLower.contains('resort')) {
            _hotelCategory = 'Resort';
          } else if (nameLower.contains('hostel')) {
            _hotelCategory = 'Hostel';
          } else if (nameLower.contains('motel')) {
            _hotelCategory = 'Motel';
          } else if (nameLower.contains('b&b') ||
              nameLower.contains('bed and breakfast') ||
              nameLower.contains('bed & breakfast')) {
            _hotelCategory = 'Bed & Breakfast';
          } else if (nameLower.contains('guest house') ||
              nameLower.contains('guesthouse')) {
            _hotelCategory = 'Guest House';
          } else if (nameLower.contains('boutique')) {
            _hotelCategory = 'Boutique Hotel';
          }
        }
      }

      setState(() => _isFetchingDetails = false);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(LucideIcons.sparkles, color: Colors.white, size: 16),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Auto-filled from Google Places! Review and adjust details.',
                    style: TextStyle(fontSize: 13),
                  ),
                ),
              ],
            ),
            behavior: SnackBarBehavior.floating,
            backgroundColor: AppTheme.accent,
            duration: Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isFetchingDetails = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not fetch details: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  // ─── Save ───────────────────────────────────────────────────────────

  Future<void> _pickImages() async {
    final remaining = 20 - _selectedImages.length;
    if (remaining <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Maximum 20 photos allowed')),
      );
      return;
    }

    final picker = ImagePicker();
    final images = await picker.pickMultiImage(
      maxWidth: 1280,
      imageQuality: 80,
    );

    if (images.isNotEmpty) {
      setState(() {
        final toAdd = images.take(remaining).toList();
        _selectedImages.addAll(toAdd);
      });
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    // Validate minimum 10 photos
    if (_selectedImages.length < 10 && widget.existing == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Please add at least 10 photos (${_selectedImages.length}/10)',
          ),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.red.shade700,
        ),
      );
      return;
    }

    setState(() {
      _isSaving = true;
      _isUploading = _selectedImages.isNotEmpty;
      _uploadedCount = 0;
    });

    try {
      final profile = ref.read(userProfileProvider).value;
      final user = ref.read(authRepositoryProvider).currentUser;
      if (user == null || profile == null) {
        throw Exception('Not logged in');
      }

      // Upload images to Firebase Storage
      final imageUrls = <String>[];
      for (int i = 0; i < _selectedImages.length; i++) {
        final file = File(_selectedImages[i].path);
        final storageRef = FirebaseStorage.instance.ref().child(
          'hotels/${user.uid}/${DateTime.now().millisecondsSinceEpoch}_$i.jpg',
        );
        await storageRef.putFile(file);
        final url = await storageRef.getDownloadURL();
        imageUrls.add(url);
        if (mounted) setState(() => _uploadedCount = i + 1);
      }

      setState(() => _isUploading = false);

      final repo = ref.read(peerListingRepositoryProvider);

      final listing = PeerListing(
        id: widget.existing?.id ?? '',
        type: 'hotel',
        ownerId: user.uid,
        ownerName: profile.fullName,
        ownerPhoto: profile.profileImage,
        title: _titleC.text.trim(),
        description: _descC.text.trim(),
        photos: imageUrls,
        pricePerUnit: double.tryParse(_priceC.text.trim()) ?? 0,
        city: _cityC.text.trim(),
        country: _countryC.text.trim().isNotEmpty
            ? _countryC.text.trim()
            : profile.hostCountry,
        countryCode: _countryCode ?? profile.hostCountryCode,
        address: _addressC.text.trim(),
        locality: _cityC.text.trim(),
        subLocality: _subLocalityC.text.trim(),
        state: _stateC.text.trim(),
        localityLower: _cityC.text.trim().toLowerCase(),
        stateLower: _stateC.text.trim().toLowerCase(),
        lat: _lat,
        lng: _lng,
        // Hotel-specific
        hotelCategory: _hotelCategory,
        starRating: _starRating,
        beds: _rooms,
        maxGuests: _maxGuests,
        checkInTime: _checkInTimeC.text.trim(),
        checkOutTime: _checkOutTimeC.text.trim(),
        amenities: _selectedAmenities,
      );

      if (widget.existing != null) {
        await repo.updateListing(widget.existing!.id, listing.toJson());
        if (mounted) {
          Navigator.pop(context, true);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Hotel listing updated!'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } else {
        final newId = await repo.createListing(listing);
        final created = await repo.getListing(newId);
        if (mounted) {
          Navigator.pop(context, true);
          if (created != null) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => PeerListingDetailScreen(listing: created),
              ),
            );
          }
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Hotel listing created!'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // ─── Build ──────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEditing = widget.existing != null;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Text(isEditing ? 'Edit Hotel Listing' : 'List Your Hotel'),
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),
      body: Stack(
        children: [
          Form(
            key: _formKey,
            child: ListView(
              padding: EdgeInsets.only(
                left: 8,
                right: 8,
                top: 8,
                bottom: MediaQuery.of(context).padding.bottom + 16,
              ),
              children: [
                // ─── Google Places Search ─────────────────────────
                if (!isEditing) ...[
                  _buildPlacesSearch(theme),
                  const SizedBox(height: 20),
                ],

                // Hotel category
                _sectionLabel(theme, 'Hotel Type'),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _hotelCategories.map((t) {
                    final selected = _hotelCategory == t;
                    return ChoiceChip(
                      label: Text(t),
                      selected: selected,
                      onSelected: (_) => setState(() => _hotelCategory = t),
                      selectedColor: AppTheme.accent.withValues(alpha: 0.2),
                      backgroundColor: AppTheme.elevationColor(context, 2),
                      labelStyle: TextStyle(
                        color: selected
                            ? AppTheme.accent
                            : theme.colorScheme.onSurface.withValues(
                                alpha: 0.7,
                              ),
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.w500,
                        fontSize: 13,
                      ),
                      side: BorderSide.none,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 20),

                // Star Rating
                _sectionLabel(theme, 'Star Rating'),
                const SizedBox(height: 8),
                Row(
                  children: List.generate(5, (i) {
                    final star = i + 1;
                    return GestureDetector(
                      onTap: () => setState(() => _starRating = star),
                      child: Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Icon(
                          star <= _starRating
                              ? LucideIcons.star
                              : LucideIcons.star,
                          size: 32,
                          color: star <= _starRating
                              ? Colors.amber
                              : theme.colorScheme.onSurface.withValues(
                                  alpha: 0.2,
                                ),
                        ),
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 20),

                // Title
                _buildTextField(
                  controller: _titleC,
                  label: 'Hotel Name',
                  hint: 'e.g. Grand Palace Hotel',
                  icon: LucideIcons.hotel,
                  validator: (v) =>
                      v == null || v.isEmpty ? 'Hotel name is required' : null,
                ),
                const SizedBox(height: 14),

                // Description
                _buildTextField(
                  controller: _descC,
                  label: 'Description',
                  hint:
                      'Describe your hotel, its unique features, and what guests can expect...',
                  icon: LucideIcons.alignLeft,
                  maxLines: 4,
                  validator: (v) =>
                      v == null || v.isEmpty ? 'Description is required' : null,
                ),
                const SizedBox(height: 14),

                // Price
                _buildTextField(
                  controller: _priceC,
                  label: 'Price per Night (USD)',
                  hint: 'e.g. 120',
                  icon: LucideIcons.dollarSign,
                  keyboardType: TextInputType.number,
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Price is required';
                    if (double.tryParse(v) == null) {
                      return 'Enter a valid number';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 14),

                // Check-in / Check-out times
                _sectionLabel(theme, 'Check-in / Check-out'),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _buildTextField(
                        controller: _checkInTimeC,
                        label: 'Check-in Time',
                        hint: '15:00',
                        icon: LucideIcons.logIn,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildTextField(
                        controller: _checkOutTimeC,
                        label: 'Check-out Time',
                        hint: '11:00',
                        icon: LucideIcons.logOut,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // Location section
                _sectionLabel(theme, 'Location'),
                const SizedBox(height: 8),
                _buildTextField(
                  controller: _addressC,
                  label: 'Street Address',
                  hint: 'Full street address',
                  icon: LucideIcons.home,
                ),
                const SizedBox(height: 12),
                _buildTextField(
                  controller: _cityC,
                  label: 'City',
                  hint: 'e.g. Lagos',
                  icon: LucideIcons.mapPin,
                ),
                const SizedBox(height: 12),
                Builder(
                  builder: (context) {
                    final profile = ref.read(userProfileProvider).value;
                    final cc = _countryCode ?? profile?.hostCountryCode ?? '';
                    final hasState = country_data
                        .hasStateLevelHierarchyFromData(cc);
                    final stateTerm = country_data.getStateTerminology(cc);

                    if (hasState) {
                      return Row(
                        children: [
                          Expanded(
                            child: _buildTextField(
                              controller: _subLocalityC,
                              label: 'Neighborhood / Area',
                              hint: 'e.g. Victoria Island',
                              icon: LucideIcons.navigation,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildTextField(
                              controller: _stateC,
                              label: stateTerm,
                              hint: 'e.g. Lagos State',
                              icon: LucideIcons.map,
                            ),
                          ),
                        ],
                      );
                    } else {
                      return _buildTextField(
                        controller: _subLocalityC,
                        label: 'Neighborhood / Area',
                        hint: 'e.g. Victoria Island',
                        icon: LucideIcons.navigation,
                      );
                    }
                  },
                ),
                const SizedBox(height: 12),
                _buildTextField(
                  controller: _countryC,
                  label: 'Country',
                  hint: 'e.g. Nigeria',
                  icon: LucideIcons.globe,
                ),
                if (_lat != null && _lng != null) ...[
                  const SizedBox(height: 6),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Row(
                      children: [
                        Icon(
                          LucideIcons.locate,
                          size: 12,
                          color: AppTheme.accent.withValues(alpha: 0.6),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'GPS: ${_lat!.toStringAsFixed(5)}, ${_lng!.toStringAsFixed(5)}',
                          style: TextStyle(
                            fontSize: 11,
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 20),

                // Rooms, Guests steppers
                _sectionLabel(theme, 'Capacity'),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _stepper(
                        theme,
                        'Rooms',
                        _rooms,
                        1,
                        500,
                        (v) => setState(() => _rooms = v),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _stepper(
                        theme,
                        'Max Guests',
                        _maxGuests,
                        1,
                        1000,
                        (v) => setState(() => _maxGuests = v),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // Amenities
                _sectionLabel(theme, 'Amenities & Services'),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _allAmenities.map((a) {
                    final selected = _selectedAmenities.contains(a);
                    return FilterChip(
                      label: Text(a),
                      selected: selected,
                      onSelected: (val) {
                        setState(() {
                          if (val) {
                            _selectedAmenities.add(a);
                          } else {
                            _selectedAmenities.remove(a);
                          }
                        });
                      },
                      selectedColor: AppTheme.accent.withValues(alpha: 0.15),
                      backgroundColor: AppTheme.elevationColor(context, 2),
                      checkmarkColor: AppTheme.accent,
                      labelStyle: TextStyle(
                        fontSize: 12,
                        color: selected
                            ? AppTheme.accent
                            : theme.colorScheme.onSurface.withValues(
                                alpha: 0.6,
                              ),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      side: BorderSide.none,
                    );
                  }).toList(),
                ),
                const SizedBox(height: 24),

                // ─── Hotel Photos ────────────────────────────────
                _sectionLabel(theme, 'Hotel Photos (min 10, max 20)'),
                const SizedBox(height: 4),
                Text(
                  '${_selectedImages.length}/10 minimum  •  Showcase rooms, lobby, pool, restaurant, and surroundings',
                  style: TextStyle(
                    fontSize: 11,
                    color: _selectedImages.length >= 10
                        ? AppTheme.success
                        : theme.hintColor,
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 110,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _selectedImages.length + 1,
                    separatorBuilder: (_, _) => const SizedBox(width: 10),
                    itemBuilder: (context, index) {
                      if (index == 0) {
                        return GestureDetector(
                          onTap: _pickImages,
                          child: Container(
                            width: 110,
                            decoration: BoxDecoration(
                              color: AppTheme.elevationColor(context, 2),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  LucideIcons.imagePlus,
                                  size: 28,
                                  color: _selectedImages.length < 10
                                      ? AppTheme.accent
                                      : theme.hintColor,
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Add Photos',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: _selectedImages.length < 10
                                        ? AppTheme.accent
                                        : theme.hintColor,
                                  ),
                                ),
                                Text(
                                  'Select multiple',
                                  style: TextStyle(
                                    fontSize: 9,
                                    color: theme.hintColor,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }

                      final img = _selectedImages[index - 1];
                      return Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: Image.file(
                              File(img.path),
                              width: 110,
                              height: 110,
                              fit: BoxFit.cover,
                            ),
                          ),
                          // Photo number badge
                          Positioned(
                            bottom: 4,
                            left: 4,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black54,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '$index',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                ),
                              ),
                            ),
                          ),
                          // Remove button
                          Positioned(
                            top: 4,
                            right: 4,
                            child: GestureDetector(
                              onTap: () => setState(
                                () => _selectedImages.removeAt(index - 1),
                              ),
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: Colors.black54,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(
                                  LucideIcons.x,
                                  color: Colors.white,
                                  size: 14,
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                const SizedBox(height: 32),

                // Save button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isSaving ? null : _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.accent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      elevation: 0,
                    ),
                    child: _isSaving
                        ? Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              ),
                              if (_isUploading) ...[
                                const SizedBox(width: 12),
                                Text(
                                  'Uploading $_uploadedCount/${_selectedImages.length}',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: Colors.white70,
                                  ),
                                ),
                              ],
                            ],
                          )
                        : Text(
                            isEditing ? 'Update Hotel' : 'Publish Hotel',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                ),
                SizedBox(height: MediaQuery.of(context).padding.bottom + 20),
              ],
            ),
          ),

          // Loading overlay when fetching place details
          if (_isFetchingDetails)
            Positioned.fill(
              child: Container(
                color: Colors.black.withValues(alpha: 0.3),
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 32,
                      vertical: 24,
                    ),
                    decoration: BoxDecoration(
                      color: theme.cardColor,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.2),
                          blurRadius: 20,
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(
                          width: 32,
                          height: 32,
                          child: CircularProgressIndicator(
                            strokeWidth: 3,
                            color: AppTheme.accent,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Fetching hotel details...',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Auto-filling from Google Places',
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ─── Google Places Search Widget ────────────────────────────────────

  Widget _buildPlacesSearch(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Search header
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                AppTheme.accent.withValues(alpha: 0.08),
                AppTheme.accent.withValues(alpha: 0.03),
              ],
            ),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(LucideIcons.sparkles, size: 16, color: AppTheme.accent),
                  SizedBox(width: 8),
                  Text(
                    'SEARCH & AUTO-FILL',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.accent,
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Search for your hotel on Google to auto-fill details.',
                style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                ),
              ),
              const SizedBox(height: 10),

              // Search field
              TextFormField(
                controller: _searchC,
                decoration: InputDecoration(
                  hintText: 'Search hotel name or address...',
                  hintStyle: TextStyle(
                    fontSize: 13,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.35),
                  ),
                  prefixIcon: Icon(
                    LucideIcons.search,
                    size: 18,
                    color: AppTheme.accent.withValues(alpha: 0.6),
                  ),
                  suffixIcon: _isSearching
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppTheme.accent,
                            ),
                          ),
                        )
                      : _searchC.text.isNotEmpty
                      ? IconButton(
                          icon: Icon(
                            LucideIcons.x,
                            size: 16,
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.4,
                            ),
                          ),
                          onPressed: () {
                            _searchC.clear();
                            setState(() => _predictions = []);
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: AppTheme.elevationColor(context, 2),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
                onChanged: _onSearchChanged,
              ),
            ],
          ),
        ),

        // Predictions list
        if (_predictions.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 4),
            constraints: const BoxConstraints(maxHeight: 240),
            decoration: BoxDecoration(
              color: theme.cardColor,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ListView.separated(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(vertical: 4),
              itemCount: _predictions.length,
              separatorBuilder: (_, _) => Divider(
                height: 1,
                indent: 48,
                color: theme.dividerColor.withValues(alpha: 0.2),
              ),
              itemBuilder: (context, index) {
                final p = _predictions[index];
                final isHotelType =
                    p.placeTypes?.any(
                      (t) =>
                          t == 'lodging' || t == 'hotel' || t == 'resort_hotel',
                    ) ??
                    false;

                return ListTile(
                  dense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                  leading: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: isHotelType
                          ? AppTheme.accent.withValues(alpha: 0.12)
                          : theme.colorScheme.onSurface.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      isHotelType ? LucideIcons.hotel : LucideIcons.mapPin,
                      size: 16,
                      color: isHotelType
                          ? AppTheme.accent
                          : theme.colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                  title: Text(
                    p.primaryText,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurface,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: p.secondaryText.isNotEmpty
                      ? Text(
                          p.secondaryText,
                          style: TextStyle(
                            fontSize: 11,
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.5,
                            ),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        )
                      : null,
                  trailing: Icon(
                    LucideIcons.arrowRight,
                    size: 14,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
                  ),
                  onTap: () => _onPlaceSelected(p),
                );
              },
            ),
          ),
      ],
    );
  }

  // ─── Helpers ────────────────────────────────────────────────────────

  Widget _sectionLabel(ThemeData theme, String text) {
    return Text(
      text.toUpperCase(),
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: AppTheme.accent,
        letterSpacing: 1.2,
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    int maxLines = 1,
    TextInputType keyboardType = TextInputType.text,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: keyboardType,
      validator: validator,
      textCapitalization: TextCapitalization.sentences,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, size: 18),
        filled: true,
        fillColor: AppTheme.elevationColor(context, 2),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
      ),
    );
  }

  Widget _stepper(
    ThemeData theme,
    String label,
    int value,
    int min,
    int max,
    ValueChanged<int> onChanged,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      decoration: BoxDecoration(
        color: AppTheme.elevationColor(context, 2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _stepperButton(
                icon: LucideIcons.minus,
                onTap: value > min ? () => onChanged(value - 1) : null,
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  '$value',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ),
              _stepperButton(
                icon: LucideIcons.plus,
                onTap: value < max ? () => onChanged(value + 1) : null,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stepperButton({required IconData icon, VoidCallback? onTap}) {
    final enabled = onTap != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: enabled
              ? AppTheme.accent.withValues(alpha: 0.12)
              : Colors.transparent,
          shape: BoxShape.circle,
        ),
        child: Icon(
          icon,
          size: 14,
          color: enabled
              ? AppTheme.accent
              : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.2),
        ),
      ),
    );
  }
}
