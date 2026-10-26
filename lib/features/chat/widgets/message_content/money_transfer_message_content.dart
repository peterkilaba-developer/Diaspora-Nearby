import 'package:flutter/material.dart';
import 'package:diaspora_nearby/features/chat/models/message.dart';
import 'package:diaspora_nearby/features/marketplace/utils/currency_helper.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:diaspora_nearby/theme/app_theme.dart';

class MoneyTransferMessageContent extends StatelessWidget {
  final Message message;
  final bool isOwn;

  const MoneyTransferMessageContent({
    super.key,
    required this.message,
    required this.isOwn,
  });

  @override
  Widget build(BuildContext context) {
    final metadata = message.metadata ?? {};
    final amount = (metadata['amount'] as num?)?.toDouble() ?? 0.0;
    final currency = metadata['currency'] as String? ?? 'USD';
    final convertedAmount =
        (metadata['convertedAmount'] as num?)?.toDouble() ?? 0.0;
    final convertedCurrency =
        metadata['convertedCurrency'] as String? ?? currency;
    final exchangeRate = (metadata['exchangeRate'] as num?)?.toDouble() ?? 1.0;
    final deliveryMethod =
        metadata['deliveryMethod'] as String? ?? 'Mobile / Bank Settlement';

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final accentColor = AppTheme.fiatColor;

    final isSameCurrency = currency == convertedCurrency;

    return Container(
      width: 260,
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
          // ─── Header: Icon + Label ───
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
              Expanded(
                child: Text(
                  isOwn ? 'Sent Remittance' : 'Received Remittance',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: isOwn
                        ? colorScheme.onPrimaryContainer
                        : colorScheme.onSurface,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '0% Fee',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: accentColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // ─── Primary Amount ───
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                CurrencyHelper.formatFiatAmount(amount),
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: accentColor,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                currency,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: accentColor.withValues(alpha: 0.85),
                ),
              ),
            ],
          ),

          // ─── Converted Amount (if different currency) ───
          if (!isSameCurrency && convertedAmount > 0) ...[
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    LucideIcons.repeat,
                    size: 12,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '≈ ${CurrencyHelper.formatFiatAmount(convertedAmount)} $convertedCurrency',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),

          // ─── Divider ───
          Divider(
            height: 1,
            color: isOwn
                ? colorScheme.onPrimaryContainer.withValues(alpha: 0.15)
                : colorScheme.outline.withValues(alpha: 0.15),
          ),
          const SizedBox(height: 10),

          // ─── Status & Actionable Details Button ───
          Row(
            children: [
              Icon(
                LucideIcons.checkCircle2,
                size: 14,
                color: Colors.green.shade600,
              ),
              const SizedBox(width: 6),
              Text(
                'Settled',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: Colors.green.shade700,
                ),
              ),
              const Spacer(),
              InkWell(
                onTap: () => _showRemittanceReceipt(
                  context,
                  amount: amount,
                  currency: currency,
                  convertedAmount: convertedAmount,
                  convertedCurrency: convertedCurrency,
                  exchangeRate: exchangeRate,
                  deliveryMethod: deliveryMethod,
                  isOwn: isOwn,
                ),
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Details',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: accentColor,
                        ),
                      ),
                      const SizedBox(width: 2),
                      Icon(
                        LucideIcons.chevronRight,
                        size: 12,
                        color: accentColor,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showRemittanceReceipt(
    BuildContext context, {
    required double amount,
    required String currency,
    required double convertedAmount,
    required String convertedCurrency,
    required double exchangeRate,
    required String deliveryMethod,
    required bool isOwn,
  }) {
    final theme = Theme.of(context);
    final accentColor = AppTheme.fiatColor;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: theme.scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: accentColor.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        LucideIcons.receipt,
                        color: accentColor,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Remittance Receipt',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'Zero-Fee Diaspora Value Transfer',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(LucideIcons.x, size: 20),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest.withValues(
                      alpha: 0.3,
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    children: [
                      _buildReceiptRow(
                        theme,
                        'Transfer Amount',
                        '${CurrencyHelper.formatFiatAmount(amount, forceDecimals: true)} $currency',
                        isBold: true,
                      ),
                      const SizedBox(height: 10),
                      if (currency != convertedCurrency &&
                          convertedAmount > 0) ...[
                        _buildReceiptRow(
                          theme,
                          'Settlement Amount',
                          '${CurrencyHelper.formatFiatAmount(convertedAmount, forceDecimals: true)} $convertedCurrency',
                          isBold: true,
                        ),
                        const SizedBox(height: 10),
                        _buildReceiptRow(
                          theme,
                          'Exchange Rate',
                          '1 $currency = ${CurrencyHelper.formatFiatAmount(exchangeRate, forceDecimals: true)} $convertedCurrency',
                        ),
                        const SizedBox(height: 10),
                      ],
                      _buildReceiptRow(
                        theme,
                        'Network Fee',
                        'Free (\$0.00 Covered)',
                        valueColor: Colors.green.shade700,
                      ),
                      const SizedBox(height: 10),
                      _buildReceiptRow(
                        theme,
                        'Delivery Method',
                        deliveryMethod,
                      ),
                      const SizedBox(height: 10),
                      _buildReceiptRow(
                        theme,
                        'Status',
                        'Instant Settlement (Completed)',
                        valueColor: Colors.green.shade700,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: accentColor,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Close'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildReceiptRow(
    ThemeData theme,
    String label,
    String value, {
    bool isBold = false,
    Color? valueColor,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        Text(
          value,
          style: theme.textTheme.bodySmall?.copyWith(
            fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
            color: valueColor ?? theme.colorScheme.onSurface,
          ),
        ),
      ],
    );
  }
}
