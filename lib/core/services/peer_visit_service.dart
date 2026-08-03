import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:diaspora_nearby/features/dsp/services/points_service.dart';
import 'package:diaspora_nearby/core/utils/location_utils.dart';

final peerVisitServiceProvider = Provider<PeerVisitService>((ref) {
  return PeerVisitService(
    FirebaseFirestore.instance,
    ref.read(pointsServiceProvider),
  );
});

class PeerVisitService {
  final FirebaseFirestore _firestore;
  final PointsService _pointsService;

  // Active visit tracking memory: Key -> "visitorUid_hostUid", Value -> DateTime start
  final Map<String, DateTime> _activeVisitSessions = {};

  PeerVisitService(this._firestore, this._pointsService);

  /// Called during background location updates to evaluate if user [visitorUid]
  /// is visiting member [hostUid] at [hostLat],[hostLng] for >60 minutes.
  Future<void> checkProximityAndRecordVisit({
    required String visitorUid,
    required String hostUid,
    required double visitorLat,
    required double visitorLng,
    required double hostLat,
    required double hostLng,
    String? locationAddress,
  }) async {
    if (visitorUid == hostUid) return;

    // Check distance (50 meters threshold for home visit proximity)
    final distanceMeters = calculateDistance(
      visitorLat,
      visitorLng,
      hostLat,
      hostLng,
    );

    final sessionKey = '${visitorUid}_$hostUid';
    final now = DateTime.now();

    if (distanceMeters <= 50.0) {
      // User is within 50m of host location
      if (!_activeVisitSessions.containsKey(sessionKey)) {
        // Start tracking new visit session
        _activeVisitSessions[sessionKey] = now;
        debugPrint(
          '🏠 [PEER VISIT] Started visit session for visitor $visitorUid at host $hostUid location',
        );
      } else {
        // Session active, check duration
        final startTime = _activeVisitSessions[sessionKey]!;
        final durationMinutes = now.difference(startTime).inMinutes;

        if (durationMinutes >= 60) {
          debugPrint(
            '🎉 [PEER VISIT] 60+ minute visit confirmed! Visitor $visitorUid visited Host $hostUid for $durationMinutes mins.',
          );

          // Trigger reward calculation with rate-limit protection
          final success = await _pointsService.trackPeerVisitReward(
            hostUserId: hostUid,
            visitorUserId: visitorUid,
            locationAddress: locationAddress,
          );

          if (success) {
            // Reset session after successful award so it doesn't trigger repeatedly
            _activeVisitSessions.remove(sessionKey);
          }
        }
      }
    } else {
      // User left host proximity — reset active visit tracking
      if (_activeVisitSessions.containsKey(sessionKey)) {
        debugPrint(
          '🚪 [PEER VISIT] Visitor $visitorUid left host $hostUid location (distance: ${distanceMeters.toStringAsFixed(1)}m)',
        );
        _activeVisitSessions.remove(sessionKey);
      }
    }
  }
}
