import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:flutter/foundation.dart';
import 'package:geoflutterfire_plus/geoflutterfire_plus.dart';
import 'package:diaspora_nearby/features/shared/models/location.dart'
    as loc_model;
import 'package:diaspora_nearby/core/services/plus_code_service.dart';
import 'package:diaspora_nearby/core/utils/location_utils.dart';

/// Service to update user's current location in Firestore.
/// Uses native geocoding for reliable reverse geocoding.
class LocationUpdateService {
  static final LocationUpdateService _instance =
      LocationUpdateService._internal();
  factory LocationUpdateService() => _instance;
  LocationUpdateService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Updates the user's current location in Firestore.
  /// Uses native geocoding to get full address details.
  Future<void> updateCurrentLocation(String userId) async {
    try {
      // Check permission
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }

      // Get current position
      Position? position;
      try {
        position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.medium,
            timeLimit: Duration(seconds: 10),
          ),
        );
      } catch (e) {
        debugPrint(
          'LocationUpdateService: Failed to get current position ($e). Trying last known...',
        );
        position = await Geolocator.getLastKnownPosition();
      }

      if (position == null) {
        debugPrint('LocationUpdateService: No location available.');
        return;
      }

      cacheLastKnownPosition(position);

      // Reverse geocode using native geocoding package
      String formattedAddress = '${position.latitude}, ${position.longitude}';
      String? city;
      String? state;
      String? country;
      String? countryCode;

      try {
        final placemarks = await placemarkFromCoordinates(
          position.latitude,
          position.longitude,
        );

        if (placemarks.isNotEmpty) {
          final placemark = placemarks.first;

          city =
              placemark.locality ??
              placemark.subLocality ??
              placemark.subAdministrativeArea;

          state = placemark.administrativeArea;
          country = placemark.country;
          countryCode = placemark.isoCountryCode;

          final addressParts = <String>[];
          if (placemark.street != null && placemark.street!.isNotEmpty) {
            addressParts.add(placemark.street!);
          }
          if (city != null && city.isNotEmpty) {
            addressParts.add(city);
          }
          if (state != null && state.isNotEmpty) {
            addressParts.add(state);
          }
          if (country != null && country.isNotEmpty) {
            addressParts.add(country);
          }

          if (addressParts.isNotEmpty) {
            formattedAddress = addressParts.join(', ');
          }
        }
      } catch (e) {
        // Silently continue with coordinates if geocoding fails
      }

      // Create GeoFirePoint for geospatial indexing
      final geoFirePoint = GeoFirePoint(
        GeoPoint(position.latitude, position.longitude),
      );

      final tsMs = DateTime.now().millisecondsSinceEpoch;
      final isoNow = DateTime.fromMillisecondsSinceEpoch(
        tsMs,
      ).toIso8601String();

      final currentLocationData = {
        'formatted_address': formattedAddress,
        'place_id': '',
        'geometry': {
          'location': {'lat': position.latitude, 'lng': position.longitude},
        },
        'city': city,
        'state': state,
        'country': country,
        'countryCode': countryCode,
        'country_code': countryCode,
        'timestamp': tsMs,
        'lastUpdated': isoNow,
      };

      // [PERF] Prefer local Firestore cache for user visibility flags
      DocumentSnapshot<Map<String, dynamic>>? userDoc;
      try {
        userDoc = await _firestore
            .collection('users')
            .doc(userId)
            .get(const GetOptions(source: Source.cache));
      } catch (_) {}
      if (userDoc == null || !userDoc.exists) {
        userDoc = await _firestore.collection('users').doc(userId).get();
      }
      final userData = userDoc.data() ?? {};
      final forfeited = userData['cityVisibilityForfeited'] == true;
      final hasExplicitChoice = userData.containsKey('showCurrentLocationName');
      final showCity = hasExplicitChoice
          ? userData['showCurrentLocationName'] != false
          : !forfeited;

      final updates = <String, dynamic>{
        'currentLocation': currentLocationData,
        'geo': geoFirePoint.data,
        'locationUpdatedAt': FieldValue.serverTimestamp(),
      };

      // [PERF] Commit public and private location updates in a single atomic batch
      final batch = _firestore.batch();
      if (showCity) {
        final safeLat = (position.latitude * 100).round() / 100;
        final safeLng = (position.longitude * 100).round() / 100;
        final summaryParts = [
          city,
          state,
          country,
        ].whereType<String>().where((p) => p.trim().isNotEmpty).join(', ');
        final publicCurrentLocation = {
          'formatted_address': summaryParts,
          'place_id': '',
          'city': city,
          'state': state,
          'country': country,
          'country_code': countryCode,
          'countryCode': countryCode,
          'timestamp': tsMs,
          'lastUpdated': isoNow,
          'geometry': {
            'location': {'lat': safeLat, 'lng': safeLng},
          },
        };
        batch.set(_firestore.collection('users').doc(userId), {
          if (!forfeited && !hasExplicitChoice) 'showCurrentLocationName': true,
          'currentCity': city,
          'currentState': state,
          'currentCountryCode': countryCode,
          'currentLocation': publicCurrentLocation,
        }, SetOptions(merge: true));
      }

      batch.set(
        _firestore.collection('user_private').doc(userId),
        updates,
        SetOptions(merge: true),
      );
      await batch.commit();

      // [PERF] Check for automatic RSVP'd event attendance in background
      unawaited(
        _checkGeofencedEventAttendance(
          userId,
          position.latitude,
          position.longitude,
        ),
      );
    } catch (e) {
      // Failed to update location
    }
  }

  /// Checks if the user is currently located within 100 meters of an active event venue
  /// they RSVP'd for, and auto-confirms attendance.
  Future<void> _checkGeofencedEventAttendance(
    String userId,
    double userLat,
    double userLng,
  ) async {
    try {
      final now = DateTime.now();

      final snapshot = await _firestore
          .collection('events')
          .where('attendees', arrayContains: userId)
          .where('status', isEqualTo: 'published')
          .limit(100)
          .get();

      for (var doc in snapshot.docs) {
        final data = doc.data();
        final eventId = doc.id;

        final confirmed = List<String>.from(data['confirmedAttendees'] ?? []);
        if (confirmed.contains(userId)) continue;

        double? venueLat = (data['latitude'] as num?)?.toDouble();
        double? venueLng = (data['longitude'] as num?)?.toDouble();

        final plusCode = data['plusCode'] as String?;
        if ((venueLat == null || venueLng == null) &&
            plusCode != null &&
            plusCode.isNotEmpty) {
          final decoded = PlusCodeService.decode(plusCode);
          if (decoded != null) {
            venueLat = decoded['latitude'];
            venueLng = decoded['longitude'];
          }
        }

        if (venueLat == null || venueLng == null) continue;

        final distanceKm = calculateDistance(
          userLat,
          userLng,
          venueLat,
          venueLng,
        );
        final distanceMeters = distanceKm * 1000.0;

        if (distanceMeters <= 100.0) {
          final startDateStr = data['startDate'] as String? ?? '';
          final startTimeStr = data['startTime'] as String? ?? '00:00';
          final endDateStr = data['endDate'] as String? ?? startDateStr;
          final endTimeStr = data['endTime'] as String? ?? '23:59';

          DateTime? start;
          DateTime? end;

          try {
            start = DateTime.parse('$startDateStr $startTimeStr');
          } catch (_) {
            try {
              start = DateTime.parse(startDateStr);
            } catch (_) {}
          }

          try {
            end = DateTime.parse('$endDateStr $endTimeStr');
          } catch (_) {
            try {
              end = DateTime.parse(endDateStr);
            } catch (_) {}
          }

          start ??= now;
          end ??= start.add(const Duration(hours: 3));

          final windowStart = start.subtract(const Duration(minutes: 30));
          final windowEnd = end.add(const Duration(hours: 1));

          if (now.isAfter(windowStart) && now.isBefore(windowEnd)) {
            debugPrint(
              '📍 [GEOFENCE AUTO CHECK-IN] User $userId is ${distanceMeters.toStringAsFixed(1)}m from event $eventId',
            );

            await _firestore.collection('events').doc(eventId).update({
              'confirmedAttendees': FieldValue.arrayUnion([userId]),
            });
          }
        }
      }
    } catch (e) {
      debugPrint('LocationUpdateService: Error in geofence event check: $e');
    }
  }

  /// Writes the user's host location into currentLocation and geo.
  /// Called when the user hides their current city — keeps proximity
  /// calculations working using the host city instead of stale GPS data.
  Future<void> fallbackToHostLocation(
    String userId,
    loc_model.UserLocation hostLocation,
  ) async {
    try {
      final lat = hostLocation.geometry?.location.lat;
      final lng = hostLocation.geometry?.location.lng;

      final currentLocationData = {
        'formatted_address': hostLocation.formattedAddress,
        'place_id': hostLocation.placeId,
        'geometry': {
          'location': {'lat': lat ?? 0.0, 'lng': lng ?? 0.0},
        },
        'city': hostLocation.city,
        'state': hostLocation.state,
        'country': hostLocation.country,
        'countryCode': hostLocation.countryCode,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };

      final updates = <String, dynamic>{
        'currentLocation': currentLocationData,
        'locationUpdatedAt': FieldValue.serverTimestamp(),
      };

      if (lat != null && lng != null) {
        final geoFirePoint = GeoFirePoint(GeoPoint(lat, lng));
        updates['geo'] = geoFirePoint.data;
      }

      await _firestore
          .collection('user_private')
          .doc(userId)
          .set(updates, SetOptions(merge: true));
    } catch (e) {
      debugPrint(
        'LocationUpdateService: Failed to fallback to host location: $e',
      );
    }
  }
}
