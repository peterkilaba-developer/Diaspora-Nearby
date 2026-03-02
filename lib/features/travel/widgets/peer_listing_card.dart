import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:lucide_icons/lucide_icons.dart';

import 'package:diaspora_nearby/theme/app_theme.dart';
import 'package:diaspora_nearby/features/travel/models/peer_listing.dart';
import 'package:diaspora_nearby/features/shared/widgets/currency_price_display.dart';

/// Unified listing card for ALL peer-to-peer travel listings:
///   - Stays  (type == 'stay')
///   - Cars   (type == 'car')
///   - Hotels (type == 'hotel')
///
/// Uses a vertical hero-photo card layout with contextual info chips
/// and a bottom bar that adapts to the listing type.
class PeerListingCard extends StatelessWidget {
  const PeerListingCard({
    super.key,
    required this.listing,
    required this.onTap,
    this.viewerCountryCode,
    this.placeholderIcon, // ignored — auto-determined from listing type
  });

  final PeerListing listing;
  final VoidCallback onTap;

  /// The viewer/buyer's host country code for currency conversion.
  final String? viewerCountryCode;

  /// Kept for backward compatibility but ignored; icon is auto-determined.
  final IconData? placeholderIcon;

  static const _radius = 15.0;

  bool get _isHotel => listing.type == 'hotel';
  bool get _isCar => listing.type == 'car';
  bool get _isApiHotel => _isHotel && listing.ownerId == 'amadeus';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final location = listing.locationLabel.isNotEmpty
        ? listing.locationLabel
        : listing.city ?? '';

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.elevationColor(context, 1),
          borderRadius: BorderRadius.circular(_radius),
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
                  _buildImage(isDark, theme),
                  // Gradient overlay
                  Positioned(
                    bottom: 0, left: 0, right: 0, height: 80,
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
                    top: 10, right: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
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
                      child: CurrencyPriceDisplay(
                        amount: listing.pricePerUnit,
                        sellerCountryCode: listing.countryCode,
                        viewerCountryCode: viewerCountryCode,
                        priceSuffix: _isCar ? '/day' : '/night',
                        compact: true,
                        primaryStyle: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                  // Type badge (top-left) for community listings
                  Positioned(
                    top: 10, left: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _isHotel
                                ? LucideIcons.hotel
                                : _isCar
                                    ? LucideIcons.car
                                    : LucideIcons.home,
                            size: 10,
                            color: Colors.white.withValues(alpha: 0.9),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _isApiHotel
                                ? 'Partner'
                                : _isHotel
                                    ? 'Community'
                                    : _isCar
                                        ? 'Car Rental'
                                        : listing.propertyType ?? 'Stay',
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
                    bottom: 10, left: 12, right: 80,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          listing.title,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            shadows: [Shadow(blurRadius: 4,
                                color: Colors.black54)],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // ── Info area ──
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Location row (without country for cars — country shown in bottom bar)
                  if (location.isNotEmpty) ...[
                    Row(
                      children: [
                        Icon(LucideIcons.mapPin,
                            size: 12,
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.4)),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            _isCar
                                ? location
                                : [location, listing.country]
                                    .where((s) =>
                                        s != null && s.isNotEmpty)
                                    .join(', '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: theme.colorScheme.onSurface
                                  .withValues(alpha: 0.5),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                  ],
                  // Contextual info chips row
                  _buildInfoChips(theme),
                  // Amenity / feature preview chips
                  _buildFeatureChips(context, theme),
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
                        color: theme.colorScheme.onSurface
                            .withValues(alpha: 0.55),
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // ── Bottom Bar ──
            _buildBottomBar(context, theme, location),
          ],
        ),
      ),
    );
  }

  // ─── Contextual info chips ──────────────────────────────────────────

  Widget _buildInfoChips(ThemeData theme) {
    if (_isHotel) {
      final chips = <Widget>[];
      if (listing.hotelCategory != null) {
        chips.add(_infoChip(theme, LucideIcons.building2, listing.hotelCategory!));
      }
      if (listing.starRating != null && listing.starRating! > 0) {
        chips.add(_infoChip(theme, LucideIcons.star, '${listing.starRating}★'));
      }
      if (listing.beds != null) {
        chips.add(_infoChip(theme, LucideIcons.bedDouble,
            '${listing.beds} room${listing.beds! > 1 ? 's' : ''}'));
      }
      if (listing.maxGuests != null) {
        chips.add(_infoChip(theme, LucideIcons.users, '${listing.maxGuests}'));
      }
      if (listing.checkInTime != null && listing.checkOutTime != null) {
        chips.add(_infoChip(theme, LucideIcons.clock,
            _formatCheckInOut(listing.checkInTime!, listing.checkOutTime!)));
      }
      return Wrap(spacing: 12, runSpacing: 6, children: chips);
    } else if (_isCar) {
      // Show key car specs that travelers care about
      final chips = <Widget>[];
      if (listing.year != null) {
        chips.add(_infoChip(theme, LucideIcons.calendar, '${listing.year}'));
      }
      if (listing.transmission != null) {
        chips.add(_infoChip(theme, LucideIcons.settings, listing.transmission!));
      }
      if (listing.fuelType != null) {
        chips.add(_infoChip(theme, LucideIcons.fuel, listing.fuelType!));
      }
      if (listing.drivetrain != null) {
        chips.add(_infoChip(theme, LucideIcons.gauge, listing.drivetrain!));
      }
      if (listing.seats != null) {
        chips.add(_infoChip(theme, LucideIcons.armchair, '${listing.seats} seats'));
      }
      return Wrap(
        spacing: 12,
        runSpacing: 6,
        children: chips,
      );
    } else {
      // Stay
      return Row(
        children: [
          if (listing.propertyType != null)
            _infoChip(theme, LucideIcons.home, listing.propertyType!),
          if (listing.beds != null) ...[
            const SizedBox(width: 12),
            _infoChip(theme, LucideIcons.bedDouble,
                '${listing.beds} bed${listing.beds! > 1 ? 's' : ''}'),
          ],
          if (listing.baths != null) ...[
            const SizedBox(width: 12),
            _infoChip(theme, LucideIcons.bath,
                '${listing.baths} bath${listing.baths! > 1 ? 's' : ''}'),
          ],
          if (listing.maxGuests != null) ...[
            const SizedBox(width: 12),
            _infoChip(theme, LucideIcons.users, '${listing.maxGuests}'),
          ],
        ],
      );
    }
  }

