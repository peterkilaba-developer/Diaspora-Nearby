import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:diaspora_nearby/features/travel/models/airport.dart';
import 'package:diaspora_nearby/features/travel/utils/geo_utils.dart';

class AirportService {
  List<Airport> _airports = [];
  bool _isInit = false;

  Future<void> init() async {
    if (_isInit) return;
    try {
      final String jsonString = await rootBundle.loadString(
        'assets/data/airports.json',
      );
      final List<dynamic> jsonList = jsonDecode(jsonString);
      _airports = jsonList.map((j) => Airport.fromJson(j)).toList();
      _isInit = true;
    } catch (e) {
      debugPrint('Error loading airports: \$e');
    }
  }

  /// Finds the closest airport algorithmically using Haversine distance
  Future<Airport?> getClosestAirport(double lat, double lon) async {
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

    return closest;
  }

  /// Finds the closest **international** (large) airport.
  /// Prioritizes `large_airport` types which handle international flights.
  /// Falls back to any airport if no large airport is found within 500km.
  Future<Airport?> getClosestInternationalAirport(
    double lat,
    double lon,
  ) async {
    await init();
    if (_airports.isEmpty) return null;

    final largeAirports = _airports
        .where((a) => a.type == 'large_airport')
        .toList();

    Airport? closest;
    double minDist = double.infinity;

    for (final airport in largeAirports) {
      final dist = GeoUtils.haversine(lat, lon, airport.lat, airport.lon);
      if (dist < minDist) {
        minDist = dist;
        closest = airport;
      }
    }

    // If closest large airport is >500km away, fall back to any closest airport
    if (closest == null || minDist > 500) {
      final anyClosest = await getClosestAirport(lat, lon);
      if (anyClosest != null) {
        final anyDist = GeoUtils.haversine(
          lat,
          lon,
          anyClosest.lat,
          anyClosest.lon,
        );
        // Only use fallback if it's significantly closer
        if (closest == null || anyDist < minDist * 0.5) {
          return anyClosest;
        }
      }
    }

    return closest;
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
