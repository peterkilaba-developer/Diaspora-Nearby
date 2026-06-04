import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// import 'package:diaspora_nearby/core/services/local_cache_service.dart'; // Deprecated
import 'package:diaspora_nearby/features/auth/repository/auth_repository.dart';
import 'package:diaspora_nearby/features/organization/models/chamber_leadership_request.dart';
import 'package:diaspora_nearby/features/organization/models/chamber_roles.dart';
import 'package:diaspora_nearby/features/organization/repository/organization_local_service.dart';

final organizationRepositoryProvider = Provider(
  (ref) => OrganizationRepository(ref),
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

  final OrganizationLocalService _localService;

  OrganizationRepository(Ref ref) : _localService = OrganizationLocalService();

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
  Future<Map<String, dynamic>?> getOrganization(
    String orgId, {
    bool force = false,
  }) async {
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

        // Add to Firestore for chat permissions
        if (chatId != null) {
          await _firestore
              .collection('users')
              .doc(userId)
              .collection('userChats')
              .doc(chatId)
              .set({
                'chatId': chatId,
                'updatedAt': DateTime.now().millisecondsSinceEpoch,
              }, SetOptions(merge: true));
          await _firestore.collection('chats').doc(chatId).update({
            'adminIds': admins,
          });
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
          await _firestore
              .collection('users')
              .doc(adminId)
              .collection('userChats')
              .doc(chatId)
              .delete();
          await _firestore.collection('chats').doc(chatId).update({
            'adminIds': admins,
          });
        }
      }
    });
  }

  /// Register a new organization
  Future<String> registerOrganization(Map<String, dynamic> data) async {
    final orgId = const Uuid().v4();
    final docRef = _firestore.collection('organizations').doc(orgId);

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

    // 2. Initialize Chat in Firestore
    final chatId = 'org_$orgId';
    final fsNow = DateTime.now().millisecondsSinceEpoch;
    await _firestore.collection('chats').doc(chatId).set({
      'id': chatId,
      'type': 'organization',
      'name': data['businessName'] ?? data['name'] ?? 'Organization',
      'photoUrl': data['profileImage'] ?? data['logoUrl'],
      'participants': [data['superAdminId']],
      'admins': [data['superAdminId']],
      'createdAt': fsNow,
      'updatedAt': fsNow,
      'createdBy': data['superAdminId'],
      'lastMessage': {
        'content': 'Organization created',
        'timestamp': fsNow,
        'type': 'system',
        'senderId': 'system',
        'senderName': 'System',
      },
    });

    await _firestore
        .collection('users')
        .doc(data['superAdminId'])
        .collection('userChats')
        .doc(chatId)
        .set({
          'chatId': chatId,
          'updatedAt': fsNow,
          'lastMessage': {
            'content': 'Organization created',
            'timestamp': fsNow,
            'type': 'system',
          },
        });

    // 3. Save to Firestore
    await docRef.set({...orgData, 'chatId': chatId});

    return orgId;
  }

  /// Ensure the bilateral "Chamber of Commerce" organization exists for a
  /// (home, host) country pairing and join the user to it.
  ///
  /// Idempotent: same (homeCC, hostCC) always maps to the same org id, so
  /// repeated calls at signup are safe. First caller creates the org + chat;
  /// subsequent callers are added as members/participants only.
  ///
  /// Returns the chamber organization id (e.g. `chamber_tz_us`), or null
  /// when no chamber is applicable (missing codes or home == host).
  ///
  /// **Opt-in model:** this method only *ensures the chamber doc exists*
  /// for the (home, host) corridor. It does NOT join the user. Joining and
  /// following are explicit user actions handled by [joinChamber] and
  /// [followChamber] respectively — matching how real chambers of commerce
  /// operate (you walk in and sign up, not citizenship-by-default).
  Future<String?> ensureCorridorChamber({
    required String userId,
    required String homeCountryCode,
    required String hostCountryCode,
    String? userName,
  }) async {
    if (homeCountryCode.isEmpty || hostCountryCode.isEmpty) return null;
    final home = homeCountryCode.toUpperCase();
    final host = hostCountryCode.toUpperCase();
    if (home == host) return null; // No corridor if home == host

    // ID & name follow host-first / home-second ordering as defined on the
    // landing page (the host country leads because the chamber operates IN
    // the host country, representing the home-country diaspora).
    final orgId = 'chamber_${host.toLowerCase()}_${home.toLowerCase()}';
    final chatId = 'org_$orgId';
    final docRef = _firestore.collection('organizations').doc(orgId);
    final chatRef = _firestore.collection('chats').doc(chatId);
    final now = DateTime.now().millisecondsSinceEpoch;
    // Bilateral arrow (⇄) between host and home denotes the corridor link,
    // matching the landing-page convention.
    final name = '$host ⇄ $home Chamber of Commerce';

    final wasCreated = await _firestore.runTransaction<bool>((tx) async {
      final snapshot = await tx.get(docRef);
      if (snapshot.exists) return false;

      // First time this corridor's chamber is referenced — create it as a
      // public, empty body. No auto-join: members/followers start empty.
      final orgData = {
        'id': orgId,
        'kind': 'corridor_chamber',
        'name': name,
        'businessName': name,
        'description': 'Official public corridor chamber — $host (host) ↔ $home (home) diaspora.',
        'type': 'Chamber of Commerce',
        'phone': '',
        'website': '',
        'profileImage': null,
        'superAdminId': null,
        'admins': <String>[],
        'pendingAdmins': <String>[],
        'adminTitles': <String, String>{},
        // Opt-in: chambers start empty. Users must explicitly Join or Follow.
        'members': <String>[],
        'followers': <String>[],
        'memberCount': 0,
        // Linked businesses — orgs registered by chamber members that are
        // affiliated with this chamber. Mirrors how real chambers list
        // member-companies.
        'linkedBusinesses': <String>[],
        'memberBusinessCount': 0,
        // Unified bilateral GDP tracking. All economic activity in this
        // corridor (DSP transfers, marketplace sales, hosting, B2B fiat,
        // etc.) is rolled up here by the recordCorridorActivity helper in
        // functions/lib/corridor_activity.js. The chamber is the single
        // source of truth for "what's happening in this corridor."
        'gdpTotal': 0,
        'gdpByActivityType': <String, dynamic>{},
        'gdpByDirection': <String, dynamic>{},
        'transactionCount': 0,
        'lastTransactionAt': null,
        'isPublic': true,
        'country': host,
        'homeCountryCode': home,
        'hostCountryCode': host,
        'communityId': null,
        'richData': null,
        'chatId': chatId,
        'status': 'active',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

      tx.set(docRef, orgData);
      tx.set(chatRef, {
        'id': chatId,
        'type': 'organization',
        'subtype': 'corridor_chamber',
        'name': name,
        'participants': <String>[],
        'admins': <String>[],
        'homeCountryCode': home,
        'hostCountryCode': host,
        'createdAt': now,
        'updatedAt': now,
        'createdBy': 'system',
        'lastMessage': {
          'content': 'Chamber of Commerce opened',
          'timestamp': now,
          'type': 'system',
          'senderId': 'system',
          'senderName': 'System',
        },
      });
      return true;
    });

    debugPrint(
      wasCreated
          ? '✅ ensureCorridorChamber: created $orgId (empty, opt-in)'
          : '✅ ensureCorridorChamber: $orgId already exists',
    );

    return orgId;
  }

  // ─────────────────────────────────────────────────────────────────────
  // CHAMBER FOLLOW / JOIN — opt-in membership lifecycle.
  //
  //   Visitor   → no record on the chamber. Cannot read the chat.
  //   Follower  → in `followers`. Chat appears in their list, read-only.
  //   Member    → in `members` (and `followers`). Full participation.
  //
  // State transitions: visitor → followChamber → follower → joinChamber →
  // member → leaveChamber → follower → unfollowChamber → visitor.
  // Joining without first following is allowed and bundles both writes.
  // ─────────────────────────────────────────────────────────────────────

  /// Read-only subscription to a chamber. Adds the user to `followers` and
  /// drops the chamber chat into their userChats list (with an
  /// `accessLevel: 'follower'` marker so the chat screen can render
  /// read-only). Does NOT add them to `members`.
  Future<void> followChamber({
    required String orgId,
    required String userId,
  }) async {
    final orgRef = _firestore.collection('organizations').doc(orgId);
    final snap = await orgRef.get();
    if (!snap.exists || snap.data()?['kind'] != 'corridor_chamber') {
      throw StateError('Not a chamber: $orgId');
    }
    final chatId = snap.data()?['chatId'] as String? ?? 'org_$orgId';
    final now = DateTime.now().millisecondsSinceEpoch;

    await orgRef.update({
      'followers': FieldValue.arrayUnion([userId]),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await _firestore.collection('chats').doc(chatId).update({
      'participants': FieldValue.arrayUnion([userId]),
      'updatedAt': now,
    });
    await _firestore
        .collection('users')
        .doc(userId)
        .collection('userChats')
        .doc(chatId)
        .set({
          'chatId': chatId,
          'accessLevel': 'follower',
          'isDeleted': false,
          'updatedAt': now,
          'lastRead': now,
        }, SetOptions(merge: true));
  }

  /// Reverse of [followChamber]. Removes from followers and drops the chat
  /// from userChats. If the user was also a `member`, this is a no-op for
  /// `members` — call [leaveChamber] first if you want a full exit.
  Future<void> unfollowChamber({
    required String orgId,
    required String userId,
  }) async {
    final orgRef = _firestore.collection('organizations').doc(orgId);
    final snap = await orgRef.get();
    if (!snap.exists) return;
    final data = snap.data() ?? {};
    if (data['kind'] != 'corridor_chamber') return;

    final members = List<String>.from(data['members'] ?? const <String>[]);
    if (members.contains(userId)) {
      throw StateError(
        'You are a chamber member. Leave the chamber first before unfollowing.',
      );
    }

    final chatId = data['chatId'] as String? ?? 'org_$orgId';
    await orgRef.update({
      'followers': FieldValue.arrayRemove([userId]),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await _firestore.collection('chats').doc(chatId).update({
      'participants': FieldValue.arrayRemove([userId]),
    });
    await _firestore
        .collection('users')
        .doc(userId)
        .collection('userChats')
        .doc(chatId)
        .delete();
  }

  /// Become a full member. Idempotent and acceptable starting from any
  /// state (visitor or follower) — promotes follower to member, or
  /// performs both follow + member writes for a brand-new visitor.
  Future<void> joinChamber({
    required String orgId,
    required String userId,
  }) async {
    final orgRef = _firestore.collection('organizations').doc(orgId);
    final initialSnap = await orgRef.get();
    if (!initialSnap.exists || initialSnap.data()?['kind'] != 'corridor_chamber') {
      throw StateError('Not a chamber: $orgId');
    }
    final chatId = initialSnap.data()?['chatId'] as String? ?? 'org_$orgId';
    final chatRef = _firestore.collection('chats').doc(chatId);
    final now = DateTime.now().millisecondsSinceEpoch;

    await _firestore.runTransaction((tx) async {
      final fresh = await tx.get(orgRef);
      if (!fresh.exists) throw StateError('Chamber disappeared mid-join');
      final data = fresh.data() ?? {};
      final members = List<String>.from(data['members'] ?? const <String>[]);
      final alreadyMember = members.contains(userId);

      tx.update(orgRef, {
        'members': FieldValue.arrayUnion([userId]),
        'followers': FieldValue.arrayUnion([userId]),
        if (!alreadyMember)
          'memberCount': FieldValue.increment(1),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      tx.update(chatRef, {
        'participants': FieldValue.arrayUnion([userId]),
        'updatedAt': now,
      });
    });

    await _firestore
        .collection('users')
        .doc(userId)
        .collection('userChats')
        .doc(chatId)
        .set({
          'chatId': chatId,
          'accessLevel': 'member',
          'isDeleted': false,
          'updatedAt': now,
          'lastRead': now,
        }, SetOptions(merge: true));
  }

  /// Step down from full membership. Demotes a member back to follower
  /// (so they still see the chat read-only). To fully exit, call
  /// [unfollowChamber] after this.
  Future<void> leaveChamber({
    required String orgId,
    required String userId,
  }) async {
    final orgRef = _firestore.collection('organizations').doc(orgId);
    await _firestore.runTransaction((tx) async {
      final snap = await tx.get(orgRef);
      if (!snap.exists) return;
      final data = snap.data() ?? {};
      if (data['kind'] != 'corridor_chamber') return;
      final members = List<String>.from(data['members'] ?? const <String>[]);
      if (!members.contains(userId)) return;
      tx.update(orgRef, {
        'members': FieldValue.arrayRemove([userId]),
        'memberCount': FieldValue.increment(-1),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
    final chatId =
        (await orgRef.get()).data()?['chatId'] as String? ?? 'org_$orgId';
    await _firestore
        .collection('users')
        .doc(userId)
        .collection('userChats')
        .doc(chatId)
        .set({'accessLevel': 'follower'}, SetOptions(merge: true));
  }

  /// Link a user-registered organization to a chamber. The caller must be
  /// an admin/superAdmin of the org, and a member of the chamber.
  Future<void> linkBusinessToChamber({
    required String chamberOrgId,
    required String businessOrgId,
    required String userId,
  }) async {
    final chamberRef =
        _firestore.collection('organizations').doc(chamberOrgId);
    final businessRef =
        _firestore.collection('organizations').doc(businessOrgId);

    final businessSnap = await businessRef.get();
    if (!businessSnap.exists) throw StateError('Business not found.');
    final business = businessSnap.data() ?? {};
    if (business['kind'] == 'corridor_chamber') {
      throw StateError('Cannot link a chamber to a chamber.');
    }
    final admins = List<String>.from(business['admins'] ?? const <String>[]);
    final isSuperAdmin = business['superAdminId'] == userId;
    if (!isSuperAdmin && !admins.contains(userId)) {
      throw StateError(
        'Only an admin of the business can link it to a chamber.',
      );
    }

    final chamberSnap = await chamberRef.get();
    if (!chamberSnap.exists ||
        chamberSnap.data()?['kind'] != 'corridor_chamber') {
      throw StateError('Not a chamber: $chamberOrgId');
    }
    final chamberMembers = List<String>.from(
      chamberSnap.data()?['members'] ?? const <String>[],
    );
    if (!chamberMembers.contains(userId)) {
      throw StateError('Join the chamber first before linking a business.');
    }

    await chamberRef.update({
      'linkedBusinesses': FieldValue.arrayUnion([businessOrgId]),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await businessRef.update({
      'linkedChamberIds': FieldValue.arrayUnion([chamberOrgId]),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Inverse of [linkBusinessToChamber].
  Future<void> unlinkBusinessFromChamber({
    required String chamberOrgId,
    required String businessOrgId,
    required String userId,
  }) async {
    final businessSnap =
        await _firestore.collection('organizations').doc(businessOrgId).get();
    if (!businessSnap.exists) return;
    final business = businessSnap.data() ?? {};
    final admins = List<String>.from(business['admins'] ?? const <String>[]);
    final isSuperAdmin = business['superAdminId'] == userId;
    if (!isSuperAdmin && !admins.contains(userId)) {
      throw StateError(
        'Only an admin of the business can unlink it from a chamber.',
      );
    }
    await _firestore.collection('organizations').doc(chamberOrgId).update({
      'linkedBusinesses': FieldValue.arrayRemove([businessOrgId]),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await _firestore.collection('organizations').doc(businessOrgId).update({
      'linkedChamberIds': FieldValue.arrayRemove([chamberOrgId]),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Appoint a trusted user to a leadership seat on a corridor chamber.
  ///
  /// **Caller authorization is the caller's responsibility.** This method
  /// trusts that the caller has already verified the requesting user holds
  /// the platform-admin claim (or that it's being invoked from an admin
  /// script). Production deployments should additionally gate this via
  /// Firestore Security Rules using `request.auth.token.admin == true`.
  ///
  /// Writes:
  ///   - `councilRoles[uid] = role` on the org doc (the canonical mapping)
  ///   - `adminTitles[uid] = displayName` (for UI labels & parity with
  ///     user-registered orgs)
  ///   - `admins` arrayUnion the user (gives moderation power in the chat)
  ///   - chamber chat `adminIds` arrayUnion (chat-level moderation)
  ///
  /// Validation:
  ///   - [role] must be one of [ChamberRoles.all]
  ///   - [userId] must already be a `members` entry on the chamber
  ///   - Home-pinned roles require `user.homeCountryCode == chamber.homeCountryCode`
  ///   - Host-pinned roles require `user.hostCountryCode == chamber.hostCountryCode`
  ///     OR a past-locations entry in the host country
  ///   - Single-occupant role: any prior holder is automatically replaced
  ///     (their `councilRoles` entry and `adminTitles` entry are cleared,
  ///     but they keep their `admins` chat moderation power until a
  ///     separate [removeChamberLeader] call).
  Future<void> appointChamberLeader({
    required String orgId,
    required String userId,
    required String role,
  }) async {
    if (!ChamberRoles.isValid(role)) {
      throw ArgumentError('Unknown chamber role: $role');
    }

    final orgRef = _firestore.collection('organizations').doc(orgId);

    // Pre-fetch the user profile for nationality validation — outside the
    // transaction to keep the tx body small and avoid cross-collection
    // contention.
    final userSnap = await _firestore.collection('users').doc(userId).get();
    if (!userSnap.exists) {
      throw StateError('User $userId does not exist.');
    }
    final userProfile = userSnap.data() ?? {};
    final userHome = (userProfile['homeCountryCode'] as String?)?.toUpperCase();
    final userHost = (userProfile['hostCountryCode'] as String?)?.toUpperCase();
    final pastCountryCodes = ((userProfile['pastLocations'] as List?) ?? [])
        .map((e) {
          if (e is! Map) return null;
          final loc = e['location'];
          if (loc is! Map) return null;
          return (loc['countryCode'] as String?)?.toUpperCase();
        })
        .whereType<String>()
        .toSet();

    await _firestore.runTransaction((tx) async {
      final snap = await tx.get(orgRef);
      if (!snap.exists) {
        throw StateError('Chamber $orgId not found.');
      }
      final data = snap.data() ?? {};

      if (data['kind'] != 'corridor_chamber') {
        throw StateError(
          'appointChamberLeader is only valid on corridor_chamber orgs '
          '(got kind="${data['kind']}").',
        );
      }

      final chamberHome = (data['homeCountryCode'] as String?)?.toUpperCase();
      final chamberHost = (data['hostCountryCode'] as String?)?.toUpperCase();

      // Nationality / lived-experience pin checks.
      if (ChamberRoles.homePinned.contains(role)) {
        if (chamberHome == null || userHome != chamberHome) {
          throw StateError(
            'Home-pinned role "$role" requires the appointee to be a '
            'national of the chamber\'s home country ($chamberHome). '
            'User\'s home is $userHome.',
          );
        }
      }
      if (ChamberRoles.hostPinned.contains(role)) {
        final isCurrentHostNational =
            chamberHost != null && userHost == chamberHost;
        final hasLivedInHost =
            chamberHost != null && pastCountryCodes.contains(chamberHost);
        if (!isCurrentHostNational && !hasLivedInHost) {
          throw StateError(
            'Host-pinned role "$role" requires the appointee to either '
            'currently live in the host country ($chamberHost) or have a '
            'past-location there.',
          );
        }
      }

      // Membership check.
      final members = List<String>.from(data['members'] ?? const <String>[]);
      if (!members.contains(userId)) {
        throw StateError(
          'User $userId is not a member of chamber $orgId. Members must '
          'join the chamber (auto-joined at signup) before being appointed.',
        );
      }

      // Replace the prior holder of this single-occupant seat, if any.
      final councilRoles = Map<String, String>.from(
        (data['councilRoles'] as Map?)?.cast<String, String>() ??
            const <String, String>{},
      );
      final adminTitles = Map<String, String>.from(
        (data['adminTitles'] as Map?)?.cast<String, String>() ??
            const <String, String>{},
      );

      final priorHolders = councilRoles.entries
          .where((e) => e.value == role && e.key != userId)
          .map((e) => e.key)
          .toList();
      for (final priorUid in priorHolders) {
        councilRoles.remove(priorUid);
        adminTitles.remove(priorUid);
      }

      councilRoles[userId] = role;
      adminTitles[userId] = ChamberRoles.displayName(role);

      final admins = List<String>.from(data['admins'] ?? const <String>[]);
      if (!admins.contains(userId)) admins.add(userId);

      tx.update(orgRef, {
        'councilRoles': councilRoles,
        'adminTitles': adminTitles,
        'admins': admins,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // Mirror chat-level moderation.
      final chatId = data['chatId'] as String?;
      if (chatId != null) {
        tx.update(_firestore.collection('chats').doc(chatId), {
          'admins': FieldValue.arrayUnion([userId]),
          'updatedAt': DateTime.now().millisecondsSinceEpoch,
        });
      }
    });

    debugPrint(
      '🏛️ Appointed $userId as ${ChamberRoles.displayName(role)} of $orgId',
    );
  }

  /// Submit a request to be appointed to a chamber leadership seat.
  ///
  /// Anyone who is a member of the chamber may request. Pre-flight validation
  /// catches the obvious failures (unknown role, non-member, duplicate
  /// pending request, nationality-pin violations) BEFORE the doc is written
  /// so callers don't litter the collection with garbage that admins then
  /// have to reject one-by-one.
  ///
  /// Returns the new request id. Admins approve by flipping `approved: true`
  /// (via the CLI, Firebase console, or future admin UI); a Cloud Function
  /// then performs the actual appointment server-side.
  Future<String> requestChamberLeadership({
    required String orgId,
    required String userId,
    required String role,
    String message = '',
  }) async {
    if (!ChamberRoles.isValid(role)) {
      throw ArgumentError('Unknown chamber role: $role');
    }

    // Load chamber + user in parallel for the pre-flight check.
    final orgSnapFuture = _firestore.collection('organizations').doc(orgId).get();
    final userSnapFuture = _firestore.collection('users').doc(userId).get();
    final orgSnap = await orgSnapFuture;
    final userSnap = await userSnapFuture;

    if (!orgSnap.exists) throw StateError('Chamber $orgId not found.');
    final org = orgSnap.data() ?? {};
    if (org['kind'] != 'corridor_chamber') {
      throw StateError(
        'Leadership requests are only valid on corridor_chamber orgs.',
      );
    }
    if (!userSnap.exists) throw StateError('User $userId not found.');
    final user = userSnap.data() ?? {};

    // Membership check.
    final members = List<String>.from(org['members'] ?? const <String>[]);
    if (!members.contains(userId)) {
      throw StateError(
        'You must be a chamber member to request leadership. '
        '(Membership is auto-granted at signup for users in this corridor.)',
      );
    }

    // Nationality / lived-experience pin checks — same rules as direct
    // appointment, so rejected requests at approval-time should be rare.
    final chamberHome = (org['homeCountryCode'] as String?)?.toUpperCase();
    final chamberHost = (org['hostCountryCode'] as String?)?.toUpperCase();
    final userHome = (user['homeCountryCode'] as String?)?.toUpperCase();
    final userHost = (user['hostCountryCode'] as String?)?.toUpperCase();
    final pastCountryCodes = ((user['pastLocations'] as List?) ?? [])
        .map((e) {
          if (e is! Map) return null;
          final loc = e['location'];
          if (loc is! Map) return null;
          return (loc['countryCode'] as String?)?.toUpperCase();
        })
        .whereType<String>()
        .toSet();

    if (ChamberRoles.homePinned.contains(role) &&
        (chamberHome == null || userHome != chamberHome)) {
      throw StateError(
        '${ChamberRoles.displayName(role)} requires home country '
        '$chamberHome.',
      );
    }
    if (ChamberRoles.hostPinned.contains(role)) {
      final livesInHost = chamberHost != null && userHost == chamberHost;
      final livedInHost =
          chamberHost != null && pastCountryCodes.contains(chamberHost);
      if (!livesInHost && !livedInHost) {
        throw StateError(
          '${ChamberRoles.displayName(role)} requires lived experience in '
          '$chamberHost (current or past).',
        );
      }
    }

    // Reject duplicate pending request for the same (user, chamber, role).
    final existing = await _firestore
        .collection('leadershipRequests')
        .where('chamberId', isEqualTo: orgId)
        .where('userId', isEqualTo: userId)
        .where('role', isEqualTo: role)
        .where('status', isEqualTo: ChamberLeadershipRequest.statusPending)
        .limit(1)
        .get();
    if (existing.docs.isNotEmpty) {
      throw StateError(
        'You already have a pending request for '
        '${ChamberRoles.displayName(role)} in this chamber.',
      );
    }

    final docRef = _firestore.collection('leadershipRequests').doc();
    await docRef.set({
      'id': docRef.id,
      'chamberId': orgId,
      'userId': userId,
      'role': role,
      'message': message,
      'status': ChamberLeadershipRequest.statusPending,
      'approved': false,
      'createdAt': FieldValue.serverTimestamp(),
      'decidedAt': null,
      'decidedBy': null,
      'decisionNote': null,
    });

    debugPrint('📨 Leadership request ${docRef.id}: $userId → $role @ $orgId');
    return docRef.id;
  }

  /// Stream PENDING leadership requests for a single chamber. For admin UIs.
  Stream<List<ChamberLeadershipRequest>> watchPendingLeadershipRequests(
    String orgId,
  ) {
    return _firestore
        .collection('leadershipRequests')
        .where('chamberId', isEqualTo: orgId)
        .where('status', isEqualTo: ChamberLeadershipRequest.statusPending)
        .snapshots()
        .map(
          (snap) => snap.docs
              .map((d) => ChamberLeadershipRequest.fromJson(d.id, d.data()))
              .toList(),
        );
  }

  /// Stream requests submitted BY a specific user (any status). Lets a user
  /// see the state of their own pitches.
  Stream<List<ChamberLeadershipRequest>> watchMyLeadershipRequests(
    String userId,
  ) {
    return _firestore
        .collection('leadershipRequests')
        .where('userId', isEqualTo: userId)
        .snapshots()
        .map(
          (snap) => snap.docs
              .map((d) => ChamberLeadershipRequest.fromJson(d.id, d.data()))
              .toList(),
        );
  }

  /// Remove a user from a chamber leadership seat. Strips their council
  /// role + title and removes them from the org/chat admin lists. They
  /// remain a regular member.
  ///
  /// If [role] is provided, only that seat is cleared (no-op if the user
  /// doesn't currently hold it). If omitted, ANY seat the user holds is
  /// cleared.
  Future<void> removeChamberLeader({
    required String orgId,
    required String userId,
    String? role,
  }) async {
    final orgRef = _firestore.collection('organizations').doc(orgId);

    await _firestore.runTransaction((tx) async {
      final snap = await tx.get(orgRef);
      if (!snap.exists) return;
      final data = snap.data() ?? {};
      if (data['kind'] != 'corridor_chamber') {
        throw StateError(
          'removeChamberLeader is only valid on corridor_chamber orgs.',
        );
      }

      final councilRoles = Map<String, String>.from(
        (data['councilRoles'] as Map?)?.cast<String, String>() ??
            const <String, String>{},
      );
      final adminTitles = Map<String, String>.from(
        (data['adminTitles'] as Map?)?.cast<String, String>() ??
            const <String, String>{},
      );

      final currentRole = councilRoles[userId];
      if (currentRole == null) return;
      if (role != null && currentRole != role) return;

      councilRoles.remove(userId);
      adminTitles.remove(userId);

      final admins = List<String>.from(data['admins'] ?? const <String>[]);
      admins.remove(userId);

      tx.update(orgRef, {
        'councilRoles': councilRoles,
        'adminTitles': adminTitles,
        'admins': admins,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      final chatId = data['chatId'] as String?;
      if (chatId != null) {
        tx.update(_firestore.collection('chats').doc(chatId), {
          'admins': FieldValue.arrayRemove([userId]),
          'updatedAt': DateTime.now().millisecondsSinceEpoch,
        });
      }
    });

    debugPrint('🪑 Removed $userId from chamber seat in $orgId');
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

    // 3. Add to userChats and participants in Firestore if chatId exists
    if (chatId != null) {
      final now = DateTime.now().millisecondsSinceEpoch;
      await _firestore
          .collection('users')
          .doc(userId)
          .collection('userChats')
          .doc(chatId)
          .set({
            'chatId': chatId,
            'updatedAt': now,
            'following': true,
          }, SetOptions(merge: true));

      // Also add to participants so they can post to the board
      await _firestore.collection('chats').doc(chatId).update({
        'participants': FieldValue.arrayUnion([userId]),
      });
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
    await _firestore
        .collection('users')
        .doc(userId)
        .collection('userChats')
        .doc(chatId)
        .set({'chatId': chatId, 'updatedAt': now}, SetOptions(merge: true));

    // 2. Add to participants in Firestore
    await _firestore.collection('chats').doc(chatId).update({
      'participants': FieldValue.arrayUnion([userId]),
    });
  }

  /// Remove a user from organization chat participants (Admin only)
  Future<void> removeChatMember(String orgId, String userId) async {
    final doc = await _firestore.collection('organizations').doc(orgId).get();
    if (!doc.exists) return;

    final chatId = doc.data()?['chatId'] as String?;
    if (chatId == null) return;

    // Remove from participants in Firestore
    await _firestore.collection('chats').doc(chatId).update({
      'participants': FieldValue.arrayRemove([userId]),
    });
  }

  /// Unfollow an organization
  Future<void> unfollowOrganization(String orgId, String userId) async {
    final docRef = _firestore.collection('organizations').doc(orgId);
    final docSnapshot = await docRef.get();

    if (!docSnapshot.exists) return; // Silent fail
    final data = docSnapshot.data()!;
    final chatId = data['chatId'] as String?;

    // Corridor chambers are auto-membership organizations: every user in
    // the (home, host) pairing belongs to the chamber by virtue of their
    // diaspora corridor, not opt-in. Unfollowing must be a no-op so we
    // don't strip them from a body they didn't choose to leave.
    if (data['kind'] == 'corridor_chamber') {
      throw StateError(
        'Corridor chambers are auto-membership — you cannot unfollow them. '
        'Mute the chat instead if you want to silence notifications.',
      );
    }

    // 1. Remove from followers
    await docRef.update({
      'followers': FieldValue.arrayRemove([userId]),
    });

    // 2. Remove from userChats and participants in Firestore
    if (chatId != null) {
      await _firestore
          .collection('users')
          .doc(userId)
          .collection('userChats')
          .doc(chatId)
          .delete();

      await _firestore.collection('chats').doc(chatId).update({
        'participants': FieldValue.arrayRemove([userId]),
      });
    }

    // 3. Force refresh local cache
    await getOrganization(orgId, force: true);
  }

  /// Enable specialized Product/Service listing for a business
  Future<void> enableProductListing(String orgId, String userId) async {
    await _firestore.collection('organizations').doc(orgId).update({
      'isListingEnabled': true,
      'listingPaidAt': FieldValue.serverTimestamp(),
      'listingPaidBy': userId,
    });

    // Refresh local cache
    await getOrganization(orgId, force: true);
  }

  /// [NEW] Add a product or service item (100 DSP)
  Future<String> addProductItem(
    String orgId,
    String userId,
    Map<String, dynamic> itemData,
  ) async {
    // Save Item
    final docRef = _firestore
        .collection('organizations')
        .doc(orgId)
        .collection('products')
        .doc();

    await docRef.set({
      ...itemData,
      'id': docRef.id,
      'createdBy': userId,
      'createdAt': FieldValue.serverTimestamp(),
    });

    return docRef.id;
  }
}
