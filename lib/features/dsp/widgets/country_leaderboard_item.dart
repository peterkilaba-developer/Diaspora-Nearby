import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:diaspora_nearby/theme/app_theme.dart';
import 'package:intl/intl.dart';
import 'package:diaspora_nearby/features/dsp/services/epoch_service.dart';

class CountryLeaderboardItem extends StatelessWidget {
  final Map<String, String> country;

  const CountryLeaderboardItem({
    super.key,
    required this.country,
  });

  @override
  Widget build(BuildContext context) {
    // Theme aware colors
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black87;
    final subTextColor = isDark ? Colors.white54 : Colors.black54;
    final cardColor = isDark ? Colors.white.withOpacity(0.01) : Colors.black.withOpacity(0.01);

    final double cumulativeValue = double.tryParse(country['cumulativeEarnings'] ?? '0') ?? 0;
    
    // Epoch Calculations
    final epochService = EpochService();
    final int memberCount = int.tryParse(country['memberCount'] ?? '0') ?? 0;
    
    // Country-specific Epoch
    final countryEpoch = epochService.getCurrentCommunityEpoch(cumulativeValue.round(), memberCount);
    final prevEpoch = epochService.getPreviousCommunityEpoch(countryEpoch.level);
    
    final int prevDspTarget = prevEpoch?.dspTarget ?? 0;
    final int prevMemberTarget = prevEpoch?.memberTarget ?? 0;
    
    // Range-based progress calculation
    final double dspProgress = ((cumulativeValue - prevDspTarget) / (countryEpoch.dspTarget - prevDspTarget)).clamp(0.0, 1.0);
    final double memberProgress = ((memberCount - prevMemberTarget) / (countryEpoch.memberTarget - prevMemberTarget)).clamp(0.0, 1.0);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(AppTheme.standardBorderRadius),
      ),
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
              Text(
                country['flag'] ?? '',
                style: const TextStyle(fontSize: 16),
              ),
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
                style: const TextStyle(fontSize: 10, color: AppTheme.accent, fontWeight: FontWeight.bold),
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
              backgroundColor: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.05),
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
                style: const TextStyle(fontSize: 10, color: Colors.blue, fontWeight: FontWeight.bold),
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
              backgroundColor: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.05),
              valueColor: const AlwaysStoppedAnimation(Colors.blue),
            ),
          ),

          const SizedBox(height: 8),
          
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
                style: TextStyle(
                  color: textColor,
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
