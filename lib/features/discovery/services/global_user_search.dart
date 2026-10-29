import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Result from global user search
class UserSearchResult {
  final String id;
  final String firstName;
  final String lastName;
  final String? profileImage;
  final String homeLocationAddress;
  final String hostLocationAddress;
  final String? currentLocationAddress;
  final String? homeCountryCode;
  final String? hostCountryCode;
  final int matchScore;
  final String matchType; // 'name' or 'location'
  final String matchedText;
  // Location geometry for distance calculation
  final Map<String, dynamic>? currentLocationData;
  final Map<String, dynamic>? hostLocationData;
  // City/state for display
  final String? city;
  final String? state;
  final String? currentLocationCountryCode;

  UserSearchResult({
    required this.id,
    required this.firstName,
    required this.lastName,
    this.profileImage,
    required this.homeLocationAddress,
    required this.hostLocationAddress,
    this.currentLocationAddress,
    this.homeCountryCode,
    this.hostCountryCode,
    required this.matchScore,
    required this.matchType,
    required this.matchedText,
    this.currentLocationData,
    this.hostLocationData,
    this.city,
    this.state,
    this.currentLocationCountryCode,
  });
}

/// Global User Search Service
/// Provides comprehensive search functionality for users across the platform
class GlobalUserSearchService {
  static final GlobalUserSearchService _instance =
      GlobalUserSearchService._internal();
  factory GlobalUserSearchService() => _instance;
  GlobalUserSearchService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static List<QueryDocumentSnapshot<Map<String, dynamic>>>? _cachedUserDocs;
  static DateTime? _cachedAt;
  static bool _isRefreshing = false;
  static const _cacheTtl = Duration(minutes: 5);

  Future<void> _refreshCacheInBackground() async {
    if (_isRefreshing) return;
    _isRefreshing = true;
    try {
      final snapshot = await _firestore.collection('users').limit(100).get();
      _cachedUserDocs = snapshot.docs;
      _cachedAt = DateTime.now();
    } catch (_) {
    } finally {
      _isRefreshing = false;
    }
  }

  /// Calculate match score for prefix matching
  /// Returns 0 for no match, higher scores for better matches
  int _calculateMatchScore(String text, String query) {
    final lowerText = text.toLowerCase();
    final lowerQuery = query.toLowerCase();

    if (lowerText == lowerQuery) {
      return 100;
    }

    if (lowerText.startsWith(lowerQuery)) {
      return 90;
    }

    final words = lowerText.split(RegExp(r'\s+'));
    for (final word in words) {
      if (word.startsWith(lowerQuery)) {
        return 80;
      }
    }

    return 0;
  }

  /// Search users globally by name and location
  Future<List<UserSearchResult>> searchUsers(
    String query, {
    bool searchNames = true,
    bool searchLocations = true,
    int maxResults = 50,
    int minMatchLength = 2,
    String? excludeUserId,
  }) async {
    final trimmedQuery = query.trim();

    if (trimmedQuery.length < minMatchLength) {
      return [];
    }

    try {
      List<QueryDocumentSnapshot<Map<String, dynamic>>> allUsers;
      if (_cachedUserDocs != null) {
        allUsers = _cachedUserDocs!;
        if (_cachedAt == null ||
            DateTime.now().difference(_cachedAt!) >= _cacheTtl) {
          unawaited(_refreshCacheInBackground());
        }
      } else {
        final snapshot = await _firestore.collection('users').limit(100).get();
        allUsers = snapshot.docs;
        _cachedUserDocs = allUsers;
        _cachedAt = DateTime.now();
      }

      final results = <UserSearchResult>[];

      for (final doc in allUsers) {
        final data = doc.data();
        final userId = doc.id;

        if (excludeUserId != null && userId == excludeUserId) {
          continue;
        }

        final firstName = data['firstName'] as String?;
        final lastName = data['lastName'] as String?;
        if (firstName == null ||
            lastName == null ||
            firstName.isEmpty ||
            lastName.isEmpty) {
          continue;
        }

        bool matched = false;
        int matchScore = 0;
        String matchType = 'name';
        String matchedText = '';

        if (searchNames) {
          final fullName = '$firstName $lastName';
          final firstNameScore = _calculateMatchScore(firstName, trimmedQuery);
          final lastNameScore = _calculateMatchScore(lastName, trimmedQuery);
          final fullNameScore = _calculateMatchScore(fullName, trimmedQuery);

          final nameScore = [
            firstNameScore,
            lastNameScore,
            fullNameScore,
          ].reduce((a, b) => a > b ? a : b);

          if (nameScore > 0) {
            matched = true;
            matchScore = nameScore + 10;
            matchType = 'name';
            matchedText = fullName;
          }
        }

        if (searchLocations && !matched) {
          final homeLocation = data['homeLocation'] as Map<String, dynamic>?;
          final homeAddress = homeLocation?['formatted_address'] as String?;
          if (homeAddress != null) {
            final homeScore = _calculateMatchScore(homeAddress, trimmedQuery);
            if (homeScore > 0) {
              matched = true;
              matchScore = homeScore;
              matchType = 'location';
              matchedText = homeAddress;
            }
          }

          if (!matched) {
            final hostLocation = data['hostLocation'] as Map<String, dynamic>?;
            final hostAddress = hostLocation?['formatted_address'] as String?;
            if (hostAddress != null) {
              final hostScore = _calculateMatchScore(hostAddress, trimmedQuery);
              if (hostScore > 0) {
                matched = true;
                matchScore = hostScore;
                matchType = 'location';
                matchedText = hostAddress;
              }
            }
          }
        }

        if (matched) {
          final homeLocation = data['homeLocation'] as Map<String, dynamic>?;
          final hostLocation = data['hostLocation'] as Map<String, dynamic>?;
          final currentLocation =
              data['currentLocation'] as Map<String, dynamic>?;

          String? city = currentLocation?['city'] as String?;
          String? state = currentLocation?['state'] as String?;
          String? currentLocationCountryCode =
              currentLocation?['countryCode'] as String?;

          if (city == null || city.isEmpty) {
            city = hostLocation?['city'] as String?;
          }
          if (state == null || state.isEmpty) {
            state = hostLocation?['state'] as String?;
          }
          if (currentLocationCountryCode == null ||
              currentLocationCountryCode.isEmpty) {
            currentLocationCountryCode = data['hostCountryCode'] as String?;
          }

          results.add(
            UserSearchResult(
              id: userId,
              firstName: firstName,
              lastName: lastName,
              profileImage:
                  (data['profilePhoto'] ?? data['profileImage']) as String?,
              homeLocationAddress:
                  homeLocation?['formatted_address'] as String? ?? 'Unknown',
              hostLocationAddress:
                  hostLocation?['formatted_address'] as String? ?? 'Unknown',
              currentLocationAddress:
                  currentLocation?['formatted_address'] as String?,
              homeCountryCode: data['homeCountryCode'] as String?,
              hostCountryCode: data['hostCountryCode'] as String?,
              matchScore: matchScore,
              matchType: matchType,
              matchedText: matchedText,
              currentLocationData: currentLocation,
              hostLocationData: hostLocation,
              city: city,
              state: state,
              currentLocationCountryCode: currentLocationCountryCode,
            ),
          );
        }
      }

      results.sort((a, b) => b.matchScore.compareTo(a.matchScore));
      return results.take(maxResults).toList();
    } catch (e) {
      rethrow;
    }
  }
}
