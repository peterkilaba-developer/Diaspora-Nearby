import 'package:flutter/material.dart';
import 'package:diaspora_nearby/theme/app_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:diaspora_nearby/features/profile/repository/profile_repository.dart';
import 'package:diaspora_nearby/features/travel/widgets/smart_date_picker.dart';
import 'package:diaspora_nearby/features/travel/widgets/country_filter_toggle.dart';
import 'package:diaspora_nearby/features/travel/widgets/travel_stepper.dart';
import 'package:diaspora_nearby/features/travel/widgets/travel_search_field.dart';
import 'package:diaspora_nearby/features/travel/widgets/travel_date_field.dart';
import 'package:diaspora_nearby/features/travel/widgets/peer_listing_card.dart';
import 'package:diaspora_nearby/features/travel/models/peer_listing.dart';
import 'package:diaspora_nearby/features/travel/services/peer_listing_repository.dart';
import 'package:diaspora_nearby/features/travel/screens/peer_listing_detail_screen.dart';
import 'package:diaspora_nearby/features/travel/screens/my_listings_screen.dart';
import 'package:diaspora_nearby/features/travel/widgets/travel_skeleton_loader.dart';
import 'package:diaspora_nearby/features/travel/utils/geo_utils.dart';

class CarRentalSearchScreen extends ConsumerStatefulWidget {
  const CarRentalSearchScreen({super.key});

  @override
  ConsumerState<CarRentalSearchScreen> createState() =>
      _CarRentalSearchScreenState();
}

class _CarRentalSearchScreenState extends ConsumerState<CarRentalSearchScreen> {
  // ─── Country toggle ─────────────────────────────────────────────────
  String _countryFilter = 'home'; // 'all', 'host', 'home' — default to home

  // ─── Search panel ───────────────────────────────────────────────────
  bool _showSearch = false;
  final _locationController = TextEditingController();
  final _pickupDateController = TextEditingController();
  final _returnDateController = TextEditingController();
  DateTime? _pickupDate;
  DateTime? _returnDate;

  // ─── Advanced filters ───────────────────────────────────────────────
  bool _showAdvanced = false;
  String? _transmission;
  String? _fuelType;
  RangeValues _priceRange = const RangeValues(0, 300);
  bool _priceFilterActive = false;
  int _minSeats = 0;
  final List<String> _selectedFeatures = [];

  // ─── Data ───────────────────────────────────────────────────────────
  bool _isLoading = true;
  List<PeerListing> _allListings = [];
  String? _error;

  static const _transmissions = ['Automatic', 'Manual'];
  static const _fuelTypes = ['Petrol', 'Diesel', 'Electric', 'Hybrid'];
  static const _filterFeatures = [
    'AC',
    'GPS',
    'Bluetooth',
    'USB Charging',
    'Backup Camera',
    'Dashcam',
    'Roof Rack',
    'Child Seat',
    'Toll Pass',
  ];

  @override
  void initState() {
    super.initState();
    _loadListings();
  }

  @override
  void dispose() {
    _locationController.dispose();
    _pickupDateController.dispose();
    _returnDateController.dispose();
    super.dispose();
  }

