import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:diaspora_nearby/theme/app_theme.dart';
import 'package:diaspora_nearby/features/real_estate/models/real_estate_listing.dart';
import 'package:diaspora_nearby/features/shared/widgets/currency_price_display.dart';
import 'package:diaspora_nearby/features/profile/repository/profile_repository.dart';
import 'package:diaspora_nearby/features/auth/repository/auth_repository.dart';
import 'package:diaspora_nearby/features/real_estate/screens/create_real_estate_listing_screen.dart';
import 'package:diaspora_nearby/features/real_estate/services/real_estate_repository.dart';

/// Detail screen for a real estate listing.
class RealEstateDetailScreen extends ConsumerStatefulWidget {
  final RealEstateListing listing;
  const RealEstateDetailScreen({super.key, required this.listing});

  @override
  ConsumerState<RealEstateDetailScreen> createState() =>
      _RealEstateDetailScreenState();
}

class _RealEstateDetailScreenState
    extends ConsumerState<RealEstateDetailScreen> {
  Map<String, int> _viewsByCountry = {};
  int _totalViews = 0;
  bool _statsLoaded = false;
  bool _isSaved = false;

  RealEstateListing get listing => widget.listing;

  Color get _categoryColor {
    switch (listing.category) {
      case 'plot':
        return Colors.amber.shade700;
      case 'farm':
        return Colors.green.shade600;
      case 'house':
        return Colors.blue.shade600;
      default:
        return AppTheme.accent;
    }
  }

  IconData get _categoryIcon {
    switch (listing.category) {
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

  bool get _isOwner {
    final user = ref.read(authRepositoryProvider).currentUser;
    return user != null && user.uid == listing.ownerId;
  }

  @override
  void initState() {
    super.initState();
    final repo = ref.read(realEstateRepositoryProvider);
    _isSaved = repo.isListingSavedSync(listing.id);
    final cachedStats = repo.getCachedStats(listing.id);
    if (cachedStats != null) {
      _viewsByCountry = Map<String, int>.from(cachedStats.viewsByCountry);
      _totalViews = cachedStats.totalViews;
      _statsLoaded = true;
    } else {
      _totalViews = listing.viewCount;
      _statsLoaded = true;
    }
    _recordView();
    _checkSavedState();
    if (_isOwnerCheck()) _loadStats();
  }

  bool _isOwnerCheck() {
    try {
      final authRepo = ref.read(authRepositoryProvider);
      final user = authRepo.currentUser;
      return user != null && user.uid == listing.ownerId;
    } catch (_) {
      return false;
    }
  }

  /// Record a view for this listing, keyed by viewer's host country.
  Future<void> _recordView() async {
    try {
      final profile = ref.read(userProfileProvider).value;
      final country = profile?.hostCountry ?? 'Unknown';
      final countryCode = profile?.hostCountryCode ?? 'XX';
      final viewerUid = ref.read(authRepositoryProvider).currentUser?.uid;
      if (viewerUid == null || viewerUid == listing.ownerId) return;

      await ref
          .read(realEstateRepositoryProvider)
          .incrementViewCount(
            listing.id,
            country: country,
            countryCode: countryCode,
          );
    } catch (_) {}
  }

  /// Check if user has saved this listing.
  Future<void> _checkSavedState() async {
    final uid = ref.read(authRepositoryProvider).currentUser?.uid;
    if (uid == null) return;
    try {
      final saved = await ref
          .read(realEstateRepositoryProvider)
          .isListingSaved(listing.id, uid);
      if (mounted && saved != _isSaved) setState(() => _isSaved = saved);
    } catch (_) {}
  }

  /// Toggle save state.
  Future<void> _toggleSave() async {
    final uid = ref.read(authRepositoryProvider).currentUser?.uid;
    if (uid == null) return;
    final newSaved = !_isSaved;
    setState(() => _isSaved = newSaved);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(newSaved ? 'Listing saved!' : 'Removed from saved'),
        duration: const Duration(seconds: 1),
      ),
    );
    try {
      final repo = ref.read(realEstateRepositoryProvider);
      if (newSaved) {
        await repo.saveListing(listing.id, uid);
      } else {
        await repo.unsaveListing(listing.id, uid);
      }
    } catch (_) {
      if (mounted) setState(() => _isSaved = !newSaved);
    }
  }

  /// Load view statistics for the owner.
  Future<void> _loadStats() async {
    try {
      final db = FirebaseFirestore.instance;
      final snap = await db
          .collection('real_estate_listings')
          .doc(listing.id)
          .collection('views')
          .get();

      final byCountry = <String, int>{};
      for (final doc in snap.docs) {
        final country = (doc.data()['country'] as String?) ?? 'Unknown';
        byCountry[country] = (byCountry[country] ?? 0) + 1;
      }

      ref
          .read(realEstateRepositoryProvider)
          .cacheStats(listing.id, byCountry, snap.docs.length);

      if (mounted) {
        setState(() {
          _viewsByCountry = byCountry;
          _totalViews = snap.docs.length;
          _statsLoaded = true;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _statsLoaded = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final profile = ref.watch(userProfileProvider).value;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: CustomScrollView(
        slivers: [
          _buildSliverAppBar(context, theme, isDark),
          SliverPadding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppTheme.pageHorizontalPadding,
              vertical: 16,
            ),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // Owner inline-edit banner
                if (_isOwner) ...[
                  _ownerActionBar(context, theme, isDark),
                  const SizedBox(height: 12),
                ],

                // Title + category badge
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: _categoryColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(_categoryIcon, size: 12, color: _categoryColor),
                          const SizedBox(width: 4),
                          Text(
                            listing.categoryLabel,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: _categoryColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (listing.listingType != null) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.accent.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'For ${listing.listingType![0].toUpperCase()}${listing.listingType!.substring(1)}',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.accent,
                          ),
                        ),
                      ),
                    ],
                    if (listing.locationVerified == true) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.green.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              LucideIcons.shieldCheck,
                              size: 10,
                              color: Colors.green.shade600,
                            ),
                            const SizedBox(width: 3),
                            Text(
                              'GPS Verified',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w600,
                                color: Colors.green.shade600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 8),

                // Title
                Text(
                  listing.title,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 6),

                // Location row
                if (listing.locationLabel.isNotEmpty)
                  Row(
                    children: [
                      Icon(
                        LucideIcons.mapPin,
                        size: 14,
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.4,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          listing.locationLabel,
                          style: TextStyle(
                            fontSize: 13,
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.5,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                const SizedBox(height: 16),

                // Price + size card
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.elevationColor(context, 1),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      Flexible(
                        child: CurrencyPriceDisplay(
                          amount: listing.price,
                          sellerCountryCode: listing.countryCode,
                          viewerCountryCode: profile?.hostCountryCode,
                          showToggle: false,
                          primaryStyle: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                      ),
                      const Spacer(),
                      if (listing.size != null)
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              '${listing.size!.toStringAsFixed(0)} m\u00B2',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: theme.colorScheme.onSurface,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${(listing.size! * 10.7639).toStringAsFixed(0)} ft\u00B2'
                              '${listing.size! >= 4047 ? '  \u00B7  ${(listing.size! / 4046.86).toStringAsFixed(1)} acres' : ''}',
                              style: TextStyle(
                                fontSize: 11,
                                color: theme.colorScheme.onSurface.withValues(
                                  alpha: 0.5,
                                ),
                              ),
                            ),
                            if (listing.hasTitle == true)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  'Title Deed \u2713',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.green.shade600,
                                  ),
                                ),
                              ),
                          ],
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Description
                if (listing.description.isNotEmpty) ...[
                  _sectionTitle(theme, 'Description'),
                  const SizedBox(height: 6),
                  Text(
                    listing.description,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.6,
                      color: theme.colorScheme.onSurface.withValues(
                        alpha: 0.65,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // Category-specific details
                if (listing.category == 'plot') _plotDetails(theme, isDark),
                if (listing.category == 'farm') _farmDetails(theme, isDark),
                if (listing.category == 'house') _houseDetails(theme, isDark),

                const SizedBox(height: 16),

                // Owner section (for non-owners)
                if (!_isOwner) _ownerSection(context, theme),

                // View Stats (owner only)
                if (_isOwner) ...[
                  const SizedBox(height: 16),
                  _viewStatsSection(theme, isDark),
                ],

                const SizedBox(height: 40),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Owner Action Bar ──────────────────────────────────────────────────
  Widget _ownerActionBar(BuildContext context, ThemeData theme, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.accent.withValues(alpha: isDark ? 0.12 : 0.06),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(LucideIcons.info, size: 14, color: AppTheme.accent),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'This is your listing',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: AppTheme.accent,
              ),
            ),
          ),
          GestureDetector(
            onTap: () async {
              final result = await Navigator.push<bool>(
                context,
                MaterialPageRoute(
                  builder: (_) => CreateRealEstateListingScreen(
                    defaultCategory: listing.category,
                    existing: listing,
                  ),
                ),
              );
              if (result == true && context.mounted) {
                Navigator.pop(context, true);
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppTheme.accent,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(LucideIcons.pencil, size: 12, color: Colors.white),
                  SizedBox(width: 4),
                  Text(
                    'Edit',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── View Stats (Owner) ────────────────────────────────────────────────
  Widget _viewStatsSection(ThemeData theme, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(theme, 'Listing Statistics'),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppTheme.elevationColor(context, 1),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    LucideIcons.eye,
                    size: 16,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '$_totalViews total view${_totalViews == 1 ? '' : 's'}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
              if (!_statsLoaded) ...[
                const SizedBox(height: 10),
                const Center(
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppTheme.accent,
                    ),
                  ),
                ),
              ],
              if (_statsLoaded && _viewsByCountry.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  'VIEWS BY COUNTRY',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.35),
                  ),
                ),
                const SizedBox(height: 6),
                ...(_viewsByCountry.entries.toList()
                      ..sort((a, b) => b.value.compareTo(a.value)))
                    .take(10)
                    .map(
                      (entry) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(
                          children: [
                            Text(
                              entry.key,
                              style: TextStyle(
                                fontSize: 12,
                                color: theme.colorScheme.onSurface.withValues(
                                  alpha: 0.65,
                                ),
                              ),
                            ),
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: AppTheme.accent.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                '${entry.value}',
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.accent,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
              ],
              if (_statsLoaded && _viewsByCountry.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'No views yet',
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  void _openFullScreenViewer(List<String> images, int index) {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        pageBuilder: (_, _, _) =>
            _FullScreenImageViewer(images: images, initialIndex: index),
        transitionsBuilder: (_, anim, _, child) {
          return FadeTransition(opacity: anim, child: child);
        },
      ),
    );
  }

  Widget _buildSliverAppBar(
    BuildContext context,
    ThemeData theme,
    bool isDark,
  ) {
    // Build ordered image list based on category:
    //   Plot/Farm: aerial (satellite) → map → user photos
    //   House: profile photo → aerial → map → remaining house photos
    final allImages = <_CarouselImage>[];

    if (listing.category == 'house') {
      // 1. First photo is the profile/hero photo
      if (listing.photos.isNotEmpty) {
        allImages.add(_CarouselImage(listing.photos.first, 'photo'));
      }
      // 2. Aerial satellite view
      if (listing.satelliteImageUrl != null) {
        allImages.add(_CarouselImage(listing.satelliteImageUrl!, 'aerial'));
      }
      // 3. Road map view
      if (listing.mapImageUrl != null) {
        allImages.add(_CarouselImage(listing.mapImageUrl!, 'map'));
      }
      // 4. Remaining house photos
      if (listing.photos.length > 1) {
        for (int i = 1; i < listing.photos.length; i++) {
          allImages.add(_CarouselImage(listing.photos[i], 'photo'));
        }
      }
    } else {
      // Plot / Farm: aerial and map first
      if (listing.satelliteImageUrl != null) {
        allImages.add(_CarouselImage(listing.satelliteImageUrl!, 'aerial'));
      }
      if (listing.mapImageUrl != null) {
        allImages.add(_CarouselImage(listing.mapImageUrl!, 'map'));
      }
      // Then user photos
      for (final url in listing.photos) {
        allImages.add(_CarouselImage(url, 'photo'));
      }
    }

    Widget heroImage;
    if (allImages.isNotEmpty) {
      final pageController = PageController();
      final imageUrls = allImages.map((e) => e.url).toList();
      heroImage = Stack(
        children: [
          PageView.builder(
            controller: pageController,
            itemCount: allImages.length,
            itemBuilder: (_, i) {
              final img = allImages[i];
              return GestureDetector(
                onTap: () => _openFullScreenViewer(imageUrls, i),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CachedNetworkImage(
                      imageUrl: img.url,
                      fit: BoxFit.cover,
                      placeholder: (_, _) => _placeholder(isDark),
                      errorWidget: (_, _, _) => _placeholder(isDark),
                    ),
                    // Label overlay for aerial/map images
                    if (img.type == 'aerial' || img.type == 'map')
                      Positioned(
                        left: 12,
                        top: MediaQuery.of(context).padding.top + 48,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.6),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                img.type == 'aerial'
                                    ? LucideIcons.satellite
                                    : LucideIcons.map,
                                size: 12,
                                color: Colors.white70,
                              ),
                              const SizedBox(width: 5),
                              Text(
                                img.type == 'aerial'
                                    ? 'Aerial View'
                                    : 'Location Map',
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white70,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
          if (allImages.length > 1)
            Positioned(
              bottom: 12,
              left: 0,
              right: 0,
              child: _PageIndicator(
                controller: pageController,
                count: allImages.length,
              ),
            ),
          Positioned(
            bottom: 12,
            right: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '${allImages.length} ${allImages.length == 1 ? 'image' : 'images'}',
                style: const TextStyle(fontSize: 10, color: Colors.white70),
              ),
            ),
          ),
        ],
      );
    } else {
      heroImage = _placeholder(isDark);
    }

    return SliverAppBar(
      expandedHeight: 280,
      pinned: true,
      backgroundColor: AppTheme.elevationColor(context, 0),
      actions: [
        Container(
          margin: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.4),
            shape: BoxShape.circle,
          ),
          child: IconButton(
            icon: Icon(
              _isSaved ? Icons.bookmark : Icons.bookmark_border,
              color: _isSaved ? AppTheme.accent : Colors.white,
              size: 20,
            ),
            onPressed: _toggleSave,
            tooltip: _isSaved ? 'Remove from saved' : 'Save listing',
          ),
        ),
      ],
      flexibleSpace: FlexibleSpaceBar(background: heroImage),
    );
  }

  Widget _placeholder(bool isDark) {
    return Container(
      color: isDark
          ? _categoryColor.withValues(alpha: 0.08)
          : _categoryColor.withValues(alpha: 0.05),
      child: Center(
        child: Icon(
          _categoryIcon,
          size: 60,
          color: _categoryColor.withValues(alpha: 0.3),
        ),
      ),
    );
  }

  Widget _sectionTitle(ThemeData theme, String text) {
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 1,
        color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
      ),
    );
  }

  // ─── Plot Details ─────────────────────────────────────────────────────
  Widget _plotDetails(ThemeData theme, bool isDark) {
    final items = <_DetailItem>[];
    if (listing.zoning != null) {
      items.add(_DetailItem(LucideIcons.building2, 'Zoning', listing.zoning!));
    }
    if (listing.terrainType != null) {
      items.add(
        _DetailItem(LucideIcons.mountain, 'Terrain', listing.terrainType!),
      );
    }
    if (listing.isFenced == true) {
      items.add(_DetailItem(LucideIcons.lock, 'Fenced', 'Yes'));
    }
    if (listing.hasWater == true) {
      items.add(_DetailItem(LucideIcons.droplets, 'Water', 'Available'));
    }
    if (listing.hasElectricity == true) {
      items.add(_DetailItem(LucideIcons.zap, 'Electricity', 'Available'));
    }
    if (listing.hasRoad == true) {
      items.add(_DetailItem(LucideIcons.navigation, 'Road Access', 'Yes'));
    }

    if (items.isEmpty) return const SizedBox.shrink();
    return _detailGrid(theme, isDark, 'Plot Features', items);
  }

  // ─── Farm Details ─────────────────────────────────────────────────────
  Widget _farmDetails(ThemeData theme, bool isDark) {
    final items = <_DetailItem>[];
    if (listing.farmableArea != null) {
      final sqft = listing.farmableArea! * 10.7639;
      items.add(
        _DetailItem(
          LucideIcons.sprout,
          'Farmable Area',
          '${listing.farmableArea!.toStringAsFixed(0)} m\u00B2 / ${sqft.toStringAsFixed(0)} ft\u00B2',
        ),
      );
    }
    if (listing.soilType != null) {
      items.add(_DetailItem(LucideIcons.leaf, 'Soil', listing.soilType!));
    }
    if (listing.hasIrrigation == true) {
      items.add(_DetailItem(LucideIcons.droplets, 'Irrigation', 'Available'));
    }
    if (listing.hasStorage == true) {
      items.add(_DetailItem(LucideIcons.warehouse, 'Storage', 'Available'));
    }
    if (listing.workers != null) {
      items.add(
        _DetailItem(LucideIcons.users, 'Workers', '${listing.workers}'),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (items.isNotEmpty)
          _detailGrid(theme, isDark, 'Farm Features', items),
        if (listing.crops != null && listing.crops!.isNotEmpty) ...[
          const SizedBox(height: 12),
          _sectionTitle(theme, 'Crops / Livestock'),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: listing.crops!
                .map((c) => _chip(theme, isDark, c))
                .toList(),
          ),
        ],
      ],
    );
  }

  // ─── House Details ────────────────────────────────────────────────────
  Widget _houseDetails(ThemeData theme, bool isDark) {
    final items = <_DetailItem>[];
    if (listing.bedrooms != null) {
      items.add(
        _DetailItem(LucideIcons.bedDouble, 'Bedrooms', '${listing.bedrooms}'),
      );
    }
    if (listing.bathrooms != null) {
      items.add(
        _DetailItem(LucideIcons.bath, 'Bathrooms', '${listing.bathrooms}'),
      );
    }
    if (listing.floors != null) {
      items.add(_DetailItem(LucideIcons.layers, 'Floors', '${listing.floors}'));
    }
    if (listing.livingArea != null) {
      final sqft = listing.livingArea! * 10.7639;
      items.add(
        _DetailItem(
          LucideIcons.square,
          'Living Area',
          '${listing.livingArea!.toStringAsFixed(0)} m\u00B2 / ${sqft.toStringAsFixed(0)} ft\u00B2',
        ),
      );
    }
    if (listing.yearBuilt != null) {
      items.add(
        _DetailItem(LucideIcons.calendar, 'Year Built', '${listing.yearBuilt}'),
      );
    }
    if (listing.propertyCondition != null) {
      items.add(
        _DetailItem(
          LucideIcons.wrench,
          'Condition',
          listing.propertyCondition!,
        ),
      );
    }
    if (listing.hasGarage == true) {
      items.add(_DetailItem(LucideIcons.car, 'Garage', 'Yes'));
    }
    if (listing.hasGarden == true) {
      items.add(_DetailItem(LucideIcons.flower2, 'Garden', 'Yes'));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (items.isNotEmpty)
          _detailGrid(theme, isDark, 'House Details', items),
        if (listing.amenities != null && listing.amenities!.isNotEmpty) ...[
          const SizedBox(height: 12),
          _sectionTitle(theme, 'Amenities'),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: listing.amenities!
                .map((a) => _chip(theme, isDark, a))
                .toList(),
          ),
        ],
      ],
    );
  }

  Widget _detailGrid(
    ThemeData theme,
    bool isDark,
    String title,
    List<_DetailItem> items,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(theme, title),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: items
              .map(
                (item) => Container(
                  constraints: const BoxConstraints(minWidth: 90),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: isDark
                        ? AppTheme.elevationDark1
                        : AppTheme.elevationLight1,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        item.icon,
                        size: 14,
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.4,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.label,
                            style: TextStyle(
                              fontSize: 9,
                              color: theme.colorScheme.onSurface.withValues(
                                alpha: 0.4,
                              ),
                            ),
                          ),
                          Text(
                            item.value,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: theme.colorScheme.onSurface.withValues(
                                alpha: 0.75,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              )
              .toList(),
        ),
      ],
    );
  }

  Widget _chip(ThemeData theme, bool isDark, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppTheme.accent.withValues(alpha: isDark ? 0.15 : 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: AppTheme.accent,
        ),
      ),
    );
  }

  Widget _ownerSection(BuildContext context, ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.elevationColor(context, 1),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundImage: listing.ownerPhoto.isNotEmpty
                ? NetworkImage(listing.ownerPhoto)
                : null,
            backgroundColor: AppTheme.accent.withValues(alpha: 0.1),
            child: listing.ownerPhoto.isEmpty
                ? const Icon(LucideIcons.user, size: 18, color: AppTheme.accent)
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  listing.ownerName,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                if (listing.country != null)
                  Text(
                    listing.country!,
                    style: TextStyle(
                      fontSize: 11,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: AppTheme.accent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(LucideIcons.messageCircle, size: 14, color: Colors.white),
                SizedBox(width: 6),
                Text(
                  'Contact',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailItem {
  final IconData icon;
  final String label;
  final String value;
  _DetailItem(this.icon, this.label, this.value);
}

/// Helper for the hero carousel — tracks image URL and its type
/// so we can display labelled overlays for aerial / map images.
class _CarouselImage {
  final String url;

  /// 'photo', 'aerial', or 'map'
  final String type;
  const _CarouselImage(this.url, this.type);
}

// ─── Page Indicator ─────────────────────────────────────────────────────

class _PageIndicator extends StatefulWidget {
  final PageController controller;
  final int count;
  const _PageIndicator({required this.controller, required this.count});

  @override
  State<_PageIndicator> createState() => _PageIndicatorState();
}

class _PageIndicatorState extends State<_PageIndicator> {
  int _current = 0;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onPage);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onPage);
    super.dispose();
  }

  void _onPage() {
    final page = widget.controller.page?.round() ?? 0;
    if (page != _current) setState(() => _current = page);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(
        widget.count,
        (i) => AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.symmetric(horizontal: 3),
          width: _current == i ? 20 : 6,
          height: 6,
          decoration: BoxDecoration(
            color: _current == i ? Colors.white : Colors.white38,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
      ),
    );
  }
}

// ─── Fullscreen Image Viewer ──────────────────────────────────────────────

class _FullScreenImageViewer extends StatefulWidget {
  final List<String> images;
  final int initialIndex;

  const _FullScreenImageViewer({
    required this.images,
    required this.initialIndex,
  });

  @override
  State<_FullScreenImageViewer> createState() => _FullScreenImageViewerState();
}

class _FullScreenImageViewerState extends State<_FullScreenImageViewer> {
  late PageController _pageController;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Swipeable fullscreen images with pinch-to-zoom
          PageView.builder(
            controller: _pageController,
            itemCount: widget.images.length,
            onPageChanged: (i) => setState(() => _currentIndex = i),
            itemBuilder: (_, i) => Center(
              child: InteractiveViewer(
                minScale: 0.5,
                maxScale: 4.0,
                child: CachedNetworkImage(
                  imageUrl: widget.images[i],
                  fit: BoxFit.contain,
                  width: double.infinity,
                  placeholder: (_, _) => const Center(
                    child: CircularProgressIndicator(
                      color: AppTheme.accent,
                      strokeWidth: 2,
                    ),
                  ),
                  errorWidget: (_, _, _) => const Icon(
                    Icons.broken_image,
                    color: Colors.white38,
                    size: 48,
                  ),
                ),
              ),
            ),
          ),

          // Close button
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            right: 12,
            child: GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: const BoxDecoration(
                  color: Colors.black54,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close, color: Colors.white, size: 22),
              ),
            ),
          ),

          // Page indicator (only when multiple images)
          if (widget.images.length > 1)
            Positioned(
              bottom: MediaQuery.of(context).padding.bottom + 24,
              left: 0,
              right: 0,
              child: Column(
                children: [
                  Text(
                    '${_currentIndex + 1} / ${widget.images.length}',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(
                      widget.images.length,
                      (i) => AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        width: _currentIndex == i ? 20 : 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: _currentIndex == i
                              ? Colors.white
                              : Colors.white38,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
