import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart' as cf;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:diaspora_nearby/features/radio/models/radio_station.dart';
import 'package:diaspora_nearby/features/auth/repository/auth_repository.dart';

final radioRepositoryProvider = Provider(
  (ref) => RadioRepository(
    firestore: cf.FirebaseFirestore.instance,
    auth: ref.read(authRepositoryProvider),
  ),
);

class RadioRepository {
  final cf.FirebaseFirestore _firestore;
  // ignore: unused_field
  final AuthRepository _auth;

  static const String _proxyUrl =
      'https://us-central1-diaspora-nearby-a3dac.cloudfunctions.net/radioProxy';
  static const String _directUrl =
      'https://de1.api.radio-browser.info/json'; // Primary mirror

  RadioRepository({
    required cf.FirebaseFirestore firestore,
    required AuthRepository auth,
  }) : _firestore = firestore,
       _auth = auth;

  // --- Helper Methods ---

  Future<List<RadioStation>> _fetchWithFallback(String endpoint) async {
    // 1. Try Proxy
    final proxyUrl = Uri.parse('$_proxyUrl?endpoint=$endpoint');
    debugPrint('RadioRepo: Attempting PROXY: $proxyUrl');

    try {
      final response = await http
          .get(proxyUrl)
          .timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        final dynamic decoded = json.decode(response.body);
        if (decoded is List && decoded.isNotEmpty) {
          debugPrint(
            'RadioRepo: Proxy SUCCESS - Found ${decoded.length} items',
          );
          return decoded
              .map(
                (item) => RadioStation.fromJson(item as Map<String, dynamic>),
              )
              .where(
                (s) =>
                    s.url.isNotEmpty &&
                    !_unreliableStationsCache.contains(s.stationuuid),
              )
              .toList();
        }
        debugPrint(
          'RadioRepo: Proxy returned 200 but ${decoded is List ? "0 items" : "non-list body"}. Falling back to Direct...',
        );
      } else {
        debugPrint(
          'RadioRepo: Proxy FAILED with status ${response.statusCode}. Falling back to Direct...',
        );
      }
    } catch (e) {
      debugPrint('RadioRepo: Proxy EXCEPTION: $e. Falling back to Direct...');
    }

    // 2. Fallback to Direct (Mirrors)
    // We try 'stations/' prefix if the endpoint doesn't have it, as the base URL ends in /json
    final directEndpoint = endpoint.startsWith('stations/')
        ? endpoint
        : 'stations/$endpoint';
    final directUrl = Uri.parse('$_directUrl/$directEndpoint');
    debugPrint('RadioRepo: Attempting DIRECT: $directUrl');

