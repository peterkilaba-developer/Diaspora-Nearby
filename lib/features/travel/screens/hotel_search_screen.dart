import 'package:flutter/material.dart';
import 'package:diaspora_nearby/theme/app_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:diaspora_nearby/core/services/google_places_service.dart';
import 'package:diaspora_nearby/features/shared/models/google_places_models.dart';
import 'package:diaspora_nearby/features/profile/repository/profile_repository.dart';
import 'package:diaspora_nearby/features/auth/repository/auth_repository.dart';
import 'package:diaspora_nearby/features/travel/providers/travel_providers.dart';
import 'package:diaspora_nearby/features/travel/widgets/travel_search_interface.dart';
import 'package:diaspora_nearby/features/travel/widgets/travel_management_menu.dart';

import 'package:diaspora_nearby/features/travel/widgets/travel_stepper.dart';
import 'package:diaspora_nearby/features/travel/widgets/travel_date_field.dart';
import 'package:diaspora_nearby/features/travel/models/travel_search_result.dart';
import 'package:diaspora_nearby/features/travel/services/amadeus_service.dart';

import 'package:diaspora_nearby/features/travel/widgets/smart_date_picker.dart';
import 'package:diaspora_nearby/features/travel/utils/geo_utils.dart';
import 'package:diaspora_nearby/features/travel/widgets/travel_skeleton_loader.dart';
import 'package:diaspora_nearby/features/travel/models/peer_listing.dart';
import 'package:diaspora_nearby/features/travel/services/peer_listing_repository.dart';
import 'package:diaspora_nearby/features/travel/widgets/peer_listing_card.dart';
import 'package:diaspora_nearby/features/travel/screens/peer_listing_detail_screen.dart';

class HotelSearchScreen extends ConsumerStatefulWidget {
  const HotelSearchScreen({super.key});

  @override
  ConsumerState<HotelSearchScreen> createState() => _HotelSearchScreenState();
}

class _HotelSearchScreenState extends ConsumerState<HotelSearchScreen> {
  final _destController = TextEditingController();
  final _checkInController = TextEditingController();
  final _checkOutController = TextEditingController();
  final _guestsController = TextEditingController(text: '1');
  int _guests = 1;

  bool _isSearching = false;
  List<HotelOfferResult> _hotelOffers = [];
  List<PeerListing> _peerHotels = []; // community (peer-listed) hotels
  bool _showSearchForm = false; // hidden by default — browse-first
  bool _initialLoading = true; // tracks first auto-load

  // Location data from Google Places
  double? _selectedLat;
  double? _selectedLng;
  String _selectedPlaceDescription = '';

  // Store dates in API format (YYYY-MM-DD)
  String _checkInDateApi = '';
  String _checkOutDateApi = '';

  // Places suggestions
  List<AutocompletePrediction> _placeSuggestions = [];
  bool _showPlaceSuggestions = false;
  bool _isLoadingSuggestions = false;

  String? _homeCountry;
  String? _searchCity;
  String? _searchCountry;

  @override
  void initState() {
    super.initState();
    _setDefaultDates();
    _autoLoadNearbyHotels();
  }

  void _setDefaultDates() {
    final today = DateTime.now();
    final tomorrow = today.add(const Duration(days: 1));

    _checkInDateApi = _toApiDate(today);
    _checkOutDateApi = _toApiDate(tomorrow);
    _checkInController.text = _toDisplayDate(today);
    _checkOutController.text = _toDisplayDate(tomorrow);
  }

  String _toApiDate(DateTime dt) =>
      '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';

  String _toDisplayDate(DateTime dt) => '${dt.month}/${dt.day}/${dt.year}';

  @override
  void dispose() {
    _destController.dispose();
    _checkInController.dispose();
    _checkOutController.dispose();
    _guestsController.dispose();
    super.dispose();
  }

