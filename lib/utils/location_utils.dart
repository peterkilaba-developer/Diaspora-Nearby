import 'dart:math' as math;
import 'package:diaspora_nearby/data/countries.dart' as country_data;
import 'package:flutter_google_places_sdk/flutter_google_places_sdk.dart';

// --------------------------------------------------------------------------
// Models
// --------------------------------------------------------------------------

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

  // [FIX] Explicitly handle New York City to avoid "New York Community" (which sounds like State)
  if (city == 'New York' && countryCode == 'US') {
      city = 'New York City';
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

  // Verify if country supports state level
  if (countryCode != null && !country_data.hasStateLevelHierarchyFromData(countryCode)) {
    state = null;
  }
  
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
  final String? placeId; // [NEW] Explicit Place ID for robust matching

  LocationParsed({
    this.city,
    this.state,
    required this.country,
    required this.countryCode,
    this.placeId,
  });

  @override
  String toString() => 'LocationParsed(city: $city, state: $state, country: $country, code: $countryCode, placeId: $placeId)';
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

  if ((locationType == 'host' || locationType == 'past') && homeCountryCode != null) {
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
  final normalizedType = type.replaceAll(RegExp(r'^(home_|host_|past_)'), '');
  
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

// --------------------------------------------------------------------------
// Formatting Helpers
// --------------------------------------------------------------------------

const Map<String, String> usStateNames = {
  'AL': 'Alabama', 'AK': 'Alaska', 'AZ': 'Arizona', 'AR': 'Arkansas', 'CA': 'California',
  'CO': 'Colorado', 'CT': 'Connecticut', 'DE': 'Delaware', 'FL': 'Florida', 'GA': 'Georgia',
  'HI': 'Hawaii', 'ID': 'Idaho', 'IL': 'Illinois', 'IN': 'Indiana', 'IA': 'Iowa',
  'KS': 'Kansas', 'KY': 'Kentucky', 'LA': 'Louisiana', 'ME': 'Maine', 'MD': 'Maryland',
  'MA': 'Massachusetts', 'MI': 'Michigan', 'MN': 'Minnesota', 'MS': 'Mississippi', 'MO': 'Missouri',
  'MT': 'Montana', 'NE': 'Nebraska', 'NV': 'Nevada', 'NH': 'New Hampshire', 'NJ': 'New Jersey',
  'NM': 'New Mexico', 'NY': 'New York', 'NC': 'North Carolina', 'ND': 'North Dakota', 'OH': 'Ohio',
  'OK': 'Oklahoma', 'OR': 'Oregon', 'PA': 'Pennsylvania', 'RI': 'Rhode Island', 'SC': 'South Carolina',
  'SD': 'South Dakota', 'TN': 'Tennessee', 'TX': 'Texas', 'UT': 'Utah', 'VT': 'Vermont',
  'VA': 'Virginia', 'WA': 'Washington', 'WV': 'West Virginia', 'WI': 'Wisconsin', 'WY': 'Wyoming',
  'DC': 'District of Columbia',
};

/// Helper to ensure full names are used for locations (e.g. TX -> Texas, US -> United States)
String formatLocationName(String? name) {
  if (name == null || name.isEmpty) return '';
  // Remove any numbers from the name (e.g. "78701" or "123")
  String cleaned = name.replaceAll(RegExp(r'\d+'), '').trim();
  if (cleaned.isEmpty) return '';
  
  final upper = cleaned.toUpperCase();
  
  // 1. Check if it's a US State abbreviation
  if (upper.length == 2 && usStateNames.containsKey(upper)) {
     return usStateNames[upper]!;
  }
  
  // 2. Check if it's a known country code
  if (upper.length == 2) {
     final country = country_data.getCountryByCode(upper);
     if (country != null) {
       return country.name;
     }
  }
  
  // 3. Handle common abbreviations requested
  if (upper == 'U.S.' || upper == 'USA') return 'United States';
  if (upper == 'UK') return 'United Kingdom';
  if (upper == 'UAE') return 'United Arab Emirates';
  
  return cleaned;
}

/// Helper to format a full address string by expanding abbreviations and removing numeric parts
String formatFullAddress(String address) {
  if (address.isEmpty) return '';
  // Split by comma, clean each part, and filter out anything that becomes empty (like purely numeric zip codes or house numbers)
  final parts = address.split(',').map((p) => p.trim()).toList();
  final formattedParts = parts
      .map((part) => formatLocationName(part))
      .where((p) => p.isNotEmpty)
      .toList();
      
  return formattedParts.join(', ');
}
