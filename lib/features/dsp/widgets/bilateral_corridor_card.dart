import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:diaspora_nearby/theme/app_theme.dart';
import 'package:diaspora_nearby/core/data/countries.dart';

class BilateralCorridorCard extends StatelessWidget {
  final String otherCountryCode;
  final String otherCountryName;
  final double cumulativeGdp;
  final int transactionCount;
  final double? gviIndex;
  final bool isGviUp;
  final VoidCallback? onTap;

  const BilateralCorridorCard({
    super.key,
    required this.otherCountryCode,
    required this.otherCountryName,
    required this.cumulativeGdp,
    required this.transactionCount,
    this.gviIndex,
    this.isGviUp = true,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final flag = getCountryByCode(otherCountryCode)?.flag ?? '🏳️';
    final formatter = NumberFormat('#,###');

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white.withAlpha(
            8,
          ), // Subtle background matching design convention
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            // Left: Flag
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withAlpha(10),
              ),
              child: Center(
                child: Text(flag, style: const TextStyle(fontSize: 20)),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    otherCountryName,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                      color: Colors.white,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        LucideIcons.arrowRightLeft,
                        size: 12,
                        color: Colors.white.withAlpha(150),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '$transactionCount txns',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white.withAlpha(150),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Right: GDP & Optional GVI
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      formatter.format(cumulativeGdp),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.accent,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'DSP',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.accent.withAlpha(200),
                      ),
                    ),
                  ],
                ),
                if (gviIndex != null) ...[
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: (isGviUp ? AppTheme.accent : Colors.redAccent)
                          .withAlpha(30),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isGviUp
                              ? LucideIcons.trendingUp
                              : LucideIcons.trendingDown,
                          size: 10,
                          color: isGviUp ? AppTheme.accent : Colors.redAccent,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          gviIndex!.toStringAsFixed(2),
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: isGviUp ? AppTheme.accent : Colors.redAccent,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'GVI',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            color: Colors.white.withAlpha(180),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
