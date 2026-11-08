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
import 'package:diaspora_nearby/features/marketplace/widgets/marketplace_card_helpers.dart';
import 'package:diaspora_nearby/features/profile/repository/profile_repository.dart';

class SavedListingsScreen extends ConsumerWidget {
  final String? listingType;

  const SavedListingsScreen({super.key, this.listingType});

  String get _effectiveType =>
      (listingType == null || listingType == 'all') ? 'product' : listingType!;

  String get _screenTitle {
    switch (_effectiveType) {
      case 'service':
        return 'Saved Services';
      case 'job':
        return 'Saved Jobs';
      default:
        return 'Saved Products';
    }
  }

  String get _emptyTitle {
    switch (_effectiveType) {
      case 'service':
        return 'No saved services';
      case 'job':
        return 'No saved jobs';
      default:
        return 'No saved products';
    }
  }

  String get _emptySubtitle {
    switch (_effectiveType) {
      case 'service':
        return 'Browse services and save them for later';
      case 'job':
        return 'Browse jobs and save them for later';
      default:
        return 'Browse products and save them for later';
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
    final cachedSaved = repo.getCachedSavedListings(
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
      ),
      body: StreamBuilder<List<MarketplaceListing>>(
        initialData: cachedSaved.isNotEmpty ? cachedSaved : null,
        stream: repo.getSavedListings(userId, listingType: _effectiveType),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const Center(
              child: CircularProgressIndicator(color: AppTheme.accent),
            );
          }

          var listings = snapshot.data ?? [];
          listings = listings
              .where((l) => l.listingType == _effectiveType)
              .toList();

          if (listings.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    LucideIcons.bookmarkMinus,
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
                ],
              ),
            );
          }

          return GridView.builder(
            padding: const EdgeInsets.all(AppTheme.pageHorizontalPadding),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 0.68,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
            ),
            itemCount: listings.length,
            itemBuilder: (context, index) {
              return _buildSavedCard(
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

  Widget _buildSavedCard(
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
        decoration: BoxDecoration(
          color: isDark
              ? Colors.white.withValues(alpha: 0.03)
              : Colors.black.withValues(alpha: 0.02),
          borderRadius: BorderRadius.circular(AppTheme.standardBorderRadius),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(AppTheme.standardBorderRadius),
              ),
              child: AspectRatio(
                aspectRatio: 1.2,
                child: listing.images.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: listing.images.first,
                        fit: BoxFit.cover,
                      )
                    : Container(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.05)
                            : Colors.black.withValues(alpha: 0.04),
                        child: Center(
                          child: Icon(
                            categoryIcon(listing.category),
                            size: 28,
                            color: theme.hintColor.withValues(alpha: 0.25),
                          ),
                        ),
                      ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        LocalPriceRow(
                          listing: listing,
                          viewerCountryCode: ref
                              .watch(userProfileProvider)
                              .value
                              ?.hostCountryCode,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          listing.title,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                    Text(
                      listing.sellerName,
                      style: TextStyle(fontSize: 10, color: theme.hintColor),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
