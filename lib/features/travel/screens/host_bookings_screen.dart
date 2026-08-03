import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:diaspora_nearby/theme/app_theme.dart';
import 'package:diaspora_nearby/features/auth/repository/auth_repository.dart';
import 'package:diaspora_nearby/features/travel/models/peer_listing.dart';
import 'package:diaspora_nearby/features/travel/services/peer_listing_repository.dart';
import 'package:diaspora_nearby/features/dsp/services/points_service.dart';

/// Screen for hosts to manage incoming booking requests.
class HostBookingsScreen extends ConsumerStatefulWidget {
  const HostBookingsScreen({super.key});

  @override
  ConsumerState<HostBookingsScreen> createState() => _HostBookingsScreenState();
}

class _HostBookingsScreenState extends ConsumerState<HostBookingsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabC;
  List<PeerBooking>? _bookings;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabC = TabController(length: 3, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabC.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final uid = ref.read(authRepositoryProvider).currentUser?.uid;
    if (uid == null) return;

    final repo = ref.read(peerListingRepositoryProvider);
    _bookings = await repo.getHostBookings(uid);

    if (mounted) setState(() => _isLoading = false);
  }

  List<PeerBooking> _filtered(String status) {
    if (_bookings == null) return [];
    return _bookings!.where((b) => b.status == status).toList();
  }

  Future<void> _updateStatus(PeerBooking booking, String status) async {
    final repo = ref.read(peerListingRepositoryProvider);
    await repo.updateBookingStatus(booking.id, status);

    if (status == 'completed' && booking.listingType == 'stay') {
      final pointsService = ref.read(pointsServiceProvider);
      await pointsService.trackHostATraveler(
        booking.hostId,
        booking.guestId,
        nights: booking.nights,
      );
    }

    _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Booking Requests'),
        elevation: 0,
        backgroundColor: Colors.transparent,
        bottom: TabBar(
          controller: _tabC,
          indicatorColor: AppTheme.accent,
          labelColor: AppTheme.accent,
          unselectedLabelColor: theme.colorScheme.onSurface.withValues(
            alpha: 0.4,
          ),
          labelStyle: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
          tabs: [
            Tab(text: 'Pending (${_filtered('pending').length})'),
            Tab(text: 'Confirmed (${_filtered('confirmed').length})'),
            Tab(
              text:
                  'Past (${_filtered('completed').length + _filtered('cancelled').length})',
            ),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabC,
              children: [
                _buildList(theme, _filtered('pending'), isPending: true),
                _buildList(theme, _filtered('confirmed'), isConfirmed: true),
                _buildList(theme, [
                  ..._filtered('completed'),
                  ..._filtered('cancelled'),
                ]),
              ],
            ),
    );
  }

  Widget _buildList(
    ThemeData theme,
    List<PeerBooking> bookings, {
    bool isPending = false,
    bool isConfirmed = false,
  }) {
    if (bookings.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              LucideIcons.inbox,
              size: 48,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.15),
            ),
            const SizedBox(height: 12),
            Text(
              'No bookings here',
              style: TextStyle(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: EdgeInsets.only(
          left: 8,
          right: 8,
          top: 8,
          bottom: MediaQuery.of(context).padding.bottom + 16,
        ),
        itemCount: bookings.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (_, i) => _bookingCard(
          theme,
          bookings[i],
          isPending: isPending,
          isConfirmed: isConfirmed,
        ),
      ),
    );
  }

  Widget _bookingCard(
    ThemeData theme,
    PeerBooking booking, {
    bool isPending = false,
    bool isConfirmed = false,
  }) {
    final isCar = booking.listingType == 'car';
    final statusColor = _statusColor(booking.status);

    return Container(
      decoration: AppTheme.cardDecoration(context),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Icon(
                isCar ? LucideIcons.car : LucideIcons.home,
                size: 18,
                color: AppTheme.accent,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  booking.listingTitle,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  booking.status.toUpperCase(),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: statusColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Guest info
          Row(
            children: [
              Icon(
                LucideIcons.user,
                size: 14,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
              ),
              const SizedBox(width: 6),
              Text(
                booking.guestName,
                style: TextStyle(
                  fontSize: 13,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                ),
              ),
              if (booking.guestPhone.isNotEmpty) ...[
                const SizedBox(width: 12),
                Icon(
                  LucideIcons.phone,
                  size: 14,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                ),
                const SizedBox(width: 4),
                Text(
                  booking.guestPhone,
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),

          // Dates
          Row(
            children: [
              Icon(
                LucideIcons.calendar,
                size: 14,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
              ),
              const SizedBox(width: 6),
              Text(
                '${_fmtDate(booking.startDate)} → ${_fmtDate(booking.endDate)}',
                style: TextStyle(
                  fontSize: 13,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '(${booking.nights} ${isCar ? 'day' : 'night'}${booking.nights > 1 ? 's' : ''})',
                style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Total
          Row(
            children: [
              Text(
                '\$${booking.totalPrice.toStringAsFixed(0)}',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.accent,
                ),
              ),
              const Spacer(),
              if (booking.guests != null && !isCar)
                Text(
                  '${booking.guests} guest${booking.guests! > 1 ? 's' : ''}',
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                  ),
                ),
            ],
          ),

          // Notes
          if (booking.notes != null && booking.notes!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppTheme.elevationColor(context, 2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    LucideIcons.messageSquare,
                    size: 14,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      booking.notes!,
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.6,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // Action buttons for pending
          if (isPending) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _updateStatus(booking, 'cancelled'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red.shade400,
                      side: BorderSide(
                        color: Colors.red.shade400.withValues(alpha: 0.3),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text(
                      'Decline',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => _updateStatus(booking, 'confirmed'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      elevation: 0,
                    ),
                    child: const Text(
                      'Confirm',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ),
          ],

          // Mark complete for confirmed
          if (isConfirmed) ...[
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => _updateStatus(booking, 'completed'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.accent,
                  side: BorderSide(
                    color: AppTheme.accent.withValues(alpha: 0.3),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                child: const Text(
                  'Mark as Completed',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _fmtDate(DateTime dt) => '${dt.month}/${dt.day}/${dt.year}';

  Color _statusColor(String status) {
    switch (status) {
      case 'pending':
        return const Color(0xFFF59E0B); // warning
      case 'confirmed':
        return const Color(0xFF22C55E); // success
      case 'completed':
        return AppTheme.accent;
      case 'cancelled':
        return const Color(0xFFEF4444); // error
      default:
        return Colors.grey;
    }
  }
}
