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

  String? get currentUserId => FirebaseAuth.instance.currentUser?.uid;

  /// [NEW] Announce Bereavement
  Future<void> announceBereavement(
    Relationship rel,
    Map<String, dynamic> details,
  ) async {
    final uid = currentUserId;
    if (uid == null) return;

    // 1. Update Relationship Status to 'deceased' (locally for me)
    await FirebaseFunctions.instance
        .httpsCallable('markRelationshipDeceased')
        .call<void>({'otherUserId': rel.id, 'details': details});

    // 2. Fetch ALL my active relationships (Immediate/Close Family) to add to support group
    final allRelsSnapshot = await _relationshipsRef(
      uid,
    ).where('status', isEqualTo: 'active').limit(200).get();

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

    // 3. Create Support Group
    final chatRepo = _ref.read(chatRepositoryProvider);
    final groupName = 'Bereaving ${rel.name}';

    await chatRepo.createGroupChat(
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
    );

    // 4. [NEW] Broadcast to Communities (Home Country & Host City)
    try {
      final profileRepo = _ref.read(profileRepositoryProvider);
      final profile = await profileRepo.getUserProfile(uid);

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
    return _relationshipsRef(userId).limit(500).snapshots().map((snapshot) {
      return snapshot.docs
          .map((doc) => Relationship.fromMap(doc.data(), doc.id))
          .toList();
    });
  }

  /// Get all relationships for a user (Future - One-time fetch)
  Future<List<Relationship>> getRelationshipsList(String userId) async {
    final snapshot = await _relationshipsRef(userId).limit(500).get();
    return snapshot.docs
        .map((doc) => Relationship.fromMap(doc.data(), doc.id))
        .toList();
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
    await FirebaseFunctions.instance
        .httpsCallable('sendRelationshipRequest')
        .call<void>({
          'toUserId': toUserId,
          'relationshipType': relationshipType,
        });
  }

  // [NEW] Stream Incoming Requests
  Stream<List<RelationshipRequest>> getIncomingRequests(String userId) {
    return _firestore
        .collection('relationship_requests')
        .where('toUserId', isEqualTo: userId)
        .where('status', isEqualTo: 'pending')
        .limit(100)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => RelationshipRequest.fromMap(doc.data()))
              .toList(),
        );
  }

  // [NEW] Stream Sent Requests
  Stream<List<RelationshipRequest>> getSentRequests(String userId) {
    return _firestore
        .collection('relationship_requests')
        .where('fromUserId', isEqualTo: userId)
        .where('status', isEqualTo: 'pending')
        .limit(100)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => RelationshipRequest.fromMap(doc.data()))
              .toList(),
        );
  }

  /// Cancel an authenticated user's pending outgoing request.
  Future<void> cancelSentRequest(RelationshipRequest request) async {
    await FirebaseFunctions.instance
        .httpsCallable('cancelRelationshipRequest')
        .call<void>({'requestId': request.id});
  }

  // [NEW] Check for Pending Sent Request (for UI updates)
  Future<RelationshipRequest?> getPendingSentRequest({
    required String fromUserId,
    required String toUserId,
  }) async {
    final snapshot = await _firestore
        .collection('relationship_requests')
        .where('fromUserId', isEqualTo: fromUserId)
        .where('toUserId', isEqualTo: toUserId)
        .where('status', isEqualTo: 'pending')
        .limit(1)
        .get();

    if (snapshot.docs.isNotEmpty) {
      return RelationshipRequest.fromMap(snapshot.docs.first.data());
    }
    return null;
  }

  // [NEW] Check for Pending Incoming Request
  Future<RelationshipRequest?> getPendingIncomingRequest({
    required String userId, // Me
    required String fromUserId, // Other
  }) async {
    final snapshot = await _firestore
        .collection('relationship_requests')
        .where('toUserId', isEqualTo: userId)
        .where('fromUserId', isEqualTo: fromUserId)
        .where('status', isEqualTo: 'pending')
        .limit(1)
        .get();

    if (snapshot.docs.isNotEmpty) {
      return RelationshipRequest.fromMap(snapshot.docs.first.data());
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
    await FirebaseFunctions.instance
        .httpsCallable('respondRelationshipRequest')
        .call<void>({
          'requestId': request.id,
          'decision': 'accepted',
          'reciprocalType': selectedReciprocalType,
        });

    // 7. Mark the receiver's relationship request notification as completed
    try {
      await _ref
          .read(notificationsRepositoryProvider)
          .markActionCompletedByDedupKey(
            request.toUserId,
            'relationship_${request.id}',
          );
    } catch (e) {
      debugPrint('Failed to mark notification completed: $e');
    }
  }

  /// Reject without client-authored rewards or reputation penalties.
  Future<void> rejectRequest(RelationshipRequest request) async {
    await FirebaseFunctions.instance
        .httpsCallable('respondRelationshipRequest')
        .call<void>({'requestId': request.id, 'decision': 'rejected'});

    // 3. Mark the receiver's relationship request notification as completed
    try {
      await _ref
          .read(notificationsRepositoryProvider)
          .markActionCompletedByDedupKey(
            request.toUserId,
            'relationship_${request.id}',
          );
    } catch (e) {
      debugPrint('Failed to mark notification completed: $e');
    }
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
    await FirebaseFunctions.instance
        .httpsCallable('removeRelationship')
        .call<void>({'otherUserId': relatedUserId});
  }

  /// Get specific relationship details if exists
  Future<Relationship?> getRelationship({
    required String userId,
    required String relatedUserId,
  }) async {
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
    await FirebaseFunctions.instance.httpsCallable('setUserBlocked').call<void>(
      {'otherUserId': relatedUserId, 'blocked': false},
    );
    _ref.invalidate(userProfileProvider);
  }
}
