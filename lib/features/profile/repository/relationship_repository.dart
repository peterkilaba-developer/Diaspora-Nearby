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
        debugPrint('✅ [RelationshipRepository] Bereavement broadcast sent to communities');
      }
    } catch (e) {
      debugPrint('❌ [RelationshipRepository] Failed to broadcast bereavement: $e');
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
    required String toUserId,
    required String toUserName,
    required String relationshipType,
  }) async {
    try {
      debugPrint(
        '🔔 [RelationshipRepository] Sending request from $fromUserId to $toUserId ($relationshipType)',
      );
      final docRef = _firestore.collection('relationship_requests').doc();
      final request = RelationshipRequest(
        id: docRef.id,
        fromUserId: fromUserId,
        fromUserName: fromUserName,
        fromUserFlag: fromUserFlag,
        toUserId: toUserId,
        toUserName: toUserName,
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
        final request = RelationshipRequest.fromMap(doc.data());
        // Check if I already have this relationship
        final existing = await getRelationship(
          userId: userId,
          relatedUserId: request.toUserId,
        );
        if (existing == null) {
          debugPrint(
            '🔄 [RelationshipRepository] Syncing accepted request for ${request.toUserName}',
          );
          // Auto-add relationship (Sender -> Receiver)
          // We need to fetch the receiver's flag/details if strictly needed,
          // but the request object has user names.
          // Problem: Request object has 'toUserName' but not 'toUserFlag' explicitly stored in standard model?
          // Let's check RelationshipRequest model.
          // It has 'toUserName'. 'toUserFlag' was not in constructor in line 133 but might be missing?
          // If missing, we might need to fetch profile or accept it without flag temporarily.
          // Or we update RelationshipRequest to include toUserFlag.
          // For now, let's assume we can fetch profile or use a placeholder.
          
          // Actually, let's check line 133.
          // It saves 'fromUserFlag'. Does it save 'toUserFlag'?
          // Line 133: fromUserFlag is there. toUserFlag is NOT param of sendRelationshipRequest.
          // So we might need to fetch it.
          
          // Fetch profile for flag
           try {
              // We can't access ProfileRepository easily here without ref circular?
              // We can just query firestore 'users' collection directly since we have firestore instance.
              final userDoc = await _firestore.collection('users').doc(request.toUserId).get();
              final flag = userDoc.data()?['countryFlag'] ?? '🏳️'; // Fallback

              await addRelationship(
                userId: userId,
                relatedUserId: request.toUserId,
                type: request.relationshipType,
                name: request.toUserName,
                flag: flag,
              );
              debugPrint('✅ [RelationshipRepository] Synced relationship with ${request.toUserName}');
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
    debugPrint('ℹ️ [RelationshipRepository] Skipping direct write to sender to avoid permission errors. Sender will sync automatically.');

    // 4. [NEW] Track Rewards (Sender +10, Receiver +10)
    try {
      await _ref
          .read(pointsServiceProvider)
          .trackRelationshipReward(
            senderId: request.fromUserId,
            receiverId: request.toUserId,
            status: 'accepted',
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

    // 2. [NEW] Increment the 'blockedByCount' of the user being blocked and check for automatic penalty
    try {
      final targetUserRef = _firestore.collection('users').doc(relatedUserId);
      
      bool shouldPenalize = false;
      await _firestore.runTransaction((transaction) async {
        final snapshot = await transaction.get(targetUserRef);
        if (snapshot.exists) {
          final data = snapshot.data()!;
          final currentCount = (data['blockedByCount'] as num?)?.toInt() ?? 0;
          final newCount = currentCount + 1;
          transaction.update(targetUserRef, {'blockedByCount': newCount});
          if (newCount == 5) {
            shouldPenalize = true;
          }
        }
      });

      if (shouldPenalize) {
        debugPrint('🚨 [RelationshipRepository] User $relatedUserId reached block threshold (5). Triggering automatic Fraud Penalty.');
        // recordFraudPenalty is proportional (10% or min 5,000 DSP)
        await _ref.read(pointsServiceProvider).recordFraudPenalty(relatedUserId);
      }
    } catch (e) {
      debugPrint('❌ [RelationshipRepository] Error updating blockedByCount: $e');
    }

    // 3. Remove any existing relationship status (optional but cleaner)
    await deleteRelationship(userId: userId, relatedUserId: relatedUserId);
    
    // 4. Refresh local profile to update blocked list UI
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
