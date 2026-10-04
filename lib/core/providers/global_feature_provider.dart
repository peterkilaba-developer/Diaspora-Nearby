import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:diaspora_nearby/core/data/countries.dart' as country_data;

class GlobalUnlockStats {
  final bool isUnlocked;
  final int registeredCount;
  final int totalRequired;

  const GlobalUnlockStats({
    required this.isUnlocked,
    required this.registeredCount,
    required this.totalRequired,
  });
}

/// Evaluates unlock status against the actual supported-country set.
///
/// Counting distinct raw database values is not sufficient: legacy or invalid
/// country codes must never substitute for a required country.
@visibleForTesting
GlobalUnlockStats evaluateGlobalUnlock(
  Iterable<String?> registeredCountryCodes, {
  Iterable<String>? requiredCountryCodes,
}) {
  final required =
      (requiredCountryCodes ??
              country_data.countries.map((country) => country.code))
          .map((code) => code.trim().toUpperCase())
          .where((code) => code.isNotEmpty)
          .toSet();
  final registered = registeredCountryCodes
      .whereType<String>()
      .map((code) => code.trim().toUpperCase())
      .where(required.contains)
      .toSet();

  return GlobalUnlockStats(
    isUnlocked: required.isNotEmpty && registered.containsAll(required),
    registeredCount: registered.length,
    totalRequired: required.length,
  );
}

Iterable<String?> _countryCodesFromStats(Map<String, dynamic> data) {
  final value =
      data['countryCodes'] ??
      data['registeredCountryCodes'] ??
      data['countries'];
  if (value is Iterable) {
    return value.map((entry) => entry?.toString());
  }
  if (value is Map) {
    return value.entries
        .where((entry) => entry.value == true || entry.value == 1)
        .map((entry) => entry.key.toString());
  }
  return const <String?>[];
}

/// Provider exposing global unlock stats and country registration progress.
/// Reads a single pre-aggregated stat document in ~10ms with 0 byte bulk download.
final globalUnlockStatsProvider = FutureProvider<GlobalUnlockStats>((
  ref,
) async {
  final firestore = FirebaseFirestore.instance;
  final totalRequired = country_data.countries.length;

  // 1. Fast server count check (~10ms, 0 bytes payload)
  // If total registered users on the platform is less than total required countries (250),
  // global mode is GUARANTEED to be locked! Return false immediately.
  try {
    final countSnapshot = await firestore.collection('users').count().get();
    final totalUsers = countSnapshot.count ?? 0;
    if (totalUsers < totalRequired) {
      return GlobalUnlockStats(
        isUnlocked: false,
        registeredCount: totalUsers,
        totalRequired: totalRequired,
      );
    }
  } catch (e) {
    debugPrint('globalUnlockStatsProvider user count check error: $e');
    return GlobalUnlockStats(
      isUnlocked: false,
      registeredCount: 0,
      totalRequired: totalRequired,
    );
  }

  // 2. Only if total users >= totalRequired, check actual country-code coverage.
  try {
    final statsDoc = await firestore
        .collection('system_stats')
        .doc('registered_countries')
        .get();
    if (statsDoc.exists && statsDoc.data() != null) {
      final data = statsDoc.data()!;
      final statsCodes = _countryCodesFromStats(data).toList();
      if (statsCodes.isNotEmpty) {
        return evaluateGlobalUnlock(statsCodes);
      }
    }

    // A count-only aggregate cannot prove coverage. If the authoritative
    // country-code aggregate is missing or empty, fail closed instead of
    // downloading the entire users collection on app startup.
    return GlobalUnlockStats(
      isUnlocked: false,
      registeredCount: 0,
      totalRequired: totalRequired,
    );
  } catch (e) {
    debugPrint('globalUnlockStatsProvider system_stats fallback: $e');
  }

  // Default to locked when totalUsers < totalRequired or stats missing
  return GlobalUnlockStats(
    isUnlocked: false,
    registeredCount: 0,
    totalRequired: totalRequired,
  );
});

/// StreamProvider wrapping globalUnlockStatsProvider for backward compatibility.
final isGlobalUnlockedProvider = StreamProvider<bool>((ref) {
  final statsAsync = ref.watch(globalUnlockStatsProvider);
  return statsAsync.when(
    data: (data) => Stream.value(data.isUnlocked),
    loading: () => Stream.value(false),
    error: (e, st) => Stream.value(false),
  );
});

/// Synchronous boolean helper provider for quick checks.
/// Defaults to false while loading or when unlocked condition is not met.
final isGlobalUnlockedSyncProvider = Provider<bool>((ref) {
  final statsAsync = ref.watch(globalUnlockStatsProvider);
  return statsAsync.value?.isUnlocked ?? false;
});
