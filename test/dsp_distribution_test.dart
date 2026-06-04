// ignore_for_file: avoid_print
/// Standalone verification test for DSP distribution logic.
/// Mirrors the exact algorithm from _distributeTreasuryPoints in points_repository.dart.
///
/// Run with: dart test test/dsp_distribution_test.dart
library;

import 'package:flutter_test/flutter_test.dart';

/// Simulates the exact distribution logic from _distributeTreasuryPoints.
/// Returns a map of communityId → DSP awarded (the `commUnit` value).
Map<String, int> simulateDistribution({
  required int amount,
  required List<String> memberships,
}) {
  final int unit = (amount * 0.1).round();

  // Helper to find membership by prefix
  String findMembership(String prefix) {
    return memberships
        .firstWhere(
          (id) => id.startsWith(prefix),
          orElse: () => '',
        )
        .toString();
  }

  // Build fractional distribution map
  final Map<String, double> communityFractions = {};

  void addSlot(String? id, double fraction) {
    final effectiveId = (id == null || id.isEmpty) ? 'global_community' : id;
    communityFractions[effectiveId] =
        (communityFractions[effectiveId] ?? 0) + fraction;
  }

  // Global: always full unit
  addSlot('global_community', 1.0);

  // Home hierarchy
  final homeContinent = findMembership('home_continent_');
  final homeCountry = findMembership('home_country_');
  final homeState = findMembership('home_state_');
  final homeCity = findMembership('home_city_');

  addSlot(homeContinent, 1.0);
  if (homeState.isNotEmpty) {
    addSlot(homeCountry, 0.5);
    addSlot(homeState, 0.5);
  } else {
    addSlot(homeCountry, 1.0);
  }
  addSlot(homeCity, 1.0);

  // Host hierarchy
  final hostContinent = findMembership('host_continent_');
  final hostCountry = findMembership('host_country_');
  final hostState = findMembership('host_state_');
  final hostCity = findMembership('host_city_');

  addSlot(hostContinent, 1.0);
  if (hostState.isNotEmpty) {
    addSlot(hostCountry, 0.5);
    addSlot(hostState, 0.5);
  } else {
    addSlot(hostCountry, 1.0);
  }
  addSlot(hostCity, 1.0);

  // Convert fractions to actual DSP units
  final Map<String, int> result = {};
  communityFractions.forEach((commId, fraction) {
    result[commId] = (unit * fraction).round();
  });

  // System treasuries
  result['founders'] = unit;
  result['liquidity'] = unit;
  result['burn'] = unit;

  return result;
}

