import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:diaspora_nearby/theme/app_theme.dart';

/// Reusable activity reward card for the Points System screen.
///
/// Used for both PoA (Proof of Activity) and PoCT (Proof of Community Trust) items.
class ActivityCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final String amount;
  final String? statusLabel; // e.g. "1,000 earned" or "10 Received"
  final Color? statusColor;
  final Color badgeColor;

  const ActivityCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.amount,
    this.statusLabel,
    this.statusColor,
    this.badgeColor = Colors.green,
  });

  /// Factory constructor for PoA activity items.
  factory ActivityCard.activity(
    BuildContext context, {
    required String title,
    required String subtitle,
    required String amount,
    required int earned,
  }) {
    return ActivityCard(
      title: title,
      subtitle: subtitle,
      amount: amount,
      statusLabel: '${NumberFormat('#,###').format(earned)} earned',
      statusColor: earned > 0 ? AppTheme.accent : Theme.of(context).hintColor,
      badgeColor: Colors.green,
    );
  }

  /// Factory constructor for PoCT trust items.
  factory ActivityCard.trust({
    required String title,
    required String subtitle,
    required String amount,
    required String standing,
  }) {
    return ActivityCard(
      title: title,
      subtitle: subtitle,
      amount: amount,
      statusLabel: standing,
      statusColor: AppTheme.accent,
      badgeColor: AppTheme.accent,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.cardDecoration(context).color,
        borderRadius: BorderRadius.circular(10),
      ),
      margin: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row 1: Title + Status
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (statusLabel != null)
                Text(
                  statusLabel!,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: statusColor,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          // Row 2: Subtitle
          Text(
            subtitle,
            style: TextStyle(fontSize: 12, color: theme.hintColor),
          ),
          const SizedBox(height: 4),
          // Row 3: Amount badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: badgeColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              amount,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: badgeColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
