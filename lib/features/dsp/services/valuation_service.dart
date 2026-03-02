import 'package:flutter_riverpod/flutter_riverpod.dart';

final valuationServiceProvider = Provider((ref) => ValuationService(ref));

class ValuationService {
  final Ref _ref;

  ValuationService(this._ref);

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
  double calculatePublicProjection(double internalPrice, {double multiplier = 3.5}) {
    return internalPrice * multiplier;
  }

  /// Calculates the velocity based on recent transaction volume vs supply.
  double calculateVelocity(int periodGdp, int supply) {
    if (supply <= 0) return 0.0;
    return periodGdp / supply;
  }
}
