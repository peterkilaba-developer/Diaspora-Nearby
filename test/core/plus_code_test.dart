import 'package:flutter_test/flutter_test.dart';
import 'package:diaspora_nearby/core/services/plus_code_service.dart';

void main() {
  group('PlusCodeService Tests', () {
    test('isValidPlusCode detects valid full Plus Codes', () {
      expect(PlusCodeService.isValidPlusCode('8FVC9G8F+6W'), isTrue);
      expect(PlusCodeService.isValidPlusCode('9G8F+6W'), isTrue);
      expect(PlusCodeService.isValidPlusCode('8FVC0000+'), isTrue);
    });

    test('isValidPlusCode rejects invalid strings', () {
      expect(PlusCodeService.isValidPlusCode('1234 Main Street'), isFalse);
      expect(PlusCodeService.isValidPlusCode('INVALID_CODE'), isFalse);
      expect(PlusCodeService.isValidPlusCode(''), isFalse);
    });

    test('encode produces expected Plus Code format', () {
      final code = PlusCodeService.encode(37.7749, -122.4194);
      expect(code, contains('+'));
      expect(PlusCodeService.isValidPlusCode(code), isTrue);
    });

    test('decode retrieves latitude and longitude coordinates', () {
      final code = PlusCodeService.encode(40.7128, -74.0060);
      final coords = PlusCodeService.decode(code);

      expect(coords, isNotNull);
      expect(coords!['latitude']!, closeTo(40.7128, 0.05));
      expect(coords['longitude']!, closeTo(-74.0060, 0.05));
    });
  });
}
