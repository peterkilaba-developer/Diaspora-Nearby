import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:diaspora_nearby/features/dsp/providers/dsp_valuation_provider.dart';
import 'package:diaspora_nearby/features/marketplace/utils/currency_helper.dart';

/// A reusable widget that displays a price in:
/// 1. The seller/lister's local currency
/// 2. The buyer/viewer's host-country currency (when different from seller's)
/// 3. The `$DIASPORA` token equivalent based on the live dynamic price floor
///
/// When [showToggle] is true, tapping cycles through Seller currency →
/// Buyer currency (if different) → `$DIASPORA` token.
/// When [showToggle] is false, all applicable prices are displayed together.
///
/// Usage:
/// ```dart
/// CurrencyPriceDisplay(
///   amount: listing.priceAmount,
///   sellerCountryCode: listing.sellerCountryCode ?? listing.countryCode,
///   viewerCountryCode: profile.hostCountryCode,
///   priceSuffix: '/night',  // optional
/// )
/// ```
class CurrencyPriceDisplay extends ConsumerStatefulWidget {
  const CurrencyPriceDisplay({
    super.key,
    required this.amount,
    required this.sellerCountryCode,
    required this.viewerCountryCode,
    this.priceSuffix,
    this.primaryStyle,
    this.secondaryStyle,
    this.primaryColor,
    this.showToggle = true,
    this.compact = false,
  });

  /// The raw price amount (in the seller's local currency).
  final double amount;

  /// Country code of the seller / lister (determines the listed price symbol).
  final String? sellerCountryCode;

  /// Country code of the viewer / buyer (determines the converted price symbol).
  final String? viewerCountryCode;

  /// Optional suffix like "/night", "/day", "/mo".
  final String? priceSuffix;

  /// Override the primary price text style.
  final TextStyle? primaryStyle;

  /// Override the secondary (converted) price text style.
  final TextStyle? secondaryStyle;

  /// Accent colour for the primary price (defaults to the caller's accent).
  final Color? primaryColor;

  /// Whether to show the tap-toggle for conversion. Set false to always
  /// show all prices stacked (useful in detail screens).
  final bool showToggle;

  /// If true, uses a more compact layout for list cards.
  final bool compact;

  @override
  ConsumerState<CurrencyPriceDisplay> createState() =>
      _CurrencyPriceDisplayState();
}

class _CurrencyPriceDisplayState extends ConsumerState<CurrencyPriceDisplay> {
  /// 0 = Seller currency, 1 = Buyer currency (or $DIASPORA if same), 2 = $DIASPORA
  int _modeIndex = 0;

  bool get _sameCurrency =>
      widget.viewerCountryCode == null ||
      CurrencyHelper.isSameCurrency(
        widget.sellerCountryCode,
        widget.viewerCountryCode,
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final valuation = ref.watch(dspValuationProvider);
    final suffix = widget.priceSuffix ?? '';

    final primaryText =
        '${CurrencyHelper.formatLocalPrice(widget.amount, widget.sellerCountryCode)}$suffix';

    final convertedText =
        '≈ ${CurrencyHelper.formatConvertedPrice(widget.amount, widget.sellerCountryCode, widget.viewerCountryCode)}$suffix';

    final tokenText =
        '≈ ${CurrencyHelper.formatDiasporaTokenPrice(widget.amount, widget.sellerCountryCode, dspPriceFloorUsd: valuation.impliedValueUsd)}$suffix';

    // Default styles
    final defaultPrimary = TextStyle(
      fontSize: widget.compact ? 14 : 15,
      fontWeight: FontWeight.bold,
      color: widget.primaryColor ?? theme.colorScheme.primary,
    );

    final defaultSecondary = TextStyle(
      fontSize: widget.compact ? 11 : 12,
      fontWeight: FontWeight.w500,
      color: isDark
          ? Colors.white.withValues(alpha: 0.5)
          : Colors.black.withValues(alpha: 0.45),
    );

    final modes = _sameCurrency
        ? <String>[primaryText, tokenText]
        : <String>[primaryText, convertedText, tokenText];

    final activeIdx = _modeIndex % modes.length;

    // Toggle mode – tap to cycle Seller → Buyer → $DIASPORA
    if (widget.showToggle) {
      return GestureDetector(
        onTap: () => setState(() => _modeIndex = (_modeIndex + 1) % modes.length),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: Text(
                  modes[activeIdx],
                  key: ValueKey(activeIdx),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: widget.primaryStyle ?? defaultPrimary,
                ),
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.swap_horiz_rounded,
              size: widget.compact ? 14 : 16,
              color: isDark
                  ? Colors.white.withValues(alpha: 0.35)
                  : Colors.black.withValues(alpha: 0.25),
            ),
          ],
        ),
      );
    }

    // Stacked mode – show Seller currency, Buyer currency, and $DIASPORA token
    final subParts = <String>[
      if (!_sameCurrency) convertedText,
      tokenText,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          primaryText,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: widget.primaryStyle ?? defaultPrimary,
        ),
        SizedBox(height: widget.compact ? 1 : 2),
        Text(
          subParts.join('  ·  '),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: widget.secondaryStyle ?? defaultSecondary,
        ),
      ],
    );
  }
}
