import 'package:cloud_firestore/cloud_firestore.dart' as cf;
import 'package:cloud_functions/cloud_functions.dart';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:universal_io/io.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
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
  static const _privateFields = <String>{
    'phone',
    'dateOfBirth',
    'currentLocation',
    'geo',
    'workLocation',
    'pastLocations',
    'fcmToken',
    'fcmTokenUpdatedAt',
    'fcmTopics',
    'fcmTopicsUpdatedAt',
    'notificationsEnabled',
  };
  static const _serverFields = <String>{
    'isAdmin',
    'admin',
    'roles',
    'customClaims',
    'trustScore',
    'trustLevel',
    'isIdentityVerified',
    'blockedByCount',
    'vouchedByCount',
    'communityMemberships',
    'walletAddress',
    'smartWalletAddress',
    'welcomeBonusAwarded',
    'advertReportCount',
    'flaggedMessagesCount',
    'isBanned',
    'bannedAt',
    'bannedReason',
    'firstQrConnection',
    'blockedUsers',
  };

  cf.DocumentReference<Map<String, dynamic>> _privateRef(String uid) =>
      _firestore.collection('user_private').doc(uid);

  Map<String, dynamic>? _publicLocation(dynamic value) {
    if (value is! Map) return null;
    final map = Map<String, dynamic>.from(value);
    final city = map['city'] as String?;
    final state = map['state'] as String?;
    final country = map['country'] as String?;
    final summary = [
      city,
      state,
      country,
    ].whereType<String>().where((part) => part.trim().isNotEmpty).join(', ');
    return {
      'formatted_address': summary,
      'city': city,
      'state': state,
      'country': country,
      'country_code': map['country_code'] ?? map['countryCode'],
    };
  }

  ({Map<String, dynamic> publicData, Map<String, dynamic> privateData})
  _splitSensitiveData(Map<String, dynamic> source) {
    final publicData = Map<String, dynamic>.from(source);
    final privateData = <String, dynamic>{};
    for (final key in _privateFields) {
      if (publicData.containsKey(key)) {
        privateData[key] = publicData.remove(key);
      }
    }
    for (final key in _serverFields) {
      publicData.remove(key);
    }
    // Optional model fields serialize as null, but the rules expect an
    // omitted business profile and a boolean city visibility forfeiture flag.
    if (publicData['businessProfile'] == null) {
      publicData.remove('businessProfile');
    }
    if (publicData['cityVisibilityForfeited'] == null) {
      publicData.remove('cityVisibilityForfeited');
    }
    for (final key in const ['homeLocation', 'hostLocation']) {
      if (publicData.containsKey(key)) {
        privateData[key] = publicData[key];
        publicData[key] = _publicLocation(publicData[key]);
      }
    }
    final business = publicData['businessProfile'];
    if (business is Map && business.containsKey('taxId')) {
      privateData['businessProfile'] = Map<String, dynamic>.from(business);
      publicData['businessProfile'] = Map<String, dynamic>.from(business)
        ..remove('taxId');
    }
    final currentSummary = _publicLocation(privateData['currentLocation']);
    if (currentSummary != null &&
        publicData['showCurrentLocationName'] == true) {
      publicData['currentCity'] = currentSummary['city'];
      publicData['currentState'] = currentSummary['state'];
      publicData['currentCountryCode'] = currentSummary['country_code'];
    } else if (publicData['showCurrentLocationName'] == false) {
      publicData['currentCity'] = cf.FieldValue.delete();
      publicData['currentState'] = cf.FieldValue.delete();
      publicData['currentCountryCode'] = cf.FieldValue.delete();
    }
    return (publicData: publicData, privateData: privateData);
  }

  /// Cleans legacy keys on an existing public user document so merged/partial
  /// writes do not retain rule-rejected fields (`place_id`, `geometry`,
  /// `currentLocation`, or explicit-null `businessProfile` /
  /// `cityVisibilityForfeited`).
  void _cleanLegacyPublicFields(
    Map<String, dynamic> publicData,
    Map<String, dynamic>? existingPublicDoc,
  ) {
    if (existingPublicDoc == null) return;
    if (existingPublicDoc.containsKey('businessProfile') &&
        existingPublicDoc['businessProfile'] == null &&
        !publicData.containsKey('businessProfile')) {
      publicData['businessProfile'] = cf.FieldValue.delete();
    }
    if (existingPublicDoc.containsKey('cityVisibilityForfeited') &&
        existingPublicDoc['cityVisibilityForfeited'] == null &&
        !publicData.containsKey('cityVisibilityForfeited')) {
      publicData['cityVisibilityForfeited'] = cf.FieldValue.delete();
    }
    if (existingPublicDoc.containsKey('currentLocation')) {
      publicData['currentLocation'] = cf.FieldValue.delete();
    }
    for (final key in const ['homeLocation', 'hostLocation']) {
      final summary = publicData[key];
      final existingLoc = existingPublicDoc[key];
      if (summary is Map<String, dynamic> && existingLoc is Map) {
        if (existingLoc.containsKey('place_id')) {
          summary['place_id'] = cf.FieldValue.delete();
        }
        if (existingLoc.containsKey('geometry')) {
          summary['geometry'] = cf.FieldValue.delete();
        }
      }
    }
  }

  Future<Map<String, dynamic>> _mergeOwnPrivateData(
    String uid,
    Map<String, dynamic> publicData,
  ) async {
    try {
      String? currentUid;
      try {
        currentUid = FirebaseAuth.instance.currentUser?.uid;
      } catch (_) {
        // In unit tests without Firebase.initializeApp(), allow merging own private doc.
        currentUid = uid;
      }
      if (currentUid != uid) return publicData;
      final privateDoc = await _privateRef(uid).get();
      if (privateDoc.exists) return {...publicData, ...?privateDoc.data()};
    } catch (_) {
      // A cached public profile remains useful while private data reconnects.
    }
    return publicData;
  }

  /// Clear cache for a specific user (call after profile update)
  void invalidateProfileCache(String uid) => _profileCache.remove(uid);

  /// Clear entire cache (call on logout)
  void clearProfileCache() => _profileCache.clear();

  Future<ProfileData?> getUserProfile(String uid) async {
    // [PERF] Check in-memory cache first
    final cached = _profileCache[uid];
    if (cached != null &&
        DateTime.now().difference(cached.fetchedAt) < _cacheTtl) {
      final p = cached.profile;
      // [FIX] Don't serve bare/FCM-only docs from cache — they have empty
      // firstName and should be re-fetched from Firestore to get real data.
      if (p != null && p.firstName.isEmpty) {
        debugPrint(
          '📋 [getUserProfile] CACHE SKIP for bare/FCM-only doc (firstName empty) → re-fetching',
        );
        _profileCache.remove(uid);
      } else {
        debugPrint(
          '📋 [getUserProfile] CACHE HIT for $uid → '
          'firstName="${p?.firstName}", lastName="${p?.lastName}", '
          'profileImage="${p?.profileImage.isNotEmpty == true ? "SET" : "EMPTY"}", '
          'homeCity="${p?.homeLocation.city}"',
        );
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
      debugPrint(
        '📋 [getUserProfile] READ for $uid → '
        'fromCache=${doc.metadata.isFromCache}, exists=${doc.exists}',
      );
      if (doc.exists && doc.data() != null) {
        try {
          final data = await _mergeOwnPrivateData(uid, doc.data()!);
          debugPrint(
            '📋 [getUserProfile] FIRESTORE DATA for $uid → '
            'firstName="${data['firstName']}", lastName="${data['lastName']}", '
            'profilePhoto="${data['profilePhoto'] != null ? "SET" : "NULL"}", '
            'homeLocation="${data['homeLocation'] != null ? "SET" : "NULL"}", '
            'keys=${data.keys.length}',
          );
          // Ensure UID is set in the model
          data['uid'] = uid;
          final profile = ProfileData.fromJson(data);
          debugPrint(
            '📋 [getUserProfile] PARSED for $uid → '
            'firstName="${profile.firstName}", homeCity="${profile.homeLocation.city}"',
          );
          // [PERF] Cache the result — but NOT bare/FCM-only docs (firstName empty).
          // These incomplete docs are created by PushNotificationService's
          // _saveTokenToFirestore() before profile setup completes. Caching them
          // causes the router to see an "incomplete" profile on every navigation
          // and wrongly redirect to /profile-setup. By not caching, the next
          // read will hit Firestore again and get the real profile.
          if (profile.firstName.isNotEmpty) {
            _profileCache[uid] = _CachedProfile(profile, DateTime.now());
          } else {
            debugPrint(
              '📋 [getUserProfile] SKIPPING CACHE for bare/FCM-only doc (firstName empty)',
            );
          }
          return profile;
        } catch (e, stackTrace) {
          debugPrint(
            '╔═══════════════════════════════════════════════════════',
          );
          debugPrint('║ ⚠ PROFILE PARSE ERROR for $uid');
          debugPrint('║ Error: $e');
          debugPrint('║ Fields present: ${doc.data()!.keys.toList()}');
          debugPrint('║ Stack: $stackTrace');
          debugPrint(
            '╚═══════════════════════════════════════════════════════',
          );
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
    return _firestore.collection('users').doc(uid).snapshots().asyncMap((
      doc,
    ) async {
      if (doc.exists && doc.data() != null) {
        final data = await _mergeOwnPrivateData(uid, doc.data()!);
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
    final split = _splitSensitiveData(data);
    final docSnapshot = await _firestore.collection('users').doc(uid).get();
    _cleanLegacyPublicFields(split.publicData, docSnapshot.data());
    final batch = _firestore.batch();
    if (split.publicData.isNotEmpty) {
      batch.update(_firestore.collection('users').doc(uid), split.publicData);
    }
    if (split.privateData.isNotEmpty) {
      batch.set(
        _privateRef(uid),
        split.privateData,
        cf.SetOptions(merge: true),
      );
    }
    await batch.commit();
  }

  Future<void> saveUserProfile(String uid, ProfileData profile) async {
    final data = profile.toJson();
    data['updatedAt'] = cf.FieldValue.serverTimestamp();
    final split = _splitSensitiveData(data);

    // [FIX] Check for 'createdAt' field, not just doc existence.
    // The doc might already exist from FCM token save (merge:true), but
    // createdAt should only be set on first real profile write.
    final docSnapshot = await _firestore.collection('users').doc(uid).get();
    if (!docSnapshot.exists || docSnapshot.data()?['createdAt'] == null) {
      split.publicData['createdAt'] = cf.FieldValue.serverTimestamp();
    }
    _cleanLegacyPublicFields(split.publicData, docSnapshot.data());
    final batch = _firestore.batch();
    batch.set(
      _firestore.collection('users').doc(uid),
      split.publicData,
      cf.SetOptions(merge: true),
    );
    batch.set(_privateRef(uid), split.privateData, cf.SetOptions(merge: true));
    await batch.commit();
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
      debugPrint(
        '📋 [profileExists] for $uid → fromCache=${doc.metadata.isFromCache}, exists=${doc.exists}',
      );
      // [FIX] Don't just check doc.exists — the FCM token save creates a bare
      // user doc (with only fcmToken + notificationsEnabled) before profile
      // setup completes. Check for 'firstName' which is only written during
      // actual profile setup via saveUserProfile().
      if (!doc.exists) return false;
      final data = doc.data();
      if (data == null) return false;
      final hasFirstName =
          data.containsKey('firstName') &&
          (data['firstName'] as String?)?.isNotEmpty == true;
      debugPrint(
        '📋 [profileExists] for $uid → hasFirstName=$hasFirstName, keys=${data.keys.length}',
      );
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
    await FirebaseFunctions.instance
        .httpsCallable('createChat')
        .call<Map<String, dynamic>>({
          'mode': 'organization',
          'organizationId': orgId,
        });

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

    final mergedData = await _mergeOwnPrivateData(uid, doc.data()!);
    final currentData = ProfileData.fromJson(mergedData);
    final oldLocation = currentData.hostLocation;

    // Create past location entry
    final pastLocation = PastLocation(
      location: oldLocation,
      until: DateTime.now().toIso8601String(),
    );

    final publicUpdates = <String, dynamic>{
      'hostLocation': _publicLocation(newLocation.toJson()),
      'hostCountry': newCountry,
      'hostCountryCode': newCountryCode,
      'updatedAt': cf.FieldValue.serverTimestamp(),
    };
    _cleanLegacyPublicFields(publicUpdates, doc.data());

    final batch = _firestore.batch();
    batch.update(docRef, publicUpdates);
    batch.set(_privateRef(uid), {
      'hostLocation': newLocation.toJson(),
      'pastLocations': cf.FieldValue.arrayUnion([pastLocation.toJson()]),
    }, cf.SetOptions(merge: true));
    await batch.commit();
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
