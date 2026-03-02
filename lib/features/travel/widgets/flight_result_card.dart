import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:diaspora_nearby/theme/app_theme.dart';
import 'package:diaspora_nearby/features/travel/services/amadeus_service.dart';

/// A rich flight result card showing airline, times, duration, stops, and price.
class FlightResultCard extends StatelessWidget {
  final FlightOffer offer;
  final VoidCallback? onTap;

  const FlightResultCard({
    super.key,
    required this.offer,
    this.onTap,
  });

  static const _radius = 15.0;

  /// Map common IATA airline codes to display names.
  static const _airlineNames = {
    'AA': 'American Airlines', 'DL': 'Delta Air Lines', 'UA': 'United Airlines',
    'WN': 'Southwest Airlines', 'B6': 'JetBlue Airways', 'AS': 'Alaska Airlines',
    'NK': 'Spirit Airlines', 'F9': 'Frontier Airlines', 'HA': 'Hawaiian Airlines',
    'SY': 'Sun Country', 'BA': 'British Airways', 'LH': 'Lufthansa',
    'AF': 'Air France', 'KL': 'KLM', 'EK': 'Emirates', 'QR': 'Qatar Airways',
    'SQ': 'Singapore Airlines', 'TK': 'Turkish Airlines', 'ET': 'Ethiopian Airlines',
    'W3': 'Arik Air', 'AT': 'Royal Air Maroc', 'KQ': 'Kenya Airways',
    'SA': 'South African Airways', 'MS': 'EgyptAir', 'QF': 'Qantas',
    'AC': 'Air Canada', 'LX': 'Swiss Intl', 'AZ': 'ITA Airways',
    'IB': 'Iberia', 'VS': 'Virgin Atlantic', 'CX': 'Cathay Pacific',
    'JL': 'Japan Airlines', 'NH': 'ANA', 'OZ': 'Asiana Airlines',
    'KE': 'Korean Air', 'SV': 'Saudi Arabian', 'GF': 'Gulf Air',
    'WB': 'RwandAir', 'HF': 'Air Côte d\'Ivoire', 'P4': 'Air Peace',
  };

  static String _airlineLogoUrl(String iataCode) {
    return 'https://pics.avs.io/80/80/$iataCode.png';
  }

  String _getAirlineName(String code) => _airlineNames[code] ?? code;

  /// Format ISO datetime "2024-03-15T14:30:00" → "2:30 PM"
  String _formatTime(String isoDateTime) {
    try {
      final dt = DateTime.parse(isoDateTime);
      final hour = dt.hour;
      final minute = dt.minute.toString().padLeft(2, '0');
      final period = hour >= 12 ? 'PM' : 'AM';
      final displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
      return '$displayHour:$minute $period';
    } catch (_) {
      return isoDateTime;
    }
  }

  /// Parse ISO duration "PT14H20M" → "14h 20m"
  String _formatDuration(String isoDuration) {
    final regex = RegExp(r'PT(?:(\d+)H)?(?:(\d+)M)?');
    final match = regex.firstMatch(isoDuration);
    if (match == null) return isoDuration;
    final hours = match.group(1) ?? '0';
    final minutes = match.group(2) ?? '0';
    return '${hours}h ${minutes}m';
  }

  /// Calculate day difference between departure and arrival.
  /// Returns 0 if same day, +1 if next day, +2 etc.
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (offer.itineraries.isEmpty) return const SizedBox.shrink();

