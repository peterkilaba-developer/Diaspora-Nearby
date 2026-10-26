import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:intl/intl.dart';
import 'package:diaspora_nearby/theme/app_theme.dart';
import 'package:diaspora_nearby/features/auth/repository/auth_repository.dart';
import 'package:diaspora_nearby/features/travel/models/peer_listing.dart';
import 'package:diaspora_nearby/features/travel/services/peer_listing_repository.dart';

/// Shows the user's P2P bookings (as guest) for a specific category.
/// Stay and Car Rental have separate pages – the [category] param
/// determines which bookings are shown.
class MyBookingsScreen extends ConsumerStatefulWidget {
  /// "Stay" or "Car Rental" — used to filter and label.
  final String category;
  const MyBookingsScreen({super.key, required this.category});

  @override
  ConsumerState<MyBookingsScreen> createState() => _MyBookingsScreenState();
}

class _MyBookingsScreenState extends ConsumerState<MyBookingsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<PeerBooking> _allBookings = [];
  bool _loading = true;

  /// Map UI category label → Firestore listing type.
  String get _listingType {
    switch (widget.category.toLowerCase()) {
      case 'car rental':
        return 'car';
      case 'stay':
      default:
        return 'stay';
    }
  }

  bool get _isStay => _listingType == 'stay';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadBookings();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadBookings() async {
    final user = ref.read(authRepositoryProvider).currentUser;
    if (user == null) {
      setState(() => _loading = false);
      return;
    }

    try {
      final repo = ref.read(peerListingRepositoryProvider);
      final bookings = await repo.getGuestBookings(user.uid);

      // Filter to only the relevant listing type.
      final filtered = bookings
          .where((b) => b.listingType == _listingType)
          .toList();

      if (mounted) {
        setState(() {
          _allBookings = filtered;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<PeerBooking> _getUpcoming() {
    final now = DateTime.now();
    return _allBookings.where((b) {
      return b.startDate.isAfter(now) &&
          (b.status == 'confirmed' || b.status == 'pending');
    }).toList();
  }

  List<PeerBooking> _getActive() {
    final now = DateTime.now();
    return _allBookings.where((b) {
      return b.startDate.isBefore(now) &&
          b.endDate.isAfter(now) &&
          b.status == 'confirmed';
    }).toList();
  }

  List<PeerBooking> _getPast() {
    final now = DateTime.now();
    return _allBookings.where((b) {
      return b.endDate.isBefore(now) ||
          b.status == 'completed' ||
          b.status == 'cancelled';
    }).toList();
  }

  Future<void> _cancelBooking(PeerBooking booking) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: AlertDialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 24),
          title: const Text('Cancel Booking'),
          content: Text(
            'Cancel your booking for "${booking.listingTitle}"? This action cannot be undone.',
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Keep'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Cancel Booking'),
            ),
          ],
        ),
      ),
    );

    if (confirm == true) {
      final repo = ref.read(peerListingRepositoryProvider);
      await repo.updateBookingStatus(booking.id, 'cancelled');
      _loadBookings();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Booking cancelled'),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: AppTheme.elevationColor(context, 0),
      appBar: AppBar(
        titleSpacing: 0,
        title: Text('${widget.category} Bookings'),
        elevation: 0,
        backgroundColor: Colors.transparent,
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppTheme.accent,
          unselectedLabelColor: theme.colorScheme.onSurface.withValues(
            alpha: 0.5,
          ),
          indicatorColor: AppTheme.accent,
          indicatorSize: TabBarIndicatorSize.label,
          tabs: const [
            Tab(text: 'Upcoming'),
            Tab(text: 'Active'),
            Tab(text: 'Past'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildBookingsList(context, _getUpcoming(), 'upcoming'),
                _buildBookingsList(context, _getActive(), 'active'),
                _buildBookingsList(context, _getPast(), 'past'),
              ],
            ),
    );
  }

  Widget _buildBookingsList(
    BuildContext context,
    List<PeerBooking> bookings,
    String tab,
  ) {
    final theme = Theme.of(context);

    if (bookings.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                tab == 'upcoming'
                    ? LucideIcons.calendarDays
                    : tab == 'active'
                    ? LucideIcons.mapPin
                    : LucideIcons.history,
                size: 48,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.15),
              ),
              const SizedBox(height: 16),
              Text(
                tab == 'upcoming'
                    ? 'No upcoming ${widget.category.toLowerCase()} bookings'
                    : tab == 'active'
                    ? 'No active ${widget.category.toLowerCase()} trips'
                    : 'No past ${widget.category.toLowerCase()} bookings',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Your ${widget.category.toLowerCase()} bookings will appear here.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadBookings,
      child: ListView.builder(
        padding: EdgeInsets.only(
          left: 8,
          right: 8,
          top: 8,
          bottom: MediaQuery.of(context).padding.bottom + 16,
        ),
        itemCount: bookings.length,
        itemBuilder: (context, index) {
          return _PeerBookingCard(
            booking: bookings[index],
            isStay: _isStay,
            onCancel: bookings[index].status == 'pending'
                ? () => _cancelBooking(bookings[index])
                : null,
          );
        },
      ),
    );
  }
}

