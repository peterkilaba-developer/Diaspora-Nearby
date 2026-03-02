import 'package:flutter/material.dart';
import 'package:diaspora_nearby/features/marketplace/utils/currency_helper.dart';

/// A reusable widget that displays a price in the seller/lister's local
/// currency and lets the buyer/viewer toggle to see the equivalent in
/// *their* host-country currency.
///
/// If both parties share the same currency (e.g. two users both in Nigeria),
/// only the primary price is shown and the toggle is hidden.
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
class CurrencyPriceDisplay extends StatefulWidget {
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
  /// show both prices stacked (useful in detail screens).
  final bool showToggle;

  /// If true, uses a more compact layout for list cards.
  final bool compact;

  @override
  State<CurrencyPriceDisplay> createState() => _CurrencyPriceDisplayState();
}

class _CurrencyPriceDisplayState extends State<CurrencyPriceDisplay> {
  bool _showConverted = false;

  bool get _sameCurrency => CurrencyHelper.isSameCurrency(
      widget.sellerCountryCode, widget.viewerCountryCode);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final primaryText =
        '${CurrencyHelper.formatLocalPrice(widget.amount, widget.sellerCountryCode)}${widget.priceSuffix ?? ''}';

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
          ? Colors.white.withOpacity(0.5)
          : Colors.black.withOpacity(0.45),
    );

    // If same currency, just show the primary price
    if (_sameCurrency) {
      return Text(primaryText, style: widget.primaryStyle ?? defaultPrimary);
    }

    final convertedText =
        '≈ ${CurrencyHelper.formatConvertedPrice(widget.amount, widget.sellerCountryCode, widget.viewerCountryCode)}${widget.priceSuffix ?? ''}';

    // Toggle mode – tap to switch between seller and buyer currency
    if (widget.showToggle) {
      return GestureDetector(
        onTap: () => setState(() => _showConverted = !_showConverted),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: Text(
                _showConverted ? convertedText : primaryText,
                key: ValueKey(_showConverted),
                style: widget.primaryStyle ?? defaultPrimary,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.swap_horiz_rounded,
              size: widget.compact ? 14 : 16,
              color: isDark
                  ? Colors.white.withOpacity(0.35)
                  : Colors.black.withOpacity(0.25),
            ),
          ],
        ),
      );
    }

    // Stacked mode – show both prices at once (for detail screens)
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(primaryText, style: widget.primaryStyle ?? defaultPrimary),
        const SizedBox(height: 2),
        Text(convertedText, style: widget.secondaryStyle ?? defaultSecondary),
      ],
    );
  }
}
