import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Service that fetches and caches live exchange rates.
///
/// Uses the free Open Exchange Rates API (no key required) with USD as base.
/// Rates are cached in SharedPreferences and refreshed every 6 hours.
/// Falls back to hardcoded rates if the network request fails.
class ExchangeRateService {
  ExchangeRateService._();

  static final ExchangeRateService instance = ExchangeRateService._();

  static const _cacheKey = 'cached_exchange_rates';
  static const _cacheTimestampKey = 'exchange_rates_timestamp';
  static const _cacheDuration = Duration(hours: 6);

  /// Free API — returns all rates based on USD, no API key needed.
  static const _apiUrl = 'https://open.er-api.com/v6/latest/USD';

  /// Live rates: currency code → units per 1 USD (e.g. {"KES": 155, "GBP": 0.79})
  Map<String, double>? _rates;

  /// Whether rates have been loaded (from cache or network).
  bool get isLoaded => _rates != null && _rates!.isNotEmpty;

  /// Get the rate for a currency code (units per 1 USD).
  /// Returns null if not available.
  double? getRate(String currencyCode) {
    return _rates?[currencyCode.toUpperCase()];
  }

  /// Initialize: load from cache, refresh from network if stale.
  /// Call this once at app startup (e.g. in main.dart or a provider).
  Future<void> initialize() async {
    // 1. Try loading from cache
    await _loadFromCache();

    // 2. Check if we need a fresh fetch
    if (_shouldRefresh()) {
      await _fetchFromNetwork();
    }
  }

  /// Force a fresh fetch from the network.
  Future<void> refresh() async {
    await _fetchFromNetwork();
  }

  // ── Private helpers ──────────────────────────────────────────────────────

  bool _shouldRefresh() {
    if (_rates == null || _rates!.isEmpty) return true;
    return _isCacheExpired();
  }

  bool _isCacheExpired() {
    try {
      // We'll check the timestamp when loading from cache
      return _cacheExpired;
    } catch (_) {
      return true;
    }
  }

  bool _cacheExpired = true;

  Future<void> _loadFromCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString(_cacheKey);
      final timestamp = prefs.getInt(_cacheTimestampKey);

      if (cached != null && timestamp != null) {
        final age = DateTime.now().millisecondsSinceEpoch - timestamp;
        _cacheExpired = age > _cacheDuration.inMilliseconds;

        final decoded = jsonDecode(cached) as Map<String, dynamic>;
        _rates = decoded.map((k, v) => MapEntry(k, (v as num).toDouble()));
        debugPrint(
            'ExchangeRateService: Loaded ${_rates!.length} rates from cache '
            '(age: ${Duration(milliseconds: age).inMinutes}min, '
            'expired: $_cacheExpired)');
      } else {
        _cacheExpired = true;
      }
    } catch (e) {
      debugPrint('ExchangeRateService: Cache load error: $e');
      _cacheExpired = true;
    }
  }

  Future<void> _fetchFromNetwork() async {
    try {
      debugPrint('ExchangeRateService: Fetching live rates from API...');
      final response = await http
          .get(Uri.parse(_apiUrl))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final ratesJson = json['rates'] as Map<String, dynamic>?;

        if (ratesJson != null && ratesJson.isNotEmpty) {
          _rates =
              ratesJson.map((k, v) => MapEntry(k, (v as num).toDouble()));
          _cacheExpired = false;

          // Persist to cache
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(_cacheKey, jsonEncode(_rates));
          await prefs.setInt(
              _cacheTimestampKey, DateTime.now().millisecondsSinceEpoch);

          debugPrint(
              'ExchangeRateService: Fetched ${_rates!.length} live rates ✓');
        }
      } else {
        debugPrint(
            'ExchangeRateService: API returned ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('ExchangeRateService: Network fetch failed: $e');
      // Keep using cached/hardcoded rates — no crash
    }
  }
}
