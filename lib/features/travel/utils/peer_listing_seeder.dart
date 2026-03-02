import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:diaspora_nearby/features/shared/utils/mock_photos.dart';

/// Seeds mock peer listings (stays + cars) across multiple countries.
class PeerListingSeeder {
  static final _firestore = FirebaseFirestore.instance;
  static final _col = _firestore.collection('peer_listings');

  static Future<void> seed() async {
    debugPrint('[PeerListingSeeder] Seeding mock peer listings...');
    final batch = _firestore.batch();

    for (final listing in _mockStays) {
      batch.set(_col.doc(), listing);
    }
    for (final listing in _mockCars) {
      batch.set(_col.doc(), listing);
    }

    await batch.commit();
    debugPrint('[PeerListingSeeder] Seeded ${_mockStays.length} stays + ${_mockCars.length} cars');
  }

  static Future<void> clear() async {
    debugPrint('[PeerListingSeeder] Clearing mock peer listings...');
    final snap = await _col.where('ownerId', isEqualTo: 'mock-seed').get();
    final batch = _firestore.batch();
    for (final doc in snap.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();
    debugPrint('[PeerListingSeeder] Cleared ${snap.docs.length} mock listings');
  }

  // ─── Mock Stays ────────────────────────────────────────────────────────

  static final _mockStays = <Map<String, dynamic>>[
    _stay(
      title: 'Cozy Downtown Apartment',
      city: 'Houston', state: 'Texas', country: 'United States', code: 'US',
      subLocality: 'Midtown',
      price: 85, beds: 1, baths: 1, guests: 2, type: 'Apartment',
      amenities: ['Wi-Fi', 'Kitchen', 'AC', 'TV', 'Parking'],
      lat: 29.7504, lng: -95.3698,
      photos: MockPhotos.stayHoustonPhotos,
    ),
    _stay(
      title: 'Spacious Family House',
      city: 'Dallas', state: 'Texas', country: 'United States', code: 'US',
      subLocality: 'Highland Park',
      price: 150, beds: 3, baths: 2, guests: 6, type: 'House',
      amenities: ['Wi-Fi', 'Kitchen', 'Pool', 'Parking', 'Washer', 'Dryer', 'AC'],
      lat: 32.8347, lng: -96.7782,
      photos: MockPhotos.stayDallasPhotos,
    ),
    _stay(
      title: 'Modern Studio Loft',
      city: 'Austin', state: 'Texas', country: 'United States', code: 'US',
      subLocality: 'South Congress',
      price: 70, beds: 1, baths: 1, guests: 2, type: 'Studio',
      amenities: ['Wi-Fi', 'Kitchen', 'AC', 'Workspace', 'TV'],
      lat: 30.2472, lng: -97.7538,
      photos: MockPhotos.stayAustinPhotos,
    ),
    _stay(
      title: 'Luxury Villa with Pool',
      city: 'Miami', state: 'Florida', country: 'United States', code: 'US',
      subLocality: 'South Beach',
      price: 280, beds: 4, baths: 3, guests: 8, type: 'Villa',
      amenities: ['Wi-Fi', 'Kitchen', 'Pool', 'AC', 'Parking', 'Gym', 'TV'],
      lat: 25.7826, lng: -80.1340,
      photos: MockPhotos.stayMiamiPhotos,
    ),
    _stay(
      title: 'Harare City Centre Flat',
      city: 'Harare', state: 'Harare', country: 'Zimbabwe', code: 'ZW',
      subLocality: 'Avondale',
      price: 45, beds: 2, baths: 1, guests: 4, type: 'Apartment',
      amenities: ['Wi-Fi', 'Kitchen', 'Parking', 'TV'],
      lat: -17.7938, lng: 31.0456,
      photos: MockPhotos.stayHararePhotos,
    ),
    _stay(
      title: 'Safari Lodge Room',
      city: 'Victoria Falls', state: 'Matabeleland North', country: 'Zimbabwe', code: 'ZW',
      subLocality: 'Chinotimba',
      price: 120, beds: 1, baths: 1, guests: 2, type: 'Room',
      amenities: ['Wi-Fi', 'Pool', 'AC', 'TV'],
      lat: -17.9244, lng: 25.8570,
      photos: MockPhotos.stayVicFallsPhotos,
    ),
    _stay(
      title: 'Bulawayo Garden Cottage',
      city: 'Bulawayo', state: 'Bulawayo', country: 'Zimbabwe', code: 'ZW',
      subLocality: 'Hillside',
      price: 35, beds: 1, baths: 1, guests: 2, type: 'House',
      amenities: ['Wi-Fi', 'Kitchen', 'Parking', 'Heating'],
      lat: -20.1325, lng: 28.6266,
      photos: MockPhotos.stayBulawayoPhotos,
    ),
    _stay(
      title: 'London Shoreditch Flat',
      city: 'London', state: 'England', country: 'United Kingdom', code: 'GB',
      subLocality: 'Shoreditch',
      price: 110, beds: 1, baths: 1, guests: 2, type: 'Apartment',
      amenities: ['Wi-Fi', 'Kitchen', 'Washer', 'TV', 'Heating'],
      lat: 51.5267, lng: -0.0808,
      photos: MockPhotos.stayLondonPhotos,
    ),
    _stay(
      title: 'Johannesburg Sandton Condo',
      city: 'Johannesburg', state: 'Gauteng', country: 'South Africa', code: 'ZA',
      subLocality: 'Sandton',
      price: 90, beds: 2, baths: 1, guests: 4, type: 'Condo',
      amenities: ['Wi-Fi', 'Kitchen', 'Pool', 'Gym', 'Parking', 'AC'],
      lat: -26.1076, lng: 28.0567,
      photos: MockPhotos.stayJoziPhotos,
    ),
    _stay(
      title: 'Lagos Victoria Island Suite',
      city: 'Lagos', state: 'Lagos', country: 'Nigeria', code: 'NG',
      subLocality: 'Victoria Island',
      price: 75, beds: 1, baths: 1, guests: 2, type: 'Apartment',
      amenities: ['Wi-Fi', 'AC', 'TV', 'Gym', 'Pool'],
      lat: 6.4281, lng: 3.4219,
      photos: MockPhotos.stayLagosPhotos,
    ),
  ];

  // ─── Mock Cars ─────────────────────────────────────────────────────────

  static final _mockCars = <Map<String, dynamic>>[
    _car(
      title: 'Toyota Camry 2022',
      make: 'Toyota', model: 'Camry', year: 2022,
      city: 'Houston', state: 'Texas', country: 'United States', code: 'US',
      subLocality: 'Galleria',
      price: 55, seats: 5, transmission: 'Automatic', fuel: 'Petrol',
      features: ['AC', 'GPS', 'Bluetooth', 'Backup Camera'],
      lat: 29.7329, lng: -95.4614,
      photos: MockPhotos.carCamryPhotos,
    ),
    _car(
      title: 'Honda Civic 2023',
      make: 'Honda', model: 'Civic', year: 2023,
      city: 'Dallas', state: 'Texas', country: 'United States', code: 'US',
      subLocality: 'Deep Ellum',
      price: 50, seats: 5, transmission: 'Automatic', fuel: 'Petrol',
      features: ['AC', 'Bluetooth', 'USB Charging'],
      lat: 32.7833, lng: -96.7833,
      photos: MockPhotos.carCivicPhotos,
    ),
    _car(
      title: 'Ford Explorer 2021',
      make: 'Ford', model: 'Explorer', year: 2021,
      city: 'Austin', state: 'Texas', country: 'United States', code: 'US',
      subLocality: 'Downtown',
      price: 80, seats: 7, transmission: 'Automatic', fuel: 'Petrol',
      features: ['AC', 'GPS', 'Bluetooth', 'Roof Rack', 'Backup Camera'],
      lat: 30.2672, lng: -97.7431,
      photos: MockPhotos.carExplorerPhotos,
    ),
    _car(
      title: 'Tesla Model 3',
      make: 'Tesla', model: 'Model 3', year: 2023,
      city: 'Miami', state: 'Florida', country: 'United States', code: 'US',
      subLocality: 'Brickell',
      price: 95, seats: 5, transmission: 'Automatic', fuel: 'Electric',
      features: ['AC', 'GPS', 'Bluetooth', 'Dashcam', 'USB Charging'],
      lat: 25.7617, lng: -80.1918,
      photos: MockPhotos.carTeslaPhotos,
    ),
    _car(
      title: 'Toyota Hilux Pickup',
      make: 'Toyota', model: 'Hilux', year: 2019,
      city: 'Harare', state: 'Harare', country: 'Zimbabwe', code: 'ZW',
      subLocality: 'Borrowdale',
      price: 40, seats: 5, transmission: 'Manual', fuel: 'Diesel',
      features: ['AC', 'Bluetooth'],
      lat: -17.7611, lng: 31.0867,
      photos: MockPhotos.carHiluxPhotos,
    ),
    _car(
      title: 'Nissan NP200 Bakkie',
      make: 'Nissan', model: 'NP200', year: 2020,
      city: 'Bulawayo', state: 'Bulawayo', country: 'Zimbabwe', code: 'ZW',
      subLocality: 'City Centre',
      price: 30, seats: 2, transmission: 'Manual', fuel: 'Petrol',
      features: ['AC'],
      lat: -20.1500, lng: 28.5833,
      photos: MockPhotos.carBakkiePhotos,
    ),
    _car(
      title: 'BMW 3 Series 2022',
      make: 'BMW', model: '3 Series', year: 2022,
      city: 'London', state: 'England', country: 'United Kingdom', code: 'GB',
      subLocality: 'Westminster',
      price: 85, seats: 5, transmission: 'Automatic', fuel: 'Petrol',
      features: ['AC', 'GPS', 'Bluetooth', 'Backup Camera', 'Dashcam'],
      lat: 51.4975, lng: -0.1357,
      photos: MockPhotos.carBMWPhotos,
    ),
    _car(
      title: 'VW Polo 2021',
      make: 'Volkswagen', model: 'Polo', year: 2021,
      city: 'Johannesburg', state: 'Gauteng', country: 'South Africa', code: 'ZA',
      subLocality: 'Rosebank',
      price: 35, seats: 5, transmission: 'Manual', fuel: 'Petrol',
      features: ['AC', 'Bluetooth', 'USB Charging'],
      lat: -26.1456, lng: 28.0442,
      photos: MockPhotos.carPoloPhotos,
    ),
    _car(
      title: 'Toyota Corolla 2020',
      make: 'Toyota', model: 'Corolla', year: 2020,
      city: 'Lagos', state: 'Lagos', country: 'Nigeria', code: 'NG',
      subLocality: 'Lekki',
      price: 45, seats: 5, transmission: 'Automatic', fuel: 'Petrol',
      features: ['AC', 'Bluetooth'],
      lat: 6.4698, lng: 3.5852,
      photos: MockPhotos.carCorollaPhotos,
    ),
  ];

  // ─── Builders ──────────────────────────────────────────────────────────

  static Map<String, dynamic> _stay({
    required String title,
    required String city,
    required String state,
    required String country,
    required String code,
    required String subLocality,
    required double price,
    required int beds,
    required int baths,
    required int guests,
    required String type,
    required List<String> amenities,
    required double lat,
    required double lng,
    List<String> photos = const [],
  }) {
    return {
      'type': 'stay',
      'ownerId': 'mock-seed',
      'ownerName': 'Mock Host',
      'ownerPhoto': '',
      'title': title,
      'description': 'A lovely $type in $subLocality, $city. Perfect for travelers.',
      'photos': photos,
      'pricePerUnit': price,
      'currency': 'USD',
      'status': 'active',
      'city': city,
      'country': country,
      'countryCode': code,
      'lat': lat,
      'lng': lng,
      'address': '$subLocality, $city',
      'locality': city,
      'subLocality': subLocality,
      'state': state,
      'localityLower': city.toLowerCase(),
      'stateLower': state.toLowerCase(),
      'createdAt': FieldValue.serverTimestamp(),
      'propertyType': type,
      'beds': beds,
      'baths': baths,
      'maxGuests': guests,
      'amenities': amenities,
    };
  }

  static Map<String, dynamic> _car({
    required String title,
    required String make,
    required String model,
    required int year,
    required String city,
    required String state,
    required String country,
    required String code,
    required String subLocality,
    required double price,
    required int seats,
    required String transmission,
    required String fuel,
    required List<String> features,
    required double lat,
    required double lng,
    List<String> photos = const [],
  }) {
    return {
      'type': 'car',
      'ownerId': 'mock-seed',
      'ownerName': 'Mock Owner',
      'ownerPhoto': '',
      'title': title,
      'description': '$year $make $model available for rent in $subLocality, $city.',
      'photos': photos,
      'pricePerUnit': price,
      'currency': 'USD',
      'status': 'active',
      'city': city,
      'country': country,
      'countryCode': code,
      'lat': lat,
      'lng': lng,
      'address': '$subLocality, $city',
      'locality': city,
      'subLocality': subLocality,
      'state': state,
      'localityLower': city.toLowerCase(),
      'stateLower': state.toLowerCase(),
      'createdAt': FieldValue.serverTimestamp(),
      'make': make,
      'model': model,
      'year': year,
      'transmission': transmission,
      'seats': seats,
      'fuelType': fuel,
      'features': features,
    };
  }
}
