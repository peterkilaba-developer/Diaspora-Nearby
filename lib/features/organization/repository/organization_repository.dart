import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart' hide Query;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:diaspora_nearby/services/local_cache_service.dart';
import 'package:diaspora_nearby/features/auth/repository/auth_repository.dart';

final organizationRepositoryProvider = Provider((ref) => OrganizationRepository());

/// Provider that streams organizations where the user has some admin role
final userOrganizationsProvider = StreamProvider<List<Map<String, dynamic>>>((ref) {
  final user = ref.watch(authStateProvider).value;
  if (user == null) return Stream.value([]);
  
  final repo = ref.watch(organizationRepositoryProvider);
  return repo.watchUserOrganizations(user.uid);
});

class OrganizationRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final DatabaseReference _rtdb = FirebaseDatabase.instance.ref();

  /// Watch organizations where the user is an admin, superAdmin, or pendingAdmin
  Stream<List<Map<String, dynamic>>> watchUserOrganizations(String userId) {
    // We combine multiple queries client-side because Firestore doesn't support OR across different fields well for arrayContains
    // For MVP, we watch superAdminId and then fetch others or use a combined collection if we had one.
    // Better: watch the whole collection where status involves the user.
    
    return _firestore
        .collection('organizations')
        .snapshots()
        .map((snapshot) {
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
                return isSuper || admins.contains(userId) || pending.contains(userId);
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
      final cachedOrgs = LocalCacheService.getMyCachedOrganizations();
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
      if (query.isEmpty) return [];
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
            final name = (org['businessName'] as String?)?.toLowerCase() ?? 
                         (org['name'] as String?)?.toLowerCase() ?? '';
            return name.contains(queryLower);
          })
          .toList();
    } catch (e) {
      return [];
    }
  }

  /// Get organization details by ID
  Future<Map<String, dynamic>?> getOrganization(String orgId) async {
    final cached = LocalCacheService.getCachedOrganization(orgId);
    if (cached != null) return cached;

    try {
      final doc = await _firestore.collection('organizations').doc(orgId).get();
      if (doc.exists) {
        final data = doc.data()!;
        data['id'] = doc.id;
        await LocalCacheService.cacheOrganization(orgId, data);
        return data;
      }
      return null;
    } catch (e) {
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

        String status = data['status'] ?? 'pending';
        if (admins.length >= 2) status = 'active';

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
    
    await LocalCacheService.cacheOrganization(orgId, cachedData);
    await LocalCacheService.addToMyOrgsList(orgId);

    // 2. Save to Firestore
    await docRef.set(orgData);
    
    return orgId;
  }
}
