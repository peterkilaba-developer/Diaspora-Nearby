import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:intl/intl.dart';
import 'package:diaspora_nearby/theme/app_theme.dart';
import 'package:diaspora_nearby/features/auth/repository/auth_repository.dart';
import 'package:diaspora_nearby/features/dsp/screens/points_system_screen.dart';

/// Shows the user's travel loyalty points wired to the DSP system.
/// Uses the base-10 milestone system: 10, 100, 1K, 10K DSP.
class LoyaltyRewardsScreen extends ConsumerWidget {
  const LoyaltyRewardsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final user = ref.watch(authRepositoryProvider).currentUser;
    final userId = user?.uid;

    // Stream user points to show real DSP data
    final userPointsAsync = userId != null
        ? ref.watch(userPointsStreamProvider(userId))
        : const AsyncValue<dynamic>.loading();

    return Scaffold(
      backgroundColor: AppTheme.elevationColor(context, 0),
      appBar: AppBar(
        title: const Text('Loyalty & Rewards'),
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),
      body: SafeArea(
        top: false,
        bottom: true,
        child: userPointsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Error: $e')),
          data: (userPoints) {
            // Extract travel-specific lifetime earnings
            final earnings = userPoints?.lifetimeEarnings ?? <String, int>{};
            final flightBookings = earnings['travel_booking_flight'] ?? 0;
            final hotelBookings = earnings['travel_booking_hotel'] ?? 0;
            final stayBookings = earnings['travel_booking_stay'] ?? 0;
            final carBookings = earnings['travel_booking_car_rental'] ?? 0;
            final reviews = earnings['travel_review'] ?? 0;
            final saves = earnings['travel_save'] ?? 0;
            final hosting = (earnings['host_traveler_host_reward'] ?? 0) +
                (earnings['host_traveler_guest_reward'] ?? 0);

            final totalTravelDSP =
                flightBookings +
                hotelBookings +
                stayBookings +
                carBookings +
                reviews +
                saves +
                hosting;

            // Determine tier based on total travel DSP (base-10 milestones)
            final tier = _getTier(totalTravelDSP);
            final nextTier = _getNextTier(totalTravelDSP);

            return SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Points Balance Card
                  _buildBalanceCard(theme, totalTravelDSP, tier, nextTier),

                  const SizedBox(height: 16),

                  // Tier Roadmap (base-10 milestones)
                  _buildTierRoadmap(theme, totalTravelDSP),

                  const SizedBox(height: 16),

                  // How to Earn — wired to DSP actions
                  _buildEarnSection(theme),

                  const SizedBox(height: 16),

                  // Travel DSP Activity
                  _buildActivitySection(
                    theme,
                    flightBookings: flightBookings,
                    hotelBookings: hotelBookings,
                    stayBookings: stayBookings,
                    carBookings: carBookings,
                    reviews: reviews,
                    saves: saves,
                    hosting: hosting,
                  ),

                  // Bottom safe area padding
                  SizedBox(height: MediaQuery.of(context).padding.bottom + 24),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  // --- Tier Logic (base-10 milestone system) ---

  static _TierInfo _getTier(int dsp) {
    if (dsp >= 10000) {
      return const _TierInfo(
        'GLOBE TROTTER',
        LucideIcons.globe,
        Color(0xFFFFA726),
        10000,
      );
    }
    if (dsp >= 1000) {
      return const _TierInfo(
        'VOYAGER',
        LucideIcons.ship,
        Color(0xFF2196F3),
        1000,
      );
    }
    if (dsp >= 100) {
      return const _TierInfo(
        'ADVENTURER',
        LucideIcons.mountain,
        Color(0xFF4CAF50),
        100,
      );
    }
    if (dsp >= 10) {
      return const _TierInfo(
        'TRAVELER',
        LucideIcons.compass,
        Color(0xFF78909C),
        10,
      );
    }
    return const _TierInfo('EXPLORER', LucideIcons.eye, Color(0xFF9E9E9E), 0);
  }

  static _TierInfo _getNextTier(int dsp) {
    if (dsp >= 10000) {
      return const _TierInfo(
        'MAX TIER',
        LucideIcons.crown,
        Color(0xFFFFA726),
        10000,
      );
    }
    if (dsp >= 1000) {
      return const _TierInfo(
        'GLOBE TROTTER',
        LucideIcons.globe,
        Color(0xFFFFA726),
        10000,
      );
    }
    if (dsp >= 100) {
      return const _TierInfo(
        'VOYAGER',
        LucideIcons.ship,
        Color(0xFF2196F3),
        1000,
      );
    }
    if (dsp >= 10) {
      return const _TierInfo(
        'ADVENTURER',
        LucideIcons.mountain,
        Color(0xFF4CAF50),
        100,
      );
    }
    return const _TierInfo(
      'TRAVELER',
      LucideIcons.compass,
      Color(0xFF78909C),
      10,
    );
  }

  // --- Widget Builders ---

  Widget _buildBalanceCard(
    ThemeData theme,
    int totalDSP,
    _TierInfo tier,
    _TierInfo nextTier,
  ) {
    final progress = nextTier.threshold > tier.threshold
        ? ((totalDSP - tier.threshold) / (nextTier.threshold - tier.threshold))
              .clamp(0.0, 1.0)
        : 1.0;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppTheme.accent, AppTheme.accentDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(LucideIcons.award, color: Colors.white, size: 22),
              const SizedBox(width: 8),
              const Text(
                'Travel DSP',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  tier.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.0,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            NumberFormat('#,###').format(totalDSP),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 42,
              fontWeight: FontWeight.bold,
              height: 1.0,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'DSP earned from travel',
            style: TextStyle(color: Colors.white60, fontSize: 14),
          ),
          const SizedBox(height: 20),
          // Progress to next tier
          if (nextTier.name != 'MAX TIER') ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Next: ${nextTier.name}',
                  style: const TextStyle(
                    color: Colors.white60,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  '${NumberFormat('#,###').format(totalDSP)} / ${NumberFormat('#,###').format(nextTier.threshold)} DSP',
                  style: const TextStyle(color: Colors.white60, fontSize: 12),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress,
                backgroundColor: Colors.white.withValues(alpha: 0.2),
                valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                minHeight: 6,
              ),
            ),
          ] else
            const Text(
              '🏆 Maximum tier reached!',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
        ],
      ),
    );
  }

  Widget _buildTierRoadmap(ThemeData theme, int totalDSP) {
    return Builder(
      builder: (context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: AppTheme.cardDecoration(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Travel Tiers',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Milestones at 10× intervals — just like DSP',
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                fontStyle: FontStyle.italic,
              ),
            ),
            const SizedBox(height: 14),
            const _TierRow(
              tier: 'Explorer',
              dsp: '0',
              perks: 'Access travel search',
              isActive: true,
              icon: LucideIcons.eye,
              color: Color(0xFF9E9E9E),
            ),
            _TierRow(
              tier: 'Traveler',
              dsp: '10',
              perks: 'Save to wishlist',
              isActive: totalDSP >= 10,
              icon: LucideIcons.compass,
              color: const Color(0xFF78909C),
            ),
            _TierRow(
              tier: 'Adventurer',
              dsp: '100',
              perks: 'Price alerts, saved searches',
              isActive: totalDSP >= 100,
              icon: LucideIcons.mountain,
              color: const Color(0xFF4CAF50),
            ),
            _TierRow(
              tier: 'Voyager',
              dsp: '1,000',
              perks: 'Priority support, exclusive deals',
              isActive: totalDSP >= 1000,
              icon: LucideIcons.ship,
              color: const Color(0xFF2196F3),
            ),
            _TierRow(
              tier: 'Globe Trotter',
              dsp: '10,000',
              perks: 'VIP access, cashback rewards',
              isActive: totalDSP >= 10000,
              icon: LucideIcons.globe,
              color: const Color(0xFFFFA726),
              isLast: true,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEarnSection(ThemeData theme) {
    return Builder(
      builder: (context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: AppTheme.cardDecoration(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'How to Earn Travel DSP',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 14),
            const _EarnRow(
              icon: LucideIcons.plane,
              action: 'Book a flight',
              points: '\$1 = 1 DSP',
            ),
            const _EarnRow(
              icon: LucideIcons.hotel,
              action: 'Book a hotel',
              points: '\$1 = 1 DSP',
            ),
            const _EarnRow(
              icon: LucideIcons.home,
              action: 'Book a stay',
              points: '\$1 = 1 DSP',
            ),
            const _EarnRow(
              icon: LucideIcons.car,
              action: 'Rent a car',
              points: '\$1 = 1 DSP',
            ),
            const _EarnRow(
              icon: LucideIcons.home,
              action: 'Host a traveler',
              points: '+100 DSP each',
              isLast: true,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActivitySection(
    ThemeData theme, {
    required int flightBookings,
    required int hotelBookings,
    required int stayBookings,
    required int carBookings,
    required int reviews,
    required int saves,
    required int hosting,
  }) {
    final total =
        flightBookings +
        hotelBookings +
        stayBookings +
        carBookings +
        reviews +
        saves +
        hosting;

    return Builder(
      builder: (context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: AppTheme.cardDecoration(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'DSP Breakdown',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                Text(
                  '${NumberFormat('#,###').format(total)} total',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.accent,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (total == 0)
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Column(
                    children: [
                      Icon(
                        LucideIcons.receipt,
                        size: 36,
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.15,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'No travel DSP earned yet',
                        style: TextStyle(
                          fontSize: 14,
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.4,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Book your first trip to start earning!',
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.3,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else ...[
              _ActivityRow(
                label: 'Flight Bookings',
                dsp: flightBookings,
                icon: LucideIcons.plane,
              ),
              _ActivityRow(
                label: 'Hotel Bookings',
                dsp: hotelBookings,
                icon: LucideIcons.hotel,
              ),
              _ActivityRow(
                label: 'Stay Bookings',
                dsp: stayBookings,
                icon: LucideIcons.home,
              ),
              _ActivityRow(
                label: 'Car Rentals',
                dsp: carBookings,
                icon: LucideIcons.car,
              ),
              _ActivityRow(
                label: 'Reviews',
                dsp: reviews,
                icon: LucideIcons.messageSquare,
              ),
              _ActivityRow(
                label: 'Wishlist Saves',
                dsp: saves,
                icon: LucideIcons.heart,
              ),
              _ActivityRow(
                label: 'Hosting Income',
                dsp: hosting,
                icon: LucideIcons.home,
                isLast: true,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// --- Data Classes ---

class _TierInfo {
  final String name;
  final IconData icon;
  final Color color;
  final int threshold;
  const _TierInfo(this.name, this.icon, this.color, this.threshold);
}

// --- Sub-Widgets ---

class _TierRow extends StatelessWidget {
  final String tier;
  final String dsp;
  final String perks;
  final bool isActive;
  final IconData icon;
  final Color color;
  final bool isLast;

  const _TierRow({
    required this.tier,
    required this.dsp,
    required this.perks,
    required this.isActive,
    required this.icon,
    required this.color,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 32,
            child: Column(
              children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: isActive ? color : color.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isActive ? LucideIcons.check : icon,
                    size: 13,
                    color: isActive
                        ? Colors.white
                        : color.withValues(alpha: 0.6),
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      color: theme.dividerColor.withValues(alpha: 0.3),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        tier,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: isActive ? color : theme.colorScheme.onSurface,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '$dsp DSP',
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    perks,
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EarnRow extends StatelessWidget {
  final IconData icon;
  final String action;
  final String points;
  final bool isLast;

  const _EarnRow({
    required this.icon,
    required this.action,
    required this.points,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 12),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: AppTheme.accent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 16, color: AppTheme.accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              action,
              style: TextStyle(
                fontSize: 14,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
          Text(
            points,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppTheme.accent,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActivityRow extends StatelessWidget {
  final String label;
  final int dsp;
  final IconData icon;
  final bool isLast;

  const _ActivityRow({
    required this.label,
    required this.dsp,
    required this.icon,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 10),
      child: Row(
        children: [
          Icon(
            icon,
            size: 16,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
          ),
          Text(
            '${NumberFormat('#,###').format(dsp)} DSP',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: dsp > 0
                  ? AppTheme.accent
                  : theme.colorScheme.onSurface.withValues(alpha: 0.3),
            ),
          ),
        ],
      ),
    );
  }
}
