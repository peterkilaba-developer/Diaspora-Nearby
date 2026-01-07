import 'package:flutter/material.dart';
import 'package:diaspora_nearby/models/message.dart';

/// Helper widget to display text content within media messages
/// Replaces logic like `_buildTextContent` usage inside other build methods
class TopLevelTextContent extends StatelessWidget {
  final Message message;
  final bool isOwn;

  const TopLevelTextContent({super.key, required this.message, required this.isOwn});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 6, left: 12, right: 12, bottom: 6),
      child: Text(
        message.content,
        textAlign: TextAlign.left,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: isOwn ? theme.colorScheme.onPrimary : theme.colorScheme.onSurface,
        ),
      ),
    );
  }
}