    try {
      final response = await http
          .get(directUrl)
          .timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        final dynamic decoded = json.decode(response.body);
        if (decoded is List) {
          debugPrint(
            'RadioRepo: Direct SUCCESS - Found ${decoded.length} items',
          );
          return decoded
              .map(
                (item) => RadioStation.fromJson(item as Map<String, dynamic>),
              )
              .where(
                (s) =>
                    s.url.isNotEmpty &&
                    !_unreliableStationsCache.contains(s.stationuuid),
              )
              .toList();
        }
      }
      debugPrint('RadioRepo: Direct FAILED with status ${response.statusCode}');
    } catch (e) {
      debugPrint('RadioRepo: Direct EXCEPTION: $e');
    }

    return [];
  }

  // --- API Methods (Radio Browser) ---

  // Cache for unreliable stations to avoid fetching on every request
  Set<String> _unreliableStationsCache = {};
  DateTime? _lastCacheUpdate;

  Future<void> _updateUnreliableCache() async {
    // Refresh cache every 5 minutes
    if (_lastCacheUpdate != null &&
        DateTime.now().difference(_lastCacheUpdate!) <
            const Duration(minutes: 5)) {
      return;
    }

    try {
      // Define "Unreliable" as > 2 failures AND failure rate > 50% (simplified to > 2 failures for now)
      // Or just fetch everything with failures > 3
      final snapshot = await _firestore
          .collection('radio_station_health')
          .where('failureCount', isGreaterThan: 3)
          .get();

      _unreliableStationsCache = snapshot.docs.map((d) => d.id).toSet();
      _lastCacheUpdate = DateTime.now();
      debugPrint(
        'RadioHealth: Updated cache with ${_unreliableStationsCache.length} unreliable stations',
      );
    } catch (e) {
      debugPrint('RadioHealth: Failed to update cache (Check Indexes?): $e');
    }
  }

  Future<List<RadioStation>> getStationsByCountry(String countryCode) async {
    await _updateUnreliableCache();
    return _fetchWithFallback(
      'bycountrycodeexact/${countryCode.toUpperCase()}',
    );
  }

  Future<List<RadioStation>> searchStations(String query) async {
    await _updateUnreliableCache();
    final encodedQuery = Uri.encodeComponent(query);
    return _fetchWithFallback('search?name=$encodedQuery&limit=100');
  }

  Future<List<RadioStation>> getTopStations({int limit = 100}) async {
    await _updateUnreliableCache();
    return _fetchWithFallback('topclick/$limit');
  }

  // --- Reliability Reporting ---

  Future<void> reportFailure(String stationUuid) async {
    try {
      final docRef = _firestore
          .collection('radio_station_health')
          .doc(stationUuid);
      await docRef.set({
        'failureCount': cf.FieldValue.increment(1),
        'lastReported': cf.FieldValue.serverTimestamp(),
      }, cf.SetOptions(merge: true));
    } catch (e) {
      debugPrint('RadioHealth: Failed report failure: $e');
    }
  }

  Future<void> reportSuccess(String stationUuid) async {
    try {
      final docRef = _firestore
          .collection('radio_station_health')
          .doc(stationUuid);
      await docRef.set({
        'successCount': cf.FieldValue.increment(1),
        'lastReported': cf.FieldValue.serverTimestamp(),
      }, cf.SetOptions(merge: true));
    } catch (e) {
      debugPrint('RadioHealth: Failed report success: $e');
    }
  }

  // --- Firestore Methods (Favorites & History) ---

  Future<void> toggleFavorite(String userId, RadioStation station) async {
    try {
      final docRef = _firestore
          .collection('users')
          .doc(userId)
          .collection('radio_favorites')
          .doc(station.stationuuid);

      final doc = await docRef.get();

      if (doc.exists) {
        await docRef.delete();
      } else {
        await docRef.set({
          ...station.toJson(),
          'addedAt': cf.FieldValue.serverTimestamp(),
        });
      }
    } catch (e) {
      debugPrint('RadioRepo: Error toggling favorite: $e');
    }
  }

  Future<List<RadioStation>> getFavorites(String userId) async {
    try {
      final snapshot = await _firestore
          .collection('users')
          .doc(userId)
          .collection('radio_favorites')
          .orderBy('addedAt', descending: true)
          .get();

      return snapshot.docs
          .map((doc) => RadioStation.fromJson(_sanitizeStationData(doc.data())))
          .toList();
    } catch (e) {
      debugPrint('RadioRepo: Error fetching favorites: $e');
      return [];
    }
  }

  Future<void> addToHistory(String userId, RadioStation station) async {
    try {
      await _firestore
          .collection('users')
          .doc(userId)
          .collection('radio_history')
          .doc(station.stationuuid)
          .set({
            ...station.toJson(),
            'playedAt': cf.FieldValue.serverTimestamp(),
          });
    } catch (e) {
      debugPrint('RadioRepo: Error adding to history: $e');
    }
  }

  Future<List<RadioStation>> getHistory(String userId) async {
    try {
      final snapshot = await _firestore
          .collection('users')
          .doc(userId)
          .collection('radio_history')
          .orderBy('playedAt', descending: true)
          .limit(20)
          .get();

      return snapshot.docs
          .map((doc) => RadioStation.fromJson(_sanitizeStationData(doc.data())))
          .toList();
    } catch (e) {
      debugPrint('RadioRepo: Error fetching history: $e');
      return [];
    }
  }

  // Helper to ensure types match what RadioStation.fromJson expects
  Map<String, dynamic> _sanitizeStationData(Map<String, dynamic> data) {
    final sanitized = Map<String, dynamic>.from(data);
    if (sanitized['votes'] is String) {
      sanitized['votes'] = int.tryParse(sanitized['votes']) ?? 0;
    }
    if (sanitized['bitrate'] is String) {
      sanitized['bitrate'] = int.tryParse(sanitized['bitrate']) ?? 0;
    }
    // Ensure url_resolved exists (may be missing from older saved stations)
    sanitized['url_resolved'] ??= '';
    return sanitized;
  }
}
