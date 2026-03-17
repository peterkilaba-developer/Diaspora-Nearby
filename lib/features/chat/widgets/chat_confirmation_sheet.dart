import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:diaspora_nearby/features/shared/widgets/bottom_sheet_item.dart';

class ChatConfirmationSheet extends StatelessWidget {
  final String title;
  final String message;
  final String actionTitle;
  final String subtitle;
  final IconData icon;
  final VoidCallback onAction;
  final bool isDestructive;

  const ChatConfirmationSheet({
    super.key,
    required this.title,
    required this.message,
    required this.actionTitle,
    required this.subtitle,
    this.icon = LucideIcons.alertTriangle,
    required this.onAction,
    this.isDestructive = true,
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
            padding: const EdgeInsets.all(24.0),
            child: Column(
              children: [
                Icon(
                  icon,
                  size: 48,
                  color: isDestructive
                      ? Colors.red.shade700
                      : theme.colorScheme.primary,
                ),
                const SizedBox(height: 16),
                Text(
                  title,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),

          const Divider(height: 1),

          AppBottomSheetItem(
            icon: icon,
            iconColor: isDestructive
                ? Colors.red.shade700
                : theme.colorScheme.primary,
            iconBgColor: isDestructive
                ? Colors.red.shade50
                : theme.colorScheme.primaryContainer.withValues(alpha: 0.1),
            title: actionTitle,
            subtitle: subtitle,
            onTap: onAction,
            isDestructive: isDestructive,
          ),

          const SizedBox(height: 8),
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
