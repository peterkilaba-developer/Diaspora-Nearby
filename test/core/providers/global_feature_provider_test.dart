import 'package:diaspora_nearby/core/providers/global_feature_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('evaluateGlobalUnlock', () {
    const required = ['US', 'KE', 'BR'];

    test('unlocks only when every required country is represented', () {
      final stats = evaluateGlobalUnlock([
        'us',
        ' KE ',
        'BR',
      ], requiredCountryCodes: required);

      expect(stats.isUnlocked, isTrue);
      expect(stats.registeredCount, 3);
      expect(stats.totalRequired, 3);
    });

    test('does not let invalid codes substitute for a missing country', () {
      final stats = evaluateGlobalUnlock([
        'US',
        'KE',
        'XX',
        'ZZ',
      ], requiredCountryCodes: required);

      expect(stats.isUnlocked, isFalse);
      expect(stats.registeredCount, 2);
    });

    test('deduplicates country codes', () {
      final stats = evaluateGlobalUnlock([
        'US',
        'us',
        'KE',
        'KE',
      ], requiredCountryCodes: required);

      expect(stats.isUnlocked, isFalse);
      expect(stats.registeredCount, 2);
    });
  });
}
