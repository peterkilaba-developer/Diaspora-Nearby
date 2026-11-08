import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:timeago/timeago.dart' as timeago;

import 'package:diaspora_nearby/theme/app_theme.dart';
import 'package:diaspora_nearby/features/marketplace/models/marketplace_listing.dart';

import 'package:diaspora_nearby/features/shared/widgets/currency_price_display.dart';
import 'package:diaspora_nearby/features/marketplace/screens/marketplace_screen.dart'
    show categoryIcon;

// ─── Shared helpers for marketplace listing cards ───────────────────────────
// Used by both marketplace_screen.dart and my_listings_screen.dart.

const Color marketplaceSageGreen = Color(0xFF6B8E6B);

/// Condition → dot-colour mapping.
Color conditionColor(String condition) {
  switch (condition) {
    case ItemCondition.brandNew:
      return AppTheme.success;
    case ItemCondition.likeNew:
      return AppTheme.info;
    case ItemCondition.usedGood:
      return AppTheme.warning;
    case ItemCondition.usedFair:
      return AppTheme.error;
    default:
      return Colors.grey;
  }
}

bool _hasSpecValue(dynamic v) => v != null && v.toString().trim().isNotEmpty;

/// Category-specific one-liner specs (e.g. "AWD · 3.0L · 45 000 km").
String getCategorySpecs(MarketplaceListing listing) {
  final parts = <String>[];

  if (listing.category == MarketplaceCategory.vehicles &&
      listing.vehicleDetails != null) {
    final v = listing.vehicleDetails!;
    if (_hasSpecValue(v['driveType'])) parts.add(v['driveType'].toString().trim());
    if (_hasSpecValue(v['engineLabel'])) {
      parts.add(v['engineLabel'].toString().trim());
    }
    if (_hasSpecValue(v['mileage'])) {
      parts.add('${v['mileage'].toString().trim()} km');
    }
    if (_hasSpecValue(v['transmission'])) {
      parts.add(v['transmission'].toString().trim());
    }
    if (_hasSpecValue(v['fuelType'])) parts.add(v['fuelType'].toString().trim());
  } else if (listing.category == MarketplaceCategory.motorcycles &&
      listing.motorcycleDetails != null) {
    final m = listing.motorcycleDetails!;
    if (_hasSpecValue(m['year'])) parts.add(m['year'].toString().trim());
    if (_hasSpecValue(m['engineSize'])) {
      parts.add(m['engineSize'].toString().trim());
    }
    if (_hasSpecValue(m['mileage'])) {
      parts.add('${m['mileage'].toString().trim()} km');
    }
    if (_hasSpecValue(m['type'])) parts.add(m['type'].toString().trim());
  } else if (listing.category == MarketplaceCategory.carParts &&
      listing.carPartsDetails != null) {
    final cp = listing.carPartsDetails!;
    if (_hasSpecValue(cp['partNumber'])) {
      parts.add('#${cp['partNumber'].toString().trim()}');
    }
    if (_hasSpecValue(cp['carMake'])) {
      parts.add('Fits ${cp['carMake'].toString().trim()}');
    }
    final vin = cp['vin']?.toString().trim() ?? '';
    if (vin.length >= 8) {
      parts.add('VIN …${vin.substring(vin.length - 6)}');
    }
  } else if (listing.category == MarketplaceCategory.realEstate &&
      listing.realEstateDetails != null) {
    final r = listing.realEstateDetails!;
    if (_hasSpecValue(r['bedrooms'])) {
      parts.add('${r['bedrooms'].toString().trim()} bed');
    }
    if (_hasSpecValue(r['bathrooms'])) {
      parts.add('${r['bathrooms'].toString().trim()} bath');
    }
    final sqft = r['squareFootage'] ?? r['sqft'];
    if (_hasSpecValue(sqft)) parts.add('${sqft.toString().trim()} sqft');
  } else if (listing.category == MarketplaceCategory.electronics &&
      listing.electronicsDetails != null) {
    final e = listing.electronicsDetails!;
    if (_hasSpecValue(e['brand'])) parts.add(e['brand'].toString().trim());
    if (_hasSpecValue(e['storage'])) parts.add(e['storage'].toString().trim());
  } else if (listing.listingType == ListingType.service &&
      listing.serviceDetails != null) {
    final s = listing.serviceDetails!;
    final exp = s['yearsExperience'] ?? s['experience'];
    if (_hasSpecValue(exp)) {
      final expStr = exp.toString().trim();
      final lower = expStr.toLowerCase();
      if (lower.contains('yr') || lower.contains('year')) {
        parts.add('$expStr experience');
      } else {
        parts.add('$expStr yrs experience');
      }
    }
    if (_hasSpecValue(s['serviceArea'])) {
      parts.add(s['serviceArea'].toString().trim());
    }
  } else if (listing.listingType == ListingType.job &&
      listing.jobDetails != null) {
    final j = listing.jobDetails!;
    if (_hasSpecValue(j['companyName'])) {
      parts.add(j['companyName'].toString().trim());
    }
    if (_hasSpecValue(j['employmentType'])) {
      parts.add(j['employmentType'].toString().trim());
    }
    if (_hasSpecValue(j['workMode'])) {
      parts.add(j['workMode'].toString().trim());
    }
  }

  if (listing.condition != null &&
      listing.listingType == ListingType.product &&
      listing.category != MarketplaceCategory.realEstate &&
      parts.length < 3) {
    parts.add(ItemCondition.displayName(listing.condition!));
  }

  return parts.join(' · ');
}

// ─── Widgets ────────────────────────────────────────────────────────────────

