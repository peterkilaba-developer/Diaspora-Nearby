import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geoflutterfire_plus/geoflutterfire_plus.dart';


class DiscoveryService {
  static final DiscoveryService _instance = DiscoveryService._internal();
  factory DiscoveryService() => _instance;
  DiscoveryService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Get users within a radius (in km) of a center point.
  /// Returns a Stream of list of DocumentSnapshots with distance data.
  Stream<List<DocumentSnapshot<Map<String, dynamic>>>> getUsersNearby({
    required GeoPoint center,
    required double radiusInKm,
    String? excludeUserId,
  }) {
    final CollectionReference<Map<String, dynamic>> collectionReference = _firestore.collection('users');
    final centerGeoPoint = GeoFirePoint(center);

    // Filter by the 'geo' field where we store the geohash data
    // The field name 'geo' must match what we saved in LocationUpdateService
    return GeoCollectionReference(collectionReference)
        .subscribeWithin(
      center: centerGeoPoint,
      radiusInKm: radiusInKm,
      field: 'geo',
      geopointFrom: (data) => (data['geo'] as Map<String, dynamic>)['geopoint'] as GeoPoint,
    );
  }
}

/// Simple wrapper or extension to handle the results if needed, 
/// but GeoDocumentSnapshot gives us the document and the distance.
