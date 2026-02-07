import 'package:cloud_firestore/cloud_firestore.dart' as cf;
import 'package:firebase_database/firebase_database.dart';
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

  Future<ProfileData?> getUserProfile(String uid) async {
    try {
      final doc = await _firestore
          .collection('users')
          .doc(uid)
          .get()
          .timeout(const Duration(seconds: 10));
      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        // Ensure UID is set in the model
        data['uid'] = uid;
        return ProfileData.fromJson(data);
      }
      return null;
    } catch (e) {
      debugPrint('Error getting user profile: $e');
      rethrow; // [FIX] Rethrow to distinguish between "No Profile" and "Network Error"
    }
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
    // Generate timestamps
    final now = DateTime.now().millisecondsSinceEpoch;

    // We need to convert to JSON and add server timestamps manually if we want FieldValue.serverTimestamp()
    // But for simplicity/typing, we'll use local time or handle it in specific update methods.
    // The exact TS equivalent uses `serverTimestamp()`.

    final data = profile.toJson();
    data['updatedAt'] = cf.FieldValue.serverTimestamp();

    // If new
    final docSnapshot = await _firestore.collection('users').doc(uid).get();
    if (!docSnapshot.exists) {
      data['createdAt'] = cf.FieldValue.serverTimestamp();
    }

    await _firestore
        .collection('users')
        .doc(uid)
        .set(data, cf.SetOptions(merge: true));
    // Cache UID locally for quick existence checks
    await _sessionService.setUserCached(uid);
  }

  Future<bool> profileExists(String uid) async {
    try {
      final doc = await _firestore
          .collection('users')
          .doc(uid)
          .get()
          .timeout(const Duration(seconds: 5));
      return doc.exists;
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

    // 2. Initialize Chat in RTDB
    try {
      final rtdb = FirebaseDatabase.instance.ref();
      await rtdb.child('chats/$chatId').set({
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
          'content': 'â­ Organization created',
          'timestamp': now,
          'type': 'system',
          'senderId': 'system',
          'senderName': 'System',
        },
      });

      await rtdb.child('userChats/$uid/$chatId').set({
        'chatId': chatId,
        'updatedAt': now,
        'lastMessage': {
          'content': 'â­ Organization created',
          'timestamp': now,
          'type': 'system',
        },
      });
    } catch (e) {
      debugPrint('Error initializing RTDB chat: $e');
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
      if (locationAddress != null) 'locationAddress': locationAddress,
      if (locationLat != null && locationLng != null)
        'location': {'lat': locationLat, 'lng': locationLng},
      if (locationCity != null) 'city': locationCity,
      if (locationState != null) 'state': locationState,
      if (locationCountry != null) 'country': locationCountry,
      if (homeCountryCode != null)
        'homeCountryCode':
            homeCountryCode, // For filtering by creator's home country
      if (creatorTitle != null) 'adminTitles': {uid: creatorTitle},
      // Save Rich Data if available
      if (richData != null) 'richData': richData,
      // [NEW] Link to community
      if (communityId != null) 'communityId': communityId,
    };

    await orgRef.set(orgData);

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
