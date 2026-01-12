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
      print('RadioHealth: Updated cache with ${_unreliableStationsCache.length} unreliable stations');
    } catch (e) {
      print('RadioHealth: Failed to update cache (Check Indexes?): $e');
    }
  }

  Future<List<RadioStation>> getStationsByCountry(String countryCode) async {
    await _updateUnreliableCache();
    try {
      // Use the main load-balanced Radio Browser endpoint
      final url = Uri.parse('https://all.api.radio-browser.info/json/stations/bycountrycodeexact/${countryCode.toUpperCase()}');
      
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
      print('RadioRepo: Error fetching stations: $e');
      return [];
    }
  }

  Future<List<RadioStation>> getTopStations({int limit = 100}) async {
    await _updateUnreliableCache();
    try {
      final url = Uri.parse('https://all.api.radio-browser.info/json/stations/topclick/$limit');
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
      print('RadioRepo: Error fetching top stations: $e');
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
      print('RadioHealth: Failed report failure: $e');
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
       print('RadioHealth: Failed report success: $e');
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
    try {
      final snapshot = await _firestore
          .collection('users')
          .doc(userId)
          .collection('radio_favorites')
          .orderBy('addedAt', descending: true)
          .get();
          
      return snapshot.docs.map((doc) => RadioStation.fromJson(_sanitizeStationData(doc.data()))).toList();
    } catch (e) {
      print('RadioRepo: Error fetching favorites: $e');
      return [];
    }
  }
  
  Future<void> addToHistory(String userId, RadioStation station) async {
     // Limit history size to 20 technically handled by read limit but write should arguably prune old ones? 
     // For now just write.
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
    try {
      final snapshot = await _firestore
        .collection('users')
        .doc(userId)
        .collection('radio_history')
        .orderBy('playedAt', descending: true)
        .limit(20)
        .get();
        
      return snapshot.docs.map((doc) => RadioStation.fromJson(_sanitizeStationData(doc.data()))).toList();
    } catch (e) {
       print('RadioRepo: Error fetching history: $e');
       return [];
    }
  }

  // Helper to ensure types match what RadioStation.fromJson expects
  Map<String, dynamic> _sanitizeStationData(Map<String, dynamic> data) {
    if (data['votes'] is String) {
      data['votes'] = int.tryParse(data['votes']) ?? 0;
    }
    if (data['bitrate'] is String) {
      data['bitrate'] = int.tryParse(data['bitrate']) ?? 0;
    }
    // Remove timestamps that might confuse restrictive parsers (though usually ignored)
    // data.remove('addedAt');
    // data.remove('playedAt');
    return data;
  }
}
