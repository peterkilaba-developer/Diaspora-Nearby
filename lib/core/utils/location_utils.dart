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
  String? streetNumber,
      route,
      premise,
      sublocality,
      neighborhood,
      sublocality2,
      adminArea3,
      adminArea2,
      postalTown,
      locality,
      state,
      country,
      countryCode,
      postalCode;

  for (final component in components) {
    final types = component.types;
    final name = component.name.trim();
    if (name.isEmpty) continue;

    if (types.contains('street_number')) {
      streetNumber ??= name;
    } else if (types.contains('route')) {
      route ??= name;
    } else if (types.contains('premise') || types.contains('subpremise')) {
      premise ??= name;
    } else if (types.contains('sublocality') ||
        types.contains('sublocality_level_1')) {
      sublocality ??= name;
    } else if (types.contains('neighborhood')) {
      neighborhood ??= name;
    } else if (types.contains('sublocality_level_2') ||
        types.contains('sublocality_level_3')) {
      sublocality2 ??= name;
    } else if (types.contains('administrative_area_level_3')) {
      adminArea3 ??= name;
    } else if (types.contains('administrative_area_level_2')) {
      adminArea2 ??= name;
    } else if (types.contains('postal_town')) {
      postalTown ??= name;
    } else if (types.contains('locality')) {
      locality ??= name;
    } else if (types.contains('administrative_area_level_1')) {
      state ??= name;
    } else if (types.contains('country')) {
      country = name;
      countryCode = component.shortName.trim();
    } else if (types.contains('postal_code')) {
      postalCode ??= name;
    }
  }

  sublocality ??= neighborhood ?? sublocality2 ?? adminArea3;

  String? city =
      locality ?? postalTown ?? adminArea2 ?? sublocality ?? adminArea3;

  // If city came from locality/postalTown and sublocality wasn't set,
  // use administrative_area_level_2 (e.g. "Ilala" district in Dar es Salaam)
  // when it is distinct from city and state.
  if ((locality != null || postalTown != null) &&
      sublocality == null &&
      adminArea2 != null &&
      !isSameOrRedundantLocationPart(adminArea2, city) &&
      !isSameOrRedundantLocationPart(adminArea2, state)) {
    sublocality = formatLocationName(adminArea2);
  }

  if (sublocality != null && isSameOrRedundantLocationPart(sublocality, city)) {
    sublocality = null;
  }

  // Fallback for country from address string if components lacked country
  if ((country == null || countryCode == null) && address.isNotEmpty) {
    final parts = address
        .split(',')
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isNotEmpty) {
      final matchedCountry = country_data.getCountryByName(parts.last);
      if (matchedCountry != null) {
        country ??= matchedCountry.name;
        countryCode ??= matchedCountry.code;
      }
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

  // [FALLBACK] If no city found (e.g. Region/Resort selected), extract from address or state
  if (city == null && address.isNotEmpty) {
    final parts = address
        .split(',')
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList();
    for (final part in parts) {
      if (!PlusCodeService.isValidPlusCode(part) &&
          !isSameOrRedundantLocationPart(part, country) &&
          !isSameOrRedundantLocationPart(part, state)) {
        city = formatLocationName(part);
        break;
      }
    }
  }
  if (city == null && state != null) {
    city = formatLocationName(state);
  }

  if (country == null || countryCode == null) return null;

  // Enforce 2-tier vs 3-tier hierarchy & strip redundant state (e.g. "Dar es Salam" vs "Dar es Salaam")
  state = sanitizeStateForCountry(
    state: state,
    city: city,
    countryCode: countryCode,
    countryName: country,
  );

  // Build clean street address (without duplicating city/state/country)
  String? streetAddress;
  if (streetNumber != null && route != null) {
    streetAddress = '$streetNumber $route';
  } else if (route != null) {
    streetAddress = route;
  } else if (premise != null &&
      !isSameOrRedundantLocationPart(premise, city)) {
    streetAddress = premise;
  } else if (address.isNotEmpty) {
    final parts = address
        .split(',')
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.length > 1) {
      final first = parts.first;
      if (!PlusCodeService.isValidPlusCode(first) &&
          !isSameOrRedundantLocationPart(first, city) &&
          !isSameOrRedundantLocationPart(first, state) &&
          !isSameOrRedundantLocationPart(first, country)) {
        streetAddress = first;
      }
    }
  }

  return LocationParsed(
    sublocality: sublocality,
    city: city,
    state: state,
    country: country,
    countryCode: countryCode,
    streetAddress: streetAddress,
    postalCode: postalCode,
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
  final String? streetAddress;
  final String? postalCode;

  LocationParsed({
    this.sublocality,
    this.city,
    this.state,
    required this.country,
    required this.countryCode,
    this.placeId,
    this.streetAddress,
    this.postalCode,
  });

  @override
  String toString() =>
      'LocationParsed(sublocality: $sublocality, city: $city, state: $state, country: $country, code: $countryCode, placeId: $placeId, streetAddress: $streetAddress)';
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

String _normalizeLocationToken(String value, {bool collapseRepeats = false}) {
  var s = value.toLowerCase().trim();
  s = s.replaceAll(
    RegExp(
      r'\b(region|state|province|district|county|township|municipality|governorate|prefecture|department|parish|city|division|zone)\b',
      caseSensitive: false,
    ),
    '',
  );
  s = s.replaceAll(RegExp(r'[^a-z0-9\s]'), ' ');
  s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (collapseRepeats && s.isNotEmpty) {
    s = s.replaceAllMapped(RegExp(r'(.)\1+'), (m) => m.group(1)!);
  }
  return s;
}

/// Returns true if two location parts represent the same or redundant place
/// (e.g. "Dar es Salaam" vs "Dar es Salam", "Mwanza" vs "Mwanza Region",
/// "New York City" vs "New York").
bool isSameOrRedundantLocationPart(String? a, String? b) {
  if (a == null || b == null) return false;
  final trimA = a.trim();
  final trimB = b.trim();
  if (trimA.isEmpty || trimB.isEmpty) return false;
  if (trimA.toLowerCase() == trimB.toLowerCase()) return true;

  final normA = _normalizeLocationToken(trimA);
  final normB = _normalizeLocationToken(trimB);
  if (normA.isNotEmpty && normA == normB) return true;

  final collapsedA = _normalizeLocationToken(trimA, collapseRepeats: true);
  final collapsedB = _normalizeLocationToken(trimB, collapseRepeats: true);
  if (collapsedA.isNotEmpty && collapsedA == collapsedB) return true;

  return false;
}

/// Returns a cleaned state/region name ONLY if the country uses a 3-tier
/// hierarchy (`hasStateLevel == true`) AND the state is not redundant with [city].
/// For 2-tier countries (like Tanzania, Kenya, Uganda, UK, etc.), always returns null.
String? sanitizeStateForCountry({
  String? state,
  String? city,
  String? countryCode,
  String? countryName,
}) {
  if (state == null) return null;
  final trimmed = state.trim();
  if (trimmed.isEmpty) return null;

  final hasCountryInfo =
      (countryCode != null && countryCode.trim().isNotEmpty) ||
      (countryName != null && countryName.trim().isNotEmpty);

  if (hasCountryInfo &&
      !country_data.hasStateLevelForCountry(
        countryCode: countryCode,
        countryName: countryName,
      )) {
    return null;
  }

  final cleaned = formatLocationName(trimmed);
  if (cleaned.isEmpty) return null;

  if (isSameOrRedundantLocationPart(city, trimmed) ||
      isSameOrRedundantLocationPart(city, cleaned)) {
    return null;
  }

  return cleaned;
}

/// Formats a location string strictly following 2-tier (`City, Country`) or
/// 3-tier (`City, State, Country`) rules for the given country, while
/// deduplicating any redundant parts (such as "Dar es Salaam, Dar es Salam").
String formatTieredLocation({
  String? subLocality,
  String? city,
  String? state,
  String? country,
  String? countryCode,
  bool includeSubLocality = false,
  bool includeCountry = true,
}) {
  final cleanSub = subLocality?.trim();
  final cleanCity = city?.trim();
  final cleanCountry = country?.trim();
  final cleanState = sanitizeStateForCountry(
    state: state,
    city: cleanCity,
    countryCode: countryCode,
    countryName: cleanCountry,
  );

  final parts = <String>[];

  void addUnique(String? value) {
    if (value == null) return;
    final v = value.trim();
    if (v.isEmpty) return;
    if (parts.any((existing) => isSameOrRedundantLocationPart(existing, v))) {
      return;
    }
    parts.add(v);
  }

  if (includeSubLocality) {
    addUnique(cleanSub);
  }
  addUnique(cleanCity);
  addUnique(cleanState);
  if (includeCountry) {
    addUnique(cleanCountry);
  }

  return parts.join(', ');
}

/// Cleans a comma-separated location display string by removing consecutive or
/// redundant parts (e.g. "Dar es Salaam, Dar es Salam, Tanzania" -> "Dar es Salaam, Tanzania")
/// and enforcing 2-tier formatting if the trailing country is a 2-tier country.
String cleanRedundantLocationString(
  String raw, {
  String? countryCode,
  String? countryName,
}) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return '';

  final rawParts = trimmed
      .split(',')
      .map((p) => p.trim())
      .where((p) => p.isNotEmpty)
      .toList();
  if (rawParts.length <= 1) return trimmed;

  final deduped = <String>[];
  for (final part in rawParts) {
    if (deduped.any((existing) => isSameOrRedundantLocationPart(existing, part))) {
      continue;
    }
    deduped.add(part);
  }

  final effectiveCountryName = countryName ?? deduped.last;
  final matchedCountry =
      (countryCode != null && countryCode.trim().isNotEmpty)
      ? country_data.getCountryByCode(countryCode)
      : country_data.getCountryByName(effectiveCountryName);

  // If 2-tier country and we have [City, Region/State, Country], drop the middle State part
  // when the last element matches the country name.
  if (matchedCountry != null &&
      !matchedCountry.hasStateLevel &&
      deduped.length == 3 &&
      isSameOrRedundantLocationPart(deduped.last, matchedCountry.name)) {
    return '${deduped.first}, ${deduped.last}';
  }

  return deduped.join(', ');
}
