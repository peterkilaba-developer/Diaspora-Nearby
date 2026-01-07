import 'package:flutter/material.dart';
import 'package:diaspora_nearby/models/message.dart';

class TextMessageContent extends StatelessWidget {
  final Message message;
  final bool isOwn;

  const TextMessageContent({
    super.key,
    required this.message,
    required this.isOwn,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 6, left: 12, right: 12),
      child: Text(
        message.content,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: isOwn ? theme.colorScheme.onPrimary : theme.colorScheme.onSurface,
          height: 1.5,
        ),
      ),
    );
  }
}
