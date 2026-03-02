import 'package:flutter/material.dart';
import 'package:diaspora_nearby/features/chat/models/message.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

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
    final metadata = message.metadata ?? {};
    final amount = metadata['amount'] as int? ?? 0;
    final assetType = metadata['assetType'] as String? ?? 'points';
    final isToken = assetType == 'token';

    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      width: 240,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isOwn
            ? colorScheme.primaryContainer.withOpacity(0.9)
            : colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isOwn
              ? colorScheme.primary.withOpacity(0.3)
              : colorScheme.outline.withOpacity(0.1),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: Icon + Label
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isOwn
                      ? Colors.white.withOpacity(0.2)
                      : colorScheme.surface,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isOwn ? LucideIcons.send : LucideIcons.download,
                  size: 16,
                  color: isOwn
                      ? colorScheme.onPrimaryContainer
                      : colorScheme.primary,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                isOwn
                    ? (isToken ? 'Sent Token' : 'Sent Points')
                    : (isToken ? 'Received Token' : 'Received Points'),
                style: GoogleFonts.outfit(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: isOwn
                      ? colorScheme.onPrimaryContainer
                      : colorScheme.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Amount
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '$amount',
                style: GoogleFonts.outfit(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: isOwn
                      ? colorScheme.onPrimaryContainer
                      : colorScheme.onSurface,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                isToken ? r'$DIASPORA' : 'DSP',
                style: GoogleFonts.outfit(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: isOwn
                      ? colorScheme.onPrimaryContainer.withOpacity(0.8)
                      : colorScheme.onSurface.withOpacity(0.8),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Divider
          Divider(
            height: 1,
            color: isOwn
                ? colorScheme.onPrimaryContainer.withOpacity(0.2)
                : colorScheme.outline.withOpacity(0.2),
          ),
          const SizedBox(height: 12),

          // Footer: "Transfer Confirmed"
          Row(
            children: [
              Icon(
                LucideIcons.checkCircle2,
                size: 14,
                color: isOwn
                    ? colorScheme.onPrimaryContainer.withOpacity(0.7)
                    : Colors.green,
              ),
              const SizedBox(width: 6),
              Text(
                'Transfer Confirmed',
                style: GoogleFonts.outfit(
                  fontSize: 12,
                  color: isOwn
                      ? colorScheme.onPrimaryContainer.withOpacity(0.7)
                      : colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
