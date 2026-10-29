import 'dart:async';
import 'package:cloud_functions/cloud_functions.dart';

class DiscoveryService {
  static final DiscoveryService _instance = DiscoveryService._internal();
  factory DiscoveryService() => _instance;
  DiscoveryService._internal();

  static List<Map<String, dynamic>>? _cachedNearbyUsers;

  List<Map<String, dynamic>>? get cachedNearbyUsers => _cachedNearbyUsers;

  /// Returns a cache-friendly stream of privacy-safe profiles. Emits any
  /// in-memory cached profiles synchronously on frame 0 before refreshing.
  Stream<List<Map<String, dynamic>>> getUsersNearby({
    double radiusInKm = 50,
    int limit = 50,
  }) {
    return Stream<List<Map<String, dynamic>>>.multi((controller) {
      if (_cachedNearbyUsers != null) {
        controller.addSync(_cachedNearbyUsers!);
      }

      () async {
        try {
          final callable = FirebaseFunctions.instance.httpsCallable(
            'findNearbyUsers',
          );
          final result = await callable.call({
            'radiusKm': radiusInKm,
            'limit': limit,
          });
          final payload = Map<String, dynamic>.from(result.data as Map);
          final users = (payload['users'] as List<dynamic>? ?? const [])
              .map((item) => Map<String, dynamic>.from(item as Map))
              .toList(growable: false);
          _cachedNearbyUsers = users;
          if (!controller.isClosed) {
            controller.add(users);
            await controller.close();
          }
        } catch (e, st) {
          if (!controller.isClosed) {
            if (_cachedNearbyUsers == null) {
              controller.addError(e, st);
            }
            await controller.close();
          }
        }
      }();
    });
  }
}