  // ─── Feature / Amenity preview chips ────────────────────────────────

  Widget _buildFeatureChips(BuildContext context, ThemeData theme) {
    final items = listing.amenities ?? listing.features;
    if (items == null || items.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(
        spacing: 6,
        runSpacing: 4,
        children: [
          ...items.take(3).map((a) => Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppTheme.elevationColor(context, 2),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(_amenityIcon(a),
                        size: 10,
                        color: AppTheme.accent.withValues(alpha: 0.6)),
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
              )),
          if (items.length > 3)
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppTheme.elevationColor(context, 2),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '+${items.length - 3} more',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                  color: AppTheme.accent.withValues(alpha: 0.7),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ─── Bottom bar ─────────────────────────────────────────────────────

  Widget _buildBottomBar(
      BuildContext context, ThemeData theme, String location) {
    return Container(
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
          // Owner avatar / hotel icon
          if (_isApiHotel) ...[
            CircleAvatar(
              radius: 10,
              backgroundColor: AppTheme.accent.withValues(alpha: 0.1),
              child: const Icon(LucideIcons.building2,
                  size: 10, color: AppTheme.accent),
            ),
          ] else ...[
            CircleAvatar(
              radius: 10,
              backgroundImage: listing.ownerPhoto.isNotEmpty
                  ? NetworkImage(listing.ownerPhoto)
                  : null,
              backgroundColor: AppTheme.accent.withValues(alpha: 0.1),
              child: listing.ownerPhoto.isEmpty
                  ? const Icon(LucideIcons.user,
                      size: 10, color: AppTheme.accent)
                  : null,
            ),
          ],
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              _isApiHotel
                  ? listing.hotelCategory ?? 'Partner Hotel'
                  : listing.ownerName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ),
          // Country flag + name (right-aligned) — same for all types
          if (listing.country != null &&
              listing.country!.isNotEmpty) ...[
            if (listing.countryCode != null &&
                listing.countryCode!.length == 2) ...[
              Text(
                _countryFlag(listing.countryCode!),
                style: const TextStyle(fontSize: 12),
              ),
              const SizedBox(width: 4),
            ],
            Text(
              listing.country!,
              style: TextStyle(
                  fontSize: 10, color: theme.hintColor),
            ),
          ],
          // View & save counts (for non-API listings)
          if (!_isApiHotel) ...[
            const SizedBox(width: 8),
            Icon(LucideIcons.eye,
                size: 10, color: theme.hintColor.withValues(alpha: 0.5)),
            const SizedBox(width: 2),
            Text('${listing.viewCount}',
                style: TextStyle(fontSize: 9, color: theme.hintColor)),
            const SizedBox(width: 5),
            Icon(LucideIcons.bookmark,
                size: 10, color: theme.hintColor.withValues(alpha: 0.5)),
            const SizedBox(width: 2),
            Text('${listing.savedCount}',
                style: TextStyle(fontSize: 9, color: theme.hintColor)),
          ],
        ],
      ),
    );
  }

  // ─── Image builder ──────────────────────────────────────────────────

  Widget _buildImage(bool isDark, ThemeData theme) {
    if (listing.photos.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: listing.photos.first,
        fit: BoxFit.cover,
        placeholder: (_, _) => _placeholder(isDark, theme),
        errorWidget: (_, _, ___) => _placeholder(isDark, theme),
      );
    }
    return _placeholder(isDark, theme);
  }

  Widget _placeholder(bool isDark, ThemeData theme) {
    return Container(
      color: isDark
          ? AppTheme.accent.withValues(alpha: 0.08)
          : AppTheme.accent.withValues(alpha: 0.05),
      child: Center(
        child: Icon(
          _isHotel
              ? LucideIcons.hotel
              : _isCar
                  ? LucideIcons.car
                  : LucideIcons.home,
          size: 40,
          color: AppTheme.accent.withValues(alpha: 0.3),
        ),
      ),
    );
  }

  // ─── Helpers ────────────────────────────────────────────────────────

  Widget _infoChip(ThemeData theme, IconData icon, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon,
            size: 14,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.45)),
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

  String _countryFlag(String code) {
    final codeUnits = code.toUpperCase().codeUnits;
    return String.fromCharCodes(
      codeUnits.map((c) => 0x1F1E6 - 0x41 + c),
    );
  }

  /// Format check-in/check-out for display.
  /// Handles both time format ("15:00") and date format ("2026-03-01").
  String _formatCheckInOut(String checkIn, String checkOut) {
    // If it's a time like "15:00", show as-is
    if (!checkIn.contains('-')) {
      return '$checkIn - $checkOut';
    }
    // If it's a date like "2026-03-01", format as "Mar 1 - Mar 3"
    try {
      const months = [
        '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
      ];
      final inDate = DateTime.parse(checkIn);
      final outDate = DateTime.parse(checkOut);
      return '${months[inDate.month]} ${inDate.day} - ${months[outDate.month]} ${outDate.day}';
    } catch (_) {
      return '$checkIn - $checkOut';
    }
  }
}
