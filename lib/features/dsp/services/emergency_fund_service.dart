import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:diaspora_nearby/features/dsp/models/emergency_fund_model.dart';
import 'package:diaspora_nearby/features/profile/models/profile_data.dart';
import 'package:diaspora_nearby/features/profile/models/relationship.dart';
import 'package:diaspora_nearby/features/profile/repository/profile_repository.dart';
import 'package:diaspora_nearby/features/dsp/repository/points_repository.dart';
import 'package:diaspora_nearby/features/trust/repository/trust_repository.dart';
import 'package:diaspora_nearby/features/chat/repository/chat_repository.dart';
import 'package:uuid/uuid.dart';

final emergencyFundServiceProvider = Provider<EmergencyFundService>((ref) {
  return EmergencyFundService(
    FirebaseFirestore.instance,
    ref.read(profileRepositoryProvider),
    ref.read(pointsRepositoryProvider),
    ref.read(trustRepositoryProvider),
    ref.read(chatRepositoryProvider),
  );
});

class EligibilityResult {
  final bool isProfileComplete;
  final bool hasEnoughPoints;
  final bool hasEnoughFamily;
  final bool hasEnoughFriends;
  final int familyCount;
  final int friendCount;

  bool get isEligible =>
      isProfileComplete &&
      hasEnoughPoints &&
      hasEnoughFamily &&
      hasEnoughFriends;

  EligibilityResult({
    required this.isProfileComplete,
    required this.hasEnoughPoints,
    required this.hasEnoughFamily,
    required this.hasEnoughFriends,
    required this.familyCount,
    required this.friendCount,
  });
}

class EmergencyFundService {
  final FirebaseFirestore _firestore;
  final ProfileRepository _profileRepo;
  final PointsRepository _pointsRepo;
  final TrustRepository _trustRepo;
  final ChatRepository _chatRepo;
  final _uuid = const Uuid();

  static const Set<String> _familyTypes = {
    'wife', 'husband', 'daughter', 'son', 'mother', 'father',
    'sister', 'brother', 'aunt', 'uncle', 'nephew', 'niece', 'cousin',
  };

  EmergencyFundService(
    this._firestore,
    this._profileRepo,
    this._pointsRepo,
    this._trustRepo,
    this._chatRepo,
  );

  // --- Eligibility ---

  Future<EligibilityResult> checkEligibility(String userId) async {
    // 1. Profile Check
    final profile = await _profileRepo.getUserProfile(userId);
    final isProfileComplete = profile?.isComplete ?? false;

    // 2. Points Check (>= 10,000 DSP — 10k Genesis Gate)
    final points = await _pointsRepo.getUserPoints(userId);
    final hasEnoughPoints = (points?.totalPoints ?? 0) >= 10000;

    // 3. Relationships Check (10 Family, 10 Friends)
    final relationshipsSnap = await _firestore
        .collection('users')
        .doc(userId)
        .collection('relationships')
        .where('status', isEqualTo: 'active')
        .get();

    int familyCount = 0;
    int friendCount = 0;

    for (var doc in relationshipsSnap.docs) {
      final type = doc.data()['type'] as String? ?? '';
      if (_familyTypes.contains(type.toLowerCase())) {
        familyCount++;
      } else if (type.toLowerCase() == 'friend') {
        friendCount++;
      }
    }

    final hasEnoughFamily = familyCount >= 10;
    final hasEnoughFriends = friendCount >= 10;

    return EligibilityResult(
      isProfileComplete: isProfileComplete,
      hasEnoughPoints: hasEnoughPoints,
      hasEnoughFamily: hasEnoughFamily,
      hasEnoughFriends: hasEnoughFriends,
      familyCount: familyCount,
      friendCount: friendCount,
    );
  }

  // --- Membership ---

  Stream<EmergencyFundMembership?> streamMembership(String userId) {
    return _firestore
        .collection('emergency_fund_memberships')
        .doc(userId)
        .snapshots()
        .map((doc) {
          if (doc.exists && doc.data() != null) {
            return EmergencyFundMembership.fromMap(doc.data()!);
          }
          return null;
        });
  }

  // Helper to fetch relationships to auto-populate
  Future<List<Relationship>> getQualifiedRelatives(String userId) async {
    try {
      final snap = await _firestore
          .collection('users')
          .doc(userId)
          .collection('relationships')
          .where('status', isEqualTo: 'active')
          .get();

      return snap.docs
          .map((doc) => Relationship.fromMap(doc.data(), doc.id))
          .where((r) => _familyTypes.contains(r.type.toLowerCase()))
          .toList();
    } catch (e) {
      return [];
    }
  }

  // Helper to fetch potential proxies from active DM chats (Verified Users Only)
  Future<List<ProfileData>> getPotentialProxies(String userId) async {
    try {
      final chats = await _chatRepo.getUserChats();
      final directChats = chats.where((c) => c.isDirect).toList();

      final potentialIds = directChats
          .map((c) => c.getOtherParticipantId(userId))
          .where((id) => id != null && id.isNotEmpty)
          .cast<String>()
          .toSet() // Unique
          .toList();

      if (potentialIds.isEmpty) return [];

      // Fetch profiles
      final profilesFutures = potentialIds.map(
        (id) => _profileRepo.getUserProfile(id),
      );
      final profiles = await Future.wait(profilesFutures);

      // Filter by Verification (and remove nulls)
      final verifiedProfiles = <ProfileData>[];
      for (final p in profiles) {
        if (p == null || p.uid == null) continue;

        final trust = await _trustRepo.getTrustData(p.uid!);
        if (trust != null && trust.isVerified) {
          verifiedProfiles.add(p);
        }
      }

      return verifiedProfiles;
    } catch (e) {
      return [];
    }
  }

