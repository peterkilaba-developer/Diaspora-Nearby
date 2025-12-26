import 'package:flutter/material.dart';

/// A simple themed surface container (formerly glassmorphic).
/// Uses the theme's card color for a clean, flat design.
class GlassContainer extends StatelessWidget {
  final Widget child;

  final Color? color;

  final BorderRadius? borderRadius;

  final EdgeInsetsGeometry? padding;

  final EdgeInsetsGeometry? margin;

  final VoidCallback? onTap;

  const GlassContainer({
    super.key,
    required this.child,
    this.color,
    this.borderRadius,
    this.padding,
    this.margin,
    this.onTap,
  });
  @override
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final surfaceColor = color ?? theme.cardColor;
    Widget container = Container(
      padding: padding ?? const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: borderRadius ?? BorderRadius.circular(16),
      ),
      child: child,
    );
    if (margin != null) {
      container = Padding(padding: margin!, child: container);
    }
    if (onTap != null) {
      return GestureDetector(onTap: onTap, child: container);
    }

    return container;
  }
}

