import 'package:geocoding/geocoding.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:diaspora_nearby/config/env.dart';
import 'package:uuid/uuid.dart';
import 'package:diaspora_nearby/features/shared/models/google_places_models.dart';
import 'package:diaspora_nearby/core/utils/location_utils.dart';

/// Firebase Cloud Functions base URL for CORS proxy
/// On web, we route Google Places API calls through this proxy
/// because the Places REST API does not support CORS.
String get _placesProxyBaseUrl {
  final projectId = Firebase.app().options.projectId;
  return 'https://us-central1-$projectId.cloudfunctions.net/placesProxy';
}

class GooglePlacesService {
  String? _sessionToken;
  final Uuid _uuid = const Uuid();
  Map<String, String>? _cachedHeaders;
  DateTime? _cachedHeadersAt;
  String? _cachedUid;

  GooglePlacesService(String apiKey);

  Future<Map<String, String>> _proxyHeaders({required bool useProxy}) async {
    if (!useProxy) return const {};
    final now = DateTime.now();
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    if (_cachedHeaders != null &&
        _cachedHeadersAt != null &&
        _cachedUid == currentUid &&
        now.difference(_cachedHeadersAt!) < const Duration(minutes: 5)) {
      return _cachedHeaders!;
    }

    final results = await Future.wait<String?>([
      FirebaseAppCheck.instance.getToken().catchError((Object e) {
        debugPrint('[Places] AppCheck token fetch warning: $e');
        return null;
      }),
      (FirebaseAuth.instance.currentUser?.getIdToken() ?? Future.value(null))
          .catchError((Object e) {
            debugPrint('[Places] Auth token fetch warning: $e');
            return null;
          }),
    ]);

    final headers = <String, String>{};
    final appCheckToken = results[0];
    final idToken = results[1];
    if (appCheckToken != null) headers['X-Firebase-AppCheck'] = appCheckToken;
    if (idToken != null) headers['Authorization'] = 'Bearer $idToken';

    _cachedHeaders = headers;
    _cachedHeadersAt = now;
    _cachedUid = currentUid;
    return headers;
  }

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
      final useProxy = kIsWeb || apiKey.isEmpty;

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

      // On web (or if client API key is not embedded), use the Cloud Functions proxy
      // On mobile with an API key, call the Google Places API directly
      final Uri url;
      if (useProxy) {
        url = Uri.parse(_placesProxyBaseUrl).replace(
          queryParameters: {
            'type': 'autocomplete',
            'input': input,
            'sessiontoken': _sessionToken!,
            'types': ?requestTypes,
          },
        );
      } else {
        url = Uri.https(
          'maps.googleapis.com',
          '/maps/api/place/autocomplete/json',
          {
            'input': input,
            'key': apiKey,
            'sessiontoken': _sessionToken!,
            'types': ?requestTypes,
          },
        );
      }

      debugPrint(
        '[Places] Autocomplete request (web=$kIsWeb): ${useProxy ? 'via proxy' : 'direct'}',
      );
      final response = await http.get(
        url,
        headers: await _proxyHeaders(useProxy: useProxy),
      );

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
              final isCoarse =
                  t.contains('locality') ||
                  t.contains('administrative_area_level_1') ||
                  t.contains('administrative_area_level_2') ||
                  t.contains('country') ||
                  t.contains('continent');
              return !isCoarse;
            }).toList();
          }

          return predictions;
        } else {
          debugPrint(
            '[Places] Autocomplete response status: ${data['status']}, error: ${data['error_message']}',
          );
        }
      } else {
        debugPrint(
          '[Places] Autocomplete HTTP error: ${response.statusCode} ${response.body}',
        );
      }
      return [];
    } catch (e) {
      debugPrint('HTTP Autocomplete Error: $e');
      return [];
    }
  }

  Future<FetchPlaceResponse?> getPlaceDetails(String placeId) async {
    return _fetchPlaceHttp(placeId);
  }

  /// Manually fetch place details via HTTP to bypass native plugin issues
  Future<FetchPlaceResponse?> _fetchPlaceHttp(String placeId) async {
    try {
      final apiKey = Env.googleMapsApiKey;
      final useProxy = kIsWeb || apiKey.isEmpty;
      final fields =
          'formatted_address,geometry,name,place_id,types,address_components,website,international_phone_number,url,rating,user_ratings_total,opening_hours,photos,price_level,editorial_summary';

      final Uri url;
      if (useProxy) {
        url = Uri.parse(_placesProxyBaseUrl).replace(
          queryParameters: {
            'type': 'details',
            'place_id': placeId,
            'fields': fields,
            'sessiontoken': ?_sessionToken,
          },
        );
      } else {
        url = Uri.https('maps.googleapis.com', '/maps/api/place/details/json', {
          'place_id': placeId,
          'fields': fields,
          'key': apiKey,
          'sessiontoken': ?_sessionToken,
        });
      }
      debugPrint(
        '[Places] Details request (web=$kIsWeb): ${useProxy ? 'via proxy' : 'direct'}',
      );

      final response = await http.get(
        url,
        headers: await _proxyHeaders(useProxy: useProxy),
      );

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
              parts.add(parsed.country);

              if (parts.isNotEmpty) {
                cleanAddress = parts.toSet().join(', ');
              }
            }
          }

          final place = Place(
            id: result['place_id'],
            name: result['name'],
            address: cleanAddress,
            fullAddress: fullAddress,
            latLng: latLng,
            addressComponents: addressComponents,
            types: (result['types'] as List?)?.cast<String>(),
            websiteUri: result['website'] != null
                ? Uri.tryParse(result['website'])
                : null,
            phoneNumber: result['international_phone_number'],
            rating: result['rating'] != null
                ? (result['rating'] as num).toDouble()
                : null,
            userRatingsTotal: result['user_ratings_total'] as int?,
            openingHours: result['opening_hours'],
            photoMetadatas: result['photos'],
            priceLevel: result['price_level'] as int?,
            editorialSummary: result['editorial_summary']?['overview'],
            attributions: [],
            businessStatus: null,
            nameLanguageCode: null,
            plusCode: null,
            utcOffsetMinutes: null,
            viewport: null,
            reviews: null,
          );

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

      final formattedAddress = [?city, ?state, ?country].join(', ');

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
