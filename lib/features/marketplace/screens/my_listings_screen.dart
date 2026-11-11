import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:diaspora_nearby/theme/app_theme.dart';
import 'package:diaspora_nearby/features/auth/repository/auth_repository.dart';
import 'package:diaspora_nearby/features/marketplace/models/marketplace_listing.dart';
import 'package:diaspora_nearby/features/marketplace/repository/marketplace_repository.dart';
import 'package:diaspora_nearby/features/marketplace/widgets/marketplace_card_helpers.dart';
import 'package:diaspora_nearby/features/profile/repository/profile_repository.dart';

class MyListingsScreen extends ConsumerWidget {
  final String? listingType;

  const MyListingsScreen({super.key, this.listingType});

  String get _effectiveType =>
      (listingType == null || listingType == 'all') ? 'product' : listingType!;

  String get _screenTitle {
    switch (_effectiveType) {
      case 'service':
        return 'My Services';
      case 'job':
        return 'My Jobs';
      default:
        return 'My Products';
    }
  }

  String get _emptyTitle {
    switch (_effectiveType) {
      case 'service':
        return 'No services yet';
      case 'job':
        return 'No jobs yet';
      default:
        return 'No products yet';
    }
  }

  String get _emptySubtitle {
    switch (_effectiveType) {
      case 'service':
        return 'Post your first service to start finding clients';
      case 'job':
        return 'Post your first job to start hiring';
      default:
        return 'Create your first product to start selling';
    }
  }

  String get _createButtonLabel {
    switch (_effectiveType) {
      case 'service':
        return 'Offer Services';
      case 'job':
        return 'Post Jobs';
      default:
        return 'Sell Products';
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final userId = ref.watch(authRepositoryProvider).currentUser?.uid;

    if (userId == null) {
      return const Scaffold(body: Center(child: Text('Please sign in')));
    }

    final repo = ref.watch(marketplaceRepositoryProvider);
    final cachedListings = repo.getCachedUserListings(
      userId,
      listingType: _effectiveType,
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _screenTitle,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        elevation: 0,
        backgroundColor: Colors.transparent,
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.plus, size: 20),
            onPressed: () => context.push(
              '/marketplace/create?type=$_effectiveType',
              extra: _effectiveType,
            ),
          ),
        ],
      ),
      body: StreamBuilder<List<MarketplaceListing>>(
        initialData: cachedListings.isNotEmpty ? cachedListings : null,
        stream: repo.getMyListings(userId, listingType: _effectiveType),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const Center(
              child: CircularProgressIndicator(color: AppTheme.accent),
            );
          }

          var listings = (snapshot.data ?? [])
              .map((l) => repo.getCachedListing(l.id) ?? l)
              .where((l) => l.listingType == _effectiveType)
              .toList();

          if (listings.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    _effectiveType == 'job'
                        ? LucideIcons.briefcase
                        : _effectiveType == 'service'
                        ? LucideIcons.wrench
                        : LucideIcons.packagePlus,
                    size: 48,
                    color: theme.hintColor.withValues(alpha: 0.3),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _emptyTitle,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: theme.hintColor,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _emptySubtitle,
                    style: TextStyle(
                      fontSize: 13,
                      color: theme.hintColor.withValues(alpha: 0.7),
                    ),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: () => context.push(
                      '/marketplace/create?type=$_effectiveType',
                      extra: _effectiveType,
                    ),
                    icon: const Icon(LucideIcons.plus, size: 16),
                    label: Text(_createButtonLabel),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.accent,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }

          return ListView.separated(
            padding: EdgeInsets.fromLTRB(
              AppTheme.pageHorizontalPadding,
              AppTheme.pageHorizontalPadding,
              AppTheme.pageHorizontalPadding,
              AppTheme.pageHorizontalPadding +
                  MediaQuery.of(context).padding.bottom,
            ),
            itemCount: listings.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              return _buildMyListingCard(
                context,
                listings[index],
                theme,
                isDark,
                ref,
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildMyListingCard(
    BuildContext context,
    MarketplaceListing listing,
    ThemeData theme,
    bool isDark,
    WidgetRef ref,
  ) {
    return GestureDetector(
      onTap: () {
        ref.read(marketplaceRepositoryProvider).cacheListing(listing);
        context.push('/marketplace/listing/${listing.id}');
      },
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withValues(alpha: 0.04) : Colors.white,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: 115,
                height: 118,
                child: MarketplaceListingImage(listing: listing),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 118),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Top row: status chip
                    Row(
                      children: [
                        Flexible(
                          child: _buildStatusChip(
                            listing.status,
                            listing.listingType,
                            isDark,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
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
                    const SizedBox(height: 4),
                    LocalPriceRow(
                      listing: listing,
                      viewerCountryCode: ref
                          .watch(userProfileProvider)
                          .value
                          ?.hostCountryCode,
                    ),
                    const SizedBox(height: 4),
                    QuickSpecs(listing: listing),
                    const SizedBox(height: 4),
                    MarketplaceCardFooter(listing: listing, showStats: true),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusChip(String status, String listingType, bool isDark) {
    Color color;
    String label;
    switch (status) {
      case ListingStatus.active:
        color = AppTheme.success;
        label = 'Active';
        break;
      case ListingStatus.sold:
        color = AppTheme.info;
        label = listingType == ListingType.job
            ? 'Filled'
            : listingType == ListingType.service
            ? 'Booked'
            : 'Sold';
        break;
      case ListingStatus.paused:
        color = AppTheme.warning;
        label = 'Paused';
        break;
      case ListingStatus.expired:
        color = AppTheme.error;
        label = 'Expired';
        break;
      default:
        color = Colors.grey;
        label = status;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}
