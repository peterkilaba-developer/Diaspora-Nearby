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
import 'package:diaspora_nearby/features/travel/utils/peer_listing_seeder.dart';
import 'package:diaspora_nearby/features/travel/utils/geo_utils.dart';

class StaySearchScreen extends ConsumerStatefulWidget {
  const StaySearchScreen({super.key});

  @override
  ConsumerState<StaySearchScreen> createState() => _StaySearchScreenState();
}

class _StaySearchScreenState extends ConsumerState<StaySearchScreen> {
  // ─── Country toggle ─────────────────────────────────────────────────
  String _countryFilter = 'home'; // 'all', 'host', 'home' — default to home

  // ─── Search panel ───────────────────────────────────────────────────
  bool _showSearch = false;
  final _locationController = TextEditingController();
  final _checkInController = TextEditingController();
  final _checkOutController = TextEditingController();
  int _guests = 1;
  DateTime? _checkInDate;
  DateTime? _checkOutDate;

  // ─── Advanced filters ───────────────────────────────────────────────
  bool _showAdvanced = false;
  String? _propertyType;
  RangeValues _priceRange = const RangeValues(0, 500);
  bool _priceFilterActive = false;
  int _minBeds = 0;
  final List<String> _selectedAmenities = [];

  // ─── Data ───────────────────────────────────────────────────────────
  bool _isLoading = true;
  List<PeerListing> _allListings = [];
  String? _error;

  static const _propertyTypes = [
    'Apartment', 'House', 'Room', 'Villa', 'Studio', 'Condo',
  ];
  static const _filterAmenities = [
    'Wi-Fi', 'Kitchen', 'AC', 'Pool', 'Parking',
    'Washer', 'Gym', 'Workspace', 'TV', 'Heating',
  ];

  @override
  void initState() {
    super.initState();
    _loadListings();
  }

  @override
  void dispose() {
    _locationController.dispose();
    _checkInController.dispose();
    _checkOutController.dispose();
    super.dispose();
  }

  Future<void> _loadListings() async {
    setState(() { _isLoading = true; _error = null; });
    try {
      final repo = ref.read(peerListingRepositoryProvider);
      final results = await repo.searchListings(type: 'stay', limit: 100);
      if (mounted) setState(() { _allListings = results; _isLoading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = '$e'; _isLoading = false; });
    }
  }

