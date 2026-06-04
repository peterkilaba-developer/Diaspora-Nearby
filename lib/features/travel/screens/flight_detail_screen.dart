import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:diaspora_nearby/theme/app_theme.dart';
import 'package:diaspora_nearby/features/travel/services/amadeus_service.dart';
import 'package:diaspora_nearby/features/travel/screens/flight_booking_screen.dart';

/// Full-detail screen for a single flight offer.
class FlightDetailScreen extends StatefulWidget {
  final FlightOffer offer;

  const FlightDetailScreen({super.key, required this.offer});

  @override
  State<FlightDetailScreen> createState() => _FlightDetailScreenState();
}

class _FlightDetailScreenState extends State<FlightDetailScreen> {
  bool _isSaved = false;

  static const _radius = 15.0;

  static const _airlineNames = {
    'AA': 'American Airlines',
    'DL': 'Delta Air Lines',
    'UA': 'United Airlines',
    'WN': 'Southwest Airlines',
    'B6': 'JetBlue Airways',
    'AS': 'Alaska Airlines',
    'NK': 'Spirit Airlines',
    'F9': 'Frontier Airlines',
    'HA': 'Hawaiian Airlines',
    'SY': 'Sun Country',
    'BA': 'British Airways',
    'LH': 'Lufthansa',
    'AF': 'Air France',
    'KL': 'KLM',
    'EK': 'Emirates',
    'QR': 'Qatar Airways',
    'SQ': 'Singapore Airlines',
    'TK': 'Turkish Airlines',
    'ET': 'Ethiopian Airlines',
    'W3': 'Arik Air',
    'AT': 'Royal Air Maroc',
    'KQ': 'Kenya Airways',
    'SA': 'South African Airways',
    'MS': 'EgyptAir',
    'QF': 'Qantas',
    'AC': 'Air Canada',
    'LX': 'Swiss Intl',
    'AZ': 'ITA Airways',
    'IB': 'Iberia',
    'VS': 'Virgin Atlantic',
    'CX': 'Cathay Pacific',
    'JL': 'Japan Airlines',
    'NH': 'ANA',
    'OZ': 'Asiana Airlines',
    'KE': 'Korean Air',
    'SV': 'Saudi Arabian',
    'GF': 'Gulf Air',
    'WB': 'RwandAir',
    'HF': 'Air Côte d\'Ivoire',
    'P4': 'Air Peace',
  };

  String _airlineName(String code) => _airlineNames[code] ?? code;
  String _airlineLogoUrl(String code) =>
      'https://pics.avs.io/100/100/$code.png';

  String _formatTime(String iso) {
    try {
      final dt = DateTime.parse(iso);
      final h = dt.hour;
      final m = dt.minute.toString().padLeft(2, '0');
      final p = h >= 12 ? 'PM' : 'AM';
      final dh = h == 0 ? 12 : (h > 12 ? h - 12 : h);
      return '$dh:$m $p';
    } catch (_) {
      return iso;
    }
  }

  String _formatDate(String iso) {
    try {
      final dt = DateTime.parse(iso);
      const months = [
        '',
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec',
      ];
      const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      return '${days[dt.weekday - 1]}, ${months[dt.month]} ${dt.day}, ${dt.year}';
    } catch (_) {
      return iso;
    }
  }

  String _formatDuration(String isoDuration) {
    final regex = RegExp(r'PT(?:(\d+)H)?(?:(\d+)M)?');
    final match = regex.firstMatch(isoDuration);
    if (match == null) return isoDuration;
    final hours = match.group(1) ?? '0';
    final minutes = match.group(2) ?? '0';
    return '${hours}h ${minutes}m';
  }

  /// Calculate day difference between departure and arrival.
  int _dayDifference(String departIso, String arriveIso) {
    try {
      final depart = DateTime.parse(departIso);
      final arrive = DateTime.parse(arriveIso);
      final departDate = DateTime(depart.year, depart.month, depart.day);
      final arriveDate = DateTime(arrive.year, arrive.month, arrive.day);
      return arriveDate.difference(departDate).inDays;
    } catch (_) {
      return 0;
    }
  }

