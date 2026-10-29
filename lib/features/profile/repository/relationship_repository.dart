import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart'; // [FIX] For debugPrint
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:diaspora_nearby/features/profile/models/relationship.dart';
import 'package:diaspora_nearby/features/profile/models/relationship_request.dart';
import 'package:diaspora_nearby/features/chat/repository/chat_repository.dart';
import 'package:diaspora_nearby/features/profile/repository/profile_repository.dart';
import 'package:diaspora_nearby/features/community/services/community_service.dart';
import 'package:diaspora_nearby/features/notifications/repository/notifications_repository.dart';

final relationshipRepositoryProvider = Provider<RelationshipRepository>((ref) {
  return RelationshipRepository(FirebaseFirestore.instance, ref);
});

final userRelationshipsProvider =
    StreamProvider.family<List<Relationship>, String>((ref, userId) {
      final repository = ref.watch(relationshipRepositoryProvider);
      return repository.getRelationships(userId);
    });

class RelationshipRepository {
  final FirebaseFirestore _firestore;
  final Ref _ref;

  RelationshipRepository(this._firestore, this._ref);

  static final Map<String, List<Relationship>> _relationshipsCache = {};
  static final Map<String, List<RelationshipRequest>> _incomingRequestsCache =
      {};
  static final Map<String, List<RelationshipRequest>> _sentRequestsCache = {};

  List<Relationship>? getCachedRelationships(String userId) =>
      _relationshipsCache[userId];

  Relationship? getCachedRelationship(String userId, String relatedUserId) {
    final list = _relationshipsCache[userId];
    if (list == null) return null;
    for (final rel in list) {
      if (rel.id == relatedUserId) return rel;
    }
    return null;
  }

  List<RelationshipRequest>? getCachedIncomingRequests(String userId) =>
      _incomingRequestsCache[userId];

  List<RelationshipRequest>? getCachedSentRequests(String userId) =>
      _sentRequestsCache[userId];

  RelationshipRequest? getCachedPendingSentRequest({
    required String fromUserId,
    required String toUserId,
  }) {
    final list = _sentRequestsCache[fromUserId];
    if (list == null) return null;
    for (final req in list) {
      if (req.toUserId == toUserId && req.status == 'pending') return req;
    }
    return null;
  }

  RelationshipRequest? getCachedPendingIncomingRequest({
    required String userId,
    required String fromUserId,
  }) {
    final list = _incomingRequestsCache[userId];
    if (list == null) return null;
    for (final req in list) {
      if (req.fromUserId == fromUserId && req.status == 'pending') return req;
    }
    return null;
  }

  String? get currentUserId => FirebaseAuth.instance.currentUser?.uid;

  /// [NEW] Announce Bereavement
  Future<void> announceBereavement(
    Relationship rel,
    Map<String, dynamic> details,
  ) async {
    final uid = currentUserId;
    if (uid == null) return;

    // Optimistically update local relationship cache to 'deceased'
    final cachedRels = _relationshipsCache[uid];
    if (cachedRels != null) {
      _relationshipsCache[uid] = cachedRels
          .map((r) => r.id == rel.id ? r.copyWith(status: 'deceased') : r)
          .toList();
    }

    // 1. Update Relationship Status & Fetch ALL my active relationships in parallel
    final results = await Future.wait([
      FirebaseFunctions.instance
          .httpsCallable('markRelationshipDeceased')
          .call<void>({'otherUserId': rel.id, 'details': details}),
      _relationshipsRef(
        uid,
      ).where('status', isEqualTo: 'active').limit(200).get(),
    ]);

    final allRelsSnapshot =
        results[1] as QuerySnapshot<Map<String, dynamic>>;

    final List<String> participants = [uid]; // Announcer is participant
    final List<String> admins = [uid]; // Announcer is admin

    for (final doc in allRelsSnapshot.docs) {
      final r = Relationship.fromMap(doc.data(), doc.id);
      participants.add(r.id);
      admins.add(r.id);
    }

    // Add the deceased ID to metadata logic if needed (they won't join chat obviously)

    final uniqueParticipants = participants.toSet().toList();
    final uniqueAdmins = admins.toSet().toList();

    // 3. Create Support Group & 4. Broadcast to Communities in parallel
    final chatRepo = _ref.read(chatRepositoryProvider);
    final groupName = 'Bereaving ${rel.name}';

    await Future.wait([
      chatRepo.createGroupChat(
        name: groupName,
        participants: uniqueParticipants,
        admins: uniqueAdmins,
        metadata: {
          'isBereavement': true,
          'deceasedId': rel.id,
          'deceasedName': rel.name,
          'announcerId': uid,
          'details': details,
        },
        type: 'group',
      ),
      () async {
        try {
          final profileRepo = _ref.read(profileRepositoryProvider);
          final profile =
              profileRepo.getCachedProfile(uid) ??
              await profileRepo.getUserProfile(uid);

          if (profile != null) {
            final communityService = _ref.read(communityServiceProvider);
            await communityService.broadcastBereavementAnnouncement(
              userId: uid,
              userName: profile.fullName,
              deceasedName: rel.name,
              relationship: rel.type,
              homeCountryCode: profile.homeCountryCode ?? '',
              hostCountryCode: profile.hostCountryCode,
              hostCity: profile.hostLocation.city,
            );
            debugPrint(
              '✅ [RelationshipRepository] Bereavement broadcast sent to communities',
            );
          }
        } catch (e) {
          debugPrint(
            '❌ [RelationshipRepository] Failed to broadcast bereavement: $e',
          );
        }
      }(),
    ]);
  }

