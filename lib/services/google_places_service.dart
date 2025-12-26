import 'package:flutter_google_places_sdk/flutter_google_places_sdk.dart';
import 'package:geocoding/geocoding.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:diaspora_nearby/config/env.dart';

class GooglePlacesService {
  final FlutterGooglePlacesSdk _places;

  GooglePlacesService(String apiKey) : _places = FlutterGooglePlacesSdk(apiKey);
  
  Future<List<AutocompletePrediction>> autocomplete(String input, {PlaceTypeFilter? filter}) async {
    if (input.isEmpty) return [];
    try {
      final response = await _places.findAutocompletePredictions(
        input,
        placeTypesFilter: [filter ?? PlaceTypeFilter.CITIES],
      );
      return response.predictions;
    } catch (e) {
      return [];
    }
  }

  Future<FetchPlaceResponse?> getPlaceDetails(String placeId) async {
    try {
      final response = await _places.fetchPlace(
        placeId,
        fields: [
          PlaceField.Address,
          PlaceField.AddressComponents,
          PlaceField.Location,
          PlaceField.Id,
          PlaceField.PhoneNumber,
          PlaceField.WebsiteUri,
          PlaceField.Types,
        ],
      );
      return response;
    } catch (e) {
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
        if (city != null) city,
        if (state != null) state,
        if (country != null) country,
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
