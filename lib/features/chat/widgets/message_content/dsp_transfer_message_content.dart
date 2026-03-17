import 'package:flutter/material.dart';
import 'package:diaspora_nearby/features/chat/models/message.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:diaspora_nearby/theme/app_theme.dart';

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
    final txHash = metadata['txHash'] as String?;

    final colorScheme = Theme.of(context).colorScheme;

    // Asset-specific accent color
    final accentColor = isToken
        ? AppTheme.tokenColor
        : AppTheme.dspColor;

    return Container(
      width: 240,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isOwn
            ? colorScheme.primaryContainer.withValues(alpha: 0.9)
            : colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isOwn
              ? colorScheme.primary.withValues(alpha: 0.3)
              : colorScheme.outline.withValues(alpha: 0.1),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
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
                  color: accentColor.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isOwn ? LucideIcons.send : LucideIcons.download,
                  size: 16,
                  color: accentColor,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                isOwn
                    ? (isToken ? r'Sent $DIASPORA' : 'Sent Points')
                    : (isToken ? r'Received $DIASPORA' : 'Received Points'),
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

          // Amount — no logo, colored by asset type
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '$amount',
                style: GoogleFonts.outfit(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: accentColor,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                isToken ? r'$DIASPORA' : 'DSP',
                style: GoogleFonts.outfit(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: accentColor.withValues(alpha: 0.8),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Divider
          Divider(
            height: 1,
            color: isOwn
                ? colorScheme.onPrimaryContainer.withValues(alpha: 0.2)
                : colorScheme.outline.withValues(alpha: 0.2),
          ),
          const SizedBox(height: 12),

          // Footer: Transfer Confirmed + Optional Verify TX link
          Row(
            children: [
              Icon(
                LucideIcons.checkCircle2,
                size: 14,
                color: isOwn
                    ? colorScheme.onPrimaryContainer.withValues(alpha: 0.7)
                    : Colors.green,
              ),
              const SizedBox(width: 6),
              Text(
                'Transfer Confirmed',
                style: GoogleFonts.outfit(
                  fontSize: 12,
                  color: isOwn
                      ? colorScheme.onPrimaryContainer.withValues(alpha: 0.7)
                      : colorScheme.onSurfaceVariant,
                ),
              ),
              if (txHash != null) ...[
                const Spacer(),
                GestureDetector(
                  onTap: () => launchUrl(
                    Uri.parse('https://basescan.org/tx/$txHash'),
                    mode: LaunchMode.externalApplication,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Verify',
                        style: GoogleFonts.outfit(
                          fontSize: 10,
                          color: accentColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 2),
                      Icon(
                        LucideIcons.externalLink,
                        size: 10,
                        color: accentColor,
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