  FlightOffer get offer => widget.offer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (offer.itineraries.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Flight Details')),
        body: const Center(child: Text('No itinerary data available')),
      );
    }

    final airlineCode =
        offer.validatingAirline ??
        (offer.itineraries.first.segments.isNotEmpty
            ? offer.itineraries.first.segments.first.carrierCode
            : '??');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Flight Details'),
        elevation: 0,
        backgroundColor: Colors.transparent,
        actions: [
          IconButton(
            icon: Icon(
              _isSaved ? LucideIcons.heartOff : LucideIcons.heart,
              color: _isSaved
                  ? Colors.red
                  : theme.colorScheme.onSurface.withValues(alpha: 0.6),
              size: 22,
            ),
            tooltip: _isSaved ? 'Remove from saved' : 'Save flight',
            onPressed: () {
              setState(() => _isSaved = !_isSaved);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    _isSaved ? 'Flight saved!' : 'Flight removed from saved',
                  ),
                  behavior: SnackBarBehavior.floating,
                  duration: const Duration(seconds: 2),
                ),
              );
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.only(
          left: 8,
          right: 8,
          top: 8,
          bottom: MediaQuery.of(context).padding.bottom + 24,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Airline Header Card ──
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.elevationColor(context, 1),
                borderRadius: BorderRadius.circular(_radius),
              ),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.network(
                      _airlineLogoUrl(airlineCode),
                      width: 48,
                      height: 48,
                      errorBuilder: (_, _, _) => Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: AppTheme.accent.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Center(
                          child: Text(
                            airlineCode,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.accent,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _airlineName(airlineCode),
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Flight $airlineCode${offer.itineraries.first.segments.first.flightNumber}',
                          style: TextStyle(
                            fontSize: 13,
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '\$${offer.totalPrice.toStringAsFixed(0)}',
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.accent,
                        ),
                      ),
                      Text(
                        offer.currency,
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ── Itineraries ──
            for (int i = 0; i < offer.itineraries.length; i++) ...[
              _buildItineraryCard(
                context,
                offer.itineraries[i],
                label: offer.itineraries.length > 1
                    ? (i == 0 ? 'Outbound Flight' : 'Return Flight')
                    : 'Flight Itinerary',
              ),
              if (i < offer.itineraries.length - 1) const SizedBox(height: 16),
            ],
            const SizedBox(height: 16),

            // ── Price Breakdown ──
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.elevationColor(context, 1),
                borderRadius: BorderRadius.circular(_radius),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        LucideIcons.receipt,
                        size: 18,
                        color: AppTheme.accent,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Price Breakdown',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  ...offer.travelerPricings.map((tp) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Traveler ${tp.travelerId} (${tp.travelerType})',
                            style: TextStyle(
                              fontSize: 13,
                              color: theme.colorScheme.onSurface.withValues(
                                alpha: 0.7,
                              ),
                            ),
                          ),
                          Text(
                            '${tp.currency} ${tp.totalPrice}',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                  Divider(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.1),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Total',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                      Text(
                        '\$${offer.totalPrice.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.accent,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ── Flight Info ──
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.elevationColor(context, 1),
                borderRadius: BorderRadius.circular(_radius),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        LucideIcons.info,
                        size: 18,
                        color: AppTheme.accent,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Flight Info',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _infoRow(
                    context,
                    LucideIcons.armchair,
                    'Seats Available',
                    '${offer.numberOfBookableSeats}',
                  ),
                  _infoRow(
                    context,
                    LucideIcons.tag,
                    'Fare Option',
                    offer.travelerPricings.isNotEmpty
                        ? offer.travelerPricings.first.fareOption
                        : 'N/A',
                  ),
                  _infoRow(
                    context,
                    LucideIcons.ticket,
                    'Instant Ticketing',
                    offer.instantTicketingRequired
                        ? 'Required'
                        : 'Not Required',
                  ),
                  _infoRow(
                    context,
                    LucideIcons.building2,
                    'Source',
                    offer.source,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // ── Book Button ──
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => FlightBookingScreen(offer: offer),
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.accent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(_radius),
                  ),
                  elevation: 0,
                ),
                icon: const Icon(LucideIcons.creditCard, size: 20),
                label: Text(
                  'Book for \$${offer.totalPrice.toStringAsFixed(0)}',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildItineraryCard(
    BuildContext context,
    FlightItinerary itinerary, {
    required String label,
  }) {
    final theme = Theme.of(context);
    final stops = itinerary.segments.length - 1;

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.elevationColor(context, 1),
        borderRadius: BorderRadius.circular(_radius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: AppTheme.elevationColor(context, 2),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(_radius),
                topRight: Radius.circular(_radius),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                Row(
                  children: [
                    Icon(
                      LucideIcons.clock,
                      size: 14,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _formatDuration(itinerary.duration),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.6,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: stops == 0
                            ? Colors.green.withValues(alpha: 0.12)
                            : Colors.orange.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        stops == 0
                            ? 'Direct'
                            : '$stops stop${stops > 1 ? "s" : ""}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: stops == 0
                              ? Colors.green.shade700
                              : Colors.orange.shade700,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Segments
          ...itinerary.segments.asMap().entries.map((entry) {
            final idx = entry.key;
            final seg = entry.value;
            return _buildSegmentDetail(
              context,
              seg,
              idx,
              itinerary.segments.length,
            );
          }),
        ],
      ),
    );
  }

  Widget _buildSegmentDetail(
    BuildContext context,
    FlightSegment segment,
    int index,
    int total,
  ) {
    final theme = Theme.of(context);
    final isLast = index == total - 1;
    final daysDiff = _dayDifference(segment.departureAt, segment.arrivalAt);

    return Column(
      children: [
        if (index > 0)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: theme.brightness == Brightness.dark
                ? Colors.orange.withValues(alpha: 0.08)
                : Colors.orange.withValues(alpha: 0.06),
            child: Row(
              children: [
                Icon(
                  LucideIcons.clock3,
                  size: 14,
                  color: Colors.orange.shade700,
                ),
                const SizedBox(width: 6),
                Text(
                  'Layover at ${segment.departureIata}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.orange.shade700,
                  ),
                ),
              ],
            ),
          ),

        Padding(
          padding: EdgeInsets.fromLTRB(16, 14, 16, isLast ? 16 : 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Timeline
              Column(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: AppTheme.accent, width: 2),
                    ),
                  ),
                  Container(
                    width: 2,
                    height: 50,
                    color: AppTheme.accent.withValues(alpha: 0.3),
                  ),
                  Container(
                    width: 10,
                    height: 10,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppTheme.accent,
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 14),
              // Details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Departure
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _formatTime(segment.departureAt),
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                        Text(
                          segment.departureIata,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.6,
                            ),
                          ),
                        ),
                      ],
                    ),
                    Text(
                      _formatDate(segment.departureAt),
                      style: TextStyle(
                        fontSize: 11,
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.4,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Flight info
                    Row(
                      children: [
                        Icon(
                          LucideIcons.plane,
                          size: 13,
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.4,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            '${_airlineName(segment.carrierCode)} ${segment.carrierCode}${segment.flightNumber}',
                            style: TextStyle(
                              fontSize: 11,
                              color: theme.colorScheme.onSurface.withValues(
                                alpha: 0.5,
                              ),
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(
                          LucideIcons.clock,
                          size: 13,
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.4,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _formatDuration(segment.duration),
                          style: TextStyle(
                            fontSize: 11,
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // Arrival
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _formatTime(segment.arrivalAt),
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: theme.colorScheme.onSurface,
                              ),
                            ),
                            if (daysDiff > 0)
                              Padding(
                                padding: const EdgeInsets.only(left: 4),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                    vertical: 1,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.orange.withValues(
                                      alpha: 0.12,
                                    ),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    '+${daysDiff}d',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.orange.shade700,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        Text(
                          segment.arrivalIata,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.6,
                            ),
                          ),
                        ),
                      ],
                    ),
                    Text(
                      _formatDate(segment.arrivalAt),
                      style: TextStyle(
                        fontSize: 11,
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _infoRow(
    BuildContext context,
    IconData icon,
    String label,
    String value,
  ) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(
            icon,
            size: 16,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
          ),
          const SizedBox(width: 10),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}
