import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:intl/intl.dart';
import 'package:diaspora_nearby/theme/app_theme.dart';

/// Shows all flight bookings for the authenticated user,
/// pulled from the `flight_bookings` Firestore collection.
class FlightBookingsScreen extends StatefulWidget {
  const FlightBookingsScreen({super.key});

  @override
  State<FlightBookingsScreen> createState() => _FlightBookingsScreenState();
}

class _FlightBookingsScreenState extends State<FlightBookingsScreen>
    with SingleTickerProviderStateMixin {
  static QuerySnapshot? _cachedSnapshot;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  Stream<QuerySnapshot> get _bookingsStream {
    final uid = _uid;
    if (uid == null) return const Stream.empty();
    return FirebaseFirestore.instance
        .collection('flight_bookings')
        .where('userId', isEqualTo: uid)
        .limit(100)
        .snapshots();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: AppTheme.elevationColor(context, 0),
      appBar: AppBar(
        titleSpacing: 0,
        title: const Text('Flight Bookings'),
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
            Tab(text: 'Past'),
            Tab(text: 'All'),
          ],
        ),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _bookingsStream,
        initialData: _cachedSnapshot,
        builder: (context, snapshot) {
          if (snapshot.hasData) {
            _cachedSnapshot = snapshot.data;
          }
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            debugPrint('✈️ Flight bookings error: ${snapshot.error}');
            return Center(
              child: Text(
                'Error loading bookings',
                style: TextStyle(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                ),
              ),
            );
          }

          // Sort client-side by createdAt descending
          final docs = snapshot.data?.docs ?? [];
          docs.sort((a, b) {
            final aData = a.data() as Map<String, dynamic>;
            final bData = b.data() as Map<String, dynamic>;
            final aTime = aData['createdAt'] as Timestamp?;
            final bTime = bData['createdAt'] as Timestamp?;
            if (aTime == null && bTime == null) return 0;
            if (aTime == null) return 1;
            if (bTime == null) return -1;
            return bTime.compareTo(aTime);
          });

          // Separate into upcoming and past
          final now = DateTime.now();
          final upcoming = <QueryDocumentSnapshot>[];
          final past = <QueryDocumentSnapshot>[];

          for (final doc in docs) {
            final data = doc.data() as Map<String, dynamic>;
            final depStr = data['departureDate'] as String?;
            DateTime? depDate;
            if (depStr != null && depStr.isNotEmpty) {
              try {
                depDate = DateTime.parse(depStr);
              } catch (_) {}
            }

            if (depDate != null && depDate.isBefore(now)) {
              past.add(doc);
            } else {
              upcoming.add(doc);
            }
          }

          return TabBarView(
            controller: _tabController,
            children: [
              _buildList(context, upcoming, 'upcoming'),
              _buildList(context, past, 'past'),
              _buildList(context, docs, 'all'),
            ],
          );
        },
      ),
    );
  }

  Widget _buildList(
    BuildContext context,
    List<QueryDocumentSnapshot> bookings,
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
                    ? LucideIcons.planeTakeoff
                    : tab == 'past'
                    ? LucideIcons.history
                    : LucideIcons.plane,
                size: 48,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.15),
              ),
              const SizedBox(height: 16),
              Text(
                tab == 'upcoming'
                    ? 'No upcoming flights'
                    : tab == 'past'
                    ? 'No past flights'
                    : 'No flight bookings yet',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Your flight bookings will appear here.',
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

    return ListView.builder(
      padding: EdgeInsets.only(
        left: 8,
        right: 8,
        top: 8,
        bottom: MediaQuery.of(context).padding.bottom + 16,
      ),
      itemCount: bookings.length,
      itemBuilder: (context, index) {
        final data = bookings[index].data() as Map<String, dynamic>;
        return _FlightBookingCard(data: data);
      },
    );
  }
}

// ─── Flight Booking Card ────────────────────────────────────

class _FlightBookingCard extends StatelessWidget {
  final Map<String, dynamic> data;

  const _FlightBookingCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final pnr = data['pnrReference'] as String? ?? 'N/A';
    final route = data['route'] as String? ?? '';
    final passengerName = data['passengerName'] as String? ?? '';
    final totalPrice = (data['totalPrice'] as num?)?.toDouble() ?? 0;
    final status = data['status'] as String? ?? 'confirmed';
    final travelerCount = data['travelerCount'] as int? ?? 1;
    final depStr = data['departureDate'] as String? ?? '';

    String formattedDate = depStr;
    try {
      final dt = DateTime.parse(depStr);
      formattedDate = DateFormat('MMM d, yyyy').format(dt);
    } catch (_) {}

    // Status color
    Color statusColor;
    switch (status) {
      case 'confirmed':
        statusColor = const Color(0xFF22C55E);
        break;
      case 'cancelled':
        statusColor = const Color(0xFFEF4444);
        break;
      case 'completed':
        statusColor = AppTheme.accent;
        break;
      default:
        statusColor = const Color(0xFF9E9E9E);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: AppTheme.cardDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: plane icon + route + status
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: AppTheme.innerDecoration(
                  context,
                ).copyWith(borderRadius: BorderRadius.circular(12)),
                child: const Icon(
                  LucideIcons.plane,
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
                      route,
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
                      passengerName,
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
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  status[0].toUpperCase() + status.substring(1),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: statusColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Details row
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
                        formattedDate,
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
                  '\$${totalPrice.toStringAsFixed(2)}',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // PNR + traveler count chips
          Row(
            children: [
              GestureDetector(
                onTap: () {
                  Clipboard.setData(ClipboardData(text: pnr));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Booking reference $pnr copied!'),
                      behavior: SnackBarBehavior.floating,
                      duration: const Duration(seconds: 2),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  );
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.accent.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        LucideIcons.hash,
                        size: 12,
                        color: AppTheme.accent,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        pnr,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.6,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        LucideIcons.copy,
                        size: 10,
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.accent.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      LucideIcons.users,
                      size: 12,
                      color: AppTheme.accent,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '$travelerCount traveler${travelerCount > 1 ? 's' : ''}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.6,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
