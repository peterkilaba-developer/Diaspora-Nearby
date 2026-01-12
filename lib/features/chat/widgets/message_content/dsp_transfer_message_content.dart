import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:diaspora_nearby/models/message.dart';

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
      width: 250, 
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16), // [FIX] 16px vertical padding
      decoration: BoxDecoration(
         color: isOwn ? theme.colorScheme.primaryContainer : theme.colorScheme.surfaceContainerHigh,
         borderRadius: BorderRadius.circular(12),
         border: Border.all(
            color: theme.colorScheme.outline.withOpacity(0.1),
         ),
      ),
      child: Column(
         mainAxisSize: MainAxisSize.min,
         crossAxisAlignment: CrossAxisAlignment.center,
         children: [
            // Main Horizontal Row
            Row(
               mainAxisAlignment: MainAxisAlignment.center,
               children: [
                  Icon(
                     LucideIcons.coins, 
                     size: 16, 
                     color: isOwn ? theme.colorScheme.primary : theme.colorScheme.tertiary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                     statusText,
                     style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: isOwn ? theme.colorScheme.primary : theme.colorScheme.tertiary,
                     ),
                  ),
                  const SizedBox(width: 8),
                  Container(width: 1, height: 16, color: theme.colorScheme.outline.withOpacity(0.3)), // Divider
                  const SizedBox(width: 8),
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
                  textAlign: TextAlign.center,
               ),
            ],
         ],
      ),
    );
  }
}
