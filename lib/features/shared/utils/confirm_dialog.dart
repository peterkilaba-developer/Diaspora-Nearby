import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:diaspora_nearby/theme/app_theme.dart';

/// Reusable confirmation dialog utility.
///
/// Usage:
/// ```dart
/// final confirmed = await ConfirmDialog.show(
///   context,
///   title: 'Delete item?',
///   message: 'This action cannot be undone.',
///   confirmText: 'Delete',
///   isDestructive: true,
/// );
/// if (confirmed) { /* proceed */ }
/// ```
class ConfirmDialog {
  ConfirmDialog._();

  /// Show a confirmation dialog and return `true` if confirmed.
  ///
  /// - [title]: Dialog title text.
  /// - [message]: Dialog body text.
  /// - [confirmText]: Label for the confirm button (default: 'Confirm').
  /// - [cancelText]: Label for the cancel button (default: 'Cancel').
  /// - [isDestructive]: If true, the confirm button is styled red.
  /// - [icon]: Optional leading icon in the title row.
  static Future<bool> show(
    BuildContext context, {
    required String title,
    required String message,
    String confirmText = 'Confirm',
    String cancelText = 'Cancel',
    bool isDestructive = false,
    IconData? icon,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                color: isDestructive ? AppTheme.error : AppTheme.accent,
                size: 22,
              ),
              const SizedBox(width: 8),
            ],
            Expanded(child: Text(title)),
          ],
        ),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(cancelText),
          ),
          if (isDestructive)
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.error,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.pop(context, true),
              child: Text(confirmText),
            )
          else
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(confirmText),
            ),
        ],
      ),
    );
    return result ?? false;
  }

  /// Convenience for destructive confirmations (delete, remove, etc).
  static Future<bool> destructive(
    BuildContext context, {
    required String title,
    required String message,
    String confirmText = 'Delete',
  }) {
    return show(
      context,
      title: title,
      message: message,
      confirmText: confirmText,
      isDestructive: true,
      icon: LucideIcons.alertTriangle,
    );
  }
}