  // Step 1: Request Proxy
  Future<void> requestProxyAndJoin({
    required String userId,
    required String country,
    required String proxyUserId,
    required List<String> coveredFamilyMembers,
  }) async {
    final membership = EmergencyFundMembership(
      userId: userId,
      country: country,
      status: MembershipStatus.pending_proxy,
      joinedDate: DateTime.now(),
      annualContribution: 100.0, // Fixed: Standardized to $100
      supportNumber: 'DN-EMG-${_uuid.v4().substring(0, 8).toUpperCase()}',
      proxyUserId: proxyUserId,
      proxyStatus: ProxyStatus.pending,
      coveredFamilyMembers: coveredFamilyMembers,
    );

    await _firestore
        .collection('emergency_fund_memberships')
        .doc(userId)
        .set(membership.toMap());

    // Logic to notify proxy would go here
  }

  // Step 2: Proxy Accepts (Called by Proxy User)
  Future<void> acceptProxyRequest(
    String memberUserId,
    String proxyUserId,
  ) async {
    // Logic to validate proxy user would go here

    await _firestore
        .collection('emergency_fund_memberships')
        .doc(memberUserId)
        .update({
          'proxyStatus': ProxyStatus.accepted.name,
          'status': MembershipStatus.pending_payment.name,
        });
  }

  // Step 3: Process Payment
  // [NOTE] Currently auto-approves as Free Beta Access.
  // [TODO] Integrate Stripe/M-Pesa payment gateway for production.
  Future<void> completeMembershipPayment(String userId) async {
    await _firestore
        .collection('emergency_fund_memberships')
        .doc(userId)
        .update({
          'status': MembershipStatus.active.name,
          'nextPaymentDate': Timestamp.fromDate(
            DateTime.now().add(const Duration(days: 365)),
          ),
        });
  }

  // Update proxy designation — creates a request that the proxy must accept
  Future<void> updateProxy({
    required String userId,
    required String userName,
    required String proxyUserId,
  }) async {
    // 1. Save proxy as pending on the membership doc
    await _firestore
        .collection('emergency_fund_memberships')
        .doc(userId)
        .set({
          'proxyUserId': proxyUserId,
          'proxyStatus': ProxyStatus.pending.name,
        }, SetOptions(merge: true));

    // 2. Write a proxy_requests doc so the proxy user gets notified
    final requestId = '${userId}_$proxyUserId';
    await _firestore
        .collection('proxy_requests')
        .doc(requestId)
        .set({
          'fromUserId': userId,
          'fromUserName': userName,
          'toUserId': proxyUserId,
          'status': 'pending',
          'createdAt': FieldValue.serverTimestamp(),
        });

    debugPrint('✅ [EmergencyFund] Proxy request created: $requestId');
  }

  // Proxy user responds to the request (accept or reject)
  Future<void> respondToProxyRequest({
    required String requestId,
    required String fromUserId,
    required bool accepted,
  }) async {
    final newStatus = accepted ? 'accepted' : 'rejected';

    // 1. Update the proxy_requests doc
    await _firestore
        .collection('proxy_requests')
        .doc(requestId)
        .update({
          'status': newStatus,
          'respondedAt': FieldValue.serverTimestamp(),
        });

    // 2. Update the membership doc
    final proxyStatus = accepted ? ProxyStatus.accepted : ProxyStatus.rejected;
    final updateData = <String, dynamic>{
      'proxyStatus': proxyStatus.name,
    };
    if (!accepted) {
      updateData['proxyUserId'] = null;
    }
    await _firestore
        .collection('emergency_fund_memberships')
        .doc(fromUserId)
        .set(updateData, SetOptions(merge: true));

    debugPrint('✅ [EmergencyFund] Proxy request $requestId $newStatus');
  }

  // Stream pending proxy requests for a given user (they are the proxy)
  Stream<QuerySnapshot> streamPendingProxyRequests(String proxyUserId) {
    return _firestore
        .collection('proxy_requests')
        .where('toUserId', isEqualTo: proxyUserId)
        .where('status', isEqualTo: 'pending')
        .snapshots();
  }

  // --- Claims ---

  Stream<List<EmergencyFundClaim>> streamUserClaims(String userId) {
    return _firestore
        .collection('emergency_fund_claims')
        .where('userId', isEqualTo: userId)
        .orderBy('submittedDate', descending: true)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs
              .map((doc) => EmergencyFundClaim.fromMap(doc.data()))
              .toList();
        });
  }

  Future<void> submitClaim({
    required String userId,
    required EmergencyType type,
    required String beneficiaryName,
    required String relationship,
    required DateTime incidentDate,
    required String description,
  }) async {
    final claimId = _uuid.v4();
    final claim = EmergencyFundClaim(
      id: claimId,
      userId: userId,
      type: type,
      beneficiaryName: beneficiaryName,
      relationship: relationship,
      incidentDate: incidentDate,
      status: ClaimStatus.submitted,
      submittedDate: DateTime.now(),
      description: description,
    );

    await _firestore
        .collection('emergency_fund_claims')
        .doc(claimId)
        .set(claim.toMap());
  }

  // --- Helpers ---
  Future<ProfileData?> getUserProfile(String uid) =>
      _profileRepo.getUserProfile(uid);
}
