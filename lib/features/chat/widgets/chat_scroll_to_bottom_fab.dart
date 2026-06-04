import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

/// A small, circular button that scrolls the chat to the bottom.
/// Typically displayed when the user has scrolled up.
class ChatScrollToBottomFAB extends StatelessWidget {
  final VoidCallback onTap;
  final bool visible;

  const ChatScrollToBottomFAB({
    super.key,
    required this.onTap,
    required this.visible,
  });

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox.shrink();

    final theme = Theme.of(context);

    return Positioned(
      right: 12,
      bottom: 12,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
            border: Border.all(
              color: theme.colorScheme.outline.withValues(alpha: 0.1),
              width: 0.5,
            ),
          ),
          child: Icon(
            LucideIcons.chevronsDown,
            size: 20,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
