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

/// Category-specific one-liner specs (e.g. "AWD · 3.0L · 45 000 km").
String getCategorySpecs(MarketplaceListing listing) {
  final parts = <String>[];

  if (listing.category == MarketplaceCategory.vehicles &&
      listing.vehicleDetails != null) {
    final v = listing.vehicleDetails!;
    if (v['driveType'] != null) parts.add(v['driveType'].toString());
    if (v['engineLabel'] != null) parts.add(v['engineLabel'].toString());
    if (v['mileage'] != null) parts.add('${v['mileage']} km');
    if (v['transmission'] != null) parts.add(v['transmission'].toString());
    if (v['fuelType'] != null) parts.add(v['fuelType'].toString());
  } else if (listing.category == MarketplaceCategory.carParts &&
      listing.carPartsDetails != null) {
    final cp = listing.carPartsDetails!;
    if (cp['partNumber'] != null && cp['partNumber'].toString().isNotEmpty) {
      parts.add('#${cp['partNumber']}');
    }
    if (cp['carMake'] != null) parts.add('Fits ${cp['carMake']}');
    if (cp['vin'] != null && cp['vin'].toString().length >= 8) {
      parts.add(
          'VIN …${cp['vin'].toString().substring(cp['vin'].toString().length - 6)}');
    }
  } else if (listing.category == MarketplaceCategory.realEstate &&
      listing.realEstateDetails != null) {
    final r = listing.realEstateDetails!;
    if (r['bedrooms'] != null) parts.add('${r['bedrooms']} bed');
    if (r['bathrooms'] != null) parts.add('${r['bathrooms']} bath');
    final sqft = r['squareFootage'] ?? r['sqft'];
    if (sqft != null) parts.add('$sqft sqft');
  } else if (listing.category == MarketplaceCategory.electronics &&
      listing.electronicsDetails != null) {
    final e = listing.electronicsDetails!;
    if (e['brand'] != null) parts.add(e['brand'].toString());
    if (e['storage'] != null) parts.add(e['storage'].toString());
  } else if (listing.listingType == ListingType.service &&
      listing.serviceDetails != null) {
    final s = listing.serviceDetails!;
    final exp = s['yearsExperience'] ?? s['experience'];
    if (exp != null) parts.add('$exp yrs experience');
    if (s['serviceArea'] != null) parts.add(s['serviceArea'].toString());
  } else if (listing.listingType == ListingType.job &&
      listing.jobDetails != null) {
    final j = listing.jobDetails!;
    if (j['companyName'] != null) parts.add(j['companyName'].toString());
    if (j['employmentType'] != null) parts.add(j['employmentType'].toString());
    if (j['workMode'] != null) parts.add(j['workMode'].toString());
  }

  if (listing.condition != null && parts.length < 3) {
    parts.add(ItemCondition.displayName(listing.condition!));
  }

  return parts.join(' · ');
}

// ─── Widgets ────────────────────────────────────────────────────────────────

/// Placeholder shown when a listing has no photo.
class MarketplaceImagePlaceholder extends StatelessWidget {
  const MarketplaceImagePlaceholder({
    super.key,
    required this.listing,
  });

  final MarketplaceListing listing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      color: isDark
          ? Colors.white.withOpacity(0.05)
          : Colors.black.withOpacity(0.03),
      child: Center(
        child: Icon(
          categoryIcon(listing.category),
          size: 32,
          color: theme.hintColor.withOpacity(0.25),
        ),
      ),
    );
  }
}

/// Listing image with fallback placeholder.
class MarketplaceListingImage extends StatelessWidget {
  const MarketplaceListingImage({
    super.key,
    required this.listing,
  });

  final MarketplaceListing listing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    if (listing.images.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: listing.images.first,
        fit: BoxFit.cover,
        placeholder: (_, __) => Container(
          color: isDark
              ? Colors.white.withOpacity(0.05)
              : Colors.black.withOpacity(0.04),
          child: Center(
              child: Icon(LucideIcons.image,
                  color: theme.hintColor.withOpacity(0.3), size: 24)),
        ),
        errorWidget: (_, __, ___) =>
            MarketplaceImagePlaceholder(listing: listing),
      );
    }
    return MarketplaceImagePlaceholder(listing: listing);
  }
}



/// Seller's local-currency price row with optional viewer currency toggle.
class LocalPriceRow extends StatelessWidget {
  const LocalPriceRow({
    super.key,
    required this.listing,
    this.viewerCountryCode,
  });

  final MarketplaceListing listing;

  /// The viewer/buyer's host country code. When provided and different from
  /// the seller's currency, a swap icon appears to toggle the converted price.
  final String? viewerCountryCode;

  @override
  Widget build(BuildContext context) {
    final sellerCountry = listing.sellerCountryCode;
    return Row(
      children: [
        CurrencyPriceDisplay(
          amount: listing.priceAmount,
          sellerCountryCode: sellerCountry,
          viewerCountryCode: viewerCountryCode,
          primaryColor: marketplaceSageGreen,
          compact: true,
        ),
        if (listing.priceNegotiable) ...[
          const SizedBox(width: 6),
          Icon(LucideIcons.tag,
              size: 12, color: marketplaceSageGreen.withOpacity(0.7)),
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
        color: theme.hintColor.withOpacity(0.7),
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
          color: theme.hintColor.withOpacity(0.5),
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
          Text(' · ',
              style: TextStyle(fontSize: 10, color: theme.hintColor)),
          Text(
            timeago.format(listing.createdAt!, locale: 'en_short'),
            style: TextStyle(fontSize: 10, color: theme.hintColor),
          ),
        ],
        if (listing.condition != null) ...[
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
          Icon(LucideIcons.eye,
              size: 10, color: theme.hintColor.withOpacity(0.5)),
          const SizedBox(width: 2),
          Text('${listing.viewCount}',
              style: TextStyle(fontSize: 9, color: theme.hintColor)),
          const SizedBox(width: 5),
          Icon(LucideIcons.bookmark,
              size: 10, color: theme.hintColor.withOpacity(0.5)),
          const SizedBox(width: 2),
          Text('${listing.savedCount}',
              style: TextStyle(fontSize: 9, color: theme.hintColor)),
        ],
        const Spacer(),
        Icon(LucideIcons.chevronRight,
            size: 14, color: theme.hintColor.withOpacity(0.4)),
      ],
    );
  }
}
