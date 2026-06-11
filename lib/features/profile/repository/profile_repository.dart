import 'package:cloud_firestore/cloud_firestore.dart' as cf;

import 'package:firebase_storage/firebase_storage.dart';
import 'package:universal_io/io.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:diaspora_nearby/features/profile/models/profile_data.dart';
import 'package:diaspora_nearby/features/auth/repository/auth_repository.dart';
import 'package:diaspora_nearby/features/shared/models/location.dart';
import 'package:diaspora_nearby/features/auth/services/session_service.dart';

final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  final sessionService = ref.watch(sessionServiceProvider);
  return ProfileRepository(cf.FirebaseFirestore.instance, sessionService);
});

final userProfileProvider =
    AsyncNotifierProvider<UserProfileNotifier, ProfileData?>(
      UserProfileNotifier.new,
    );

// Added missing provider for fetching profile by ID
final userProfileByIdProvider = FutureProvider.family<ProfileData?, String>((
  ref,
  userId,
) async {
  final repo = ref.watch(profileRepositoryProvider);
  return repo.getUserProfile(userId);
});

class UserProfileNotifier extends AsyncNotifier<ProfileData?> {
  @override
  Future<ProfileData?> build() async {
    final auth = ref.watch(authStateProvider);
    final user = auth.asData?.value;
    if (user == null) return null;

    final repo = ref.watch(profileRepositoryProvider);
    return repo.getUserProfile(user.uid);
  }

  void updateProfile(ProfileData newProfile) {
    state = AsyncData(newProfile);
  }
}

class ProfileRepository {
  final cf.FirebaseFirestore _firestore;
  final SessionService _sessionService;

  ProfileRepository(this._firestore, this._sessionService);

  // [PERF] In-memory profile cache with TTL to avoid N+1 Firestore reads
  // in chat lists with many DM conversations
  static final Map<String, _CachedProfile> _profileCache = {};
  static const _cacheTtl = Duration(minutes: 5);

  /// Clear cache for a specific user (call after profile update)
  void invalidateProfileCache(String uid) => _profileCache.remove(uid);

  /// Clear entire cache (call on logout)
  void clearProfileCache() => _profileCache.clear();

