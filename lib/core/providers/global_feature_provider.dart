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

GlobalUnlockStats? _cachedGlobalUnlockStats;

/// Provider exposing global unlock stats and country registration progress.
/// Reads pre-aggregated stats in parallel and caches in memory for 0-latency access.
final globalUnlockStatsProvider = FutureProvider<GlobalUnlockStats>((
  ref,
) async {
  final firestore = FirebaseFirestore.instance;
  final totalRequired = country_data.countries.length;

  try {
    final results = await Future.wait([
      firestore.collection('users').count().get(),
      firestore.collection('system_stats').doc('registered_countries').get(),
    ]);

    final countSnapshot = results[0] as AggregateQuerySnapshot;
    final statsDoc = results[1] as DocumentSnapshot<Map<String, dynamic>>;

    final totalUsers = countSnapshot.count ?? 0;
    if (totalUsers < totalRequired) {
      final stats = GlobalUnlockStats(
        isUnlocked: false,
        registeredCount: totalUsers,
        totalRequired: totalRequired,
      );
      _cachedGlobalUnlockStats = stats;
      return stats;
    }

    if (statsDoc.exists && statsDoc.data() != null) {
      final data = statsDoc.data()!;
      final statsCodes = _countryCodesFromStats(data).toList();
      if (statsCodes.isNotEmpty) {
        final stats = evaluateGlobalUnlock(statsCodes);
        _cachedGlobalUnlockStats = stats;
        return stats;
      }
    }
  } catch (e) {
    debugPrint('globalUnlockStatsProvider error: $e');
    if (_cachedGlobalUnlockStats != null) {
      return _cachedGlobalUnlockStats!;
    }
  }

  final fallback = GlobalUnlockStats(
    isUnlocked: false,
    registeredCount: 0,
    totalRequired: totalRequired,
  );
  _cachedGlobalUnlockStats ??= fallback;
  return fallback;
});

/// StreamProvider wrapping globalUnlockStatsProvider for backward compatibility.
final isGlobalUnlockedProvider = StreamProvider<bool>((ref) {
  final statsAsync = ref.watch(globalUnlockStatsProvider);
  final fallback = _cachedGlobalUnlockStats?.isUnlocked ?? false;
  return statsAsync.when(
    data: (data) => Stream.value(data.isUnlocked),
    loading: () => Stream.value(fallback),
    error: (e, st) => Stream.value(fallback),
  );
});

/// Synchronous boolean helper provider for quick checks.
/// Uses in-memory cache while loading.
final isGlobalUnlockedSyncProvider = Provider<bool>((ref) {
  final statsAsync = ref.watch(globalUnlockStatsProvider);
  return statsAsync.value?.isUnlocked ??
      _cachedGlobalUnlockStats?.isUnlocked ??
      false;
});
