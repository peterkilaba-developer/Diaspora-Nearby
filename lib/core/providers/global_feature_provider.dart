import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:diaspora_nearby/core/data/countries.dart' as country_data;

/// Provider that determines whether global features (Global View Toggle,
/// Global Community Chat, Global User Lists) are unlocked.
///
/// Global features remain locked until at least one user from EVERY country
/// defined in `countries.dart` is registered on the platform. This ensures
/// early adoption communities do not present misleading global listings.
final isGlobalUnlockedProvider = StreamProvider<bool>((ref) {
  final firestore = FirebaseFirestore.instance;

  return firestore.collection('users').snapshots().map((snapshot) {
    if (snapshot.docs.isEmpty) return false;

    final registeredCountries = <String>{};
    for (final doc in snapshot.docs) {
      final data = doc.data();
      final countryCode =
          data['homeCountryCode'] as String? ?? data['countryCode'] as String?;
      if (countryCode != null && countryCode.trim().isNotEmpty) {
        registeredCountries.add(countryCode.trim().toUpperCase());
      }
    }

    final totalRequiredCountries = country_data.countries.length;
    // Global mode is unlocked ONLY when every country in countries.dart has at least 1 registered user
    return registeredCountries.length >= totalRequiredCountries;
  });
});

/// Synchronous boolean helper provider for quick checks.
/// Defaults to false while loading or when unlocked condition is not met.
final isGlobalUnlockedSyncProvider = Provider<bool>((ref) {
  final asyncVal = ref.watch(isGlobalUnlockedProvider);
  return asyncVal.value ?? false;
});
