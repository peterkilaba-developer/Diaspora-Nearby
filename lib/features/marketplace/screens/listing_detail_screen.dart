import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:diaspora_nearby/theme/app_theme.dart';
import 'package:diaspora_nearby/features/auth/repository/auth_repository.dart';
import 'package:diaspora_nearby/features/marketplace/models/marketplace_listing.dart';
import 'package:diaspora_nearby/features/marketplace/repository/marketplace_repository.dart';
import 'package:diaspora_nearby/features/marketplace/screens/marketplace_screen.dart'
    show categoryIcon;
import 'package:diaspora_nearby/features/shared/widgets/currency_price_display.dart';
import 'package:diaspora_nearby/features/marketplace/widgets/marketplace_card_helpers.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:url_launcher/url_launcher.dart';
import 'package:diaspora_nearby/features/profile/repository/profile_repository.dart';
import 'package:diaspora_nearby/features/chat/repository/chat_repository.dart';
import 'package:diaspora_nearby/features/shared/utils/whatsapp_utils.dart';

class ListingDetailScreen extends ConsumerStatefulWidget {
  final String listingId;

  const ListingDetailScreen({super.key, required this.listingId});

  @override
  ConsumerState<ListingDetailScreen> createState() =>
      _ListingDetailScreenState();
}

class _ListingDetailScreenState extends ConsumerState<ListingDetailScreen> {
  MarketplaceListing? _listing;
  bool _isLoading = true;
  bool _isSaved = false;
  int _currentImageIndex = 0;
  final PageController _imagePageController = PageController();
  String? _viewerCountryCode;

