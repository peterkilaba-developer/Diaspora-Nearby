import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter/foundation.dart';
import 'package:geoflutterfire_plus/geoflutterfire_plus.dart';
import 'package:diaspora_nearby/config/env.dart';
import 'package:diaspora_nearby/core/services/google_places_service.dart';
import 'package:diaspora_nearby/features/shared/models/location.dart'
    as loc_model;
import 'package:diaspora_nearby/core/utils/location_utils.dart';

/// Service to update user's current location in Firestore in real time.
/// Uses native + Google reverse geocoding for accurate sub-locality (neighborhood)
/// and locality resolution, streams live movement, and feeds the
/// server-authoritative proximity dwell (100 ft / >10 min) and
/// Grassroots Gathering (100 ft / >60 min) engines.
class LocationUpdateService {
  static final LocationUpdateService _instance =
      LocationUpdateService._internal();
  factory LocationUpdateService() => _instance;
  LocationUpdateService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final GooglePlacesService _placesService = GooglePlacesService(
    Env.googleMapsApiKey,
  );
  final Map<String, DateTime> _lastUpdateByUser = {};
  final Map<String, Position> _lastPositionByUser = {};
  final Map<String, Map<String, dynamic>> _lastGeocodedByUser = {};
  Timer? _heartbeatTimer;
  StreamSubscription<Position>? _positionStreamSub;
  String? _heartbeatUserId;
  bool _isUpdating = false;

  /// Starts a real-time foreground position stream (35m movement filter) AND
  /// a 3-minute periodic location heartbeat so:
  ///   1. Moving between neighborhoods / sub-localities updates user cards in real time.
  ///   2. Stationary devices meeting within 100 feet continuously advance the
  ///      10-minute automatic proximity timer and 60-minute Grassroots Gathering timer.
  void startProximityHeartbeat(String userId) {
    if (userId.isEmpty) return;
    final alreadyTrackingUser = _heartbeatUserId == userId;

    if (!alreadyTrackingUser) {
      stopProximityHeartbeat();
      _heartbeatUserId = userId;
    }

    if (_heartbeatTimer == null || !_heartbeatTimer!.isActive) {
      _heartbeatTimer = Timer.periodic(const Duration(minutes: 3), (_) {
        unawaited(updateCurrentLocation(userId));
      });
    }

    if (_positionStreamSub == null) {
      unawaited(_startRealtimePositionStream(userId));
    }
  }

