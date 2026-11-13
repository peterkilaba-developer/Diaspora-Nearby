import 'dart:async';
import 'package:universal_io/io.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:diaspora_nearby/core/utils/media_upload_helper.dart';
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
  Timer? _searchDebounce;
  int _searchSeq = 0;
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
  final List<String> _existingPhotoUrls = [];
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
    final city = l.locality ?? l.city ?? '';
    _cityC.text = city;
    _subLocalityC.text = l.subLocality ?? '';
    _stateC.text =
        sanitizeStateForCountry(
          state: l.state,
          city: city,
          countryCode: l.countryCode,
          countryName: l.country,
        ) ??
        '';
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
    if (l.photos.isNotEmpty) _existingPhotoUrls.addAll(l.photos);
  }

  void _prefillFromProfile() {
    final profile = ref.read(userProfileProvider).value;
    if (profile == null) return;
    final city = profile.hostLocation.city ?? '';
    _cityC.text = city;
    _stateC.text =
        sanitizeStateForCountry(
          state: profile.hostLocation.state,
          city: city,
          countryCode: profile.hostCountryCode,
          countryName: profile.hostCountry,
        ) ??
        '';
    _countryC.text = profile.hostCountry ?? '';
    _countryCode = profile.hostCountryCode;
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
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

  void _onSearchChanged(String query) {
    _searchDebounce?.cancel();
    final trimmed = query.trim();
    if (trimmed.length < 2) {
      setState(() {
        _predictions = [];
        _isSearching = false;
      });
      return;
    }

    setState(() => _isSearching = true);
    final seq = ++_searchSeq;

    _searchDebounce = Timer(const Duration(milliseconds: 280), () async {
      try {
        final service = ref.read(googlePlacesServiceProvider);
        final results = await service.autocomplete(
          trimmed,
          filter: PlaceTypeFilter.ALL,
        );

        if (!mounted || seq != _searchSeq) return;
        // Sort lodging/hotel establishments first while keeping all matches
        results.sort((a, b) {
          final aHotel =
              a.placeTypes?.any(
                (t) =>
                    t == 'lodging' ||
                    t == 'hotel' ||
                    t == 'resort_hotel' ||
                    t == 'point_of_interest' ||
                    t == 'establishment',
              ) ??
              false;
          final bHotel =
              b.placeTypes?.any(
                (t) =>
                    t == 'lodging' ||
                    t == 'hotel' ||
                    t == 'resort_hotel' ||
                    t == 'point_of_interest' ||
                    t == 'establishment',
              ) ??
              false;
          if (aHotel != bHotel) return aHotel ? -1 : 1;
          return 0;
        });

        setState(() {
          _predictions = results;
          _isSearching = false;
        });
      } catch (e) {
        if (mounted && seq == _searchSeq) {
          setState(() => _isSearching = false);
        }
      }
    });
  }

  Future<void> _onPlaceSelected(AutocompletePrediction prediction) async {
    _searchDebounce?.cancel();
    FocusScope.of(context).unfocus();
    setState(() {
      _predictions = [];
      _isSearching = false;
      _isFetchingDetails = true;
      _searchC.text = prediction.primaryText;
      if (prediction.primaryText.isNotEmpty) {
        _titleC.text = prediction.primaryText;
      }
      if (prediction.secondaryText.isNotEmpty) {
        _addressC.text = prediction.secondaryText;
      }
    });

    try {
      final service = ref.read(googlePlacesServiceProvider);
      final response = await service.getPlaceDetails(prediction.placeId);

      if (!mounted || response == null) {
        if (mounted) setState(() => _isFetchingDetails = false);
        return;
      }

      final place = response.place;

      // 1. Auto-fill hotel name
      final hotelName = (place.name != null && place.name!.trim().isNotEmpty)
          ? place.name!.trim()
          : prediction.primaryText.trim();
      if (hotelName.isNotEmpty) {
        _titleC.text = hotelName;
      }

      // 2. Auto-fill coordinates
      if (place.latLng != null) {
        _lat = place.latLng!.lat;
        _lng = place.latLng!.lng;
      }

      // 3. Parse address components for street address, neighborhood, city, state, country
      final rawFullAddress =
          place.fullAddress ?? place.address ?? prediction.fullText;
      LocationParsed? parsed;
      if (place.addressComponents != null &&
          place.addressComponents!.isNotEmpty) {
        parsed = parseLocationComponents(
          rawFullAddress,
          place.addressComponents!,
        );
      }

      if (parsed != null) {
        _cityC.text = parsed.city ?? '';
        _subLocalityC.text = parsed.sublocality ?? '';
        _stateC.text = parsed.state ?? '';
        _countryC.text = parsed.country;
        _countryCode = parsed.countryCode;
        _addressC.text =
            (parsed.streetAddress != null &&
                parsed.streetAddress!.trim().isNotEmpty)
            ? parsed.streetAddress!.trim()
            : rawFullAddress;
      } else if (_lat != null && _lng != null) {
        final rev = await service.reverseGeocode(_lat!, _lng!);
        if (rev != null) {
          _cityC.text = (rev['city'] as String?) ?? '';
          _subLocalityC.text = (rev['subLocality'] as String?) ?? '';
          _stateC.text = (rev['state'] as String?) ?? '';
          _countryC.text = (rev['country'] as String?) ?? '';
          _countryCode = rev['countryCode'] as String?;
        }
        if (rawFullAddress.isNotEmpty) {
          _addressC.text = rawFullAddress;
        }
      } else if (rawFullAddress.isNotEmpty) {
        _addressC.text = rawFullAddress;
      }

      // 4. Detect Star Rating (prefer explicit "X-star" in editorial summary, then Google rating)
      final summaryText = place.editorialSummary?.trim() ?? '';
      final starMatch = RegExp(
        r'\b([1-5])\s*-\s*star\b',
        caseSensitive: false,
      ).firstMatch('$summaryText $hotelName');
      if (starMatch != null) {
        _starRating = int.parse(starMatch.group(1)!);
      } else if (place.rating != null) {
        _starRating = place.rating!.round().clamp(1, 5);
      }

      // 5. Detect Hotel Category from name, editorial summary, and Google types
      final combinedLower = '$hotelName $summaryText'.toLowerCase();
      final placeTypes = place.types ?? const <String>[];
      if (combinedLower.contains('resort') ||
          placeTypes.contains('resort_hotel')) {
        _hotelCategory = 'Resort';
      } else if (combinedLower.contains('boutique')) {
        _hotelCategory = 'Boutique Hotel';
      } else if (combinedLower.contains('hostel') ||
          placeTypes.contains('hostel')) {
        _hotelCategory = 'Hostel';
      } else if (combinedLower.contains('motel') ||
          placeTypes.contains('motel')) {
        _hotelCategory = 'Motel';
      } else if (combinedLower.contains('b&b') ||
          combinedLower.contains('bed and breakfast') ||
          combinedLower.contains('bed & breakfast') ||
          placeTypes.contains('bed_and_breakfast')) {
        _hotelCategory = 'Bed & Breakfast';
      } else if (combinedLower.contains('guest house') ||
          combinedLower.contains('guesthouse') ||
          combinedLower.contains('lodge') ||
          placeTypes.contains('guest_house')) {
        _hotelCategory = 'Guest House';
      } else if (combinedLower.contains('business') ||
          combinedLower.contains('conference') ||
          combinedLower.contains('convention')) {
        _hotelCategory = 'Business Hotel';
      } else {
        _hotelCategory = 'Hotel';
      }

      // 6. Auto-fill Description (editorial summary or synthesized overview)
      if (summaryText.isNotEmpty) {
        _descC.text = summaryText;
      } else {
        final locText = formatTieredLocation(
          subLocality: _subLocalityC.text,
          city: _cityC.text,
          state: _stateC.text,
          country: _countryC.text,
          countryCode: _countryCode,
          includeSubLocality: true,
        );
        final ratingNote = place.rating != null
            ? ' Rated ${place.rating!.toStringAsFixed(1)}/5 on Google${place.userRatingsTotal != null ? ' (${place.userRatingsTotal} reviews)' : ''}.'
            : '';
        _descC.text =
            '$hotelName is a $_starRating-star ${_hotelCategory.toLowerCase()}'
            '${locText.isNotEmpty ? ' located in $locText' : ''}.'
            '$ratingNote '
            'Welcoming guests with comfortable accommodations and convenient access to local attractions.';
      }

      // 7. Auto-fill Price per Night (estimate from priceLevel or starRating if empty)
      if (_priceC.text.trim().isEmpty) {
        final int estimatedPrice;
        if (place.priceLevel != null && place.priceLevel! > 0) {
          switch (place.priceLevel!) {
            case 1:
              estimatedPrice = 50;
            case 2:
              estimatedPrice = 95;
            case 3:
              estimatedPrice = 160;
            default:
              estimatedPrice = 260;
          }
        } else {
          switch (_starRating) {
            case 5:
              estimatedPrice = 220;
            case 4:
              estimatedPrice = 135;
            case 3:
              estimatedPrice = 80;
            case 2:
              estimatedPrice = 50;
            default:
              estimatedPrice = 35;
          }
        }
        _priceC.text = '$estimatedPrice';
      }

      // 8. Auto-populate Amenities from text, types, and star class
      final inferredAmenities = <String>{'Wi-Fi', 'AC', 'Parking'};
      if (_starRating >= 4 || _hotelCategory == 'Resort') {
        inferredAmenities.addAll([
          'Restaurant',
          'Room Service',
          'Concierge',
          'Laundry',
          'Bar / Lounge',
        ]);
      }
      if (_starRating >= 5 || _hotelCategory == 'Resort') {
        inferredAmenities.addAll(['Pool', 'Spa', 'Gym']);
      }
      if (_hotelCategory == 'Business Hotel') {
        inferredAmenities.addAll(['Business Center', 'Conference Room']);
      }
      if (combinedLower.contains('pool') ||
          combinedLower.contains('swimming')) {
        inferredAmenities.add('Pool');
      }
      if (combinedLower.contains('spa') ||
          combinedLower.contains('wellness') ||
          combinedLower.contains('massage')) {
        inferredAmenities.add('Spa');
      }
      if (combinedLower.contains('gym') || combinedLower.contains('fitness')) {
        inferredAmenities.add('Gym');
      }
      if (combinedLower.contains('restaurant') ||
          combinedLower.contains('dining') ||
          combinedLower.contains('eatery') ||
          combinedLower.contains('eateries') ||
          combinedLower.contains('breakfast') ||
          placeTypes.contains('restaurant')) {
        inferredAmenities.add('Restaurant');
      }
      if (combinedLower.contains('bar') ||
          combinedLower.contains('lounge') ||
          placeTypes.contains('bar')) {
        inferredAmenities.add('Bar / Lounge');
      }
      if (combinedLower.contains('conference') ||
          combinedLower.contains('meeting') ||
          combinedLower.contains('business')) {
        inferredAmenities.addAll(['Business Center', 'Conference Room']);
      }
      if (combinedLower.contains('airport') ||
          combinedLower.contains('shuttle')) {
        inferredAmenities.add('Airport Shuttle');
      }
      _selectedAmenities
        ..clear()
        ..addAll(
          _allAmenities.where((a) => inferredAmenities.contains(a)),
        );

      // 9. Auto-populate Google Places photos if available
      if (place.photoMetadatas != null && place.photoMetadatas!.isNotEmpty) {
        final urls = <String>[];
        for (final item in place.photoMetadatas!) {
          if (item is Map) {
            final refStr = item['photo_reference']?.toString();
            final url = service.getPlacePhotoUrl(refStr, maxWidth: 1200);
            if (url != null) urls.add(url);
          }
        }
        if (urls.isNotEmpty) {
          _existingPhotoUrls
            ..clear()
            ..addAll(urls.take(20 - _selectedImages.length));
        }
      }

      if (mounted) {
        setState(() => _isFetchingDetails = false);
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
      }
    }
  }

  // ─── Save ───────────────────────────────────────────────────────────

  Future<void> _pickImages() async {
    final totalCurrent = _existingPhotoUrls.length + _selectedImages.length;
    final remaining = 20 - totalCurrent;
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

    final totalPhotos = _existingPhotoUrls.length + _selectedImages.length;
    // Validate minimum 10 photos
    if (totalPhotos < 10 && widget.existing == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Please add at least 10 photos ($totalPhotos/10)',
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

      final repo = ref.read(peerListingRepositoryProvider);
      final isEditing = widget.existing != null;
      final listingId = isEditing
          ? widget.existing!.id
          : repo.generateListingId();
      final imagesToUpload = List<XFile>.from(_selectedImages);
      final existingPhotos = List<String>.from(_existingPhotoUrls);

      final effectiveCountry = _countryC.text.trim().isNotEmpty
          ? _countryC.text.trim()
          : (widget.existing?.country ?? profile.hostCountry);
      final matchedCountry = effectiveCountry != null
          ? country_data.getCountryByName(effectiveCountry)
          : null;
      final effectiveCountryCode =
          _countryCode ??
          matchedCountry?.code ??
          widget.existing?.countryCode ??
          profile.hostCountryCode;
      final cleanCity = _cityC.text.trim();
      final cleanState = sanitizeStateForCountry(
        state: _stateC.text.trim(),
        city: cleanCity,
        countryCode: effectiveCountryCode,
        countryName: effectiveCountry,
      );

      final optimisticListing = PeerListing(
        id: listingId,
        type: 'hotel',
        ownerId: widget.existing?.ownerId ?? user.uid,
        ownerName: profile.fullName,
        ownerPhoto: profile.profileImage,
        title: _titleC.text.trim(),
        description: _descC.text.trim(),
        photos: existingPhotos,
        pricePerUnit: double.tryParse(_priceC.text.trim()) ?? 0,
        currency: widget.existing?.currency ?? 'USD',
        city: cleanCity,
        country: effectiveCountry,
        countryCode: effectiveCountryCode,
        address: _addressC.text.trim(),
        locality: cleanCity,
        subLocality: _subLocalityC.text.trim(),
        state: cleanState,
        localityLower: cleanCity.toLowerCase(),
        stateLower: cleanState?.toLowerCase(),
        lat: _lat ?? widget.existing?.lat,
        lng: _lng ?? widget.existing?.lng,
        status: widget.existing?.status ?? 'active',
        viewCount: widget.existing?.viewCount ?? 0,
        savedCount: widget.existing?.savedCount ?? 0,
        createdAt: widget.existing?.createdAt,
        // Hotel-specific
        hotelCategory: _hotelCategory,
        starRating: _starRating,
        beds: _rooms,
        maxGuests: _maxGuests,
        checkInTime: _checkInTimeC.text.trim(),
        checkOutTime: _checkOutTimeC.text.trim(),
        amenities: List<String>.from(_selectedAmenities),
      );

      repo.cacheListing(optimisticListing);

      if (mounted) {
        final navigator = Navigator.of(context);
        final messenger = ScaffoldMessenger.of(context);
        navigator.pop(true);
        if (!isEditing) {
          navigator.push(
            MaterialPageRoute(
              builder: (_) =>
                  PeerListingDetailScreen(listing: optimisticListing),
            ),
          );
        }
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              isEditing ? 'Hotel listing updated!' : 'Hotel listing created!',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }

      unawaited(() async {
        try {
          final timestamp = DateTime.now().millisecondsSinceEpoch;
          final uploadedUrls = await Future.wait(
            List.generate(imagesToUpload.length, (i) async {
              final xfile = imagesToUpload[i];
              final mediaInfo = MediaUploadHelper.resolve(xfile, 'image');
              final storageRef = FirebaseStorage.instance.ref().child(
                'hotels/${user.uid}/${timestamp}_$i${mediaInfo.extension}',
              );
              final metadata = SettableMetadata(
                contentType: mediaInfo.contentType,
                cacheControl: 'public, max-age=31536000',
              );
              if (kIsWeb || xfile.path.isEmpty) {
                await storageRef.putData(await xfile.readAsBytes(), metadata);
              } else {
                await storageRef.putFile(File(xfile.path), metadata);
              }
              return storageRef.getDownloadURL();
            }),
          );
          final finalPhotos = uploadedUrls.isNotEmpty
              ? [...existingPhotos, ...uploadedUrls]
              : existingPhotos;
          final finalListing = optimisticListing.copyWith(photos: finalPhotos);
          repo.cacheListing(finalListing);
          if (isEditing) {
            await repo.updateListing(listingId, finalListing.toJson());
          } else {
            await repo.createListing(finalListing);
          }
        } catch (e) {
          debugPrint('CreateHotelListingScreen save error: $e');
        }
      }());
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
      if (mounted) {
        setState(() {
          _isSaving = false;
          _isUploading = false;
        });
      }
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
                _buildPlacesSearch(theme),
                const SizedBox(height: 20),

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
                    final countryText = _countryC.text.trim();
                    final cc =
                        _countryCode ??
                        (countryText.isNotEmpty
                            ? country_data.getCountryByName(countryText)?.code
                            : null) ??
                        profile?.hostCountryCode ??
                        '';
                    final hasState = country_data.hasStateLevelForCountry(
                      countryCode: cc,
                      countryName: countryText,
                    );
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
                Builder(
                  builder: (context) {
                    final totalPhotos =
                        _existingPhotoUrls.length + _selectedImages.length;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$totalPhotos/10 minimum  •  Showcase rooms, lobby, pool, restaurant, and surroundings',
                          style: TextStyle(
                            fontSize: 11,
                            color: totalPhotos >= 10
                                ? AppTheme.success
                                : theme.hintColor,
                          ),
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          height: 110,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: totalPhotos + 1,
                            separatorBuilder: (_, _) =>
                                const SizedBox(width: 10),
                            itemBuilder: (context, index) {
                              if (index == 0) {
                                return GestureDetector(
                                  onTap: _pickImages,
                                  child: Container(
                                    width: 110,
                                    decoration: BoxDecoration(
                                      color: AppTheme.elevationColor(
                                        context,
                                        2,
                                      ),
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          LucideIcons.imagePlus,
                                          size: 28,
                                          color: totalPhotos < 10
                                              ? AppTheme.accent
                                              : theme.hintColor,
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          'Add Photos',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                            color: totalPhotos < 10
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

                              final itemIdx = index - 1;
                              final isNetwork =
                                  itemIdx < _existingPhotoUrls.length;
                              return Stack(
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(14),
                                    child: isNetwork
                                        ? Image.network(
                                            _existingPhotoUrls[itemIdx],
                                            width: 110,
                                            height: 110,
                                            fit: BoxFit.cover,
                                            errorBuilder: (_, _, _) =>
                                                Container(
                                                  width: 110,
                                                  height: 110,
                                                  color:
                                                      AppTheme.elevationColor(
                                                        context,
                                                        2,
                                                      ),
                                                  child: Icon(
                                                    LucideIcons.image,
                                                    color: theme.hintColor,
                                                  ),
                                                ),
                                          )
                                        : Image.file(
                                            File(
                                              _selectedImages[itemIdx -
                                                      _existingPhotoUrls.length]
                                                  .path,
                                            ),
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
                                      onTap: () => setState(() {
                                        if (isNetwork) {
                                          _existingPhotoUrls.removeAt(itemIdx);
                                        } else {
                                          _selectedImages.removeAt(
                                            itemIdx - _existingPhotoUrls.length,
                                          );
                                        }
                                      }),
                                      child: Container(
                                        padding: const EdgeInsets.all(4),
                                        decoration: BoxDecoration(
                                          color: Colors.black54,
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
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
                      ],
                    );
                  },
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
