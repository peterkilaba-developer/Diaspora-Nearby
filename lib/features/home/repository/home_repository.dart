import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:diaspora_nearby/features/profile/models/profile_data.dart';
import 'package:diaspora_nearby/features/auth/repository/auth_repository.dart';
import 'package:diaspora_nearby/features/chat/repository/chat_repository.dart';
import 'package:diaspora_nearby/core/utils/location_utils.dart';

final homeRepositoryProvider = Provider((ref) {
  final auth = ref.watch(authRepositoryProvider);
  final chatRepo = ref.watch(chatRepositoryProvider);
  return HomeRepository(FirebaseFirestore.instance, auth, chatRepo);
});

class HomeRepository {
  final FirebaseFirestore _firestore;
  final AuthRepository _auth;
  final ChatRepository _chatRepo;

  HomeRepository(this._firestore, this._auth, this._chatRepo);

  Future<List<ProfileData>> getNearbyUsers({bool isGlobal = false}) async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) return [];

      final currentUserDoc = await _firestore
          .collection('users')
          .doc(currentUser.uid)
          .get();
      if (!currentUserDoc.exists) return [];

      final currentUserData = currentUserDoc.data()!;
    final homeCountryCode = currentUserData['homeCountryCode'] as String?;
    final blockedUsers = currentUserData['blockedUsers'] as List<dynamic>? ?? [];
    final Set<String> blockedUserIds = 
        blockedUsers.map((e) => e.toString()).toSet();

    // Location variables for distance calc
    final currentUserProfile = ProfileData.fromJson(currentUserData);
    final myLat =
        currentUserProfile.currentLocation?.geometry.location.lat ??
        currentUserProfile.hostLocation.geometry?.location.lat ??
        0.0;
    final myLng =
        currentUserProfile.currentLocation?.geometry.location.lng ??
        currentUserProfile.hostLocation.geometry?.location.lng ??
        0.0;

    // 1. Fetch DM user IDs to exclude
    final Set<String> dmUserIds = {};
    try {
      // Note: we fetch ALL chats here to ensure we exclude all connected users.
      // ChatRepository.getUserChats() might filter out blocked users, but
      // we handle blocked users explicitly below.
      final chats = await _chatRepo.getUserChats();
      for (var chat in chats) {
        if (chat.type == 'direct') {
          for (var pid in chat.participants) {
            if (pid != currentUser.uid) dmUserIds.add(pid);
          }
        }
      }
    } catch (e) {
      // Continue even if chat fetch fails
    }

    Query query = _firestore.collection('users');

    // Note: We use the same filtering logic as before
    // [FIX] If homeCountryCode is null, we treat it as Global to avoid asymmetry
    // where one user filters and the other doesn't.
    if (!isGlobal && homeCountryCode != null) {
      // Local Code: Filter by homeCountryCode
      query = query.where('homeCountryCode', isEqualTo: homeCountryCode);
    }

    // Fetch more users (1000) for distance-based sorting and exclusion
    final snapshot = await query.limit(1000).get();

    final users = snapshot.docs
        .where((doc) {
          if (doc.id == currentUser.uid) return false;
          
          // [FIX] Exclude blocked users explicitly
          if (blockedUserIds.contains(doc.id)) return false;

          if (dmUserIds.contains(doc.id)) {
            return false; // Exclude connected users
          }
          return true;
        })
        .map((doc) {
          final data = doc.data() as Map<String, dynamic>;
          var profile = ProfileData.fromJson(data);
          profile.uid = doc.id;

          // [FIX] Double check if the other user has blocked US
          // This ensures asymmetry in blocking is also handled (though usually mutual in results)
          final theirBlockedList = data['blockedUsers'] as List<dynamic>? ?? [];
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
        })
        .whereType<ProfileData>() // Filter out nulls from mutual blocking check
        .toList();

    // Sort by distance (ascending)
    users.sort(
      (a, b) => (a.distance ?? 999999).compareTo(b.distance ?? 999999),
    );

    return users;
    } catch (e) {
      return [];
    }
  }

  Future<List<ProfileData>> searchUsers(String queryText) async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null || queryText.isEmpty) return [];

      final queryLower = queryText.toLowerCase();

      // Current user location for distance calc
      final currentUserDoc = await _firestore
          .collection('users')
          .doc(currentUser.uid)
          .get();
      
      if (!currentUserDoc.exists) return [];
      
      final currentUserData = currentUserDoc.data()!;
      final blockedUsers = currentUserData['blockedUsers'] as List<dynamic>? ?? [];
      final Set<String> blockedUserIds = 
          blockedUsers.map((e) => e.toString()).toSet();

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

      // 1. Fetch DM user IDs to exclude
      final Set<String> dmUserIds = {};
      try {
        final chats = await _chatRepo.getUserChats();
        for (var chat in chats) {
          if (chat.type == 'direct') {
            for (var pid in chat.participants) {
              if (pid != currentUser.uid) dmUserIds.add(pid);
            }
          }
        }
      } catch (e) {
        // Continue even if chat fetch fails
      }

      final snapshot = await _firestore.collection('users').limit(1000).get();

      final users = snapshot.docs
          .where((doc) {
            if (doc.id == currentUser.uid) return false;
            
            // [FIX] Exclude blocked users explicitly
            if (blockedUserIds.contains(doc.id)) return false;

            if (dmUserIds.contains(doc.id)) {
              return false; // Exclude connected users
            }
            
            final data = doc.data();
            
            // [FIX] Double check if the other user has blocked US
            final theirBlockedList = data['blockedUsers'] as List<dynamic>? ?? [];
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
              var profile = ProfileData.fromJson(data);
              if (myLat != null && myLng != null) {
                final theirLat =
                    profile.currentLocation?.geometry.location.lat ??
                    profile.hostLocation.geometry?.location.lat ??
                    0.0;
                final theirLng =
                    profile.currentLocation?.geometry.location.lng ??
                    profile.hostLocation.geometry?.location.lng ??
                    0.0;
                profile = profile.copyWith(
                  distance: calculateDistance(myLat, myLng, theirLat, theirLng),
                );
              }
              return profile;
            } catch (e) {
              return null;
            }
          })
          .whereType<ProfileData>()
          .toList();

      // Sort results by distance if available
      users.sort(
        (a, b) => (a.distance ?? 999999).compareTo(b.distance ?? 999999),
      );

      return users;
    } catch (e) {
      return [];
    }
  }

  Future<List<ProfileData>> getNearbyCompatriots() async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) return [];

      final currentUserDoc = await _firestore
          .collection('users')
          .doc(currentUser.uid)
          .get();
      if (!currentUserDoc.exists) return [];

      final currentUserData = currentUserDoc.data()!;
      final homeCountryCode = currentUserData['homeCountryCode'] as String?;
      if (homeCountryCode == null) return [];

      final currentUserProfile = ProfileData.fromJson(currentUserData);
      final myLat =
          currentUserProfile.currentLocation?.geometry.location.lat ??
          currentUserProfile.hostLocation.geometry?.location.lat ??
          0.0;
      final myLng =
          currentUserProfile.currentLocation?.geometry.location.lng ??
          currentUserProfile.hostLocation.geometry?.location.lng ??
          0.0;

      // 1. Fetch DM user IDs to exclude
      final Set<String> dmUserIds = {};
      try {
        final chats = await _chatRepo.getUserChats();
        for (var chat in chats) {
          if (chat.type == 'direct') {
            for (var pid in chat.participants) {
              if (pid != currentUser.uid) dmUserIds.add(pid);
            }
          }
        }
      } catch (e) {
        // Continue even if chat fetch fails
      }

      // 2. Query users from the same country
      final snapshot = await _firestore
          .collection('users')
          .where('homeCountryCode', isEqualTo: homeCountryCode)
          .get();

      final users = snapshot.docs
          .where((doc) {
            if (doc.id == currentUser.uid) return false;
            if (dmUserIds.contains(doc.id)) return false;
            return true;
          })
          .map((doc) {
            final data = doc.data();
            var profile = ProfileData.fromJson(data);
            profile.uid = doc.id;

            final theirLat =
                profile.currentLocation?.geometry.location.lat ??
                profile.hostLocation.geometry?.location.lat ??
                0.0;
            final theirLng =
                profile.currentLocation?.geometry.location.lng ??
                profile.hostLocation.geometry?.location.lng ??
                0.0;

            final distKm = calculateDistance(myLat, myLng, theirLat, theirLng);
            // Convert km to miles (1 km â‰ˆ 0.621371 miles)
            final distanceMiles = distKm * 0.621371;
            return profile.copyWith(distance: distanceMiles);
          })
          .where(
            (profile) => (profile.distance ?? 999999) <= 999,
          ) // Within 999 miles
          .toList();

      return users;
    } catch (e) {
      return [];
    }
  }
}
