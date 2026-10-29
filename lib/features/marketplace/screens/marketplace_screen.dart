import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:diaspora_nearby/theme/app_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:diaspora_nearby/features/travel/widgets/country_filter_toggle.dart';
import 'package:diaspora_nearby/features/profile/repository/profile_repository.dart';
import 'package:diaspora_nearby/features/marketplace/models/marketplace_listing.dart';
import 'package:diaspora_nearby/features/marketplace/repository/marketplace_repository.dart';
import 'package:diaspora_nearby/features/marketplace/data/vehicle_data.dart';
import 'package:diaspora_nearby/features/marketplace/data/motorcycle_data.dart';
import 'package:diaspora_nearby/features/marketplace/widgets/marketplace_card_helpers.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:diaspora_nearby/features/shared/widgets/currency_price_display.dart';

// ─── Category → Icon mapping ────────────────────────────────────────────────
IconData categoryIcon(String id) {
  switch (id) {
    case MarketplaceCategory.vehicles:
      return LucideIcons.car;
    case MarketplaceCategory.motorcycles:
      return LucideIcons.bike;
    case MarketplaceCategory.carParts:
      return LucideIcons.wrench;
    case MarketplaceCategory.realEstate:
      return LucideIcons.home;
    case MarketplaceCategory.electronics:
      return LucideIcons.smartphone;
    case MarketplaceCategory.fashion:
      return LucideIcons.shirt;
    case MarketplaceCategory.foodGrocery:
      return LucideIcons.shoppingBag;
    case MarketplaceCategory.homeGarden:
      return LucideIcons.lamp;
    case MarketplaceCategory.health:
      return LucideIcons.heartPulse;
    case MarketplaceCategory.sports:
      return LucideIcons.trophy;
    case MarketplaceCategory.booksMedia:
      return LucideIcons.bookOpen;
    case MarketplaceCategory.otherProducts:
      return LucideIcons.package;
    case MarketplaceCategory.professional:
      return LucideIcons.briefcase;
    case MarketplaceCategory.techDigital:
      return LucideIcons.code;
    case MarketplaceCategory.education:
      return LucideIcons.graduationCap;
    case MarketplaceCategory.homeServices:
      return LucideIcons.wrench;
    case MarketplaceCategory.transport:
      return LucideIcons.truck;
    case MarketplaceCategory.eventsCatering:
      return LucideIcons.sparkles;
    case MarketplaceCategory.financial:
      return LucideIcons.wallet;
    case MarketplaceCategory.wellness:
      return LucideIcons.heart;
    case MarketplaceCategory.travel:
      return LucideIcons.plane;
    case MarketplaceCategory.otherServices:
      return LucideIcons.settings;
    case MarketplaceCategory.jobTechnology:
      return LucideIcons.laptop;
    case MarketplaceCategory.jobHealthcare:
      return LucideIcons.stethoscope;
    case MarketplaceCategory.jobFinance:
      return LucideIcons.barChart;
    case MarketplaceCategory.jobEngineering:
      return LucideIcons.cog;
    case MarketplaceCategory.jobEducation:
      return LucideIcons.bookOpen;
    case MarketplaceCategory.jobMarketing:
      return LucideIcons.megaphone;
    case MarketplaceCategory.jobSales:
      return LucideIcons.users;
    case MarketplaceCategory.jobCustomerService:
      return LucideIcons.headphones;
    case MarketplaceCategory.jobAdminHR:
      return LucideIcons.folderOpen;
    case MarketplaceCategory.jobConstruction:
      return LucideIcons.hardHat;
    case MarketplaceCategory.jobTransportLogistics:
      return LucideIcons.truck;
    case MarketplaceCategory.jobHospitality:
      return LucideIcons.chefHat;
    case MarketplaceCategory.jobRetail:
      return LucideIcons.shoppingCart;
    case MarketplaceCategory.jobCreativeMedia:
      return LucideIcons.palette;
    case MarketplaceCategory.jobOther:
      return LucideIcons.briefcase;
    default:
      return LucideIcons.package;
  }
}

class MarketplaceScreen extends ConsumerStatefulWidget {
  final String? initialType;
  const MarketplaceScreen({super.key, this.initialType});

  @override
  ConsumerState<MarketplaceScreen> createState() => _MarketplaceScreenState();
}

class _MarketplaceScreenState extends ConsumerState<MarketplaceScreen> {
  String? _selectedCategory;
  late String _selectedType = widget.initialType ?? 'all';
  String _selectedCountryFilter = 'all';
  bool _showSearch = false;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  bool get _hasInitialType =>
      widget.initialType != null && widget.initialType != 'all';

  // Deep category-specific filters
  String? _filterMake;
  String? _filterModel;
  String? _filterYear;
  String? _filterCondition;

  // Job-specific filters
  String? _filterEmploymentType;
  String? _filterWorkMode;
  String? _filterExperienceLevel;

  // Real estate filters
  String? _filterBedrooms;
  String? _filterListingPurpose;

  // Electronics filter
  String? _filterBrand;

  bool get _hasActiveFilters =>
      (!_hasInitialType && _selectedType != 'all') ||
      _selectedCategory != null ||
      _selectedCountryFilter != 'all' ||
      _filterMake != null ||
      _filterModel != null ||
      _filterYear != null ||
      _filterCondition != null ||
      _filterEmploymentType != null ||
      _filterWorkMode != null ||
      _filterExperienceLevel != null ||
      _filterBedrooms != null ||
      _filterListingPurpose != null ||
      _filterBrand != null;

  int get _activeFilterCount {
    int count = 0;
    if (!_hasInitialType && _selectedType != 'all') count++;
    if (_selectedCategory != null) count++;
    if (_selectedCountryFilter != 'all') count++;
    if (_filterMake != null) count++;
    if (_filterModel != null) count++;
    if (_filterYear != null) count++;
    if (_filterCondition != null) count++;
    if (_filterEmploymentType != null) count++;
    if (_filterWorkMode != null) count++;
    if (_filterExperienceLevel != null) count++;
    if (_filterBedrooms != null) count++;
    if (_filterListingPurpose != null) count++;
    if (_filterBrand != null) count++;
    return count;
  }

