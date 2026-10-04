import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:intl/intl.dart';

import 'package:diaspora_nearby/theme/app_theme.dart';
import 'package:diaspora_nearby/features/trust/services/trust_service.dart';
import 'package:diaspora_nearby/features/trust/widgets/trust_slider_widget.dart';
import 'package:diaspora_nearby/features/dsp/repository/points_repository.dart';

/// Trust vouch modal opened from chat header name tap.
/// Overlaps the chat AppBar with rounded top corners.
class TrustVouchModal extends ConsumerWidget {
  final String targetUserId;
  final String currentUserId;
  final String displayName;
  final String? photoUrl;

  const TrustVouchModal({
    super.key,
    required this.targetUserId,
    required this.currentUserId,
    required this.displayName,
    this.photoUrl,
  });

  /// Show the modal overlapping the chat header
  static Future<void> show({
    required BuildContext context,
    required String targetUserId,
    required String currentUserId,
    required String displayName,
    String? photoUrl,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: false,
      backgroundColor: Colors.transparent,
      builder: (_) => TrustVouchModal(
        targetUserId: targetUserId,
        currentUserId: currentUserId,
        displayName: displayName,
        photoUrl: photoUrl,
      ),
    );
  }

  /// Spectral color from trust score
  Color _trustColor(double score) {
    if (score <= 20) return AppTheme.error;
    if (score <= 40) return Colors.deepOrange;
    if (score <= 60) return Colors.amber;
    if (score <= 80) return Colors.lightGreen;
    return AppTheme.accent;
  }

  static const Color _sageGreen = Color(0xFF7A9E7E);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final trustAsync = ref.watch(userTrustProvider(targetUserId));
    final pointsAsync = ref.watch(userPointsProvider(targetUserId));

    return Container(
      // Overlap the header — use ~90% of screen height
      height: MediaQuery.of(context).size.height * 0.90,
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(top: 10, bottom: 6),
              decoration: BoxDecoration(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // --- Title row with PCT + DSP stats ---
          Padding(
            padding: const EdgeInsets.only(
              left: AppTheme.pageHorizontalPadding,
              right: AppTheme.pageHorizontalPadding,
              top: 4,
              bottom: 8,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Vouch for ${displayName.split(' ').first}',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      // PCT + DSP inline stats
                      Row(
                        children: [
                          Icon(
                            LucideIcons.shieldCheck,
                            size: 13,
                            color: trustAsync.when(
                              data: (t) => _trustColor(t?.trustScore ?? 0),
                              loading: () => theme.colorScheme.onSurface
                                  .withValues(alpha: 0.4),
                              error: (_, _) => theme.colorScheme.onSurface
                                  .withValues(alpha: 0.4),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            trustAsync.when(
                              data: (t) => '${t?.trustScore.toInt() ?? 0} PCT',
                              loading: () => '--',
                              error: (_, _) => '--',
                            ),
                            style: TextStyle(
                              fontSize: 12,
                              color: trustAsync.when(
                                data: (t) => _trustColor(t?.trustScore ?? 0),
                                loading: () => theme.colorScheme.onSurface
                                    .withValues(alpha: 0.4),
                                error: (_, _) => theme.colorScheme.onSurface
                                    .withValues(alpha: 0.4),
                              ),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Icon(
                            LucideIcons.coins,
                            size: 13,
                            color: _sageGreen,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            pointsAsync.when(
                              data: (p) =>
                                  '${NumberFormat('#,###').format(p?.availablePoints ?? 0)} DSP',
                              loading: () => '--',
                              error: (_, _) => '--',
                            ),
                            style: const TextStyle(
                              fontSize: 12,
                              color: _sageGreen,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(LucideIcons.x, size: 20),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  tooltip: 'Close',
                ),
              ],
            ),
          ),

          // Scrollable content
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                horizontal: AppTheme.pageHorizontalPadding,
                vertical: 8,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // --- Explanation Card ---
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.elevationColor(context, 1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              LucideIcons.info,
                              size: 16,
                              color: theme.colorScheme.onSurface.withValues(
                                alpha: 0.6,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'How Trust Vouching Works',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: theme.colorScheme.onSurface,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        _buildExplainerRow(
                          context,
                          LucideIcons.target,
                          'Rate how much you trust this person -- 0 to 100',
                        ),
                        const SizedBox(height: 8),
                        _buildExplainerRow(
                          context,
                          LucideIcons.gift,
                          'Any rating earns you 1,000 DSP vouch reward -- first time only',
                        ),
                        const SizedBox(height: 8),
                        _buildExplainerRow(
                          context,
                          LucideIcons.lock,
                          'No Trust (1-10) or Full Trust (91-100) -- your 1,000 DSP is staked instead of free',
                        ),
                        const SizedBox(height: 8),
                        _buildExplainerRow(
                          context,
                          LucideIcons.trendingUp,
                          'Stakers earn +100 DSP when others agree (same tier)',
                        ),
                        const SizedBox(height: 8),
                        _buildExplainerRow(
                          context,
                          LucideIcons.trendingDown,
                          'Stakers lose -100 DSP from stake when others disagree',
                        ),
                        const SizedBox(height: 8),
                        _buildExplainerRow(
                          context,
                          LucideIcons.trophy,
                          'Every 10 Net Vouches (Full Trust minus No Trust) earns ±1 PCT for the trusted user',
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // --- The Trust Slider ---
                  TrustSliderWidget(
                    targetUserId: targetUserId,
                    currentUserId: currentUserId,
                    displayName: displayName,
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

  Widget _buildExplainerRow(BuildContext context, IconData icon, String text) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(
            icon,
            size: 14,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 13,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
            ),
          ),
        ),
      ],
    );
  }
}
