import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:diaspora_nearby/features/travel/utils/geo_utils.dart';
import 'package:diaspora_nearby/core/data/countries.dart' as country_data;
import 'package:diaspora_nearby/features/shared/models/google_places_models.dart';
import 'package:diaspora_nearby/features/profile/models/profile_data.dart';
import 'package:diaspora_nearby/features/events/models/event_data.dart';
import 'package:diaspora_nearby/core/services/plus_code_service.dart';

// --------------------------------------------------------------------------
// Models
// --------------------------------------------------------------------------

LocationParsed? parseLocationComponents(
  String address,
  List<AddressComponent> components,
) {
  String? sublocality, city, state, country, countryCode;

  for (final component in components) {
    final types = component.types;
    if (types.contains('sublocality') ||
        types.contains('sublocality_level_1')) {
      sublocality ??= component.name;
    } else if (types.contains('neighborhood')) {
      sublocality ??= component.name; // fallback if no sublocality
    } else if (types.contains('locality')) {
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
        country = 'England';
        countryCode = 'GB-ENG';
        break;
      } else if (name == 'Scotland') {
        country = 'Scotland';
        countryCode = 'GB-SCT';
        break;
      } else if (name == 'Wales') {
        country = 'Wales';
        countryCode = 'GB-WLS';
        break;
      } else if (name == 'Northern Ireland') {
        country = 'Northern Ireland';
        countryCode = 'GB-NIR';
        break;
      }
    }
  }

  // [FALLBACK] If no city found (e.g. Region selected), use first part of address
  if (city == null && address.isNotEmpty) {
    final parts = address.split(',');
    if (parts.isNotEmpty) {
      city = parts.first.trim();
    }
  }

  if (country == null || countryCode == null) return null;

  // Verify if country supports state level
  if (!country_data.hasStateLevelHierarchyFromData(countryCode)) {
    state = null;
  }

  return LocationParsed(
    sublocality: sublocality,
    city: city,
    state: state,
    country: country,
    countryCode: countryCode,
  );
}

class LocationParsed {
  final String?
  sublocality; // neighborhood / sub-locality for precise marketplace locations
  final String? city;
  final String? state;
  final String country;
  final String countryCode;
  final String? placeId; // [NEW] Explicit Place ID for robust matching

  LocationParsed({
    this.sublocality,
    this.city,
    this.state,
    required this.country,
    required this.countryCode,
    this.placeId,
  });

  @override
  String toString() =>
      'LocationParsed(sublocality: $sublocality, city: $city, state: $state, country: $country, code: $countryCode, placeId: $placeId)';
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
    case country_data.Continent.africa:
      return 'AF';
    case country_data.Continent.asia:
      return 'AS';
    case country_data.Continent.europe:
      return 'EU';
    case country_data.Continent.northAmerica:
      return 'NA';
    case country_data.Continent.southAmerica:
      return 'SA';
    case country_data.Continent.oceania:
      return 'OC';
    case country_data.Continent.caribbean:
      return 'CB';
    case country_data.Continent.antarctica:
      return 'AN';
  }
}

