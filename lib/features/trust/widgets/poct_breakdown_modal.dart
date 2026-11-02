import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:intl/intl.dart';

import 'package:diaspora_nearby/theme/app_theme.dart';
import 'package:diaspora_nearby/features/trust/services/trust_service.dart';
import 'package:diaspora_nearby/features/trust/repository/trust_repository.dart';
import 'package:diaspora_nearby/features/trust/models/trust_data.dart';
import 'package:diaspora_nearby/features/dsp/repository/points_repository.dart';

/// PCT breakdown modal showing how a user earned their trust score.
/// Opened by tapping the Community Status card on profile page.
class PoctBreakdownModal extends ConsumerWidget {
  final String userId;
  final String displayName;
  final double trustScore;

  const PoctBreakdownModal({
    super.key,
    required this.userId,
    required this.displayName,
    required this.trustScore,
  });

  /// Show the modal from any context
  static Future<void> show({
    required BuildContext context,
    required String userId,
    required String displayName,
    required double trustScore,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: PoctBreakdownModal(
          userId: userId,
          displayName: displayName,
          trustScore: trustScore,
        ),
      ),
    );
  }

  Color _trustColor(double score) {
    if (score <= 20) return AppTheme.error;
    if (score <= 40) return Colors.deepOrange;
    if (score <= 60) return Colors.amber;
    if (score <= 80) return Colors.lightGreen;
    return AppTheme.accent;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final trustAsync = ref.watch(userTrustProvider(userId));
    final pointsAsync = ref.watch(userPointsProvider(userId));
    final t =
        trustAsync.value ??
        ref.read(trustRepositoryProvider).getCachedTrustData(userId);
    final pts =
        pointsAsync.value ??
        ref.read(pointsRepositoryProvider).getCachedUserPoints(userId);
    final signupDate = pts?.signupDate ?? DateTime.now();
    final daysActive = DateTime.now().difference(signupDate).inDays;
    final balance = pts?.availablePoints ?? 0;
    final color = _trustColor(trustScore);

    return Container(
      height: MediaQuery.of(context).size.height * 0.88,
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // --- Drag Handle ---
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              decoration: BoxDecoration(
                color: theme.dividerColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // --- Header with Score Circle ---
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              children: [
                // PCT Score Ring
                SizedBox(
                  width: 56,
                  height: 56,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      CircularProgressIndicator(
                        value: 1.0,
                        strokeWidth: 5,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          color.withValues(alpha: 0.2),
                        ),
                      ),
                      CircularProgressIndicator(
                        value: trustScore / 100.0,
                        strokeWidth: 5,
                        valueColor: AlwaysStoppedAnimation<Color>(color),
                        strokeCap: StrokeCap.round,
                      ),
                      Text(
                        '${trustScore.toInt()}',
                        style: TextStyle(
                          color: color,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "$displayName's PCT Score",
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        TrustLevelExtension.fromScore(trustScore).displayName,
                        style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(LucideIcons.x),
                  tooltip: 'Close',
                ),
              ],
            ),
          ),

          const Divider(height: 1),

          // --- Scrollable Breakdown (0ms immediate render) ---
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // === SECTION 1: Genesis Milestones (70 PCT Max) ===
                  _buildSectionHeader(
                    theme,
                    'Genesis Milestones',
                    'One-time +10 PCT each (70 PCT max)',
                    LucideIcons.award,
                  ),
                  const SizedBox(height: 12),

                  _buildTransparencyRow(
                    theme,
                    icon: LucideIcons.mapPin,
                    label: 'Current Location Transparency',
                    achieved:
                        t?.awardedQualificationMilestones.contains(
                              'LocationTransparency',
                            ) ==
                            true ||
                        trustScore >= 10,
                    poct: 10,
                  ),
                  _buildMilestoneRow(
                    theme,
                    icon: LucideIcons.userCheck,
                    label: 'Profile Completion',
                    count:
                        t?.awardedQualificationMilestones.contains('Profile') ==
                            true
                        ? 1
                        : 0,
                    milestone: 1,
                    poct: 10,
                    achieved:
                        t?.awardedQualificationMilestones.contains('Profile') ==
                        true,
                  ),
                  _buildMilestoneRow(
                    theme,
                    icon: LucideIcons.qrCode,
                    label: 'QR Identity Exchanges (First 10)',
                    count: (t?.uniqueQrCount ?? 0).clamp(0, 10),
                    milestone: 10,
                    poct: 10,
                    achieved: (t?.uniqueQrCount ?? 0) >= 10,
                  ),
                  _buildMilestoneRow(
                    theme,
                    icon: LucideIcons.users,
                    label: 'Family Connections (First 10)',
                    count: (t?.uniqueFamilyCount ?? 0).clamp(0, 10),
                    milestone: 10,
                    poct: 10,
                    achieved: (t?.uniqueFamilyCount ?? 0) >= 10,
                  ),
                  _buildMilestoneRow(
                    theme,
                    icon: LucideIcons.userPlus,
                    label: 'Friend Connections (First 10)',
                    count: (t?.uniqueFriendCount ?? 0).clamp(0, 10),
                    milestone: 10,
                    poct: 10,
                    achieved: (t?.uniqueFriendCount ?? 0) >= 10,
                  ),
                  _buildMilestoneRow(
                    theme,
                    icon: LucideIcons.badgeCheck,
                    label: 'Verified by Peers (First 10)',
                    count: (t?.uniqueVerificationCount ?? 0).clamp(0, 10),
                    milestone: 10,
                    poct: 10,
                    achieved: (t?.uniqueVerificationCount ?? 0) >= 10,
                  ),
                  _buildTransparencyRow(
                    theme,
                    icon: LucideIcons.heartHandshake,
                    label: 'Ubuntu Emergency Fund Contributor',
                    achieved:
                        t?.awardedQualificationMilestones.contains(
                          'EmergencyFund',
                        ) ==
                        true,
                    poct: 10,
                  ),

                  const SizedBox(height: 8),
                  _buildMilestoneSummary(theme, t),

                  const SizedBox(height: 24),

                  // === SECTION 2: Ongoing Trust-Building Events (+1 PCT per 10) ===
                  _buildSectionHeader(
                    theme,
                    'Ongoing Trust-Building Events',
                    '+1 PCT per 10 positive trust events',
                    LucideIcons.users2,
                  ),
                  const SizedBox(height: 12),

                  _buildOngoingTrustActivityRow(
                    theme,
                    icon: LucideIcons.radio,
                    label: 'Proximity Connections',
                    subtitle: '10+ min within 100 ft of another member',
                    count: t?.proximityConnectionsCount ?? 0,
                  ),
                  _buildOngoingTrustActivityRow(
                    theme,
                    icon: LucideIcons.flame,
                    label: 'Grassroots Gatherings',
                    subtitle: '60+ min within 100 ft at an invited gathering',
                    count: t?.grassrootsGatheringsCount ?? 0,
                  ),
                  _buildOngoingTrustActivityRow(
                    theme,
                    icon: LucideIcons.calendarCheck,
                    label: 'Event Attendance (Check-ins)',
                    subtitle: 'Verified QR or venue event check-ins',
                    count: t?.verifiedCheckInCount ?? 0,
                  ),
                  _buildOngoingTrustActivityRow(
                    theme,
                    icon: LucideIcons.calendarPlus,
                    label: 'Event Hosting (Attendees)',
                    subtitle: 'Verified attendees at events you host',
                    count: t?.hostedEventAttendeesCount ?? 0,
                  ),
                  _buildOngoingTrustActivityRow(
                    theme,
                    icon: LucideIcons.qrCode,
                    label: 'Additional QR Exchanges (11+)',
                    subtitle: 'In-person QR scans beyond first 10 milestone',
                    count: (t?.uniqueQrCount ?? 0) > 10
                        ? (t!.uniqueQrCount - 10)
                        : 0,
                  ),
                  _buildOngoingTrustActivityRow(
                    theme,
                    icon: LucideIcons.badgeCheck,
                    label: 'Additional Peer Verifications (11+)',
                    subtitle: 'Verifications received beyond first 10',
                    count: (t?.uniqueVerificationCount ?? 0) > 10
                        ? (t!.uniqueVerificationCount - 10)
                        : 0,
                  ),
                  _buildOngoingTrustActivityRow(
                    theme,
                    icon: LucideIcons.checkCircle2,
                    label: 'Peer Verifications Given',
                    subtitle: 'Profile fields you verified for other members',
                    count: t?.verificationsGivenCount ?? 0,
                  ),
                  _buildOngoingTrustActivityRow(
                    theme,
                    icon: LucideIcons.users,
                    label: 'Additional Family & Friends (11+)',
                    subtitle: 'Family & friend links beyond first 10 each',
                    count:
                        ((t?.uniqueFamilyCount ?? 0) > 10
                            ? (t!.uniqueFamilyCount - 10)
                            : 0) +
                        ((t?.uniqueFriendCount ?? 0) > 10
                            ? (t!.uniqueFriendCount - 10)
                            : 0),
                  ),
                  _buildOngoingTrustActivityRow(
                    theme,
                    icon: LucideIcons.messageSquare,
                    label: 'Verified Chat Solutions',
                    subtitle: 'Helpful community answers verified by peers',
                    count: t?.verifiedSolutionsCount ?? 0,
                  ),
                  _buildOngoingTrustActivityRow(
                    theme,
                    icon: LucideIcons.share2,
                    label: 'Member Referrals',
                    subtitle: 'Members who joined using your referral code',
                    count: t?.referralCount ?? 0,
                  ),
                  _buildOngoingTrustActivityRow(
                    theme,
                    icon: LucideIcons.arrowLeftRight,
                    label: 'Economic & Peer Stay Transactions',
                    subtitle: 'Completed P2P/B2B/C2B & peer hosting stays',
                    count: t?.economicTxCount ?? 0,
                  ),
                  _buildOngoingTrustActivityRow(
                    theme,
                    icon: LucideIcons.vote,
                    label: 'Governance Votes Cast',
                    subtitle: 'Votes cast on community governance proposals',
                    count: t?.governanceVotesCount ?? 0,
                  ),

                  const SizedBox(height: 24),

                  // === SECTION 3: Trust Slider (Ongoing PCT) ===
                  _buildSectionHeader(
                    theme,
                    'Trust Slider Vouches',
                    '+1 PCT per 10 unique full-trust (>90) voters',
                    LucideIcons.heartHandshake,
                  ),
                  const SizedBox(height: 12),

                  _buildTrustSliderStats(theme, t),

                  const SizedBox(height: 24),

                  // === SECTION 4: Seniority ===
                  _buildSectionHeader(
                    theme,
                    'Seniority',
                    '+1 PCT per 100 days active',
                    LucideIcons.calendar,
                  ),
                  const SizedBox(height: 12),

                  _buildSeniorityRow(theme, daysActive),

                  const SizedBox(height: 24),

                  // === SECTION 5: Penalties ===
                  _buildSectionHeader(
                    theme,
                    'Penalties',
                    '-1 PCT per 10 occurrences (-10 PCT per 10 flagged msgs)',
                    LucideIcons.shieldAlert,
                  ),
                  const SizedBox(height: 12),

                  _buildPenaltiesSection(theme, t),

                  const SizedBox(height: 24),

                  // === SECTION 5: DSP Balance ===
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.amber.shade100, Colors.amber.shade50],
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          LucideIcons.coins,
                          color: Colors.amber.shade800,
                          size: 28,
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'DSP Balance',
                              style: TextStyle(
                                color: Colors.amber.shade900,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            Text(
                              '${NumberFormat('#,###').format(balance)} \$DIASPORA',
                              style: TextStyle(
                                color: Colors.amber.shade900,
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Section Header ──

  Widget _buildSectionHeader(
    ThemeData theme,
    String title,
    String subtitle,
    IconData icon,
  ) {
    return Row(
      children: [
        Icon(icon, size: 20, color: theme.colorScheme.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 11,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Milestone Row ──

  Widget _buildMilestoneRow(
    ThemeData theme, {
    required IconData icon,
    required String label,
    required int count,
    required int milestone,
    required int poct,
    required bool achieved,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: achieved
              ? AppTheme.accent.withValues(alpha: 0.08)
              : theme.colorScheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 18,
              color: achieved ? AppTheme.accent : theme.colorScheme.outline,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: achieved
                          ? theme.colorScheme.onSurface
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 2),
                  // Progress bar
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: (count / milestone).clamp(0.0, 1.0),
                      minHeight: 4,
                      backgroundColor: theme.dividerColor.withValues(
                        alpha: 0.3,
                      ),
                      valueColor: const AlwaysStoppedAnimation(AppTheme.accent),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '$count / $milestone',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: achieved ? AppTheme.accent : theme.hintColor,
                  ),
                ),
                if (achieved)
                  Text(
                    '+$poct PCT',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppTheme.accent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMilestoneSummary(ThemeData theme, TrustData? t) {
    // Seven genesis milestones × 10 = 70 max.
    int milestonePoCT = 0;
    if (t?.awardedQualificationMilestones.contains('LocationTransparency') ==
            true ||
        (t?.trustScore ?? 0) >= 10) {
      milestonePoCT += 10;
    }
    if ((t?.uniqueFamilyCount ?? 0) >= 10) milestonePoCT += 10;
    if ((t?.uniqueFriendCount ?? 0) >= 10) milestonePoCT += 10;
    if ((t?.uniqueQrCount ?? 0) >= 10) milestonePoCT += 10;
    if ((t?.uniqueVerificationCount ?? 0) >= 10) milestonePoCT += 10;
    if (t?.awardedQualificationMilestones.contains('Profile') == true) {
      milestonePoCT += 10;
    }
    if (t?.awardedQualificationMilestones.contains('EmergencyFund') == true) {
      milestonePoCT += 10;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Genesis Milestones Total',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 13,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          Text(
            '+$milestonePoCT / 70',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
              color: milestonePoCT > 0 ? AppTheme.accent : theme.hintColor,
            ),
          ),
        ],
      ),
    );
  }

  // ── Trust Slider Stats ──

  Widget _buildTrustSliderStats(ThemeData theme, TrustData? t) {
    final fullTrustVoters = t?.vouchedByCount ?? 0;
    final poctFromVouches = fullTrustVoters ~/ 10;
    final reviewCount = t?.reviewCount ?? 0;
    final avgRating = t?.averageRating ?? 0.0;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Row(
            children: [
              _buildStatChip(
                theme,
                'Total Ratings',
                '$reviewCount',
                LucideIcons.users,
              ),
              const SizedBox(width: 12),
              _buildStatChip(
                theme,
                'Avg. Rating',
                avgRating > 0 ? '${avgRating.toStringAsFixed(1)}%' : '—',
                LucideIcons.trendingUp,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _buildStatChip(
                theme,
                'Full Trust (>90)',
                '$fullTrustVoters',
                LucideIcons.shieldCheck,
                highlight: true,
              ),
              const SizedBox(width: 12),
              _buildStatChip(
                theme,
                'PCT from Vouches',
                '+$poctFromVouches',
                LucideIcons.award,
                highlight: poctFromVouches > 0,
              ),
            ],
          ),
          if (fullTrustVoters > 0) ...[
            const SizedBox(height: 10),
            // Progress to next PCT
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: (fullTrustVoters % 10) / 10.0,
                minHeight: 6,
                backgroundColor: theme.dividerColor.withValues(alpha: 0.3),
                valueColor: const AlwaysStoppedAnimation(AppTheme.accent),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${fullTrustVoters % 10} / 10 toward next PCT',
              style: TextStyle(
                fontSize: 11,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatChip(
    ThemeData theme,
    String label,
    String value,
    IconData icon, {
    bool highlight = false,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: highlight
              ? AppTheme.accent.withValues(alpha: 0.08)
              : theme.colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.5,
                ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 16,
              color: highlight ? AppTheme.accent : theme.hintColor,
            ),
            const SizedBox(width: 6),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 10,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                Text(
                  value,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: highlight ? AppTheme.accent : null,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── Seniority ──

  Widget _buildSeniorityRow(ThemeData theme, int daysActive) {
    final seniorityPoCT = daysActive ~/ 100;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.clock, size: 18, color: theme.colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$daysActive days active',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 2),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: (daysActive % 100) / 100.0,
                    minHeight: 4,
                    backgroundColor: theme.dividerColor.withValues(alpha: 0.3),
                    valueColor: const AlwaysStoppedAnimation(AppTheme.accent),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${daysActive % 100} / 100 toward next PCT',
                  style: TextStyle(
                    fontSize: 11,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            '+$seniorityPoCT PCT',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
              color: seniorityPoCT > 0 ? AppTheme.accent : theme.hintColor,
            ),
          ),
        ],
      ),
    );
  }

  // ── Penalties ──

  Widget _buildPenaltiesSection(ThemeData theme, TrustData? t) {
    final penalties = <_PenaltyItem>[
      _PenaltyItem('Blocked by users', t?.blockedByCount ?? 0),
      _PenaltyItem('Flagged messages', t?.flaggedMessagesCount ?? 0),
      _PenaltyItem('Reported fraud', t?.reportedFraudCount ?? 0),

      _PenaltyItem('Event no-shows', t?.eventNoShowCount ?? 0),
      _PenaltyItem(
        'Rejected family requests',
        t?.rejectedFamilyConnectionsCount ?? 0,
      ),
    ];

    final totalPenaltyPoCT = penalties.fold<int>(
      0,
      (sum, p) => sum + (p.count ~/ 10),
    );

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: totalPenaltyPoCT > 0
            ? AppTheme.error.withValues(alpha: 0.05)
            : theme.colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          ...penalties.map(
            (p) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Icon(
                    LucideIcons.alertTriangle,
                    size: 14,
                    color: p.count > 0 ? AppTheme.error : theme.hintColor,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      p.label,
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  Text(
                    '${p.count}',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: p.count > 0 ? AppTheme.error : theme.hintColor,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '-${p.count ~/ 10}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      color: p.count >= 10 ? AppTheme.error : theme.hintColor,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Divider(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Total Penalty',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              Text(
                '-$totalPenaltyPoCT PCT',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: totalPenaltyPoCT > 0
                      ? AppTheme.error
                      : theme.hintColor,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Transparency Row ──

  Widget _buildTransparencyRow(
    ThemeData theme, {
    required IconData icon,
    required String label,
    required bool achieved,
    required int poct,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: achieved
              ? AppTheme.accent.withValues(alpha: 0.08)
              : theme.colorScheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 18,
              color: achieved ? AppTheme.accent : theme.colorScheme.outline,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: achieved
                      ? theme.colorScheme.onSurface
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            Text(
              achieved ? '+$poct PCT' : '0 / 1',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: achieved ? AppTheme.accent : theme.hintColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Ongoing Trust-Building Events (+1 PCT per 10) ──

  Widget _buildOngoingTrustActivityRow(
    ThemeData theme, {
    required IconData icon,
    required String label,
    required String subtitle,
    required int count,
  }) {
    final earnedPoct = count ~/ 10;
    final progressInBatch = count % 10;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: earnedPoct > 0
              ? AppTheme.accent.withValues(alpha: 0.08)
              : theme.colorScheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Row(
              children: [
                Icon(
                  icon,
                  size: 18,
                  color: earnedPoct > 0
                      ? AppTheme.accent
                      : theme.colorScheme.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 11,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '+$earnedPoct PCT',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: earnedPoct > 0
                            ? AppTheme.accent
                            : theme.hintColor,
                      ),
                    ),
                    Text(
                      '$count total',
                      style: TextStyle(
                        fontSize: 11,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progressInBatch / 10.0,
                minHeight: 4,
                backgroundColor: theme.dividerColor.withValues(alpha: 0.3),
                valueColor: const AlwaysStoppedAnimation(AppTheme.accent),
              ),
            ),
            const SizedBox(height: 3),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                '$progressInBatch / 10 toward next +1 PCT',
                style: TextStyle(
                  fontSize: 10,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PenaltyItem {
  final String label;
  final int count;
  const _PenaltyItem(this.label, this.count);
}
