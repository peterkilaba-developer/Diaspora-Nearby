import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:diaspora_nearby/theme/app_theme.dart';

enum VerificationAlertType {
  conflict,
  limit,
  alreadyVerified,
  requirements,
  success,
  error,
}

class VerificationAlertModal extends StatelessWidget {
  final VerificationAlertType type;
  final String title;
  final String message;
  final VoidCallback? onConfirm;

  const VerificationAlertModal({
    super.key,
    required this.type,
    required this.title,
    required this.message,
    this.onConfirm,
  });

  static Future<void> show(
    BuildContext context, {
    required VerificationAlertType type,
    required String title,
    required String message,
    VoidCallback? onConfirm,
  }) {
    return showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      builder: (context) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: VerificationAlertModal(
          type: type,
          title: title,
          message: message,
          onConfirm: onConfirm,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Determine the "Theme Color" based on type
    Color alertColor;
    IconData icon;

    switch (type) {
      case VerificationAlertType.conflict:
        alertColor = AppTheme.warning;
        icon = LucideIcons.shieldAlert;
        break;
      case VerificationAlertType.limit:
        alertColor = Colors.orange;
        icon = LucideIcons.clock;
        break;
      case VerificationAlertType.alreadyVerified:
        alertColor = AppTheme.success;
        icon = LucideIcons.checkCircle;
        break;
      case VerificationAlertType.requirements:
        alertColor = AppTheme.warning;
        icon = LucideIcons.shieldAlert;
        break;
      case VerificationAlertType.success:
        alertColor = AppTheme.accent;
        icon = LucideIcons.shieldCheck;
        break;
      case VerificationAlertType.error:
        alertColor = AppTheme.error;
        icon = LucideIcons.alertTriangle;
        break;
    }

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 24),
      child: Container(
        padding: const EdgeInsets.all(AppTheme.pageHorizontalPadding * 3),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: alertColor.withValues(alpha: 0.1),
              blurRadius: 20,
              spreadRadius: 5,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Icon Header with circular tint
            Container(
              padding: const EdgeInsets.all(AppTheme.pageHorizontalPadding * 2),
              decoration: BoxDecoration(
                color: alertColor.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 48, color: alertColor),
            ),
            const SizedBox(height: 24),

            // Title
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 16),

            // Message
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                height: 1.5,
              ),
            ),
            const SizedBox(height: 32),

            // Action Button
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () {
                  Navigator.pop(context);
                  onConfirm?.call();
                },
                style: FilledButton.styleFrom(
                  backgroundColor: alertColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: const Text(
                  'Understood',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