  void _resetAllFilters() {
    setState(() {
      _selectedType = widget.initialType ?? 'all';
      _selectedCategory = null;
      _selectedCountryFilter = 'all';
      _searchController.clear();
      _searchQuery = '';
      _filterMake = null;
      _filterModel = null;
      _filterYear = null;
      _filterCondition = null;
      _filterEmploymentType = null;
      _filterWorkMode = null;
      _filterExperienceLevel = null;
      _filterBedrooms = null;
      _filterListingPurpose = null;
      _filterBrand = null;
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String get _screenTitle {
    switch (_selectedType) {
      case 'product':
        return 'Products';
      case 'service':
        return 'Services';
      case 'job':
        return 'Jobs';
      default:
        return 'Diaspora Marketplace';
    }
  }

  String get _searchHint {
    switch (_selectedType) {
      case 'product':
        return 'Search products by name, category, or city...';
      case 'service':
        return 'Search services by name, category, or city...';
      case 'job':
        return 'Search jobs by title, category, or city...';
      default:
        return 'Search products, services, or jobs...';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final profileAsync = ref.watch(userProfileProvider);
    final profile = profileAsync.value;
    // final isBusiness = profile?.businessProfile?.isBusinessVerified == true; // [COMMENTED] Re-add for verified business gate later
    final communityIds = profile?.communityMemberships;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: _buildAppBar(theme, isDark),
      body: Column(
        children: [
          // Host / Home country toggle
          CountryFilterToggle(
            selected: _selectedCountryFilter,
            onChanged: (v) => setState(() => _selectedCountryFilter = v),
            hostCountryCode: profile?.hostCountryCode,
            homeCountryCode: profile?.homeCountryCode,
          ),

          // Collapsible dropdown search bar for this category
          if (_showSearch) _buildSearchPanel(theme, isDark),

          // Active filter pills
          if (_hasActiveFilters) _buildActiveFilters(theme, isDark),

          // Listings
          Expanded(
            child: _buildListingsStream(theme, isDark, communityIds, profile),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchPanel(ThemeData theme, bool isDark) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: AppTheme.elevationColor(context, 1),
          borderRadius: BorderRadius.circular(16),
        ),
        padding: const EdgeInsets.all(8),
        child: Container(
          decoration: BoxDecoration(
            color: AppTheme.elevationColor(context, 2),
            borderRadius: BorderRadius.circular(12),
          ),
          child: TextField(
            controller: _searchController,
            autofocus: true,
            onChanged: (value) => setState(() => _searchQuery = value.trim()),
            style: const TextStyle(fontSize: 13),
            decoration: InputDecoration(
              hintText: _searchHint,
              hintStyle: TextStyle(fontSize: 12, color: theme.hintColor),
              prefixIcon: const Icon(
                LucideIcons.search,
                size: 16,
                color: AppTheme.accent,
              ),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(LucideIcons.x, size: 14),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _searchQuery = '');
                      },
                    )
                  : null,
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 12,
              ),
              isDense: true,
            ),
          ),
        ),
      ),
    );
  }