  Future<void> _startRealtimePositionStream(String userId) async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }
      if (_heartbeatUserId != userId || _positionStreamSub != null) return;

      const int distanceFilterMeters = 35;
      final LocationSettings settings;
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        settings = AndroidSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: distanceFilterMeters,
        );
      } else if (!kIsWeb &&
          (defaultTargetPlatform == TargetPlatform.iOS ||
              defaultTargetPlatform == TargetPlatform.macOS)) {
        settings = AppleSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: distanceFilterMeters,
          pauseLocationUpdatesAutomatically: true,
        );
      } else {
        settings = const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: distanceFilterMeters,
        );
      }

      _positionStreamSub = Geolocator.getPositionStream(
        locationSettings: settings,
      ).listen(
        (Position pos) {
          cacheLastKnownPosition(pos);
          if (_heartbeatUserId == userId) {
            unawaited(updateCurrentLocation(userId, providedPosition: pos));
          }
        },
        onError: (Object e) {
          debugPrint('LocationUpdateService: Position stream error: $e');
        },
      );
    } catch (e) {
      debugPrint('LocationUpdateService: Could not start position stream: $e');
    }
  }

  /// Stops the foreground proximity heartbeat timer and real-time position stream.
  void stopProximityHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _positionStreamSub?.cancel();
    _positionStreamSub = null;
    _heartbeatUserId = null;
  }

  /// Updates the user's current location in Firestore.
  /// Resolves sub-locality (neighborhood) + locality for real-time UserCard display.
  Future<void> updateCurrentLocation(
    String userId, {
    Position? providedPosition,
    bool force = false,
  }) async {
    if (userId.isEmpty || _isUpdating) return;
    _isUpdating = true;
    try {
      final now = DateTime.now();
      final lastUpdate = _lastUpdateByUser[userId];
      final lastPos = _lastPositionByUser[userId];

      // Allow immediate updates when forced or when the user moved >= 35 meters;
      // otherwise throttle rapid duplicate calls within 30 seconds.
      if (!force && lastUpdate != null) {
        final elapsed = now.difference(lastUpdate);
        bool movedSignificantly = false;
        if (providedPosition != null && lastPos != null) {
          final movedMeters =
              calculateDistance(
                lastPos.latitude,
                lastPos.longitude,
                providedPosition.latitude,
                providedPosition.longitude,
              ) *
              1000.0;
          movedSignificantly = movedMeters >= 35.0;
        }
        if (!movedSignificantly && elapsed < const Duration(seconds: 30)) {
          return;
        }
        if (movedSignificantly && elapsed < const Duration(seconds: 5)) {
          return;
        }
      }

      Position? position = providedPosition;
      if (position == null) {
        // Check permission
        LocationPermission permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied) {
          permission = await Geolocator.requestPermission();
        }

        if (permission == LocationPermission.denied ||
            permission == LocationPermission.deniedForever) {
          return;
        }

        // Get current position with high accuracy for 100-ft proximity detection
        try {
          position = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
              timeLimit: Duration(seconds: 10),
            ),
          );
        } catch (e) {
          debugPrint(
            'LocationUpdateService: Failed to get current position ($e). Trying last known...',
          );
          position = await Geolocator.getLastKnownPosition();
        }
      }

      if (position == null) {
        debugPrint('LocationUpdateService: No location available.');
        return;
      }

      // Start live foreground stream once we know location is permitted
      if (_positionStreamSub == null && _heartbeatUserId == userId) {
        unawaited(_startRealtimePositionStream(userId));
      }

      _lastUpdateByUser[userId] = DateTime.now();
      cacheLastKnownPosition(position);

      // Reuse cached reverse-geocoding if device moved < 30m and we already have a subLocality/city
      Map<String, dynamic>? geocoded;
      final prevPos = _lastPositionByUser[userId];
      final prevGeo = _lastGeocodedByUser[userId];
      if (!force && prevPos != null && prevGeo != null) {
        final movedMeters =
            calculateDistance(
              prevPos.latitude,
              prevPos.longitude,
              position.latitude,
              position.longitude,
            ) *
            1000.0;
        if (movedMeters < 30.0 &&
            (prevGeo['subLocality'] != null || prevGeo['city'] != null)) {
          geocoded = prevGeo;
        }
      }

      geocoded ??= await _placesService.reverseGeocode(
        position.latitude,
        position.longitude,
      );

      _lastPositionByUser[userId] = position;
      if (geocoded != null) {
        _lastGeocodedByUser[userId] = geocoded;
      } else if (prevGeo != null && prevPos != null) {
        final movedKm = calculateDistance(
          prevPos.latitude,
          prevPos.longitude,
          position.latitude,
          position.longitude,
        );
        // Keep last resolved labels on transient network blips if still within ~1km
        if (movedKm < 1.0) {
          geocoded = prevGeo;
        }
      }

      String? subLocality = geocoded?['subLocality'] as String?;
      String? city = geocoded?['city'] as String?;
      String? state = geocoded?['state'] as String?;
      String? country = geocoded?['country'] as String?;
      String? countryCode = geocoded?['countryCode'] as String?;

      if (subLocality != null && subLocality.trim().isEmpty) {
        subLocality = null;
      }
      if (city != null && city.trim().isEmpty) {
        city = null;
      }
      if (subLocality != null &&
          isSameOrRedundantLocationPart(subLocality, city)) {
        subLocality = null;
      }

      String formattedAddress =
          (geocoded?['formattedAddress'] as String?)?.trim() ?? '';
      if (formattedAddress.isEmpty) {
        final parts = [
          subLocality,
          city,
          state,
          country,
        ].whereType<String>().where((p) => p.trim().isNotEmpty).toList();
        formattedAddress = parts.isNotEmpty
            ? parts.join(', ')
            : '${position.latitude}, ${position.longitude}';
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
        'subLocality': subLocality,
        'city': city,
        'state': state,
        'country': country,
        'countryCode': countryCode,
        'country_code': countryCode,
        'isLiveGps': true,
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

      // [PERF] Commit public and private location updates in a single atomic batch.
      // Writing to user_private/{userId} triggers checkProximity in Cloud Functions,
      // which evaluates both 100-ft / 10-min Automatic Proximity Rewards and
      // 100-ft / 60-min Grassroots Gathering rewards server-authoritatively.
      final batch = _firestore.batch();
      if (showCity) {
        final safeLat = (position.latitude * 100).round() / 100;
        final safeLng = (position.longitude * 100).round() / 100;
        final summaryParts = [
          subLocality,
          city,
          state,
          country,
        ].whereType<String>().where((p) => p.trim().isNotEmpty).join(', ');
        final publicCurrentLocation = {
          'formatted_address': summaryParts,
          'place_id': '',
          'subLocality': subLocality,
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
          'currentSubLocality': subLocality ?? FieldValue.delete(),
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
    } catch (e) {
      debugPrint('LocationUpdateService: Failed to update location: $e');
    } finally {
      _isUpdating = false;
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
        'isLiveGps': false,
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
