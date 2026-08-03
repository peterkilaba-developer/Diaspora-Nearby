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

          // Extract city - try multiple fields
          city =
              placemark.locality ??
              placemark.subLocality ??
              placemark.subAdministrativeArea;

          state = placemark.administrativeArea;
          country = placemark.country;
          countryCode = placemark.isoCountryCode;

          // Build formatted address
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

      // Create currentLocation data matching React structure
      final currentLocationData = {
        'formatted_address': formattedAddress,
        'place_id': '', // Not available from geocoding package
        'geometry': {
          'location': {'lat': position.latitude, 'lng': position.longitude},
        },
        'city': city,
        'state': state,
        'country': country,
        'countryCode': countryCode,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };

      // Determine whether to auto-enable city visibility for the +10 PCT.
      // We award it the moment we have the user's current location — but
      // never re-enable it if they've already forfeited the +10 by hiding.
      final userDoc = await _firestore.collection('users').doc(userId).get();
      final userData = userDoc.data() ?? {};
      final forfeited = userData['cityVisibilityForfeited'] == true;
      final hasExplicitChoice = userData.containsKey('showCurrentLocationName');

      final updates = <String, dynamic>{
        'currentLocation': currentLocationData,
        'geo': geoFirePoint.data, // Add geohash data for queries
        'locationUpdatedAt': FieldValue.serverTimestamp(),
      };

      // First-ever location fetch + user hasn't forfeited → grant visibility,
      // which immediately triggers the +10 City Visibility PCT.
      if (!forfeited && !hasExplicitChoice) {
        updates['showCurrentLocationName'] = true;
      }

      // Update Firestore
      await _firestore.collection('users').doc(userId).update(updates);

      // Check for automatic RSVP'd event attendance within 100 meters
      await _checkGeofencedEventAttendance(userId, position.latitude, position.longitude);
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

      // Query active published events where user is listed in 'attendees'
      final snapshot = await _firestore
          .collection('events')
          .where('attendees', arrayContains: userId)
          .where('status', isEqualTo: 'published')
          .get();

      for (var doc in snapshot.docs) {
        final data = doc.data();
        final eventId = doc.id;

        // Check if user is already confirmed
        final confirmed = List<String>.from(data['confirmedAttendees'] ?? []);
        if (confirmed.contains(userId)) continue;

        // Check venue coordinates or plus code
        double? venueLat = (data['latitude'] as num?)?.toDouble();
        double? venueLng = (data['longitude'] as num?)?.toDouble();

        final plusCode = data['plusCode'] as String?;
        if ((venueLat == null || venueLng == null) && plusCode != null && plusCode.isNotEmpty) {
          final decoded = PlusCodeService.decode(plusCode);
          if (decoded != null) {
            venueLat = decoded['latitude'];
            venueLng = decoded['longitude'];
          }
        }

        if (venueLat == null || venueLng == null) continue;

        // Calculate distance in kilometers, convert to meters
        final distanceKm = calculateDistance(
          userLat,
          userLng,
          venueLat,
          venueLng,
        );
        final distanceMeters = distanceKm * 1000.0;

        if (distanceMeters <= 100.0) {
          // Check event timeframe
          final startDateStr = data['startDate'] as String? ?? '';
          final startTimeStr = data['startTime'] as String? ?? '00:00';
          final endDateStr = data['endDate'] as String? ?? startDateStr;
          final endTimeStr = data['endTime'] as String? ?? '23:59';

          DateTime? start;
          DateTime? end;

          try {
            start = DateTime.parse('$startDateStr $startTimeStr');
          } catch (_) {
            try { start = DateTime.parse(startDateStr); } catch (_) {}
          }

          try {
            end = DateTime.parse('$endDateStr $endTimeStr');
          } catch (_) {
            try { end = DateTime.parse(endDateStr); } catch (_) {}
          }

          start ??= now;
          end ??= start.add(const Duration(hours: 3));

          // Allow check-in from 30 mins before start until 1 hour after end
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

      await _firestore.collection('users').doc(userId).update(updates);
    } catch (e) {
      debugPrint(
        'LocationUpdateService: Failed to fallback to host location: $e',
      );
    }
  }
}