    final outbound = offer.itineraries.first;
    final hasReturn = offer.itineraries.length > 1;
    final airlineCode = offer.validatingAirline ?? 
        (outbound.segments.isNotEmpty ? outbound.segments.first.carrierCode : '??');

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(_radius),
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.elevationColor(context, 1),
          borderRadius: BorderRadius.circular(_radius),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Airline header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppTheme.elevationColor(context, 2),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(_radius),
                  topRight: Radius.circular(_radius),
                ),
              ),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Image.network(
                      _airlineLogoUrl(airlineCode),
                      width: 28, height: 28,
                      errorBuilder: (_, __, ___) => Container(
                        width: 28, height: 28,
                        decoration: BoxDecoration(
                          color: AppTheme.accent.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Center(
                          child: Text(airlineCode,
                            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.accent),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _getAirlineName(airlineCode),
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: theme.colorScheme.onSurface),
                    ),
                  ),
                  Text(
                    '\$${offer.totalPrice.toStringAsFixed(0)}',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.accent),
                  ),
                ],
              ),
            ),

            // Outbound flight
            _buildItineraryRow(context, outbound, label: hasReturn ? 'Depart' : null),

            // Return flight
            if (hasReturn) ...[
              Center(
                child: Icon(
                  LucideIcons.repeat2,
                  size: 12,
                  color: theme.colorScheme.onSurface.withOpacity(0.15),
                ),
              ),
              _buildItineraryRow(context, offer.itineraries[1], label: 'Return'),
            ],

            // Bottom info bar
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
                  Icon(LucideIcons.armchair, size: 14, color: theme.colorScheme.onSurface.withOpacity(0.4)),
                  const SizedBox(width: 4),
                  Text(
                    '${offer.numberOfBookableSeats} seat${offer.numberOfBookableSeats != 1 ? "s" : ""} left',
                    style: TextStyle(
                      fontSize: 11,
                      color: offer.numberOfBookableSeats <= 3
                          ? Colors.red.shade400
                          : theme.colorScheme.onSurface.withOpacity(0.5),
                      fontWeight: offer.numberOfBookableSeats <= 3 ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    offer.currency,
                    style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurface.withOpacity(0.4)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildItineraryRow(BuildContext context, FlightItinerary itinerary, {String? label}) {
    final theme = Theme.of(context);
    if (itinerary.segments.isEmpty) return const SizedBox.shrink();

    final firstSeg = itinerary.segments.first;
    final lastSeg = itinerary.segments.last;
    final departTime = _formatTime(firstSeg.departureAt);
    final arriveTime = _formatTime(lastSeg.arrivalAt);
    final departCode = firstSeg.departureIata;
    final arriveCode = lastSeg.arrivalIata;
    final duration = _formatDuration(itinerary.duration);
    final stops = itinerary.segments.length - 1;
    final daysDiff = _dayDifference(firstSeg.departureAt, lastSeg.arrivalAt);

    String stopsText;
    Color stopsColor;
    if (stops == 0) {
      stopsText = 'Direct';
      stopsColor = Colors.green.shade600;
    } else {
      final layovers = itinerary.segments
          .take(itinerary.segments.length - 1)
          .map((s) => s.arrivalIata)
          .join(', ');
      stopsText = '$stops stop${stops > 1 ? "s" : ""} ($layovers)';
      stopsColor = stops == 1 ? Colors.orange.shade600 : Colors.red.shade400;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (label != null) ...[
            Text(label,
              style: TextStyle(
                fontSize: 10, fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurface.withOpacity(0.4),
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 6),
          ],

          // Time → Duration → Time
          Row(
            children: [
              // Departure
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(departTime,
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface),
                  ),
                  Text(departCode,
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: theme.colorScheme.onSurface.withOpacity(0.5)),
                  ),
                ],
              ),

              // Duration line
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(duration,
                        style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurface.withOpacity(0.5)),
                      ),
                      const SizedBox(height: 4),
                      Stack(
                        alignment: Alignment.center,
                        children: [
                          Container(
                            height: 2,
                            decoration: BoxDecoration(
                              color: theme.colorScheme.onSurface.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(1),
                            ),
                          ),
                          const Icon(LucideIcons.plane, size: 14, color: AppTheme.accent),
                          if (stops > 0)
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: List.generate(stops, (i) => Container(
                                width: 6, height: 6,
                                decoration: BoxDecoration(
                                  color: stopsColor, shape: BoxShape.circle,
                                  border: Border.all(color: theme.scaffoldBackgroundColor, width: 1),
                                ),
                              )),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(stopsText,
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: stopsColor),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),

              // Arrival
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(arriveTime,
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface),
                      ),
                      // Next-day indicator
                      if (daysDiff > 0)
                        Padding(
                          padding: const EdgeInsets.only(left: 2),
                          child: Text(
                            '+${daysDiff}d',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: Colors.orange.shade600,
                            ),
                          ),
                        ),
                    ],
                  ),
                  Text(arriveCode,
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: theme.colorScheme.onSurface.withOpacity(0.5)),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}