  void _clearFilters() {
    setState(() {
      _locationController.clear();
      _checkInController.clear();
      _checkOutController.clear();
      _guests = 1;
      _checkInDate = null;
      _checkOutDate = null;
      _propertyType = null;
      _priceRange = const RangeValues(0, 500);
      _priceFilterActive = false;
      _minBeds = 0;
      _selectedAmenities.clear();
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
          l.locality, l.subLocality, l.city, l.state,
          l.country, l.address, l.localityLower,
        ].whereType<String>().map((s) => s.toLowerCase());
        return fields.any((f) => f.contains(locQuery));
      }).toList();
    }

    // Property type
    if (_propertyType != null) {
      list = list.where((l) =>
          l.propertyType?.toLowerCase() == _propertyType!.toLowerCase(),
      ).toList();
    }

    // Price range
    if (_priceFilterActive) {
      list = list.where((l) =>
          l.pricePerUnit >= _priceRange.start &&
          l.pricePerUnit <= _priceRange.end,
      ).toList();
    }

    // Min beds
    if (_minBeds > 0) {
      list = list.where((l) => (l.beds ?? 0) >= _minBeds).toList();
    }

    // Min guests
    if (_guests > 1) {
      list = list.where((l) => (l.maxGuests ?? 1) >= _guests).toList();
    }

    // Amenities
    if (_selectedAmenities.isNotEmpty) {
      list = list.where((l) {
        final la = l.amenities?.map((a) => a.toLowerCase()).toSet() ?? {};
        return _selectedAmenities.every(
            (a) => la.contains(a.toLowerCase()));
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
    final profile = profileAsync.valueOrNull;
    final listings = _filteredListings(profile);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: _buildAppBar(theme, isDark),
      body: Column(
        children: [
          CountryFilterToggle(
            selected: _countryFilter,
            onChanged: (v) => setState(() => _countryFilter = v),
            hostCountryCode: profile?.hostCountryCode,
            homeCountryCode: profile?.homeCountryCode,
          ),
          if (_showSearch) _buildSearchPanel(theme, isDark),
          Expanded(child: _buildBody(theme, isDark, listings)),
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
        'Find a Stay',
        style: TextStyle(
          fontSize: 18, fontWeight: FontWeight.bold,
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          itemBuilder: (_) => [
            PopupMenuItem(
              value: 'my_listings',
              child: Row(children: [
                Icon(LucideIcons.layoutList, size: 16, color: theme.colorScheme.onSurface),
                const SizedBox(width: 10),
                const Text('My Listings'),
              ]),
            ),
            const PopupMenuDivider(),
            PopupMenuItem(
              value: 'seed',
              child: Row(children: [
                Icon(LucideIcons.database, size: 16, color: theme.colorScheme.onSurface),
                const SizedBox(width: 10),
                const Text('Seed Mock Stays'),
              ]),
            ),
            PopupMenuItem(
              value: 'clear_seed',
              child: Row(children: [
                Icon(LucideIcons.trash2, size: 16, color: theme.colorScheme.onSurface),
                const SizedBox(width: 10),
                const Text('Clear Mock Data'),
              ]),
            ),
          ],
          onSelected: (v) async {
            if (v == 'my_listings') {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const MyListingsScreen(filterType: 'stay'),
                ),
              );
            } else if (v == 'seed') {
              await PeerListingSeeder.seed();
              _loadListings();
            } else if (v == 'clear_seed') {
              await PeerListingSeeder.clear();
              _loadListings();
            }
          },
        ),
      ],
    );
  }

  // ─── Country Toggle ─────────────────────────────────────────────────

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
            Row(children: [
              Expanded(child: TravelDateField(
                controller: _checkInController,
                hint: 'Check-in',
                icon: LucideIcons.calendarDays,
                onTap: () => _pickDate(isCheckIn: true),
              )),
              const SizedBox(width: 8),
              Expanded(child: TravelDateField(
                controller: _checkOutController,
                hint: 'Check-out',
                icon: LucideIcons.calendarDays,
                onTap: () => _pickDate(isCheckIn: false),
              )),
            ]),
            const SizedBox(height: 8),

            // Guests stepper
            TravelStepper(
              label: 'Guests',
              icon: LucideIcons.users,
              value: _guests,
              min: 1,
              max: 20,
              onChanged: (v) => setState(() => _guests = v),
            ),
            const SizedBox(height: 8),

            // Advanced toggle
            GestureDetector(
              onTap: () => setState(() => _showAdvanced = !_showAdvanced),
              child: Row(children: [
                Icon(
                  _showAdvanced ? LucideIcons.chevronUp : LucideIcons.chevronDown,
                  size: 14, color: AppTheme.accent,
                ),
                const SizedBox(width: 4),
                Text(
                  _showAdvanced ? 'Hide filters' : 'More filters',
                  style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w500,
                    color: AppTheme.accent,
                  ),
                ),
              ]),
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
                  child: Text('Clear all',
                    style: TextStyle(fontSize: 11,
                        color: AppTheme.accent.withOpacity(0.8))),
                ),
              ),
          ],
        ),
      ),
    );
  }

  bool get _hasActiveSearchFilters =>
      _locationController.text.isNotEmpty ||
      _propertyType != null ||
      _priceFilterActive ||
      _minBeds > 0 ||
      _guests > 1 ||
      _selectedAmenities.isNotEmpty;

  Widget _searchField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    ValueChanged<String>? onChanged,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.elevationColor(context, 2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        style: const TextStyle(fontSize: 13),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(fontSize: 12, color: Theme.of(context).hintColor),
          prefixIcon: Icon(icon, size: 16, color: AppTheme.accent),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          isDense: true,
        ),
      ),
    );
  }

  Widget _dateTapField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: AppTheme.elevationColor(context, 2),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(children: [
          Icon(icon, size: 16, color: AppTheme.accent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              controller.text.isNotEmpty ? controller.text : hint,
              style: TextStyle(
                fontSize: 12,
                color: controller.text.isNotEmpty
                    ? Theme.of(context).colorScheme.onSurface
                    : Theme.of(context).hintColor,
              ),
            ),
          ),
        ]),
      ),
    );
  }

  Future<void> _pickDate({required bool isCheckIn}) async {
    final now = DateTime.now();
    final firstDate = isCheckIn ? now : (_checkInDate ?? now);
    final lastDate = now.add(const Duration(days: 365));
    final initialDate = isCheckIn
        ? (_checkInDate ?? now)
        : (_checkOutDate ?? _checkInDate?.add(const Duration(days: 1)) ?? now);

    final date = await SmartDatePicker.show(
      context: context,
      title: isCheckIn ? 'Check-in Date' : 'Check-out Date',
      initialDate: initialDate.isBefore(firstDate) ? firstDate : initialDate,
      firstDate: firstDate,
      lastDate: lastDate,
    );

    if (date != null && mounted) {
      setState(() {
        if (isCheckIn) {
          _checkInDate = date;
          _checkInController.text = _formatDate(date);
          // Reset check-out if earlier than new check-in
          if (_checkOutDate != null && !_checkOutDate!.isAfter(date)) {
            _checkOutDate = null;
            _checkOutController.clear();
          }
        } else {
          _checkOutDate = date;
          _checkOutController.text = _formatDate(date);
        }
      });
    }
  }

  String _formatDate(DateTime d) {
    const months = ['Jan','Feb','Mar','Apr','May','Jun',
                    'Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${months[d.month - 1]} ${d.day}, ${d.year}';
  }

  Widget _guestsStepper(ThemeData theme, bool isDark) {
    return TravelStepper(
      label: 'Guests',
      icon: LucideIcons.users,
      value: _guests,
      min: 1,
      max: 20,
      onChanged: (v) => setState(() => _guests = v),
    );
  }

  Widget _buildAdvancedFilters(ThemeData theme, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Property type chips
        Text('Property type',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurface.withOpacity(0.5))),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6, runSpacing: 6,
          children: _propertyTypes.map((t) {
            final sel = _propertyType == t;
            return GestureDetector(
              onTap: () => setState(() => _propertyType = sel ? null : t),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: sel
                      ? AppTheme.accent.withOpacity(isDark ? 0.2 : 0.1)
                      : AppTheme.elevationColor(context, 2),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: sel ? AppTheme.accent.withOpacity(0.4) : Colors.transparent,
                  ),
                ),
                child: Text(t, style: TextStyle(
                  fontSize: 11,
                  fontWeight: sel ? FontWeight.w600 : FontWeight.w400,
                  color: sel ? AppTheme.accent : theme.colorScheme.onSurface.withOpacity(0.6),
                )),
              ),
            );
          }).toList(),
        ),

        // Price range
        const SizedBox(height: 12),
        Row(children: [
          Text('Price range',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurface.withOpacity(0.5))),
          const Spacer(),
          if (_priceFilterActive)
            Text('\$${_priceRange.start.round()} – \$${_priceRange.end.round()}',
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                    color: AppTheme.accent)),
        ]),
        RangeSlider(
          values: _priceRange,
          min: 0, max: 500, divisions: 50,
          activeColor: AppTheme.accent,
          inactiveColor: AppTheme.accent.withOpacity(0.15),
          onChanged: (v) => setState(() {
            _priceRange = v;
            _priceFilterActive = true;
          }),
        ),

        // Min beds stepper
        TravelStepper(
          label: 'Min beds',
          value: _minBeds,
          min: 0,
          max: 10,
          bare: true,
          onChanged: (v) => setState(() => _minBeds = v),
        ),

        // Amenities
        const SizedBox(height: 12),
        Text('Amenities',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurface.withOpacity(0.5))),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6, runSpacing: 6,
          children: _filterAmenities.map((a) {
            final sel = _selectedAmenities.contains(a);
            return GestureDetector(
              onTap: () => setState(() {
                if (sel) { _selectedAmenities.remove(a); }
                else { _selectedAmenities.add(a); }
              }),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: sel
                      ? AppTheme.accent.withOpacity(isDark ? 0.2 : 0.1)
                      : AppTheme.elevationColor(context, 2),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: sel ? AppTheme.accent.withOpacity(0.4) : Colors.transparent,
                  ),
                ),
                child: Text(a, style: TextStyle(
                  fontSize: 11,
                  fontWeight: sel ? FontWeight.w600 : FontWeight.w400,
                  color: sel ? AppTheme.accent : theme.colorScheme.onSurface.withOpacity(0.6),
                )),
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
        label: 'Loading stays...',
        icon: LucideIcons.home,
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(LucideIcons.alertCircle, size: 40,
                color: theme.colorScheme.error.withOpacity(0.5)),
            const SizedBox(height: 12),
            Text('Error loading stays', style: TextStyle(
                color: theme.colorScheme.error, fontSize: 14)),
            const SizedBox(height: 8),
            TextButton(onPressed: _loadListings,
                child: const Text('Retry', style: TextStyle(color: AppTheme.accent))),
          ]),
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
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, i) => PeerListingCard(
          listing: listings[i],
          placeholderIcon: LucideIcons.home,
          viewerCountryCode: ref.read(userProfileProvider).valueOrNull?.hostCountryCode,
          onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => PeerListingDetailScreen(listing: listings[i])),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(LucideIcons.home, size: 48,
              color: AppTheme.accent.withOpacity(0.3)),
          const SizedBox(height: 16),
          Text('No stays found',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurface.withOpacity(0.6))),
          const SizedBox(height: 8),
          Text(
            _hasActiveSearchFilters
                ? 'Try adjusting your search filters'
                : 'No stays are listed yet. Be the first to list!',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12,
                color: theme.colorScheme.onSurface.withOpacity(0.4)),
          ),
        ]),
      ),
    );
  }

  // ─── Listing Card ───────────────────────────────────────────────────

  // Listing card now uses shared PeerListingCard widget
}