  /// Helper to get the relationship collection reference for a user
  CollectionReference<Map<String, dynamic>> _relationshipsRef(String userId) {
    return _firestore
        .collection('users')
        .doc(userId)
        .collection('relationships');
  }

  /// Get all relationships for a user (Stream)
  Stream<List<Relationship>> getRelationships(String userId) {
    return Stream.multi((controller) {
      final cached = _relationshipsCache[userId];
      if (cached != null) {
        controller.add(cached);
      }
      final sub = _relationshipsRef(userId).limit(500).snapshots().listen(
        (snapshot) {
          final list = snapshot.docs
              .map((doc) => Relationship.fromMap(doc.data(), doc.id))
              .toList();
          _relationshipsCache[userId] = list;
          controller.add(list);
        },
        onError: controller.addError,
        onDone: controller.close,
      );
      controller.onCancel = sub.cancel;
    });
  }

  /// Get all relationships for a user (Future - One-time fetch)
  Future<List<Relationship>> getRelationshipsList(String userId) async {
    final snapshot = await _relationshipsRef(userId).limit(500).get();
    final list = snapshot.docs
        .map((doc) => Relationship.fromMap(doc.data(), doc.id))
        .toList();
    _relationshipsCache[userId] = list;
    return list;
  }

  /// Request a relationship using server-derived profile identity fields.
  Future<void> sendRelationshipRequest({
    required String fromUserId,
    required String fromUserName,
    required String fromUserFlag,
    String? fromUserPhoto,
    required String toUserId,
    required String toUserName,
    String? toUserPhoto,
    required String relationshipType,
  }) async {
    final optimisticReq = RelationshipRequest(
      id: 'temp_${fromUserId}_$toUserId',
      fromUserId: fromUserId,
      fromUserName: fromUserName,
      fromUserFlag: fromUserFlag,
      fromUserPhoto: fromUserPhoto,
      toUserId: toUserId,
      toUserName: toUserName,
      toUserPhoto: toUserPhoto,
      relationshipType: relationshipType,
      status: 'pending',
      timestamp: DateTime.now(),
    );
    final currentSent = List<RelationshipRequest>.from(
      _sentRequestsCache[fromUserId] ?? const [],
    );
    currentSent.removeWhere((r) => r.toUserId == toUserId);
    currentSent.insert(0, optimisticReq);
    _sentRequestsCache[fromUserId] = currentSent;

    await FirebaseFunctions.instance
        .httpsCallable('sendRelationshipRequest')
        .call<void>({
          'toUserId': toUserId,
          'relationshipType': relationshipType,
        });
  }

  // [NEW] Stream Incoming Requests
  Stream<List<RelationshipRequest>> getIncomingRequests(String userId) {
    return Stream.multi((controller) {
      final cached = _incomingRequestsCache[userId];
      if (cached != null) {
        controller.add(cached);
      }
      final sub = _firestore
          .collection('relationship_requests')
          .where('toUserId', isEqualTo: userId)
          .where('status', isEqualTo: 'pending')
          .limit(100)
          .snapshots()
          .listen(
            (snapshot) {
              final list = snapshot.docs
                  .map((doc) => RelationshipRequest.fromMap(doc.data(), doc.id))
                  .toList();
              _incomingRequestsCache[userId] = list;
              controller.add(list);
            },
            onError: controller.addError,
            onDone: controller.close,
          );
      controller.onCancel = sub.cancel;
    });
  }

