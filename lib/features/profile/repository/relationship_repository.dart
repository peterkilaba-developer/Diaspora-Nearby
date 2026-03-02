import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart'; // [FIX] For debugPrint
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:diaspora_nearby/features/profile/models/relationship.dart';
import 'package:diaspora_nearby/features/profile/models/relationship_request.dart';
import 'package:diaspora_nearby/features/dsp/services/points_service.dart';
import 'package:diaspora_nearby/features/chat/repository/chat_repository.dart';
import 'package:diaspora_nearby/features/profile/repository/profile_repository.dart';
import 'package:diaspora_nearby/features/community/services/community_service.dart';
import 'package:diaspora_nearby/features/trust/services/trust_service.dart';
import 'package:diaspora_nearby/router.dart';

final relationshipRepositoryProvider = Provider<RelationshipRepository>((ref) {
  final repo = RelationshipRepository(FirebaseFirestore.instance, ref);
  // Initialize sync for the current user
  final user = FirebaseAuth.instance.currentUser;
  if (user != null) {
    repo.syncAcceptedSentRequests(user.uid);
  }
  return repo;
});

final userRelationshipsProvider =
    StreamProvider.family<List<Relationship>, String>((ref, userId) {
      final repository = ref.watch(relationshipRepositoryProvider);
      return repository.getRelationships(userId);
    });

/// The 13 family relationship types that trigger a Family Group Chat.
const Set<String> kFamilyRelationshipTypes = {
  'wife',
  'husband',
  'daughter',
  'son',
  'mother',
  'father',
  'sister',
  'brother',
  'aunt',
  'uncle',
  'nephew',
  'niece',
  'cousin',
};

