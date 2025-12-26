import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';

/// Service to update user's current location in Firestore.
/// Uses native geocoding for reliable reverse geocoding.
class LocationUpdateService {
  static final LocationUpdateService _instance = LocationUpdateService._internal();
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
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
        timeLimit: const Duration(seconds: 10),
      );

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
          city = placemark.locality ?? 
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

      // Create currentLocation data matching React structure
      final currentLocationData = {
        'formatted_address': formattedAddress,
        'place_id': '', // Not available from geocoding package
        'geometry': {
          'location': {
            'lat': position.latitude,
            'lng': position.longitude,
          },
        },
        'city': city,
        'state': state,
        'country': country,
        'countryCode': countryCode,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };

      // Update Firestore
      await _firestore.collection('users').doc(userId).update({
        'currentLocation': currentLocationData,
        'locationUpdatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      // Failed to update location
    }
  }
}