  // [NEW] Stream Sent Requests
  Stream<List<RelationshipRequest>> getSentRequests(String userId) {
    return Stream.multi((controller) {
      final cached = _sentRequestsCache[userId];
      if (cached != null) {
        controller.add(cached);
      }
      final sub = _firestore
          .collection('relationship_requests')
          .where('fromUserId', isEqualTo: userId)
          .where('status', isEqualTo: 'pending')
          .limit(100)
          .snapshots()
          .listen(
            (snapshot) {
              final list = snapshot.docs
                  .map((doc) => RelationshipRequest.fromMap(doc.data(), doc.id))
                  .toList();
              _sentRequestsCache[userId] = list;
              controller.add(list);
            },
            onError: controller.addError,
            onDone: controller.close,
          );
      controller.onCancel = sub.cancel;
    });
  }

  /// Cancel an authenticated user's pending outgoing request.
  Future<void> cancelSentRequest(RelationshipRequest request) async {
    final list = _sentRequestsCache[request.fromUserId];
    if (list != null) {
      _sentRequestsCache[request.fromUserId] = list
          .where((r) => r.id != request.id && r.toUserId != request.toUserId)
          .toList();
    }
    await FirebaseFunctions.instance
        .httpsCallable('cancelRelationshipRequest')
        .call<void>({'requestId': request.id});
  }

  // [NEW] Check for Pending Sent Request (for UI updates)
  Future<RelationshipRequest?> getPendingSentRequest({
    required String fromUserId,
    required String toUserId,
  }) async {
    final cached = getCachedPendingSentRequest(
      fromUserId: fromUserId,
      toUserId: toUserId,
    );
    if (cached != null) return cached;

    final snapshot = await _firestore
        .collection('relationship_requests')
        .where('fromUserId', isEqualTo: fromUserId)
        .where('toUserId', isEqualTo: toUserId)
        .where('status', isEqualTo: 'pending')
        .limit(1)
        .get();

    if (snapshot.docs.isNotEmpty) {
      final doc = snapshot.docs.first;
      return RelationshipRequest.fromMap(doc.data(), doc.id);
    }
    return null;
  }

  // [NEW] Check for Pending Incoming Request
  Future<RelationshipRequest?> getPendingIncomingRequest({
    required String userId, // Me
    required String fromUserId, // Other
  }) async {
    final cached = getCachedPendingIncomingRequest(
      userId: userId,
      fromUserId: fromUserId,
    );
    if (cached != null) return cached;

    final snapshot = await _firestore
        .collection('relationship_requests')
        .where('toUserId', isEqualTo: userId)
        .where('fromUserId', isEqualTo: fromUserId)
        .where('status', isEqualTo: 'pending')
        .limit(1)
        .get();

    if (snapshot.docs.isNotEmpty) {
      final doc = snapshot.docs.first;
      return RelationshipRequest.fromMap(doc.data(), doc.id);
    }
    return null;
  }

  /// Accept atomically: both relationship projections and the direct chat are
  /// written by the server in one idempotent transaction.
  Future<void> acceptRequest(
    RelationshipRequest request,
    String accepterFlag,
    String selectedReciprocalType,
  ) async {
    // Optimistically remove from incoming requests and add to relationships cache
    final inc = _incomingRequestsCache[request.toUserId];
    if (inc != null) {
      _incomingRequestsCache[request.toUserId] = inc
          .where((r) => r.id != request.id)
          .toList();
    }
    final rels = List<Relationship>.from(
      _relationshipsCache[request.toUserId] ?? const [],
    );
    rels.removeWhere((r) => r.id == request.fromUserId);
    rels.add(
      Relationship(
        id: request.fromUserId,
        name: request.fromUserName,
        type: request.relationshipType,
        flag: request.fromUserFlag,
        photoUrl: request.fromUserPhoto,
        status: 'active',
        createdAt: DateTime.now(),
      ),
    );
    _relationshipsCache[request.toUserId] = rels;

    unawaited(
      _ref
          .read(notificationsRepositoryProvider)
          .markActionCompletedByDedupKey(
            request.toUserId,
            'relationship_${request.id}',
          )
          .catchError((Object e) {
            debugPrint('Failed to mark notification completed: $e');
          }),
    );

    await FirebaseFunctions.instance
        .httpsCallable('respondRelationshipRequest')
        .call<void>({
          'requestId': request.id,
          'decision': 'accepted',
          'reciprocalType': selectedReciprocalType,
        });
  }

