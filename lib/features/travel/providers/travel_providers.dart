import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:diaspora_nearby/features/travel/services/airport_service.dart';
import 'package:diaspora_nearby/features/travel/services/amadeus_service.dart';

final airportServiceProvider = Provider<AirportService>((ref) {
  return AirportService();
});

final amadeusServiceProvider = Provider<AmadeusService>((ref) {
  return AmadeusService();
});
