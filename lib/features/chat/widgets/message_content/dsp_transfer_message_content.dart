import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:diaspora_nearby/features/chat/models/message.dart';

class DSPTransferMessageContent extends StatelessWidget {
  final Message message;
  final bool isOwn;

  const DSPTransferMessageContent({
    super.key,
    required this.message,
    required this.isOwn,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final amount = message.metadata?['amount'] ?? 0;
    final currency = message.metadata?['currency'] ?? 'DSP';
    final caption = message.content.isNotEmpty == true ? message.content : null;

    // [FIX] Redundant text check
    // The system might auto-populate content with "Sent X DSP". We hide it if it's redundant.
    bool showCaption = false;
    if (caption != null && caption.trim().isNotEmpty) {
      final lowerCaption = caption.toLowerCase().trim();
      final autoText1 = 'sent $amount ${currency.toLowerCase()}';
      final autoText2 = '$amount ${currency.toLowerCase()} sent';
      final autoText3 = 'transfer sent';
      final autoText4 = 'transfer received';

      // Hide if it's just the auto-text
      if (lowerCaption != autoText1 &&
          lowerCaption != autoText2 &&
          lowerCaption != autoText3 &&
          lowerCaption != autoText4) {
        showCaption = true;
      }
    }

    final statusText = isOwn ? 'Transfer Sent' : 'Transfer Received';

    return Container(
      width:
          280, // [FIX] Fixed width to ensure Expanded works for right alignment
      constraints: const BoxConstraints(minWidth: 280),
      padding: const EdgeInsets.all(16), // [FIX] 16px padding all sides
      decoration: BoxDecoration(
        color: isOwn
            ? theme.colorScheme.primaryContainer
            : theme.colorScheme.surfaceContainerHigh,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Main Horizontal Row
          Row(
            children: [
              // [FIX] Wrap Left Side in Expanded to take remaining space
              Expanded(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      LucideIcons.coins,
                      size: 16,
                      color: isOwn
                          ? theme.colorScheme.primary
                          : theme.colorScheme.tertiary,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        statusText,
                        style: theme.textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: isOwn
                              ? theme.colorScheme.primary
                              : theme.colorScheme.tertiary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 1,
                height: 16,
                color: theme.colorScheme.outline.withOpacity(0.3),
              ),
              const SizedBox(width: 8),
              // [FIX] Amount is NOT Flexible, so it refuses to shrink
              Text(
                '$amount $currency',
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ],
          ),

          // Caption (if present and not redundant)
          if (showCaption) ...[
            const SizedBox(height: 8),
            Text(
              caption!,
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.left, // [FIX] Align to left
            ),
          ],
        ],
      ),
    );
  }
}
