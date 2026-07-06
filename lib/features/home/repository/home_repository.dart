import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:diaspora_nearby/features/profile/models/profile_data.dart';
import 'package:diaspora_nearby/features/auth/repository/auth_repository.dart';
import 'package:diaspora_nearby/features/chat/repository/chat_repository.dart';
import 'package:diaspora_nearby/core/utils/location_utils.dart';
import 'package:diaspora_nearby/core/providers/view_mode_provider.dart';
import 'package:diaspora_nearby/features/profile/repository/profile_repository.dart';

final homeRepositoryProvider = Provider((ref) {
  final auth = ref.watch(authRepositoryProvider);
  return HomeRepository(FirebaseFirestore.instance, auth);
});

// ─── [PERF] Cached DM exclusion list ───
// Fetching all chats to build an exclusion set is expensive.
// Cache it for 10 minutes — only rebuild on explicit invalidation.
final _dmExclusionProvider = FutureProvider<Set<String>>((ref) async {
  final auth = ref.watch(authRepositoryProvider);
  final chatRepo = ref.watch(chatRepositoryProvider);
  final currentUser = auth.currentUser;
  if (currentUser == null) return {};

  final Set<String> dmUserIds = {};
  try {
    final chats = await chatRepo.getUserChats();
    for (var chat in chats) {
      if (chat.type == 'direct') {
        for (var pid in chat.participants) {
          if (pid != currentUser.uid) dmUserIds.add(pid);
        }
      }
    }
  } catch (e) {
    debugPrint('[PERF] DM exclusion fetch failed: $e');
  }
  return dmUserIds;
});

// ─── [PERF] Cached Nearby Users Provider ───
// Replaces the raw FutureBuilder approach. Data is cached and only
// re-fetched when the view mode changes or the user explicitly refreshes.
final nearbyUsersProvider =
    AsyncNotifierProvider<NearbyUsersNotifier, List<ProfileData>>(
      NearbyUsersNotifier.new,
    );

class NearbyUsersNotifier extends AsyncNotifier<List<ProfileData>> {
  // [PERF] In-memory cache with TTL to avoid hammering Firestore
  static List<ProfileData>? _cachedUsers;
  static ViewMode? _cachedViewMode;
  static DateTime _lastFetch = DateTime(2000);
  static const _cacheTtl = Duration(minutes: 3);

  @override
  Future<List<ProfileData>> build() async {
    final viewMode = ref.watch(nearbyViewModeProvider);
    final isGlobal = viewMode == ViewMode.global;

    // [PERF] Serve from cache if still fresh and same view mode
    final now = DateTime.now();
    if (_cachedUsers != null &&
        _cachedViewMode == viewMode &&
        now.difference(_lastFetch) < _cacheTtl) {
      debugPrint(
        '[PERF] nearbyUsersProvider CACHE HIT (${_cachedUsers!.length} users, ${now.difference(_lastFetch).inSeconds}s old)',
      );
      return _cachedUsers!;
    }

    debugPrint('[PERF] nearbyUsersProvider FETCHING (isGlobal=$isGlobal)');
    final repo = ref.read(homeRepositoryProvider);
    // Nearby data must not be blocked by a full chat-history scan. On a slow
    // or reconnecting Firestore client that scan can take indefinitely.
    final dmExclusion = await ref
        .watch(_dmExclusionProvider.future)
        .timeout(const Duration(seconds: 2), onTimeout: () => <String>{});
    final users = await repo.getNearbyUsers(
      isGlobal: isGlobal,
      dmExclusionIds: dmExclusion,
      currentUserProfile: ref.read(userProfileProvider).value,
    );

    // Cache result
    _cachedUsers = users;
    _cachedViewMode = viewMode;
    _lastFetch = DateTime.now();

    debugPrint('[PERF] nearbyUsersProvider FETCHED ${users.length} users');
    return users;
  }

  /// Force refresh — called by pull-to-refresh
  Future<void> refresh() async {
    _cachedUsers = null; // Bust cache
    _lastFetch = DateTime(2000);
    ref.invalidate(_dmExclusionProvider); // Also refresh DM exclusion
    ref.invalidateSelf();
  }
}

class HomeRepository {
  final FirebaseFirestore _firestore;
  final AuthRepository _auth;

  HomeRepository(this._firestore, this._auth);

