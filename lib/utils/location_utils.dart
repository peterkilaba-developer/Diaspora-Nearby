import 'dart:math' as math;
import 'package:diaspora_nearby/data/countries.dart' as country_data;

// --------------------------------------------------------------------------
// Models
// --------------------------------------------------------------------------

// Add `AddressComponent` import if not available, or just dynamic if we can't import GPlaces SDK here without adding dep to utils (bad practice).
// Better: Duplicate logic or move GPlaces dependency? 
// The error was that `_UserProfileScreenState` couldn't find it. 
// We will implement a standalone helper that takes the raw components structure.
// But better yet, let's look at how it was implemented in `profile_setup_screen.dart` and move it here.

// It seems `AddressComponent` comes from `flutter_google_places_sdk`.
// We need to import it here.
import 'package:flutter_google_places_sdk/flutter_google_places_sdk.dart';

LocationParsed? parseLocationComponents(String address, List<AddressComponent> components) {
  String? city, state, country, countryCode;
  
  for (final component in components) {
    final types = component.types;
    if (types.contains('locality')) {
      city = component.name;
    } else if (types.contains('administrative_area_level_1')) {
      state = component.name;
    } else if (types.contains('country')) {
      country = component.name;
      countryCode = component.shortName;
    }
  }

  // UK Logic
  if (countryCode == 'GB') {
    for (final component in components) {
      final name = component.name;
      if (name == 'England') {
        country = 'England'; countryCode = 'GB-ENG'; break;
      } else if (name == 'Scotland') {
        country = 'Scotland'; countryCode = 'GB-SCT'; break;
      } else if (name == 'Wales') {
        country = 'Wales'; countryCode = 'GB-WLS'; break;
      } else if (name == 'Northern Ireland') {
        country = 'Northern Ireland'; countryCode = 'GB-NIR'; break;
      }
    }
  }

  if (country == null || countryCode == null) return null;
  
  return LocationParsed(
    city: city, 
    state: state, 
    country: country, 
    countryCode: countryCode
  );
}

class LocationParsed {
  final String? city;
  final String? state;
  final String country;
  final String countryCode;

  LocationParsed({
    this.city,
    this.state,
    required this.country,
    required this.countryCode,
  });

  @override
  String toString() => 'LocationParsed(city: $city, state: $state, country: $country, code: $countryCode)';
}

// --------------------------------------------------------------------------
// Constants & Lookups
// --------------------------------------------------------------------------

/// Get continent name from code (e.g. "AF" -> "Africa")
String getContinentName(String continentCode) {
  final codeToContinent = {
    'AF': country_data.Continent.africa,
    'AS': country_data.Continent.asia,
    'EU': country_data.Continent.europe,
    'NA': country_data.Continent.northAmerica,
    'SA': country_data.Continent.southAmerica,
    'OC': country_data.Continent.oceania,
    'AN': country_data.Continent.antarctica,
    'CB': country_data.Continent.caribbean,
  };
  final continent = codeToContinent[continentCode];
  return continent != null 
    ? country_data.continentDisplayNames[continent] ?? 'Global'
    : 'Global';
}

/// Get continent code by country code
String getContinentByCountryCode(String countryCode) {
  final continent = country_data.getContinentByCountryCode(countryCode);
  if (continent == null) return 'AF';
  
  switch (continent) {
    case country_data.Continent.africa: return 'AF';
    case country_data.Continent.asia: return 'AS';
    case country_data.Continent.europe: return 'EU';
    case country_data.Continent.northAmerica: return 'NA';
    case country_data.Continent.southAmerica: return 'SA';
    case country_data.Continent.oceania: return 'OC';
    case country_data.Continent.caribbean: return 'CB';
    case country_data.Continent.antarctica: return 'AN';
  }
}

// --------------------------------------------------------------------------
// Community Generation Logic
// --------------------------------------------------------------------------

String generateCommunityId({
  required String locationType, // 'home' | 'host'
  required String type, // 'city' | 'state' | 'country' | 'continent' | 'global'
  LocationParsed? location,
  String? continent,
  String? homeCountryCode,
}) {
  if (type == 'global') return 'global_community';

  final List<String> parts = [locationType];

  if (type == 'continent' && continent != null) {
    parts.add('continent');
    parts.add(continent.toLowerCase().replaceAll(RegExp(r'\s+'), '-'));
  } else if (type == 'country' && location != null) {
    parts.add('country');
    parts.add(location.countryCode.toLowerCase());
  } else if (type == 'state' && location != null && location.state != null) {
    parts.add('state');
    parts.add(location.countryCode.toLowerCase());
    parts.add(location.state!.toLowerCase().replaceAll(RegExp(r'\s+'), '-'));
  } else if (type == 'city' && location != null && location.city != null) {
    parts.add('city');
    parts.add(location.countryCode.toLowerCase());
    parts.add(location.state != null 
        ? location.state!.toLowerCase().replaceAll(RegExp(r'\s+'), '-') 
        : 'no-state');
    parts.add(location.city!.toLowerCase().replaceAll(RegExp(r'\s+'), '-'));
  }

  if (locationType == 'host' && homeCountryCode != null) {
    parts.add(homeCountryCode.toLowerCase());
  }

  return parts.join('_');
}

String generateCommunityName({
  required String type,
  required LocationParsed location,
  String? continent,
  String? locationType,
}) {
  final normalizedType = type.replaceAll(RegExp(r'^(home_|host_)'), '');
  
  if (normalizedType == 'global') return 'Global Community';
  
  if (normalizedType == 'continent' && continent != null) {
    return '$continent Community';
  }
  
  if (normalizedType == 'country') {
    return '${location.country} Community';
  }
  
  if (normalizedType == 'state' && location.state != null) {
    return '${location.state} Community';
  }
  
  if (normalizedType == 'city' && location.city != null) {
    return '${location.city} Community';
  }
  
  return 'Unknown Community';
}

// --------------------------------------------------------------------------
// Distance Utilities
// --------------------------------------------------------------------------

/// Calculate distance between two points in kilometers using Haversine formula
double calculateDistance(double lat1, double lon1, double lat2, double lon2) {
  const p = 0.017453292519943295; // Math.PI / 180
  final a = 0.5 - math.cos((lat2 - lat1) * p) / 2 +
      math.cos(lat1 * p) * math.cos(lat2 * p) *
      (1 - math.cos((lon2 - lon1) * p)) / 2;
  return 12742 * math.asin(math.sqrt(a)); // 2 * R; R = 6371 km
}

/// Human readable distance string
String formatDistance(double km) {
  if (km < 1) {
    return '${(km * 1000).round()} m';
  } else if (km < 10) {
    return '${km.toStringAsFixed(1)} km';
  } else {
    return '${km.round()} km';
  }
}
