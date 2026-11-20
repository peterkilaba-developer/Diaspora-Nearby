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
import 'package:diaspora_nearby/core/data/countries.dart' as country_data;

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
      // For VENUES or ALL, we don't pass a 'types' param (fetch all).
      String? requestTypes;
      if (filter == null || filter == PlaceTypeFilter.CITIES) {
        requestTypes = '(cities)';
      } else if (filter == PlaceTypeFilter.ALL ||
          filter == PlaceTypeFilter.VENUES) {
        requestTypes = null;
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
              final formatted = formatTieredLocation(
                city: parsed.city,
                state: parsed.state,
                country: parsed.country,
                countryCode: parsed.countryCode,
              );
              if (formatted.isNotEmpty) {
                cleanAddress = formatted;
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

  /// Constructs a direct Google Places Photo URL for a given [photoReference].
  String? getPlacePhotoUrl(String? photoReference, {int maxWidth = 1000}) {
    final ref = photoReference?.trim();
    if (ref == null || ref.isEmpty) return null;
    final apiKey = Env.googleMapsApiKey;
    if (apiKey.isEmpty) return null;
    return Uri.https('maps.googleapis.com', '/maps/api/place/photo', {
      'maxwidth': '$maxWidth',
      'photo_reference': ref,
      'key': apiKey,
    }).toString();
  }

  /// Reverse geocode: convert lat/lng to place details
  /// Returns structured location data including subLocality, city, state, country, countryCode.
  /// Tries native OS geocoding first (when non-web), and falls back to Google Geocoding API
  /// (directly on mobile or via `placesProxy` on web) when native geocoding fails or lacks subLocality.
  Future<Map<String, dynamic>?> reverseGeocode(double lat, double lng) async {
    Map<String, dynamic>? nativeResult;
    if (!kIsWeb) {
      try {
        final placemarks = await placemarkFromCoordinates(lat, lng);

        if (placemarks.isNotEmpty) {
          String? bestSubLocality;
          String? bestLocality;
          String? bestSubAdmin;
          String? bestAdmin;
          String? bestCountry;
          String? bestIsoCode;

          for (final p in placemarks) {
            if (bestSubLocality == null &&
                p.subLocality != null &&
                p.subLocality!.trim().isNotEmpty) {
              bestSubLocality = p.subLocality!.trim();
            }
            if (bestLocality == null &&
                p.locality != null &&
                p.locality!.trim().isNotEmpty) {
              bestLocality = p.locality!.trim();
            }
            if (bestSubAdmin == null &&
                p.subAdministrativeArea != null &&
                p.subAdministrativeArea!.trim().isNotEmpty) {
              bestSubAdmin = p.subAdministrativeArea!.trim();
            }
            if (bestAdmin == null &&
                p.administrativeArea != null &&
                p.administrativeArea!.trim().isNotEmpty) {
              bestAdmin = p.administrativeArea!.trim();
            }
            if (bestCountry == null &&
                p.country != null &&
                p.country!.trim().isNotEmpty) {
              bestCountry = p.country!.trim();
            }
            if (bestIsoCode == null &&
                p.isoCountryCode != null &&
                p.isoCountryCode!.trim().isNotEmpty) {
              bestIsoCode = p.isoCountryCode!.trim().toUpperCase();
            }
          }

          final countryCode = bestIsoCode;
          String? country;
          if (countryCode != null) {
            final matched = country_data.getCountryByCode(countryCode);
            country = matched?.name ?? bestCountry;
          } else {
            country = bestCountry;
          }

          final rawCity = bestLocality ?? bestSubAdmin ?? bestSubLocality;
          final city = rawCity != null && rawCity.isNotEmpty
              ? formatLocationName(rawCity)
              : null;

          String? adminArea2 = bestSubAdmin != null && bestSubAdmin.isNotEmpty
              ? formatLocationName(bestSubAdmin)
              : null;
          if (adminArea2 != null && adminArea2.isEmpty) {
            adminArea2 = null;
          }

          // Only treat p.subLocality as a true smaller sub-locality/neighborhood.
          // Never promote subAdministrativeArea (County/District) to subLocality!
          String? subLocality = bestSubLocality != null
              ? formatLocationName(bestSubLocality)
              : null;
          if (subLocality != null &&
              (subLocality.isEmpty ||
                  isSameOrRedundantLocationPart(subLocality, city))) {
            subLocality = null;
          }

          final state = sanitizeStateForCountry(
            state: bestAdmin,
            city: city,
            countryCode: countryCode,
            countryName: country,
          );
          final stateCode = abbreviateStateForCountry(
            state: bestAdmin,
            city: city,
            countryCode: countryCode,
            countryName: country,
          );

          final formattedAddress = formatTieredLocation(
            subLocality: subLocality,
            city: city,
            state: state,
            country: country,
            countryCode: countryCode,
            includeSubLocality: subLocality != null,
          );

          nativeResult = {
            'formattedAddress': formattedAddress,
            'placeId': '',
            'subLocality': subLocality,
            'adminArea2': adminArea2,
            'city': city,
            'state': state,
            'stateCode': stateCode,
            'country': country,
            'countryCode': countryCode,
            'lat': lat,
            'lng': lng,
          };

          if (subLocality != null &&
              subLocality.isNotEmpty &&
              (city != null || adminArea2 != null)) {
            return nativeResult;
          }
        }
      } catch (_) {}
    }

    // Fallback or enrich with Google Geocoding HTTP API (gets neighborhood / sublocality / adminArea2 reliably)
    final httpResult = await _reverseGeocodeHttp(lat, lng);
    if (httpResult != null) {
      if (nativeResult == null) return httpResult;
      return {
        ...nativeResult,
        'subLocality': httpResult['subLocality'] ?? nativeResult['subLocality'],
        'adminArea2': httpResult['adminArea2'] ?? nativeResult['adminArea2'],
        'city': nativeResult['city'] ?? httpResult['city'],
        'state': nativeResult['state'] ?? httpResult['state'],
        'stateCode': httpResult['stateCode'] ?? nativeResult['stateCode'],
        'country': nativeResult['country'] ?? httpResult['country'],
        'countryCode':
            nativeResult['countryCode'] ?? httpResult['countryCode'],
        'formattedAddress':
            (httpResult['subLocality'] != null &&
                (httpResult['formattedAddress'] as String?)?.isNotEmpty == true)
            ? httpResult['formattedAddress']
            : nativeResult['formattedAddress'],
      };
    }

    return nativeResult;
  }

  Future<Map<String, dynamic>?> _reverseGeocodeHttp(
    double lat,
    double lng,
  ) async {
    Future<http.Response?> doFetch({required bool useProxy}) async {
      try {
        final apiKey = Env.googleMapsApiKey;
        if (!useProxy && apiKey.isEmpty) return null;
        final Uri url;
        if (useProxy) {
          url = Uri.parse(_placesProxyBaseUrl).replace(
            queryParameters: {
              'type': 'reverse_geocode',
              'lat': '$lat',
              'lng': '$lng',
            },
          );
        } else {
          url = Uri.https('maps.googleapis.com', '/maps/api/geocode/json', {
            'latlng': '$lat,$lng',
            'key': apiKey,
          });
        }
        return await http
            .get(url, headers: await _proxyHeaders(useProxy: useProxy))
            .timeout(const Duration(seconds: 6));
      } catch (_) {
        return null;
      }
    }

    try {
      final apiKey = Env.googleMapsApiKey;
      // Route via Cloud Functions proxy when web or if direct key denies Geocoding API
      Map<String, dynamic>? data;
      if (!kIsWeb && apiKey.isNotEmpty) {
        final directResp = await doFetch(useProxy: false);
        if (directResp != null && directResp.statusCode == 200) {
          final decoded = jsonDecode(directResp.body) as Map<String, dynamic>;
          if (decoded['status'] == 'OK') {
            data = decoded;
          }
        }
      }
      if (data == null) {
        final proxyResp = await doFetch(useProxy: true);
        if (proxyResp != null && proxyResp.statusCode == 200) {
          final decoded = jsonDecode(proxyResp.body) as Map<String, dynamic>;
          if (decoded['status'] == 'OK') {
            data = decoded;
          }
        }
      }
      if (data == null) return null;

      final results = data['results'] as List<dynamic>?;
      if (results == null || results.isEmpty) return null;

      String? subLocality;
      String? adminArea2;
      String? city;
      String? state;
      String? stateCode;
      String? country;
      String? countryCode;

      for (final raw in results) {
        if (raw is! Map) continue;
        final compsJson = raw['address_components'] as List<dynamic>?;
        if (compsJson == null) continue;
        final components = compsJson
            .whereType<Map>()
            .map(
              (e) => AddressComponent(
                name: (e['long_name'] as String?) ?? '',
                shortName: (e['short_name'] as String?) ?? '',
                types: (e['types'] as List?)?.cast<String>() ?? const [],
              ),
            )
            .toList();

        final parsed = parseLocationComponents(
          (raw['formatted_address'] as String?) ?? '',
          components,
        );
        if (parsed != null) {
          subLocality ??= parsed.sublocality;
          adminArea2 ??= parsed.adminArea2;
          city ??= parsed.city;
          state ??= parsed.state;
          stateCode ??= parsed.stateCode;
          country ??= parsed.country;
          countryCode ??= parsed.countryCode;
          if (subLocality != null && (city != null || adminArea2 != null)) {
            break;
          }
        }
      }

      if (city == null &&
          subLocality == null &&
          adminArea2 == null &&
          countryCode == null) {
        return null;
      }

      if (subLocality != null) {
        final cleanedSub = formatLocationName(subLocality);
        subLocality = cleanedSub.isNotEmpty ? cleanedSub : subLocality.trim();
        if (isSameOrRedundantLocationPart(subLocality, city)) {
          subLocality = null;
        }
      }

      stateCode ??= abbreviateStateForCountry(
        state: state,
        city: city,
        countryCode: countryCode,
        countryName: country,
      );

      final formattedAddress = formatTieredLocation(
        subLocality: subLocality,
        city: city ?? adminArea2,
        state: state,
        country: country,
        countryCode: countryCode,
        includeSubLocality: subLocality != null,
      );

      return {
        'formattedAddress': formattedAddress,
        'placeId': '',
        'subLocality': subLocality,
        'adminArea2': adminArea2,
        'city': city,
        'state': state,
        'stateCode': stateCode,
        'country': country,
        'countryCode': countryCode,
        'lat': lat,
        'lng': lng,
      };
    } catch (e) {
      debugPrint('[Places] HTTP reverse geocode error: $e');
      return null;
    }
  }
}

final googlePlacesServiceProvider = Provider((ref) {
  return GooglePlacesService(Env.googleMapsApiKey);
});