  Future<void> _loadListings() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final repo = ref.read(peerListingRepositoryProvider);
      final results = await repo.searchListings(type: 'car', limit: 100);
      if (mounted) {
        setState(() {
          _allListings = results;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _isLoading = false;
        });
      }
    }
  }

  void _clearFilters() {
    setState(() {
      _locationController.clear();
      _pickupDateController.clear();
      _returnDateController.clear();
      _pickupDate = null;
      _returnDate = null;
      _transmission = null;
      _fuelType = null;
      _priceRange = const RangeValues(0, 300);
      _priceFilterActive = false;
      _minSeats = 0;
      _selectedFeatures.clear();
    });
  }

  // ─── Filter + Sort ──────────────────────────────────────────────────

  List<PeerListing> _filteredListings(dynamic profile) {
    var list = List<PeerListing>.from(_allListings);

    // Country filter
    if (_countryFilter != 'all' && profile != null) {
      final filterCode = _countryFilter == 'host'
          ? profile.hostCountryCode as String?
          : profile.homeCountryCode as String?;
      if (filterCode != null) {
        list = list.where((l) {
          final cc = (l.countryCode ?? l.country ?? '').toLowerCase();
          return cc == filterCode.toLowerCase();
        }).toList();
      }
    }

    // Location text search
    final locQuery = _locationController.text.trim().toLowerCase();
    if (locQuery.isNotEmpty) {
      list = list.where((l) {
        final fields = [
          l.locality,
          l.subLocality,
          l.city,
          l.state,
          l.country,
          l.address,
          l.localityLower,
        ].whereType<String>().map((s) => s.toLowerCase());
        return fields.any((f) => f.contains(locQuery));
      }).toList();
    }

    // Transmission
    if (_transmission != null) {
      list = list
          .where(
            (l) =>
                l.transmission?.toLowerCase() == _transmission!.toLowerCase(),
          )
          .toList();
    }

    // Fuel type
    if (_fuelType != null) {
      list = list
          .where((l) => l.fuelType?.toLowerCase() == _fuelType!.toLowerCase())
          .toList();
    }

    // Price range
    if (_priceFilterActive) {
      list = list
          .where(
            (l) =>
                l.pricePerUnit >= _priceRange.start &&
                l.pricePerUnit <= _priceRange.end,
          )
          .toList();
    }

    // Min seats
    if (_minSeats > 0) {
      list = list.where((l) => (l.seats ?? 0) >= _minSeats).toList();
    }

    // Features
    if (_selectedFeatures.isNotEmpty) {
      list = list.where((l) {
        final lf = l.features?.map((f) => f.toLowerCase()).toSet() ?? {};
        return _selectedFeatures.every((f) => lf.contains(f.toLowerCase()));
      }).toList();
    }

    // Sort by proximity to home town
    final (homeLat, homeLng) = GeoUtils.homeLatLng(profile);
    GeoUtils.sortByProximity(list, refLat: homeLat, refLng: homeLng);
    return list;
  }

  // ─── Build ──────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final profileAsync = ref.watch(userProfileProvider);
    final profile = profileAsync.value;
    final listings = _filteredListings(profile);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: _buildAppBar(theme, isDark),
      resizeToAvoidBottomInset: true,
      body: Column(
        children: [
          CountryFilterToggle(
            selected: _countryFilter,
            onChanged: (v) => setState(() => _countryFilter = v),
            hostCountryCode: profile?.hostCountryCode,
            homeCountryCode: profile?.homeCountryCode,
          ),
          Expanded(
            child: CustomScrollView(
              slivers: [
                if (_showSearch)
                  SliverToBoxAdapter(child: _buildSearchPanel(theme, isDark)),
                SliverFillRemaining(
                  hasScrollBody: true,
                  child: _buildBody(theme, isDark, listings),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── AppBar ─────────────────────────────────────────────────────────

  PreferredSizeWidget _buildAppBar(ThemeData theme, bool isDark) {
    return AppBar(
      elevation: 0,
      backgroundColor: Colors.transparent,
      titleSpacing: 0,
      title: Text(
        'Rent a Car',
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: theme.colorScheme.onSurface,
        ),
      ),
      actions: [
        IconButton(
          icon: Icon(
            _showSearch ? LucideIcons.x : LucideIcons.search,
            size: 20,
            color: _showSearch ? AppTheme.accent : null,
          ),
          onPressed: () => setState(() {
            _showSearch = !_showSearch;
            if (!_showSearch) _clearFilters();
          }),
          tooltip: _showSearch ? 'Close search' : 'Search',
        ),
        PopupMenuButton<String>(
          icon: const Icon(LucideIcons.moreVertical, size: 20),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          itemBuilder: (_) => [
            PopupMenuItem(
              value: 'my_listings',
              child: Row(
                children: [
                  Icon(
                    LucideIcons.layoutList,
                    size: 16,
                    color: theme.colorScheme.onSurface,
                  ),
                  const SizedBox(width: 10),
                  const Text('My Listings'),
                ],
              ),
            ),
          ],
          onSelected: (v) async {
            if (v == 'my_listings') {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const MyListingsScreen(filterType: 'car'),
                ),
              );
            }
          },
        ),
      ],
    );
  }

  // Country toggle now uses shared CountryFilterToggle widget

  // ─── Search Panel ───────────────────────────────────────────────────

  Widget _buildSearchPanel(ThemeData theme, bool isDark) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.elevationColor(context, 1),
          borderRadius: BorderRadius.circular(16),
        ),
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Location
            TravelSearchField(
              controller: _locationController,
              hint: 'City, neighborhood, or area...',
              icon: LucideIcons.mapPin,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),

            // Date row
            Row(
              children: [
                Expanded(
                  child: TravelDateField(
                    controller: _pickupDateController,
                    hint: 'Pickup date',
                    icon: LucideIcons.calendarDays,
                    onTap: () => _pickDate(isPickup: true),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TravelDateField(
                    controller: _returnDateController,
                    hint: 'Return date',
                    icon: LucideIcons.calendarDays,
                    onTap: () => _pickDate(isPickup: false),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Advanced toggle
            GestureDetector(
              onTap: () => setState(() => _showAdvanced = !_showAdvanced),
              child: Row(
                children: [
                  Icon(
                    _showAdvanced
                        ? LucideIcons.chevronUp
                        : LucideIcons.chevronDown,
                    size: 14,
                    color: AppTheme.accent,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _showAdvanced ? 'Hide filters' : 'More filters',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: AppTheme.accent,
                    ),
                  ),
                ],
              ),
            ),

            if (_showAdvanced) ...[
              const SizedBox(height: 8),
              _buildAdvancedFilters(theme, isDark),
            ],

            const SizedBox(height: 8),

            // Clear button
            if (_hasActiveSearchFilters)
              Align(
                alignment: Alignment.centerRight,
                child: GestureDetector(
                  onTap: _clearFilters,
                  child: Text(
                    'Clear all',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppTheme.accent.withValues(alpha: 0.8),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  bool get _hasActiveSearchFilters =>
      _locationController.text.isNotEmpty ||
      _transmission != null ||
      _fuelType != null ||
      _priceFilterActive ||
      _minSeats > 0 ||
      _selectedFeatures.isNotEmpty;

  // Search field and date field now use shared widgets

  Future<void> _pickDate({required bool isPickup}) async {
    final now = DateTime.now();
    final firstDate = isPickup ? now : (_pickupDate ?? now);
    final lastDate = now.add(const Duration(days: 365));
    final initialDate = isPickup
        ? (_pickupDate ?? now)
        : (_returnDate ?? _pickupDate?.add(const Duration(days: 1)) ?? now);

    final date = await SmartDatePicker.show(
      context: context,
      title: isPickup ? 'Pickup Date' : 'Return Date',
      initialDate: initialDate.isBefore(firstDate) ? firstDate : initialDate,
      firstDate: firstDate,
      lastDate: lastDate,
    );

    if (date != null && mounted) {
      setState(() {
        if (isPickup) {
          _pickupDate = date;
          _pickupDateController.text = _formatDate(date);
          if (_returnDate != null && !_returnDate!.isAfter(date)) {
            _returnDate = null;
            _returnDateController.clear();
          }
        } else {
          _returnDate = date;
          _returnDateController.text = _formatDate(date);
        }
      });
    }
  }

  String _formatDate(DateTime d) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[d.month - 1]} ${d.day}, ${d.year}';
  }

  Widget _buildAdvancedFilters(ThemeData theme, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Transmission chips
        Text(
          'Transmission',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: _transmissions.map((t) {
            final sel = _transmission == t;
            return GestureDetector(
              onTap: () => setState(() => _transmission = sel ? null : t),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: sel
                      ? AppTheme.accent.withValues(alpha: isDark ? 0.2 : 0.1)
                      : AppTheme.elevationColor(context, 2),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: sel
                        ? AppTheme.accent.withValues(alpha: 0.4)
                        : Colors.transparent,
                  ),
                ),
                child: Text(
                  t,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: sel ? FontWeight.w600 : FontWeight.w400,
                    color: sel
                        ? AppTheme.accent
                        : theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ),
            );
          }).toList(),
        ),

        // Fuel type chips
        const SizedBox(height: 12),
        Text(
          'Fuel type',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: _fuelTypes.map((f) {
            final sel = _fuelType == f;
            return GestureDetector(
              onTap: () => setState(() => _fuelType = sel ? null : f),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: sel
                      ? AppTheme.accent.withValues(alpha: isDark ? 0.2 : 0.1)
                      : AppTheme.elevationColor(context, 2),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: sel
                        ? AppTheme.accent.withValues(alpha: 0.4)
                        : Colors.transparent,
                  ),
                ),
                child: Text(
                  f,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: sel ? FontWeight.w600 : FontWeight.w400,
                    color: sel
                        ? AppTheme.accent
                        : theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ),
            );
          }).toList(),
        ),

        // Price range
        const SizedBox(height: 12),
        Row(
          children: [
            Text(
              'Price range',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
            const Spacer(),
            if (_priceFilterActive)
              Text(
                '\$${_priceRange.start.round()} – \$${_priceRange.end.round()}',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.accent,
                ),
              ),
          ],
        ),
        RangeSlider(
          values: _priceRange,
          min: 0,
          max: 300,
          divisions: 30,
          activeColor: AppTheme.accent,
          inactiveColor: AppTheme.accent.withValues(alpha: 0.15),
          onChanged: (v) => setState(() {
            _priceRange = v;
            _priceFilterActive = true;
          }),
        ),

        // Min seats stepper
        TravelStepper(
          label: 'Min seats',
          value: _minSeats,
          min: 0,
          max: 12,
          bare: true,
          onChanged: (v) => setState(() => _minSeats = v),
        ),

        // Features
        const SizedBox(height: 12),
        Text(
          'Features',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: _filterFeatures.map((f) {
            final sel = _selectedFeatures.contains(f);
            return GestureDetector(
              onTap: () => setState(() {
                if (sel) {
                  _selectedFeatures.remove(f);
                } else {
                  _selectedFeatures.add(f);
                }
              }),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: sel
                      ? AppTheme.accent.withValues(alpha: isDark ? 0.2 : 0.1)
                      : AppTheme.elevationColor(context, 2),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: sel
                        ? AppTheme.accent.withValues(alpha: 0.4)
                        : Colors.transparent,
                  ),
                ),
                child: Text(
                  f,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: sel ? FontWeight.w600 : FontWeight.w400,
                    color: sel
                        ? AppTheme.accent
                        : theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  // ─── Body (Listings) ────────────────────────────────────────────────

  Widget _buildBody(ThemeData theme, bool isDark, List<PeerListing> listings) {
    if (_isLoading) {
      return const TravelSkeletonLoader(
        label: 'Loading cars...',
        icon: LucideIcons.car,
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                LucideIcons.alertCircle,
                size: 40,
                color: theme.colorScheme.error.withValues(alpha: 0.5),
              ),
              const SizedBox(height: 12),
              Text(
                'Error loading cars',
                style: TextStyle(color: theme.colorScheme.error, fontSize: 14),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: _loadListings,
                child: const Text(
                  'Retry',
                  style: TextStyle(color: AppTheme.accent),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (listings.isEmpty) {
      return _buildEmptyState(theme);
    }

    return RefreshIndicator(
      onRefresh: _loadListings,
      color: AppTheme.accent,
      child: ListView.separated(
        padding: const EdgeInsets.only(top: 8, bottom: 80),
        itemCount: listings.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (_, i) => PeerListingCard(
          listing: listings[i],
          placeholderIcon: LucideIcons.car,
          viewerCountryCode: ref
              .read(userProfileProvider)
              .value
              ?.hostCountryCode,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => PeerListingDetailScreen(listing: listings[i]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              LucideIcons.car,
              size: 48,
              color: AppTheme.accent.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 16),
            Text(
              'No cars found',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _hasActiveSearchFilters
                  ? 'Try adjusting your search filters'
                  : 'No cars are listed yet. Be the first to list!',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Listing Card ───────────────────────────────────────────────────

  // Listing card now uses shared PeerListingCard widget
}
