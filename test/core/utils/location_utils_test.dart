import 'package:flutter_test/flutter_test.dart';
import 'package:diaspora_nearby/core/utils/location_utils.dart' as location_utils;

void main() {
  group('Distance Formatting Tests (Whole Numbers)', () {
    test('Metric: Less than 1 km should show meters', () {
      expect(location_utils.formatDistance(0.5), '500 m');
      expect(location_utils.formatDistance(0.1), '100 m');
    });

    test('Metric: 1 km or more should show whole km', () {
      expect(location_utils.formatDistance(1.0), '1 km');
      expect(location_utils.formatDistance(1.2), '1 km');
      expect(location_utils.formatDistance(1.5), '2 km');
      expect(location_utils.formatDistance(9.4), '9 km');
      expect(location_utils.formatDistance(10.0), '10 km');
      expect(location_utils.formatDistance(15.7), '16 km');
    });
  });
}
