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

  /// Direct fiat GDP contribution per token (Total Fiat GDP ÷ Circulating Supply).
  final double gdpFloorPerToken;

  /// Legacy factor multiplier equivalent for backward compatibility.
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
    required this.gdpFloorPerToken,
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

  /// Calculates the dynamic implied value / price floor of 1 DSP.
  ///
  /// Formula:
  /// ```
  /// Dynamic Price Floor = [basePriceUSD × (1 + networkMultiplier + deflationRatio) × epochScarcity]
  ///                     + (fiatGdpUsd / circulatingSupply)
  /// ```
  DspValuation calculateImpliedValue({
    required int totalUsers,
    required int totalMinted,
    required int totalBurned,
    required int currentEpoch,
    required double fiatGdpUsd,
    int circulatingSupply = 0,
  }) {
    // --- Factor 1: Network Effect ---
    final double networkMultiplier = totalUsers > 0
        ? log(max(totalUsers, 1).toDouble()) / (ln10 * 10)
        : 0.0;

    // --- Factor 2: Deflation Ratio ---
    final double rawDeflation = totalMinted > 0
        ? totalBurned / totalMinted.toDouble()
        : 0.0;
    final double deflationRatio = min(rawDeflation, 0.5);

    // --- Factor 3: Epoch Scarcity ---
    final double epochScarcity = 1.0 + (max(currentEpoch, 1) * 0.1);

    // --- Network Baseline Valuation ---
    final double networkBaseline =
        basePriceUsd *
        (1.0 + networkMultiplier + deflationRatio) *
        epochScarcity;

    // --- Factor 4: Additive Fiat GDP Floor per Token ---
    final int effectiveCirculating = circulatingSupply > 0
        ? circulatingSupply
        : max(totalMinted - totalBurned, 0);

    final double gdpFloorPerToken = (effectiveCirculating > 0 && fiatGdpUsd > 0)
        ? fiatGdpUsd / effectiveCirculating.toDouble()
        : 0.0;

    // --- Composite Dynamic Price Floor ---
    final double impliedValue = networkBaseline + gdpFloorPerToken;

    final double fiatGdpBoost = networkBaseline > 0
        ? 1.0 + (gdpFloorPerToken / networkBaseline)
        : 1.0;

    return DspValuation(
      impliedValueUsd: impliedValue,
      basePriceUsd: basePriceUsd,
      networkMultiplier: networkMultiplier,
      deflationRatio: deflationRatio,
      epochScarcity: epochScarcity,
      gdpFloorPerToken: gdpFloorPerToken,
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
