import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:diaspora_nearby/theme/app_theme.dart';
import 'package:diaspora_nearby/features/trust/models/trust_data.dart';

/// Data class for requirement items inside a StatusCard.
class RequirementItem {
  final String label;
  final bool isMet;
  const RequirementItem(this.label, this.isMet);
}

/// Reusable status/level card showing progress toward a trust or activity level.
///
/// Used in the Points System screen for both PSA activity levels and PCT trust levels.
class StatusCard extends StatelessWidget {
  final String title;
  final TrustLevel level;
  final bool isActive;
  final List<RequirementItem> requirements;
  final List<double>? progress;
  final List<String>? progressLabels;
  final bool isCompleted;
  final Color levelColor;

  const StatusCard({
    super.key,
    required this.title,
    required this.level,
    required this.isActive,
    required this.requirements,
    this.progress,
    this.progressLabels,
    this.isCompleted = false,
    this.levelColor = AppTheme.accent,
  });

  @override
  Widget build(BuildContext context) {
    final color = isActive
        ? levelColor
        : (isCompleted ? Colors.green : Colors.grey);

    return Opacity(
      opacity: isActive || isCompleted ? 1.0 : 0.6,
      child: Container(
        width: double.infinity,
        padding: AppTheme.cardPaddingEdgeInsets,
        decoration: AppTheme.cardDecoration(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isCompleted
                      ? LucideIcons.checkCircle2
                      : (isActive ? LucideIcons.star : LucideIcons.lock),
                  color: color,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: isActive ? AppTheme.accentDark : color,
                  ),
                ),
                const Spacer(),
                if (isActive)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.accent,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      'CURRENT',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            ...requirements.map(
              (req) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Icon(
                      req.isMet ? LucideIcons.checkCircle2 : LucideIcons.circle,
                      size: 14,
                      color: req.isMet
                          ? Colors.green
                          : color.withValues(alpha: 0.5),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        req.label,
                        style: TextStyle(
                          fontSize: 13,
                          color: req.isMet
                              ? Theme.of(context).textTheme.bodyMedium?.color
                              : Theme.of(context).textTheme.bodyMedium?.color
                                    ?.withValues(alpha: 0.7),
                          fontWeight: req.isMet
                              ? FontWeight.w500
                              : FontWeight.normal,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (isActive &&
                !isCompleted &&
                progress != null &&
                progressLabels != null) ...[
              const SizedBox(height: 16),
              const Text(
                'Next Level Progress:',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey,
                ),
              ),
              const SizedBox(height: 8),
              for (int i = 0; i < progress!.length; i++) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      progressLabels![i],
                      style: const TextStyle(fontSize: 10, color: Colors.grey),
                    ),
                    Text(
                      '${(progress![i].clamp(0.0, 1.0) * 100).toInt()}%',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: isActive ? levelColor : color,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress![i].clamp(0.0, 1.0),
                    minHeight: 6,
                    backgroundColor: color.withValues(alpha: 0.1),
                    valueColor: AlwaysStoppedAnimation(color),
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
