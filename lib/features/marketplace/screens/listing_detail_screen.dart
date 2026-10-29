import 'dart:async';
import 'dart:ui';
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
import 'package:diaspora_nearby/features/chat/models/chat.dart';
import 'package:diaspora_nearby/features/chat/repository/chat_repository.dart';
import 'package:diaspora_nearby/features/dsp/providers/dsp_valuation_provider.dart';
import 'package:diaspora_nearby/features/dsp/services/points_service.dart';
import 'package:diaspora_nearby/features/dsp/services/smart_wallet_service.dart';
import 'package:diaspora_nearby/features/marketplace/utils/currency_helper.dart';

class ListingDetailScreen extends ConsumerStatefulWidget {
  final String listingId;

  const ListingDetailScreen({super.key, required this.listingId});

  @override
  ConsumerState<ListingDetailScreen> createState() =>
      _ListingDetailScreenState();
}

class _ListingDetailScreenState extends ConsumerState<ListingDetailScreen> {
  MarketplaceListing? _listing;
  Chat? _listingChat;
  Future<Chat?>? _listingChatFuture;
  bool _isOpeningChat = false;
  bool _isLoading = true;
  bool _isSaved = false;
  int _currentImageIndex = 0;
  final PageController _imagePageController = PageController();
  String? _viewerCountryCode;

