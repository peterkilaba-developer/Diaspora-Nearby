import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:diaspora_nearby/theme/app_theme.dart';
import 'package:intl/intl.dart';
import 'package:diaspora_nearby/features/dsp/services/epoch_service.dart';

class CountryLeaderboardItem extends StatelessWidget {
  final Map<String, String> country;

  const CountryLeaderboardItem({super.key, required this.country});

  @override
  Widget build(BuildContext context) {
    // Theme aware colors
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black87;
    final subTextColor = isDark ? Colors.white54 : Colors.black54;
    // cardColor removed — using AppTheme.cardDecoration instead

    final double cumulativeValue =
        double.tryParse(country['cumulativeEarnings'] ?? '0') ?? 0;

    // Epoch Calculations
    final epochService = EpochService();
    final int memberCount = int.tryParse(country['memberCount'] ?? '0') ?? 0;

    // Country-specific Epoch
    final countryEpoch = epochService.getCurrentCommunityEpoch(
      cumulativeValue.round(),
      memberCount,
    );
    final prevEpoch = epochService.getPreviousCommunityEpoch(
      countryEpoch.level,
    );

    final int prevDspTarget = prevEpoch?.dspTarget ?? 0;
    final int prevMemberTarget = prevEpoch?.memberTarget ?? 0;

    // Range-based progress calculation
    final double dspProgress =
        ((cumulativeValue - prevDspTarget) /
                (countryEpoch.dspTarget - prevDspTarget))
            .clamp(0.0, 1.0);
    final double memberProgress =
        ((memberCount - prevMemberTarget) /
                (countryEpoch.memberTarget - prevMemberTarget))
            .clamp(0.0, 1.0);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 0),
      padding: const EdgeInsets.all(12),
      decoration: AppTheme.cardDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top Row: Rank, Name & Flag | Epoch Info
          Row(
            children: [
              Text(
                '#${country['rank']}',
                style: const TextStyle(
                  color: AppTheme.accent,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              const SizedBox(width: 12),
              Text(country['flag'] ?? '', style: const TextStyle(fontSize: 16)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  country['name']!,
                  style: TextStyle(
                    color: textColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                'Epoch ${countryEpoch.level}',
                style: const TextStyle(
                  color: AppTheme.accent,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // DSP Progress
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${NumberFormat.compact().format(cumulativeValue)} / ${NumberFormat.compact().format(countryEpoch.dspTarget)} DSP',
                style: const TextStyle(
                  fontSize: 10,
                  color: AppTheme.accent,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                '${(dspProgress * 100).toInt()}%',
                style: const TextStyle(fontSize: 10, color: AppTheme.accent),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: dspProgress,
              minHeight: 4,
              backgroundColor: isDark
                  ? Colors.white.withValues(alpha: 0.05)
                  : Colors.black.withValues(alpha: 0.05),
              valueColor: const AlwaysStoppedAnimation(AppTheme.accent),
            ),
          ),

          const SizedBox(height: 8),

          // Population Progress
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${NumberFormat.compact().format(memberCount)} / ${NumberFormat.compact().format(countryEpoch.memberTarget)} Users',
                style: const TextStyle(
                  fontSize: 10,
                  color: Colors.blue,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                '${(memberProgress * 100).toInt()}%',
                style: const TextStyle(fontSize: 10, color: Colors.blue),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: memberProgress,
              minHeight: 4,
              backgroundColor: isDark
                  ? Colors.white.withValues(alpha: 0.05)
                  : Colors.black.withValues(alpha: 0.05),
              valueColor: const AlwaysStoppedAnimation(Colors.blue),
            ),
          ),

          const SizedBox(height: 8),

          // Efficiency & Payout Info
          if (country['averagePoCT'] != null) ...[
            Builder(
              builder: (context) {
                final double avgPoCT =
                    double.tryParse(country['averagePoCT'] ?? '0') ?? 0;
                final double efficiency = epochService.calculateEfficiency(
                  avgPoCT,
                );
                final int rawPoints =
                    int.tryParse(country['points'] ?? '0') ?? 0;
                final double payout = rawPoints * efficiency;
                final payoutStr =
                    '${NumberFormat('#,###').format(payout.round())} \$DIASPORA';
                final Color efficiencyColor = EpochService.getEfficiencyColor(
                  avgPoCT,
                );

                return Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 0,
                    vertical: 12,
                  ),
                  decoration: AppTheme.innerDecoration(context),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'ESTIMATED \$DIASPORA PAYOUT',
                            style: TextStyle(
                              fontSize: 8,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey,
                              letterSpacing: 0.8,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: efficiencyColor.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '${(efficiency * 100).toInt()}% Yield',
                              style: TextStyle(
                                fontSize: 8,
                                fontWeight: FontWeight.bold,
                                color: efficiencyColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
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
                );
              },
            ),
          ],

          // Bottom Row: Treasury Balance
          Row(
            children: [
              Icon(LucideIcons.landmark, size: 12, color: subTextColor),
              const SizedBox(width: 4),
              Text(
                'Treasury Balance',
                style: TextStyle(color: subTextColor, fontSize: 11),
              ),
              const Spacer(),
              Text(
                country['balance']!,
                style: const TextStyle(
                  color: AppTheme.accent,
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