/// Placeholder shown when a listing has no photo.
class MarketplaceImagePlaceholder extends StatelessWidget {
  const MarketplaceImagePlaceholder({super.key, required this.listing});

  final MarketplaceListing listing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      color: isDark
          ? Colors.white.withValues(alpha: 0.05)
          : Colors.black.withValues(alpha: 0.03),
      child: Center(
        child: Icon(
          categoryIcon(listing.category),
          size: 32,
          color: theme.hintColor.withValues(alpha: 0.25),
        ),
      ),
    );
  }
}

/// Listing image with fallback placeholder.
class MarketplaceListingImage extends StatelessWidget {
  const MarketplaceListingImage({super.key, required this.listing});

  final MarketplaceListing listing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    if (listing.images.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: listing.images.first,
        fit: BoxFit.cover,
        placeholder: (_, _) => Container(
          color: isDark
              ? Colors.white.withValues(alpha: 0.05)
              : Colors.black.withValues(alpha: 0.04),
          child: Center(
            child: Icon(
              LucideIcons.image,
              color: theme.hintColor.withValues(alpha: 0.3),
              size: 24,
            ),
          ),
        ),
        errorWidget: (_, _, _) => MarketplaceImagePlaceholder(listing: listing),
      );
    }
    return MarketplaceImagePlaceholder(listing: listing);
  }
}

/// Seller's local-currency price row with buyer currency and $DIASPORA token.
class LocalPriceRow extends StatelessWidget {
  const LocalPriceRow({
    super.key,
    required this.listing,
    this.viewerCountryCode,
  });

  final MarketplaceListing listing;

  /// The viewer/buyer's host country code.
  final String? viewerCountryCode;

  @override
  Widget build(BuildContext context) {
    final sellerCountry = listing.sellerCountryCode;
    final salaryRange = listing.jobDetails?['salaryRange']?.toString().trim();
    final useTextPrice =
        listing.priceAmount <= 0 &&
        (listing.listingType == ListingType.job ||
            listing.listingType == ListingType.service ||
            listing.priceNegotiable);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Flexible(
          child: useTextPrice
              ? Text(
                  (salaryRange != null && salaryRange.isNotEmpty)
                      ? salaryRange
                      : 'Negotiable',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: marketplaceSageGreen,
                  ),
                )
              : CurrencyPriceDisplay(
                  amount: listing.priceAmount,
                  sellerCountryCode: sellerCountry,
                  viewerCountryCode: viewerCountryCode,
                  primaryColor: marketplaceSageGreen,
                  compact: true,
                  showToggle: false,
                ),
        ),
        if (listing.priceNegotiable &&
            (!useTextPrice ||
                (salaryRange != null && salaryRange.isNotEmpty))) ...[
          const SizedBox(width: 6),
          Icon(
            LucideIcons.tag,
            size: 12,
            color: marketplaceSageGreen.withValues(alpha: 0.7),
          ),
        ],
      ],
    );
  }
}

/// Category-specific quick specs line.
class QuickSpecs extends StatelessWidget {
  const QuickSpecs({super.key, required this.listing});

  final MarketplaceListing listing;

  @override
  Widget build(BuildContext context) {
    final specs = getCategorySpecs(listing);
    if (specs.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Text(
      specs,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 11,
        color: theme.hintColor.withValues(alpha: 0.7),
      ),
    );
  }
}

/// Card footer: location · time · condition dot · chevron.
///
/// Set [showStats] to true to render view/save counts (for "my listings").
class MarketplaceCardFooter extends StatelessWidget {
  const MarketplaceCardFooter({
    super.key,
    required this.listing,
    this.showStats = true,
  });

  final MarketplaceListing listing;
  final bool showStats;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(
          listing.scope == ListingScope.international
              ? LucideIcons.globe
              : LucideIcons.mapPin,
          size: 11,
          color: theme.hintColor.withValues(alpha: 0.5),
        ),
        const SizedBox(width: 3),
        Flexible(
          child: Text(
            listing.sellerCity ?? listing.sellerCountryCode ?? '',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 10, color: theme.hintColor),
          ),
        ),
        if (listing.createdAt != null) ...[
          Text(' · ', style: TextStyle(fontSize: 10, color: theme.hintColor)),
          Text(
            timeago.format(listing.createdAt!, locale: 'en_short'),
            style: TextStyle(fontSize: 10, color: theme.hintColor),
          ),
        ],
        if (listing.condition != null &&
            listing.listingType == ListingType.product &&
            listing.category != MarketplaceCategory.realEstate) ...[
          const SizedBox(width: 6),
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: conditionColor(listing.condition!),
              shape: BoxShape.circle,
            ),
          ),
        ],
        if (showStats) ...[
          const SizedBox(width: 6),
          Icon(
            LucideIcons.eye,
            size: 10,
            color: theme.hintColor.withValues(alpha: 0.5),
          ),
          const SizedBox(width: 2),
          Text(
            '${listing.viewCount}',
            style: TextStyle(fontSize: 9, color: theme.hintColor),
          ),
          const SizedBox(width: 5),
          Icon(
            LucideIcons.bookmark,
            size: 10,
            color: theme.hintColor.withValues(alpha: 0.5),
          ),
          const SizedBox(width: 2),
          Text(
            '${listing.savedCount}',
            style: TextStyle(fontSize: 9, color: theme.hintColor),
          ),
        ],
        const Spacer(),
        Icon(
          LucideIcons.chevronRight,
          size: 14,
          color: theme.hintColor.withValues(alpha: 0.4),
        ),
      ],
    );
  }
}
