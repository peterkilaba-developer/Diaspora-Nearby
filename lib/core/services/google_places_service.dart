import 'package:geocoding/geocoding.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';
import 'package:diaspora_nearby/config/env.dart';
import 'package:uuid/uuid.dart';
import 'package:diaspora_nearby/features/shared/models/google_places_models.dart';
import 'package:diaspora_nearby/core/utils/location_utils.dart';

class GooglePlacesService {
  String? _sessionToken;
  final Uuid _uuid = const Uuid();

  GooglePlacesService(String apiKey);

  /// Generates a new session token if one doesn't exist
  void _ensureSessionToken() {
    _sessionToken ??= _uuid.v4();
  }

  /// Clears the session token after a successful place selection (Place Details)
  void _clearSessionToken() {
    _sessionToken = null;
  }

  Future<List<AutocompletePrediction>> autocomplete(
    String input, {
    PlaceTypeFilter? filter,
  }) async {
    if (input.isEmpty) return [];
    // FALLBACK: Use HTTP directly for Autocomplete to support Session Tokens and avoid native issues
    return _findAutocompletePredictionsHttp(input, filter: filter);
  }

  Future<List<AutocompletePrediction>> _findAutocompletePredictionsHttp(
    String input, {
    PlaceTypeFilter? filter,
  }) async {
    try {
      _ensureSessionToken();
      final apiKey = Env.googleMapsApiKey;

      // Default to cities to enforce strict locality/city-level matching if no filter provided
      // For VENUES, we don't pass a 'types' param (fetch all), but we filter client-side.
      String? requestTypes;
      if (filter == null || filter == PlaceTypeFilter.CITIES) {
        requestTypes = '(cities)';
      } else if (filter == PlaceTypeFilter.REGIONS) {
        requestTypes = '(regions)';
      } else if (filter == PlaceTypeFilter.ADDRESS) {
        requestTypes = 'address';
      } else if (filter == PlaceTypeFilter.ESTABLISHMENT) {
        requestTypes = 'establishment';
      } else if (filter == PlaceTypeFilter.GEOCODE) {
        requestTypes = 'geocode';
      } else if (filter == PlaceTypeFilter.SCHOOLS) {
        requestTypes = 'school|university';
      }
      // For VENUES, we leave requestTypes as null to fetch everything, then filter in code

      var urlString =
          'https://maps.googleapis.com/maps/api/place/autocomplete/json?input=$input&key=$apiKey&sessiontoken=$_sessionToken';
      if (requestTypes != null) {
        urlString += '&types=$requestTypes';
      }

      final url = Uri.parse(urlString);
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        if (data['status'] == 'OK' && data['predictions'] != null) {
          final predictions = (data['predictions'] as List).map((p) {
            return AutocompletePrediction(
              placeId: p['place_id'],
              primaryText: p['structured_formatting']?['main_text'] ?? '',
              secondaryText:
                  p['structured_formatting']?['secondary_text'] ?? '',
              fullText: p['description'] ?? '',
              distanceMeters: null,
              placeTypes: (p['types'] as List?)?.cast<String>(),
            );
          }).toList();

          // Apply Client-Side Filtering for VENUES
          if (filter == PlaceTypeFilter.VENUES) {
            return predictions.where((p) {
              final t = p.placeTypes ?? [];
              // Exclude if it is purely a coarse region
              // We want to keep: establishment, premise, street_address, route, geocode (if precise)
              // We want to remove: locality, country, administrative_area_level_X, continent, political (if alone)

              final isCoarse =
                  t.contains('locality') ||
                  t.contains('administrative_area_level_1') ||
                  t.contains('administrative_area_level_2') ||
                  t.contains('country') ||
                  t.contains('continent');

              // If it's coarse, only keep it if it ALSO has specific types (unlikely)
              // But usually 'locality' is just 'locality, political'.
              return !isCoarse;
            }).toList();
          }

          return predictions;
        }
      }
      return [];
    } catch (e) {
      debugPrint('HTTP Autocomplete Error: $e');
      return [];
    }
  }

  Future<FetchPlaceResponse?> getPlaceDetails(String placeId) async {
    // FALLBACK: Use HTTP directly because the native plugin has version conflicts
    // with the latest Google Places Android SDK on some devices (Samsung S22+ etc).
    return _fetchPlaceHttp(placeId);
  }

  /// Manually fetch place details via HTTP to bypass native plugin issues
  Future<FetchPlaceResponse?> _fetchPlaceHttp(String placeId) async {
    try {
      final apiKey = Env.googleMapsApiKey;
      // Pass the session token to link this selection to the search
      final sessionTokenParam = _sessionToken != null
          ? '&sessiontoken=$_sessionToken'
          : '';

      // Request critical fields and rich data
      final fields =
          'formatted_address,geometry,name,place_id,types,address_components,website,international_phone_number,url,rating,user_ratings_total,opening_hours,photos,price_level,editorial_summary';
      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/place/details/json?place_id=$placeId&fields=$fields&key=$apiKey$sessionTokenParam',
      );

      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        if (data['status'] == 'OK' && data['result'] != null) {
          final result = data['result'] as Map<String, dynamic>;

          // Parse LatLng
          LatLng? latLng;
          if (result['geometry'] != null &&
              result['geometry']['location'] != null) {
            final loc = result['geometry']['location'];
            latLng = LatLng(
              lat: (loc['lat'] as num).toDouble(),
              lng: (loc['lng'] as num).toDouble(),
            );
          }

          // Parse Address Components
          List<AddressComponent>? addressComponents;
          if (result['address_components'] != null) {
            addressComponents = (result['address_components'] as List)
                .map(
                  (e) => AddressComponent(
                    name: e['long_name'] ?? '',
                    shortName: e['short_name'] ?? '',
                    types: (e['types'] as List?)?.cast<String>() ?? [],
                  ),
                )
                .toList();
          }

          // [FIX] Use shared location parsing to ensure correct naming conventions (UK etc)
          String cleanAddress = result['formatted_address'] ?? '';
          final fullAddress = cleanAddress;

          if (addressComponents != null) {
            final parsed = parseLocationComponents(
              fullAddress,
              addressComponents,
            );
            if (parsed != null) {
              final parts = <String>[];
              if (parsed.city != null) parts.add(parsed.city!);
              if (parsed.state != null) parts.add(parsed.state!);
              // For UK, parsed.country will be "England", "Scotland" etc.
              parts.add(parsed.country);

              if (parts.isNotEmpty) {
                cleanAddress = parts.toSet().join(', ');
              }
            }
          }

          final place = Place(
            id: result['place_id'],
            name: result['name'],
            address: cleanAddress, // Standardized: City, State, Country
            fullAddress: fullAddress, // [NEW] Full raw address
            latLng: latLng,
            addressComponents: addressComponents,
            types: (result['types'] as List?)?.cast<String>(),
            // Rich Data Mapping
            websiteUri: result['website'] != null
                ? Uri.tryParse(result['website'])
                : null,
            phoneNumber: result['international_phone_number'],
            rating: result['rating'] != null
                ? (result['rating'] as num).toDouble()
                : null,
            userRatingsTotal: result['user_ratings_total'] as int?,
            openingHours: result['opening_hours'], // Keep as dynamic map
            photoMetadatas: result['photos'], // Keep as dynamic list
            priceLevel: result['price_level'] as int?,
            editorialSummary: result['editorial_summary']?['overview'],

            // Defaults for others
            attributions: [],
            businessStatus: null,
            nameLanguageCode: null,
            plusCode: null,
            utcOffsetMinutes: null,
            viewport: null,
            reviews: null,
          );

          // Clear session token on success to start a fresh session next time
          _clearSessionToken();

          return FetchPlaceResponse(place);
        }
      }
      return null;
    } catch (e) {
      debugPrint('HTTP Fetch Place Error: $e');
      return null;
    }
  }

  /// Reverse geocode: convert lat/lng to place details
  /// Returns structured location data including city, state, country, countryCode
  Future<Map<String, dynamic>?> reverseGeocode(double lat, double lng) async {
    try {
      final placemarks = await placemarkFromCoordinates(lat, lng);

      if (placemarks.isEmpty) {
        return null;
      }

      final place = placemarks.first;
      final countryCode = place.isoCountryCode?.toUpperCase();

      String? country;
      if (countryCode != null) {
        final countryNames = {
          'US': 'United States',
          'TZ': 'Tanzania',
          'GB': 'United Kingdom',
          'CA': 'Canada',
          'AU': 'Australia',
          'IN': 'India',
          'CN': 'China',
          'JP': 'Japan',
          'BR': 'Brazil',
          'MX': 'Mexico',
          'DE': 'Germany',
          'FR': 'France',
          'IT': 'Italy',
        };
        country = countryNames[countryCode] ?? place.country;
      } else {
        country = place.country;
      }

      final city = place.locality ?? place.subAdministrativeArea;
      final state = place.administrativeArea;

      final formattedAddress = [
        ?city,
        ?state,
        ?country,
      ].join(', ');

      return {
        'formattedAddress': formattedAddress,
        'placeId': '',
        'city': city,
        'state': state,
        'country': country,
        'countryCode': countryCode,
        'lat': lat,
        'lng': lng,
      };
    } catch (e) {
      return null;
    }
  }
}

final googlePlacesServiceProvider = Provider((ref) {
  return GooglePlacesService(Env.googleMapsApiKey);
});
