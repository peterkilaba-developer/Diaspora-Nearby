import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart' hide Query;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// import 'package:diaspora_nearby/core/services/local_cache_service.dart'; // Deprecated
import 'package:diaspora_nearby/features/auth/repository/auth_repository.dart';
import 'package:diaspora_nearby/features/organization/repository/organization_local_service.dart';

final organizationRepositoryProvider = Provider(
  (ref) => OrganizationRepository(),
);

/// Provider that streams organizations where the user has some admin role
final userOrganizationsProvider = StreamProvider<List<Map<String, dynamic>>>((
  ref,
) {
  final user = ref.watch(authStateProvider).value;
  if (user == null) return Stream.value([]);

  final repo = ref.watch(organizationRepositoryProvider);
  return repo.watchUserOrganizations(user.uid);
});

final organizationByIdProvider =
    FutureProvider.family<Map<String, dynamic>?, String>((ref, id) {
      return ref.watch(organizationRepositoryProvider).getOrganization(id);
    });

class OrganizationRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final DatabaseReference _rtdb = FirebaseDatabase.instance.ref();

  final OrganizationLocalService _localService;
  
  OrganizationRepository() : _localService = OrganizationLocalService();


  /// Watch organizations where the user is an admin, superAdmin, or pendingAdmin
  Stream<List<Map<String, dynamic>>> watchUserOrganizations(String userId) {
    // We combine multiple queries client-side because Firestore doesn't support OR across different fields well for arrayContains
    // For MVP, we watch superAdminId and then fetch others or use a combined collection if we had one.
    // Better: watch the whole collection where status involves the user.

    return _firestore.collection('organizations').snapshots().map((snapshot) {
      return snapshot.docs
          .map((doc) {
            final data = doc.data();
            data['id'] = doc.id;
            return data;
          })
          .where((org) {
            final admins = List<String>.from(org['admins'] ?? []);
            final pending = List<String>.from(org['pendingAdmins'] ?? []);
            final isSuper = org['superAdminId'] == userId;
            return isSuper ||
                admins.contains(userId) ||
                pending.contains(userId);
          })
          .toList();
    });
  }

  /// Fetch organizations where the user is an admin or superAdmin
  Future<List<Map<String, dynamic>>> getUserOrganizations(String userId) async {
    try {
      final orgs = <String, Map<String, dynamic>>{};

      final adminsQuery = await _firestore
          .collection('organizations')
          .where('admins', arrayContains: userId)
          .get();
      for (var doc in adminsQuery.docs) {
        final data = doc.data();
        data['id'] = doc.id;
        orgs[doc.id] = data;
      }

      final superAdminsQuery = await _firestore
          .collection('organizations')
          .where('superAdminId', isEqualTo: userId)
          .get();
      for (var doc in superAdminsQuery.docs) {
        final data = doc.data();
        data['id'] = doc.id;
        orgs[doc.id] = data;
      }

      final pendingAdminsQuery = await _firestore
          .collection('organizations')
          .where('pendingAdmins', arrayContains: userId)
          .get();
      for (var doc in pendingAdminsQuery.docs) {
        final data = doc.data();
        data['id'] = doc.id;
        orgs[doc.id] = data;
      }

      // Merge with local cache
      final cachedOrgs = await _localService.getUserOrganizations(userId);
      for (final org in cachedOrgs) {
        final id = org['id'];
        if (id != null && !orgs.containsKey(id)) {
          orgs[id] = org;
        }
      }

      return orgs.values.toList();
    } catch (e) {
      debugPrint('Error in getUserOrganizations: $e');
      return [];
    }
  }

  /// Get all active organizations
  Future<List<Map<String, dynamic>>> getAllOrganizations() async {
    try {
      final snapshot = await _firestore
          .collection('organizations')
          .where('status', isEqualTo: 'active')
          .get();

      return snapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return data;
      }).toList();
    } catch (e) {
      debugPrint('Error fetching organizations: $e');
      return [];
    }
  }

  /// Search organizations by name
  Future<List<Map<String, dynamic>>> searchOrganizations(String query) async {
    try {
      final queryLower = query.toLowerCase();

      final snapshot = await _firestore
          .collection('organizations')
          .where('status', isEqualTo: 'active')
          .get();

      return snapshot.docs
          .map((doc) {
            final data = doc.data();
            data['id'] = doc.id;
            return data;
          })
          .where((org) {
            if (query.isEmpty) return true;
            final name =
                (org['businessName'] as String?)?.toLowerCase() ??
                (org['name'] as String?)?.toLowerCase() ??
                '';
            return name.contains(queryLower);
          })
          .toList();
    } catch (e) {
      return [];
    }
  }

  /// Get organization details by ID
  Future<Map<String, dynamic>?> getOrganization(String orgId, {bool force = false}) async {
    // 1. Check Local Cache
    if (!force) {
      final localOrg = await _localService.getOrganization(orgId);
      if (localOrg != null) {
        // Background refresh
        _fetchAndSaveOrg(orgId);
        return localOrg;
      }
    }

    return await _fetchAndSaveOrg(orgId);
  }

  Future<Map<String, dynamic>?> _fetchAndSaveOrg(String orgId) async {
    try {
      final doc = await _firestore.collection('organizations').doc(orgId).get();
      if (doc.exists) {
        final data = doc.data()!;
        data['id'] = doc.id;
        
        // Cache to Isar
        await _localService.saveOrganization(data);
        
        return data;
      }
      return null;
    } catch (e) {
      debugPrint('Error fetching/saving org: $e');
      return null;
    }
  }

  /// Invite an admin
  Future<void> inviteAdmin(String orgId, String userId) async {
    final orgRef = _firestore.collection('organizations').doc(orgId);

    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(orgRef);
      if (!snapshot.exists) return;

      final data = snapshot.data() as Map<String, dynamic>;
      final admins = List<String>.from(data['admins'] ?? []);
      final pendingAdmins = List<String>.from(data['pendingAdmins'] ?? []);

      if (!admins.contains(userId) && !pendingAdmins.contains(userId)) {
        pendingAdmins.add(userId);
        transaction.update(orgRef, {'pendingAdmins': pendingAdmins});
      }
    });
  }

  /// Accept an admin invite
  Future<void> acceptInvite(String orgId, String userId) async {
    final orgRef = _firestore.collection('organizations').doc(orgId);

    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(orgRef);
      if (!snapshot.exists) return;

      final data = snapshot.data() as Map<String, dynamic>;
      final admins = List<String>.from(data['admins'] ?? []);
      final pendingAdmins = List<String>.from(data['pendingAdmins'] ?? []);
      final chatId = data['chatId'] as String?;

      if (pendingAdmins.contains(userId)) {
        pendingAdmins.remove(userId);
        if (!admins.contains(userId)) admins.add(userId);

        // String status = data['status'] ?? 'pending';
        // if (admins.length >= 2) status = 'active';

        // MVP Change: Org is active immediately upon creation/acceptance
        String status = 'active';

        transaction.update(orgRef, {
          'admins': admins,
          'pendingAdmins': pendingAdmins,
          'status': status,
        });

        // Add to RTDB for chat permissions
        if (chatId != null) {
          await _rtdb.child('userChats/$userId/$chatId').set(true);
          await _rtdb.child('chats/$chatId/adminIds').set(admins);
        }
      }
    });
  }

  /// Decline or remove pending invite
  Future<void> declineInvite(String orgId, String userId) async {
    final orgRef = _firestore.collection('organizations').doc(orgId);
    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(orgRef);
      if (!snapshot.exists) return;
      final data = snapshot.data() as Map<String, dynamic>;
      final pendingAdmins = List<String>.from(data['pendingAdmins'] ?? []);
      if (pendingAdmins.contains(userId)) {
        pendingAdmins.remove(userId);
        transaction.update(orgRef, {'pendingAdmins': pendingAdmins});
      }
    });
  }

  /// Remove an existing admin
  Future<void> removeAdmin(String orgId, String adminId) async {
    final orgRef = _firestore.collection('organizations').doc(orgId);
    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(orgRef);
      if (!snapshot.exists) return;
      final data = snapshot.data() as Map<String, dynamic>;
      final admins = List<String>.from(data['admins'] ?? []);
      final chatId = data['chatId'] as String?;

      if (admins.contains(adminId) && data['superAdminId'] != adminId) {
        admins.remove(adminId);
        transaction.update(orgRef, {'admins': admins});

        if (chatId != null) {
          await _rtdb.child('userChats/$adminId/$chatId').remove();
          await _rtdb.child('chats/$chatId/adminIds').set(admins);
        }
      }
    });
  }

  /// Register a new organization
  Future<String> registerOrganization(Map<String, dynamic> data) async {
    final docRef = _firestore.collection('organizations').doc();
    final orgId = docRef.id;

    final orgData = {
      ...data,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'status': 'active', // Default to active for MVP
      'admins': [data['superAdminId']],
      'pendingAdmins': [],
    };

    // 1. Immediately Cache
    final cachedData = Map<String, dynamic>.from(orgData);
    cachedData['id'] = orgId;
    // Replace serverTimestamp with local time for cache
    cachedData['createdAt'] = DateTime.now().millisecondsSinceEpoch;
    cachedData['updatedAt'] = DateTime.now().millisecondsSinceEpoch;

    cachedData['createdAt'] = DateTime.now().millisecondsSinceEpoch;
    cachedData['updatedAt'] = DateTime.now().millisecondsSinceEpoch;

    // Cache to Isar
    _localService.saveOrganization(cachedData);
    // await LocalCacheService.addToMyOrgsList(orgId); // Isar query handles this automatically implicitly by admin check

    // 2. Initialize Chat in RTDB
    final chatId = 'org_$orgId';
    final rtdbNow = DateTime.now().millisecondsSinceEpoch;
    await _rtdb.child('chats/$chatId').set({
      'id': chatId,
      'type': 'organization',
      'name': data['businessName'] ?? data['name'] ?? 'Organization',
      'photoUrl': data['profileImage'] ?? data['logoUrl'],
      'participants': [data['superAdminId']],
      'admins': [data['superAdminId']],
      'createdAt': rtdbNow,
      'updatedAt': rtdbNow,
      'createdBy': data['superAdminId'],
      'lastMessage': {
        'content': 'â­ Organization created',
        'timestamp': rtdbNow,
        'type': 'system',
        'senderId': 'system',
        'senderName': 'System',
      },
    });

    await _rtdb.child('userChats/${data['superAdminId']}/$chatId').set({
      'chatId': chatId,
      'updatedAt': rtdbNow,
      'lastMessage': {
        'content': 'â­ Organization created',
        'timestamp': rtdbNow,
        'type': 'system',
      },
    });

    // 3. Save to Firestore
    await docRef.set({...orgData, 'chatId': chatId});

    return orgId;
  }

  /// Follow an organization
  Future<void> followOrganization(String orgId, String userId) async {
    // 1. Get Org Data to find chatId
    final docRef = _firestore.collection('organizations').doc(orgId);
    final docSnapshot = await docRef.get();

    if (!docSnapshot.exists) throw Exception("Organization not found");
    final data = docSnapshot.data()!;
    final chatId = data['chatId'] as String?;

    // 2. Add to followers in Firestore
    await docRef.update({
      'followers': FieldValue.arrayUnion([userId]),
    });

    // 3. Add to userChats in RTDB if chatId exists
    if (chatId != null) {
      final now = DateTime.now().millisecondsSinceEpoch;
      await _rtdb.child('userChats/$userId/$chatId').update({
        'chatId': chatId,
        'updatedAt': now,
        'following': true,
      });

      // [NEW] Also add to participants in RTDB so they can post to the board
      final participantsRef = _rtdb.child('chats/$chatId/participants');
      final pSnapshot = await participantsRef.get();
      List<String> participants = [];
      if (pSnapshot.exists) {
        if (pSnapshot.value is List) {
          participants = List<String>.from(pSnapshot.value as List);
        } else if (pSnapshot.value is Map) {
          participants = (pSnapshot.value as Map).values.map((e) => e.toString()).toList();
        }
      }
      if (!participants.contains(userId)) {
        participants.add(userId);
        await participantsRef.set(participants);
      }
    }
    
    // 4. Force refresh local cache
    await getOrganization(orgId, force: true);
  }

  /// Add a user to organization chat participants (Admin only)
  Future<void> addChatMember(String orgId, String userId) async {
    final doc = await _firestore.collection('organizations').doc(orgId).get();
    if (!doc.exists) return;

    final chatId = doc.data()?['chatId'] as String?;
    if (chatId == null) return;

    final now = DateTime.now().millisecondsSinceEpoch;

    // 1. Ensure userChats entry exists
    await _rtdb.child('userChats/$userId/$chatId').update({
      'chatId': chatId,
      'updatedAt': now,
      // We don't force 'following' here, but user should probably follow to see it.
    });

    // 2. Add to participants in RTDB
    final participantsRef = _rtdb.child('chats/$chatId/participants');
    final snapshot = await participantsRef.get();
    List<String> participants = [];
    if (snapshot.exists) {
      participants = List<String>.from(snapshot.value as List);
    }
    if (!participants.contains(userId)) {
      participants.add(userId);
      await participantsRef.set(participants);
    }
  }

  /// Remove a user from organization chat participants (Admin only)
  Future<void> removeChatMember(String orgId, String userId) async {
    final doc = await _firestore.collection('organizations').doc(orgId).get();
    if (!doc.exists) return;

    final chatId = doc.data()?['chatId'] as String?;
    if (chatId == null) return;

    // Remove from participants in RTDB
    final participantsRef = _rtdb.child('chats/$chatId/participants');
    final snapshot = await participantsRef.get();
    if (snapshot.exists) {
      final participants = List<String>.from(snapshot.value as List);
      if (participants.contains(userId)) {
        participants.remove(userId);
        await participantsRef.set(participants);
      }
    }

    // We don't necessarily remove from userChats if they are still 'following'
    // but without participant status they might not see it or can't post.
    // Actually, if they are not participants, the filter in ChatRepository might hide it?
    // Let's check ChatRepository's list fetching.
  }

  /// Unfollow an organization
  Future<void> unfollowOrganization(String orgId, String userId) async {
    final docRef = _firestore.collection('organizations').doc(orgId);
    final docSnapshot = await docRef.get();

    if (!docSnapshot.exists) return; // Silent fail
    final data = docSnapshot.data()!;
    final chatId = data['chatId'] as String?;

    // 1. Remove from followers
    await docRef.update({
      'followers': FieldValue.arrayRemove([userId]),
    });

    // 2. Remove from userChats and participants
    if (chatId != null) {
      await _rtdb.child('userChats/$userId/$chatId').remove();

      final participantsRef = _rtdb.child('chats/$chatId/participants');
      final snapshot = await participantsRef.get();
      if (snapshot.exists) {
        List<String> participants = [];
        if (snapshot.value is List) {
          participants = List<String>.from(snapshot.value as List);
        } else if (snapshot.value is Map) {
          participants = (snapshot.value as Map).values.map((e) => e.toString()).toList();
        }
        
        if (participants.contains(userId)) {
          participants.remove(userId);
          await participantsRef.set(participants);
        }
      }
    }

    // 3. Force refresh local cache
    await getOrganization(orgId, force: true);
  }
}
