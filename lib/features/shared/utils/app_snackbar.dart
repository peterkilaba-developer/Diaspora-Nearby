import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:diaspora_nearby/theme/app_theme.dart';

/// Centralized snackbar utility for consistent messaging across the app.
///
/// Usage:
/// ```dart
/// AppSnackbar.success(context, 'Profile updated!');
/// AppSnackbar.error(context, 'Something went wrong');
/// AppSnackbar.info(context, 'Loading...');
/// AppSnackbar.show(context, 'Custom message');
/// ```
class AppSnackbar {
  AppSnackbar._();

  /// Show a success snackbar with a green accent.
  static void success(BuildContext context, String message) {
    _show(
      context,
      message: message,
      icon: LucideIcons.checkCircle2,
      backgroundColor: AppTheme.success,
    );
  }

  /// Show an error snackbar with a red accent.
  static void error(BuildContext context, String message) {
    _show(
      context,
      message: message,
      icon: LucideIcons.alertCircle,
      backgroundColor: AppTheme.error,
    );
  }

  /// Show an info snackbar with a blue accent.
  static void info(BuildContext context, String message) {
    _show(
      context,
      message: message,
      icon: LucideIcons.info,
      backgroundColor: AppTheme.info,
    );
  }

  /// Show a warning snackbar with an amber accent.
  static void warning(BuildContext context, String message) {
    _show(
      context,
      message: message,
      icon: LucideIcons.alertTriangle,
      backgroundColor: AppTheme.warning,
    );
  }

  /// Show a plain snackbar with default styling (backward-compatible).
  static void show(BuildContext context, String message) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  static void _show(
    BuildContext context, {
    required String message,
    required IconData icon,
    required Color backgroundColor,
    Duration duration = const Duration(seconds: 3),
  }) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(icon, color: Colors.white, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
          backgroundColor: backgroundColor,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          duration: duration,
        ),
      );
  }
}
