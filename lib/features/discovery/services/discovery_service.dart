import 'package:cloud_functions/cloud_functions.dart';

class DiscoveryService {
  static final DiscoveryService _instance = DiscoveryService._internal();
  factory DiscoveryService() => _instance;
  DiscoveryService._internal();

  /// Returns a cache-friendly one-shot stream of privacy-safe profiles. Exact
  /// coordinates stay server-side; only computed distance is returned.
  Stream<List<Map<String, dynamic>>> getUsersNearby({
    double radiusInKm = 50,
    int limit = 50,
  }) async* {
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
    yield users;
  }
}