  // ─── AppBar with title + filter icon ──────────────────────────────────
  PreferredSizeWidget _buildAppBar(ThemeData theme, bool isDark) {
    return AppBar(
      elevation: 0,
      backgroundColor: Colors.transparent,
      automaticallyImplyLeading: false,
      leadingWidth: 40,
      leading: IconButton(
        icon: const Icon(LucideIcons.arrowLeft, size: 20),
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(),
        onPressed: () => Navigator.of(context).pop(),
      ),
      titleSpacing: 8,
      title: Text(
        _screenTitle,
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: theme.colorScheme.onSurface,
        ),
      ),
      actions: [
        // Search toggle icon (expands/collapses dropdown search bar)
        IconButton(
          icon: Icon(
            _showSearch ? LucideIcons.x : LucideIcons.search,
            size: 20,
            color: (_showSearch || _searchQuery.isNotEmpty)
                ? AppTheme.accent
                : null,
          ),
          onPressed: () => setState(() {
            _showSearch = !_showSearch;
            if (!_showSearch) {
              _searchController.clear();
              _searchQuery = '';
            }
          }),
          tooltip: _showSearch ? 'Close search' : 'Search',
        ),
        // Filter icon with badge
        Stack(
          clipBehavior: Clip.none,
          children: [
            IconButton(
              icon: Icon(
                LucideIcons.filter,
                size: 20,
                color: _hasActiveFilters ? AppTheme.accent : null,
              ),
              onPressed: () => _showFilterSheet(theme, isDark),
              tooltip: 'Filters',
            ),
            if (_activeFilterCount > 0)
              Positioned(
                right: 4,
                top: 4,
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: const BoxDecoration(
                    color: AppTheme.accent,
                    shape: BoxShape.circle,
                  ),
                  constraints: const BoxConstraints(
                    minWidth: 16,
                    minHeight: 16,
                  ),
                  child: Text(
                    '$_activeFilterCount',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
          ],
        ),
        // ⋮ menu
        PopupMenuButton<String>(
          icon: const Icon(LucideIcons.moreVertical, size: 20),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          itemBuilder: (_) => [
            PopupMenuItem(
              value: 'saved',
              child: Row(
                children: [
                  Icon(
                    LucideIcons.bookmark,
                    size: 16,
                    color: theme.colorScheme.onSurface,
                  ),
                  const SizedBox(width: 10),
                  const Text('Saved Listings'),
                ],
              ),
            ),
            const PopupMenuDivider(),
            PopupMenuItem(
              value: 'my_listings',
              child: Row(
                children: [
                  Icon(
                    LucideIcons.shoppingBag,
                    size: 16,
                    color: theme.colorScheme.onSurface,
                  ),
                  const SizedBox(width: 10),
                  const Text('My Listings'),
                ],
              ),
            ),
            const PopupMenuDivider(),
            if (!_hasInitialType || _selectedType == 'product')
              PopupMenuItem(
                value: 'sell_product',
                child: Row(
                  children: [
                    Icon(
                      LucideIcons.packagePlus,
                      size: 16,
                      color: theme.colorScheme.onSurface,
                    ),
                    const SizedBox(width: 10),
                    const Text('Sell Products'),
                  ],
                ),
              ),
            if (!_hasInitialType || _selectedType == 'service')
              PopupMenuItem(
                value: 'find_clients',
                child: Row(
                  children: [
                    Icon(
                      LucideIcons.users,
                      size: 16,
                      color: theme.colorScheme.onSurface,
                    ),
                    const SizedBox(width: 10),
                    const Text('Find Clients'),
                  ],
                ),
              ),
            if (!_hasInitialType || _selectedType == 'job')
              PopupMenuItem(
                value: 'hire_candidates',
                child: Row(
                  children: [
                    Icon(
                      LucideIcons.userPlus,
                      size: 16,
                      color: theme.colorScheme.onSurface,
                    ),
                    const SizedBox(width: 10),
                    const Text('Hire Candidates'),
                  ],
                ),
              ),
          ],
          onSelected: (value) => _handleMenuAction(
            value,
            profile: ref.read(userProfileProvider).value,
          ),
        ),
      ],
    );
  }

  // ─── Host / Home Country Toggle ─────────────────────────────────────────

  // ─── Active Filter Pills ────────────────────────────────────────────────
  Widget _buildActiveFilters(ThemeData theme, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                if (!_hasInitialType && _selectedType != 'all')
                  _filterPill(
                    icon: _selectedType == 'product'
                        ? LucideIcons.package
                        : _selectedType == 'job'
                        ? LucideIcons.briefcase
                        : LucideIcons.wrench,
                    label: _selectedType == 'product'
                        ? 'Products'
                        : _selectedType == 'job'
                        ? 'Jobs'
                        : 'Services',
                    onRemove: () => setState(() => _selectedType = 'all'),
                    isDark: isDark,
                  ),
                if (_selectedCategory != null)
                  _filterPill(
                    icon: categoryIcon(_selectedCategory!),
                    label: MarketplaceCategory.displayName(_selectedCategory!),
                    onRemove: () => setState(() {
                      _selectedCategory = null;
                      _filterMake = null;
                      _filterModel = null;
                      _filterYear = null;
                      _filterCondition = null;
                      _filterEmploymentType = null;
                      _filterWorkMode = null;
                      _filterExperienceLevel = null;
                      _filterBedrooms = null;
                      _filterListingPurpose = null;
                      _filterBrand = null;
                    }),
                    isDark: isDark,
                  ),
                if (_filterMake != null)
                  _filterPill(
                    icon: LucideIcons.tag,
                    label: _filterMake!,
                    onRemove: () => setState(() {
                      _filterMake = null;
                      _filterModel = null;
                    }),
                    isDark: isDark,
                  ),
                if (_filterModel != null)
                  _filterPill(
                    icon: LucideIcons.tag,
                    label: _filterModel!,
                    onRemove: () => setState(() => _filterModel = null),
                    isDark: isDark,
                  ),
                if (_filterYear != null)
                  _filterPill(
                    icon: LucideIcons.calendar,
                    label: _filterYear!,
                    onRemove: () => setState(() => _filterYear = null),
                    isDark: isDark,
                  ),
                if (_filterCondition != null)
                  _filterPill(
                    icon: LucideIcons.checkCircle,
                    label: ItemCondition.displayName(_filterCondition!),
                    onRemove: () => setState(() => _filterCondition = null),
                    isDark: isDark,
                  ),
                if (_filterEmploymentType != null)
                  _filterPill(
                    icon: LucideIcons.clock,
                    label: _filterEmploymentType!,
                    onRemove: () =>
                        setState(() => _filterEmploymentType = null),
                    isDark: isDark,
                  ),
                if (_filterWorkMode != null)
                  _filterPill(
                    icon: LucideIcons.building,
                    label: _filterWorkMode!,
                    onRemove: () => setState(() => _filterWorkMode = null),
                    isDark: isDark,
                  ),
                if (_filterExperienceLevel != null)
                  _filterPill(
                    icon: LucideIcons.award,
                    label: _filterExperienceLevel!,
                    onRemove: () =>
                        setState(() => _filterExperienceLevel = null),
                    isDark: isDark,
                  ),
                if (_filterBedrooms != null)
                  _filterPill(
                    icon: LucideIcons.bed,
                    label: '${_filterBedrooms}BR',
                    onRemove: () => setState(() => _filterBedrooms = null),
                    isDark: isDark,
                  ),
                if (_filterListingPurpose != null)
                  _filterPill(
                    icon: LucideIcons.home,
                    label: _filterListingPurpose!,
                    onRemove: () =>
                        setState(() => _filterListingPurpose = null),
                    isDark: isDark,
                  ),
                if (_filterBrand != null)
                  _filterPill(
                    icon: LucideIcons.cpu,
                    label: _filterBrand!,
                    onRemove: () => setState(() => _filterBrand = null),
                    isDark: isDark,
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _resetAllFilters,
            child: Text(
              'Clear all',
              style: TextStyle(
                fontSize: 11,
                color: AppTheme.accent.withValues(alpha: 0.8),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _filterPill({
    required IconData icon,
    required String label,
    required VoidCallback onRemove,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.accent.withValues(alpha: isDark ? 0.15 : 0.08),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: AppTheme.accent),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: AppTheme.accent,
            ),
          ),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: onRemove,
            child: Icon(
              LucideIcons.x,
              size: 12,
              color: AppTheme.accent.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Listings Stream ────────────────────────────────────────────────────
  Widget _buildListingsStream(
    ThemeData theme,
    bool isDark,
    List<String>? communityIds,
    dynamic profile,
  ) {
    final repo = ref.watch(marketplaceRepositoryProvider);
    final cachedListings = repo.getCachedListings(
      communityIds: communityIds,
      category: _selectedCategory,
      listingType: _selectedType == 'all' ? null : _selectedType,
    );

    return StreamBuilder<List<MarketplaceListing>>(
      initialData: cachedListings.isNotEmpty ? cachedListings : null,
      stream: repo.getListings(
        communityIds: communityIds,
        category: _selectedCategory,
        listingType: _selectedType == 'all' ? null : _selectedType,
      ),
      builder: (context, snapshot) {
        if (snapshot.hasError && !snapshot.hasData) {
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
                    'Error loading listings',
                    style: TextStyle(
                      color: theme.colorScheme.error,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const Center(
            child: CircularProgressIndicator(color: AppTheme.accent),
          );
        }

        var listings = snapshot.data ?? cachedListings;

        // Apply country filter client-side
        if (_selectedCountryFilter != 'all' && profile != null) {
          final filterCode = _selectedCountryFilter == 'host'
              ? profile.hostCountryCode as String?
              : profile.homeCountryCode as String?;
          if (filterCode != null) {
            listings = listings.where((l) {
              final listingCountry =
                  l.sellerCountryCode ?? l.location?.countryCode;
              return listingCountry?.toLowerCase() == filterCode.toLowerCase();
            }).toList();
          }
        }

        // Apply deep filters client-side
        if (_filterMake != null) {
          listings = listings.where((l) {
            if (l.category == MarketplaceCategory.vehicles) {
              return l.vehicleDetails?['make']?.toString().toLowerCase() ==
                  _filterMake!.toLowerCase();
            } else if (l.category == MarketplaceCategory.motorcycles) {
              return l.motorcycleDetails?['make']?.toString().toLowerCase() ==
                  _filterMake!.toLowerCase();
            } else if (l.category == MarketplaceCategory.carParts) {
              return l.carPartsDetails?['carMake']?.toString().toLowerCase() ==
                  _filterMake!.toLowerCase();
            }
            return true;
          }).toList();
        }
        if (_filterModel != null) {
          listings = listings.where((l) {
            if (l.category == MarketplaceCategory.vehicles) {
              return l.vehicleDetails?['model']?.toString().toLowerCase() ==
                  _filterModel!.toLowerCase();
            } else if (l.category == MarketplaceCategory.motorcycles) {
              return l.motorcycleDetails?['model']?.toString().toLowerCase() ==
                  _filterModel!.toLowerCase();
            } else if (l.category == MarketplaceCategory.carParts) {
              return l.carPartsDetails?['carModel']?.toString().toLowerCase() ==
                  _filterModel!.toLowerCase();
            }
            return true;
          }).toList();
        }
        if (_filterYear != null) {
          listings = listings.where((l) {
            if (l.category == MarketplaceCategory.vehicles) {
              return l.vehicleDetails?['year']?.toString() == _filterYear;
            } else if (l.category == MarketplaceCategory.motorcycles) {
              return l.motorcycleDetails?['year']?.toString() == _filterYear;
            } else if (l.category == MarketplaceCategory.carParts) {
              return l.carPartsDetails?['carYear']?.toString() == _filterYear;
            }
            return true;
          }).toList();
        }
        if (_filterCondition != null) {
          listings = listings
              .where((l) => l.condition == _filterCondition)
              .toList();
        }
        if (_searchQuery.isNotEmpty) {
          final q = _searchQuery.toLowerCase();
          listings = listings.where((l) {
            return l.title.toLowerCase().contains(q) ||
                l.description.toLowerCase().contains(q) ||
                l.category.toLowerCase().contains(q) ||
                (l.subcategory?.toLowerCase().contains(q) ?? false) ||
                (l.sellerCity?.toLowerCase().contains(q) ?? false);
          }).toList();
        }

        if (listings.isEmpty) return _buildEmptyState(theme);

        return ListView.builder(
          padding: const EdgeInsets.only(top: 8, bottom: 80),
          itemCount: listings.length,
          itemBuilder: (_, i) => _buildListingCard(listings[i], theme, isDark),
        );
      },
    );
  }

  // ─── Listing Card (Single Column, Horizontal) ──────────────────────────
  Widget _buildListingCard(
    MarketplaceListing listing,
    ThemeData theme,
    bool isDark,
  ) {
    // For vehicles, use vertical hero-photo card like car rental cards
    if (listing.category == MarketplaceCategory.vehicles) {
      return _buildVehicleCard(listing, theme, isDark);
    }
    return GestureDetector(
      onTap: () {
        ref.read(marketplaceRepositoryProvider).cacheListing(listing);
        context.push('/marketplace/listing/${listing.id}');
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppTheme.elevationColor(context, 1),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: 110,
                height: 110,
                child: MarketplaceListingImage(listing: listing),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: SizedBox(
                height: 110,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      listing.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.onSurface,
                        height: 1.3,
                      ),
                    ),
                    const Spacer(),
                    LocalPriceRow(
                      listing: listing,
                      viewerCountryCode: ref
                          .read(userProfileProvider)
                          .value
                          ?.hostCountryCode,
                    ),
                    const Spacer(),
                    QuickSpecs(listing: listing),
                    const SizedBox(height: 4),
                    MarketplaceCardFooter(listing: listing),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Vehicle Card (vertical hero layout, matching car rental cards) ─────
  Widget _buildVehicleCard(
    MarketplaceListing listing,
    ThemeData theme,
    bool isDark,
  ) {
    final v = listing.vehicleDetails ?? {};
    const radius = 15.0;

    return GestureDetector(
      onTap: () {
        ref.read(marketplaceRepositoryProvider).cacheListing(listing);
        context.push('/marketplace/listing/${listing.id}');
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: AppTheme.elevationColor(context, 1),
          borderRadius: BorderRadius.circular(radius),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Hero Photo ──
            SizedBox(
              height: 140,
              width: double.infinity,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  listing.images.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: listing.images.first,
                          fit: BoxFit.cover,
                          placeholder: (_, _) => Container(
                            color: AppTheme.accent.withValues(alpha: 0.05),
                            child: Center(
                              child: Icon(
                                LucideIcons.car,
                                size: 40,
                                color: AppTheme.accent.withValues(alpha: 0.3),
                              ),
                            ),
                          ),
                          errorWidget: (_, _, _) => Container(
                            color: AppTheme.accent.withValues(alpha: 0.05),
                            child: Center(
                              child: Icon(
                                LucideIcons.car,
                                size: 40,
                                color: AppTheme.accent.withValues(alpha: 0.3),
                              ),
                            ),
                          ),
                        )
                      : Container(
                          color: AppTheme.accent.withValues(
                            alpha: isDark ? 0.08 : 0.05,
                          ),
                          child: Center(
                            child: Icon(
                              LucideIcons.car,
                              size: 40,
                              color: AppTheme.accent.withValues(alpha: 0.3),
                            ),
                          ),
                        ),
                  // Gradient overlay
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    height: 80,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.65),
                          ],
                        ),
                      ),
                    ),
                  ),
                  // Price badge (top-right)
                  Positioned(
                    top: 10,
                    right: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: marketplaceSageGreen,
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.25),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: CurrencyPriceDisplay(
                        amount: listing.priceAmount,
                        sellerCountryCode: listing.sellerCountryCode,
                        viewerCountryCode: ref
                            .read(userProfileProvider)
                            .value
                            ?.hostCountryCode,
                        compact: true,
                        showToggle: false,
                        primaryStyle: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                        secondaryStyle: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                          color: Colors.white70,
                        ),
                      ),
                    ),
                  ),
                  // "For Sale" badge (top-left)
                  Positioned(
                    top: 10,
                    left: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            LucideIcons.car,
                            size: 10,
                            color: Colors.white.withValues(alpha: 0.9),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'For Sale',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w600,
                              color: Colors.white.withValues(alpha: 0.9),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Title overlay (bottom-left)
                  Positioned(
                    bottom: 10,
                    left: 12,
                    right: 80,
                    child: Text(
                      listing.title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        shadows: [Shadow(blurRadius: 4, color: Colors.black54)],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),

            // ── Info area ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Location row
                  if (listing.sellerCity != null) ...[
                    Row(
                      children: [
                        Icon(
                          LucideIcons.mapPin,
                          size: 12,
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.4,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            listing.sellerCity!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: theme.colorScheme.onSurface.withValues(
                                alpha: 0.5,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                  ],
                  // Info chips: car specs
                  Wrap(
                    spacing: 12,
                    runSpacing: 6,
                    children: [
                      if (v['year'] != null)
                        _vehicleInfoChip(
                          theme,
                          LucideIcons.calendar,
                          v['year'].toString(),
                        ),
                      if (v['transmission'] != null)
                        _vehicleInfoChip(
                          theme,
                          LucideIcons.settings,
                          v['transmission'].toString(),
                        ),
                      if (v['fuelType'] != null)
                        _vehicleInfoChip(
                          theme,
                          LucideIcons.fuel,
                          v['fuelType'].toString(),
                        ),
                      if (v['driveType'] != null)
                        _vehicleInfoChip(
                          theme,
                          LucideIcons.gauge,
                          v['driveType'].toString(),
                        ),
                      if (v['mileage'] != null)
                        _vehicleInfoChip(
                          theme,
                          LucideIcons.gauge,
                          '${v['mileage']} km',
                        ),
                    ],
                  ),
                  // Condition badge
                  if (listing.condition != null) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: conditionColor(
                          listing.condition!,
                        ).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        ItemCondition.displayName(listing.condition!),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: conditionColor(listing.condition!),
                        ),
                      ),
                    ),
                  ],
                  // Description
                  if (listing.description.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      listing.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.4,
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.55,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // ── Bottom Bar ──
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: AppTheme.elevationColor(context, 2),
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(radius),
                  bottomRight: Radius.circular(radius),
                ),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 10,
                    backgroundColor: marketplaceSageGreen.withValues(
                      alpha: 0.1,
                    ),
                    child: const Icon(
                      LucideIcons.user,
                      size: 10,
                      color: marketplaceSageGreen,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      listing.sellerName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.6,
                        ),
                      ),
                    ),
                  ),
                  if (listing.sellerCountryCode != null &&
                      listing.sellerCountryCode!.length == 2) ...[
                    Text(
                      _countryFlagEmoji(listing.sellerCountryCode!),
                      style: const TextStyle(fontSize: 12),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      listing.sellerCountryCode!.toUpperCase(),
                      style: TextStyle(fontSize: 10, color: theme.hintColor),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _vehicleInfoChip(ThemeData theme, IconData icon, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 14,
          color: theme.colorScheme.onSurface.withValues(alpha: 0.45),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
          ),
        ),
      ],
    );
  }

  String _countryFlagEmoji(String code) {
    final codeUnits = code.toUpperCase().codeUnits;
    return String.fromCharCodes(codeUnits.map((c) => 0x1F1E6 - 0x41 + c));
  }

  // ─── Search Results ─────────────────────────────────────────────────────

  // ─── Empty State ────────────────────────────────────────────────────────
  Widget _buildEmptyState(ThemeData theme, {bool isSearch = false}) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: theme.hintColor.withValues(alpha: 0.06),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isSearch ? LucideIcons.searchX : LucideIcons.store,
              size: 32,
              color: theme.hintColor.withValues(alpha: 0.3),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            isSearch ? 'No results found' : 'No listings yet',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: theme.hintColor,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            isSearch
                ? 'Try different keywords or adjust filters'
                : 'Be the first to sell in your community!',
            style: TextStyle(
              fontSize: 13,
              color: theme.hintColor.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Filter Bottom Sheet ────────────────────────────────────────────────
  void _showFilterSheet(ThemeData theme, bool isDark) {
    var tempType = _selectedType;
    String? tempCategory = _selectedCategory;
    String? tempMake = _filterMake;
    String? tempModel = _filterModel;
    String? tempYear = _filterYear;
    String? tempCondition = _filterCondition;
    String? tempEmploymentType = _filterEmploymentType;
    String? tempWorkMode = _filterWorkMode;
    String? tempExperienceLevel = _filterExperienceLevel;
    String? tempBedrooms = _filterBedrooms;
    String? tempListingPurpose = _filterListingPurpose;
    String? tempBrand = _filterBrand;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.elevationColor(context, 3), // Level 3 modal
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            // ── Derived state ──
            final hasChosenType = tempType != 'all';
            final showCategory = hasChosenType;

            // Categories based on type
            final categories = tempType == 'service'
                ? MarketplaceCategory.serviceCategories
                : tempType == 'product'
                ? MarketplaceCategory.productCategories
                : tempType == 'job'
                ? MarketplaceCategory.jobCategories
                : [
                    ...MarketplaceCategory.productCategories,
                    ...MarketplaceCategory.jobCategories,
                    ...MarketplaceCategory.serviceCategories,
                  ];

            // Show make/model for vehicle categories
            final showMakeModel =
                tempCategory == MarketplaceCategory.vehicles ||
                tempCategory == MarketplaceCategory.motorcycles ||
                tempCategory == MarketplaceCategory.carParts;

            // Show condition only for product categories (not jobs or services)
            final isProductCategory =
                tempCategory != null &&
                MarketplaceCategory.productCategories.contains(tempCategory);
            final showCondition = isProductCategory;

            // Show real estate filters
            final showRealEstate =
                tempCategory == MarketplaceCategory.realEstate;

            // Show electronics filters
            final showElectronics =
                tempCategory == MarketplaceCategory.electronics;

            // Show job-specific filters
            final isJobCategory =
                tempCategory != null &&
                MarketplaceCategory.jobCategories.contains(tempCategory);
            final showJobFilters = isJobCategory || tempType == 'job';

            // Makes & models
            List<String> makes = [];
            if (tempCategory == MarketplaceCategory.vehicles ||
                tempCategory == MarketplaceCategory.carParts) {
              makes = VehicleData.brands;
            } else if (tempCategory == MarketplaceCategory.motorcycles) {
              makes = MotorcycleData.brands;
            }

            List<String> models = [];
            if (tempMake != null) {
              if (tempCategory == MarketplaceCategory.vehicles ||
                  tempCategory == MarketplaceCategory.carParts) {
                models = VehicleData.getModels(tempMake!);
              } else if (tempCategory == MarketplaceCategory.motorcycles) {
                models = MotorcycleData.getModels(tempMake!);
              }
            }

            final currentYear = DateTime.now().year;
            final years = List.generate(
              currentYear - 1979,
              (i) => (currentYear - i).toString(),
            );

            // ── Count temp-active filters ──
            int tempCount = 0;

            if (!_hasInitialType && tempType != 'all') tempCount++;
            if (tempCategory != null) tempCount++;
            if (tempMake != null) tempCount++;
            if (tempModel != null) tempCount++;
            if (tempYear != null) tempCount++;
            if (tempCondition != null) tempCount++;
            if (tempEmploymentType != null) tempCount++;
            if (tempWorkMode != null) tempCount++;
            if (tempExperienceLevel != null) tempCount++;
            if (tempBedrooms != null) tempCount++;
            if (tempListingPurpose != null) tempCount++;
            if (tempBrand != null) tempCount++;

            // ── Helpers ──
            Widget sectionLabel(String text) => Padding(
              padding: const EdgeInsets.only(bottom: 10, top: 4),
              child: Text(
                text,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1,
                  color: theme.hintColor,
                ),
              ),
            );

            InputDecoration dropdownDeco(String hint) => InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(
                color: theme.hintColor.withValues(alpha: 0.6),
                fontSize: 13,
              ),
              filled: true,
              fillColor: isDark
                  ? Colors.white.withValues(alpha: 0.04)
                  : Colors.black.withValues(alpha: 0.03),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 12,
              ),
              isDense: true,
            );

            // ── Active-filter chip builder (inside modal) ──
            Widget activeChip(
              IconData icon,
              String label,
              VoidCallback onRemove,
            ) {
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.accent.withValues(
                    alpha: isDark ? 0.15 : 0.08,
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 11, color: AppTheme.accent),
                    const SizedBox(width: 4),
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: AppTheme.accent,
                      ),
                    ),
                    const SizedBox(width: 3),
                    GestureDetector(
                      onTap: onRemove,
                      child: Icon(
                        LucideIcons.x,
                        size: 11,
                        color: AppTheme.accent.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ),
              );
            }

            return BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: SafeArea(
                child: DraggableScrollableSheet(
                  initialChildSize: 0.85,
                  maxChildSize: 0.92,
                  minChildSize: 0.4,
                  expand: false,
                  builder: (_, scrollController) => Padding(
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
                  child: ListView(
                    controller: scrollController,
                    children: [
                      // ── Handle ──
                      Center(
                        child: Container(
                          width: 36,
                          height: 4,
                          decoration: BoxDecoration(
                            color: theme.hintColor.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // ── Title row with count badge + Reset ──
                      Row(
                        children: [
                          Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Icon(
                                LucideIcons.filter,
                                size: 18,
                                color: tempCount > 0
                                    ? AppTheme.accent
                                    : theme.colorScheme.onSurface,
                              ),
                              if (tempCount > 0)
                                Positioned(
                                  right: -6,
                                  top: -4,
                                  child: Container(
                                    padding: const EdgeInsets.all(2.5),
                                    decoration: const BoxDecoration(
                                      color: AppTheme.accent,
                                      shape: BoxShape.circle,
                                    ),
                                    constraints: const BoxConstraints(
                                      minWidth: 14,
                                      minHeight: 14,
                                    ),
                                    child: Text(
                                      '$tempCount',
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        fontSize: 8,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(width: 10),
                          Text(
                            'Filters',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                          const Spacer(),
                          if (tempCount > 0)
                            TextButton(
                              onPressed: () => setSheetState(() {
                                tempType = widget.initialType ?? 'all';
                                tempCategory = null;
                                tempMake = null;
                                tempModel = null;
                                tempYear = null;
                                tempCondition = null;
                                tempEmploymentType = null;
                                tempWorkMode = null;
                                tempExperienceLevel = null;
                                tempBedrooms = null;
                                tempListingPurpose = null;
                                tempBrand = null;
                              }),
                              child: const Text(
                                'Reset',
                                style: TextStyle(
                                  color: AppTheme.accent,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                        ],
                      ),

                      // ── Active filter chips (top of modal) ──
                      if (tempCount > 0) ...[
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            if (!_hasInitialType && tempType != 'all')
                              activeChip(
                                tempType == 'product'
                                    ? LucideIcons.package
                                    : tempType == 'job'
                                    ? LucideIcons.briefcase
                                    : LucideIcons.wrench,
                                tempType == 'product'
                                    ? 'Products'
                                    : tempType == 'job'
                                    ? 'Jobs'
                                    : 'Services',
                                () => setSheetState(() {
                                  tempType = 'all';
                                  tempCategory = null;
                                  tempMake = null;
                                  tempModel = null;
                                  tempCondition = null;
                                  tempEmploymentType = null;
                                  tempWorkMode = null;
                                  tempExperienceLevel = null;
                                  tempBedrooms = null;
                                  tempListingPurpose = null;
                                  tempBrand = null;
                                }),
                              ),

                            if (tempCategory != null)
                              activeChip(
                                categoryIcon(tempCategory!),
                                MarketplaceCategory.displayName(tempCategory!),
                                () => setSheetState(() {
                                  tempCategory = null;
                                  tempMake = null;
                                  tempModel = null;
                                  tempYear = null;
                                  tempCondition = null;
                                  tempEmploymentType = null;
                                  tempWorkMode = null;
                                  tempExperienceLevel = null;
                                  tempBedrooms = null;
                                  tempListingPurpose = null;
                                  tempBrand = null;
                                }),
                              ),
                            if (tempMake != null)
                              activeChip(
                                LucideIcons.tag,
                                tempMake!,
                                () => setSheetState(() {
                                  tempMake = null;
                                  tempModel = null;
                                }),
                              ),
                            if (tempModel != null)
                              activeChip(
                                LucideIcons.tag,
                                tempModel!,
                                () => setSheetState(() => tempModel = null),
                              ),
                            if (tempYear != null)
                              activeChip(
                                LucideIcons.calendar,
                                tempYear!,
                                () => setSheetState(() => tempYear = null),
                              ),
                            if (tempCondition != null)
                              activeChip(
                                LucideIcons.checkCircle,
                                ItemCondition.displayName(tempCondition!),
                                () => setSheetState(() => tempCondition = null),
                              ),
                            if (tempEmploymentType != null)
                              activeChip(
                                LucideIcons.clock,
                                tempEmploymentType!,
                                () => setSheetState(
                                  () => tempEmploymentType = null,
                                ),
                              ),
                            if (tempWorkMode != null)
                              activeChip(
                                LucideIcons.building,
                                tempWorkMode!,
                                () => setSheetState(() => tempWorkMode = null),
                              ),
                            if (tempExperienceLevel != null)
                              activeChip(
                                LucideIcons.award,
                                tempExperienceLevel!,
                                () => setSheetState(
                                  () => tempExperienceLevel = null,
                                ),
                              ),
                            if (tempBedrooms != null)
                              activeChip(
                                LucideIcons.bed,
                                '${tempBedrooms}BR',
                                () => setSheetState(() => tempBedrooms = null),
                              ),
                            if (tempListingPurpose != null)
                              activeChip(
                                LucideIcons.home,
                                tempListingPurpose!,
                                () => setSheetState(
                                  () => tempListingPurpose = null,
                                ),
                              ),
                            if (tempBrand != null)
                              activeChip(
                                LucideIcons.cpu,
                                tempBrand!,
                                () => setSheetState(() => tempBrand = null),
                              ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 16),

                      // ═══════════════════════════════════════
                      // ── TYPE (only when not opened for a specific category) ──
                      // ═══════════════════════════════════════
                      if (!_hasInitialType) ...[
                        sectionLabel('TYPE'),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _sheetChip('All', 'all', tempType, isDark, (v) {
                              setSheetState(() {
                                tempType = v;
                                tempCategory = null;
                                tempMake = null;
                                tempModel = null;
                                tempYear = null;
                                tempCondition = null;
                                tempEmploymentType = null;
                                tempWorkMode = null;
                                tempExperienceLevel = null;
                                tempBedrooms = null;
                                tempListingPurpose = null;
                                tempBrand = null;
                              });
                            }),
                            _sheetChip(
                              'Products',
                              'product',
                              tempType,
                              isDark,
                              (v) {
                                setSheetState(() {
                                  tempType = v;
                                  tempCategory = null;
                                  tempMake = null;
                                  tempModel = null;
                                  tempYear = null;
                                  tempEmploymentType = null;
                                  tempWorkMode = null;
                                  tempExperienceLevel = null;
                                });
                              },
                              icon: LucideIcons.package,
                            ),
                            _sheetChip(
                              'Jobs',
                              'job',
                              tempType,
                              isDark,
                              (v) {
                                setSheetState(() {
                                  tempType = v;
                                  tempCategory = null;
                                  tempMake = null;
                                  tempModel = null;
                                  tempYear = null;
                                  tempCondition = null;
                                  tempBedrooms = null;
                                  tempListingPurpose = null;
                                  tempBrand = null;
                                });
                              },
                              icon: LucideIcons.briefcase,
                            ),
                            _sheetChip(
                              'Services',
                              'service',
                              tempType,
                              isDark,
                              (v) {
                                setSheetState(() {
                                  tempType = v;
                                  tempCategory = null;
                                  tempMake = null;
                                  tempModel = null;
                                  tempYear = null;
                                  tempCondition = null;
                                  tempBedrooms = null;
                                  tempListingPurpose = null;
                                  tempBrand = null;
                                  tempEmploymentType = null;
                                  tempWorkMode = null;
                                  tempExperienceLevel = null;
                                });
                              },
                              icon: LucideIcons.wrench,
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                      ],

                      // ═══════════════════════════════════════
                      // ── CATEGORY (revealed once type chosen) ──
                      // ═══════════════════════════════════════
                      if (showCategory) ...[
                        sectionLabel('CATEGORY'),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _sheetChip(
                              'All',
                              '__all__',
                              tempCategory ?? '__all__',
                              isDark,
                              (_) => setSheetState(() {
                                tempCategory = null;
                                tempMake = null;
                                tempModel = null;
                                tempYear = null;
                                tempCondition = null;
                                tempEmploymentType = null;
                                tempWorkMode = null;
                                tempExperienceLevel = null;
                                tempBedrooms = null;
                                tempListingPurpose = null;
                                tempBrand = null;
                              }),
                            ),
                            // When a category is selected, show only that one;
                            // otherwise show all available categories.
                            if (tempCategory != null)
                              _sheetChip(
                                MarketplaceCategory.displayName(tempCategory!),
                                tempCategory!,
                                tempCategory!,
                                isDark,
                                (v) => setSheetState(() {
                                  tempCategory = v;
                                  tempMake = null;
                                  tempModel = null;
                                  tempYear = null;
                                  tempCondition = null;
                                  tempEmploymentType = null;
                                  tempWorkMode = null;
                                  tempExperienceLevel = null;
                                  tempBedrooms = null;
                                  tempListingPurpose = null;
                                  tempBrand = null;
                                }),
                                icon: categoryIcon(tempCategory!),
                              )
                            else
                              for (final cat in categories)
                                _sheetChip(
                                  MarketplaceCategory.displayName(cat),
                                  cat,
                                  tempCategory ?? '',
                                  isDark,
                                  (v) => setSheetState(() {
                                    tempCategory = v;
                                    tempMake = null;
                                    tempModel = null;
                                    tempYear = null;
                                    tempCondition = null;
                                    tempEmploymentType = null;
                                    tempWorkMode = null;
                                    tempExperienceLevel = null;
                                    tempBedrooms = null;
                                    tempListingPurpose = null;
                                    tempBrand = null;
                                  }),
                                  icon: categoryIcon(cat),
                                ),
                          ],
                        ),
                      ],

                      // ═══════════════════════════════════════
                      // ── MAKE / MODEL / YEAR (vehicle categories) ──
                      // ═══════════════════════════════════════
                      if (showMakeModel) ...[
                        const SizedBox(height: 16),
                        sectionLabel('MAKE'),
                        DropdownButtonFormField<String>(
                          initialValue: tempMake,
                          decoration: dropdownDeco('Any Make'),
                          isExpanded: true,
                          menuMaxHeight: 300,
                          style: TextStyle(
                            fontSize: 13,
                            color: theme.colorScheme.onSurface,
                          ),
                          items: [
                            const DropdownMenuItem(
                              value: null,
                              child: Text(
                                'Any Make',
                                style: TextStyle(fontSize: 13),
                              ),
                            ),
                            ...makes.map(
                              (m) => DropdownMenuItem(
                                value: m,
                                child: Text(
                                  m,
                                  style: const TextStyle(fontSize: 13),
                                ),
                              ),
                            ),
                          ],
                          onChanged: (v) => setSheetState(() {
                            tempMake = v;
                            tempModel = null;
                          }),
                        ),

                        if (tempMake != null && models.isNotEmpty) ...[
                          const SizedBox(height: 14),
                          sectionLabel('MODEL'),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _sheetChip(
                                'All Models',
                                '__all__',
                                tempModel ?? '__all__',
                                isDark,
                                (_) => setSheetState(() => tempModel = null),
                              ),
                              for (final model in models)
                                _sheetChip(
                                  model,
                                  model,
                                  tempModel ?? '',
                                  isDark,
                                  (v) => setSheetState(() => tempModel = v),
                                ),
                            ],
                          ),
                        ],

                        const SizedBox(height: 14),
                        sectionLabel('YEAR'),
                        DropdownButtonFormField<String>(
                          initialValue: tempYear,
                          decoration: dropdownDeco('Any Year'),
                          isExpanded: true,
                          menuMaxHeight: 300,
                          style: TextStyle(
                            fontSize: 13,
                            color: theme.colorScheme.onSurface,
                          ),
                          items: [
                            const DropdownMenuItem(
                              value: null,
                              child: Text(
                                'Any Year',
                                style: TextStyle(fontSize: 13),
                              ),
                            ),
                            ...years.map(
                              (y) => DropdownMenuItem(
                                value: y,
                                child: Text(
                                  y,
                                  style: const TextStyle(fontSize: 13),
                                ),
                              ),
                            ),
                          ],
                          onChanged: (v) => setSheetState(() => tempYear = v),
                        ),
                      ],

                      // ═══════════════════════════════════════
                      // ── CONDITION (only for product categories) ──
                      // ═══════════════════════════════════════
                      if (showCondition) ...[
                        const SizedBox(height: 16),
                        sectionLabel('CONDITION'),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _sheetChip(
                              'Any',
                              '__all__',
                              tempCondition ?? '__all__',
                              isDark,
                              (_) => setSheetState(() => tempCondition = null),
                            ),
                            _sheetChip(
                              'New',
                              ItemCondition.brandNew,
                              tempCondition ?? '',
                              isDark,
                              (v) => setSheetState(() => tempCondition = v),
                              icon: LucideIcons.sparkles,
                            ),
                            _sheetChip(
                              'Like New',
                              ItemCondition.likeNew,
                              tempCondition ?? '',
                              isDark,
                              (v) => setSheetState(() => tempCondition = v),
                              icon: LucideIcons.checkCircle,
                            ),
                            _sheetChip(
                              'Used - Good',
                              ItemCondition.usedGood,
                              tempCondition ?? '',
                              isDark,
                              (v) => setSheetState(() => tempCondition = v),
                              icon: LucideIcons.thumbsUp,
                            ),
                            _sheetChip(
                              'Used - Fair',
                              ItemCondition.usedFair,
                              tempCondition ?? '',
                              isDark,
                              (v) => setSheetState(() => tempCondition = v),
                              icon: LucideIcons.alertTriangle,
                            ),
                          ],
                        ),
                      ],

                      // ═══════════════════════════════════════
                      // ── REAL ESTATE FILTERS ──
                      // ═══════════════════════════════════════
                      if (showRealEstate) ...[
                        const SizedBox(height: 16),
                        sectionLabel('PURPOSE'),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _sheetChip(
                              'Any',
                              '__all__',
                              tempListingPurpose ?? '__all__',
                              isDark,
                              (_) => setSheetState(
                                () => tempListingPurpose = null,
                              ),
                            ),
                            _sheetChip(
                              'For Sale',
                              'For Sale',
                              tempListingPurpose ?? '',
                              isDark,
                              (v) =>
                                  setSheetState(() => tempListingPurpose = v),
                              icon: LucideIcons.badgeDollarSign,
                            ),
                            _sheetChip(
                              'For Rent',
                              'For Rent',
                              tempListingPurpose ?? '',
                              isDark,
                              (v) =>
                                  setSheetState(() => tempListingPurpose = v),
                              icon: LucideIcons.key,
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        sectionLabel('BEDROOMS'),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _sheetChip(
                              'Any',
                              '__all__',
                              tempBedrooms ?? '__all__',
                              isDark,
                              (_) => setSheetState(() => tempBedrooms = null),
                            ),
                            for (final br in ['1', '2', '3', '4', '5+'])
                              _sheetChip(
                                br,
                                br,
                                tempBedrooms ?? '',
                                isDark,
                                (v) => setSheetState(() => tempBedrooms = v),
                                icon: LucideIcons.bed,
                              ),
                          ],
                        ),
                      ],

                      // ═══════════════════════════════════════
                      // ── ELECTRONICS FILTERS ──
                      // ═══════════════════════════════════════
                      if (showElectronics) ...[
                        const SizedBox(height: 16),
                        sectionLabel('BRAND'),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _sheetChip(
                              'Any',
                              '__all__',
                              tempBrand ?? '__all__',
                              isDark,
                              (_) => setSheetState(() => tempBrand = null),
                            ),
                            for (final b in [
                              'Apple',
                              'Samsung',
                              'Google',
                              'Sony',
                              'LG',
                              'HP',
                              'Dell',
                              'Lenovo',
                              'Huawei',
                              'Xiaomi',
                              'Other',
                            ])
                              if (tempBrand == null || tempBrand == b)
                                _sheetChip(
                                  b,
                                  b,
                                  tempBrand ?? '',
                                  isDark,
                                  (v) => setSheetState(() => tempBrand = v),
                                  icon: LucideIcons.cpu,
                                ),
                          ],
                        ),
                      ],

                      // ═══════════════════════════════════════
                      // ── JOB FILTERS ──
                      // ═══════════════════════════════════════
                      if (showJobFilters) ...[
                        const SizedBox(height: 16),
                        sectionLabel('EMPLOYMENT TYPE'),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _sheetChip(
                              'Any',
                              '__all__',
                              tempEmploymentType ?? '__all__',
                              isDark,
                              (_) => setSheetState(
                                () => tempEmploymentType = null,
                              ),
                            ),
                            for (final et in [
                              'Full-time',
                              'Part-time',
                              'Contract',
                              'Freelance',
                              'Internship',
                            ])
                              _sheetChip(
                                et,
                                et,
                                tempEmploymentType ?? '',
                                isDark,
                                (v) =>
                                    setSheetState(() => tempEmploymentType = v),
                                icon: LucideIcons.clock,
                              ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        sectionLabel('WORK MODE'),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _sheetChip(
                              'Any',
                              '__all__',
                              tempWorkMode ?? '__all__',
                              isDark,
                              (_) => setSheetState(() => tempWorkMode = null),
                            ),
                            for (final wm in ['Remote', 'On-site', 'Hybrid'])
                              _sheetChip(
                                wm,
                                wm,
                                tempWorkMode ?? '',
                                isDark,
                                (v) => setSheetState(() => tempWorkMode = v),
                                icon: wm == 'Remote'
                                    ? LucideIcons.wifi
                                    : wm == 'On-site'
                                    ? LucideIcons.building
                                    : LucideIcons.split,
                              ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        sectionLabel('EXPERIENCE LEVEL'),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _sheetChip(
                              'Any',
                              '__all__',
                              tempExperienceLevel ?? '__all__',
                              isDark,
                              (_) => setSheetState(
                                () => tempExperienceLevel = null,
                              ),
                            ),
                            for (final el in [
                              'Entry-level',
                              'Mid-level',
                              'Senior',
                              'Lead / Manager',
                              'Executive',
                            ])
                              _sheetChip(
                                el,
                                el,
                                tempExperienceLevel ?? '',
                                isDark,
                                (v) => setSheetState(
                                  () => tempExperienceLevel = v,
                                ),
                                icon: LucideIcons.award,
                              ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 24),

                      // ── Show Me Listings button ──
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () {
                            setState(() {
                              _selectedType = tempType;
                              _selectedCategory = tempCategory;
                              _filterMake = tempMake;
                              _filterModel = tempModel;
                              _filterYear = tempYear;
                              _filterCondition = tempCondition;
                              _filterEmploymentType = tempEmploymentType;
                              _filterWorkMode = tempWorkMode;
                              _filterExperienceLevel = tempExperienceLevel;
                              _filterBedrooms = tempBedrooms;
                              _filterListingPurpose = tempListingPurpose;
                              _filterBrand = tempBrand;
                            });
                            Navigator.pop(ctx);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.accent,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            elevation: 0,
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(LucideIcons.search, size: 18),
                              SizedBox(width: 8),
                              Text(
                                'Show Me Listings',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      );
    },
  );
}

  Widget _sheetChip(
    String label,
    String value,
    String selected,
    bool isDark,
    ValueChanged<String> onTap, {
    IconData? icon,
  }) {
    final isSelected = selected == value;
    return GestureDetector(
      onTap: () => onTap(value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.accent.withValues(alpha: isDark ? 0.2 : 0.1)
              : isDark
              ? Colors.white.withValues(alpha: 0.04)
              : Colors.black.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 14,
                color: isSelected ? AppTheme.accent : Colors.grey,
              ),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                color: isSelected ? AppTheme.accent : Colors.grey,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Helpers ────────────────────────────────────────────────────────────
  void _handleMenuAction(String value, {dynamic profile}) async {
    switch (value) {
      case 'saved':
        context.push('/marketplace/saved');
        break;
      case 'my_listings':
        context.push('/marketplace/my-listings');
        break;
      case 'sell_product':
        context.push('/marketplace/create', extra: ListingType.product);
        break;
      case 'find_clients':
        context.push('/marketplace/create', extra: ListingType.service);
        break;
      case 'hire_candidates':
        context.push('/marketplace/create', extra: ListingType.job);
        break;
    }
  }
}