  /// Auto-loads hotels near the user's current location on screen open.
  /// Falls back to home location if current location is unavailable.
  Future<void> _autoLoadNearbyHotels() async {
    final userId = ref.read(authRepositoryProvider).currentUser?.uid;
    if (userId == null) {
      if (mounted) setState(() => _initialLoading = false);
      return;
    }

    final profileData = await ref
        .read(profileRepositoryProvider)
        .getUserProfile(userId);
    if (profileData == null || !mounted) {
      if (mounted) setState(() => _initialLoading = false);
      return;
    }

    // Set home country for empty state
    if (profileData.homeCountry != null && mounted) {
      setState(() => _homeCountry = profileData.homeCountry);
    }

    // Use home town location for auto-load — connecting with home
    double? homeLat, homeLng;
    String locationLabel = '';

    if (profileData.homeLocation.geometry?.location != null) {
      homeLat = profileData.homeLocation.geometry!.location.lat;
      homeLng = profileData.homeLocation.geometry!.location.lng;
      final homeCity = profileData.homeLocation.city;
      final homeCountry = profileData.homeLocation.country;
      locationLabel = [?homeCity, ?homeCountry].join(', ');
      _searchCity = homeCity;
      _searchCountry = homeCountry;
    }

    if (homeLat == null || homeLng == null || !mounted) {
      if (mounted) setState(() => _initialLoading = false);
      return;
    }

    // Set the destination field and coordinates
    setState(() {
      _selectedLat = homeLat;
      _selectedLng = homeLng;
      _selectedPlaceDescription = locationLabel;
      _destController.text = locationLabel;
      _isSearching = true;
    });

    try {
      // Fetch both API hotels and peer-listed hotels in parallel
      final amadeus = ref.read(amadeusServiceProvider);
      final peerRepo = ref.read(peerListingRepositoryProvider);
      final guests = _guests;

      final results = await Future.wait([
        amadeus.searchHotelsByLocation(
          latitude: homeLat,
          longitude: homeLng,
          checkInDate: _checkInDateApi,
          checkOutDate: _checkOutDateApi,
          adults: guests,
          radius: 50, // wider radius for browse mode
          maxResults: 30,
        ),
        peerRepo.searchListings(
          type: 'hotel',
          countryCode: profileData.homeCountryCode,
        ),
      ]);

      if (!mounted) return;

      final offers = results[0] as List<HotelOfferResult>;
      final peerHotels = results[1] as List<PeerListing>;

      // Sort API results by distance from home town
      offers.sort((a, b) {
        final da = (a.latitude != null && a.longitude != null)
            ? GeoUtils.haversine(homeLat!, homeLng!, a.latitude!, a.longitude!)
            : double.infinity;
        final db = (b.latitude != null && b.longitude != null)
            ? GeoUtils.haversine(homeLat!, homeLng!, b.latitude!, b.longitude!)
            : double.infinity;
        return da.compareTo(db);
      });

      setState(() {
        _hotelOffers = offers;
        _peerHotels = peerHotels;
        _isSearching = false;
        _initialLoading = false;
        _showSearchForm = false;
      });
    } catch (e) {
      debugPrint('Auto-load hotels error: $e');
      if (mounted) {
        setState(() {
          _isSearching = false;
          _initialLoading = false;
        });
      }
    }
  }

  Future<void> _searchPlaces(String query) async {
    if (query.length < 2) {
      setState(() {
        _placeSuggestions = [];
        _showPlaceSuggestions = false;
      });
      return;
    }

    setState(() => _isLoadingSuggestions = true);

    try {
      final service = ref.read(googlePlacesServiceProvider);
      // Use REGIONS filter — returns cities, neighborhoods, sub-localities,
      // postal codes, and admin areas. Excludes airports & establishments.
      final results = await service.autocomplete(
        query,
        filter: PlaceTypeFilter.REGIONS,
      );

      if (!mounted) return;
      setState(() {
        _placeSuggestions = results;
        _showPlaceSuggestions = results.isNotEmpty;
        _isLoadingSuggestions = false;
      });
    } catch (e) {
      if (mounted) setState(() => _isLoadingSuggestions = false);
    }
  }

  Future<void> _selectPlace(AutocompletePrediction prediction) async {
    setState(() {
      _destController.text = prediction.fullText.isNotEmpty
          ? prediction.fullText
          : '${prediction.primaryText}, ${prediction.secondaryText}';
      _selectedPlaceDescription = _destController.text;
      _placeSuggestions = [];
      _showPlaceSuggestions = false;
      _searchCity = prediction.primaryText;
      _searchCountry = prediction.secondaryText;
    });

    // Fetch place details to get lat/lng
    try {
      final service = ref.read(googlePlacesServiceProvider);
      final response = await service.getPlaceDetails(prediction.placeId);

      if (response?.place.latLng != null && mounted) {
        setState(() {
          _selectedLat = response!.place.latLng!.lat;
          _selectedLng = response.place.latLng!.lng;
        });
      }
    } catch (e) {
      debugPrint('Failed to get place details: $e');
    }
  }

