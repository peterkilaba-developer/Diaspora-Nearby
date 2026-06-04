import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:diaspora_nearby/features/shared/widgets/bottom_sheet_item.dart';

class ChatReportSheet extends StatelessWidget {
  static const userReasons = [
    'Fake Account',
    'Harassment or Bullying',
    'Inappropriate Content',
    'Spam',
    'Prohibited Advertising',
    'Other',
  ];

  static const messageReasons = [
    'Spam or Scam',
    'Prohibited Advertising',
    'Hate Speech',
    'Harassment or Bullying',
    'Nudity or Sexual Activity',
    'False Information',
    'Other',
  ];

  final String title;
  final String entityName;
  final List<String> reasons;
  final void Function(String reason) onReport;

  const ChatReportSheet({
    super.key,
    required this.title,
    required this.entityName,
    required this.reasons,
    required this.onReport,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Container(
            margin: const EdgeInsets.symmetric(vertical: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              title,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),

          const Divider(height: 1),

          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              physics: const BouncingScrollPhysics(),
              itemCount: reasons.length,
              separatorBuilder: (context, index) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final reason = reasons[index];
                return AppBottomSheetItem(
                  icon: LucideIcons.flag,
                  iconColor: Colors.red.shade700,
                  iconBgColor: Colors.red.shade50,
                  title: reason,
                  subtitle: 'Report $entityName for $reason',
                  onTap: () => onReport(reason),
                );
              },
            ),
          ),

          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
