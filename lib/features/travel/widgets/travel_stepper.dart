import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import 'package:diaspora_nearby/theme/app_theme.dart';

/// A unified +/− stepper used for guest count, seats, passengers, etc.
///
/// Provides a consistent look across all travel screens:
/// icon + label on the left, [−] value [+] on the right.
class TravelStepper extends StatelessWidget {
  const TravelStepper({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.icon,
    this.min = 1,
    this.max = 20,
    this.bare = false,
  });

  final String label;

  /// Icon shown to the left of the label. Ignored when [bare] is true.
  final IconData? icon;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  /// When `true`, renders a flat Row (label + buttons) without the decorated
  /// container and icon — ideal for inline use inside advanced-filter panels.
  final bool bare;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final buttons = Row(
      mainAxisSize: bare ? MainAxisSize.min : MainAxisSize.max,
      children: [
        if (!bare) ...[
          Icon(icon, size: 16, color: AppTheme.accent),
          const SizedBox(width: 8),
          Text(label, style: TextStyle(fontSize: 12, color: theme.hintColor)),
        ] else
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
            ),
          ),
        const Spacer(),
        _StepperButton(
          icon: LucideIcons.minus,
          enabled: value > min,
          onTap: () => onChanged(value - 1),
          isDark: isDark,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            '$value',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
        ),
        _StepperButton(
          icon: LucideIcons.plus,
          enabled: value < max,
          onTap: () => onChanged(value + 1),
          isDark: isDark,
        ),
      ],
    );

    if (bare) return buttons;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.elevationColor(context, 2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: buttons,
    );
  }
}

class _StepperButton extends StatelessWidget {
  const _StepperButton({
    required this.icon,
    required this.enabled,
    required this.onTap,
    required this.isDark,
  });

  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: enabled
              ? AppTheme.accent.withValues(alpha: isDark ? 0.2 : 0.1)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: enabled
                ? AppTheme.accent.withValues(alpha: 0.3)
                : Theme.of(context).hintColor.withValues(alpha: 0.2),
          ),
        ),
        child: Icon(
          icon,
          size: 14,
          color: enabled
              ? AppTheme.accent
              : Theme.of(context).hintColor.withValues(alpha: 0.3),
        ),
      ),
    );
  }
}