bool _isFamilyType(String type) =>
    kFamilyRelationshipTypes.contains(type.toLowerCase());

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
    await _relationshipsRef(
      uid,
    ).doc(rel.id).update({'status': 'deceased', 'bereavementDetails': details});

    // 2. Fetch ALL my active relationships (Immediate/Close Family) to add to support group
    final allRelsSnapshot = await _relationshipsRef(
      uid,
    ).where('status', isEqualTo: 'active').get();

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
    return _relationshipsRef(userId).snapshots().map((snapshot) {
      return snapshot.docs
          .map((doc) => Relationship.fromMap(doc.data(), doc.id))
          .toList();
    });
  }

  /// Get all relationships for a user (Future - One-time fetch)
  Future<List<Relationship>> getRelationshipsList(String userId) async {
    final snapshot = await _relationshipsRef(userId).get();
    return snapshot.docs
        .map((doc) => Relationship.fromMap(doc.data(), doc.id))
        .toList();
  }

  /// Add a new relationship
  Future<void> addRelationship({
    required String userId,
    required String relatedUserId,
    required String type,
    required String name,
    String status = 'active',
    String? flag, // [NEW]
  }) async {
    final relationship = Relationship(
      id: relatedUserId,
      type: type,
      name: name,
      createdAt: DateTime.now(),
      status: status,
      flag: flag,
    );

    await _relationshipsRef(
      userId,
    ).doc(relatedUserId).set(relationship.toMap());
  }

  // [NEW] Send Relationship Request
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
    try {
      // [UPDATED] No fee charged on send. Fee is charged on acceptance.
      debugPrint(
        '🔔 [RelationshipRepository] Sending request from $fromUserId to $toUserId ($relationshipType)',
      );
      final docRef = _firestore.collection('relationship_requests').doc();
      final request = RelationshipRequest(
        id: docRef.id,
        fromUserId: fromUserId,
        fromUserName: fromUserName,
        fromUserFlag: fromUserFlag,
        fromUserPhoto: fromUserPhoto,
        toUserId: toUserId,
        toUserName: toUserName,
        toUserPhoto: toUserPhoto,
        relationshipType: relationshipType,
        timestamp: DateTime.now(),
        status: 'pending',
      );
      await docRef.set(request.toMap());
      debugPrint(
        '✅ [RelationshipRepository] Request sent successfully! ID: ${docRef.id}',
      );
    } catch (e) {
      debugPrint('❌ [RelationshipRepository] Error sending request: $e');
      rethrow;
    }
  }

  // [NEW] Stream Incoming Requests
  Stream<List<RelationshipRequest>> getIncomingRequests(String userId) {
    return _firestore
        .collection('relationship_requests')
        .where('toUserId', isEqualTo: userId)
        .where('status', isEqualTo: 'pending')
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
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => RelationshipRequest.fromMap(doc.data()))
              .toList(),
        );
  }

  // [NEW] Cancel a Sent Request
  Future<void> cancelSentRequest(RelationshipRequest request) async {
    // Just delete the request document — no fee was charged on send
    await _firestore
        .collection('relationship_requests')
        .doc(request.id)
        .delete();

    debugPrint(
      '✅ [RelationshipRepository] Cancelled sent request to ${request.toUserName}',
    );
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

  // [NEW] Sync Accepted Requests (Sender Side Self-Repair)
  // Listens for requests sent by me that are now 'accepted' but likely missing from my relationships
  void syncAcceptedSentRequests(String userId) {
    _firestore
        .collection('relationship_requests')
        .where('fromUserId', isEqualTo: userId)
        .where('status', isEqualTo: 'accepted')
        .snapshots()
        .listen((snapshot) async {
          for (final doc in snapshot.docs) {
            final docData = doc.data();
            final request = RelationshipRequest.fromMap(docData);
            // Check if I already have this relationship
            final existing = await getRelationship(
              userId: userId,
              relatedUserId: request.toUserId,
            );
            if (existing == null) {
              debugPrint(
                '🔄 [RelationshipRepository] Syncing accepted request for ${request.toUserName}',
              );

              // Fetch profile for flag
              try {
                final userDoc = await _firestore
                    .collection('users')
                    .doc(request.toUserId)
                    .get();
                final flag =
                    userDoc.data()?['countryFlag'] ?? '🏳️'; // Fallback

                await addRelationship(
                  userId: userId,
                  relatedUserId: request.toUserId,
                  type: request.relationshipType,
                  name: request.toUserName,
                  flag: flag,
                );
                debugPrint(
                  '✅ [RelationshipRepository] Synced relationship with ${request.toUserName}',
                );

                // [NEW] Also join Family Group Chat if applicable (sender side sync)
                if (_isFamilyType(request.relationshipType)) {
                  try {
                    final chatRepo = _ref.read(chatRepositoryProvider);
                    await chatRepo.createOrJoinFamilyGroupChat(
                      userId1: userId, // Sender (me)
                      userId2: request.toUserId, // Receiver
                    );
                    debugPrint(
                      '✅ [RelationshipRepository] Sender joined Family Group Chat after sync',
                    );
                  } catch (e) {
                    debugPrint(
                      '❌ [RelationshipRepository] Sender family group chat join failed: $e',
                    );
                  }
                }

                // [NEW] Navigate sender to the auto-created DM chat
                final chatId = docData['chatId'] as String?;
                if (chatId != null) {
                  debugPrint(
                    '🔔 [RelationshipRepository] Navigating sender to DM chat: $chatId',
                  );
                  try {
                    _ref.read(routerProvider).push('/chats/$chatId');
                  } catch (e) {
                    debugPrint(
                      '⚠️ [RelationshipRepository] Could not navigate to chat: $e',
                    );
                  }
                }
              } catch (e) {
                debugPrint('❌ [RelationshipRepository] Sync failed: $e');
              }
            }
          }
        });
  }

  // [NEW] Accept Request
  Future<void> acceptRequest(
    RelationshipRequest request,
    String accepterFlag,
    String selectedReciprocalType,
  ) async {
    // 1. Update Request Status
    await _firestore.collection('relationship_requests').doc(request.id).update(
      {'status': 'accepted'},
    );

    // 2. Add Relationship for Receiver (User who accepted) -> Add Sender (fromUser)
    await addRelationship(
      userId: request.toUserId,
      relatedUserId: request.fromUserId,
      type: selectedReciprocalType, // Use user-selected reciprocal type
      name: request.fromUserName,
      flag: request.fromUserFlag, // Sender's flag
    );

    // 3. [UPDATED] Do NOT write to Sender's path directly to avoid Permission Denied.
    // The Sender (fromUser) will be updated via 'syncAcceptedSentRequests' listener on their client.
    debugPrint(
      'ℹ️ [RelationshipRepository] Skipping direct write to sender to avoid permission errors. Sender will sync automatically.',
    );

    // 4. [NEW] If a family relationship type, create/join the Family Group Chat
    if (_isFamilyType(request.relationshipType) ||
        _isFamilyType(selectedReciprocalType)) {
      try {
        final chatRepo = _ref.read(chatRepositoryProvider);
        await chatRepo.createOrJoinFamilyGroupChat(
          userId1: request.toUserId, // Receiver (accepter)
          userId2: request.fromUserId, // Sender
        );
        debugPrint(
          '✅ [RelationshipRepository] Family Group Chat created/joined after accepting ${request.relationshipType}',
        );
      } catch (e) {
        debugPrint(
          '❌ [RelationshipRepository] Failed to create Family Group Chat: $e',
        );
      }
    }

    // 4b. [NEW] Auto-create a DM chat between the two users on acceptance
    try {
      final chatRepo = _ref.read(chatRepositoryProvider);
      final chat = await chatRepo.createDirectChat(request.fromUserId);
      if (chat != null) {
        // Store chatId on the request doc so the sender's sync listener can navigate to it
        await _firestore
            .collection('relationship_requests')
            .doc(request.id)
            .update({'chatId': chat.id});
        debugPrint(
          '✅ [RelationshipRepository] DM Chat auto-created: ${chat.id}',
        );
      }
    } catch (e) {
      debugPrint(
        '❌ [RelationshipRepository] Failed to auto-create DM chat: $e',
      );
    }

    // 5. [SIMPLIFIED] Connection fee removed — all connections are now free.
    // Both users receive a 1000 DSP reward via trackRelationshipReward below.

    // 6. [SIMPLIFIED] Track Rewards (Sender +1000, Receiver +1000)
    try {
      await _ref
          .read(pointsServiceProvider)
          .trackRelationshipReward(
            senderId: request.fromUserId,
            receiverId: request.toUserId,
            status: 'accepted',
            relationshipType: request.relationshipType,
          );
    } catch (e) {
      debugPrint('Failed to track accept rewards: $e');
    }
  }

  // [NEW] Reject Request (with Penalty Trigger)
  Future<void> rejectRequest(RelationshipRequest request) async {
    // 1. Update Status
    await _firestore.collection('relationship_requests').doc(request.id).update(
      {'status': 'rejected'},
    );

    // 2. [NEW] Apply Rewards/Penalty (Receiver +10, Sender -10)
    try {
      await _ref
          .read(pointsServiceProvider)
          .trackRelationshipReward(
            senderId: request.fromUserId,
            receiverId: request
                .toUserId, // Receiver is the one rejecting (current user usually)
            status: 'rejected',
          );

      // HTS Signal: Rejected Connection
      await _ref
          .read(trustServiceProvider)
          .recordActivity(request.fromUserId, HTSActivityType.rejectedVouch);
    } catch (e) {
      debugPrint('Error applying rejection penalty/reward: $e');
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
    await _relationshipsRef(userId).doc(relatedUserId).delete();
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
    // 1. Add to blockedUsers array in User Profile
    await _firestore.collection('users').doc(userId).update({
      'blockedUsers': FieldValue.arrayUnion([relatedUserId]),
    });

    // 2. Use TrustService for automated HTS tracking and penalty
    try {
      await _ref
          .read(trustServiceProvider)
          .recordActivity(relatedUserId, HTSActivityType.blockedBy);
    } catch (e) {
      debugPrint(
        '❌ [RelationshipRepository] Error recording blockedBy HTS: $e',
      );
    }

    // 3. Milestone penalty: every 10 unique blockers → deduct 100 DSP + 1 PoCT
    try {
      final blockersSnapshot = await _firestore
          .collection('users')
          .where('blockedUsers', arrayContains: relatedUserId)
          .count()
          .get();
      final uniqueBlockers = blockersSnapshot.count ?? 0;

      if (uniqueBlockers > 0 && uniqueBlockers % 10 == 0) {
        final pointsService = _ref.read(pointsServiceProvider);
        await pointsService.deductPoints(
          userId: relatedUserId,
          amount: 100,
          reason: 'blocked_by_milestone_${uniqueBlockers ~/ 10}',
        );
        await pointsService.deductPoints(
          userId: relatedUserId,
          amount: 1,
          reason: 'poct_blocked_by_milestone_${uniqueBlockers ~/ 10}',
        );
        debugPrint(
          '🚨 Block milestone: $uniqueBlockers unique blockers — 100 DSP + 1 PoCT deducted from $relatedUserId',
        );
      }
    } catch (e) {
      debugPrint('Error checking block milestone: $e');
    }

    // 4. Remove any existing relationship status (optional but cleaner)
    await deleteRelationship(userId: userId, relatedUserId: relatedUserId);

    // 5. Refresh local profile to update blocked list UI
    _ref.invalidate(userProfileProvider);
  }

  /// Unblock a user
  Future<void> unblockUser({
    required String userId,
    required String relatedUserId,
  }) async {
    await _firestore.collection('users').doc(userId).update({
      'blockedUsers': FieldValue.arrayRemove([relatedUserId]),
    });

    // [NEW] Decrement the 'blockedByCount' of the user being unblocked
    await _firestore.collection('users').doc(relatedUserId).update({
      'blockedByCount': FieldValue.increment(-1),
    });

    // Refresh local profile
    _ref.invalidate(userProfileProvider);
  }
}
