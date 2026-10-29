import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rxdart/rxdart.dart';
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
      ref.keepAlive();
      return ref.watch(organizationRepositoryProvider).getOrganization(id);
    });

class OrganizationRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  final OrganizationLocalService _localService;
  static final Map<String, Map<String, dynamic>> _orgCache = {};
  static final Map<String, List<Map<String, dynamic>>> _userOrgsCache = {};
  static List<Map<String, dynamic>>? _allOrgsCache;
  static final Map<String, List<ChamberLeadershipRequest>>
      _myLeadershipRequestsCache = {};
  static final Map<String, List<ChamberLeadershipRequest>>
      _pendingLeadershipRequestsCache = {};

  OrganizationRepository(Ref ref) : _localService = OrganizationLocalService();

  Map<String, dynamic>? getCachedOrganization(String orgId) => _orgCache[orgId];

  void cacheOrganization(String orgId, Map<String, dynamic> data) {
    _orgCache[orgId] = {...data, 'id': orgId};
  }

  List<Map<String, dynamic>>? getCachedUserOrganizations(String userId) =>
      _userOrgsCache[userId];

  List<Map<String, dynamic>>? getCachedAllOrganizations() => _allOrgsCache;

  List<ChamberLeadershipRequest>? getCachedMyLeadershipRequests(
    String userId,
  ) => _myLeadershipRequestsCache[userId];

  List<ChamberLeadershipRequest>? getCachedPendingLeadershipRequests(
    String orgId,
  ) => _pendingLeadershipRequestsCache[orgId];

  /// Watch organizations where the user is an admin, superAdmin, or pendingAdmin
  Stream<List<Map<String, dynamic>>> watchUserOrganizations(String userId) {
    final admins = _firestore
        .collection('organizations')
        .where('admins', arrayContains: userId)
        .limit(100)
        .snapshots();
    final pending = _firestore
        .collection('organizations')
        .where('pendingAdmins', arrayContains: userId)
        .limit(100)
        .snapshots();
    final owned = _firestore
        .collection('organizations')
        .where('superAdminId', isEqualTo: userId)
        .limit(100)
        .snapshots();

    return Rx.combineLatest3(admins, pending, owned, (a, p, o) {
      final unique = <String, Map<String, dynamic>>{};
      for (final doc in [...a.docs, ...p.docs, ...o.docs]) {
        final item = {...doc.data(), 'id': doc.id};
        unique[doc.id] = item;
        _orgCache[doc.id] = item;
      }
      final list = unique.values.toList();
      _userOrgsCache[userId] = list;
      return list;
    }).startWith(_userOrgsCache[userId] ?? const <Map<String, dynamic>>[]);
  }

  /// Fetch organizations where the user is an admin or superAdmin
  Future<List<Map<String, dynamic>>> getUserOrganizations(String userId) async {
    try {
      final orgs = <String, Map<String, dynamic>>{};

      final results = await Future.wait([
        _firestore
            .collection('organizations')
            .where('admins', arrayContains: userId)
            .limit(100)
            .get(),
        _firestore
            .collection('organizations')
            .where('superAdminId', isEqualTo: userId)
            .limit(100)
            .get(),
        _firestore
            .collection('organizations')
            .where('pendingAdmins', arrayContains: userId)
            .limit(100)
            .get(),
        _localService.getUserOrganizations(userId),
      ]);

      final adminsQuery = results[0] as QuerySnapshot<Map<String, dynamic>>;
      final superAdminsQuery =
          results[1] as QuerySnapshot<Map<String, dynamic>>;
      final pendingAdminsQuery =
          results[2] as QuerySnapshot<Map<String, dynamic>>;
      final cachedOrgs = results[3] as List<Map<String, dynamic>>;

      for (final query in [
        adminsQuery,
        superAdminsQuery,
        pendingAdminsQuery,
      ]) {
        for (var doc in query.docs) {
          final data = doc.data();
          data['id'] = doc.id;
          orgs[doc.id] = data;
          _orgCache[doc.id] = data;
        }
      }

      // Merge with local cache
      for (final org in cachedOrgs) {
        final id = org['id'] as String?;
        if (id != null && !orgs.containsKey(id)) {
          orgs[id] = org;
          _orgCache[id] = org;
        }
      }

      final list = orgs.values.toList();
      _userOrgsCache[userId] = list;
      return list;
    } catch (e) {
      debugPrint('Error in getUserOrganizations: $e');
      return _userOrgsCache[userId] ?? [];
    }
  }

  /// Get all active organizations
  Future<List<Map<String, dynamic>>> getAllOrganizations() async {
    try {
      final snapshot = await _firestore
          .collection('organizations')
          .where('status', isEqualTo: 'active')
          .limit(200)
          .get();

      final list = snapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        _orgCache[doc.id] = data;
        return data;
      }).toList();
      _allOrgsCache = list;
      return list;
    } catch (e) {
      debugPrint('Error fetching organizations: $e');
      return _allOrgsCache ?? [];
    }
  }

  /// Search organizations by name
  Future<List<Map<String, dynamic>>> searchOrganizations(String query) async {
    try {
      final queryLower = query.toLowerCase();

      final snapshot = await _firestore
          .collection('organizations')
          .where('status', isEqualTo: 'active')
          .limit(200)
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
    // 1. Check In-Memory Cache
    if (!force && _orgCache.containsKey(orgId)) {
      _fetchAndSaveOrg(orgId);
      return _orgCache[orgId];
    }
    // 2. Check Local Cache
    if (!force) {
      final localOrg = await _localService.getOrganization(orgId);
      if (localOrg != null) {
        _orgCache[orgId] = localOrg;
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
        _orgCache[orgId] = data;

        // Cache to Isar
        await _localService.saveOrganization(data);

        return data;
      }
      return null;
    } catch (e) {
      debugPrint('Error fetching/saving org: $e');
      return _orgCache[orgId];
    }
  }

  /// Invite an admin
  Future<void> inviteAdmin(String orgId, String userId) async {
    await FirebaseFunctions.instance
        .httpsCallable('manageOrganizationAdmin')
        .call<void>({
          'organizationId': orgId,
          'action': 'invite',
          'userId': userId,
        });
  }

  /// Accept an admin invite
  Future<void> acceptInvite(String orgId, String userId) async {
    await FirebaseFunctions.instance
        .httpsCallable('manageOrganizationAdmin')
        .call<void>({'organizationId': orgId, 'action': 'accept'});
  }

  /// Decline or remove pending invite
  Future<void> declineInvite(String orgId, String userId) async {
    await FirebaseFunctions.instance
        .httpsCallable('manageOrganizationAdmin')
        .call<void>({'organizationId': orgId, 'action': 'decline'});
  }

  /// Remove an existing admin
  Future<void> removeAdmin(String orgId, String adminId) async {
    await FirebaseFunctions.instance
        .httpsCallable('manageOrganizationAdmin')
        .call<void>({
          'organizationId': orgId,
          'action': 'remove',
          'userId': adminId,
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

    await docRef.set(orgData);
    await FirebaseFunctions.instance
        .httpsCallable('createChat')
        .call<Map<String, dynamic>>({
          'mode': 'organization',
          'organizationId': orgId,
        });

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
    final result = await FirebaseFunctions.instanceFor(
      region: 'us-central1',
    ).httpsCallable('ensureSignupChamber').call<Map<String, dynamic>>();
    return result.data['chatId'] as String?;
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
    final chatId = snap.data()?['chatId'] as String? ?? orgId;
    try {
      await FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('setChamberFollow')
          .call<void>({'chatId': chatId, 'following': true});
    } catch (_) {
      // Direct Firestore transaction fallback for seamless reliability
      final batch = _firestore.batch();
      batch.update(orgRef, {
        'followers': FieldValue.arrayUnion([userId]),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      final userChatRef = _firestore
          .collection('users')
          .doc(userId)
          .collection('userChats')
          .doc(chatId);
      batch.set(userChatRef, {
        'chatId': chatId,
        'accessLevel': 'follower',
        'isDeleted': false,
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
        'lastRead': DateTime.now().millisecondsSinceEpoch,
      }, SetOptions(merge: true));
      await batch.commit();
    }
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

    final chatId = data['chatId'] as String? ?? orgId;
    try {
      await FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('setChamberFollow')
          .call<void>({'chatId': chatId, 'following': false});
    } catch (_) {
      // Direct Firestore transaction fallback
      final batch = _firestore.batch();
      batch.update(orgRef, {
        'followers': FieldValue.arrayRemove([userId]),
        'members': FieldValue.arrayRemove([userId]),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      final userChatRef = _firestore
          .collection('users')
          .doc(userId)
          .collection('userChats')
          .doc(chatId);
      batch.delete(userChatRef);
      final userRef = _firestore.collection('users').doc(userId);
      batch.set(userRef, {
        'organizationMemberships': FieldValue.arrayRemove([orgId, chatId]),
      }, SetOptions(merge: true));
      await batch.commit();
    }
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
    if (!initialSnap.exists ||
        initialSnap.data()?['kind'] != 'corridor_chamber') {
      throw StateError('Not a chamber: $orgId');
    }
    final chatId = initialSnap.data()?['chatId'] as String? ?? orgId;
    try {
      await FirebaseFunctions.instanceFor(
        region: 'us-central1',
      ).httpsCallable('joinChamber').call<void>({'chatId': chatId});
    } catch (_) {
      // Direct Firestore transaction fallback
      final batch = _firestore.batch();
      final orgData = initialSnap.data() ?? {};
      final members = List<String>.from(orgData['members'] as List? ?? []);
      if (!members.contains(userId)) members.add(userId);

      batch.update(orgRef, {
        'members': FieldValue.arrayUnion([userId]),
        'followers': FieldValue.arrayUnion([userId]),
        'memberCount': members.length,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      final userChatRef = _firestore
          .collection('users')
          .doc(userId)
          .collection('userChats')
          .doc(chatId);
      batch.set(userChatRef, {
        'chatId': chatId,
        'accessLevel': 'member',
        'isDeleted': false,
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
        'lastRead': DateTime.now().millisecondsSinceEpoch,
      }, SetOptions(merge: true));
      final userRef = _firestore.collection('users').doc(userId);
      batch.set(userRef, {
        'organizationMemberships': FieldValue.arrayUnion([orgId]),
      }, SetOptions(merge: true));
      await batch.commit();
    }
  }

  /// Step down from full membership. Demotes a member back to follower
  /// (so they still see the chat read-only). To fully exit, call
  /// [unfollowChamber] after this.
  Future<void> leaveChamber({
    required String orgId,
    required String userId,
  }) async {
    final orgRef = _firestore.collection('organizations').doc(orgId);
    final snapshot = await orgRef.get();
    if (!snapshot.exists) return;
    final chatId = snapshot.data()?['chatId'] as String? ?? orgId;
    try {
      await FirebaseFunctions.instanceFor(
        region: 'us-central1',
      ).httpsCallable('leaveChamber').call<void>({'chatId': chatId});
    } catch (_) {
      // Direct Firestore transaction fallback for immediate local reliability
      final batch = _firestore.batch();
      final orgData = snapshot.data() ?? {};
      final members = List<String>.from(orgData['members'] as List? ?? []);
      members.remove(userId);

      batch.update(orgRef, {
        'members': FieldValue.arrayRemove([userId]),
        'memberCount': members.length,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      final userChatRef = _firestore
          .collection('users')
          .doc(userId)
          .collection('userChats')
          .doc(chatId);
      batch.set(userChatRef, {
        'accessLevel': 'follower',
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      }, SetOptions(merge: true));
      final userRef = _firestore.collection('users').doc(userId);
      batch.set(userRef, {
        'organizationMemberships': FieldValue.arrayRemove([orgId, chatId]),
      }, SetOptions(merge: true));
      await batch.commit();
    }
  }

  /// Link a user-registered organization to a chamber. The caller must be
  /// an admin/superAdmin of the org, and a member of the chamber.
  Future<void> linkBusinessToChamber({
    required String chamberOrgId,
    required String businessOrgId,
    required String userId,
  }) async {
    await FirebaseFunctions.instance
        .httpsCallable('setBusinessChamberLink')
        .call<void>({
          'chamberId': chamberOrgId,
          'businessId': businessOrgId,
          'linked': true,
        });
  }

  /// Inverse of [linkBusinessToChamber].
  Future<void> unlinkBusinessFromChamber({
    required String chamberOrgId,
    required String businessOrgId,
    required String userId,
  }) async {
    await FirebaseFunctions.instance
        .httpsCallable('setBusinessChamberLink')
        .call<void>({
          'chamberId': chamberOrgId,
          'businessId': businessOrgId,
          'linked': false,
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
    final orgSnapFuture = _firestore
        .collection('organizations')
        .doc(orgId)
        .get();
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
    return Stream.multi((controller) {
      final cached = _pendingLeadershipRequestsCache[orgId];
      if (cached != null) {
        controller.add(cached);
      }
      final sub = _firestore
          .collection('leadershipRequests')
          .where('chamberId', isEqualTo: orgId)
          .where('status', isEqualTo: ChamberLeadershipRequest.statusPending)
          .limit(100)
          .snapshots()
          .listen(
            (snap) {
              final list = snap.docs
                  .map((d) => ChamberLeadershipRequest.fromJson(d.id, d.data()))
                  .toList();
              _pendingLeadershipRequestsCache[orgId] = list;
              controller.add(list);
            },
            onError: controller.addError,
            onDone: controller.close,
          );
      controller.onCancel = sub.cancel;
    });
  }

  /// Stream requests submitted BY a specific user (any status). Lets a user
  /// see the state of their own pitches.
  Stream<List<ChamberLeadershipRequest>> watchMyLeadershipRequests(
    String userId,
  ) {
    return Stream.multi((controller) {
      final cached = _myLeadershipRequestsCache[userId];
      if (cached != null) {
        controller.add(cached);
      }
      final sub = _firestore
          .collection('leadershipRequests')
          .where('userId', isEqualTo: userId)
          .limit(100)
          .snapshots()
          .listen(
            (snap) {
              final list = snap.docs
                  .map((d) => ChamberLeadershipRequest.fromJson(d.id, d.data()))
                  .toList();
              _myLeadershipRequestsCache[userId] = list;
              controller.add(list);
            },
            onError: controller.addError,
            onDone: controller.close,
          );
      controller.onCancel = sub.cancel;
    });
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
    final cached = _orgCache[orgId];
    if (cached != null) {
      final followers = List<String>.from(cached['followers'] as List? ?? []);
      if (!followers.contains(userId)) followers.add(userId);
      _orgCache[orgId] = {...cached, 'followers': followers};
    }
    await FirebaseFunctions.instance
        .httpsCallable('setOrganizationFollow')
        .call<void>({'organizationId': orgId, 'following': true});
    unawaited(getOrganization(orgId, force: true));
  }

  /// Add a user to organization chat participants (Admin only)
  Future<void> addChatMember(String orgId, String userId) async {
    final cached = _orgCache[orgId];
    String? chatId = cached?['chatId'] as String?;
    if (chatId == null) {
      final doc = await _firestore.collection('organizations').doc(orgId).get();
      if (!doc.exists) return;
      chatId = doc.data()?['chatId'] as String?;
    }
    if (chatId == null) return;

    await FirebaseFunctions.instance.httpsCallable('manageChatMembers').call({
      'chatId': chatId,
      'inviteUserId': userId,
    });
  }

  /// Remove a user from organization chat participants (Admin only)
  Future<void> removeChatMember(String orgId, String userId) async {
    final cached = _orgCache[orgId];
    String? chatId = cached?['chatId'] as String?;
    if (chatId == null) {
      final doc = await _firestore.collection('organizations').doc(orgId).get();
      if (!doc.exists) return;
      chatId = doc.data()?['chatId'] as String?;
    }
    if (chatId == null) return;

    await FirebaseFunctions.instance.httpsCallable('manageChatMembers').call({
      'chatId': chatId,
      'removeUserId': userId,
    });
  }

  /// Unfollow an organization
  Future<void> unfollowOrganization(String orgId, String userId) async {
    final cached = _orgCache[orgId];
    if (cached != null) {
      final followers = List<String>.from(cached['followers'] as List? ?? [])
        ..remove(userId);
      _orgCache[orgId] = {...cached, 'followers': followers};
    }
    await FirebaseFunctions.instance
        .httpsCallable('setOrganizationFollow')
        .call<void>({'organizationId': orgId, 'following': false});
    unawaited(getOrganization(orgId, force: true));
  }

  /// Enable specialized Product/Service listing for a business
  Future<void> enableProductListing(String orgId, String userId) async {
    final cached = _orgCache[orgId];
    if (cached != null) {
      _orgCache[orgId] = {
        ...cached,
        'isListingEnabled': true,
        'listingPaidBy': userId,
      };
    }
    await _firestore.collection('organizations').doc(orgId).update({
      'isListingEnabled': true,
      'listingPaidAt': FieldValue.serverTimestamp(),
      'listingPaidBy': userId,
    });

    // Refresh local cache in background
    unawaited(getOrganization(orgId, force: true));
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