void main() {
  group('DSP Distribution - State Split Logic', () {
    // =========================================================================
    // SCENARIO A: 3-Tier Home ↔ 3-Tier Host
    // User from Texas, USA living in Ontario, Canada
    // =========================================================================
    test('Scenario A: 3-tier home → 3-tier host', () {
      final result = simulateDistribution(
        amount: 1000,
        memberships: [
          'global_community',
          'home_continent_na',
          'home_country_us',
          'home_state_us_texas',
          'home_city_us_texas_houston',
          'host_continent_na',
          'host_country_ca',
          'host_state_ca_ontario',
          'host_city_ca_ontario_toronto_ng',
        ],
      );

      print('\n=== SCENARIO A: 3-Tier ↔ 3-Tier ===');
      result.forEach((k, v) => print('  $k: $v DSP'));

      // Community treasuries
      expect(result['global_community'], 100, reason: 'Global: full unit');
      expect(result['home_continent_na'], 100, reason: 'Home Continent: full');
      expect(result['home_country_us'], 50, reason: 'Home Country: SPLIT');
      expect(result['home_state_us_texas'], 50, reason: 'Home State: SPLIT');
      expect(result['home_city_us_texas_houston'], 100, reason: 'Home City: full');
      expect(result['host_continent_na'], 100, reason: 'Host Continent: full');
      expect(result['host_country_ca'], 50, reason: 'Host Country: SPLIT');
      expect(result['host_state_ca_ontario'], 50, reason: 'Host State: SPLIT');
      expect(result['host_city_ca_ontario_toronto_ng'], 100, reason: 'Host City: full');

      // System treasuries
      expect(result['founders'], 100);
      expect(result['liquidity'], 100);
      expect(result['burn'], 100);

      // Total verification
      final communityTotal = result.entries
          .where((e) => !['founders', 'liquidity', 'burn'].contains(e.key))
          .fold<int>(0, (sum, e) => sum + e.value);
      final systemTotal = result['founders']! + result['liquidity']! + result['burn']!;

      expect(communityTotal, 700, reason: 'Community pool must be 700');
      expect(systemTotal, 300, reason: 'System pool must be 300');
      expect(communityTotal + systemTotal, 1000, reason: 'Total must be 1000');

      print('  Community Total: $communityTotal');
      print('  System Total: $systemTotal');
      print('  Grand Total: ${communityTotal + systemTotal} ✅');
    });

    // =========================================================================
    // SCENARIO B: 2-Tier Home ↔ 2-Tier Host
    // User from Lagos, Nigeria living in Accra, Ghana
    // =========================================================================
    test('Scenario B: 2-tier home → 2-tier host', () {
      final result = simulateDistribution(
        amount: 1000,
        memberships: [
          'global_community',
          'home_continent_af',
          'home_country_ng',
          // NO home_state_ — 2-tier
          'home_city_ng_no-state_lagos',
          'host_continent_af',
          'host_country_gh',
          // NO host_state_ — 2-tier
          'host_city_gh_no-state_accra_ng',
        ],
      );

      print('\n=== SCENARIO B: 2-Tier ↔ 2-Tier ===');
      result.forEach((k, v) => print('  $k: $v DSP'));

      // Community treasuries
      expect(result['global_community'], 100, reason: 'Global: full unit');
      expect(result['home_continent_af'], 100, reason: 'Home Continent: full');
      expect(result['home_country_ng'], 100, reason: 'Home Country: FULL (no state)');
      expect(result['home_city_ng_no-state_lagos'], 100, reason: 'Home City: full');
      expect(result['host_continent_af'], 100, reason: 'Host Continent: full');
      expect(result['host_country_gh'], 100, reason: 'Host Country: FULL (no state)');
      expect(result['host_city_gh_no-state_accra_ng'], 100, reason: 'Host City: full');

      // System treasuries
      expect(result['founders'], 100);
      expect(result['liquidity'], 100);
      expect(result['burn'], 100);

      // Total verification
      final communityTotal = result.entries
          .where((e) => !['founders', 'liquidity', 'burn'].contains(e.key))
          .fold<int>(0, (sum, e) => sum + e.value);
      final systemTotal = result['founders']! + result['liquidity']! + result['burn']!;

      expect(communityTotal, 700, reason: 'Community pool must be 700');
      expect(systemTotal, 300, reason: 'System pool must be 300');
      expect(communityTotal + systemTotal, 1000, reason: 'Total must be 1000');

      print('  Community Total: $communityTotal');
      print('  System Total: $systemTotal');
      print('  Grand Total: ${communityTotal + systemTotal} ✅');
    });

    // =========================================================================
    // SCENARIO C: 2-Tier Home ↔ 3-Tier Host
    // User from Nairobi, Kenya living in California, USA
    // =========================================================================
    test('Scenario C: 2-tier home → 3-tier host', () {
      final result = simulateDistribution(
        amount: 1000,
        memberships: [
          'global_community',
          'home_continent_af',
          'home_country_ke',
          // NO home_state_ — Kenya is 2-tier
          'home_city_ke_no-state_nairobi',
          'host_continent_na',
          'host_country_us',
          'host_state_us_california', // USA is 3-tier
          'host_city_us_california_los-angeles_ke',
        ],
      );

      print('\n=== SCENARIO C: 2-Tier Home → 3-Tier Host ===');
      result.forEach((k, v) => print('  $k: $v DSP'));

      // Community treasuries
      expect(result['global_community'], 100, reason: 'Global: full unit');
      expect(result['home_continent_af'], 100, reason: 'Home Continent: full');
      expect(result['home_country_ke'], 100, reason: 'Home Country: FULL (no home state)');
      expect(result['home_city_ke_no-state_nairobi'], 100, reason: 'Home City: full');
      expect(result['host_continent_na'], 100, reason: 'Host Continent: full');
      expect(result['host_country_us'], 50, reason: 'Host Country: SPLIT (host state exists)');
      expect(result['host_state_us_california'], 50, reason: 'Host State: SPLIT');
      expect(result['host_city_us_california_los-angeles_ke'], 100, reason: 'Host City: full');

      // System treasuries
      expect(result['founders'], 100);
      expect(result['liquidity'], 100);
      expect(result['burn'], 100);

      // Total verification
      final communityTotal = result.entries
          .where((e) => !['founders', 'liquidity', 'burn'].contains(e.key))
          .fold<int>(0, (sum, e) => sum + e.value);
      final systemTotal = result['founders']! + result['liquidity']! + result['burn']!;

      expect(communityTotal, 700, reason: 'Community pool must be 700');
      expect(systemTotal, 300, reason: 'System pool must be 300');
      expect(communityTotal + systemTotal, 1000, reason: 'Total must be 1000');

      print('  Community Total: $communityTotal');
      print('  System Total: $systemTotal');
      print('  Grand Total: ${communityTotal + systemTotal} ✅');
    });

    // =========================================================================
    // SCENARIO D: 3-Tier Home ↔ 2-Tier Host
    // User from Florida, USA living in London, England
    // =========================================================================
    test('Scenario D: 3-tier home → 2-tier host', () {
      final result = simulateDistribution(
        amount: 1000,
        memberships: [
          'global_community',
          'home_continent_na',
          'home_country_us',
          'home_state_us_florida', // USA is 3-tier
          'home_city_us_florida_miami',
          'host_continent_eu',
          'host_country_gb-eng',
          // NO host_state_ — England is 2-tier
          'host_city_gb-eng_no-state_london_us',
        ],
      );

      print('\n=== SCENARIO D: 3-Tier Home → 2-Tier Host ===');
      result.forEach((k, v) => print('  $k: $v DSP'));

      // Community treasuries
      expect(result['global_community'], 100, reason: 'Global: full unit');
      expect(result['home_continent_na'], 100, reason: 'Home Continent: full');
      expect(result['home_country_us'], 50, reason: 'Home Country: SPLIT (home state exists)');
      expect(result['home_state_us_florida'], 50, reason: 'Home State: SPLIT');
      expect(result['home_city_us_florida_miami'], 100, reason: 'Home City: full');
      expect(result['host_continent_eu'], 100, reason: 'Host Continent: full');
      expect(result['host_country_gb-eng'], 100, reason: 'Host Country: FULL (no host state)');
      expect(result['host_city_gb-eng_no-state_london_us'], 100, reason: 'Host City: full');

      // System treasuries
      expect(result['founders'], 100);
      expect(result['liquidity'], 100);
      expect(result['burn'], 100);

      // Total verification
      final communityTotal = result.entries
          .where((e) => !['founders', 'liquidity', 'burn'].contains(e.key))
          .fold<int>(0, (sum, e) => sum + e.value);
      final systemTotal = result['founders']! + result['liquidity']! + result['burn']!;

      expect(communityTotal, 700, reason: 'Community pool must be 700');
      expect(systemTotal, 300, reason: 'System pool must be 300');
      expect(communityTotal + systemTotal, 1000, reason: 'Total must be 1000');

      print('  Community Total: $communityTotal');
      print('  System Total: $systemTotal');
      print('  Grand Total: ${communityTotal + systemTotal} ✅');
    });

    // =========================================================================
    // EDGE CASE: Same continent for home and host (fractions merge)
    // User from Houston TX, USA → Toronto ON, Canada (both North America)
    // =========================================================================
    test('Edge Case: Shared continent merges fractions correctly', () {
      final result = simulateDistribution(
        amount: 1000,
        memberships: [
          'global_community',
          'home_continent_na', // North America
          'home_country_us',
          'home_state_us_texas',
          'home_city_us_texas_houston',
          'host_continent_na', // Also North America — same ID!
          'host_country_ca',
          'host_state_ca_ontario',
          'host_city_ca_ontario_toronto_ng',
        ],
      );

      print('\n=== EDGE CASE: Shared Continent (NA + NA) ===');
      result.forEach((k, v) => print('  $k: $v DSP'));

      // home_continent_na and host_continent_na are DIFFERENT keys (different prefix)
      // so they each get their own full 100 DSP — no merging happens
      expect(result['home_continent_na'], 100,
          reason: 'Home continent gets its own full unit');
      expect(result['host_continent_na'], 100,
          reason: 'Host continent gets its own full unit');

      // Countries and states still split correctly
      expect(result['home_country_us'], 50);
      expect(result['home_state_us_texas'], 50);
      expect(result['host_country_ca'], 50);
      expect(result['host_state_ca_ontario'], 50);

      // Total still 700 community + 300 system = 1000
      final communityTotal = result.entries
          .where((e) => !['founders', 'liquidity', 'burn'].contains(e.key))
          .fold<int>(0, (sum, e) => sum + e.value);
      expect(communityTotal, 700, reason: 'Community pool must still be 700');
      print('  Community Total: $communityTotal ✅');
    });

    // =========================================================================
    // EDGE CASE: Missing slots overflow to global
    // User with no host city
    // =========================================================================
    test('Edge Case: Missing host city overflows to global', () {
      final result = simulateDistribution(
        amount: 1000,
        memberships: [
          'global_community',
          'home_continent_af',
          'home_country_ng',
          'home_city_ng_no-state_lagos',
          'host_continent_af',
          'host_country_gh',
          // NO host_city_ — missing
        ],
      );

      print('\n=== EDGE CASE: Missing Host City ===');
      result.forEach((k, v) => print('  $k: $v DSP'));

      // Missing host city → falls back to global_community
      // Global gets: 1.0 (own) + 1.0 (missing host city) = 2.0 × 100 = 200
      expect(result['global_community'], 200,
          reason: 'Global absorbs missing host city slot');

      final communityTotal = result.entries
          .where((e) => !['founders', 'liquidity', 'burn'].contains(e.key))
          .fold<int>(0, (sum, e) => sum + e.value);
      expect(communityTotal, 700, reason: 'Community pool must still be 700');
      print('  Community Total: $communityTotal ✅');
    });
  });
}
