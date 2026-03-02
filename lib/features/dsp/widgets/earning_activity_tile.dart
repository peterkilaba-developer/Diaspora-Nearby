import 'package:flutter/material.dart';
import 'package:diaspora_nearby/theme/app_theme.dart';
import 'package:lucide_icons/lucide_icons.dart';

class EarningActivityTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final int rewardAmount;
  final int? earnedAmount; // [NEW] Total earned from this activity
  final Color iconColor;
  final double? progress; // 0.0 to 1.0
  final String? progressLabel; // e.g. "12/100"
  final bool isCompleted;
  final VoidCallback? onTap;

  const EarningActivityTile({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.rewardAmount,
    this.earnedAmount,
    this.iconColor = AppTheme.accent,
    this.progress,
    this.progressLabel,
    this.isCompleted = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: AppTheme.cardDecoration(context),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppTheme.standardBorderRadius),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // Icon Container
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isCompleted
                        ? AppTheme.accent.withOpacity(0.1)
                        : (progress != null && progress! > 0)
                        ? iconColor.withOpacity(0.1)
                        : Colors.grey.withOpacity(0.05),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isCompleted ? LucideIcons.check : icon,
                    color: isCompleted
                        ? AppTheme.accent
                        : (progress != null && progress! > 0)
                        ? iconColor
                        : Colors.grey,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 16),

                // Content
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: isCompleted
                              ? Theme.of(
                                  context,
                                ).textTheme.bodyLarge?.color?.withOpacity(0.7)
                              : null,
                          decoration: isCompleted
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.accent.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '+$rewardAmount DSP',
                              style: const TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.accent,
                              ),
                            ),
                          ),
                          // [NEW] Display Total Earned if available
                          if (earnedAmount != null && earnedAmount! > 0) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.green.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                'Total: $earnedAmount',
                                style: const TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green,
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              subtitle,
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      if (progress != null) ...[
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: LinearProgressIndicator(
                                  value: progress,
                                  minHeight: 6,
                                  backgroundColor: Colors.grey.withOpacity(0.1),
                                  valueColor: AlwaysStoppedAnimation(iconColor),
                                ),
                              ),
                            ),
                            if (progressLabel != null) ...[
                              const SizedBox(width: 12),
                              Text(
                                progressLabel!,
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ],
                  ),
                ),

                // Chevron or Action
                if (!isCompleted && onTap != null)
                  const Padding(
                    padding: EdgeInsets.only(left: 8),
                    child: Icon(
                      LucideIcons.chevronRight,
                      size: 20,
                      color: Colors.grey,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