/// Get continent adjective from code (e.g. "AF" -> "African")
String getContinentAdjective(String continentCode) {
  switch (continentCode) {
    case 'AF':
      return 'African';
    case 'AS':
      return 'Asian';
    case 'EU':
      return 'European';
    case 'NA':
      return 'North American';
    case 'SA':
      return 'South American';
    case 'OC':
      return 'Oceanian';
    case 'AN':
      return 'Antarctic';
    case 'CB':
      return 'Caribbean';
    default:
      return 'Global';
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
    parts.add(
      location.state != null
          ? location.state!.toLowerCase().replaceAll(RegExp(r'\s+'), '-')
          : 'no-state',
    );
    parts.add(location.city!.toLowerCase().replaceAll(RegExp(r'\s+'), '-'));
  }

  if ((locationType == 'host' || locationType == 'past') &&
      homeCountryCode != null) {
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
    final isHome = locationType == 'home';

    if (continent == 'Africa') {
      return isHome ? 'African Community' : 'Africa Community';
    }
    if (continent == 'Asia') {
      return isHome ? 'Asian Community' : 'Asia Community';
    }
    if (continent == 'Europe') {
      return isHome ? 'European Community' : 'Europe Community';
    }
    if (continent == 'North America') {
      return isHome ? 'North American Community' : 'North America Community';
    }
    if (continent == 'South America') {
      return isHome ? 'South American Community' : 'South America Community';
    }
    if (continent == 'Oceania') {
      return isHome ? 'Oceanian Community' : 'Oceania Community';
    }
    if (continent == 'Antarctica') {
      return isHome ? 'Antarctic Community' : 'Antarctica Community';
    }
    if (continent == 'Caribbean') {
      return isHome ? 'Caribbean Community' : 'Caribbean Community';
    }

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
double calculateDistance(double lat1, double lon1, double lat2, double lon2) =>
    GeoUtils.haversine(lat1, lon1, lat2, lon2);

/// Extract the best available non-zero coordinates from a user profile:
/// 1. currentLocation, 2. hostLocation, 3. homeLocation, 4. country centroid.
(double, double)? extractProfileCoords(ProfileData? profile) {
  if (profile == null) return null;

  (double, double)? validCoords(double? lat, double? lng) {
    if (lat != null &&
        lng != null &&
        lat.isFinite &&
        lng.isFinite &&
        (lat != 0 || lng != 0)) {
      return (lat, lng);
    }
    return null;
  }

  final cur = profile.currentLocation?.geometry.location;
  final c1 = validCoords(cur?.lat, cur?.lng);
  if (c1 != null) return c1;

  final host = profile.hostLocation.geometry?.location;
  final c2 = validCoords(host?.lat, host?.lng);
  if (c2 != null) return c2;

  final home = profile.homeLocation.geometry?.location;
  final c3 = validCoords(home?.lat, home?.lng);
  if (c3 != null) return c3;

  return null;
}

/// Calculate distance in km between a viewer and a target profile.
double? calculateProfileDistanceKm(
  ProfileData? viewer,
  ProfileData? target, {
  double? fallbackDistanceKm,
}) {
  if (viewer != null &&
      target != null &&
      viewer.uid != null &&
      viewer.uid == target.uid) {
    return 0.0;
  }
  final myCoords = extractProfileCoords(viewer);
  final theirCoords = extractProfileCoords(target);
  if (myCoords != null && theirCoords != null) {
    return calculateDistance(
      myCoords.$1,
      myCoords.$2,
      theirCoords.$1,
      theirCoords.$2,
    );
  }
  return fallbackDistanceKm ?? target?.distance;
}

Position? _lastKnownPositionCache;

/// Returns the most recently cached GPS position synchronously (if available).
Position? get cachedLastKnownPosition => _lastKnownPositionCache;

/// Updates the synchronous in-memory GPS position cache.
void cacheLastKnownPosition(Position position) {
  _lastKnownPositionCache = position;
}

/// Real-time stream of the device's GPS position when permission is granted.
/// Emits [cachedLastKnownPosition] synchronously on frame 0 if available.
final liveUserPositionProvider = StreamProvider<Position?>((ref) {
  return Stream<Position?>.multi((controller) {
    if (_lastKnownPositionCache != null) {
      controller.addSync(_lastKnownPositionCache);
    }

    StreamSubscription<Position>? sub;

    Future<void> init() async {
      try {
        final serviceEnabled = await Geolocator.isLocationServiceEnabled();
        if (!serviceEnabled) {
          if (_lastKnownPositionCache == null && !controller.isClosed) {
            controller.add(null);
          }
          return;
        }

        final permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied ||
            permission == LocationPermission.deniedForever) {
          if (_lastKnownPositionCache == null && !controller.isClosed) {
            controller.add(null);
          }
          return;
        }

        final lastKnown = await Geolocator.getLastKnownPosition();
        if (lastKnown != null) {
          _lastKnownPositionCache = lastKnown;
          if (!controller.isClosed) {
            controller.add(lastKnown);
          }
        }

        try {
          final current = await Geolocator.getCurrentPosition().timeout(
            const Duration(seconds: 5),
          );
          _lastKnownPositionCache = current;
          if (!controller.isClosed) {
            controller.add(current);
          }
        } catch (_) {}

        sub =
            Geolocator.getPositionStream(
              locationSettings: const LocationSettings(
                accuracy: LocationAccuracy.medium,
                distanceFilter: 100,
              ),
            ).listen((pos) {
              _lastKnownPositionCache = pos;
              if (!controller.isClosed) controller.add(pos);
            }, onError: (_) {});
      } catch (_) {
        if (_lastKnownPositionCache == null && !controller.isClosed) {
          controller.add(null);
        }
      }
    }

    init();

    controller.onCancel = () {
      sub?.cancel();
    };
  });
});

/// Extract the best available non-zero coordinates from an Event:
/// 1. (event.latitude, event.longitude), 2. PlusCode decode, 3. country centroid.
(double, double)? extractEventCoords(Event? event) {
  if (event == null) return null;

  (double, double)? validCoords(double? lat, double? lng) {
    if (lat != null &&
        lng != null &&
        lat.isFinite &&
        lng.isFinite &&
        (lat != 0 || lng != 0)) {
      return (lat, lng);
    }
    return null;
  }

  final c1 = validCoords(event.latitude, event.longitude);
  if (c1 != null) return c1;

  if (event.plusCode != null && event.plusCode!.isNotEmpty) {
    final decoded = PlusCodeService.decode(event.plusCode!);
    final c2 = validCoords(decoded?['latitude'], decoded?['longitude']);
    if (c2 != null) return c2;
  }

  if (event.location.isNotEmpty &&
      PlusCodeService.isValidPlusCode(event.location)) {
    final decoded = PlusCodeService.decode(event.location);
    final c3 = validCoords(decoded?['latitude'], decoded?['longitude']);
    if (c3 != null) return c3;
  }

  return null;
}

/// Calculate distance in km between the logged-in user and an Event.
double? calculateEventDistanceKm(
  Event event, {
  ProfileData? viewer,
  Position? livePosition,
  double? fallbackDistanceKm,
}) {
  final effectivePos = livePosition ?? _lastKnownPositionCache;
  (double, double)? myCoords;
  if (effectivePos != null &&
      effectivePos.latitude.isFinite &&
      effectivePos.longitude.isFinite &&
      (effectivePos.latitude != 0 || effectivePos.longitude != 0)) {
    myCoords = (effectivePos.latitude, effectivePos.longitude);
  } else {
    myCoords = extractProfileCoords(viewer);
  }

  final eventCoords = extractEventCoords(event);
  if (myCoords != null && eventCoords != null) {
    return calculateDistance(
      myCoords.$1,
      myCoords.$2,
      eventCoords.$1,
      eventCoords.$2,
    );
  }
  return fallbackDistanceKm ?? event.distance;
}

/// Human readable distance string
String formatDistance(double km) {
  if (km < 1) {
    return '${(km * 1000).round()} m';
  } else {
    return '${km.round()} km';
  }
}

// --------------------------------------------------------------------------
// Formatting Helpers
// --------------------------------------------------------------------------

const Map<String, String> usStateNames = {
  'AL': 'Alabama',
  'AK': 'Alaska',
  'AZ': 'Arizona',
  'AR': 'Arkansas',
  'CA': 'California',
  'CO': 'Colorado',
  'CT': 'Connecticut',
  'DE': 'Delaware',
  'FL': 'Florida',
  'GA': 'Georgia',
  'HI': 'Hawaii',
  'ID': 'Idaho',
  'IL': 'Illinois',
  'IN': 'Indiana',
  'IA': 'Iowa',
  'KS': 'Kansas',
  'KY': 'Kentucky',
  'LA': 'Louisiana',
  'ME': 'Maine',
  'MD': 'Maryland',
  'MA': 'Massachusetts',
  'MI': 'Michigan',
  'MN': 'Minnesota',
  'MS': 'Mississippi',
  'MO': 'Missouri',
  'MT': 'Montana',
  'NE': 'Nebraska',
  'NV': 'Nevada',
  'NH': 'New Hampshire',
  'NJ': 'New Jersey',
  'NM': 'New Mexico',
  'NY': 'New York',
  'NC': 'North Carolina',
  'ND': 'North Dakota',
  'OH': 'Ohio',
  'OK': 'Oklahoma',
  'OR': 'Oregon',
  'PA': 'Pennsylvania',
  'RI': 'Rhode Island',
  'SC': 'South Carolina',
  'SD': 'South Dakota',
  'TN': 'Tennessee',
  'TX': 'Texas',
  'UT': 'Utah',
  'VT': 'Vermont',
  'VA': 'Virginia',
  'WA': 'Washington',
  'WV': 'West Virginia',
  'WI': 'Wisconsin',
  'WY': 'Wyoming',
  'DC': 'District of Columbia',
};

/// Helper to ensure full names are used for locations (e.g. TX -> Texas, US -> United States)
String formatLocationName(String? name) {
  if (name == null || name.isEmpty) return '';
  String cleaned = name.replaceAll(RegExp(r'\d+'), '').trim();
  if (cleaned.isEmpty) return '';

  final upper = cleaned.toUpperCase();

  if (upper.length == 2 && usStateNames.containsKey(upper)) {
    return usStateNames[upper]!;
  }

  if (upper.length == 2) {
    final country = country_data.getCountryByCode(upper);
    if (country != null) {
      return country.name;
    }
  }

  if (upper == 'U.S.' || upper == 'USA') return 'United States';
  if (upper == 'UK') return 'United Kingdom';
  if (upper == 'UAE') return 'United Arab Emirates';

  final suffixRegex = RegExp(
    r'\s+(Region|State|Province|District|County|Township)\b',
    caseSensitive: false,
  );

  String processed = cleaned.replaceAll(suffixRegex, '').trim();

  if (processed.isNotEmpty) {
    return processed;
  }

  return cleaned;
}

/// Helper to format a full address string by expanding abbreviations and removing numeric parts
String formatFullAddress(String address) {
  if (address.isEmpty) return '';
  final parts = address.split(',').map((p) => p.trim()).toList();
  final formattedParts = parts
      .map((part) => formatLocationName(part))
      .where((p) => p.isNotEmpty)
      .toList();

  return formattedParts.join(', ');
}