  /// Reject without client-authored rewards or reputation penalties.
  Future<void> rejectRequest(RelationshipRequest request) async {
    final inc = _incomingRequestsCache[request.toUserId];
    if (inc != null) {
      _incomingRequestsCache[request.toUserId] = inc
          .where((r) => r.id != request.id)
          .toList();
    }

    unawaited(
      _ref
          .read(notificationsRepositoryProvider)
          .markActionCompletedByDedupKey(
            request.toUserId,
            'relationship_${request.id}',
          )
          .catchError((Object e) {
            debugPrint('Failed to mark notification completed: $e');
          }),
    );

    await FirebaseFunctions.instance
        .httpsCallable('respondRelationshipRequest')
        .call<void>({'requestId': request.id, 'decision': 'rejected'});
  }

  // Helper: Get Reciprocal Type
  // Simple English logic. Ideally this should be more robust or user-selected.
  // Helper: Get Possible Reciprocal Types
  // Returns a list of logical inverse relationships for the receiver to choose from.
  List<String> getPossibleReciprocalTypes(String type) {
    final lower = type.toLowerCase();
    switch (lower) {
      case 'father':
      case 'mother':
        return ['Son', 'Daughter'];
      case 'husband':
        return ['Wife'];
      case 'wife':
        return ['Husband'];
      case 'brother':
      case 'sister':
        return ['Brother', 'Sister'];
      case 'son':
      case 'daughter':
        return ['Father', 'Mother'];
      case 'uncle':
      case 'aunt':
        return ['Nephew', 'Niece'];
      case 'nephew':
      case 'niece':
        return ['Uncle', 'Aunt'];
      case 'cousin':
        return ['Cousin'];
      case 'friend':
        return ['Friend'];
      case 'business partner':
        return ['Business Partner'];
      case 'community member':
        return ['Community Member'];
      default:
        return ['Relative'];
    }
  }

  /// Delete a relationship
  Future<void> deleteRelationship({
    required String userId,
    required String relatedUserId,
  }) async {
    final cached = _relationshipsCache[userId];
    if (cached != null) {
      _relationshipsCache[userId] = cached
          .where((r) => r.id != relatedUserId)
          .toList();
    }
    await FirebaseFunctions.instance
        .httpsCallable('removeRelationship')
        .call<void>({'otherUserId': relatedUserId});
  }

  /// Get specific relationship details if exists
  Future<Relationship?> getRelationship({
    required String userId,
    required String relatedUserId,
  }) async {
    final cached = getCachedRelationship(userId, relatedUserId);
    if (cached != null) return cached;

    final doc = await _relationshipsRef(userId).doc(relatedUserId).get();
    if (doc.exists) {
      return Relationship.fromMap(doc.data()!, doc.id);
    }
    return null;
  }

  /// Block a user
  Future<void> blockUser({
    required String userId,
    required String relatedUserId,
  }) async {
    // Optimistically update profile blockedUsers list immediately
    final profileRepo = _ref.read(profileRepositoryProvider);
    final currentProfile = profileRepo.getCachedProfile(userId);
    if (currentProfile != null) {
      final updatedBlocked = <String>{
        ...(currentProfile.blockedUsers ?? const []),
        relatedUserId,
      }.toList();
      final updatedProfile = currentProfile.copyWith(
        blockedUsers: updatedBlocked,
      );
      profileRepo.cacheProfile(userId, updatedProfile);
      _ref.read(userProfileProvider.notifier).updateProfile(updatedProfile);
    }
    await FirebaseFunctions.instance.httpsCallable('setUserBlocked').call<void>(
      {'otherUserId': relatedUserId, 'blocked': true},
    );
    _ref.invalidate(userProfileProvider);
  }

  /// Unblock a user
  Future<void> unblockUser({
    required String userId,
    required String relatedUserId,
  }) async {
    // Optimistically update profile blockedUsers list immediately
    final profileRepo = _ref.read(profileRepositoryProvider);
    final currentProfile = profileRepo.getCachedProfile(userId);
    if (currentProfile != null) {
      final updatedBlocked = List<String>.from(
        currentProfile.blockedUsers ?? const [],
      )..remove(relatedUserId);
      final updatedProfile = currentProfile.copyWith(
        blockedUsers: updatedBlocked,
      );
      profileRepo.cacheProfile(userId, updatedProfile);
      _ref.read(userProfileProvider.notifier).updateProfile(updatedProfile);
    }
    await FirebaseFunctions.instance.httpsCallable('setUserBlocked').call<void>(
      {'otherUserId': relatedUserId, 'blocked': false},
    );
    _ref.invalidate(userProfileProvider);
  }
}