  Future<ProfileData?> getUserProfile(String uid) async {
    // [PERF] Check in-memory cache first
    final cached = _profileCache[uid];
    if (cached != null && DateTime.now().difference(cached.fetchedAt) < _cacheTtl) {
      final p = cached.profile;
      // [FIX] Don't serve bare/FCM-only docs from cache — they have empty
      // firstName and should be re-fetched from Firestore to get real data.
      if (p != null && p.firstName.isEmpty) {
        debugPrint('📋 [getUserProfile] CACHE SKIP for bare/FCM-only doc (firstName empty) → re-fetching');
        _profileCache.remove(uid);
      } else {
        debugPrint('📋 [getUserProfile] CACHE HIT for $uid → '
            'firstName="${p?.firstName}", lastName="${p?.lastName}", '
            'profileImage="${p?.profileImage.isNotEmpty == true ? "SET" : "EMPTY"}", '
            'homeCity="${p?.homeLocation.city}"');
        return p;
      }
    }

    try {
      // Read Firestore's local cache first so returning users do not wait on
      // network/DNS before their profile can render. Fall back to the server
      // when the cache is empty or unavailable.
      cf.DocumentSnapshot<Map<String, dynamic>> doc;
      try {
        doc = await _firestore
            .collection('users')
            .doc(uid)
            .get(const cf.GetOptions(source: cf.Source.cache))
            .timeout(const Duration(seconds: 2));
        if (!doc.exists || doc.data() == null) {
          throw StateError('Profile is not cached');
        }
      } catch (_) {
        // Cache miss: fetch a fresh profile from the server.
        doc = await _firestore
            .collection('users')
            .doc(uid)
            .get(const cf.GetOptions(source: cf.Source.server))
            .timeout(const Duration(seconds: 8));
      }
      debugPrint('📋 [getUserProfile] READ for $uid → '
          'fromCache=${doc.metadata.isFromCache}, exists=${doc.exists}');
      if (doc.exists && doc.data() != null) {
        try {
          final data = doc.data()!;
          debugPrint('📋 [getUserProfile] FIRESTORE DATA for $uid → '
              'firstName="${data['firstName']}", lastName="${data['lastName']}", '
              'profilePhoto="${data['profilePhoto'] != null ? "SET" : "NULL"}", '
              'homeLocation="${data['homeLocation'] != null ? "SET" : "NULL"}", '
              'keys=${data.keys.length}');
          // Ensure UID is set in the model
          data['uid'] = uid;
          final profile = ProfileData.fromJson(data);
          debugPrint('📋 [getUserProfile] PARSED for $uid → '
              'firstName="${profile.firstName}", homeCity="${profile.homeLocation.city}"');
          // [PERF] Cache the result — but NOT bare/FCM-only docs (firstName empty).
          // These incomplete docs are created by PushNotificationService's
          // _saveTokenToFirestore() before profile setup completes. Caching them
          // causes the router to see an "incomplete" profile on every navigation
          // and wrongly redirect to /profile-setup. By not caching, the next
          // read will hit Firestore again and get the real profile.
          if (profile.firstName.isNotEmpty) {
            _profileCache[uid] = _CachedProfile(profile, DateTime.now());
          } else {
            debugPrint('📋 [getUserProfile] SKIPPING CACHE for bare/FCM-only doc (firstName empty)');
          }
          return profile;
        } catch (e, stackTrace) {
          debugPrint('╔═══════════════════════════════════════════════════════');
          debugPrint('║ ⚠ PROFILE PARSE ERROR for $uid');
          debugPrint('║ Error: $e');
          debugPrint('║ Fields present: ${doc.data()!.keys.toList()}');
          debugPrint('║ Stack: $stackTrace');
          debugPrint('╚═══════════════════════════════════════════════════════');
          return null;
        }
      }
      debugPrint('📋 [getUserProfile] DOC NOT FOUND for $uid');
      // Cache null result too (profile doesn't exist) to avoid repeated lookups
      _profileCache[uid] = _CachedProfile(null, DateTime.now());
      return null;
    } catch (e) {
      debugPrint('Error getting user profile: $e');
      // A profile refresh is not app-fatal. Returning null lets screens use
      // their cached/session-backed state while Firestore reconnects.
      final staleProfile = cached?.profile;
      if (staleProfile != null && staleProfile.firstName.isNotEmpty) {
        debugPrint('📋 [getUserProfile] USING STALE MEMORY CACHE for $uid');
        return staleProfile;
      }
      return null;
    }
  }

