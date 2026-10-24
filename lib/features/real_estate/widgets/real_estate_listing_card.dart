import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:lucide_icons/lucide_icons.dart';

import 'package:diaspora_nearby/theme/app_theme.dart';
import 'package:diaspora_nearby/features/real_estate/models/real_estate_listing.dart';
import 'package:diaspora_nearby/features/shared/widgets/currency_price_display.dart';

/// Unified listing card for real estate: plots, farms, and houses.
/// Uses the same visual language as PeerListingCard (stay card).
class RealEstateListingCard extends StatelessWidget {
  const RealEstateListingCard({
    super.key,
    required this.listing,
    required this.onTap,
    this.viewerCountryCode,
  });

  final RealEstateListing listing;
  final VoidCallback onTap;
  final String? viewerCountryCode;

  static const _radius = 15.0;

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

  String get _listingTypeLabel {
    switch (listing.listingType) {
      case 'sale':
        return 'Buy';
      case 'rent':
        return 'Rent';
      case 'lease':
        return 'Lease';
      default:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

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
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (listing.listingType != null) ...[
                            Text(
                              _listingTypeLabel,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Colors.white70,
                              ),
                            ),
                            const SizedBox(width: 5),
                          ],
                          CurrencyPriceDisplay(
                            amount: listing.price,
                            sellerCountryCode: listing.countryCode,
                            viewerCountryCode: viewerCountryCode,
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
                        ],
                      ),
                    ),
                  ),
                  // Category badge (top-left)
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
                            _categoryIcon,
                            size: 10,
                            color: Colors.white.withValues(alpha: 0.9),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            listing.categoryLabel,
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
                    right: 14,
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
                  if (listing.locationLabel.isNotEmpty ||
                      (listing.city != null && listing.city!.isNotEmpty)) ...[
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
                                  listing.locationLabel.isNotEmpty
                                      ? listing.locationLabel
                                      : listing.city,
                                  listing.country,
                                ]
                                .where((s) => s != null && s.isNotEmpty)
                                .join(', '),
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
                  // Info chips (no duplicates of title content)
                  _buildInfoChips(theme),
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
            _buildBottomBar(context, theme),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoChips(ThemeData theme) {
    final chips = <Widget>[];

    // Title already contains: listing type, location, and:
    //   house → beds/baths   |   plot/farm → size
    // So we only show info NOT in the title.

    if (listing.category == 'house') {
      // Floors
      if (listing.floors != null && listing.floors! > 1) {
        chips.add(
          _infoChip(
            theme,
            LucideIcons.layers,
            '${listing.floors} floor${listing.floors! > 1 ? 's' : ''}',
          ),
        );
      }
      // Living area
      if (listing.livingArea != null) {
        final unit = listing.livingAreaUnit ?? 'm²';
        chips.add(
          _infoChip(
            theme,
            LucideIcons.square,
            '${listing.livingArea!.toStringAsFixed(0)} $unit living',
          ),
        );
      }
      // Condition or Year built
      if (listing.propertyCondition != null) {
        chips.add(
          _infoChip(theme, LucideIcons.hammer, listing.propertyCondition!),
        );
      } else if (listing.yearBuilt != null) {
        chips.add(
          _infoChip(theme, LucideIcons.calendar, 'Built ${listing.yearBuilt}'),
        );
      }
      // Garage / Garden
      if (listing.hasGarage == true) {
        chips.add(_infoChip(theme, LucideIcons.car, 'Garage'));
      }
      if (listing.hasGarden == true) {
        chips.add(_infoChip(theme, LucideIcons.flower2, 'Garden'));
      }
      // First two amenities
      if (listing.amenities != null && listing.amenities!.isNotEmpty) {
        for (final a in listing.amenities!.take(2)) {
          chips.add(_infoChip(theme, LucideIcons.checkCircle, a));
        }
      }
    } else if (listing.category == 'farm') {
      // Title deed
      if (listing.hasTitle == true) {
        chips.add(_infoChip(theme, LucideIcons.fileCheck, 'Title Deed'));
      }
      // Soil type
      if (listing.soilType != null) {
        chips.add(
          _infoChip(theme, LucideIcons.leaf, '${listing.soilType!} soil'),
        );
      }
      // Crops
      if (listing.crops != null && listing.crops!.isNotEmpty) {
        chips.add(
          _infoChip(
            theme,
            LucideIcons.sprout,
            listing.crops!.take(2).join(', '),
          ),
        );
      }
      // Irrigation
      if (listing.hasIrrigation == true) {
        chips.add(_infoChip(theme, LucideIcons.droplets, 'Irrigated'));
      }
      // Storage
      if (listing.hasStorage == true) {
        chips.add(_infoChip(theme, LucideIcons.warehouse, 'Storage'));
      }
      // Farmable area
      if (listing.farmableArea != null) {
        chips.add(
          _infoChip(
            theme,
            LucideIcons.maximize2,
            '${listing.farmableArea!.toStringAsFixed(0)} m² farmable',
          ),
        );
      }
    } else {
      // Plot — title already has size; show other useful info
      if (listing.hasTitle == true) {
        chips.add(_infoChip(theme, LucideIcons.fileCheck, 'Title Deed'));
      }
      if (listing.zoning != null) {
        chips.add(_infoChip(theme, LucideIcons.building2, listing.zoning!));
      }
      if (listing.terrainType != null) {
        chips.add(_infoChip(theme, LucideIcons.mountain, listing.terrainType!));
      }
      // Infrastructure
      if (listing.hasWater == true) {
        chips.add(_infoChip(theme, LucideIcons.droplets, 'Water'));
      }
      if (listing.hasElectricity == true) {
        chips.add(_infoChip(theme, LucideIcons.zap, 'Electricity'));
      }
      if (listing.hasRoad == true) {
        chips.add(_infoChip(theme, LucideIcons.milestone, 'Road Access'));
      }
      if (listing.isFenced == true) {
        chips.add(_infoChip(theme, LucideIcons.lock, 'Fenced'));
      }
    }

    if (chips.isEmpty) return const SizedBox.shrink();
    return Wrap(spacing: 12, runSpacing: 6, children: chips);
  }

  Widget _buildBottomBar(BuildContext context, ThemeData theme) {
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
          // Owner avatar
          CircleAvatar(
            radius: 10,
            backgroundImage: listing.ownerPhoto.isNotEmpty
                ? NetworkImage(listing.ownerPhoto)
                : null,
            backgroundColor: AppTheme.accent.withValues(alpha: 0.1),
            child: listing.ownerPhoto.isEmpty
                ? const Icon(LucideIcons.user, size: 10, color: AppTheme.accent)
                : null,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              listing.ownerName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ),
          // Country flag + name
          if (listing.country != null && listing.country!.isNotEmpty) ...[
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
              style: TextStyle(fontSize: 10, color: theme.hintColor),
            ),
          ],
          // View & save counts
          const SizedBox(width: 8),
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
      ),
    );
  }

  Widget _buildImage(bool isDark, ThemeData theme) {
    // For plot/farm: prefer satellite aerial image as default hero
    if (listing.category != 'house') {
      final satUrl = listing.satelliteImageUrl;
      if (satUrl != null) {
        return CachedNetworkImage(
          imageUrl: satUrl,
          fit: BoxFit.cover,
          placeholder: (_, _) => _placeholder(isDark),
          errorWidget: (_, _, _) => _placeholder(isDark),
        );
      }
    }
    // For house (or plot/farm without satellite): use first user photo
    if (listing.photos.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: listing.photos.first,
        fit: BoxFit.cover,
        placeholder: (_, _) => _placeholder(isDark),
        errorWidget: (_, _, _) => _placeholder(isDark),
      );
    }
    return _placeholder(isDark);
  }

  Widget _placeholder(bool isDark) {
    return Container(
      color: isDark
          ? _categoryColor.withValues(alpha: 0.08)
          : _categoryColor.withValues(alpha: 0.05),
      child: Center(
        child: Icon(
          _categoryIcon,
          size: 40,
          color: _categoryColor.withValues(alpha: 0.3),
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

  String _countryFlag(String code) {
    final codeUnits = code.toUpperCase().codeUnits;
    return String.fromCharCodes(codeUnits.map((c) => 0x1F1E6 - 0x41 + c));
  }
}
