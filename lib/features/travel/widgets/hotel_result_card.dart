import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:diaspora_nearby/theme/app_theme.dart';
import 'package:diaspora_nearby/features/travel/services/amadeus_service.dart';

/// Curated hotel/travel photos from Unsplash (stable direct URLs).
/// Each hotel is deterministically assigned one based on its ID hash.
const _hotelPhotoUrls = [
  // Luxury hotel pool at sunset
  'https://images.unsplash.com/photo-1566073771259-6a8506099945?w=600&h=300&fit=crop&q=80',
  // Modern hotel lobby
  'https://images.unsplash.com/photo-1551882547-ff40c63fe5fa?w=600&h=300&fit=crop&q=80',
  // Resort with palm trees
  'https://images.unsplash.com/photo-1571896349842-33c89424de2d?w=600&h=300&fit=crop&q=80',
  // Hotel room with city view
  'https://images.unsplash.com/photo-1520250497591-112f2f40a3f4?w=600&h=300&fit=crop&q=80',
  // Tropical resort beachfront
  'https://images.unsplash.com/photo-1542314831-068cd1dbfeeb?w=600&h=300&fit=crop&q=80',
  // Boutique hotel exterior
  'https://images.unsplash.com/photo-1445019980597-93fa8acb246c?w=600&h=300&fit=crop&q=80',
  // Modern hotel hallway
  'https://images.unsplash.com/photo-1578683010236-d716f9a3f461?w=600&h=300&fit=crop&q=80',
  // Elegant hotel bedroom
  'https://images.unsplash.com/photo-1582719478250-c89cae4dc85b?w=600&h=300&fit=crop&q=80',
  // Infinity pool overlooking ocean
  'https://images.unsplash.com/photo-1596394516093-501ba68a0ba6?w=600&h=300&fit=crop&q=80',
  // Grand hotel entrance
  'https://images.unsplash.com/photo-1564501049412-61c2a3083791?w=600&h=300&fit=crop&q=80',
  // Mountain lodge
  'https://images.unsplash.com/photo-1618773928121-c32f218949c2?w=600&h=300&fit=crop&q=80',
  // Seaside resort
  'https://images.unsplash.com/photo-1610641818989-c2051b5e2cfd?w=600&h=300&fit=crop&q=80',
];

/// Get a deterministic photo URL for a hotel based on its ID.
String _getHotelPhotoUrl(String hotelId) {
  final index = hotelId.hashCode.abs() % _hotelPhotoUrls.length;
  return _hotelPhotoUrls[index];
}

/// A rich hotel result card with hero photo, hotel name, price, room info, and board type.
class HotelResultCard extends StatelessWidget {
  final HotelOfferResult hotel;
  final VoidCallback? onTap;

  const HotelResultCard({
    super.key,
    required this.hotel,
    this.onTap,
  });

  static const _radius = 15.0;

  /// Map common chain codes to readable names.
  static const _chainNames = {
    'HY': 'Hyatt', 'HI': 'Holiday Inn', 'BW': 'Best Western',
    'MC': 'Marriott', 'HH': 'Hilton', 'SI': 'Sheraton',
    'WI': 'Westin', 'RT': 'Ritz-Carlton', 'IC': 'InterContinental',
    'AK': 'Accor', 'YX': 'IHG', 'WH': 'Wyndham',
    'CW': 'Crowne Plaza', 'EM': 'Embassy Suites',
    'HL': 'Hilton Garden Inn', 'FN': 'Fairfield Inn',
    'CI': 'Comfort Inn', 'RA': 'Ramada', 'DI': 'Days Inn',
    'SB': 'Novotel', 'PH': 'Park Hyatt',
  };

  String _getChainName(String? code) =>
      code != null ? (_chainNames[code] ?? '') : '';

