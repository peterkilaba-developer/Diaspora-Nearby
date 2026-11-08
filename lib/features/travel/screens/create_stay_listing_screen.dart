import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:diaspora_nearby/theme/app_theme.dart';
import 'package:diaspora_nearby/features/profile/repository/profile_repository.dart';
import 'package:diaspora_nearby/features/auth/repository/auth_repository.dart';
import 'package:diaspora_nearby/features/travel/models/peer_listing.dart';
import 'package:diaspora_nearby/features/travel/services/peer_listing_repository.dart';
import 'package:diaspora_nearby/core/data/countries.dart' as country_data;
import 'package:diaspora_nearby/features/travel/screens/peer_listing_detail_screen.dart';
import 'package:diaspora_nearby/features/trust/services/trust_service.dart';
import 'package:diaspora_nearby/core/services/google_places_service.dart';
import 'package:diaspora_nearby/core/utils/location_utils.dart';
import 'package:diaspora_nearby/features/shared/models/google_places_models.dart';

class CreateStayListingScreen extends ConsumerStatefulWidget {
  final PeerListing? existing; // If editing
  final bool isPeerHosting;

  const CreateStayListingScreen({
    super.key,
    this.existing,
    this.isPeerHosting = false,
  });

  @override
  ConsumerState<CreateStayListingScreen> createState() =>
      _CreateStayListingScreenState();
}

