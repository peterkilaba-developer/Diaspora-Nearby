import 'dart:math';

import 'package:diaspora_nearby/features/travel/models/peer_listing.dart';

/// Centralised geography helpers used across the travel portal.
class GeoUtils {
  GeoUtils._();

  /// Haversine distance in **km** between two lat/lng pairs.
  static double haversine(double lat1, double lng1, double lat2, double lng2) {
    const r = 6371.0;
    final dLat = _deg2rad(lat2 - lat1);
    final dLng = _deg2rad(lng2 - lng1);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_deg2rad(lat1)) * cos(_deg2rad(lat2)) *
            sin(dLng / 2) * sin(dLng / 2);
    return r * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  static double _deg2rad(double deg) => deg * pi / 180;

  /// Sorts [listings] in-place by distance from ([refLat], [refLng]).
  /// Falls back to newest-first when the reference point is unavailable.
  static void sortByProximity(
    List<PeerListing> listings, {
    required double? refLat,
    required double? refLng,
  }) {
    if (refLat != null && refLng != null) {
      listings.sort((a, b) {
        final da = (a.lat != null && a.lng != null)
            ? haversine(refLat, refLng, a.lat!, a.lng!)
            : double.infinity;
        final db = (b.lat != null && b.lng != null)
            ? haversine(refLat, refLng, b.lat!, b.lng!)
            : double.infinity;
        return da.compareTo(db);
      });
    } else {
      listings.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    }
  }

  /// Extracts home-town lat/lng from a profile (dynamic to avoid tight coupling).
  /// Returns `null` pair if unavailable.
  static (double?, double?) homeLatLng(dynamic profile) {
    if (profile == null) return (null, null);
    try {
      final lat = profile.homeLocation?.geometry?.location?.lat as double?;
      final lng = profile.homeLocation?.geometry?.location?.lng as double?;
      return (lat, lng);
    } catch (_) {
      return (null, null);
    }
  }
}