  @override
  void initState() {
    super.initState();
    _loadListing();
    // Load viewer's country code for currency conversion
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final profile = ref.read(userProfileProvider).value;
      if (mounted && profile != null) {
        setState(() => _viewerCountryCode = profile.hostCountryCode);
      }
    });
  }

  @override
  void dispose() {
    _imagePageController.dispose();
    super.dispose();
  }

  Future<void> _loadListing() async {
    try {
      final repo = ref.read(marketplaceRepositoryProvider);
      final listing = await repo.getListingById(widget.listingId);
      if (listing != null) {
        // Increment view
        repo.incrementViewCount(widget.listingId);

        // Check saved state
        final user = ref.read(authRepositoryProvider).currentUser;
        if (user != null) {
          final saved = await repo.isListingSaved(widget.listingId, user.uid);
          if (mounted) setState(() => _isSaved = saved);
        }
      }
      if (mounted) {
        setState(() {
          _listing = listing;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('❌ Error loading listing ${widget.listingId}: $e');
      if (mounted) {
        setState(() {
          _listing = null;
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(elevation: 0, backgroundColor: Colors.transparent),
        body: const Center(
          child: CircularProgressIndicator(color: AppTheme.accent),
        ),
      );
    }

    if (_listing == null) {
      return Scaffold(
        appBar: AppBar(elevation: 0, backgroundColor: Colors.transparent),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(LucideIcons.fileX, size: 48, color: theme.hintColor),
              const SizedBox(height: 16),
              Text(
                'Listing not found',
                style: TextStyle(fontSize: 16, color: theme.hintColor),
              ),
            ],
          ),
        ),
      );
    }

    final listing = _listing!;
    final userId = ref.read(authRepositoryProvider).currentUser?.uid;
    final isOwner = listing.sellerId == userId;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: CustomScrollView(
        slivers: [
          // ── Slim pinned AppBar ────────────────────────────────────
          SliverAppBar(
            pinned: true,
            elevation: 0,
            backgroundColor: theme.scaffoldBackgroundColor,
            actions: [
              IconButton(
                icon: Icon(
                  _isSaved ? Icons.bookmark : Icons.bookmark_border,
                  color: _isSaved ? AppTheme.accent : null,
                ),
                onPressed: () => _toggleSave(listing),
              ),
              if (isOwner)
                PopupMenuButton<String>(
                  onSelected: (v) => _onMenuAction(v, listing),
                  icon: const Icon(LucideIcons.moreVertical, size: 20),
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                      value: 'edit',
                      child: Text('Edit Listing'),
                    ),
                    if (listing.status == ListingStatus.active)
                      const PopupMenuItem(
                        value: 'pause',
                        child: Text('Pause Listing'),
                      ),
                    if (listing.status == ListingStatus.paused ||
                        listing.status == ListingStatus.sold)
                      const PopupMenuItem(
                        value: 'activate',
                        child: Text('Activate'),
                      ),
                    if (listing.status != ListingStatus.sold)
                      PopupMenuItem(
                        value: 'sold',
                        child: Text(
                          listing.listingType == ListingType.job
                              ? 'Mark as Filled'
                              : 'Mark as Sold',
                        ),
                      ),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Text(
                        'Delete',
                        style: TextStyle(color: AppTheme.error),
                      ),
                    ),
                  ],
                )
              else
                IconButton(
                  icon: const Icon(LucideIcons.flag, size: 18),
                  onPressed: () => _reportListing(listing),
                ),
            ],
          ),

          // ── Image Section ──────────────────────────────────────────
          if (listing.images.isNotEmpty)
            SliverToBoxAdapter(
              child: Column(
                children: [
                  // Main image — tappable for fullscreen
                  SizedBox(
                    height: 300,
                    width: double.infinity,
                    child: PageView.builder(
                      controller: _imagePageController,
                      itemCount: listing.images.length,
                      onPageChanged: (i) =>
                          setState(() => _currentImageIndex = i),
                      itemBuilder: (_, i) => GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => _openFullScreenViewer(listing.images, i),
                        child: CachedNetworkImage(
                          imageUrl: listing.images[i],
                          fit: BoxFit.cover,
                          width: double.infinity,
                        ),
                      ),
                    ),
                  ),

                  // Thumbnail strip
                  if (listing.images.length > 1)
                    Container(
                      height: 64,
                      margin: const EdgeInsets.only(top: 8),
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        itemCount: listing.images.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 6),
                        itemBuilder: (_, i) => GestureDetector(
                          onTap: () {
                            _imagePageController.animateToPage(
                              i,
                              duration: const Duration(milliseconds: 250),
                              curve: Curves.easeInOut,
                            );
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            width: 64,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: _currentImageIndex == i
                                    ? AppTheme.accent
                                    : Colors.transparent,
                                width: 2,
                              ),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: CachedNetworkImage(
                                imageUrl: listing.images[i],
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            )
          else
            SliverToBoxAdapter(
              child: Container(
                height: 200,
                color: isDark
                    ? Colors.white.withValues(alpha: 0.05)
                    : Colors.black.withValues(alpha: 0.04),
                child: Center(
                  child: Icon(
                    categoryIcon(listing.category),
                    size: 64,
                    color: theme.hintColor.withValues(alpha: 0.2),
                  ),
                ),
              ),
            ),

          // ── Content ───────────────────────────────────────────────
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(8, 16, 8, 16),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // Status badge (if not active)
                if (listing.status != ListingStatus.active)
                  _buildStatusBadge(listing, theme),
                // Seller's local currency price
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    CurrencyPriceDisplay(
                      amount: listing.priceAmount,
                      sellerCountryCode: listing.sellerCountryCode,
                      viewerCountryCode: _viewerCountryCode,
                      primaryColor: marketplaceSageGreen,
                      primaryStyle: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: marketplaceSageGreen,
                      ),
                    ),
                    if (listing.priceNegotiable) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: marketplaceSageGreen.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              LucideIcons.tag,
                              size: 10,
                              color: marketplaceSageGreen,
                            ),
                            SizedBox(width: 4),
                            Text(
                              'Negotiable',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w500,
                                color: marketplaceSageGreen,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const Spacer(),
                    // "Find Parts" button for vehicles & motorcycles
                    if (((listing.category == MarketplaceCategory.vehicles &&
                            listing.vehicleDetails?['make'] != null &&
                            listing.vehicleDetails!['make']
                                .toString()
                                .isNotEmpty) ||
                        (listing.category == MarketplaceCategory.motorcycles &&
                            listing.motorcycleDetails?['make'] != null &&
                            listing.motorcycleDetails!['make']
                                .toString()
                                .isNotEmpty))) ...[
                      GestureDetector(
                        onTap: () {
                          final make =
                              listing.category ==
                                  MarketplaceCategory.motorcycles
                              ? (listing.motorcycleDetails?['make'] ??
                                        listing.vehicleDetails?['make'] ??
                                        '')
                                    .toString()
                              : listing.vehicleDetails!['make'].toString();
                          final model =
                              listing.category ==
                                  MarketplaceCategory.motorcycles
                              ? (listing.motorcycleDetails?['model'] ??
                                        listing.vehicleDetails?['model'] ??
                                        '')
                                    .toString()
                              : (listing.vehicleDetails?['model'] ?? '')
                                    .toString();
                          final year =
                              listing.category ==
                                  MarketplaceCategory.motorcycles
                              ? (listing.motorcycleDetails?['year'] ??
                                        listing.vehicleDetails?['year'] ??
                                        '')
                                    .toString()
                              : (listing.vehicleDetails?['year'] ?? '')
                                    .toString();

                          final encodedMake = Uri.encodeComponent(make);
                          var path = '/marketplace/parts/$encodedMake';
                          final queryParams = <String, String>{};
                          if (model.isNotEmpty) queryParams['model'] = model;
                          if (year.isNotEmpty) queryParams['year'] = year;
                          if (queryParams.isNotEmpty) {
                            path +=
                                '?${queryParams.entries.map((e) => '${e.key}=${Uri.encodeComponent(e.value)}').join('&')}';
                          }
                          context.push(path);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.orange.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: Colors.orange.withValues(alpha: 0.3),
                              width: 1,
                            ),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                LucideIcons.wrench,
                                size: 12,
                                color: Colors.orange,
                              ),
                              SizedBox(width: 5),
                              Text(
                                'Find Parts',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.orange,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),

                const SizedBox(height: 12),

                // Title
                Text(
                  listing.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onSurface,
                  ),
                ),

                const SizedBox(height: 8),

                // Badges row
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    _buildIconChip(
                      categoryIcon(listing.category),
                      MarketplaceCategory.displayName(listing.category),
                      isDark,
                    ),
                    if (listing.subcategory != null)
                      _buildIconChip(null, listing.subcategory!, isDark),
                    _buildIconChip(
                      listing.scope == ListingScope.international
                          ? LucideIcons.globe
                          : LucideIcons.mapPin,
                      listing.scope == ListingScope.international
                          ? 'International'
                          : 'Local',
                      isDark,
                    ),
                    if (listing.condition != null)
                      _buildIconChip(
                        null,
                        ItemCondition.displayName(listing.condition!),
                        isDark,
                        color: conditionColor(listing.condition!),
                      ),
                    _buildIconChip(
                      listing.listingType == ListingType.product
                          ? LucideIcons.package
                          : listing.listingType == ListingType.job
                          ? LucideIcons.briefcase
                          : LucideIcons.wrench,
                      listing.listingType == ListingType.product
                          ? 'Product'
                          : listing.listingType == ListingType.job
                          ? 'Job'
                          : 'Service',
                      isDark,
                    ),
                  ],
                ),

                const SizedBox(height: 20),

                // Description
                _buildSection('Description', theme),
                const SizedBox(height: 6),
                Text(
                  listing.description,
                  style: TextStyle(
                    fontSize: 14,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.75),
                    height: 1.5,
                  ),
                ),

                const SizedBox(height: 20),

                // ── Category-specific details ───────────────────────
                _buildContextualDetails(listing, theme, isDark),

                // ── Seller / Poster Info ─────────────────────────────
                const SizedBox(height: 20),
                _buildSellerCard(listing, theme, isDark),

                // Delivery
                if (listing.deliveryOptions != null &&
                    listing.deliveryOptions!.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  _buildSection('Delivery', theme),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: listing.deliveryOptions!
                        .map((d) => _buildIconChip(_deliveryIcon(d), d, isDark))
                        .toList(),
                  ),
                ],

                // Stats
                const SizedBox(height: 20),
                Row(
                  children: [
                    _buildStat(LucideIcons.eye, '${listing.viewCount}', theme),
                    const SizedBox(width: 16),
                    _buildStat(
                      LucideIcons.bookmark,
                      '${listing.savedCount}',
                      theme,
                    ),
                    const Spacer(),
                    if (listing.createdAt != null)
                      Text(
                        'Listed ${timeago.format(listing.createdAt!)}',
                        style: TextStyle(fontSize: 11, color: theme.hintColor),
                      ),
                  ],
                ),

                const SizedBox(height: 80), // space for bottom bar
              ]),
            ),
          ),
        ],
      ),

      // ── Bottom Action Bar ────────────────────────────────────────
      bottomNavigationBar: isOwner
          ? null
          : _buildBottomBar(listing, theme, isDark),
    );
  }

  // ─── Bottom Action Bar ──────────────────────────────────────────────
  Widget _buildBottomBar(
    MarketplaceListing listing,
    ThemeData theme,
    bool isDark,
  ) {
    const sageGreen = marketplaceSageGreen;
    final isJob = listing.listingType == ListingType.job;
    final isService = listing.listingType == ListingType.service;
    final applicationUrl = listing.jobDetails?['applicationUrl'] as String?;

    // Determine primary button text + icon + action
    String primaryLabel;
    IconData primaryIcon;
    VoidCallback primaryAction;

    if (isJob) {
      primaryLabel = 'Apply';
      primaryIcon = LucideIcons.fileUp;
      primaryAction = () => _applyWithResume(listing);
    } else if (isService) {
      primaryLabel = 'Hire';
      primaryIcon = LucideIcons.briefcase;
      primaryAction = () => _contactSeller(listing);
    } else {
      primaryLabel = 'Buy';
      primaryIcon = LucideIcons.shoppingBag;
      primaryAction = () => _contactSeller(listing);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.02)
            : Colors.black.withValues(alpha: 0.01),
        border: Border(
          top: BorderSide(
            color: theme.dividerColor.withValues(alpha: 0.3),
            width: 0.5,
          ),
        ),
      ),
      child: SafeArea(
        child: Row(
          children: [
            // Primary action button (Buy / Apply / Hire)
            Expanded(
              child: ElevatedButton.icon(
                onPressed: primaryAction,
                icon: Icon(primaryIcon, size: 18),
                label: Text(
                  primaryLabel,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: sageGreen,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Secondary: Contact seller
            SizedBox(
              width: 56,
              child: ElevatedButton(
                onPressed: () => _contactSeller(listing),
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                  foregroundColor: sageGreen,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Icon(_contactIcon(listing.contactMethod), size: 20),
              ),
            ),
            // External link for jobs with applicationUrl
            if (isJob &&
                applicationUrl != null &&
                applicationUrl.isNotEmpty) ...[
              const SizedBox(width: 8),
              SizedBox(
                width: 50,
                child: ElevatedButton(
                  onPressed: () => _openApplicationLink(applicationUrl),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: theme.colorScheme.surfaceContainerHighest,
                    foregroundColor: theme.colorScheme.primary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Icon(LucideIcons.externalLink, size: 20),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Pick a document (CV/Resume) and navigate to DM with the seller to send it
  Future<void> _applyWithResume(MarketplaceListing listing) async {
    if (!mounted) return;

    // Navigate to chat with the employer — the user can use the
    // existing document attachment feature in the chat input to
    // send their CV/resume directly.
    if (!mounted) return;
    context.push('/chat/direct/${listing.sellerId}');

    if (mounted) {
      // Brief guidance toast
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              Icon(LucideIcons.paperclip, size: 16, color: Colors.white),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Use the attachment button to send your CV/Resume',
                  style: TextStyle(fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
          backgroundColor: AppTheme.accent,
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 4),
        ),
      );
    }
  }

  /// Open an external application link in the browser
  Future<void> _openApplicationLink(String url) async {
    final uri = Uri.parse(url);
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        throw 'Could not open link';
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open application link: $e')),
        );
      }
    }
  }

  // ─── Contextual Category Details ──────────────────────────────────────
  Widget _buildContextualDetails(
    MarketplaceListing listing,
    ThemeData theme,
    bool isDark,
  ) {
    final widgets = <Widget>[];

    // Car
    if (listing.vehicleDetails != null &&
        listing.category == MarketplaceCategory.vehicles) {
      final v = listing.vehicleDetails!;

      // Primary specs — always visible
      final primarySpecs = <Widget>[
        if (v['make'] != null)
          _detailItem('Make', v['make'].toString(), isDark),
        if (v['model'] != null)
          _detailItem('Model', v['model'].toString(), isDark),
        if (v['year'] != null)
          _detailItem('Year', v['year'].toString(), isDark),
        if (v['mileage'] != null && v['mileage'].toString().isNotEmpty)
          _detailItem('Mileage', '${v['mileage']} km', isDark),
        if (v['transmission'] != null)
          _detailItem('Trans.', v['transmission'].toString(), isDark),
        if (v['fuelType'] != null)
          _detailItem('Fuel', v['fuelType'].toString(), isDark),
      ];

      // Secondary specs — body, drive, engine
      final secondarySpecs = <Widget>[
        if (v['bodyType'] != null)
          _detailItem('Body', v['bodyType'].toString(), isDark),
        if (v['driveType'] != null)
          _detailItem('Drive', v['driveType'].toString(), isDark),
        if (v['engineSize'] != null)
          _detailItem('Engine', v['engineSize'].toString(), isDark),
        if (v['horsepower'] != null)
          _detailItem('Power', '${v['horsepower']} hp', isDark),
        if (v['doors'] != null)
          _detailItem('Doors', v['doors'].toString(), isDark),
        if (v['trim'] != null)
          _detailItem('Trim', v['trim'].toString(), isDark),
        if (v['series'] != null)
          _detailItem('Series', v['series'].toString(), isDark),
        if (v['vehicleType'] != null)
          _detailItem('Type', v['vehicleType'].toString(), isDark),
      ];

      // Safety & EV specs
      final safetySpecs = <Widget>[
        if (v['abs'] != null) _detailItem('ABS', v['abs'].toString(), isDark),
        if (v['airbagLocations'] != null)
          _detailItem('Airbags', v['airbagLocations'].toString(), isDark),
        if (v['gvwr'] != null)
          _detailItem('GVWR', v['gvwr'].toString(), isDark),
        if (v['electrificationType'] != null)
          _detailItem(
            'Electrification',
            v['electrificationType'].toString(),
            isDark,
          ),
        if (v['batteryKWh'] != null)
          _detailItem('Battery', '${v['batteryKWh']} kWh', isDark),
      ];

      widgets.addAll([
        _buildSection('Car Details', theme),
        const SizedBox(height: 8),
        _buildDetailGrid(primarySpecs),
        if (secondarySpecs.isNotEmpty) ...[
          const SizedBox(height: 10),
          _buildDetailGrid(secondarySpecs),
        ],
        if (safetySpecs.isNotEmpty) ...[
          const SizedBox(height: 10),
          _buildDetailGrid(safetySpecs),
        ],
        // Plant origin badge
        if ((v['plantCountry'] != null &&
                v['plantCountry'].toString().isNotEmpty) ||
            (v['plantCity'] != null &&
                v['plantCity'].toString().isNotEmpty)) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.04)
                  : Colors.black.withValues(alpha: 0.02),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.06)
                    : Colors.black.withValues(alpha: 0.06),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(LucideIcons.factory, size: 13, color: theme.hintColor),
                const SizedBox(width: 6),
                Text(
                  'Made in ${[if (v['plantCity'] != null && v['plantCity'].toString().isNotEmpty) v['plantCity'].toString(), if (v['plantCountry'] != null && v['plantCountry'].toString().isNotEmpty) v['plantCountry'].toString()].join(', ')}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: theme.hintColor,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
        ],
        // VIN display
        if (v['vin'] != null && v['vin'].toString().isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.04)
                  : Colors.black.withValues(alpha: 0.02),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.06)
                    : Colors.black.withValues(alpha: 0.06),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(LucideIcons.fingerprint, size: 13, color: theme.hintColor),
                const SizedBox(width: 6),
                Text(
                  'VIN: ${v['vin']}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: theme.hintColor,
                    letterSpacing: 1.1,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 16),
      ]);
    }

    // Motorcycle
    if (listing.motorcycleDetails != null &&
        listing.category == MarketplaceCategory.motorcycles) {
      final m = listing.motorcycleDetails!;
      widgets.addAll([
        _buildSection('Motorcycle Details', theme),
        const SizedBox(height: 8),
        _buildDetailGrid([
          if (m['make'] != null)
            _detailItem('Make', m['make'].toString(), isDark),
          if (m['model'] != null)
            _detailItem('Model', m['model'].toString(), isDark),
          if (m['year'] != null)
            _detailItem('Year', m['year'].toString(), isDark),
          if (m['mileage'] != null && m['mileage'].toString().isNotEmpty)
            _detailItem('Mileage', '${m['mileage']} km', isDark),
          if (m['engineSize'] != null)
            _detailItem('Engine', m['engineSize'].toString(), isDark),
          if (m['type'] != null)
            _detailItem('Type', m['type'].toString(), isDark),
        ]),
        const SizedBox(height: 16),
      ]);
    }

    // Car Parts
    if (listing.carPartsDetails != null &&
        listing.category == MarketplaceCategory.carParts) {
      final cp = listing.carPartsDetails!;
      widgets.addAll([
        _buildSection('Part Details', theme),
        const SizedBox(height: 8),
        _buildDetailGrid([
          if (cp['partNumber'] != null &&
              cp['partNumber'].toString().isNotEmpty)
            _detailItem('Part #', cp['partNumber'].toString(), isDark),
          if (cp['carMake'] != null)
            _detailItem('Fits Make', cp['carMake'].toString(), isDark),
          if (cp['carModel'] != null)
            _detailItem('Fits Model', cp['carModel'].toString(), isDark),
          if (cp['carYear'] != null)
            _detailItem('Fits Year', cp['carYear'].toString(), isDark),
          if (cp['vin'] != null && cp['vin'].toString().isNotEmpty)
            _detailItem('VIN', cp['vin'].toString(), isDark),
          if (cp['oem'] != null)
            _detailItem('OEM', cp['oem'].toString(), isDark),
        ]),
        // Compatible models list
        if (cp['compatibleModels'] != null &&
            (cp['compatibleModels'] as List).isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            'Also fits',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: theme.hintColor,
            ),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: (cp['compatibleModels'] as List)
                .map(
                  (m) => Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.06)
                          : Colors.black.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      m.toString(),
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                )
                .toList(),
          ),
        ],
        const SizedBox(height: 16),
      ]);
    }

    // Real Estate
    if (listing.realEstateDetails != null &&
        listing.category == MarketplaceCategory.realEstate) {
      final r = listing.realEstateDetails!;
      // Support both old keys (sqft, propertyAddress, type) and seeder keys
      final purpose = r['listingPurpose'] ?? r['type'];
      final area = r['squareFootage'] ?? r['sqft'];
      final address = r['address'] ?? r['propertyAddress'];
      widgets.addAll([
        _buildSection('Property Details', theme),
        const SizedBox(height: 8),
        _buildDetailGrid([
          if (purpose != null)
            _detailItem(
              'Type',
              purpose.toString().toLowerCase() == 'rent'
                  ? 'For Rent'
                  : purpose.toString(),
              isDark,
            ),
          if (r['bedrooms'] != null)
            _detailItem('Beds', r['bedrooms'].toString(), isDark),
          if (r['bathrooms'] != null)
            _detailItem('Baths', r['bathrooms'].toString(), isDark),
          if (area != null) _detailItem('Area', '$area sqft', isDark),
          if (address != null)
            _detailItem('Location', address.toString(), isDark),
        ]),
        const SizedBox(height: 16),
      ]);
    }

    // Electronics
    if (listing.electronicsDetails != null &&
        listing.category == MarketplaceCategory.electronics) {
      final e = listing.electronicsDetails!;
      widgets.addAll([
        _buildSection('Device Details', theme),
        const SizedBox(height: 8),
        _buildDetailGrid([
          if (e['brand'] != null)
            _detailItem('Brand', e['brand'].toString(), isDark),
          if (e['model'] != null)
            _detailItem('Model', e['model'].toString(), isDark),
          if (e['storage'] != null)
            _detailItem('Specs', e['storage'].toString(), isDark),
        ]),
        const SizedBox(height: 16),
      ]);
    }

    // Service
    if (listing.serviceDetails != null &&
        listing.listingType == ListingType.service) {
      final s = listing.serviceDetails!;
      // Support both old key (experience) and seeder key (yearsExperience)
      final experience = s['yearsExperience'] ?? s['experience'];
      widgets.addAll([
        _buildSection('Service Details', theme),
        const SizedBox(height: 8),
        _buildDetailGrid([
          if (experience != null)
            _detailItem('Experience', '$experience yrs', isDark),
          if (s['serviceArea'] != null)
            _detailItem('Area', s['serviceArea'].toString(), isDark),
          if (s['availability'] != null)
            _detailItem('Available', s['availability'].toString(), isDark),
        ]),
        const SizedBox(height: 16),
      ]);
    }

    // Job
    if (listing.jobDetails != null && listing.listingType == ListingType.job) {
      final j = listing.jobDetails!;
      widgets.addAll([
        _buildSection('Job Details', theme),
        const SizedBox(height: 8),
        _buildDetailGrid([
          if (j['companyName'] != null)
            _detailItem('Company', j['companyName'].toString(), isDark),
          if (j['employmentType'] != null)
            _detailItem('Type', j['employmentType'].toString(), isDark),
          if (j['salaryRange'] != null)
            _detailItem('Salary', j['salaryRange'].toString(), isDark),
          if (j['experienceLevel'] != null)
            _detailItem('Experience', j['experienceLevel'].toString(), isDark),
          if (j['workMode'] != null)
            _detailItem('Work Mode', j['workMode'].toString(), isDark),
          if (j['applicationDeadline'] != null)
            _detailItem(
              'Deadline',
              j['applicationDeadline'].toString(),
              isDark,
            ),
          if (j['visaSponsorship'] != null)
            _detailItem(
              'Visa Sponsor',
              j['visaSponsorship'].toString(),
              isDark,
            ),
        ]),
        const SizedBox(height: 16),
      ]);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: widgets,
    );
  }

  Widget _buildDetailGrid(List<Widget> items) {
    return Wrap(spacing: 8, runSpacing: 8, children: items);
  }

  Widget _detailItem(String label, String value, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.03)
            : Colors.black.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: isDark
                  ? Colors.white.withValues(alpha: 0.4)
                  : Colors.black.withValues(alpha: 0.4),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: isDark
                  ? Colors.white.withValues(alpha: 0.8)
                  : Colors.black.withValues(alpha: 0.8),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Seller / Poster Card (Organizer-style) ─────────────────────────
  Widget _buildSellerCard(
    MarketplaceListing listing,
    ThemeData theme,
    bool isDark,
  ) {
    final userId = ref.read(authRepositoryProvider).currentUser?.uid;
    final isOwner = listing.sellerId == userId;

    // Fetch live profile for the seller
    final sellerProfileAsync = ref.watch(
      userProfileByIdProvider(listing.sellerId),
    );

    // Label based on listing type
    final roleLabel = listing.listingType == ListingType.job
        ? 'Posted by'
        : listing.listingType == ListingType.service
        ? 'Offered by'
        : 'Sold by';

    return sellerProfileAsync.when(
      data: (profile) {
        final displayName =
            listing.orgName ??
            (profile != null
                ? '${profile.firstName} ${profile.lastName}'
                : listing.sellerName);
        final photoUrl = profile?.profileImage ?? listing.sellerPhoto;
        final city = profile?.hostLocation.city ?? listing.sellerCity;
        final phone = profile?.phone;

        return InkWell(
          onTap: () => context.push('/profile/${listing.sellerId}'),
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withValues(
                alpha: 0.2,
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                // Avatar
                CircleAvatar(
                  radius: 20,
                  backgroundImage: photoUrl != null && photoUrl.isNotEmpty
                      ? CachedNetworkImageProvider(photoUrl)
                      : null,
                  backgroundColor: isDark
                      ? Colors.white.withValues(alpha: 0.06)
                      : Colors.black.withValues(alpha: 0.04),
                  child: (photoUrl == null || photoUrl.isEmpty)
                      ? Icon(
                          LucideIcons.user,
                          size: 18,
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.5,
                          ),
                        )
                      : null,
                ),
                const SizedBox(width: 12),
                // Name + role label
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        roleLabel,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              displayName,
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Icon(
                            Icons.verified,
                            size: 14,
                            color: AppTheme.info,
                          ),
                        ],
                      ),
                      if (city != null && city.isNotEmpty) ...[
                        const SizedBox(height: 1),
                        Row(
                          children: [
                            Icon(
                              LucideIcons.mapPin,
                              size: 10,
                              color: theme.hintColor,
                            ),
                            const SizedBox(width: 3),
                            Text(
                              city,
                              style: TextStyle(
                                fontSize: 11,
                                color: theme.hintColor,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                // Quick action buttons (only for non-owners)
                if (!isOwner) ...[
                  // WhatsApp button (if phone available)
                  if (phone != null && phone.isNotEmpty)
                    IconButton(
                      icon: const Icon(
                        LucideIcons.phone,
                        size: 18,
                        color: Colors.green,
                      ),
                      tooltip: 'WhatsApp Call',
                      visualDensity: VisualDensity.compact,
                      onPressed: () => _launchWhatsApp(phone),
                    ),
                  // In-app chat button
                  IconButton(
                    icon: Icon(
                      LucideIcons.messageCircle,
                      size: 18,
                      color: theme.colorScheme.primary,
                    ),
                    tooltip: 'Send Message',
                    visualDensity: VisualDensity.compact,
                    onPressed: () =>
                        context.push('/chat/direct/${listing.sellerId}'),
                  ),
                ],
                if (isOwner)
                  Icon(
                    LucideIcons.chevronRight,
                    size: 16,
                    color: theme.hintColor,
                  ),
              ],
            ),
          ),
        );
      },
      loading: () => Container(
        height: 56,
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(
            alpha: 0.2,
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Center(child: LinearProgressIndicator()),
      ),
      error: (_, _) => const SizedBox.shrink(),
    );
  }

  // ─── Chips & Badges ───────────────────────────────────────────────────
  Widget _buildIconChip(
    IconData? icon,
    String label,
    bool isDark, {
    Color? color,
  }) {
    final chipColor = color ?? (isDark ? Colors.white70 : Colors.black54);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: (color ?? Colors.grey).withValues(alpha: isDark ? 0.15 : 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: chipColor),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: chipColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSection(String title, ThemeData theme) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w700,
        color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
      ),
    );
  }

  Widget _buildStat(IconData icon, String value, ThemeData theme) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: theme.hintColor),
        const SizedBox(width: 4),
        Text(value, style: TextStyle(fontSize: 12, color: theme.hintColor)),
      ],
    );
  }

  Widget _buildStatusBadge(MarketplaceListing listing, ThemeData theme) {
    Color color;
    String label;
    IconData statusIcon;
    switch (listing.status) {
      case ListingStatus.sold:
        color = AppTheme.success;
        label = 'Sold';
        statusIcon = LucideIcons.checkCircle;
        break;
      case ListingStatus.paused:
        color = AppTheme.warning;
        label = 'Paused';
        statusIcon = LucideIcons.pauseCircle;
        break;
      case ListingStatus.expired:
        color = AppTheme.error;
        label = 'Expired';
        statusIcon = LucideIcons.clock;
        break;
      case ListingStatus.flagged:
        color = AppTheme.error;
        label = 'Flagged';
        statusIcon = LucideIcons.flag;
        break;
      default:
        color = AppTheme.info;
        label = listing.status;
        statusIcon = LucideIcons.info;
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(statusIcon, size: 16, color: color),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: color,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _deliveryIcon(String d) {
    switch (d) {
      case 'pickup':
        return LucideIcons.mapPin;
      case 'delivery':
        return LucideIcons.truck;
      case 'shipping':
        return LucideIcons.package;
      case 'digital':
        return LucideIcons.monitor;
      default:
        return LucideIcons.package;
    }
  }

  IconData _contactIcon(String method) {
    switch (method) {
      case ContactMethod.chat:
        return LucideIcons.messageCircle;
      case ContactMethod.phone:
        return LucideIcons.phone;
      case ContactMethod.whatsapp:
        return LucideIcons.messageSquare;
      case ContactMethod.email:
        return LucideIcons.mail;
      default:
        return LucideIcons.messageCircle;
    }
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

  // ─── Actions ──────────────────────────────────────────────────────────
  void _toggleSave(MarketplaceListing listing) async {
    final user = ref.read(authRepositoryProvider).currentUser;
    if (user == null) return;
    final repo = ref.read(marketplaceRepositoryProvider);

    setState(() => _isSaved = !_isSaved);

    if (_isSaved) {
      await repo.saveListing(listing.id, user.uid);
      await repo.saveListingToUser(listing.id, user.uid);
    } else {
      await repo.unsaveListing(listing.id, user.uid);
      await repo.unsaveListingFromUser(listing.id, user.uid);
    }
  }

  /// Determine the seller role based on the listing category
  String _getSellerRole(String category) {
    if (MarketplaceCategory.jobCategories.contains(category)) {
      return 'Employer';
    } else if (MarketplaceCategory.serviceCategories.contains(category)) {
      return 'Provider';
    } else {
      return 'Seller';
    }
  }

  /// Determine the listing type (product, service, job) from category
  String _getListingType(String category) {
    if (MarketplaceCategory.jobCategories.contains(category)) {
      return 'job';
    } else if (MarketplaceCategory.serviceCategories.contains(category)) {
      return 'service';
    } else {
      return 'product';
    }
  }

  Future<void> _contactSeller(MarketplaceListing listing) async {
    final user = ref.read(authRepositoryProvider).currentUser;
    if (user == null) return;

    if (!mounted) return;

    // Create or get listing-specific chat
    final sellerRole = _getSellerRole(listing.category);
    final listingType = _getListingType(listing.category);

    // Route based on contact method
    switch (listing.contactMethod) {
      case ContactMethod.whatsapp:
        final profileAsync = ref.read(
          userProfileByIdProvider(listing.sellerId),
        );
        final phone = profileAsync.value?.phone;
        if (phone != null && phone.isNotEmpty) {
          _launchWhatsApp(phone);
        } else {
          await _navigateToListingChat(listing, sellerRole, listingType);
        }
        break;
      case ContactMethod.chat:
        await _navigateToListingChat(listing, sellerRole, listingType);
        break;
      case ContactMethod.phone:
        final profileAsync = ref.read(
          userProfileByIdProvider(listing.sellerId),
        );
        final phone = profileAsync.value?.phone;
        if (phone != null && phone.isNotEmpty) {
          final cleanPhone = phone.replaceAll(RegExp(r'[^\d+]'), '');
          launchUrl(Uri.parse('tel:$cleanPhone'));
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Phone number not available')),
          );
        }
        break;
      case ContactMethod.email:
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Contacting ${listing.sellerName} via email...'),
            backgroundColor: AppTheme.accent,
          ),
        );
        break;
      default:
        await _navigateToListingChat(listing, sellerRole, listingType);
    }
  }

  /// Creates (or retrieves) a listing-specific chat and navigates to it
  Future<void> _navigateToListingChat(
    MarketplaceListing listing,
    String sellerRole,
    String listingType,
  ) async {
    try {
      final chatRepo = ref.read(chatRepositoryProvider);
      final chat = await chatRepo.createListingChat(
        otherUserId: listing.sellerId,
        listingId: listing.id,
        listingTitle: listing.title,
        listingType: listingType,
        sellerRole: sellerRole,
        listingImageUrl: listing.images.isNotEmpty
            ? listing.images.first
            : null,
      );

      if (!mounted) return;

      if (chat != null) {
        debugPrint('✅ [Marketplace] Navigating to listing chat: ${chat.id}');
        context.push('/chats/${chat.id}');
      } else {
        debugPrint(
          '⚠️ [Marketplace] Chat creation returned null, falling back to direct DM',
        );
        context.push('/chat/direct/${listing.sellerId}');
      }
    } catch (e) {
      debugPrint(
        '❌ [Marketplace] Chat creation error: $e — falling back to direct DM',
      );
      if (!mounted) return;
      context.push('/chat/direct/${listing.sellerId}');
    }
  }

  /// Launch WhatsApp with the given phone number
  Future<void> _launchWhatsApp(String phone) async {
    final success = await WhatsAppUtils.launchWhatsApp(phone);
    if (!success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not launch WhatsApp')),
      );
    }
  }

  void _onMenuAction(String action, MarketplaceListing listing) async {
    final repo = ref.read(marketplaceRepositoryProvider);

    switch (action) {
      case 'edit':
        context.push('/marketplace/create', extra: listing);
        break;
      case 'pause':
        await repo.updateListingStatus(listing.id, ListingStatus.paused);
        _loadListing();
        break;
      case 'activate':
        await repo.updateListingStatus(listing.id, ListingStatus.active);
        _loadListing();
        break;
      case 'sold':
        await repo.updateListingStatus(listing.id, ListingStatus.sold);
        _loadListing();
        break;
      case 'delete':
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Delete Listing?'),
            content: const Text('This action cannot be undone.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text(
                  'Delete',
                  style: TextStyle(color: AppTheme.error),
                ),
              ),
            ],
          ),
        );
        if (confirmed == true && mounted) {
          await repo.deleteListing(listing.id);
          if (mounted) context.pop();
        }
    }
  }

  void _reportListing(MarketplaceListing listing) {
    showDialog(
      context: context,
      builder: (ctx) {
        final reasonController = TextEditingController();
        return AlertDialog(
          title: const Text('Report Listing'),
          content: TextField(
            controller: reasonController,
            decoration: const InputDecoration(
              hintText: 'Why are you reporting this?',
            ),
            maxLines: 3,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                final user = ref.read(authRepositoryProvider).currentUser;
                if (user != null) {
                  await ref
                      .read(marketplaceRepositoryProvider)
                      .reportListing(
                        listing.id,
                        user.uid,
                        reasonController.text,
                      );
                }
                if (ctx.mounted) {
                  Navigator.pop(ctx);
                }
                messenger.showSnackBar(
                  const SnackBar(content: Text('Report submitted')),
                );
              },
              child: const Text(
                'Submit',
                style: TextStyle(color: AppTheme.error),
              ),
            ),
          ],
        );
      },
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

          // Page indicator
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