  Stream<ProfileData?> watchProfile(String uid) {
    return _firestore.collection('users').doc(uid).snapshots().map((doc) {
      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        data['uid'] = uid;
        return ProfileData.fromJson(data);
      }
      return null;
    });
  }

  Future<List<ProfileData>> searchUsers(
    String query, {
    String? communityId,
  }) async {
    if (query.isEmpty) return [];
    try {
      // Capitalize first letter for search (assuming stored names are capitalized)
      final searchKey = query.isNotEmpty
          ? query[0].toUpperCase() + query.substring(1)
          : query;

      final userQuery = await _firestore
          .collection('users')
          .where('firstName', isGreaterThanOrEqualTo: searchKey)
          .where('firstName', isLessThan: '$searchKey\uf8ff')
          .limit(20)
          .get();

      List<ProfileData> results = userQuery.docs
          .map((d) {
            try {
              final data = d.data();
              data['uid'] = d.id;
              return ProfileData.fromJson(data);
            } catch (e) {
              return null;
            }
          })
          .whereType<ProfileData>()
          .toList();

      // Optional client-side filtering for community
      if (communityId != null && communityId != 'global') {
        results = results
            .where(
              (u) => u.communityMemberships?.contains(communityId) ?? false,
            )
            .toList();
      }

      return results;
    } catch (e) {
      debugPrint('Error searching users: $e');
      return [];
    }
  }

  Future<List<ProfileData>> getProfiles(List<String> uids) async {
    if (uids.isEmpty) return [];
    try {
      final List<ProfileData> profiles = [];
      // Firestore 'whereIn' allows max 10 items
      for (var i = 0; i < uids.length; i += 10) {
        final end = (i + 10 < uids.length) ? i + 10 : uids.length;
        final chunk = uids.sublist(i, end);

        final query = await _firestore
            .collection('users')
            .where(cf.FieldPath.documentId, whereIn: chunk)
            .get();

        for (final doc in query.docs) {
          if (doc.exists) {
            final data = doc.data();
            data['uid'] = doc.id;
            profiles.add(ProfileData.fromJson(data));
          }
        }
      }
      return profiles;
    } catch (e) {
      debugPrint('Error getting profiles: $e');
      return [];
    }
  }

  Future<void> updateProfileData(String uid, Map<String, dynamic> data) async {
    data['updatedAt'] = cf.FieldValue.serverTimestamp();
    await _firestore.collection('users').doc(uid).update(data);
  }

  Future<void> saveUserProfile(String uid, ProfileData profile) async {
    final data = profile.toJson();
    data['updatedAt'] = cf.FieldValue.serverTimestamp();

    // [FIX] Check for 'createdAt' field, not just doc existence.
    // The doc might already exist from FCM token save (merge:true), but
    // createdAt should only be set on first real profile write.
    final docSnapshot = await _firestore.collection('users').doc(uid).get();
    if (!docSnapshot.exists || docSnapshot.data()?['createdAt'] == null) {
      data['createdAt'] = cf.FieldValue.serverTimestamp();
    }

    await _firestore
        .collection('users')
        .doc(uid)
        .set(data, cf.SetOptions(merge: true));
    // [FIX] Invalidate in-memory cache so next getUserProfile reads fresh data
    invalidateProfileCache(uid);
    // Cache UID locally for quick existence checks
    await _sessionService.setUserCached(uid);
  }

  Future<bool> profileExists(String uid) async {
    try {
      cf.DocumentSnapshot<Map<String, dynamic>> doc;
      try {
        // [FIX] Always try server first to avoid reading stale FCM-only docs
        // from Firestore's offline cache on fresh APK installs. The default
        // .get() can serve cached bare docs ({fcmToken, notificationsEnabled})
        // that were written by PushNotificationService before profile setup.
        doc = await _firestore
            .collection('users')
            .doc(uid)
            .get(const cf.GetOptions(source: cf.Source.server))
            .timeout(const Duration(seconds: 8));
      } catch (_) {
        // Server unavailable (offline) — fall back to local cache
        doc = await _firestore
            .collection('users')
            .doc(uid)
            .get(const cf.GetOptions(source: cf.Source.cache))
            .timeout(const Duration(seconds: 3));
      }
      debugPrint('📋 [profileExists] for $uid → fromCache=${doc.metadata.isFromCache}, exists=${doc.exists}');
      // [FIX] Don't just check doc.exists — the FCM token save creates a bare
      // user doc (with only fcmToken + notificationsEnabled) before profile
      // setup completes. Check for 'firstName' which is only written during
      // actual profile setup via saveUserProfile().
      if (!doc.exists) return false;
      final data = doc.data();
      if (data == null) return false;
      final hasFirstName = data.containsKey('firstName') && 
             (data['firstName'] as String?)?.isNotEmpty == true;
      debugPrint('📋 [profileExists] for $uid → hasFirstName=$hasFirstName, keys=${data.keys.length}');
      return hasFirstName;
    } catch (e) {
      debugPrint('Error checking profile existence: $e');
      rethrow; // [FIX] Rethrow to distinguish between "No Profile" and "Network Error"
    }
  }

  Future<String> submitBusinessRegistration({
    required String uid,
    required String businessName,
    required String description,
    required String phone,
    required String organizationType,
    required String website,
    String? logoUrl,
    String? locationAddress,
    double? locationLat,
    double? locationLng,
    String? locationCity,
    String? locationState,
    String? locationCountry,
    String? homeCountryCode, // Creator's home country code for filtering
    String? creatorTitle,
    Map<String, dynamic>? richData, // Rich data from Google Places
    String? communityId, // [NEW] Link to community
  }) async {
    // 1. Create the Organization Document in Firestore
    final orgRef = _firestore.collection('organizations').doc();
    final orgId = orgRef.id;
    final chatId = 'org_$orgId';
    final now = DateTime.now().millisecondsSinceEpoch;

    // 2. Initialize Chat in Firestore
    try {
      await _firestore.collection('chats').doc(chatId).set({
        'id': chatId,
        'type': 'organization',
        'name': businessName,
        'photoUrl': logoUrl,
        'participants': [uid],
        'admins': [uid],
        'createdAt': now,
        'updatedAt': now,
        'createdBy': uid,
        'lastMessage': {
          'content': 'Organization created',
          'timestamp': now,
          'type': 'system',
          'senderId': 'system',
          'senderName': 'System',
        },
      });

      await _firestore
          .collection('users')
          .doc(uid)
          .collection('userChats')
          .doc(chatId)
          .set({
            'chatId': chatId,
            'updatedAt': now,
            'lastMessage': {
              'content': 'Organization created',
              'timestamp': now,
              'type': 'system',
            },
          });
    } catch (e) {
      debugPrint('Error initializing Firestore chat: $e');
    }

    final orgData = {
      'id': orgId,
      'name':
          businessName, // Add 'name' field for consistency with browse screen
      'businessName': businessName,
      'description': description,
      'phone': phone,
      'type': organizationType,
      'website': website,
      'profileImage': logoUrl,
      'superAdminId': uid,
      'admins': [uid],
      'pendingAdmins': <String>[],
      'chatId': chatId,
      'createdAt': cf.FieldValue.serverTimestamp(),
      'status': 'active',
      // Location data
      'locationAddress': ?locationAddress,
      if (locationLat != null && locationLng != null)
        'location': {'lat': locationLat, 'lng': locationLng},
      'city': ?locationCity,
      'state': ?locationState,
      'country': ?locationCountry,
      'homeCountryCode':
          ?homeCountryCode, // For filtering by creator's home country
      if (creatorTitle != null) 'adminTitles': {uid: creatorTitle},
      // Save Rich Data if available
      'richData': ?richData,
      // [NEW] Link to community
      'communityId': ?communityId,
    };

    await orgRef.set(orgData);

    // 2. Cache org locally for immediate access (Deprecated: now handled by OrganizationRepository subscription)
    // await LocalCacheService.cacheOrganization(orgId, orgData);

    // 3. Add orgId to creator's organizationMemberships for denormalized lookup
    try {
      await _firestore.collection('users').doc(uid).update({
        'organizationMemberships': cf.FieldValue.arrayUnion([orgId]),
      });
    } catch (e) {
      debugPrint('Error updating user memberships: $e');
    }

    return orgId;
  }

  Future<void> updateHostLocation(
    String uid,
    UserLocation newLocation,
    String newCountry,
    String newCountryCode,
  ) async {
    final docRef = _firestore.collection('users').doc(uid);
    final doc = await docRef.get();

    if (!doc.exists) throw Exception('User not found');

    final currentData = ProfileData.fromJson(doc.data()!);
    final oldLocation = currentData.hostLocation;

    // Create past location entry
    final pastLocation = PastLocation(
      location: oldLocation,
      until: DateTime.now().toIso8601String(),
    );

    // Update Firestore
    await docRef.update({
      'hostLocation': newLocation.toJson(),
      'hostCountry': newCountry,
      'hostCountryCode': newCountryCode,
      'pastLocations': cf.FieldValue.arrayUnion([pastLocation.toJson()]),
      'updatedAt': cf.FieldValue.serverTimestamp(),
    });
  }

  Future<String> uploadProfileImage(String uid, XFile image) async {
    try {
      final storageRef = FirebaseStorage.instance.ref().child(
        'profile_photos/$uid/${DateTime.now().millisecondsSinceEpoch}.jpg',
      );

      final metadata = SettableMetadata(
        contentType: 'image/jpeg',
        cacheControl: 'public, max-age=31536000',
      );

      UploadTask uploadTask;
      if (kIsWeb) {
        final bytes = await image.readAsBytes();
        uploadTask = storageRef.putData(bytes, metadata);
      } else {
        // Use putFile on mobile for better performance/resumability
        uploadTask = storageRef.putFile(File(image.path), metadata);
      }

      final snapshot = await uploadTask;
      final downloadUrl = await snapshot.ref.getDownloadURL();
      return downloadUrl;
    } catch (e) {
      debugPrint('Error uploading profile image: $e');
      rethrow;
    }
  }
}

/// [PERF] Helper class for in-memory profile caching
class _CachedProfile {
  final ProfileData? profile;
  final DateTime fetchedAt;
  const _CachedProfile(this.profile, this.fetchedAt);
}