  @override
  void initState() {
    super.initState();
    final repo = ref.read(marketplaceRepositoryProvider);
    final cached = repo.getCachedListing(widget.listingId);
    if (cached != null) {
      _listing = cached;
      _isLoading = false;
      _isSaved = repo.isListingSavedSync(widget.listingId);
      _listingChat = ref
          .read(chatRepositoryProvider)
          .getCachedListingChat(cached.id);
    }
    _viewerCountryCode = ref.read(userProfileProvider).value?.hostCountryCode;
    _loadListing();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final profile = ref.read(userProfileProvider).value;
      if (profile != null && _viewerCountryCode != profile.hostCountryCode) {
        setState(() => _viewerCountryCode = profile.hostCountryCode);
      }
      if (_listing != null) {
        _listingChatFuture ??= _ensureListingChat(_listing!);
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
      final user = ref.read(authRepositoryProvider).currentUser;

      final listingFuture = repo.getListingById(widget.listingId);
      final savedFuture = user != null
          ? repo.isListingSaved(widget.listingId, user.uid)
          : Future.value(false);

      final listing = await listingFuture;
      if (listing != null) {
        unawaited(repo.incrementViewCount(widget.listingId));

        if (user != null) {
          _listingChat ??= ref
              .read(chatRepositoryProvider)
              .getCachedListingChat(listing.id);
          _listingChatFuture ??= _ensureListingChat(listing);
        }
      }
      final saved = await savedFuture;
      if (mounted) {
        setState(() {
          if (listing != null) _listing = listing;
          _isSaved = saved;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('❌ Error loading listing ${widget.listingId}: $e');
      if (mounted) {
        setState(() {
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
                              color: _currentImageIndex == i
                                  ? AppTheme.accent.withValues(alpha: 0.25)
                                  : const Color(0x14888888),
                              borderRadius: BorderRadius.circular(8),
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
                    Flexible(
                      child: CurrencyPriceDisplay(
                        amount: listing.priceAmount,
                        sellerCountryCode: listing.sellerCountryCode,
                        viewerCountryCode: _viewerCountryCode,
                        showToggle: false,
                        primaryColor: marketplaceSageGreen,
                        primaryStyle: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: marketplaceSageGreen,
                        ),
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
          ? _buildOwnerBottomBar(listing, theme, isDark)
          : _buildBottomBar(listing, theme, isDark),
    );
  }

  // ─── Owner Bottom Action Bar ────────────────────────────────────────
  Widget _buildOwnerBottomBar(
    MarketplaceListing listing,
    ThemeData theme,
    bool isDark,
  ) {
    const sageGreen = marketplaceSageGreen;
    final isJob = listing.listingType == ListingType.job;
    final isSold = listing.status == ListingStatus.sold;
    final isPaused = listing.status == ListingStatus.paused;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.02)
            : Colors.black.withValues(alpha: 0.01),
      ),
      child: SafeArea(
        child: Row(
          children: [
            // Primary action: Open Shop Chat
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _isOpeningChat
                    ? null
                    : () {
                        final sellerRole = _getSellerRole(listing.category);
                        final listingType = _getListingType(listing.category);
                        _navigateToListingChat(
                          listing,
                          sellerRole,
                          listingType,
                        );
                      },
                icon: _isOpeningChat
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(LucideIcons.shoppingCart, size: 18),
                label: const Text(
                  'Open Shop Chat',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
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
            // Secondary: Mark Sold / Filled or Relist
            ElevatedButton.icon(
              onPressed: () => _onMenuAction(
                (isSold || isPaused) ? 'activate' : 'sold',
                listing,
              ),
              icon: Icon(
                (isSold || isPaused)
                    ? LucideIcons.rotateCcw
                    : LucideIcons.checkCircle2,
                size: 16,
              ),
              label: Text(
                (isSold || isPaused)
                    ? 'Relist'
                    : (isJob ? 'Mark Filled' : 'Mark Sold'),
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
                foregroundColor: (isSold || isPaused)
                    ? AppTheme.accent
                    : sageGreen,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 14,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Edit button
            SizedBox(
              width: 48,
              child: ElevatedButton(
                onPressed: () => _onMenuAction('edit', listing),
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                  foregroundColor: theme.colorScheme.onSurface,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Icon(LucideIcons.edit3, size: 18),
              ),
            ),
          ],
        ),
      ),
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
      primaryAction = () => _showCheckoutModal(listing);
    } else {
      primaryLabel = 'Buy';
      primaryIcon = LucideIcons.shoppingBag;
      primaryAction = () => _showCheckoutModal(listing);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.02)
            : Colors.black.withValues(alpha: 0.01),
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
            // Secondary: Open listing chat
            SizedBox(
              width: 56,
              child: ElevatedButton(
                onPressed: _isOpeningChat
                    ? null
                    : () => _openListingChat(listing),
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                  foregroundColor: sageGreen,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _isOpeningChat
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: sageGreen,
                        ),
                      )
                    : const Icon(LucideIcons.messageCircle, size: 20),
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

  /// Pick a document (CV/Resume) and navigate to the listing chat to send it
  Future<void> _applyWithResume(MarketplaceListing listing) async {
    if (!mounted) return;

    await _openListingChat(listing);

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

    // Fetch live profile for the seller with synchronous cache fallback (0ms)
    final sellerProfileAsync = ref.watch(
      userProfileByIdProvider(listing.sellerId),
    );
    final profile =
        sellerProfileAsync.asData?.value ??
        ref.read(profileRepositoryProvider).getCachedProfile(listing.sellerId);

    // Label based on listing type
    final roleLabel = listing.listingType == ListingType.job
        ? 'Posted by'
        : listing.listingType == ListingType.service
        ? 'Offered by'
        : 'Sold by';

    final displayName =
        listing.orgName ??
        (profile != null
            ? '${profile.firstName} ${profile.lastName}'
            : listing.sellerName);
    final photoUrl =
        (profile != null && profile.profileImage.isNotEmpty)
        ? profile.profileImage
        : listing.sellerPhoto;
    final city =
        (profile?.hostLocation.city?.isNotEmpty == true)
        ? profile!.hostLocation.city!
        : listing.sellerCity;

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
            // Quick action button (only for non-owners): In-app listing chat
            if (!isOwner)
              IconButton(
                icon: _isOpeningChat
                    ? SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: theme.colorScheme.primary,
                        ),
                      )
                    : Icon(
                        LucideIcons.messageCircle,
                        size: 18,
                        color: theme.colorScheme.primary,
                      ),
                tooltip: 'Listing Chat',
                visualDensity: VisualDensity.compact,
                onPressed: _isOpeningChat
                    ? null
                    : () => _openListingChat(listing),
              ),
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

    final nextSaved = !_isSaved;
    setState(() => _isSaved = nextSaved);

    try {
      if (nextSaved) {
        await Future.wait([
          repo.saveListing(listing.id, user.uid),
          repo.saveListingToUser(listing.id, user.uid),
        ]);
      } else {
        await Future.wait([
          repo.unsaveListing(listing.id, user.uid),
          repo.unsaveListingFromUser(listing.id, user.uid),
        ]);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaved = !nextSaved);
      }
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

  /// Ensure the listing chat exists and is cached in memory
  Future<Chat?> _ensureListingChat(MarketplaceListing listing) async {
    final chatRepo = ref.read(chatRepositoryProvider);
    final cached = _listingChat ?? chatRepo.getCachedListingChat(listing.id);
    if (cached != null) {
      _listingChat = cached;
      return cached;
    }
    final sellerRole = _getSellerRole(listing.category);
    final listingType = _getListingType(listing.category);
    final chat = await chatRepo.createListingChat(
      otherUserId: listing.sellerId,
      listingId: listing.id,
      listingTitle: listing.title,
      listingType: listingType,
      sellerRole: sellerRole,
      listingImageUrl: listing.images.isNotEmpty ? listing.images.first : null,
    );
    if (chat != null) {
      _listingChat = chat;
    }
    return chat;
  }

  /// Open the listing-specific in-app chat
  Future<void> _openListingChat(MarketplaceListing listing) async {
    final user = ref.read(authRepositoryProvider).currentUser;
    if (user == null || !mounted) return;

    final sellerRole = _getSellerRole(listing.category);
    final listingType = _getListingType(listing.category);
    await _navigateToListingChat(listing, sellerRole, listingType);
  }

  /// Show the modified Value Transfer modal for Marketplace Checkout
  void _showCheckoutModal(MarketplaceListing listing) {
    final user = ref.read(authRepositoryProvider).currentUser;
    if (user == null || !mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (modalCtx) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: _MarketplaceCheckoutModal(
          listing: listing,
          onPayToken: (int tokenAmount) async {
            Navigator.pop(modalCtx);
            await _executeTokenCheckout(listing, tokenAmount);
          },
          onPayFiat:
              (
                double amount,
                String currency,
                double convertedAmount,
                String receiverCurrency,
                double exchangeRate,
              ) async {
                Navigator.pop(modalCtx);
                await _executeFiatCheckout(
                  listing,
                  amount,
                  currency,
                  convertedAmount,
                  receiverCurrency,
                  exchangeRate,
                );
              },
        ),
      ),
    );
  }

  /// Execute $DIASPORA Smart Wallet checkout and post receipt into the listing chat
  Future<void> _executeTokenCheckout(
    MarketplaceListing listing,
    int amount,
  ) async {
    final currentUserId = ref.read(authRepositoryProvider).currentUser?.uid;
    if (currentUserId == null || !mounted) return;

    try {
      final chatRepo = ref.read(chatRepositoryProvider);
      final fastChat = _listingChat ?? chatRepo.getCachedListingChat(listing.id);
      if (fastChat != null && mounted) {
        context.push('/chats/${fastChat.id}');
      }

      final pointsService = ref.read(pointsServiceProvider);
      unawaited(() async {
        try {
          await pointsService.transferAsset(
            fromUserId: currentUserId,
            toUserId: listing.sellerId,
            amount: amount,
            assetType: 'token',
          );
          final chat =
              fastChat ??
              await (_listingChatFuture ?? _ensureListingChat(listing));
          if (chat != null) {
            await chatRepo.sendTextMessage(
              chat.id,
              'Paid $amount \$DIASPORA for ${listing.title}',
              type: 'dsp_transfer',
              metadata: {
                'amount': amount,
                'currency': 'DIASPORA',
                'assetType': 'token',
                'listingId': listing.id,
                'listingTitle': listing.title,
              },
              participants: chat.participants,
            );
            if (fastChat == null && mounted) {
              context.push('/chats/${chat.id}');
            }
          }
        } catch (e) {
          debugPrint('CHECKOUT_TOKEN_ERROR: $e');
          if (mounted) {
            final cleanMsg = e
                .toString()
                .split('\n')
                .first
                .replaceFirst(RegExp(r'^\[firebase_functions/[^\]]+\]\s*'), '');
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text('Checkout failed: $cleanMsg')));
          }
        }
      }());
    } catch (e) {
      debugPrint('CHECKOUT_TOKEN_ERROR: $e');
      if (mounted) {
        final cleanMsg = e
            .toString()
            .split('\n')
            .first
            .replaceFirst(RegExp(r'^\[firebase_functions/[^\]]+\]\s*'), '');
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Checkout failed: $cleanMsg')));
      }
    }
  }

  /// Execute Fiat checkout and post remittance receipt into the listing chat
  Future<void> _executeFiatCheckout(
    MarketplaceListing listing,
    double amount,
    String currency,
    double convertedAmount,
    String receiverCurrency,
    double exchangeRate,
  ) async {
    final currentUserId = ref.read(authRepositoryProvider).currentUser?.uid;
    if (currentUserId == null || !mounted) return;

    try {
      final chatRepo = ref.read(chatRepositoryProvider);
      final formattedAmount = CurrencyHelper.formatFiatAmount(amount);
      final formattedConverted = CurrencyHelper.formatFiatAmount(
        convertedAmount,
      );
      final caption = currency != receiverCurrency && convertedAmount > 0
          ? 'Paid $formattedAmount $currency (≈ $formattedConverted $receiverCurrency) for ${listing.title}'
          : 'Paid $formattedAmount $currency for ${listing.title}';

      final fastChat = _listingChat ?? chatRepo.getCachedListingChat(listing.id);
      if (fastChat != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Payment of $formattedAmount $currency sent for ${listing.title}!',
            ),
            backgroundColor: Colors.green.shade700,
            behavior: SnackBarBehavior.floating,
          ),
        );
        context.push('/chats/${fastChat.id}');
      }

      unawaited(() async {
        try {
          final chat =
              fastChat ??
              await (_listingChatFuture ?? _ensureListingChat(listing));
          if (chat != null) {
            await chatRepo.sendTextMessage(
              chat.id,
              caption,
              type: 'money-transfer',
              metadata: {
                'amount': amount,
                'currency': currency,
                'convertedAmount': convertedAmount,
                'convertedCurrency': receiverCurrency,
                'exchangeRate': exchangeRate,
                'deliveryMethod': 'Mobile Money / Bank Settlement',
                'fee': 0.0,
                'status': 'Completed',
                'assetType': 'fiat',
                'recipientId': listing.sellerId,
                'listingId': listing.id,
                'listingTitle': listing.title,
                'timestamp': DateTime.now().millisecondsSinceEpoch,
              },
              participants: chat.participants,
            );
            if (fastChat == null && mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Payment of $formattedAmount $currency sent for ${listing.title}!',
                  ),
                  backgroundColor: Colors.green.shade700,
                  behavior: SnackBarBehavior.floating,
                ),
              );
              context.push('/chats/${chat.id}');
            }
          }
        } catch (e) {
          debugPrint('CHECKOUT_FIAT_ERROR: $e');
          if (mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text('Checkout failed: $e')));
          }
        }
      }());
    } catch (e) {
      debugPrint('CHECKOUT_FIAT_ERROR: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Checkout failed: $e')));
      }
    }
  }

  /// Creates (or retrieves) a listing-specific chat and navigates to it
  Future<void> _navigateToListingChat(
    MarketplaceListing listing,
    String sellerRole,
    String listingType,
  ) async {
    // 1. Instant 0ms synchronous navigation if already pre-warmed / cached
    final chatRepo = ref.read(chatRepositoryProvider);
    final fastChat = _listingChat ?? chatRepo.getCachedListingChat(listing.id);
    if (fastChat != null) {
      _listingChat = fastChat;
      context.push('/chats/${fastChat.id}');
      return;
    }

    if (_isOpeningChat) return;
    setState(() => _isOpeningChat = true);

    try {
      final chat = await (_listingChatFuture ?? _ensureListingChat(listing));

      if (!mounted) return;
      setState(() => _isOpeningChat = false);

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
      setState(() => _isOpeningChat = false);
      context.push('/chat/direct/${listing.sellerId}');
    }
  }

  void _onMenuAction(String action, MarketplaceListing listing) async {
    final repo = ref.read(marketplaceRepositoryProvider);

    switch (action) {
      case 'edit':
        context.push('/marketplace/create', extra: listing);
        break;
      case 'pause':
        final paused = listing.copyWith(status: ListingStatus.paused);
        setState(() => _listing = paused);
        repo.cacheListing(paused);
        unawaited(() async {
          await repo.updateListingStatus(listing.id, ListingStatus.paused);
          await _notifyShopChatStatus(listing, 'Listing paused by seller');
        }());
        break;
      case 'activate':
        final active = listing.copyWith(status: ListingStatus.active);
        setState(() => _listing = active);
        repo.cacheListing(active);
        unawaited(() async {
          await repo.updateListingStatus(listing.id, ListingStatus.active);
          await _notifyShopChatStatus(
            listing,
            'Listing is now available again',
          );
        }());
        break;
      case 'sold':
        final sold = listing.copyWith(status: ListingStatus.sold);
        setState(() => _listing = sold);
        repo.cacheListing(sold);
        unawaited(() async {
          await repo.updateListingStatus(listing.id, ListingStatus.sold);
          await _notifyShopChatStatus(
            listing,
            listing.listingType == ListingType.job
                ? 'Position marked as Filled'
                : 'Item marked as Sold',
          );
        }());
        break;
      case 'delete':
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: AlertDialog(
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 24,
              ),
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
          ),
        );
        if (confirmed == true && mounted) {
          repo.removeCachedListing(listing.id);
          context.pop();
          unawaited(repo.deleteListing(listing.id));
        }
    }
  }

  /// Post a system status update in the listing's Shop Chat when status changes
  Future<void> _notifyShopChatStatus(
    MarketplaceListing listing,
    String statusMessage,
  ) async {
    try {
      final chatRepo = ref.read(chatRepositoryProvider);
      final chatId = await chatRepo.getExistingListingChat(listing.id);
      if (chatId != null) {
        final chat = await chatRepo.getChat(chatId);
        await chatRepo.sendTextMessage(
          chatId,
          statusMessage,
          type: 'system',
          participants: chat?.participants,
        );
      }
    } catch (e) {
      debugPrint('⚠️ [Marketplace] Could not post shop status update: $e');
    }
  }

  void _reportListing(MarketplaceListing listing) {
    showDialog(
      context: context,
      builder: (ctx) {
        final reasonController = TextEditingController();
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: AlertDialog(
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 8,
              vertical: 24,
            ),
            title: const Text('Report Listing'),
            content: TextField(
              controller: reasonController,
              decoration: const InputDecoration(
                hintText: 'Why are you reporting this?',
                border: InputBorder.none,
              ),
              maxLines: 3,
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () {
                  final reason = reasonController.text;
                  final messenger = ScaffoldMessenger.of(context);
                  final user = ref.read(authRepositoryProvider).currentUser;
                  final repo = ref.read(marketplaceRepositoryProvider);
                  if (ctx.mounted) {
                    Navigator.pop(ctx);
                  }
                  messenger.showSnackBar(
                    const SnackBar(content: Text('Report submitted')),
                  );
                  if (user != null) {
                    unawaited(
                      repo.reportListing(
                        listing.id,
                        user.uid,
                        reason,
                        sellerId: listing.sellerId,
                      ),
                    );
                  }
                },
                child: const Text(
                  'Submit',
                  style: TextStyle(color: AppTheme.error),
                ),
              ),
            ],
          ),
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

// ─── Marketplace Value Transfer Checkout Modal ────────────────────────────
class _MarketplaceCheckoutModal extends ConsumerStatefulWidget {
  final MarketplaceListing listing;
  final ValueChanged<int> onPayToken;
  final void Function(
    double amount,
    String currency,
    double convertedAmount,
    String receiverCurrency,
    double exchangeRate,
  )
  onPayFiat;

  const _MarketplaceCheckoutModal({
    required this.listing,
    required this.onPayToken,
    required this.onPayFiat,
  });

  @override
  ConsumerState<_MarketplaceCheckoutModal> createState() =>
      _MarketplaceCheckoutModalState();
}

class _MarketplaceCheckoutModalState
    extends ConsumerState<_MarketplaceCheckoutModal> {
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _fiatAmountController = TextEditingController();

  String _selectedAssetType = 'token'; // 'token' or 'fiat'
  int _inputAmount = 0;
  double _fiatInputAmount = 0;
  bool _initializedDefaults = false;

  @override
  void initState() {
    super.initState();
    _amountController.addListener(() {
      final val = int.tryParse(_amountController.text.replaceAll(',', '')) ?? 0;
      if (mounted) setState(() => _inputAmount = val);
    });
    _fiatAmountController.addListener(() {
      final val =
          double.tryParse(_fiatAmountController.text.replaceAll(',', '')) ?? 0;
      if (mounted) setState(() => _fiatInputAmount = val);
    });
  }

  @override
  void dispose() {
    _amountController.dispose();
    _fiatAmountController.dispose();
    super.dispose();
  }

  void _initializeDefaultAmounts({
    required double dspPriceFloorUsd,
    required String buyerCountryCode,
    required String sellerCountryCode,
  }) {
    if (_initializedDefaults) return;
    _initializedDefaults = true;

    final price = widget.listing.priceAmount;
    if (price <= 0) return;

    final rawTokens = CurrencyHelper.localToDiasporaToken(
      price,
      sellerCountryCode,
      dspPriceFloorUsd: dspPriceFloorUsd,
    ).round();
    final defaultTokens = rawTokens > 0 ? rawTokens : 1;
    _amountController.text = defaultTokens.toString();
    _inputAmount = defaultTokens;

    final defaultFiat =
        CurrencyHelper.isSameCurrency(sellerCountryCode, buyerCountryCode)
        ? price
        : CurrencyHelper.convertCurrency(
            price,
            sellerCountryCode,
            buyerCountryCode,
          );
    _fiatAmountController.text = defaultFiat.toStringAsFixed(
      defaultFiat.truncateToDouble() == defaultFiat ? 0 : 2,
    );
    _fiatInputAmount =
        double.tryParse(_fiatAmountController.text) ?? defaultFiat;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isFiat = _selectedAssetType == 'fiat';
    final isToken = _selectedAssetType == 'token';
    final activeColor = isFiat ? AppTheme.fiatColor : AppTheme.tokenColor;

    // Fetch live $DIASPORA valuation & user's Smart Wallet balance
    final valuation = ref.watch(dspValuationProvider);
    final tokenBalanceAsync = ref.watch(tokenBalanceProvider);
    final currentBalance =
        (double.tryParse(tokenBalanceAsync.asData?.value ?? '0') ?? 0.0)
            .toInt();
    final isLoadingBalance = tokenBalanceAsync.isLoading;

    // Buyer (sender) currency
    final buyerProfile = ref.watch(userProfileProvider).asData?.value;
    final buyerCountryCode = buyerProfile?.hostCountryCode ?? 'US';
    final currencyCode = CurrencyHelper.currencyCode(buyerCountryCode);
    final currencySymbol = CurrencyHelper.currencySymbol(buyerCountryCode);

    // Seller (recipient) profile & currency
    final sellerProfileAsync = ref.watch(
      userProfileByIdProvider(widget.listing.sellerId),
    );
    final sellerProfile = sellerProfileAsync.asData?.value;
    final sellerCountryCode =
        widget.listing.sellerCountryCode ??
        sellerProfile?.currentLocation?.countryCode ??
        sellerProfile?.hostCountryCode ??
        sellerProfile?.homeCountryCode ??
        'TZ';
    final receiverCurrencyCode = CurrencyHelper.currencyCode(sellerCountryCode);

    final rawSellerFirstName = sellerProfile?.firstName.trim() ?? '';
    final fallbackFirstName = widget.listing.sellerName.trim().split(' ').first;
    final sellerFirstName = rawSellerFirstName.isNotEmpty
        ? rawSellerFirstName
        : (fallbackFirstName.isNotEmpty ? fallbackFirstName : 'Seller');
    final sellerDisplayName =
        widget.listing.orgName ??
        (sellerProfile != null
            ? '${sellerProfile.firstName} ${sellerProfile.lastName}'.trim()
            : widget.listing.sellerName);

    _initializeDefaultAmounts(
      dspPriceFloorUsd: valuation.impliedValueUsd,
      buyerCountryCode: buyerCountryCode,
      sellerCountryCode: sellerCountryCode,
    );

    final remaining = currentBalance - _inputAmount;
    final isError = _inputAmount > currentBalance;
    final isZero = _inputAmount <= 0;

    final convertedAmount = CurrencyHelper.convertCurrency(
      _fiatInputAmount,
      buyerCountryCode,
      sellerCountryCode,
    );
    final exchangeRate = CurrencyHelper.convertCurrency(
      1.0,
      buyerCountryCode,
      sellerCountryCode,
    );
    final isFiatZero = _fiatInputAmount <= 0;

    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return SafeArea(
      child: Container(
        decoration: BoxDecoration(
          color: theme.scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: EdgeInsets.fromLTRB(12, 16, 12, 20 + bottomInset),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Drag handle
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: theme.colorScheme.onSurfaceVariant.withValues(
                    alpha: 0.25,
                  ),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              // ─── LISTING CHECKOUT SUMMARY CARD ───
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest.withValues(
                    alpha: 0.25,
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: widget.listing.images.isNotEmpty
                          ? CachedNetworkImage(
                              imageUrl: widget.listing.images.first,
                              width: 52,
                              height: 52,
                              fit: BoxFit.cover,
                            )
                          : Container(
                              width: 52,
                              height: 52,
                              color: marketplaceSageGreen.withValues(
                                alpha: 0.12,
                              ),
                              child: Icon(
                                categoryIcon(widget.listing.category),
                                color: marketplaceSageGreen,
                                size: 24,
                              ),
                            ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.listing.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 2),
                          CurrencyPriceDisplay(
                            amount: widget.listing.priceAmount,
                            sellerCountryCode: sellerCountryCode,
                            viewerCountryCode: buyerCountryCode,
                            showToggle: false,
                            compact: true,
                            primaryColor: marketplaceSageGreen,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // ─── TWO-WAY TOGGLE ($DIASPORA and Fiat) ───
              Container(
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest.withValues(
                    alpha: 0.35,
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
                padding: const EdgeInsets.all(5),
                child: Row(
                  children: [
                    _buildToggleTab(
                      theme,
                      label: r'Pay $DIASPORA',
                      icon: Image.asset(
                        'assets/icons/logo-orange-transparent-24.png',
                        width: 17,
                        height: 17,
                      ),
                      isSelected: isToken,
                      brandColor: AppTheme.tokenColor,
                      onTap: () => setState(() => _selectedAssetType = 'token'),
                    ),
                    const SizedBox(width: 6),
                    _buildToggleTab(
                      theme,
                      label: 'Pay $currencyCode',
                      icon: Icon(
                        LucideIcons.banknote,
                        size: 17,
                        color: isFiat
                            ? AppTheme.fiatColor
                            : AppTheme.fiatColor.withValues(alpha: 0.6),
                      ),
                      isSelected: isFiat,
                      brandColor: AppTheme.fiatColor,
                      onTap: () => setState(() => _selectedAssetType = 'fiat'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // ─── SELLER RECIPIENT ROW ───
              if (isToken)
                _buildTokenRecipientRow(
                  theme,
                  sellerDisplayName,
                  sellerProfile?.walletAddress,
                  sellerProfileAsync.isLoading,
                )
              else
                _buildFiatRecipientRow(theme, sellerDisplayName, currencyCode),

              const SizedBox(height: 12),

              // ─── TOKEN CHECKOUT UI ───
              if (isToken)
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest.withValues(
                      alpha: 0.3,
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    children: [
                      IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // LEFT: Available Balance
                            Expanded(
                              flex: 2,
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    'Available',
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                      fontSize: 10,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    isLoadingBalance ? '...' : '$remaining',
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      color: isError
                                          ? theme.colorScheme.error
                                          : theme.colorScheme.onSurface,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    r'$DIASPORA',
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      fontSize: 8,
                                      color: activeColor,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            // CENTER: Token amount input
                            Expanded(
                              flex: 3,
                              child: Container(
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.surface,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: TextField(
                                  controller: _amountController,
                                  keyboardType: TextInputType.number,
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.headlineSmall
                                      ?.copyWith(
                                        fontWeight: FontWeight.bold,
                                        color: activeColor,
                                      ),
                                  decoration: InputDecoration(
                                    hintText: '0',
                                    hintStyle: TextStyle(
                                      color: theme.colorScheme.onSurfaceVariant
                                          .withValues(alpha: 0.3),
                                    ),
                                    border: InputBorder.none,
                                    contentPadding: const EdgeInsets.symmetric(
                                      vertical: 8,
                                    ),
                                    isDense: true,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            // RIGHT: Checkout / Send button
                            Expanded(
                              flex: 2,
                              child: Center(
                                child: Material(
                                  color: (isZero || isError || isLoadingBalance)
                                      ? theme.disabledColor
                                      : activeColor,
                                  shape: const CircleBorder(),
                                  child: InkWell(
                                    onTap:
                                        (isZero || isError || isLoadingBalance)
                                        ? null
                                        : () => widget.onPayToken(_inputAmount),
                                    customBorder: const CircleBorder(),
                                    child: Container(
                                      width: 48,
                                      height: 48,
                                      alignment: Alignment.center,
                                      child: const Icon(
                                        LucideIcons.arrowRight,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            LucideIcons.shieldCheck,
                            size: 12,
                            color: activeColor,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Base Smart Wallet • Gasless Zero-Fee Checkout',
                            style: theme.textTheme.labelSmall?.copyWith(
                              fontSize: 10,
                              color: activeColor,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

              // ─── FIAT CHECKOUT UI ───
              if (isFiat)
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest.withValues(
                      alpha: 0.3,
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    children: [
                      // Live Real-Time Conversion Card (above amount input)
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: activeColor.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Exchange Rate: 1 $currencyCode = ${CurrencyHelper.formatFiatAmount(exchangeRate, forceDecimals: true)} $receiverCurrencyCode',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    fontSize: 10,
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                Text(
                                  'Instant Settlement',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    fontSize: 10,
                                    color: Colors.green.shade700,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Icon(
                                  LucideIcons.repeat,
                                  size: 13,
                                  color: activeColor,
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    '$sellerFirstName gets: ≈ ${CurrencyHelper.formatFiatAmount(convertedAmount)} $receiverCurrencyCode',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                      color: activeColor,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // LEFT: Currency info
                            Expanded(
                              flex: 2,
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    'Currency',
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                      fontSize: 10,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    currencySymbol,
                                    style: theme.textTheme.bodyLarge?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      color: activeColor,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    currencyCode,
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      fontSize: 8,
                                      color: activeColor,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            // CENTER: Fiat amount input
                            Expanded(
                              flex: 3,
                              child: Container(
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.surface,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: TextField(
                                  controller: _fiatAmountController,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                        decimal: true,
                                      ),
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.headlineSmall
                                      ?.copyWith(
                                        fontWeight: FontWeight.bold,
                                        color: activeColor,
                                      ),
                                  decoration: InputDecoration(
                                    hintText: '0.00',
                                    hintStyle: TextStyle(
                                      color: theme.colorScheme.onSurfaceVariant
                                          .withValues(alpha: 0.3),
                                    ),
                                    border: InputBorder.none,
                                    contentPadding: const EdgeInsets.symmetric(
                                      vertical: 8,
                                    ),
                                    isDense: true,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            // RIGHT: Checkout / Send button
                            Expanded(
                              flex: 2,
                              child: Center(
                                child: Material(
                                  color: isFiatZero
                                      ? theme.disabledColor
                                      : activeColor,
                                  shape: const CircleBorder(),
                                  child: InkWell(
                                    onTap: isFiatZero
                                        ? null
                                        : () => widget.onPayFiat(
                                            _fiatInputAmount,
                                            currencyCode,
                                            convertedAmount,
                                            receiverCurrencyCode,
                                            exchangeRate,
                                          ),
                                    customBorder: const CircleBorder(),
                                    child: Container(
                                      width: 48,
                                      height: 48,
                                      alignment: Alignment.center,
                                      child: const Icon(
                                        LucideIcons.arrowRight,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Diaspora Zero-Fee Marketplace Checkout',
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontSize: 10,
                          color: activeColor,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildToggleTab(
    ThemeData theme, {
    required String label,
    Widget? icon,
    required bool isSelected,
    required Color brandColor,
    required VoidCallback onTap,
  }) {
    final bgColor = isSelected ? theme.colorScheme.surface : Colors.transparent;
    final shadow = isSelected
        ? [
            BoxShadow(
              color: brandColor.withValues(alpha: 0.25),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ]
        : null;
    final textColor = isSelected
        ? brandColor
        : brandColor.withValues(alpha: 0.65);
    final fontWeight = isSelected ? FontWeight.bold : FontWeight.w600;

    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(10),
              boxShadow: shadow,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[icon, const SizedBox(width: 6)],
                Flexible(
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: fontWeight,
                      fontSize: 12.5,
                      color: textColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTokenRecipientRow(
    ThemeData theme,
    String sellerDisplayName,
    String? walletAddress,
    bool isLoading,
  ) {
    final displayAddress = (walletAddress != null && walletAddress.length >= 10)
        ? '${walletAddress.substring(0, 6)}...${walletAddress.substring(walletAddress.length - 4)}'
        : (isLoading ? 'Loading...' : 'Smart Wallet linked');

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              LucideIcons.wallet,
              color: Colors.orange,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'To: $sellerDisplayName',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  displayAddress,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                    color: theme.colorScheme.onSurfaceVariant,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFiatRecipientRow(
    ThemeData theme,
    String sellerDisplayName,
    String currencyCode,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.green.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              LucideIcons.banknote,
              color: Colors.green,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'To: $sellerDisplayName',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Fiat checkout via $currencyCode',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.green.shade700,
                    fontSize: 11,
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