// ─── Booking Card ────────────────────────────────────────────────

class _PeerBookingCard extends StatelessWidget {
  final PeerBooking booking;
  final bool isStay;
  final VoidCallback? onCancel;

  const _PeerBookingCard({
    required this.booking,
    required this.isStay,
    this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final df = DateFormat('MMM d');

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
      decoration: AppTheme.cardDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: AppTheme.innerDecoration(
                  context,
                ).copyWith(borderRadius: BorderRadius.circular(12)),
                child: Icon(
                  isStay ? LucideIcons.home : LucideIcons.car,
                  color: AppTheme.accent,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      booking.listingTitle,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.onSurface,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Hosted by ${booking.hostName}',
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              _StatusBadge(status: booking.status),
            ],
          ),
          const SizedBox(height: 10),

          // Dates & price row
          Container(
            padding: const EdgeInsets.all(10),
            decoration: AppTheme.innerDecoration(context),
            child: Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Icon(
                        LucideIcons.calendar,
                        size: 14,
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.5,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${df.format(booking.startDate)} – ${df.format(booking.endDate)}',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.7,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  '\$${booking.totalPrice.toStringAsFixed(0)}',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ),

          // Details chips + cancel
          const SizedBox(height: 8),
          Row(
            children: [
              if (isStay && booking.guests != null)
                _DetailChip(
                  icon: LucideIcons.users,
                  label:
                      '${booking.guests} guest${booking.guests! > 1 ? 's' : ''}',
                ),
              _DetailChip(
                icon: LucideIcons.moon,
                label:
                    '${booking.nights} ${isStay ? 'night' : 'day'}${booking.nights > 1 ? 's' : ''}',
              ),
              const Spacer(),
              if (onCancel != null)
                TextButton.icon(
                  onPressed: onCancel,
                  icon: const Icon(LucideIcons.x, size: 14),
                  label: const Text('Cancel', style: TextStyle(fontSize: 12)),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.red.shade400,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Detail Chip ─────────────────────────────────────────────────

class _DetailChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _DetailChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: AppTheme.accent),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Status Badge ────────────────────────────────────────────────

class _StatusBadge extends StatelessWidget {
  final String status;

  const _StatusBadge({required this.status});

  Color _statusColor() {
    switch (status) {
      case 'confirmed':
        return const Color(0xFF22C55E);
      case 'pending':
        return const Color(0xFFF59E0B);
      case 'cancelled':
        return const Color(0xFFEF4444);
      case 'completed':
        return AppTheme.accent;
      default:
        return const Color(0xFF9E9E9E);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: _statusColor().withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        status[0].toUpperCase() + status.substring(1),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: _statusColor(),
        ),
      ),
    );
  }
}
