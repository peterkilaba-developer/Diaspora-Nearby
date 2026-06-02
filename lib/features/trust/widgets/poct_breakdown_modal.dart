import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:intl/intl.dart';

import 'package:diaspora_nearby/theme/app_theme.dart';
import 'package:diaspora_nearby/features/trust/services/trust_service.dart';
import 'package:diaspora_nearby/features/trust/models/trust_data.dart';
import 'package:diaspora_nearby/features/dsp/repository/points_repository.dart';

/// PoCT breakdown modal showing how a user earned their trust score.
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
      builder: (_) => PoctBreakdownModal(
        userId: userId,
        displayName: displayName,
        trustScore: trustScore,
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
                // PoCT Score Ring
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
                        "$displayName's PoCT Score",
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

          // --- Scrollable Breakdown ---
          Expanded(
            child: trustAsync.when(
              data: (trustData) {
                final t = trustData;
                // Compute days active from UserPoints signup date
                final pts = pointsAsync.value;
                final signupDate = pts?.signupDate ?? DateTime.now();
                final daysActive = DateTime.now().difference(signupDate).inDays;

                return SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // === SECTION 1: Genesis Milestones ===
                      _buildSectionHeader(
                        theme,
                        'Genesis Milestones',
                        'One-time +10 PoCT at first 10 unique',
                        LucideIcons.award,
                      ),
                      const SizedBox(height: 12),

                      _buildMilestoneRow(
                        theme,
                        icon: LucideIcons.users,
                        label: 'Family Connections',
                        count: (t?.uniqueFamilyCount ?? 0).clamp(0, 10),
                        milestone: 10,
                        poct: 10,
                        achieved: (t?.uniqueFamilyCount ?? 0) >= 10,
                      ),
                      _buildMilestoneRow(
                        theme,
                        icon: LucideIcons.userPlus,
                        label: 'Friend Connections',
                        count: (t?.uniqueFriendCount ?? 0).clamp(0, 10),
                        milestone: 10,
                        poct: 10,
                        achieved: (t?.uniqueFriendCount ?? 0) >= 10,
                      ),
                      _buildMilestoneRow(
                        theme,
                        icon: LucideIcons.qrCode,
                        label: 'QR Identity Exchanges',
                        count: (t?.uniqueQrCount ?? 0).clamp(0, 10),
                        milestone: 10,
                        poct: 10,
                        achieved: (t?.uniqueQrCount ?? 0) >= 10,
                      ),
                      // [UPDATED v3] Split into separate Verified and Vouched
                      _buildMilestoneRow(
                        theme,
                        icon: LucideIcons.badgeCheck,
                        label: 'Verified by Peers',
                        count: (t?.uniqueVerificationCount ?? 0).clamp(0, 10),
                        milestone: 10,
                        poct: 10,
                        achieved: (t?.uniqueVerificationCount ?? 0) >= 10,
                      ),
                      _buildMilestoneRow(
                        theme,
                        icon: LucideIcons.shieldCheck,
                        label: 'Vouched by Peers',
                        count: (t?.uniqueVouchCount ?? 0).clamp(0, 10),
                        milestone: 10,
                        poct: 10,
                        achieved: (t?.uniqueVouchCount ?? 0) >= 10,
                      ),
                      _buildMilestoneRow(
                        theme,
                        icon: LucideIcons.userCheck,
                        label: 'Profile Completion',
                        count: t?.isVerified == true ? 1 : 0,
                        milestone: 1,
                        poct: 10,
                        achieved: t?.isVerified == true,
                      ),

                      const SizedBox(height: 8),
                      _buildMilestoneSummary(theme, t),

                      const SizedBox(height: 24),

                      // === SECTION 2: Transparency Signals ===
                      _buildSectionHeader(
                        theme,
                        'Transparency Signals',
                        'One-time +10 PoCT for openness',
                        LucideIcons.eye,
                      ),
                      const SizedBox(height: 12),

                      _buildTransparencyRow(
                        theme,
                        icon: LucideIcons.mapPin,
                        label: 'City Visibility Enabled',
                        achieved:
                            trustScore >=
                            10, // proxy: city visibility contributes
                        poct: 10,
                      ),

                      const SizedBox(height: 24),

                      // === SECTION 3: Community Participation ===
                      _buildSectionHeader(
                        theme,
                        'Community Participation',
                        'One-time +10 PoCT per milestone',
                        LucideIcons.users2,
                      ),
                      const SizedBox(height: 12),

                      _buildMilestoneRow(
                        theme,
                        icon: LucideIcons.calendarCheck,
                        label: 'Event Attendance (QR)',
                        count: (t?.verifiedCheckInCount ?? 0).clamp(0, 10),
                        milestone: 10,
                        poct: 10,
                        achieved: (t?.verifiedCheckInCount ?? 0) >= 10,
                      ),
                      _buildTransparencyRow(
                        theme,
                        icon: LucideIcons.heartHandshake,
                        label: 'Emergency Fund Contributor',
                        achieved: false, // Can't infer from TrustData alone
                        poct: 10,
                      ),

                      const SizedBox(height: 24),

                      // === SECTION 4: Trust Slider (Ongoing PoCT) ===
                      _buildSectionHeader(
                        theme,
                        'Trust Slider Vouches',
                        '+1 PoCT per 10 unique full-trust (>90) voters',
                        LucideIcons.heartHandshake,
                      ),
                      const SizedBox(height: 12),

                      _buildTrustSliderStats(theme, t),

                      const SizedBox(height: 24),

                      // === SECTION 5: Economic Transactions ===
                      _buildSectionHeader(
                        theme,
                        'Economic Transactions',
                        '+1 PoCT per 10 completed P2P/B2B/C2B transactions',
                        LucideIcons.arrowLeftRight,
                      ),
                      const SizedBox(height: 12),

                      _buildEconomicTxRow(theme, t),

                      const SizedBox(height: 24),

                      // === SECTION 6: Seniority ===
                      _buildSectionHeader(
                        theme,
                        'Seniority',
                        '+1 PoCT per 100 days active',
                        LucideIcons.calendar,
                      ),
                      const SizedBox(height: 12),

                      _buildSeniorityRow(theme, daysActive),

                      const SizedBox(height: 24),

                      // === SECTION 7: Penalties ===
                      _buildSectionHeader(
                        theme,
                        'Penalties',
                        '-10 PoCT per 10 occurrences',
                        LucideIcons.shieldAlert,
                      ),
                      const SizedBox(height: 12),

                      _buildPenaltiesSection(theme, t),

                      const SizedBox(height: 24),

                      // === SECTION 5: DSP Balance ===
                      pointsAsync.when(
                        data: (points) {
                          final balance = points?.availablePoints ?? 0;
                          return Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Colors.amber.shade100,
                                  Colors.amber.shade50,
                                ],
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
                          );
                        },
                        loading: () => const SizedBox.shrink(),
                        error: (_, _) => const SizedBox.shrink(),
                      ),

                      const SizedBox(height: 40),
                    ],
                  ),
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, _) =>
                  const Center(child: Text('Unable to load trust data')),
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
          border: Border.all(
            color: achieved
                ? AppTheme.accent.withValues(alpha: 0.3)
                : theme.dividerColor.withValues(alpha: 0.3),
          ),
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
                    '+$poct PoCT',
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
    // [UPDATED v3] 6 genesis milestones × 10 = 60 max
    int milestonePoCT = 0;
    if ((t?.uniqueFamilyCount ?? 0) >= 10) milestonePoCT += 10;
    if ((t?.uniqueFriendCount ?? 0) >= 10) milestonePoCT += 10;
    if ((t?.uniqueQrCount ?? 0) >= 10) milestonePoCT += 10;
    if ((t?.uniqueVerificationCount ?? 0) >= 10) milestonePoCT += 10;
    if ((t?.uniqueVouchCount ?? 0) >= 10) milestonePoCT += 10;
    if (t?.isVerified == true) milestonePoCT += 10;

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
            '+$milestonePoCT / 60',
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
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.3)),
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
                'PoCT from Vouches',
                '+$poctFromVouches',
                LucideIcons.award,
                highlight: poctFromVouches > 0,
              ),
            ],
          ),
          if (fullTrustVoters > 0) ...[
            const SizedBox(height: 10),
            // Progress to next PoCT
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
              '${fullTrustVoters % 10} / 10 toward next PoCT',
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
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.3)),
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
                  '${daysActive % 100} / 100 toward next PoCT',
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
            '+$seniorityPoCT PoCT',
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
      _PenaltyItem('Fake verifications', t?.fakeVerificationsCount ?? 0),
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
        border: Border.all(
          color: totalPenaltyPoCT > 0
              ? AppTheme.error.withValues(alpha: 0.2)
              : theme.dividerColor.withValues(alpha: 0.3),
        ),
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
                '-$totalPenaltyPoCT PoCT',
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
          border: Border.all(
            color: achieved
                ? AppTheme.accent.withValues(alpha: 0.3)
                : theme.dividerColor.withValues(alpha: 0.3),
          ),
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
              achieved ? '+$poct PoCT' : '0 / 1',
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

  // ── Economic Transactions ──

  Widget _buildEconomicTxRow(ThemeData theme, TrustData? t) {
    // We don't have the exact tx count in TrustData, so show from the score
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(
            LucideIcons.arrowLeftRight,
            size: 18,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Completed Transactions',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                ),
                const SizedBox(height: 2),
                Text(
                  'Every 10 completed P2P/B2B/C2B transactions earns +1 PoCT',
                  style: TextStyle(
                    fontSize: 11,
                    color: theme.colorScheme.onSurfaceVariant,
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

class _PenaltyItem {
  final String label;
  final int count;
  const _PenaltyItem(this.label, this.count);
}
