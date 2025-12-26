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
  static final GlobalUserSearchService _instance = GlobalUserSearchService._internal();
  factory GlobalUserSearchService() => _instance;
  GlobalUserSearchService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Calculate match score for prefix matching
  /// Returns 0 for no match, higher scores for better matches
  int _calculateMatchScore(String text, String query) {
    final lowerText = text.toLowerCase();
    final lowerQuery = query.toLowerCase();

    // Exact match = 100
    if (lowerText == lowerQuery) {
      return 100;
    }

    // Starts with query = 90
    if (lowerText.startsWith(lowerQuery)) {
      return 90;
    }

    // Check if any word starts with query = 80
    final words = lowerText.split(RegExp(r'\s+'));
    for (final word in words) {
      if (word.startsWith(lowerQuery)) {
        return 80;
      }
    }

    // No match
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
      // Get all users from Firestore
      final snapshot = await _firestore.collection('users').get();
      final allUsers = snapshot.docs;

      final results = <UserSearchResult>[];

      for (final doc in allUsers) {
        final data = doc.data();
        final userId = doc.id;

        // Skip excluded user (typically the current user)
        if (excludeUserId != null && userId == excludeUserId) {
          continue;
        }

        // Skip users without required fields
        final firstName = data['firstName'] as String?;
        final lastName = data['lastName'] as String?;
        if (firstName == null || lastName == null || firstName.isEmpty || lastName.isEmpty) {
          continue;
        }

        bool matched = false;
        int matchScore = 0;
        String matchType = 'name';
        String matchedText = '';

        // Search in user names
        if (searchNames) {
          final fullName = '$firstName $lastName';
          final firstNameScore = _calculateMatchScore(firstName, trimmedQuery);
          final lastNameScore = _calculateMatchScore(lastName, trimmedQuery);
          final fullNameScore = _calculateMatchScore(fullName, trimmedQuery);

          final nameScore = [firstNameScore, lastNameScore, fullNameScore]
              .reduce((a, b) => a > b ? a : b);

          if (nameScore > 0) {
            matched = true;
            matchScore = nameScore + 10; // Boost name matches
            matchType = 'name';
            matchedText = fullName;
          }
        }

        // Search in locations (if name didn't match)
        if (searchLocations && !matched) {
          // Check home location
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

          // Check host location
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

        // Add to results if matched
        if (matched) {
          final homeLocation = data['homeLocation'] as Map<String, dynamic>?;
          final hostLocation = data['hostLocation'] as Map<String, dynamic>?;
          final currentLocation = data['currentLocation'] as Map<String, dynamic>?;

          // Extract city/state from currentLocation first, then hostLocation
          String? city = currentLocation?['city'] as String?;
          String? state = currentLocation?['state'] as String?;
          String? currentLocationCountryCode = currentLocation?['countryCode'] as String?;
          
          // Fallback to hostLocation if currentLocation doesn't have city/state
          if (city == null || city.isEmpty) {
            city = hostLocation?['city'] as String?;
          }
          if (state == null || state.isEmpty) {
            state = hostLocation?['state'] as String?;
          }
          if (currentLocationCountryCode == null || currentLocationCountryCode.isEmpty) {
            currentLocationCountryCode = data['hostCountryCode'] as String?;
          }

          results.add(UserSearchResult(
            id: userId,
            firstName: firstName,
            lastName: lastName,
            // Try 'profilePhoto' first (standard), then 'profileImage' (legacy/fallback)
            profileImage: (data['profilePhoto'] ?? data['profileImage']) as String?,
            homeLocationAddress: homeLocation?['formatted_address'] as String? ?? 'Unknown',
            hostLocationAddress: hostLocation?['formatted_address'] as String? ?? 'Unknown',
            currentLocationAddress: currentLocation?['formatted_address'] as String?,
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
          ));
        }
      }

      // Sort by match score (highest first)
      results.sort((a, b) => b.matchScore.compareTo(a.matchScore));

      // Limit results
      return results.take(maxResults).toList();
    } catch (e) {
      rethrow;
    }
  }
}