  void _handleSearch() async {
    if (_selectedLat == null || _selectedLng == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a destination from the suggestions'),
        ),
      );
      return;
    }

    if (_checkInDateApi.isEmpty || _checkOutDateApi.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select check-in and check-out dates'),
        ),
      );
      return;
    }

    setState(() {
      _isSearching = true;
      _showPlaceSuggestions = false;
    });

    try {
      final amadeus = ref.read(amadeusServiceProvider);
      final peerRepo = ref.read(peerListingRepositoryProvider);
      final guests = _guests;

      // Fetch both API hotels and peer-listed hotels in parallel
      final results = await Future.wait([
        amadeus.searchHotelsByLocation(
          latitude: _selectedLat!,
          longitude: _selectedLng!,
          checkInDate: _checkInDateApi,
          checkOutDate: _checkOutDateApi,
          adults: guests,
          maxResults: 15,
        ),
        peerRepo.searchListings(type: 'hotel', city: _selectedPlaceDescription),
      ]);

      if (!mounted) return;

      final offers = results[0] as List<HotelOfferResult>;
      final peerHotels = results[1] as List<PeerListing>;

      // Sort by distance from searched location
      final sLat = _selectedLat!;
      final sLng = _selectedLng!;
      offers.sort((a, b) {
        final da = (a.latitude != null && a.longitude != null)
            ? GeoUtils.haversine(sLat, sLng, a.latitude!, a.longitude!)
            : double.infinity;
        final db = (b.latitude != null && b.longitude != null)
            ? GeoUtils.haversine(sLat, sLng, b.latitude!, b.longitude!)
            : double.infinity;
        return da.compareTo(db);
      });

      setState(() {
        _isSearching = false;
        _showSearchForm = false;
        _hotelOffers = offers;
        _peerHotels = peerHotels;
      });

      if (_hotelOffers.isEmpty && _peerHotels.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No hotels found for this location and dates'),
          ),
        );
        setState(() {
          _showSearchForm = true;
        });
      }
    } on AmadeusException catch (e) {
      if (!mounted) return;
      setState(() {
        _isSearching = false;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Search error: ${e.message}')));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSearching = false;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Connection error: $e')));
    }
  }

  void _handleClear() {
    setState(() {
      _destController.clear();
      _checkInController.clear();
      _checkOutController.clear();
      _guestsController.text = '1';
      _checkInDateApi = '';
      _checkOutDateApi = '';
      _selectedLat = null;
      _selectedLng = null;
      _selectedPlaceDescription = '';
      _placeSuggestions = [];
      _showPlaceSuggestions = false;
      _hotelOffers.clear();
      _peerHotels.clear();
      _showSearchForm = false;
    });
    _setDefaultDates();
    _autoLoadNearbyHotels();
  }

  Future<void> _pickDate(
    TextEditingController controller, {
    required bool isCheckIn,
  }) async {
    final now = DateTime.now();

    DateTime firstDate = now;
    DateTime initialDate = now; // Default to today

    if (isCheckIn) {
      if (_checkInDateApi.isNotEmpty) {
        try {
          initialDate = DateTime.parse(_checkInDateApi);
        } catch (_) {}
      }
    } else {
      // Check-out must be after check-in
      if (_checkInDateApi.isNotEmpty) {
        try {
          final checkIn = DateTime.parse(_checkInDateApi);
          firstDate = checkIn.add(const Duration(days: 1));
          initialDate = checkIn.add(
            const Duration(days: 1),
          ); // Default to day after check-in
          if (_checkOutDateApi.isNotEmpty) {
            final existing = DateTime.parse(_checkOutDateApi);
            if (existing.isAfter(firstDate)) initialDate = existing;
          }
        } catch (_) {}
      }
    }

    if (initialDate.isBefore(firstDate)) initialDate = firstDate;
    final lastDate = now.add(const Duration(days: 365));
    if (initialDate.isAfter(lastDate)) initialDate = lastDate;

    final date = await SmartDatePicker.show(
      context: context,
      title: isCheckIn ? 'Check-in Date' : 'Check-out Date',
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: lastDate,
    );

    if (date != null && mounted) {
      setState(() {
        controller.text = _toDisplayDate(date);
        if (isCheckIn) {
          _checkInDateApi = _toApiDate(date);
          // If check-in moved past check-out, adjust check-out
          if (_checkOutDateApi.isNotEmpty) {
            try {
              final coDate = DateTime.parse(_checkOutDateApi);
              if (!coDate.isAfter(date)) {
                final newCheckout = date.add(const Duration(days: 1));
                _checkOutDateApi = _toApiDate(newCheckout);
                _checkOutController.text = _toDisplayDate(newCheckout);
              }
            } catch (_) {}
          }
        } else {
          _checkOutDateApi = _toApiDate(date);
        }
      });
    }
  }

  Widget _buildLocationField() {
    final theme = Theme.of(context);
    final inputDecoration = InputDecoration(
      filled: true,
      fillColor: AppTheme.elevationColor(context, 2),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      hintText: 'Where? (city, neighborhood, address)',
      prefixIcon: Icon(
        LucideIcons.mapPin,
        color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
      ),
      suffixIcon: _isLoadingSuggestions
          ? const Padding(
              padding: EdgeInsets.all(12),
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          : _destController.text.isNotEmpty
          ? IconButton(
              icon: Icon(
                LucideIcons.x,
                size: 18,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
              ),
              onPressed: () => setState(() {
                _destController.clear();
                _selectedLat = null;
                _selectedLng = null;
                _selectedPlaceDescription = '';
                _placeSuggestions = [];
                _showPlaceSuggestions = false;
              }),
            )
          : null,
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _destController,
          decoration: inputDecoration,
          onChanged: _searchPlaces,
          onTap: () {
            if (_destController.text.length >= 2) {
              _searchPlaces(_destController.text);
            }
          },
        ),
        // Location confirmed indicator
        if (_selectedLat != null && !_showPlaceSuggestions)
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 4),
            child: Row(
              children: [
                Icon(
                  LucideIcons.checkCircle,
                  size: 12,
                  color: Colors.green.shade600,
                ),
                const SizedBox(width: 4),
                Text(
                  'Location confirmed',
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.green.shade600,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        if (_showPlaceSuggestions && _placeSuggestions.isNotEmpty)
          Container(
            constraints: const BoxConstraints(maxHeight: 200),
            margin: const EdgeInsets.only(top: 4),
            decoration: BoxDecoration(
              color: AppTheme.elevationColor(context, 3),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ListView.builder(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              itemCount: _placeSuggestions.length,
              itemBuilder: (context, index) {
                final prediction = _placeSuggestions[index];
                // Show appropriate icon based on place types
                IconData icon = LucideIcons.mapPin;
                if (prediction.placeTypes != null) {
                  final types = prediction.placeTypes!;
                  if (types.contains('sublocality') ||
                      types.contains('sublocality_level_1') ||
                      types.contains('neighborhood')) {
                    icon = LucideIcons.map;
                  } else if (types.contains('locality')) {
                    icon = LucideIcons.building2;
                  } else if (types.contains('postal_code')) {
                    icon = LucideIcons.mail;
                  } else if (types.contains('administrative_area_level_1') ||
                      types.contains('administrative_area_level_2')) {
                    icon = LucideIcons.landmark;
                  } else if (types.contains('country')) {
                    icon = LucideIcons.globe;
                  }
                }
                return ListTile(
                  dense: true,
                  leading: Icon(
                    icon,
                    size: 16,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                  title: Text(
                    prediction.primaryText,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: prediction.secondaryText.isNotEmpty
                      ? Text(
                          prediction.secondaryText,
                          style: TextStyle(
                            fontSize: 11,
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.5,
                            ),
                          ),
                        )
                      : null,
                  onTap: () => _selectPlace(prediction),
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _buildSearchForm() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Destination with Google Places autocomplete
        _buildLocationField(),
        const SizedBox(height: 10),

        // Check-in / Check-out dates
        Row(
          children: [
            Expanded(
              child: TravelDateField(
                controller: _checkInController,
                hint: 'Check-in',
                icon: LucideIcons.calendarDays,
                onTap: () => _pickDate(_checkInController, isCheckIn: true),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TravelDateField(
                controller: _checkOutController,
                hint: 'Check-out',
                icon: LucideIcons.calendarCheck,
                onTap: () => _pickDate(_checkOutController, isCheckIn: false),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        TravelStepper(
          label: 'Guests',
          icon: LucideIcons.users,
          value: _guests,
          min: 1,
          max: 9,
          onChanged: (v) => setState(() {
            _guests = v;
            _guestsController.text = '$v';
          }),
        ),
      ],
    );
  }

  /// Builds a section header label (e.g. "Community Hotels", "Partner Hotels")
  Widget _sectionHeader(
    ThemeData theme,
    IconData icon,
    String label,
    int count,
  ) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 6, left: 4),
      child: Row(
        children: [
          Icon(icon, size: 14, color: AppTheme.accent),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: AppTheme.accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '$count',
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: AppTheme.accent,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bool showAppBarSearch = !_showSearchForm;

    // Total results = peer hotels + optional header + API hotels + optional header
    final hasPeer = _peerHotels.isNotEmpty;
    final hasApi = _hotelOffers.isNotEmpty;
    final totalItems =
        (hasPeer ? _peerHotels.length + 1 : 0) +
        (hasApi ? _hotelOffers.length + 1 : 0);
    final hasAnyResults = hasPeer || hasApi;

    // Create dummy results for the interface's empty check
    final dummyResults = hasAnyResults
        ? [TravelSearchResult(id: 'dummy', title: '', subtitle: '', price: '')]
        : <TravelSearchResult>[];

    return GestureDetector(
      onTap: () {
        setState(() {
          _showPlaceSuggestions = false;
        });
        FocusScope.of(context).unfocus();
      },
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        appBar: AppBar(
          titleSpacing: 0,
          title: const Text('Hotel Search'),
          elevation: 0,
          backgroundColor: Colors.transparent,
          actions: [
            if (showAppBarSearch)
              IconButton(
                icon: const Icon(LucideIcons.search),
                tooltip: 'Modify Search',
                onPressed: () {
                  setState(() {
                    _showSearchForm = true;
                  });
                },
              ),
            const TravelManagementMenu(category: 'Hotel'),
          ],
        ),
        body: _initialLoading
            ? TravelApiSkeletonLoader(
                label: _homeCountry != null
                    ? 'Loading hotels in $_homeCountry...'
                    : 'Loading hotels...',
              )
            : TravelSearchInterface(
                title: 'Find a Hotel',
                icon: LucideIcons.hotel,
                searchForm: _buildSearchForm(),
                isSearching: _isSearching,
                results: dummyResults,
                onClear: _handleClear,
                onSearch: _handleSearch,
                showSearchForm: _showSearchForm,
                emptyStateMessage: _homeCountry != null
                    ? 'Search hotels in $_homeCountry or your next destination'
                    : 'Search hotels at your next destination',
                customResultCount: totalItems,
                customResultBuilder: (context, index) {
                  int cursor = 0;

                  // ── Community Hotels section ──
                  if (hasPeer) {
                    if (index == cursor) {
                      return _sectionHeader(
                        theme,
                        LucideIcons.users,
                        'Community Hotels',
                        _peerHotels.length,
                      );
                    }
                    cursor++;
                    if (index < cursor + _peerHotels.length) {
                      final listing = _peerHotels[index - cursor];
                      return PeerListingCard(
                        listing: listing,
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  PeerListingDetailScreen(listing: listing),
                            ),
                          );
                        },
                      );
                    }
                    cursor += _peerHotels.length;
                  }

                  // ── Partner Hotels section (API) ──
                  if (hasApi) {
                    if (index == cursor) {
                      return _sectionHeader(
                        theme,
                        LucideIcons.building2,
                        'Partner Hotels',
                        _hotelOffers.length,
                      );
                    }
                    cursor++;
                    if (index < cursor + _hotelOffers.length) {
                      final hotel = _hotelOffers[index - cursor];
                      final listing = PeerListing.fromHotelOffer(
                        hotel,
                        city: _searchCity,
                        country: _searchCountry,
                      );
                      return PeerListingCard(
                        listing: listing,
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  PeerListingDetailScreen(listing: listing),
                            ),
                          );
                        },
                      );
                    }
                  }

                  return const SizedBox.shrink();
                },
              ),
      ),
    );
  }
}
