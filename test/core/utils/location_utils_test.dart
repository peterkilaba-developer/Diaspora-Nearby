import 'package:flutter_test/flutter_test.dart';
import 'package:diaspora_nearby/core/utils/location_utils.dart'
    as location_utils;
import 'package:diaspora_nearby/features/shared/models/google_places_models.dart';
import 'package:diaspora_nearby/features/real_estate/models/real_estate_listing.dart';

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

  group('Two-Tier vs Three-Tier Location Formatting', () {
    test('Detects redundant spelling variants like Dar es Salaam vs Dar es Salam', () {
      expect(
        location_utils.isSameOrRedundantLocationPart(
          'Dar es Salaam',
          'Dar es Salam',
        ),
        isTrue,
      );
      expect(
        location_utils.isSameOrRedundantLocationPart(
          'Mwanza',
          'Mwanza Region',
        ),
        isTrue,
      );
    });

    test('Two-tier countries (e.g. Tanzania) omit state level', () {
      expect(
        location_utils.sanitizeStateForCountry(
          state: 'Dar es Salam',
          city: 'Dar es Salaam',
          countryCode: 'TZ',
          countryName: 'Tanzania',
        ),
        isNull,
      );
      expect(
        location_utils.formatTieredLocation(
          city: 'Dar es Salaam',
          state: 'Dar es Salam',
          country: 'Tanzania',
          countryCode: 'TZ',
        ),
        'Dar es Salaam, Tanzania',
      );
    });

    test('Three-tier countries (e.g. United States) preserve state level', () {
      expect(
        location_utils.formatTieredLocation(
          city: 'Houston',
          state: 'TX',
          country: 'United States',
          countryCode: 'US',
        ),
        'Houston, Texas, United States',
      );
    });

    test('parseLocationComponents extracts street, sublocality, city and strips 2-tier state', () {
      final parsed = location_utils.parseLocationComponents(
        'Ohio St, Dar es Salaam, Tanzania',
        [
          AddressComponent(
            name: 'Ohio St',
            shortName: 'Ohio St',
            types: ['route'],
          ),
          AddressComponent(
            name: 'Dar es Salaam',
            shortName: 'Dar es Salaam',
            types: ['locality', 'political'],
          ),
          AddressComponent(
            name: 'Ilala',
            shortName: 'Ilala',
            types: ['administrative_area_level_2', 'political'],
          ),
          AddressComponent(
            name: 'Dar es Salam',
            shortName: 'Dar es Salam',
            types: ['administrative_area_level_1', 'political'],
          ),
          AddressComponent(
            name: 'Tanzania',
            shortName: 'TZ',
            types: ['country', 'political'],
          ),
        ],
      );

      expect(parsed, isNotNull);
      expect(parsed!.streetAddress, 'Ohio St');
      expect(parsed.sublocality, 'Ilala');
      expect(parsed.city, 'Dar es Salaam');
      expect(parsed.state, isNull);
      expect(parsed.country, 'Tanzania');
      expect(parsed.countryCode, 'TZ');
    });

    test('RealEstateListing.fromJson sanitizes 2-tier title and locationLabel', () {
      final listing = RealEstateListing.fromJson({
        'category': 'plot',
        'ownerId': 'u1',
        'ownerName': 'Teddy Prosper',
        'title': '0 m² Plot for Sale in Dar es Salaam, Dar es Salam',
        'description': 'Residential',
        'price': 200000,
        'currency': 'TZS',
        'city': 'Dar es Salaam',
        'locality': 'Dar es Salaam',
        'state': 'Dar es Salam',
        'country': 'Tanzania',
        'countryCode': 'TZ',
      }, 'doc1');

      expect(listing.title, '0 m² Plot for Sale in Dar es Salaam');
      expect(listing.state, isNull);
      expect(listing.locationLabel, 'Dar es Salaam');
    });
  });
}
