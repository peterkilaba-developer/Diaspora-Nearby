import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:diaspora_nearby/theme/app_theme.dart';
import 'package:diaspora_nearby/features/auth/repository/auth_repository.dart';
import 'package:diaspora_nearby/features/profile/repository/profile_repository.dart';
import 'package:diaspora_nearby/features/real_estate/models/real_estate_listing.dart';
import 'package:diaspora_nearby/features/real_estate/services/real_estate_repository.dart';
import 'package:diaspora_nearby/features/real_estate/widgets/real_estate_listing_card.dart';
import 'package:diaspora_nearby/features/real_estate/screens/create_real_estate_listing_screen.dart';
import 'package:diaspora_nearby/features/real_estate/screens/real_estate_detail_screen.dart';
import 'package:diaspora_nearby/features/travel/widgets/country_filter_toggle.dart';
import 'package:diaspora_nearby/features/travel/widgets/travel_search_field.dart';
import 'package:diaspora_nearby/features/travel/widgets/travel_skeleton_loader.dart';
import 'package:diaspora_nearby/features/real_estate/utils/real_estate_seeder.dart';

/// Browse and search real estate listings filtered by category.
class RealEstateSearchScreen extends ConsumerStatefulWidget {
  final String category; // 'plot', 'farm', 'house'

  const RealEstateSearchScreen({super.key, required this.category});

  @override
  ConsumerState<RealEstateSearchScreen> createState() =>
      _RealEstateSearchScreenState();
}

class _RealEstateSearchScreenState
    extends ConsumerState<RealEstateSearchScreen> {
  String _countryFilter = 'home';
  bool _showSearch = false;
  final _locationController = TextEditingController();

  bool _isLoading = true;
  List<RealEstateListing> _allListings = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadListings();
  }

  @override
  void dispose() {
    _locationController.dispose();
    super.dispose();
  }

  Future<void> _loadListings() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final repo = ref.read(realEstateRepositoryProvider);
      final results =
          await repo.searchListings(category: widget.category, limit: 100);
      if (mounted) {
        setState(() {
          _allListings = results;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('RealEstateSearchScreen load error: $e');
      // Gracefully show empty state instead of error
      if (mounted) {
        setState(() {
          _allListings = [];
          _isLoading = false;
        });
      }
    }
  }

  List<RealEstateListing> _filteredListings(dynamic profile) {
    var list = List<RealEstateListing>.from(_allListings);

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

    // Location text search — match only location fields
    final locQuery = _locationController.text.trim().toLowerCase();
    if (locQuery.isNotEmpty) {
      list = list.where((l) {
        final fields = [
          l.locality, l.subLocality, l.city, l.state,
          l.country, l.address, l.localityLower, l.stateLower,
          l.countryCode,
        ].whereType<String>().map((s) => s.toLowerCase());
        return fields.any((f) => f.contains(locQuery));
      }).toList();
    }

    return list;
  }

  String get _screenTitle {
    switch (widget.category) {
      case 'plot':
        return 'Plots for Sale';
      case 'farm':
        return 'Farms';
      case 'house':
        return 'Houses';
      default:
        return 'Real Estate';
    }
  }

  IconData get _categoryIcon {
    switch (widget.category) {
      case 'plot':
        return LucideIcons.map;
      case 'farm':
        return LucideIcons.sprout;
      case 'house':
        return LucideIcons.home;
      default:
        return LucideIcons.landmark;
    }
  }

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

  PreferredSizeWidget _buildAppBar(ThemeData theme, bool isDark) {
    return AppBar(
      elevation: 0,
      backgroundColor: Colors.transparent,
      titleSpacing: 0,
      title: Text(
        _screenTitle,
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
            if (!_showSearch) _locationController.clear();
          }),
          tooltip: _showSearch ? 'Close search' : 'Search',
        ),
        PopupMenuButton<String>(
          icon: const Icon(LucideIcons.moreVertical, size: 20),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          itemBuilder: (_) => [
            PopupMenuItem(
              value: 'add_listing',
              child: Row(children: [
                Icon(LucideIcons.plus,
                    size: 16, color: theme.colorScheme.onSurface),
                const SizedBox(width: 10),
                const Text('Add Listing'),
              ]),
            ),
            PopupMenuItem(
              value: 'my_listings',
              child: Row(children: [
                Icon(LucideIcons.layoutList,
                    size: 16, color: theme.colorScheme.onSurface),
                const SizedBox(width: 10),
                const Text('My Listings'),
              ]),
            ),
            const PopupMenuDivider(),
            PopupMenuItem(
              value: 'seed',
              child: Row(children: [
                Icon(LucideIcons.database,
                    size: 16, color: theme.colorScheme.onSurface),
                const SizedBox(width: 10),
                const Text('Seed Mock Data'),
              ]),
            ),
            PopupMenuItem(
              value: 'clear_seed',
              child: Row(children: [
                Icon(LucideIcons.trash2,
                    size: 16, color: theme.colorScheme.onSurface),
                const SizedBox(width: 10),
                const Text('Clear Mock Data'),
              ]),
            ),
          ],
          onSelected: (v) async {
            if (v == 'add_listing') {
              final created = await Navigator.push<bool>(
                context,
                MaterialPageRoute(
                  builder: (_) => CreateRealEstateListingScreen(
                    defaultCategory: widget.category,
                  ),
                ),
              );
              if (created == true) _loadListings();
            } else if (v == 'my_listings') {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => _MyRealEstateListingsScreen(
                      category: widget.category),
                ),
              );
            } else if (v == 'seed') {
              final userId =
                  ref.read(authRepositoryProvider).currentUser?.uid ?? '';
              final profile =
                  await ref.read(profileRepositoryProvider).getUserProfile(userId);
              final name = profile?.fullName ?? 'Diaspora Seller';
              await RealEstateSeeder.seed(userId, name);
              _loadListings();
            } else if (v == 'clear_seed') {
              await RealEstateSeeder.clear();
              _loadListings();
            }
          },
        ),
      ],
    );
  }

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
        child: TravelSearchField(
          controller: _locationController,
          hint: 'City, neighborhood, or area...',
          icon: LucideIcons.mapPin,
          onChanged: (_) => setState(() {}),
        ),
      ),
    );
  }

  Widget _buildBody(
      ThemeData theme, bool isDark, List<RealEstateListing> listings) {
    if (_isLoading) {
      return TravelSkeletonLoader(
        label: 'Loading ${widget.category}s...',
        icon: _categoryIcon,
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(LucideIcons.alertCircle,
                size: 40,
                color: theme.colorScheme.error.withOpacity(0.5)),
            const SizedBox(height: 12),
            Text('Error loading listings',
                style: TextStyle(
                    color: theme.colorScheme.error, fontSize: 14)),
            const SizedBox(height: 8),
            TextButton(
                onPressed: _loadListings,
                child: const Text('Retry',
                    style: TextStyle(color: AppTheme.accent))),
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
        itemBuilder: (_, i) => Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: AppTheme.pageHorizontalPadding),
          child: RealEstateListingCard(
            listing: listings[i],
            viewerCountryCode:
                ref.read(userProfileProvider).valueOrNull?.hostCountryCode,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    RealEstateDetailScreen(listing: listings[i]),
              ),
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
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(_categoryIcon,
              size: 48, color: AppTheme.accent.withOpacity(0.3)),
          const SizedBox(height: 16),
          Text('No ${widget.category}s found',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurface.withOpacity(0.6))),
          const SizedBox(height: 8),
          Text(
            _showSearch
                ? 'Try adjusting your search filters'
                : 'No ${widget.category}s listed yet. Be the first!',
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.onSurface.withOpacity(0.4)),
          ),
        ]),
      ),
    );
  }
}