class _CreateStayListingScreenState
    extends ConsumerState<CreateStayListingScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleC = TextEditingController();
  final _descC = TextEditingController();
  final _priceC = TextEditingController();
  final _addressC = TextEditingController();
  final _cityC = TextEditingController();
  final _subLocalityC = TextEditingController();
  final _stateC = TextEditingController();
  final _locationSearchC = TextEditingController();
  Timer? _searchDebounce;
  int _searchSeq = 0;
  List<AutocompletePrediction> _predictions = [];
  bool _isSearchingLocation = false;
  double? _lat;
  double? _lng;
  String? _country;
  String? _countryCode;

  String _propertyType = 'Apartment';
  int _beds = 1;
  int _baths = 1;
  int _maxGuests = 2;
  final List<String> _selectedAmenities = [];
  bool _isSaving = false;
  bool _isPeerHosting = false;

  static const _propertyTypes = [
    'Apartment',
    'House',
    'Room',
    'Villa',
    'Studio',
    'Condo',
  ];

  static const _allAmenities = [
    'Wi-Fi',
    'Kitchen',
    'Washer',
    'Dryer',
    'AC',
    'Heating',
    'TV',
    'Pool',
    'Parking',
    'Gym',
    'Workspace',
    'Iron',
    'Hair Dryer',
    'First Aid Kit',
    'Smoke Alarm',
    'Lockbox',
  ];

  @override
  void initState() {
    super.initState();
    _isPeerHosting = widget.isPeerHosting;
    if (widget.existing != null) {
      _prefillFromExisting(widget.existing!);
    } else {
      _prefillFromProfile();
      if (_isPeerHosting) {
        _priceC.text = '0';
      }
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
    _country = l.country;
    _countryCode = l.countryCode;
    _lat = l.lat;
    _lng = l.lng;
    _propertyType = l.propertyType ?? 'Apartment';
    _beds = l.beds ?? 1;
    _baths = l.baths ?? 1;
    _maxGuests = l.maxGuests ?? 2;
    _isPeerHosting = l.isPeerHosting;
    if (_isPeerHosting) {
      _priceC.text = '0';
    } else {
      _priceC.text = l.pricePerUnit.toStringAsFixed(0);
    }
    if (l.amenities != null) _selectedAmenities.addAll(l.amenities!);
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
    _country = profile.hostCountry;
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
    _locationSearchC.dispose();
    super.dispose();
  }

  void _onLocationSearchChanged(String query) {
    _searchDebounce?.cancel();
    final trimmed = query.trim();
    if (trimmed.length < 2) {
      setState(() {
        _predictions = [];
        _isSearchingLocation = false;
      });
      return;
    }
    setState(() => _isSearchingLocation = true);
    final seq = ++_searchSeq;
    _searchDebounce = Timer(const Duration(milliseconds: 280), () async {
      try {
        final service = ref.read(googlePlacesServiceProvider);
        final results = await service.autocomplete(
          trimmed,
          filter: PlaceTypeFilter.ALL,
        );
        if (!mounted || seq != _searchSeq) return;
        setState(() {
          _predictions = results;
          _isSearchingLocation = false;
        });
      } catch (_) {
        if (mounted && seq == _searchSeq) {
          setState(() => _isSearchingLocation = false);
        }
      }
    });
  }

  Future<void> _onPlaceSelected(AutocompletePrediction prediction) async {
    _searchDebounce?.cancel();
    FocusScope.of(context).unfocus();
    setState(() {
      _predictions = [];
      _isSearchingLocation = false;
      _locationSearchC.text = prediction.fullText;
    });

    try {
      final service = ref.read(googlePlacesServiceProvider);
      final response = await service.getPlaceDetails(prediction.placeId);
      if (!mounted || response == null) return;
      final place = response.place;
      final rawFull =
          place.fullAddress ?? place.address ?? prediction.fullText;
      if (place.latLng != null) {
        _lat = place.latLng!.lat;
        _lng = place.latLng!.lng;
      }
      if (place.addressComponents != null) {
        final parsed = parseLocationComponents(
          rawFull,
          place.addressComponents!,
        );
        if (parsed != null) {
          setState(() {
            _cityC.text = parsed.city ?? '';
            _subLocalityC.text = parsed.sublocality ?? '';
            _stateC.text = parsed.state ?? '';
            _country = parsed.country;
            _countryCode = parsed.countryCode;
            _addressC.text =
                (parsed.streetAddress != null &&
                    parsed.streetAddress!.isNotEmpty)
                ? parsed.streetAddress!
                : rawFull;
          });
        }
      }
    } catch (_) {}
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      final profile = ref.read(userProfileProvider).value;
      final user = ref.read(authRepositoryProvider).currentUser;
      if (user == null || profile == null) {
        throw Exception('Not logged in');
      }

      final repo = ref.read(peerListingRepositoryProvider);

      if (_isPeerHosting) {
        final trustData = ref.read(userTrustProvider(user.uid)).value;
        if (trustData == null || trustData.trustScore < 91) {
          throw Exception(
            'You need a Trust Score of 91+ to host in Peer Hosting.',
          );
        }
      }

      final isEditing = widget.existing != null;
      final listingId = isEditing
          ? widget.existing!.id
          : repo.generateListingId();

      final effectiveCountry =
          _country ?? widget.existing?.country ?? profile.hostCountry;
      final effectiveCountryCode =
          _countryCode ??
          widget.existing?.countryCode ??
          profile.hostCountryCode;
      final cleanCity = _cityC.text.trim();
      final cleanState = sanitizeStateForCountry(
        state: _stateC.text.trim(),
        city: cleanCity,
        countryCode: effectiveCountryCode,
        countryName: effectiveCountry,
      );

      final listing = PeerListing(
        id: listingId,
        type: 'stay',
        isPeerHosting: _isPeerHosting,
        ownerId: widget.existing?.ownerId ?? user.uid,
        ownerName: profile.fullName,
        ownerPhoto: profile.profileImage,
        title: _titleC.text.trim(),
        description: _descC.text.trim(),
        photos: widget.existing?.photos ?? const [],
        pricePerUnit: _isPeerHosting
            ? 0
            : (double.tryParse(_priceC.text.trim()) ?? 0),
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
        propertyType: _propertyType,
        beds: _beds,
        baths: _baths,
        maxGuests: _maxGuests,
        amenities: List<String>.from(_selectedAmenities),
      );

      repo.cacheListing(listing);

      if (mounted) {
        final navigator = Navigator.of(context);
        final messenger = ScaffoldMessenger.of(context);
        navigator.pop(true);
        if (!isEditing) {
          navigator.push(
            MaterialPageRoute(
              builder: (_) => PeerListingDetailScreen(listing: listing),
            ),
          );
        }
        messenger.showSnackBar(
          SnackBar(
            content: Text(isEditing ? 'Stay updated!' : 'Stay published!'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }

      unawaited(() async {
        try {
          if (isEditing) {
            await repo.updateListing(listingId, listing.toJson());
          } else {
            await repo.createListing(listing);
          }
        } catch (e) {
          debugPrint('CreateStayListingScreen save error: $e');
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
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEditing = widget.existing != null;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Text(isEditing ? 'Edit Stay' : 'Post Stay'),
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: EdgeInsets.only(
            left: 8,
            right: 8,
            top: 8,
            bottom: MediaQuery.of(context).padding.bottom + 16,
          ),
          children: [
            // Property type
            _sectionLabel(theme, 'Property Type'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _propertyTypes.map((t) {
                final selected = _propertyType == t;
                return ChoiceChip(
                  label: Text(t),
                  selected: selected,
                  onSelected: (_) => setState(() => _propertyType = t),
                  selectedColor: AppTheme.accent.withValues(alpha: 0.2),
                  backgroundColor: AppTheme.elevationColor(context, 2),
                  labelStyle: TextStyle(
                    color: selected
                        ? AppTheme.accent
                        : theme.colorScheme.onSurface.withValues(alpha: 0.7),
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
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

            // Title
            _buildTextField(
              controller: _titleC,
              label: 'Stay Title',
              hint: 'e.g. Cozy 2BR Apartment near Downtown',
              icon: LucideIcons.type,
              validator: (v) =>
                  v == null || v.isEmpty ? 'Title is required' : null,
            ),
            const SizedBox(height: 14),

            // Description
            _buildTextField(
              controller: _descC,
              label: 'Description',
              hint:
                  'Describe your space, neighborhood, and what makes it special...',
              icon: LucideIcons.alignLeft,
              maxLines: 4,
              validator: (v) =>
                  v == null || v.isEmpty ? 'Description is required' : null,
            ),
            const SizedBox(height: 14),

            // Price
            if (!_isPeerHosting) ...[
              _buildTextField(
                controller: _priceC,
                label: 'Price per Night (USD)',
                hint: 'e.g. 85',
                icon: LucideIcons.dollarSign,
                keyboardType: TextInputType.number,
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Price is required';
                  if (double.tryParse(v) == null) return 'Enter a valid number';
                  return null;
                },
              ),
              const SizedBox(height: 14),
            ],

            // Location section
            _sectionLabel(theme, 'Location'),
            const SizedBox(height: 8),
            TextFormField(
              controller: _locationSearchC,
              onChanged: _onLocationSearchChanged,
              decoration: InputDecoration(
                labelText: 'Search Address or Area on Google Maps',
                hintText: 'Type address, building, or neighborhood...',
                prefixIcon: const Icon(
                  LucideIcons.search,
                  size: 18,
                  color: AppTheme.accent,
                ),
                suffixIcon: _isSearchingLocation
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
                    : _locationSearchC.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(LucideIcons.x, size: 16),
                        onPressed: () {
                          _locationSearchC.clear();
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
              ),
            ),
            if (_predictions.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(top: 4),
                constraints: const BoxConstraints(maxHeight: 200),
                decoration: BoxDecoration(
                  color: theme.cardColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _predictions.length,
                  itemBuilder: (context, idx) {
                    final p = _predictions[idx];
                    return ListTile(
                      dense: true,
                      leading: const Icon(
                        LucideIcons.mapPin,
                        size: 16,
                        color: AppTheme.accent,
                      ),
                      title: Text(
                        p.primaryText,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: p.secondaryText.isNotEmpty
                          ? Text(
                              p.secondaryText,
                              style: const TextStyle(fontSize: 11),
                            )
                          : null,
                      onTap: () => _onPlaceSelected(p),
                    );
                  },
                ),
              ),
            const SizedBox(height: 12),
            _buildTextField(
              controller: _cityC,
              label: 'City',
              hint: 'e.g. Houston',
              icon: LucideIcons.mapPin,
            ),
            const SizedBox(height: 12),
            Builder(
              builder: (context) {
                final profile = ref.read(userProfileProvider).value;
                final cc = _countryCode ?? profile?.hostCountryCode ?? '';
                final hasState = country_data.hasStateLevelForCountry(
                  countryCode: cc,
                  countryName: _country ?? profile?.hostCountry,
                );
                final stateTerm = country_data.getStateTerminology(cc);

                if (hasState) {
                  return Row(
                    children: [
                      Expanded(
                        child: _buildTextField(
                          controller: _subLocalityC,
                          label: 'Neighborhood / Area',
                          hint: 'e.g. Midtown',
                          icon: LucideIcons.navigation,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildTextField(
                          controller: _stateC,
                          label: stateTerm,
                          hint: 'e.g. Texas',
                          icon: LucideIcons.map,
                        ),
                      ),
                    ],
                  );
                } else {
                  return _buildTextField(
                    controller: _subLocalityC,
                    label: 'Neighborhood / Area',
                    hint: 'e.g. Midtown',
                    icon: LucideIcons.navigation,
                  );
                }
              },
            ),
            const SizedBox(height: 12),
            _buildTextField(
              controller: _addressC,
              label: 'Street Address (optional)',
              hint: 'Full street address',
              icon: LucideIcons.home,
            ),
            const SizedBox(height: 20),

            // Beds, Baths, Guests steppers
            _sectionLabel(theme, 'Capacity'),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _stepper(
                    theme,
                    'Beds',
                    _beds,
                    1,
                    20,
                    (v) => setState(() => _beds = v),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _stepper(
                    theme,
                    'Baths',
                    _baths,
                    1,
                    10,
                    (v) => setState(() => _baths = v),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _stepper(
                    theme,
                    'Guests',
                    _maxGuests,
                    1,
                    30,
                    (v) => setState(() => _maxGuests = v),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Amenities
            _sectionLabel(theme, 'Amenities'),
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
                        : theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  side: BorderSide.none,
                );
              }).toList(),
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
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        isEditing ? 'Update Stay' : 'Publish Stay',
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
    );
  }

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
