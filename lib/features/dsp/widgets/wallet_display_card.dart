import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:diaspora_nearby/theme/app_theme.dart';
import 'package:diaspora_nearby/features/dsp/services/epoch_service.dart';

/// Reusable wallet/treasury display card used in Points System and Crypto screens.
///
/// Displays a treasury with title, icon, allocation percentage, DSP balance,
/// estimated $DIASPORA payout, efficiency, and TGE information.
class WalletDisplayCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final String percentage;
  final int points;
  final double? efficiency;
  final String? epochLabel;
  final String? payoutLabel;
  final Widget? avatarWidget;
  final double? trustScore;
  final int? tgeEvent;
  final String? estimatedValueLabel;

  const WalletDisplayCard({
    super.key,
    required this.title,
    required this.icon,
    required this.color,
    required this.percentage,
    required this.points,
    this.efficiency,
    this.epochLabel,
    this.payoutLabel,
    this.avatarWidget,
    this.trustScore,
    this.tgeEvent,
    this.estimatedValueLabel,
  });

  String _formatPoints(int pts) {
    return '${pts.toString().replaceAllMapped(RegExp(r"(\d{1,3})(?=(\d{3})+(?!\d))"), (Match m) => "${m[1]},")} DSP';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final themeTextColor = isDark ? Colors.white : Colors.black87;
    final subTextColor = isDark ? Colors.white54 : Colors.black54;

    final double eff = efficiency ?? 1.0;
    final payout = points * eff;
    final payoutStr =
        '${NumberFormat('#,###').format(payout.round())} \$DIASPORA';

    return Container(
      padding: AppTheme.cardPaddingEdgeInsets,
      decoration: AppTheme.cardDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (avatarWidget != null) ...[
                avatarWidget!,
                const SizedBox(width: 8),
              ] else ...[
                Icon(icon, size: 18, color: color),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: themeTextColor,
                    fontSize: 13,
                  ),
                ),
              ),
              if (percentage.isNotEmpty)
                Text(
                  percentage,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppTheme.accent,
                    fontSize: 13,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  payoutLabel ?? 'ESTIMATED \$DIASPORA PAYOUT',
                  style: TextStyle(
                    fontSize: 8,
                    fontWeight: FontWeight.bold,
                    color: subTextColor,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      payoutStr,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.warning,
                      ),
                    ),
                  ],
                ),
                if (estimatedValueLabel != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    estimatedValueLabel!,
                    style: TextStyle(
                      fontSize: 11,
                      color: subTextColor,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              if (trustScore != null || tgeEvent != null)
                Expanded(
                  child: RichText(
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    text: TextSpan(
                      style: TextSpan(
                        style: TextStyle(
                          color: subTextColor,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ).style,
                      children: [
                        if (trustScore != null) ...[
                          const TextSpan(text: 'Efficiency: '),
                          TextSpan(
                            text: '${(eff * 100).toInt()}%',
                            style: TextStyle(
                              color: EpochService.getEfficiencyColor(
                                trustScore!,
                              ),
                            ),
                          ),
                        ],
                        if (trustScore != null && tgeEvent != null)
                          const TextSpan(text: ' • '),
                        if (tgeEvent != null)
                          TextSpan(text: 'TGE $tgeEvent/10'),
                      ],
                    ),
                  ),
                )
              else if (epochLabel != null)
                Expanded(
                  child: Text(
                    epochLabel!,
                    style: TextStyle(
                      color: subTextColor,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                )
              else
                Text(
                  'Treasury balance',
                  style: TextStyle(color: subTextColor, fontSize: 11),
                ),
              const SizedBox(width: 8),
              Text(
                _formatPoints(points),
                style: const TextStyle(
                  color: AppTheme.accent,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