  /// [PERF] Accepts pre-cached DM exclusion set to avoid re-fetching chats
  Future<List<ProfileData>> getNearbyUsers({
    bool isGlobal = false,
    Set<String> dmExclusionIds = const {},
    ProfileData? currentUserProfile,
  }) async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) return [];

      // [PERF] Use cache-first for current user doc — profile data doesn't
      // change frequently and cache-first avoids a network roundtrip.
      var profile = currentUserProfile;
      if (profile == null) {
        DocumentSnapshot<Map<String, dynamic>> currentUserDoc;
        try {
          currentUserDoc = await _firestore
              .collection('users')
              .doc(currentUser.uid)
              .get(const GetOptions(source: Source.cache))
              .timeout(const Duration(seconds: 2));
          if (!currentUserDoc.exists) {
            throw StateError('Current user profile is not cached');
          }
        } catch (_) {
          currentUserDoc = await _firestore
              .collection('users')
              .doc(currentUser.uid)
              .get()
              .timeout(const Duration(seconds: 8));
        }
        if (!currentUserDoc.exists || currentUserDoc.data() == null) return [];
        final data = Map<String, dynamic>.from(currentUserDoc.data()!);
        data['uid'] = currentUser.uid;
        profile = ProfileData.fromJson(data);
      }

      final homeCountryCode = profile.homeCountryCode;
      final blockedUsers = profile.blockedUsers ?? [];
      final Set<String> blockedUserIds = blockedUsers
          .map((e) => e.toString())
          .toSet();

      // Location variables for distance calc
      final myLat =
          profile.currentLocation?.geometry.location.lat ??
          profile.hostLocation.geometry?.location.lat ??
          0.0;
      final myLng =
          profile.currentLocation?.geometry.location.lng ??
          profile.hostLocation.geometry?.location.lng ??
          0.0;

      Query query = _firestore.collection('users');

      if (!isGlobal && homeCountryCode != null) {
        query = query.where('homeCountryCode', isEqualTo: homeCountryCode);
      }

      // [PERF] Reduced from 1000 → 200. 1000 docs was causing massive
      // read costs and slow parsing on mobile. 200 is plenty for a feed.
      QuerySnapshot snapshot;
      try {
        snapshot = await query
            .limit(200)
            .get(const GetOptions(source: Source.cache))
            .timeout(const Duration(seconds: 2));
        if (snapshot.docs.isEmpty) throw StateError('Nearby cache is empty');
      } catch (_) {
        snapshot = await query
            .limit(200)
            .get()
            .timeout(const Duration(seconds: 10));
      }

      final users = snapshot.docs
          .where((doc) {
            if (doc.id == currentUser.uid) return false;
            if (blockedUserIds.contains(doc.id)) return false;
            if (dmExclusionIds.contains(doc.id)) return false;
            return true;
          })
          .map((doc) {
            try {
              final data = doc.data() as Map<String, dynamic>;
              var profile = ProfileData.fromJson(data);
              profile.uid = doc.id;

              // Check if the other user has blocked US
              final theirBlockedList =
                  data['blockedUsers'] as List<dynamic>? ?? [];
              if (theirBlockedList.contains(currentUser.uid)) return null;

              // Calculate Distance
              final theirLat =
                  profile.currentLocation?.geometry.location.lat ??
                  profile.hostLocation.geometry?.location.lat ??
                  0.0;
              final theirLng =
                  profile.currentLocation?.geometry.location.lng ??
                  profile.hostLocation.geometry?.location.lng ??
                  0.0;

              final dist = calculateDistance(myLat, myLng, theirLat, theirLng);
              return profile.copyWith(distance: dist);
            } catch (e) {
              return null;
            }
          })
          .whereType<ProfileData>()
          .toList();

      // Sort by distance (ascending)
      users.sort(
        (a, b) => (a.distance ?? 999999).compareTo(b.distance ?? 999999),
      );

      return users;
    } catch (e) {
      debugPrint('[HomeRepository] getNearbyUsers error: $e');
      return [];
    }
  }

  Future<List<ProfileData>> searchUsers(String queryText) async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null || queryText.isEmpty) return [];

      final queryLower = queryText.toLowerCase();

      // [PERF] Use cache-first for current user doc
      DocumentSnapshot<Map<String, dynamic>> currentUserDoc;
      try {
        currentUserDoc = await _firestore
            .collection('users')
            .doc(currentUser.uid)
            .get(const GetOptions(source: Source.cache))
            .timeout(const Duration(seconds: 2));
      } catch (_) {
        currentUserDoc = await _firestore
            .collection('users')
            .doc(currentUser.uid)
            .get();
      }

      if (!currentUserDoc.exists) return [];

      final currentUserData = currentUserDoc.data()!;
      final blockedUsers =
          currentUserData['blockedUsers'] as List<dynamic>? ?? [];
      final Set<String> blockedUserIds = blockedUsers
          .map((e) => e.toString())
          .toSet();

      double? myLat, myLng;
      final profile = ProfileData.fromJson(currentUserData);
      myLat =
          profile.currentLocation?.geometry.location.lat ??
          profile.hostLocation.geometry?.location.lat ??
          0.0;
      myLng =
          profile.currentLocation?.geometry.location.lng ??
          profile.hostLocation.geometry?.location.lng ??
          0.0;

      // [PERF] Reduced from 1000 → 200 for search as well
      final snapshot = await _firestore.collection('users').limit(200).get();

      final users = snapshot.docs
          .where((doc) {
            if (doc.id == currentUser.uid) return false;
            if (blockedUserIds.contains(doc.id)) return false;

            final data = doc.data();

            final theirBlockedList =
                data['blockedUsers'] as List<dynamic>? ?? [];
            if (theirBlockedList.contains(currentUser.uid)) return false;

            final firstName =
                (data['firstName'] as String?)?.toLowerCase() ?? '';
            final lastName = (data['lastName'] as String?)?.toLowerCase() ?? '';
            final fullName = '$firstName $lastName'.toLowerCase();

            final homeLoc = data['homeLocation'] as Map<String, dynamic>?;
            final hostLoc = data['hostLocation'] as Map<String, dynamic>?;
            final currLoc = data['currentLocation'] as Map<String, dynamic>?;

            final homeAddr =
                (homeLoc?['formatted_address'] as String?)?.toLowerCase() ?? '';
            final hostAddr =
                (hostLoc?['formatted_address'] as String?)?.toLowerCase() ?? '';
            final currAddr =
                (currLoc?['formatted_address'] as String?)?.toLowerCase() ?? '';

            final homeCity = (homeLoc?['city'] as String?)?.toLowerCase() ?? '';
            final hostCity = (hostLoc?['city'] as String?)?.toLowerCase() ?? '';
            final currCity = (currLoc?['city'] as String?)?.toLowerCase() ?? '';

            final homeCountry =
                (homeLoc?['country'] as String?)?.toLowerCase() ?? '';
            final hostCountry =
                (hostLoc?['country'] as String?)?.toLowerCase() ?? '';
            final currCountryCode =
                (currLoc?['countryCode'] as String?)?.toLowerCase() ?? '';

            final query = queryLower;

            return fullName.contains(query) ||
                homeAddr.contains(query) ||
                hostAddr.contains(query) ||
                currAddr.contains(query) ||
                homeCity.contains(query) ||
                hostCity.contains(query) ||
                currCity.contains(query) ||
                homeCountry.contains(query) ||
                hostCountry.contains(query) ||
                currCountryCode.contains(query);
          })
          .map((doc) {
            final data = doc.data();
            data['uid'] = doc.id;
            try {
              var userProfile = ProfileData.fromJson(data);
              if (myLat != null && myLng != null) {
                final theirLat =
                    userProfile.currentLocation?.geometry.location.lat ??
                    userProfile.hostLocation.geometry?.location.lat ??
                    0.0;
                final theirLng =
                    userProfile.currentLocation?.geometry.location.lng ??
                    userProfile.hostLocation.geometry?.location.lng ??
                    0.0;
                userProfile = userProfile.copyWith(
                  distance: calculateDistance(myLat, myLng, theirLat, theirLng),
                );
              }
              return userProfile;
            } catch (e) {
              return null;
            }
          })
          .whereType<ProfileData>()
          .toList();

      users.sort(
        (a, b) => (a.distance ?? 999999).compareTo(b.distance ?? 999999),
      );

      return users;
    } catch (e) {
      debugPrint('[HomeRepository] searchUsers error: $e');
      return [];
    }
  }
}