// ─── My Listings screen (simple) ─────────────────────────────────────────

class _MyRealEstateListingsScreen extends ConsumerStatefulWidget {
  final String category;
  const _MyRealEstateListingsScreen({required this.category});

  @override
  ConsumerState<_MyRealEstateListingsScreen> createState() =>
      _MyRealEstateListingsScreenState();
}

class _MyRealEstateListingsScreenState
    extends ConsumerState<_MyRealEstateListingsScreen> {
  bool _isLoading = true;
  List<RealEstateListing> _listings = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final uid =
          ref.read(authRepositoryProvider).currentUser?.uid ?? '';
      final repo = ref.read(realEstateRepositoryProvider);
      final results =
          await repo.getMyListings(uid, category: widget.category);
      if (mounted) setState(() { _listings = results; _isLoading = false; });
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        title: Text('My ${widget.category[0].toUpperCase()}${widget.category.substring(1)} Listings',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppTheme.accent))
          : _listings.isEmpty
              ? Center(
                  child: Text('No listings yet',
                      style: TextStyle(
                          color: theme.colorScheme.onSurface
                              .withOpacity(0.5))))
              : RefreshIndicator(
                  onRefresh: _load,
                  color: AppTheme.accent,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(8),
                    itemCount: _listings.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: 8),
                    itemBuilder: (_, i) => RealEstateListingCard(
                      listing: _listings[i],
                      viewerCountryCode: ref
                          .read(userProfileProvider)
                          .valueOrNull
                          ?.hostCountryCode,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => RealEstateDetailScreen(
                              listing: _listings[i]),
                        ),
                      ),
                    ),
                  ),
                ),
    );
  }
}
