import 'dart:math';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

final valuationServiceProvider = Provider((ref) => ValuationService());

/// Holds the computed DSP implied valuation and supporting factor breakdown.
class DspValuation {
  /// The estimated value of 1 DSP in USD.
  final double impliedValueUsd;

  /// The base price constant (currently $0.001).
  final double basePriceUsd;

  /// Individual factor contributions.
  final double networkMultiplier;
  final double deflationRatio;
  final double epochScarcity;
  final double fiatGdpBoost;

  /// Raw inputs used in calculation (for display).
  final int totalUsers;
  final int totalMinted;
  final int totalBurned;
  final int currentEpoch;
  final double fiatGdpUsd;

  /// When this valuation was computed.
  final DateTime calculatedAt;

  const DspValuation({
    required this.impliedValueUsd,
    required this.basePriceUsd,
    required this.networkMultiplier,
    required this.deflationRatio,
    required this.epochScarcity,
    required this.fiatGdpBoost,
    required this.totalUsers,
    required this.totalMinted,
    required this.totalBurned,
    required this.currentEpoch,
    required this.fiatGdpUsd,
    required this.calculatedAt,
  });

  /// Convenience: estimated dollar value of a given DSP balance.
  double estimatedValue(int dspBalance) => impliedValueUsd * dspBalance;

  /// Formatted: "$0.00112"
  String get formattedImpliedValue {
    if (impliedValueUsd < 0.01) {
      return '\$${impliedValueUsd.toStringAsFixed(5)}';
    } else if (impliedValueUsd < 1.0) {
      return '\$${impliedValueUsd.toStringAsFixed(4)}';
    } else {
      return '\$${impliedValueUsd.toStringAsFixed(2)}';
    }
  }

  /// Formatted: "≈ $5.00 est."
  String formatBalance(int dspBalance) {
    final value = estimatedValue(dspBalance);
    if (value < 0.01) {
      return '≈ \$${value.toStringAsFixed(5)} est.';
    } else if (value < 1.0) {
      return '≈ \$${value.toStringAsFixed(4)} est.';
    } else {
      return '≈ \$${NumberFormat('#,##0.00').format(value)} est.';
    }
  }
}

class ValuationService {
  /// The fixed base price for 1 DSP.
  static const double basePriceUsd = 0.001;

  ValuationService();

  /// Calculates the dynamic implied value of 1 DSP based on platform metrics.
  ///
  /// Formula:
  /// ```
  /// impliedValue = basePriceUSD × (1 + networkMultiplier + deflationRatio)
  ///                             × epochScarcity
  ///                             × fiatGdpBoost
  /// ```
  ///
  /// Each factor only pushes the value UP — it can never drop below the
  /// base price × epochScarcity × fiatGdpBoost.
  DspValuation calculateImpliedValue({
    required int totalUsers,
    required int totalMinted,
    required int totalBurned,
    required int currentEpoch,
    required double fiatGdpUsd,
  }) {
    // --- Factor 1: Network Effect ---
    // Logarithmic growth — slow at first, increasingly valuable with each
    // order-of-magnitude increase in users.
    final double networkMultiplier = totalUsers > 0
        ? log(max(totalUsers, 1).toDouble()) / (ln10 * 10)
        : 0.0;

    // --- Factor 2: Deflation Ratio ---
    // Rewards burn activity. As more DSP is burned, scarcity increases.
    // Capped at 0.5 to prevent a single large burn from dominating.
    final double rawDeflation = totalMinted > 0
        ? totalBurned / totalMinted.toDouble()
        : 0.0;
    final double deflationRatio = min(rawDeflation, 0.5);

    // --- Factor 3: Epoch Scarcity ---
    // Each epoch adds a 10% premium, reflecting the progressive scarcity
    // of later-epoch DSP.
    final double epochScarcity = 1.0 + (max(currentEpoch, 1) * 0.1);

    // --- Factor 4: Fiat GDP Boost ---
    // Real economic activity (marketplace, travel, remittances) adds a
    // bonus. Logarithmic scale prevents extreme spikes.
    final double fiatGdpBoost = fiatGdpUsd > 0
        ? 1.0 + log(max(fiatGdpUsd, 1.0)) / (ln10 * 10)
        : 1.0;

    // --- Composite ---
    final double impliedValue =
        basePriceUsd *
        (1.0 + networkMultiplier + deflationRatio) *
        epochScarcity *
        fiatGdpBoost;

    return DspValuation(
      impliedValueUsd: impliedValue,
      basePriceUsd: basePriceUsd,
      networkMultiplier: networkMultiplier,
      deflationRatio: deflationRatio,
      epochScarcity: epochScarcity,
      fiatGdpBoost: fiatGdpBoost,
      totalUsers: totalUsers,
      totalMinted: totalMinted,
      totalBurned: totalBurned,
      currentEpoch: currentEpoch,
      fiatGdpUsd: fiatGdpUsd,
      calculatedAt: DateTime.now(),
    );
  }

  // ---------------------------------------------------------------------------
  // Legacy methods (kept for backward compatibility)
  // ---------------------------------------------------------------------------

  /// Calculates the Internal Price Index based on the Equation of Exchange (MV = PQ).
  /// Formula: Price = (GDP / Supply) / Velocity_Adjustment
  double calculateInternalPrice({
    required int gdp,
    required int supply,
    double velocityAdj = 1.0,
  }) {
    if (supply <= 0) return 0.0;

    // Base valuation: GDP per token
    double basePrice = gdp / supply;

    // Velocity adjustment: Lower velocity (higher holding) increases price
    return basePrice / velocityAdj;
  }

  /// Calculates the "Public Projection" price which includes a speculative premium.
  /// Historically, network value often trades at a 3x-10x premium to daily utility.
  double calculatePublicProjection(
    double internalPrice, {
    double multiplier = 3.5,
  }) {
    return internalPrice * multiplier;
  }

  /// Calculates the velocity based on recent transaction volume vs supply.
  double calculateVelocity(int periodGdp, int supply) {
    if (supply <= 0) return 0.0;
    return periodGdp / supply;
  }
}
