import 'package:flutter/material.dart';
import 'package:diaspora_nearby/features/chat/models/message.dart';
import 'package:diaspora_nearby/features/chat/widgets/message_content/ai_agent_actions_section.dart';
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

  String _formatAmount(int amount) {
    final s = amount.toString();
    final reg = RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))');
    return s.replaceAllMapped(reg, (Match m) => '${m[1]},');
  }

  @override
  Widget build(BuildContext context) {
    final metadata = message.metadata ?? {};
    final amount = (metadata['amount'] as num?)?.toInt() ?? 0;
    final assetType = metadata['assetType'] as String? ?? 'points';
    final isToken = assetType == 'token';
    final txHash = metadata['txHash'] as String?;
    final isConversion = metadata['isConversion'] == true;
    final headerLabel = metadata['headerLabel'] as String?;
    final footerLabel = metadata['footerLabel'] as String?;
    final explanationText = metadata['explanationText'] as String?;
    final nextTaskTitle = metadata['nextTaskTitle'] as String?;
    final nextTaskBody = metadata['nextTaskBody'] as String?;
    final hasAiActions = !isOwn && metadata['aiActions'] is List;
    final hasRichConversionBody =
        (explanationText != null && explanationText.trim().isNotEmpty) ||
        (nextTaskBody != null && nextTaskBody.trim().isNotEmpty) ||
        hasAiActions;

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // Asset-specific accent color
    final accentColor = isToken ? AppTheme.tokenColor : AppTheme.dspColor;

    final resolvedHeader =
        headerLabel != null && headerLabel.trim().isNotEmpty
        ? headerLabel.trim()
        : (isOwn
              ? (isToken ? r'Sent $DIASPORA' : 'Sent Points')
              : (isConversion
                    ? r'DSP Converted to $DIASPORA'
                    : (isToken ? r'Received $DIASPORA' : 'Received Points')));

    final resolvedFooter =
        footerLabel != null && footerLabel.trim().isNotEmpty
        ? footerLabel.trim()
        : (isConversion ? '100% PoH Conversion Confirmed' : 'Transfer Confirmed');

    return Container(
      width: hasRichConversionBody ? 292 : 240,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isOwn
            ? colorScheme.primaryContainer.withValues(alpha: 0.9)
            : colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
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
                  isOwn
                      ? LucideIcons.send
                      : (isConversion
                            ? LucideIcons.sparkles
                            : LucideIcons.download),
                  size: 16,
                  color: accentColor,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  resolvedHeader,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: isOwn
                        ? colorScheme.onPrimaryContainer
                        : colorScheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Amount — colored by asset type
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: Text(
                  isConversion ? '+${_formatAmount(amount)}' : _formatAmount(amount),
                  style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.bold,
                    color: accentColor,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                isToken ? r'$DIASPORA' : 'DSP',
                style: TextStyle(
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
              Expanded(
                child: Text(
                  resolvedFooter,
                  style: TextStyle(
                    fontSize: 12,
                    color: isOwn
                        ? colorScheme.onPrimaryContainer.withValues(alpha: 0.7)
                        : colorScheme.onSurfaceVariant,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (txHash != null && txHash.isNotEmpty) ...[
                const SizedBox(width: 6),
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
                        style: TextStyle(
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

          if (explanationText != null && explanationText.trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              explanationText.trim(),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: isOwn
                    ? colorScheme.onPrimaryContainer
                    : colorScheme.onSurface,
                height: 1.45,
              ),
            ),
          ],

          if (nextTaskBody != null && nextTaskBody.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        LucideIcons.compass,
                        size: 14,
                        color: accentColor,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          (nextTaskTitle != null &&
                                  nextTaskTitle.trim().isNotEmpty)
                              ? nextTaskTitle.trim()
                              : r'Next PoH Task to Earn More $DIASPORA',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: accentColor,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    nextTaskBody.trim(),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurface,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ],

          if (hasAiActions) AiAgentActionsSection(message: message),
        ],
      ),
    );
  }
}
