import 'package:flutter/material.dart';

import 'package:diaspora_nearby/theme/app_theme.dart';

/// A compact tap-to-pick date field, styled consistently across travel screens.
class TravelDateField extends StatelessWidget {
  const TravelDateField({
    super.key,
    required this.controller,
    required this.hint,
    required this.icon,
    required this.onTap,
  });

  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: AppTheme.elevationColor(context, 2),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: AppTheme.accent),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                controller.text.isNotEmpty ? controller.text : hint,
                style: TextStyle(
                  fontSize: 12,
                  color: controller.text.isNotEmpty
                      ? theme.colorScheme.onSurface
                      : theme.hintColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
