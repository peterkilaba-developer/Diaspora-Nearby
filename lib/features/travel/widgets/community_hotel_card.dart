import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:lucide_icons/lucide_icons.dart';

import 'package:diaspora_nearby/theme/app_theme.dart';
import 'package:diaspora_nearby/features/travel/models/peer_listing.dart';
import 'package:diaspora_nearby/features/marketplace/utils/currency_helper.dart';

/// A premium, prominent card for community-listed hotels.
///
/// Layout mirrors the partner hotel card but is richer:
/// tall hero photo with gradient overlay, community badge (top-left),
/// price badge (top-right — same location as partner), hotel name overlay,
/// then a rich info area with star rating, room specs, description, and owner.
///
/// Edge-to-edge layout (no horizontal margin) matches partner hotel cards.
class CommunityHotelCard extends StatelessWidget {
  const CommunityHotelCard({
    super.key,
    required this.listing,
    required this.onTap,
  });

  final PeerListing listing;
  final VoidCallback onTap;

  static const _radius = 15.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final location = listing.locationLabel.isNotEmpty
        ? listing.locationLabel
        : listing.city ?? '';
    final priceText = CurrencyHelper.formatLocalPrice(
      listing.pricePerUnit,
      listing.countryCode,
    );

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(_radius),
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.elevationColor(context, 1),
          borderRadius: BorderRadius.circular(_radius),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Hero Photo with overlays ──
            SizedBox(
              height: 170,
              width: double.infinity,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Photo
                  if (listing.photos.isNotEmpty)
                    CachedNetworkImage(
                      imageUrl: listing.photos.first,
                      fit: BoxFit.cover,
                      placeholder: (_, _) => _photoPlaceholder(isDark),
                      errorWidget: (_, _, _) => _photoPlaceholder(isDark),
                    )
                  else
                    _photoPlaceholder(isDark),

                  // Bottom gradient
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    height: 90,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.70),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // Community badge (top-left)
                  Positioned(
                    top: 10,
                    left: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.accent,
                        borderRadius: BorderRadius.circular(7),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.25),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            LucideIcons.users,
                            size: 10,
                            color: Colors.white,
                          ),
                          SizedBox(width: 3),
                          Text(
                            'COMMUNITY',
                            style: TextStyle(
                              fontSize: 8,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Price badge (top-right — matches partner hotel)
                  Positioned(
                    top: 10,
                    right: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.accent,
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.25),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            priceText,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          Text(
                            '/night',
                            style: TextStyle(
                              fontSize: 9,
                              color: Colors.white.withValues(alpha: 0.8),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Hotel name + category overlay
                  Positioned(
                    bottom: 10,
                    left: 12,
                    right: 80,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          listing.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            shadows: [
                              Shadow(blurRadius: 4, color: Colors.black54),
                            ],
                          ),
                        ),
                        if (listing.hotelCategory != null &&
                            listing.hotelCategory!.isNotEmpty)
                          Text(
                            listing.hotelCategory!,
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.white.withValues(alpha: 0.8),
                              shadows: const [
                                Shadow(blurRadius: 4, color: Colors.black54),
                              ],
                            ),
                          ),
                      ],
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
                  // ── Row: Star rating + room specs ──
                  Row(
                    children: [
                      if (listing.starRating != null &&
                          listing.starRating! > 0) ...[
                        ...List.generate(
                          listing.starRating!,
                          (_) => const Icon(
                            LucideIcons.star,
                            size: 12,
                            color: Colors.amber,
                          ),
                        ),
                        const SizedBox(width: 12),
                      ],
                      if (listing.beds != null)
                        _infoChip(
                          theme,
                          LucideIcons.bedDouble,
                          '${listing.beds} room${listing.beds! > 1 ? 's' : ''}',
                        ),
                      if (listing.beds != null && listing.maxGuests != null)
                        const SizedBox(width: 12),
                      if (listing.maxGuests != null)
                        _infoChip(
                          theme,
                          LucideIcons.users,
                          '${listing.maxGuests} guest${listing.maxGuests! > 1 ? 's' : ''}',
                        ),
                      const Spacer(),
                      if (listing.checkInTime != null)
                        _infoChip(
                          theme,
                          LucideIcons.clock,
                          listing.checkInTime!,
                        ),
                    ],
                  ),

                  // ── Location row ──
                  if (location.isNotEmpty) ...[
                    const SizedBox(height: 8),
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
                            [
                              location,
                              if (listing.country != null) listing.country!,
                            ].join(', '),
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
                  ],

                  // ── Amenity preview chips ──
                  if (listing.amenities != null &&
                      listing.amenities!.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        ...listing.amenities!.take(3).map((a) {
                          return Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.elevationColor(context, 2),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  _amenityIcon(a),
                                  size: 10,
                                  color: AppTheme.accent.withValues(alpha: 0.6),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  a,
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: theme.colorScheme.onSurface
                                        .withValues(alpha: 0.55),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                        if (listing.amenities!.length > 3)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.elevationColor(context, 2),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '+${listing.amenities!.length - 3} more',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w500,
                                color: AppTheme.accent.withValues(alpha: 0.7),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],

                  // ── Description ──
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

            // ── Bottom bar: owner + location ──
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: AppTheme.elevationColor(context, 2),
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(_radius),
                  bottomRight: Radius.circular(_radius),
                ),
              ),
              child: Row(
                children: [
                  // Owner avatar
                  CircleAvatar(
                    radius: 10,
                    backgroundImage: listing.ownerPhoto.isNotEmpty
                        ? NetworkImage(listing.ownerPhoto)
                        : null,
                    backgroundColor: AppTheme.accent.withValues(alpha: 0.1),
                    child: listing.ownerPhoto.isEmpty
                        ? const Icon(
                            LucideIcons.user,
                            size: 9,
                            color: AppTheme.accent,
                          )
                        : null,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    'Owned by ${listing.ownerName.split(' ').first}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                  const Spacer(),
                  // Check-in / Check-out times
                  if (listing.checkInTime != null &&
                      listing.checkOutTime != null) ...[
                    Icon(
                      LucideIcons.logIn,
                      size: 10,
                      color: theme.hintColor.withValues(alpha: 0.5),
                    ),
                    const SizedBox(width: 3),
                    Text(
                      '${listing.checkInTime!} - ${listing.checkOutTime!}',
                      style: TextStyle(fontSize: 10, color: theme.hintColor),
                    ),
                  ] else ...[
                    Icon(
                      LucideIcons.mapPin,
                      size: 10,
                      color: theme.hintColor.withValues(alpha: 0.5),
                    ),
                    const SizedBox(width: 3),
                    Flexible(
                      child: Text(
                        listing.country ??
                            (location.isNotEmpty ? location : ''),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 10, color: theme.hintColor),
                      ),
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

  Widget _photoPlaceholder(bool isDark) {
    return Container(
      color: isDark
          ? AppTheme.accent.withValues(alpha: 0.08)
          : AppTheme.accent.withValues(alpha: 0.05),
      child: Center(
        child: Icon(
          LucideIcons.hotel,
          size: 40,
          color: AppTheme.accent.withValues(alpha: 0.3),
        ),
      ),
    );
  }

  Widget _infoChip(ThemeData theme, IconData icon, String label) {
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

  IconData _amenityIcon(String amenity) {
    switch (amenity.toLowerCase()) {
      case 'wi-fi':
      case 'wifi':
        return LucideIcons.wifi;
      case 'pool':
        return LucideIcons.waves;
      case 'spa':
        return LucideIcons.sparkles;
      case 'gym':
        return LucideIcons.dumbbell;
      case 'restaurant':
        return LucideIcons.utensils;
      case 'room service':
        return LucideIcons.bellRing;
      case 'bar / lounge':
      case 'bar':
        return LucideIcons.wine;
      case 'parking':
        return LucideIcons.car;
      case 'airport shuttle':
        return LucideIcons.plane;
      case 'ac':
        return LucideIcons.thermometer;
      case 'laundry':
        return LucideIcons.shirt;
      default:
        return LucideIcons.checkCircle;
    }
  }
}
