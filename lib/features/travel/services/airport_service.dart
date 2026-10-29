import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:diaspora_nearby/features/travel/models/airport.dart';
import 'package:diaspora_nearby/features/travel/utils/geo_utils.dart';

List<Airport> _parseAirportsJson(String jsonString) {
  final List<dynamic> jsonList = jsonDecode(jsonString);
  return jsonList.map((j) => Airport.fromJson(j)).toList();
}

class AirportService {
  static List<Airport> _staticAirports = [];
  static bool _staticIsInit = false;
  static Future<void>? _initFuture;
  static final Map<String, Airport?> _closestCache = {};
  static final Map<String, Airport?> _closestIntlCache = {};

  List<Airport> get _airports => _staticAirports;

  static String _coordKey(double lat, double lon) =>
      '${lat.toStringAsFixed(2)},${lon.toStringAsFixed(2)}';

  Future<void> init() async {
    if (_staticIsInit) return;
    if (_initFuture != null) {
      await _initFuture;
      return;
    }
    _initFuture = () async {
      try {
        final String jsonString = await rootBundle.loadString(
          'assets/data/airports.json',
        );
        _staticAirports = await compute(_parseAirportsJson, jsonString);
        _staticIsInit = true;
      } catch (e) {
        debugPrint('Error loading airports: $e');
      } finally {
        _initFuture = null;
      }
    }();
    await _initFuture;
  }

  /// Synchronous lookup if already cached
  Airport? getCachedClosestInternationalAirport(double lat, double lon) =>
      _closestIntlCache[_coordKey(lat, lon)];

  /// Finds the closest airport algorithmically using Haversine distance
  Future<Airport?> getClosestAirport(double lat, double lon) async {
    final key = _coordKey(lat, lon);
    if (_closestCache.containsKey(key)) return _closestCache[key];

    await init();
    if (_airports.isEmpty) return null;

    Airport? closest;
    double minDistanceStr = double.infinity;

    for (final airport in _airports) {
      final dist = GeoUtils.haversine(lat, lon, airport.lat, airport.lon);
      if (dist < minDistanceStr) {
        minDistanceStr = dist;
        closest = airport;
      }
    }

    _closestCache[key] = closest;
    return closest;
  }

  /// Finds the closest **international** (large) airport.
  /// Prioritizes `large_airport` types which handle international flights.
  /// Falls back to any airport if no large airport is found within 500km.
  Future<Airport?> getClosestInternationalAirport(
    double lat,
    double lon,
  ) async {
    final key = _coordKey(lat, lon);
    if (_closestIntlCache.containsKey(key)) return _closestIntlCache[key];

    await init();
    if (_airports.isEmpty) return null;

    Airport? closestLarge;
    double minLargeDist = double.infinity;
    Airport? closestAny;
    double minAnyDist = double.infinity;

    for (final airport in _airports) {
      final dist = GeoUtils.haversine(lat, lon, airport.lat, airport.lon);
      if (dist < minAnyDist) {
        minAnyDist = dist;
        closestAny = airport;
      }
      if (airport.type == 'large_airport' && dist < minLargeDist) {
        minLargeDist = dist;
        closestLarge = airport;
      }
    }

    _closestCache[key] = closestAny;

    // If closest large airport is >500km away, fall back to any closest airport
    if (closestLarge == null || minLargeDist > 500) {
      if (closestAny != null &&
          (closestLarge == null || minAnyDist < minLargeDist * 0.5)) {
        _closestIntlCache[key] = closestAny;
        return closestAny;
      }
    }

    _closestIntlCache[key] = closestLarge;
    return closestLarge;
  }

  /// Search airports by query string (IATA code, name, city, or country).
  /// Returns up to [limit] results sorted by relevance.
  Future<List<Airport>> searchAirports(String query, {int limit = 10}) async {
    await init();
    if (query.trim().isEmpty) return [];

    final q = query.trim().toLowerCase();

    // Score each airport for relevance
    final scored = <MapEntry<Airport, int>>[];

    for (final airport in _airports) {
      int score = 0;

      // Exact IATA match is highest priority
      if (airport.iataCode.toLowerCase() == q) {
        score = 100;
      } else if (airport.iataCode.toLowerCase().startsWith(q)) {
        score = 80;
      } else if (airport.name.toLowerCase().contains(q)) {
        score = 60;
      } else if (airport.municipality.toLowerCase().contains(q)) {
        score = 50;
      } else if (airport.isoCountry.toLowerCase().contains(q)) {
        score = 30;
      }

      if (score > 0) {
        scored.add(MapEntry(airport, score));
      }
    }

    // Sort by score descending
    scored.sort((a, b) => b.value.compareTo(a.value));

    return scored.take(limit).map((e) => e.key).toList();
  }
}
