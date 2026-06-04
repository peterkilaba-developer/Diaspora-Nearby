import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:diaspora_nearby/theme/app_theme.dart';
import 'package:diaspora_nearby/features/travel/screens/flight_bookings_screen.dart';

/// Universal booking confirmation screen for flights and hotels.
class BookingConfirmationScreen extends StatelessWidget {
  final String bookingType; // 'Flight' or 'Hotel'
  final String bookingId;
  final String pnrReference;
  final String passengerName;
  final String route;
  final String date;
  final String price;
  final String currency;

  const BookingConfirmationScreen({
    super.key,
    required this.bookingType,
    required this.bookingId,
    required this.pnrReference,
    required this.passengerName,
    required this.route,
    required this.date,
    required this.price,
    required this.currency,
  });

  static const _radius = 15.0;

  String _formatDate(String iso) {
    try {
      final dt = DateTime.parse(iso);
      const months = [
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
      return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
    } catch (_) {
      return iso;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: AppTheme.elevationColor(context, 0),
      appBar: AppBar(
        title: const Text('Booking Confirmed'),
        elevation: 0,
        backgroundColor: Colors.transparent,
        automaticallyImplyLeading: false,
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          16,
          8,
          16,
          MediaQuery.of(context).padding.bottom + 32,
        ),
        child: Column(
          children: [
            const SizedBox(height: 16),

            // ── Success animation ──
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    AppTheme.accent.withValues(alpha: 0.2),
                    const Color(0xFF4CAF50).withValues(alpha: 0.2),
                  ],
                ),
              ),
              child: const Icon(
                LucideIcons.checkCircle2,
                size: 40,
                color: Color(0xFF4CAF50),
              ),
            ),
            const SizedBox(height: 20),

            Text(
              '$bookingType Booked!',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Your booking has been confirmed successfully.',
              style: TextStyle(
                fontSize: 14,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 28),

            // ── PNR Reference Card ──
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    AppTheme.accent.withValues(alpha: 0.08),
                    AppTheme.accent.withValues(alpha: 0.03),
                  ],
                ),
                borderRadius: BorderRadius.circular(_radius),
                border: Border.all(
                  color: AppTheme.accent.withValues(alpha: 0.2),
                ),
              ),
              child: Column(
                children: [
                  Text(
                    'BOOKING REFERENCE',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.5,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                    ),
                  ),
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: pnrReference));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Booking reference copied!'),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    },
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          pnrReference,
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.accent,
                            letterSpacing: 3,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(
                          LucideIcons.copy,
                          size: 16,
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Tap to copy',
                    style: TextStyle(
                      fontSize: 10,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // ── Booking Details Card ──
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.elevationColor(context, 1),
                borderRadius: BorderRadius.circular(_radius),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'BOOKING DETAILS',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.5,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                    ),
                  ),
                  const SizedBox(height: 14),
                  _detailRow(
                    context,
                    LucideIcons.hash,
                    'Booking ID',
                    bookingId,
                  ),
                  _detailRow(
                    context,
                    LucideIcons.user,
                    'Passenger',
                    passengerName,
                  ),
                  _detailRow(
                    context,
                    bookingType == 'Flight'
                        ? LucideIcons.plane
                        : LucideIcons.hotel,
                    'Route',
                    route,
                  ),
                  if (date.isNotEmpty)
                    _detailRow(
                      context,
                      LucideIcons.calendar,
                      'Date',
                      _formatDate(date),
                    ),
                  _detailRow(
                    context,
                    LucideIcons.creditCard,
                    'Amount',
                    price,
                    isLast: true,
                    valueColor: AppTheme.accent,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ── Info Notice ──
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.elevationColor(context, 1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    LucideIcons.info,
                    size: 14,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'A confirmation email will be sent to you shortly. '
                      'You can view this booking in My Bookings at any time. '
                      'Use your booking reference for check-in and airline support.',
                      style: TextStyle(
                        fontSize: 11,
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.4,
                        ),
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),

            // ── Done Button ──
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  // Pop back to travel hub
                  Navigator.of(context).popUntil((route) => route.isFirst);
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
                icon: const Icon(LucideIcons.checkCircle, size: 18),
                label: const Text(
                  'Done',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // View Bookings link
            TextButton(
              onPressed: () {
                Navigator.of(context).popUntil((route) => route.isFirst);
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const FlightBookingsScreen(),
                  ),
                );
              },
              child: const Text(
                'View My Bookings',
                style: TextStyle(
                  fontSize: 13,
                  color: AppTheme.accent,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(
    BuildContext context,
    IconData icon,
    String label,
    String value, {
    bool isLast = false,
    Color? valueColor,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 14),
      child: Row(
        children: [
          Icon(
            icon,
            size: 16,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: valueColor ?? theme.colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
