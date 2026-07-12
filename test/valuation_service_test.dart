/// Unit tests for the DSP dynamic valuation formula.
///
/// Run with: dart test test/valuation_service_test.dart
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:diaspora_nearby/features/dsp/services/valuation_service.dart';

void main() {
  late ValuationService service;

  setUp(() {
    service = ValuationService();
  });

  group('calculateImpliedValue', () {
    test('returns base price with zero activity', () {
      final result = service.calculateImpliedValue(
        totalUsers: 0,
        totalMinted: 0,
        totalBurned: 0,
        currentEpoch: 1,
        fiatGdpUsd: 0.0,
      );

      // With 0 users, 0 burned, epoch 1, 0 GDP:
      // value = 0.001 × (1 + 0 + 0) × 1.1 × 1.0 = 0.0011
      expect(result.impliedValueUsd, closeTo(0.0011, 0.0001));
      expect(result.basePriceUsd, 0.001);
      expect(result.networkMultiplier, 0.0);
      expect(result.deflationRatio, 0.0);
      expect(result.epochScarcity, 1.1);
      expect(result.fiatGdpBoost, 1.0);
    });

    test('value never drops below base × epoch × gdp', () {
      final result = service.calculateImpliedValue(
        totalUsers: 1,
        totalMinted: 1000000,
        totalBurned: 0,
        currentEpoch: 1,
        fiatGdpUsd: 0.0,
      );

      // Floor is basePriceUsd × epochScarcity × fiatGdpBoost
      // = 0.001 × 1.1 × 1.0 = 0.0011
      // With 1 user: network = log10(1) / 10 = 0
      // value = 0.001 × (1 + 0 + 0) × 1.1 = 0.0011
      expect(result.impliedValueUsd, greaterThanOrEqualTo(0.001));
    });

    test('increases with more users (network effect)', () {
      final oneUser = service.calculateImpliedValue(
        totalUsers: 1,
        totalMinted: 100000,
        totalBurned: 0,
        currentEpoch: 1,
        fiatGdpUsd: 0.0,
      );

      final thousandUsers = service.calculateImpliedValue(
        totalUsers: 1000,
        totalMinted: 100000,
        totalBurned: 0,
        currentEpoch: 1,
        fiatGdpUsd: 0.0,
      );

      expect(
        thousandUsers.impliedValueUsd,
        greaterThan(oneUser.impliedValueUsd),
      );
      expect(
        thousandUsers.networkMultiplier,
        greaterThan(oneUser.networkMultiplier),
      );
    });

    test('increases with more burn (deflation)', () {
      final noBurn = service.calculateImpliedValue(
        totalUsers: 100,
        totalMinted: 100000,
        totalBurned: 0,
        currentEpoch: 1,
        fiatGdpUsd: 0.0,
      );

      final someBurn = service.calculateImpliedValue(
        totalUsers: 100,
        totalMinted: 100000,
        totalBurned: 10000,
        currentEpoch: 1,
        fiatGdpUsd: 0.0,
      );

      expect(someBurn.impliedValueUsd, greaterThan(noBurn.impliedValueUsd));
      expect(someBurn.deflationRatio, greaterThan(0.0));
    });

    test('deflation ratio capped at 0.5', () {
      final extreme = service.calculateImpliedValue(
        totalUsers: 100,
        totalMinted: 100,
        totalBurned: 90, // 90% burned — should be capped at 0.5
        currentEpoch: 1,
        fiatGdpUsd: 0.0,
      );

      expect(extreme.deflationRatio, 0.5);
    });

    test('increases with higher epoch (scarcity)', () {
      final epoch1 = service.calculateImpliedValue(
        totalUsers: 100,
        totalMinted: 100000,
        totalBurned: 0,
        currentEpoch: 1,
        fiatGdpUsd: 0.0,
      );

      final epoch5 = service.calculateImpliedValue(
        totalUsers: 100,
        totalMinted: 100000,
        totalBurned: 0,
        currentEpoch: 5,
        fiatGdpUsd: 0.0,
      );

      expect(epoch5.impliedValueUsd, greaterThan(epoch1.impliedValueUsd));
      expect(epoch5.epochScarcity, 1.5);
      expect(epoch1.epochScarcity, 1.1);
    });

    test('increases with fiat GDP activity', () {
      final noGdp = service.calculateImpliedValue(
        totalUsers: 100,
        totalMinted: 100000,
        totalBurned: 0,
        currentEpoch: 1,
        fiatGdpUsd: 0.0,
      );

      final withGdp = service.calculateImpliedValue(
        totalUsers: 100,
        totalMinted: 100000,
        totalBurned: 0,
        currentEpoch: 1,
        fiatGdpUsd: 10000.0,
      );

      expect(withGdp.impliedValueUsd, greaterThan(noGdp.impliedValueUsd));
      expect(withGdp.fiatGdpBoost, greaterThan(1.0));
    });

    test('all factors contribute multiplicatively', () {
      final result = service.calculateImpliedValue(
        totalUsers: 10000,
        totalMinted: 500000,
        totalBurned: 50000,
        currentEpoch: 3,
        fiatGdpUsd: 50000.0,
      );

      // All factors should be active
      expect(result.networkMultiplier, greaterThan(0));
      expect(result.deflationRatio, greaterThan(0));
      expect(result.epochScarcity, 1.3); // epoch 3: 1 + 0.3
      expect(result.fiatGdpBoost, greaterThan(1.0));
      // Value should be meaningfully above base
      expect(result.impliedValueUsd, greaterThan(0.001));
    });
  });

  group('DspValuation formatting', () {
    test('formatBalance shows correct dollar estimate', () {
      final valuation = service.calculateImpliedValue(
        totalUsers: 100,
        totalMinted: 100000,
        totalBurned: 0,
        currentEpoch: 1,
        fiatGdpUsd: 0.0,
      );

      final formatted = valuation.formatBalance(5000);
      expect(formatted, contains('≈'));
      expect(formatted, contains('est.'));
      expect(formatted, contains('\$'));
    });

    test('formattedImpliedValue includes dollar sign', () {
      final valuation = service.calculateImpliedValue(
        totalUsers: 100,
        totalMinted: 100000,
        totalBurned: 0,
        currentEpoch: 1,
        fiatGdpUsd: 0.0,
      );

      expect(valuation.formattedImpliedValue, startsWith('\$'));
    });

    test('estimatedValue multiplies correctly', () {
      final valuation = service.calculateImpliedValue(
        totalUsers: 0,
        totalMinted: 0,
        totalBurned: 0,
        currentEpoch: 1,
        fiatGdpUsd: 0.0,
      );

      // 1000 DSP × impliedValue
      final est = valuation.estimatedValue(1000);
      expect(est, closeTo(valuation.impliedValueUsd * 1000, 0.001));
    });
  });

  group('Legacy methods still work', () {
    test('calculateInternalPrice returns 0 for 0 supply', () {
      expect(service.calculateInternalPrice(gdp: 1000, supply: 0), 0.0);
    });

    test('calculateInternalPrice computes correctly', () {
      final price = service.calculateInternalPrice(gdp: 10000, supply: 1000);
      expect(price, 10.0); // 10000 / 1000
    });

    test('calculateVelocity returns 0 for 0 supply', () {
      expect(service.calculateVelocity(1000, 0), 0.0);
    });
  });
}