  /// Format hotel name to title case.
  String _formatHotelName(String name) {
    if (name.isEmpty) return name;
    // Amadeus often returns ALL CAPS names
    if (name == name.toUpperCase() && name.length > 3) {
      return name.split(' ').map((word) {
        if (word.isEmpty) return word;
        if (word.length <= 2) return word; // Keep short words (II, IV, etc.)
        return '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}';
      }).join(' ');
    }
    return name;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (hotel.offers.isEmpty) return const SizedBox.shrink();

    final cheapest = hotel.offers.reduce(
        (a, b) => a.totalPrice <= b.totalPrice ? a : b);
    final chainName = _getChainName(hotel.chainCode);
    final nights = cheapest.nights;
    final photoUrl = _getHotelPhotoUrl(hotel.hotelId);

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
            // ── Hero Photo ──
            SizedBox(
              height: 140,
              width: double.infinity,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Photo
                  Image.network(
                    photoUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      color: AppTheme.accent.withOpacity(0.15),
                      child: const Center(
                        child: Icon(LucideIcons.building2, size: 40, color: AppTheme.accent),
                      ),
                    ),
                    loadingBuilder: (context, child, progress) {
                      if (progress == null) return child;
                      return Container(
                        color: AppTheme.elevationColor(context, 2),
                        child: Center(
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            value: progress.expectedTotalBytes != null
                                ? progress.cumulativeBytesLoaded / progress.expectedTotalBytes!
                                : null,
                            color: AppTheme.accent.withOpacity(0.5),
                          ),
                        ),
                      );
                    },
                  ),
                  // Gradient overlay for text readability
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
                            Colors.black.withOpacity(0.65),
                          ],
                        ),
                      ),
                    ),
                  ),
                  // Price badge
                  Positioned(
                    top: 10,
                    right: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: AppTheme.accent,
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.25),
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
                            '\$${hotel.cheapestPrice.toStringAsFixed(0)}',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          Text(
                            nights > 1 ? '$nights nights' : '/night',
                            style: TextStyle(
                              fontSize: 9,
                              color: Colors.white.withOpacity(0.8),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Hotel name overlay on photo
                  Positioned(
                    bottom: 10,
                    left: 12,
                    right: 80,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _formatHotelName(hotel.hotelName),
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            shadows: [Shadow(blurRadius: 4, color: Colors.black54)],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (chainName.isNotEmpty)
                          Text(
                            chainName,
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.white.withOpacity(0.8),
                              shadows: const [Shadow(blurRadius: 4, color: Colors.black54)],
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // ── Room Info ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  // Bed info
                  _infoChip(
                    context,
                    LucideIcons.bedDouble,
                    cheapest.bedInfo,
                  ),
                  const SizedBox(width: 12),
                  // Board type
                  _infoChip(
                    context,
                    cheapest.boardType == 'BREAKFAST' ||
                        cheapest.boardType == 'HALF_BOARD' ||
                        cheapest.boardType == 'FULL_BOARD' ||
                        cheapest.boardType == 'ALL_INCLUSIVE'
                      ? LucideIcons.coffee
                      : LucideIcons.doorOpen,
                    cheapest.boardTypeDisplay,
                  ),
                  const Spacer(),
                  // Per night price (when multiple nights)
                  if (nights > 1)
                    Text(
                      '\$${cheapest.pricePerNight.toStringAsFixed(0)}/night',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: theme.colorScheme.onSurface.withOpacity(0.6),
                      ),
                    ),
                ],
              ),
            ),

            // ── Bottom Bar ──
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
                  // Cancellation info
                  Icon(
                    cheapest.cancellationDeadline != null
                        ? LucideIcons.checkCircle
                        : LucideIcons.alertCircle,
                    size: 14,
                    color: cheapest.cancellationDeadline != null
                        ? Colors.green.shade600
                        : theme.colorScheme.onSurface.withOpacity(0.4),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    cheapest.cancellationDeadline != null
                        ? 'Free cancellation'
                        : 'Non-refundable',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: cheapest.cancellationDeadline != null
                          ? FontWeight.w600
                          : FontWeight.normal,
                      color: cheapest.cancellationDeadline != null
                          ? Colors.green.shade600
                          : theme.colorScheme.onSurface.withOpacity(0.5),
                    ),
                  ),
                  const Spacer(),
                  // Payment type
                  if (cheapest.paymentType != null)
                    Text(
                      cheapest.paymentType == 'GUARANTEE'
                          ? 'Pay at hotel  \$${cheapest.totalPrice.toStringAsFixed(0)}'
                          : 'Pay now  \$${cheapest.totalPrice.toStringAsFixed(0)}',
                      style: TextStyle(
                        fontSize: 11,
                        color: theme.colorScheme.onSurface.withOpacity(0.4),
                      ),
                    ),
                  const SizedBox(width: 8),
                  Text(
                    hotel.currency,
                    style: TextStyle(
                      fontSize: 11,
                      color: theme.colorScheme.onSurface.withOpacity(0.4),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoChip(BuildContext context, IconData icon, String label) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: theme.colorScheme.onSurface.withOpacity(0.45)),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: theme.colorScheme.onSurface.withOpacity(0.65),
          ),
        ),
      ],
    );
  }
}
