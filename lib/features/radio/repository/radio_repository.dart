import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart' as cf;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:diaspora_nearby/models/radio_station.dart';
import 'package:diaspora_nearby/features/auth/repository/auth_repository.dart';

final radioRepositoryProvider = Provider((ref) => RadioRepository(
  firestore: cf.FirebaseFirestore.instance,
  auth: ref.read(authRepositoryProvider),
));

class RadioRepository {
  final cf.FirebaseFirestore _firestore;
  // ignore: unused_field
  final AuthRepository _auth;

  RadioRepository({
    required cf.FirebaseFirestore firestore,
    required AuthRepository auth,
  }) : _firestore = firestore, _auth = auth;

  // --- API Methods (Radio Browser) ---

  // Cache for unreliable stations to avoid fetching on every request
  Set<String> _unreliableStationsCache = {};
  DateTime? _lastCacheUpdate;

  Future<void> _updateUnreliableCache() async {
    // Refresh cache every 5 minutes
    if (_lastCacheUpdate != null && DateTime.now().difference(_lastCacheUpdate!) < const Duration(minutes: 5)) {
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
    } catch (e) {
      // Failed to update unreliable stations cache
    }
  }

  Future<List<RadioStation>> getStationsByCountry(String countryCode) async {
    await _updateUnreliableCache();
    try {
      // Use a known Radio Browser mirror. In production, we should probably resolve DNS or try multiple.
      final url = Uri.parse('https://de1.api.radio-browser.info/json/stations/bycountrycodeexact/${countryCode.toUpperCase()}');
      
      final response = await http.get(url).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.map((json) => RadioStation.fromJson(json))
            .where((s) => s.url.isNotEmpty && !_unreliableStationsCache.contains(s.stationuuid))
            .toList();
      } else {
        throw Exception('Failed to load stations');
      }
    } catch (e) {
      return [];
    }
  }

  Future<List<RadioStation>> getTopStations({int limit = 100}) async {
    await _updateUnreliableCache();
    try {
      final url = Uri.parse('https://de1.api.radio-browser.info/json/stations/topclick/$limit');
      final response = await http.get(url).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.map((json) => RadioStation.fromJson(json))
             .where((s) => !_unreliableStationsCache.contains(s.stationuuid))
             .toList();
      } else {
        throw Exception('Failed to load top stations');
      }
    } catch (e) {
      return [];
    }
  }

  // --- Reliability Reporting ---

  Future<void> reportFailure(String stationUuid) async {
    try {
      final docRef = _firestore.collection('radio_station_health').doc(stationUuid);
      await docRef.set({
        'failureCount': cf.FieldValue.increment(1),
        'lastReported': cf.FieldValue.serverTimestamp(),
      }, cf.SetOptions(merge: true));
    } catch (e) {
      // Failed to report radio failure
    }
  }

  Future<void> reportSuccess(String stationUuid) async {
    try {
      final docRef = _firestore.collection('radio_station_health').doc(stationUuid);
      await docRef.set({
        'successCount': cf.FieldValue.increment(1),
        'lastReported': cf.FieldValue.serverTimestamp(),
      }, cf.SetOptions(merge: true));
    } catch (e) {
        // Failed to report radio success
    }
  }
  
  // --- Firestore Methods (Favorites & History) ---
  
  Future<void> toggleFavorite(String userId, RadioStation station) async {
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
  }
  
  Future<List<RadioStation>> getFavorites(String userId) async {
    final snapshot = await _firestore
        .collection('users')
        .doc(userId)
        .collection('radio_favorites')
        .orderBy('addedAt', descending: true)
        .get();
        
    return snapshot.docs.map((doc) => RadioStation.fromJson(doc.data())).toList();
  }
  
  Future<void> addToHistory(String userId, RadioStation station) async {
     await _firestore
          .collection('users')
          .doc(userId)
          .collection('radio_history')
          .doc(station.stationuuid)
          .set({
            ...station.toJson(),
            'playedAt': cf.FieldValue.serverTimestamp(),
          });
  }
  
  Future<List<RadioStation>> getHistory(String userId) async {
      final snapshot = await _firestore
        .collection('users')
        .doc(userId)
        .collection('radio_history')
        .orderBy('playedAt', descending: true)
        .limit(20)
        .get();
        
    return snapshot.docs.map((doc) => RadioStation.fromJson(doc.data())).toList();
  }
}
